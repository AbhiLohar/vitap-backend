import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../services/api_service.dart';
import '../services/captcha_solver.dart';
import '../services/error_formatter.dart';
import '../config/app_theme.dart';

class VtopWebViewScreen extends StatefulWidget {
  final String username;
  
  const VtopWebViewScreen({super.key, required this.username});

  @override
  State<VtopWebViewScreen> createState() => _VtopWebViewScreenState();
}

class _VtopWebViewScreenState extends State<VtopWebViewScreen> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  bool _isInit = true;
  String? _csrfToken;
  String _currentUrl = '';
  String _statusMessage = 'Initializing...';

  @override
  void initState() {
    super.initState();
    ApiService.suppressOtpDialog = true;
    _initNativeLoginAndLoad();
  }

  @override
  void dispose() {
    ApiService.suppressOtpDialog = false;
    super.dispose();
  }

  void _updateStatus(String msg) {
    if (mounted) {
      setState(() { _statusMessage = msg; });
    }
    debugPrint('VTOP WebView: $msg');
  }

  Future<void> _initNativeLoginAndLoad() async {
    setState(() {
      _isLoading = true;
      _isInit = true;
    });

    try {
      final storage = const FlutterSecureStorage();
      final password = await storage.read(key: 'password') ?? '';

      if (password.isEmpty) {
        throw Exception("Password not found in secure storage");
      }

      final cookieManager = CookieManager.instance();

      final ioc = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      final client = IOClient(ioc);

      const userAgent = 'Mozilla/5.0 (Linux; Android 14; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';

      const int maxRetries = 10;
      bool loginSuccess = false;
      String jsessionId = '';

      // Initialize captcha solver once
      final captchaSolver = CaptchaSolver();
      await captchaSolver.initialize();
      _updateStatus('Captcha solver ready');

      for (int attempt = 0; attempt < maxRetries; attempt++) {
        _updateStatus('Login attempt ${attempt + 1}/$maxRetries');
        
        await cookieManager.deleteAllCookies();

        // ── Step 1: GET /vtop/open/page — Establish session cookies + get initial CSRF ──
        _updateStatus('Establishing session...');
        http.Response resp;
        try {
          resp = await client.get(
            Uri.parse('https://vtop.vitap.ac.in/vtop/open/page'),
            headers: {'User-Agent': userAgent},
          );
        } catch (e) {
          debugPrint('Failed to reach VTOP: $e');
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }

        // Extract JSESSIONID from set-cookie
        String setCookie = resp.headers['set-cookie'] ?? '';
        if (setCookie.contains('JSESSIONID=')) {
          jsessionId = setCookie.split('JSESSIONID=')[1].split(';')[0];
        }

        // Extract CSRF from the open page
        final csrfRegex = RegExp(r'name="_csrf"\s+(?:content|value)="([^"]+)"');
        final csrfMatch = csrfRegex.firstMatch(resp.body);
        if (csrfMatch != null) {
          _csrfToken = csrfMatch.group(1);
        }
        // Also try input field
        if (_csrfToken == null) {
          final csrfRegex2 = RegExp(r'name="_csrf"\s+value="([^"]+)"');
          final csrfMatch2 = csrfRegex2.firstMatch(resp.body);
          if (csrfMatch2 != null) {
            _csrfToken = csrfMatch2.group(1);
          }
        }

        if (jsessionId.isEmpty || _csrfToken == null) {
          debugPrint('Missing JSESSIONID or CSRF from open/page. Retrying...');
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
        debugPrint('Got session: JSESSIONID=${jsessionId.substring(0, 8)}..., CSRF=${_csrfToken!.substring(0, 8)}...');

        // ── Step 2: POST /vtop/prelogin/setup — Tell VTOP we want image captcha ──
        _updateStatus('Setting up login...');
        http.Response preloginResp;
        try {
          preloginResp = await client.post(
            Uri.parse('https://vtop.vitap.ac.in/vtop/prelogin/setup'),
            headers: {
              'User-Agent': userAgent,
              'Cookie': 'JSESSIONID=$jsessionId',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: '_csrf=${Uri.encodeComponent(_csrfToken!)}&flag=VTOP',
            encoding: Encoding.getByName('utf-8'),
          );
        } catch (e) {
          debugPrint('Prelogin failed: $e');
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }

        // The prelogin response may contain the captcha directly, or we may need to fetch it
        String captchaB64 = '';
        final imgRegex = RegExp(r'src="(data:image/[^;]+;base64,[^"]+)"');
        final imgMatch = imgRegex.firstMatch(preloginResp.body);
        if (imgMatch != null) {
          captchaB64 = imgMatch.group(1)!;
          debugPrint('Got captcha from prelogin response directly');
        }

        // Update CSRF from prelogin response if available
        final preloginCsrf = csrfRegex.firstMatch(preloginResp.body);
        if (preloginCsrf != null) {
          _csrfToken = preloginCsrf.group(1);
        }

        // Check for captchaType — if it's 2 (reCAPTCHA), we need to retry
        final captchaTypeRegex = RegExp(r'var\s+captchaType\s*=\s*(\d+)');
        final captchaTypeMatch = captchaTypeRegex.firstMatch(preloginResp.body);
        if (captchaTypeMatch != null && captchaTypeMatch.group(1) == '2') {
          debugPrint('VTOP requested Google reCAPTCHA. Refreshing session...');
          await Future.delayed(const Duration(milliseconds: 300));
          continue;
        }

        // ── Step 3: If captcha not in prelogin response, fetch from /vtop/get/new/captcha ──
        if (captchaB64.isEmpty) {
          _updateStatus('Fetching captcha...');
          try {
            // First try GET /vtop/login to get the login page with captcha
            final loginPageResp = await client.get(
              Uri.parse('https://vtop.vitap.ac.in/vtop/login'),
              headers: {
                'User-Agent': userAgent,
                'Cookie': 'JSESSIONID=$jsessionId',
              },
            );

            // Update CSRF from login page
            final loginCsrf = csrfRegex.firstMatch(loginPageResp.body);
            if (loginCsrf != null) {
              _csrfToken = loginCsrf.group(1);
            }

            // Check for reCAPTCHA again
            final loginCaptchaType = captchaTypeRegex.firstMatch(loginPageResp.body);
            if (loginCaptchaType != null && loginCaptchaType.group(1) == '2') {
              debugPrint('Login page has reCAPTCHA. Refreshing session...');
              await Future.delayed(const Duration(milliseconds: 300));
              continue;
            }

            // Fetch captcha via AJAX endpoint
            final captchaResp = await client.get(
              Uri.parse('https://vtop.vitap.ac.in/vtop/get/new/captcha'),
              headers: {
                'User-Agent': userAgent,
                'Cookie': 'JSESSIONID=$jsessionId',
              },
            );

            final captchaImgMatch = imgRegex.firstMatch(captchaResp.body);
            if (captchaImgMatch != null) {
              captchaB64 = captchaImgMatch.group(1)!;
            }
          } catch (e) {
            debugPrint('Failed to fetch captcha: $e');
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }
        }

        if (captchaB64.isEmpty) {
          debugPrint('No captcha image found. Retrying...');
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }

        // ── Step 4: Solve CAPTCHA locally ──
        _updateStatus('Solving captcha...');
        String solvedCaptcha = '';
        try {
          solvedCaptcha = await captchaSolver.predict(captchaB64);
        } catch (e) {
          debugPrint('Local ML failed to solve CAPTCHA: $e');
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }

        if (solvedCaptcha.length != 6) {
          debugPrint('Invalid CAPTCHA solve length: ${solvedCaptcha.length}. Retrying...');
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
        debugPrint('Captcha solved: $solvedCaptcha');

        // ── Step 5: Submit Login POST ──
        _updateStatus('Submitting credentials...');
        http.Response submitResp;
        try {
          submitResp = await client.post(
            Uri.parse('https://vtop.vitap.ac.in/vtop/login'),
            headers: {
              'User-Agent': userAgent,
              'Cookie': 'JSESSIONID=$jsessionId',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {
              '_csrf': _csrfToken!,
              'username': widget.username.toUpperCase(),
              'password': password,
              'captchaStr': solvedCaptcha,
              'gResponse': '',
            },
          );
        } catch (e) {
          debugPrint('Login POST failed: $e');
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }

        String bodyLower = submitResp.body.toLowerCase();

        // ── Step 6: Check login result ──
        
        // 404 / Tomcat error — session corrupted
        if (submitResp.statusCode == 404 || bodyLower.contains("apache tomcat") || bodyLower.contains("http status 404")) {
          debugPrint('VTOP returned 404 (session expired). Re-initializing...');
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }

        // Invalid captcha — just retry
        if (bodyLower.contains("invalid captcha")) {
          debugPrint('Invalid Captcha. Retrying...');
          await Future.delayed(const Duration(milliseconds: 300));
          continue;
        }

        // Bad credentials — fatal, stop trying
        if (bodyLower.contains("invalid credentials") || 
            bodyLower.contains("user id not available") ||
            bodyLower.contains("invalid loginid/password") ||
            bodyLower.contains("invalid  username/password")) {
          throw Exception("Invalid username or password.");
        }

        // OTP required — that's still a successful login!
        if (bodyLower.contains("otp") && (bodyLower.contains("sent") || bodyLower.contains("verify"))) {
          debugPrint('Login success — OTP required');
          loginSuccess = true;
          // Update CSRF from OTP page
          final otpCsrf = csrfRegex.firstMatch(submitResp.body);
          if (otpCsrf != null) {
            _csrfToken = otpCsrf.group(1);
          }
          break;
        }

        // If we reach here, VTOP accepted the login!
        debugPrint('Login successful!');
        loginSuccess = true;
        
        // Update CSRF from post-login page
        final postCsrf = csrfRegex.firstMatch(submitResp.body);
        if (postCsrf != null) {
          _csrfToken = postCsrf.group(1);
        }
        break;
      }

      if (!loginSuccess) {
         throw Exception("VTOP is repeatedly rejecting the login due to CAPTCHA issues. Please try again later.");
      }

      // ── Step 7: Inject authenticated JSESSIONID into WebView ──
      _updateStatus('Injecting session into WebView...');
      await cookieManager.setCookie(
        url: WebUri("https://vtop.vitap.ac.in/vtop/"),
        name: 'JSESSIONID',
        value: jsessionId,
        domain: 'vtop.vitap.ac.in',
        path: '/',
      );

    } catch (e) {
      debugPrint('Native Login Flow Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ErrorFormatter.format(e))));
      }
    } finally {
      if (mounted) {
        setState(() { _isInit = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Build the auto-submit HTML form that POSTs to /vtop/content
    // This avoids loading any VTOP page (which would overwrite our JSESSIONID)
    final String autoSubmitHtml = _csrfToken != null ? '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
<body>
<p style="text-align:center;margin-top:40%;font-family:sans-serif;color:#666;">Loading VTOP Dashboard...</p>
<form id="autoForm" method="POST" action="https://vtop.vitap.ac.in/vtop/content">
  <input type="hidden" name="_csrf" value="$_csrfToken">
  <input type="hidden" name="verifyMenu" value="true">
</form>
<script>document.getElementById('autoForm').submit();</script>
</body>
</html>
''' : '''
<!DOCTYPE html>
<html>
<body>
<p style="text-align:center;margin-top:40%;font-family:sans-serif;color:#666;">Login failed. Please go back and try again.</p>
</body>
</html>
''';

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text('VTOP Portal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_controller != null && _csrfToken != null) {
                // Re-navigate to dashboard on refresh
                _controller!.loadData(
                  data: autoSubmitHtml,
                  baseUrl: WebUri('https://vtop.vitap.ac.in/vtop/'),
                  mimeType: 'text/html',
                  encoding: 'utf-8',
                );
              }
            },
          ),
        ],
      ),
      body: _isInit 
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(_statusMessage, style: const TextStyle(fontSize: 14)),
              ],
            ),
          )
        : Column(
            children: [
              if (_isLoading) const LinearProgressIndicator(),
              Expanded(
                child: InAppWebView(
                  // Load a local HTML page that auto-submits the POST form
                  // The baseUrl ensures cookies are scoped to vtop.vitap.ac.in
                  initialData: InAppWebViewInitialData(
                    data: autoSubmitHtml,
                    baseUrl: WebUri('https://vtop.vitap.ac.in/vtop/'),
                    mimeType: 'text/html',
                    encoding: 'utf-8',
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    userAgent: 'Mozilla/5.0 (Linux; Android 14; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36',
                  ),
                  onWebViewCreated: (controller) {
                    _controller = controller;
                  },
                  onLoadStart: (controller, url) {
                    setState(() { 
                      _isLoading = true; 
                      _currentUrl = url?.toString() ?? '';
                    });
                  },
                  onLoadStop: (controller, url) async {
                    setState(() { 
                      _isLoading = false; 
                      _currentUrl = url?.toString() ?? '';
                    });
                    debugPrint('WebView loaded: $_currentUrl');
                  },
                  onReceivedError: (controller, request, error) {
                    debugPrint('WebView Error for ${request.url}: ${error.description}');
                  },
                  onReceivedServerTrustAuthRequest: (controller, challenge) async {
                    return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);
                  },
                ),
              ),
            ],
          ),
    );
  }
}
