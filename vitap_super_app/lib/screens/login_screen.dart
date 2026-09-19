import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../services/error_formatter.dart';
import '../widgets/running_login_button.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final regController = TextEditingController();
  final passController = TextEditingController();
  final FocusNode regFocus = FocusNode();
  final FocusNode passFocus = FocusNode();
  final RunningLoginButtonController _loginBtnController =
      RunningLoginButtonController();

  bool isLoading = false;
  String loadingStatus = "Connecting to VTOP...";
  bool obscurePassword = true;
  String? errorMessage;

  // Mascot animation state
  double _lookProgress = 0.0; // 0.0 (left) to 1.0 (right)
  bool _isLookingDown = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late AnimationController _orbController;
  late AnimationController _pawController;
  late AnimationController _peekController;
  late AnimationController _blinkController;
  late AnimationController _shakeController;

  Timer? _blinkTimer;

  // Loading status messages
  final _statusMessages = [
    "Connecting to VTOP...",
    "Verifying credentials...",
    "Loading your data...",
    "Almost there...",
  ];
  int _statusIndex = 0;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();

    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    // Paws covering eyes animation
    _pawController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    // Peeking with one eye animation
    _peekController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    // Blinking animation
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    // Error shake animation
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _startBlinkTimer();

    // Focus listeners for mascot interaction
    regFocus.addListener(_onFocusChange);
    passFocus.addListener(_onFocusChange);

    regController.addListener(_onRegTextChange);

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAutoLogin());
  }

  void _startBlinkTimer() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 3200), (timer) {
      if (!mounted) return;
      if (!passFocus.hasFocus) {
        _blinkController.forward().then((_) {
          if (mounted) _blinkController.reverse();
        });
      }
    });
  }

  void _onFocusChange() {
    setState(() {
      if (passFocus.hasFocus) {
        _isLookingDown = false;
        if (obscurePassword) {
          _pawController.forward();
          _peekController.reverse();
        } else {
          _pawController.forward();
          _peekController.forward();
        }
      } else {
        _pawController.reverse();
        _peekController.reverse();
        _isLookingDown = regFocus.hasFocus;
      }
    });
  }

  void _onRegTextChange() {
    if (regFocus.hasFocus) {
      setState(() {
        // Map 0 to ~15 characters to 0.0 -> 1.0 progress
        final len = regController.text.length;
        _lookProgress = (len / 14.0).clamp(0.0, 1.0);
        _isLookingDown = true;
      });
    }
  }

  void _toggleObscure() {
    setState(() {
      obscurePassword = !obscurePassword;
      if (passFocus.hasFocus) {
        if (obscurePassword) {
          _peekController.reverse();
        } else {
          _peekController.forward();
        }
      }
    });
  }

  Future<void> _checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    const storage = FlutterSecureStorage();
    final savedUser = prefs.getString('username');
    final savedPass = await storage.read(key: 'password');

    if (savedUser != null && savedPass != null) {
      final biometricEnabled = prefs.getBool('biometricEnabled') ?? false;
      if (biometricEnabled) {
        final authenticated = await _authenticateBiometric();
        if (!authenticated) return;
      }

      setState(() {
        regController.text = savedUser;
        passController.text = savedPass;
      });

      final savedSem = prefs.getString('semesterId');
      if (savedSem != null && savedSem.isNotEmpty) {
        navigateToMain();
        return;
      }

      final isAlive = await ApiService.checkSession(savedUser);
      if (isAlive) {
        fetchSemestersAndNavigate();
      } else {
        submitLogin();
      }
    }
  }

  Future<bool> _authenticateBiometric() async {
    final LocalAuthentication auth = LocalAuthentication();
    try {
      final canCheck = await auth.canCheckBiometrics;
      final isDeviceSupported = await auth.isDeviceSupported();
      if (!canCheck || !isDeviceSupported) return true;

      final authenticated = await auth.authenticate(
        localizedReason: 'Authenticate to access VTOP',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      return authenticated;
    } catch (e) {
      return true;
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    regController.removeListener(_onRegTextChange);
    regFocus.removeListener(_onFocusChange);
    passFocus.removeListener(_onFocusChange);
    regController.dispose();
    passController.dispose();
    regFocus.dispose();
    passFocus.dispose();
    _loginBtnController.dispose();
    _animController.dispose();
    _orbController.dispose();
    _pawController.dispose();
    _peekController.dispose();
    _blinkController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _startStatusCycler() {
    _statusIndex = 0;
    _cycleStatus();
  }

  void _cycleStatus() async {
    while (isLoading && mounted) {
      await Future.delayed(const Duration(seconds: 3));
      if (!isLoading || !mounted) break;
      _statusIndex = (_statusIndex + 1) % _statusMessages.length;
      final msg = _statusMessages[_statusIndex];
      setState(() => loadingStatus = msg);
      if (_loginBtnController.status == LoginButtonStatus.running) {
        _loginBtnController.updateMessage(msg);
      }
    }
  }

  void submitLogin() async {
    final username = regController.text.trim();
    final password = passController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _triggerError("Enter Login ID and password");
      return;
    }

    // Unfocus all fields when submitting - mascot uncovers eyes and watches
    regFocus.unfocus();
    passFocus.unfocus();

    setState(() {
      isLoading = true;
      errorMessage = null;
      loadingStatus = _statusMessages[0];
    });
    _loginBtnController.startRunning(message: _statusMessages[0]);
    _startStatusCycler();

    try {
      final startTime = DateTime.now();
      final data = await ApiService.login(
        username: username,
        password: password,
      );

      // Ensure minimum running duration of 1.2s so the user can enjoy the animated sequence
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsed < 1200) {
        await Future.delayed(Duration(milliseconds: 1200 - elapsed));
      }

      if (!mounted) return;

      final status = data["status"];

      if (status == "otp_required") {
        _loginBtnController.enterRoom(onComplete: () {
          if (mounted) {
            setState(() => isLoading = false);
            _loginBtnController.reset();
            showOtpSheet();
          }
        });
        return;
      } else if (status == "success") {
        final prefs = await SharedPreferences.getInstance();
        const storage = FlutterSecureStorage();
        await prefs.setString('username', username);
        await storage.write(key: 'password', value: password);

        // Keep running in backend while fetching semesters
        _loginBtnController.updateMessage("Loading your data...");
        fetchSemestersAndNavigate();
        return;
      } else if (status == "invalid_credentials") {
        _loginBtnController.fail();
        _triggerError(data["detail"] ?? "Invalid Username or Password. Please check your credentials and try again.");
        return;
      } else {
        _loginBtnController.fail();
        _triggerError(data["detail"] ?? "Login failed. Please check your credentials and try again.");
      }
    } catch (e) {
      if (!mounted) return;
      _loginBtnController.fail();
      _triggerError(ErrorFormatter.format(e));
    }
  }

  void _triggerError(String msg) {
    setState(() {
      errorMessage = msg;
      isLoading = false;
    });
    _shakeController.forward(from: 0.0);
  }

  Future<void> fetchSemestersAndNavigate() async {
    setState(() {
      isLoading = true;
      loadingStatus = "Fetching semesters...";
    });
    if (_loginBtnController.status == LoginButtonStatus.idle) {
      _loginBtnController.startRunning(message: "Loading your data...");
    } else {
      _loginBtnController.updateMessage("Loading your data...");
    }

    try {
      final username = regController.text.trim();
      final prefs = await SharedPreferences.getInstance();
      final savedSem = prefs.getString('semesterId');
      if (savedSem != null && savedSem.isNotEmpty) {
        _preWarmDataInBackground(username, savedSem);
        if (mounted) {
          _loginBtnController.enterRoom(onComplete: () {
            if (mounted) {
              setState(() => isLoading = false);
              _loginBtnController.reset();
              navigateToMain();
            }
          });
        }
        return;
      }

      final semesters = await ApiService.getSemesters(username);

      if (!mounted) return;

      if (semesters.isEmpty) {
        setState(() => isLoading = false);
        _loginBtnController.fail();
        _triggerError("No semesters found. Session may have expired.");
        return;
      }

      // Load is done! Man enters the room, and THEN the semester sheet pops up!
      _loginBtnController.enterRoom(onComplete: () {
        if (mounted) {
          setState(() => isLoading = false);
          _loginBtnController.reset();
          showSemesterSheet(semesters);
        }
      });
    } catch (e) {
      if (mounted) {
        _loginBtnController.fail();
        _triggerError(ErrorFormatter.format(e));
      }
    }
  }

  void _preWarmDataInBackground(String username, String semesterId) {
    ApiService.preloadAllData(username, semesterId: semesterId).then((_) {
      print("Background pre-warm completed for $username");
    }).catchError((e) {
      print("Background pre-warm error (non-fatal): $e");
    });
  }

  void showSemesterSheet(List semesters) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.cardBg(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "Select Semester",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Choose your active semester to proceed",
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 300,
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: semesters.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final sem = semesters[index];
                    return InkWell(
                      onTap: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('semesterId', sem['id']);
                        await prefs.setString('semesterName', sem['name']);
                        if (mounted) {
                          Navigator.pop(ctx);
                          _preWarmDataInBackground(
                            regController.text.trim(),
                            sem['id'],
                          );
                          navigateToMain();
                        }
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.scaffoldBg(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.cardBorder(context),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                sem['name'],
                                style: TextStyle(
                                  color: AppColors.textPrimary(context),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: AppColors.textMuted(context),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void navigateToMain() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            MainScreen(username: regController.text.trim()),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void showOtpSheet() {
    final otpController = TextEditingController();
    bool otpLoading = false;
    String? otpError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.cardBg(context),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.cardBorder(context)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withValues(alpha: 0.15),
                                AppColors.accent.withValues(alpha: 0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.lock_outline,
                            color: AppColors.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Enter OTP",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Sent to your registered email/phone",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        fontSize: 20,
                        letterSpacing: 8,
                        color: AppColors.textPrimary(context),
                      ),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: "• • • • • •",
                        hintStyle: TextStyle(
                          color: AppColors.textMuted(context),
                          letterSpacing: 8,
                        ),
                        filled: true,
                        fillColor: AppColors.scaffoldBg(context),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: AppColors.cardBorder(context),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: AppColors.cardBorder(context),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    if (otpError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        otpError!,
                        style: const TextStyle(
                          color: AppColors.red,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: otpLoading
                            ? null
                            : () async {
                                if (otpController.text.trim().isEmpty) {
                                  setSheetState(
                                    () => otpError = "Enter the OTP",
                                  );
                                  return;
                                }
                                setSheetState(() {
                                  otpLoading = true;
                                  otpError = null;
                                });
                                try {
                                  final data = await ApiService.verifyOtp(
                                    username: regController.text.trim(),
                                    otp: otpController.text.trim(),
                                  );
                                  if (data["status"] == "success") {
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    const storage = FlutterSecureStorage();
                                    await prefs.setString(
                                      'username',
                                      regController.text.trim(),
                                    );
                                    await storage.write(
                                      key: 'password',
                                      value: passController.text.trim(),
                                    );
                                    if (context.mounted) {
                                      Navigator.pop(ctx);
                                      fetchSemestersAndNavigate();
                                    }
                                  } else {
                                    setSheetState(() {
                                      otpError =
                                          data["detail"] ?? "Invalid OTP";
                                      otpLoading = false;
                                    });
                                  }
                                } catch (e) {
                                  setSheetState(() {
                                    otpError = ErrorFormatter.format(e);
                                    otpLoading = false;
                                  });
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: otpLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                "Verify OTP",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: otpLoading
                          ? null
                          : () async {
                              setSheetState(() {
                                otpLoading = true;
                                otpError = null;
                              });
                              try {
                                final data = await ApiService.resendOtp(
                                  username: regController.text.trim(),
                                );
                                if (data["status"] == "success") {
                                  setSheetState(() {
                                    otpLoading = false;
                                    otpError = null;
                                  });
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "OTP resent to your registered email",
                                        ),
                                      ),
                                    );
                                  }
                                } else {
                                  setSheetState(() {
                                    otpLoading = false;
                                    otpError =
                                        data["detail"] ??
                                        "Failed to resend OTP. Try logging in again.";
                                  });
                                }
                              } catch (e) {
                                setSheetState(() {
                                  otpLoading = false;
                                  otpError =
                                      "Connection error. Please check your internet.";
                                });
                              }
                            },
                      icon: const Icon(
                        Icons.refresh,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      label: const Text(
                        "Resend OTP",
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E1A),
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF070A14),
                  Color(0xFF0F1B3D),
                  Color(0xFF080C1A),
                ],
              ),
            ),
          ),

          // Animated background glowing ambient orbs
          AnimatedBuilder(
            animation: _orbController,
            builder: (context, child) {
              return CustomPaint(
                size: MediaQuery.of(context).size,
                painter: _OrbPainter(_orbController.value),
              );
            },
          ),

          // Main Interactive Content
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 10),

                      // Header Titles
                      Text(
                        "Welcome Back 👋",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary(context),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Sign in with your VTOP Student Credentials",
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 28),

                      // Mascot Container (Husky character directly above login card)
                      SizedBox(
                        height: 145,
                        width: 175,
                        child: AnimatedBuilder(
                          animation: Listenable.merge([
                            _pawController,
                            _peekController,
                            _blinkController,
                          ]),
                          builder: (context, child) {
                            return CustomPaint(
                              painter: _HuskyPainter(
                                lookProgress: _lookProgress,
                                isLookingDown: _isLookingDown,
                                pawProgress: _pawController.value,
                                peekProgress: _peekController.value,
                                blinkProgress: _blinkController.value,
                              ),
                            );
                          },
                        ),
                      ),

                      // Error Shake Animation Wrapper
                      AnimatedBuilder(
                        animation: _shakeController,
                        builder: (context, child) {
                          final offset = sin(_shakeController.value * pi * 4) * 8 * (1 - _shakeController.value);
                          return Transform.translate(
                            offset: Offset(offset, 0),
                            child: child,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF131B2E).withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: const Color(0xFF283556),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 28,
                                offset: const Offset(0, 12),
                              ),
                              BoxShadow(
                                color: const Color(0xFF7C4DFF).withValues(alpha: 0.08),
                                blurRadius: 40,
                                spreadRadius: -5,
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Username / Registration Number
                              _buildModernTextField(
                                controller: regController,
                                focusNode: regFocus,
                                label: "Registration No. / Login ID",
                                hint: "e.g. 23BCE1000",
                                icon: Icons.person_outline_rounded,
                                isUppercase: true,
                              ),

                              const SizedBox(height: 18),

                              // Password Field
                              _buildModernTextField(
                                controller: passController,
                                focusNode: passFocus,
                                label: "Password",
                                hint: "Enter your password",
                                icon: Icons.lock_outline_rounded,
                                isPassword: true,
                                obscure: obscurePassword,
                                onToggleObscure: _toggleObscure,
                              ),

                              // Inline Error Message Banner
                              if (errorMessage != null) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.red.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.red.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: AppColors.red,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          errorMessage!,
                                          style: const TextStyle(
                                            color: AppColors.red,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 24),

                              // Interactive Running Login Button (Runner enters room through door)
                              RunningLoginButton(
                                controller: _loginBtnController,
                                onPressed: isLoading ? () {} : submitLogin,
                                label: "Sign In",
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Safe badge note
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 15,
                            color: AppColors.textMuted(context),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "End-to-End Secure VTOP Session",
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted(context),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    bool isUppercase = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFFB0BEC5),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0B1120),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focusNode.hasFocus
                  ? const Color(0xFF7C4DFF)
                  : const Color(0xFF1E293B),
              width: focusNode.hasFocus ? 1.6 : 1.0,
            ),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: isPassword ? obscure : false,
            textCapitalization: isUppercase
                ? TextCapitalization.characters
                : TextCapitalization.none,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 14,
              ),
              prefixIcon: Icon(
                icon,
                size: 20,
                color: focusNode.hasFocus
                    ? const Color(0xFF7C4DFF)
                    : const Color(0xFF64748B),
              ),
              suffixIcon: isPassword
                  ? IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: const Color(0xFF64748B),
                        size: 20,
                      ),
                      onPressed: onToggleObscure,
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dynamic Animated Husky Mascot Painter
class _HuskyPainter extends CustomPainter {
  final double lookProgress; // 0.0 (left) to 1.0 (right)
  final bool isLookingDown;
  final double pawProgress; // 0.0 (idle down) to 1.0 (covering eyes)
  final double peekProgress; // 0.0 (covering) to 1.0 (peeking with one eye)
  final double blinkProgress; // 0.0 (open) to 1.0 (closed)

  _HuskyPainter({
    required this.lookProgress,
    required this.isLookingDown,
    required this.pawProgress,
    required this.peekProgress,
    required this.blinkProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 10;

    final paint = Paint()..isAntiAlias = true;

    // Head tilt offset based on horizontal look
    final tiltX = (lookProgress - 0.5) * 8.0;
    final tiltY = isLookingDown ? 5.0 : 0.0;

    // ── 1. Husky Pointy Ears ────────────────────────────────────────────────
    final leftEarPath = Path()
      ..moveTo(cx - 52 + tiltX, cy - 25 + tiltY)
      ..lineTo(cx - 68 + tiltX, cy - 70 + tiltY)
      ..quadraticBezierTo(cx - 45 + tiltX, cy - 78 + tiltY, cx - 24 + tiltX, cy - 40 + tiltY)
      ..close();
    paint.color = const Color(0xFF2C3E50);
    canvas.drawPath(leftEarPath, paint);

    // Inner left ear (pink/peach)
    final leftInnerEar = Path()
      ..moveTo(cx - 48 + tiltX, cy - 30 + tiltY)
      ..lineTo(cx - 62 + tiltX, cy - 64 + tiltY)
      ..quadraticBezierTo(cx - 44 + tiltX, cy - 70 + tiltY, cx - 30 + tiltX, cy - 42 + tiltY)
      ..close();
    paint.color = const Color(0xFFFFAB91);
    canvas.drawPath(leftInnerEar, paint);

    final rightEarPath = Path()
      ..moveTo(cx + 52 + tiltX, cy - 25 + tiltY)
      ..lineTo(cx + 68 + tiltX, cy - 70 + tiltY)
      ..quadraticBezierTo(cx + 45 + tiltX, cy - 78 + tiltY, cx + 24 + tiltX, cy - 40 + tiltY)
      ..close();
    paint.color = const Color(0xFF2C3E50);
    canvas.drawPath(rightEarPath, paint);

    // Inner right ear (pink/peach)
    final rightInnerEar = Path()
      ..moveTo(cx + 48 + tiltX, cy - 30 + tiltY)
      ..lineTo(cx + 62 + tiltX, cy - 64 + tiltY)
      ..quadraticBezierTo(cx + 44 + tiltX, cy - 70 + tiltY, cx + 30 + tiltX, cy - 42 + tiltY)
      ..close();
    paint.color = const Color(0xFFFFAB91);
    canvas.drawPath(rightInnerEar, paint);

    // ── 2. Husky Head Base (Dark Coat) ──────────────────────────────────────
    paint.color = const Color(0xFF2C3E50);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx + tiltX, cy + tiltY), width: 110, height: 96),
        const Radius.circular(48),
      ),
      paint,
    );

    // ── 3. White Face Mask ──────────────────────────────────────────────────
    final maskPath = Path()
      ..moveTo(cx - 42 + tiltX, cy + 2 + tiltY)
      ..quadraticBezierTo(cx - 46 + tiltX, cy - 24 + tiltY, cx - 22 + tiltX, cy - 32 + tiltY)
      ..quadraticBezierTo(cx + tiltX, cy - 14 + tiltY, cx + 22 + tiltX, cy - 32 + tiltY)
      ..quadraticBezierTo(cx + 46 + tiltX, cy - 24 + tiltY, cx + 42 + tiltX, cy + 2 + tiltY)
      ..quadraticBezierTo(cx + 36 + tiltX, cy + 42 + tiltY, cx + tiltX, cy + 45 + tiltY)
      ..quadraticBezierTo(cx - 36 + tiltX, cy + 42 + tiltY, cx - 42 + tiltX, cy + 2 + tiltY)
      ..close();
    paint.color = const Color(0xFFF8FAFC);
    canvas.drawPath(maskPath, paint);

    // ── 4. Forehead Husky Blaze ─────────────────────────────────────────────
    final blazePath = Path()
      ..moveTo(cx - 10 + tiltX, cy - 46 + tiltY)
      ..quadraticBezierTo(cx + tiltX, cy - 48 + tiltY, cx + 10 + tiltX, cy - 46 + tiltY)
      ..lineTo(cx + 5 + tiltX, cy - 28 + tiltY)
      ..lineTo(cx - 5 + tiltX, cy - 28 + tiltY)
      ..close();
    paint.color = const Color(0xFFF8FAFC);
    canvas.drawPath(blazePath, paint);

    // ── 5. Eyes & Pupils (with Tracking & Blinking) ──────────────────────────
    final leftEyeCenter = Offset(cx - 20 + tiltX, cy - 6 + tiltY);
    final rightEyeCenter = Offset(cx + 20 + tiltX, cy - 6 + tiltY);

    // Eye whites
    paint.color = Colors.white;
    final eyeHeightFactor = (1.0 - blinkProgress).clamp(0.08, 1.0);

    canvas.drawOval(
      Rect.fromCenter(center: leftEyeCenter, width: 18, height: 22 * eyeHeightFactor),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: rightEyeCenter, width: 18, height: 22 * eyeHeightFactor),
      paint,
    );

    // Pupils (Husky Icy Blue)
    if (eyeHeightFactor > 0.3) {
      // Calculate pupil offset
      final pupilDx = (lookProgress - 0.5) * 7.0;
      final pupilDy = isLookingDown ? 4.0 : 0.0;

      paint.color = const Color(0xFF00B4D8); // Bright husky blue iris
      canvas.drawCircle(
        Offset(leftEyeCenter.dx + pupilDx, leftEyeCenter.dy + pupilDy),
        6.0 * eyeHeightFactor,
        paint,
      );
      canvas.drawCircle(
        Offset(rightEyeCenter.dx + pupilDx, rightEyeCenter.dy + pupilDy),
        6.0 * eyeHeightFactor,
        paint,
      );

      // Dark pupil center
      paint.color = const Color(0xFF0F172A);
      canvas.drawCircle(
        Offset(leftEyeCenter.dx + pupilDx, leftEyeCenter.dy + pupilDy),
        3.5 * eyeHeightFactor,
        paint,
      );
      canvas.drawCircle(
        Offset(rightEyeCenter.dx + pupilDx, rightEyeCenter.dy + pupilDy),
        3.5 * eyeHeightFactor,
        paint,
      );

      // White shine catchlight
      paint.color = Colors.white;
      canvas.drawCircle(
        Offset(leftEyeCenter.dx + pupilDx - 1.8, leftEyeCenter.dy + pupilDy - 1.8),
        1.6 * eyeHeightFactor,
        paint,
      );
      canvas.drawCircle(
        Offset(rightEyeCenter.dx + pupilDx - 1.8, rightEyeCenter.dy + pupilDy - 1.8),
        1.6 * eyeHeightFactor,
        paint,
      );
    }

    // ── 6. Snout & Cute Nose ────────────────────────────────────────────────
    final snoutCenter = Offset(cx + tiltX, cy + 18 + tiltY);
    paint.color = const Color(0xFFE2E8F0);
    canvas.drawOval(
      Rect.fromCenter(center: snoutCenter, width: 42, height: 30),
      paint,
    );

    // Cute rounded black nose
    paint.color = const Color(0xFF1E293B);
    final nosePath = Path()
      ..moveTo(snoutCenter.dx - 9, snoutCenter.dy - 6)
      ..quadraticBezierTo(snoutCenter.dx, snoutCenter.dy - 8, snoutCenter.dx + 9, snoutCenter.dy - 6)
      ..quadraticBezierTo(snoutCenter.dx + 10, snoutCenter.dy + 3, snoutCenter.dx, snoutCenter.dy + 5)
      ..quadraticBezierTo(snoutCenter.dx - 10, snoutCenter.dy + 3, snoutCenter.dx - 9, snoutCenter.dy - 6)
      ..close();
    canvas.drawPath(nosePath, paint);

    // Nose light highlight
    paint.color = Colors.white.withValues(alpha: 0.6);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(snoutCenter.dx - 2.5, snoutCenter.dy - 4), width: 3.5, height: 2),
      paint,
    );

    // Cute mouth line
    paint.color = const Color(0xFF475569);
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.8;
    paint.strokeCap = StrokeCap.round;

    final mouthPath = Path()
      ..moveTo(snoutCenter.dx, snoutCenter.dy + 5)
      ..lineTo(snoutCenter.dx, snoutCenter.dy + 9)
      ..moveTo(snoutCenter.dx - 7, snoutCenter.dy + 12)
      ..quadraticBezierTo(snoutCenter.dx - 3.5, snoutCenter.dy + 14, snoutCenter.dx, snoutCenter.dy + 9)
      ..quadraticBezierTo(snoutCenter.dx + 3.5, snoutCenter.dy + 14, snoutCenter.dx + 7, snoutCenter.dy + 12);
    canvas.drawPath(mouthPath, paint);

    paint.style = PaintingStyle.fill; // Reset to fill

    // ── 7. Interactive Paws (Covering Eyes Animation) ───────────────────────
    if (pawProgress > 0.01) {
      // Left Paw
      final leftPawTargetY = cy - 6; // covers left eye
      final leftPawCurrentY = (cy + 70) - (pawProgress * (cy + 70 - leftPawTargetY));
      final leftPawCurrentX = cx - 22;

      _drawPaw(
        canvas,
        Offset(leftPawCurrentX, leftPawCurrentY),
        isLeft: true,
        pawScale: pawProgress,
      );

      // Right Paw (Drops slightly if peeking)
      final rightPawTargetY = (cy - 6) + (peekProgress * 24.0); // Drops down when peeking
      final rightPawCurrentY = (cy + 70) - (pawProgress * (cy + 70 - rightPawTargetY));
      final rightPawCurrentX = cx + 22 + (peekProgress * 6.0);

      _drawPaw(
        canvas,
        Offset(rightPawCurrentX, rightPawCurrentY),
        isLeft: false,
        pawScale: pawProgress,
      );
    }
  }

  void _drawPaw(Canvas canvas, Offset center, {required bool isLeft, required double pawScale}) {
    final paint = Paint()..isAntiAlias = true;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(isLeft ? -0.15 : 0.15);

    // Paw outer fluff (Dark Husky Coat)
    paint.color = const Color(0xFF2C3E50);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0, 0), width: 34 * pawScale, height: 38 * pawScale),
        Radius.circular(16 * pawScale),
      ),
      paint,
    );

    // Inner White Fur
    paint.color = const Color(0xFFF8FAFC);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0, 2), width: 28 * pawScale, height: 30 * pawScale),
        Radius.circular(14 * pawScale),
      ),
      paint,
    );

    // Main center paw pad (Cute Pink)
    paint.color = const Color(0xFFFF8A80);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 4), width: 14 * pawScale, height: 11 * pawScale),
      paint,
    );

    // 3 Toe pads (Pink)
    canvas.drawCircle(Offset(-6 * pawScale, -5 * pawScale), 3.2 * pawScale, paint);
    canvas.drawCircle(Offset(0, -7 * pawScale), 3.2 * pawScale, paint);
    canvas.drawCircle(Offset(6 * pawScale, -5 * pawScale), 3.2 * pawScale, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HuskyPainter old) =>
      old.lookProgress != lookProgress ||
      old.isLookingDown != isLookingDown ||
      old.pawProgress != pawProgress ||
      old.peekProgress != peekProgress ||
      old.blinkProgress != blinkProgress;
}

/// Ambient Orb Painter
class _OrbPainter extends CustomPainter {
  final double animValue;

  _OrbPainter(this.animValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Top-right purple orb
    final orb1Center = Offset(
      size.width * 0.85 + sin(animValue * 2 * pi) * 25,
      size.height * 0.18 + cos(animValue * 2 * pi) * 18,
    );
    paint.shader = RadialGradient(
      colors: [
        const Color(0xFF7C4DFF).withValues(alpha: 0.16),
        const Color(0xFF7C4DFF).withValues(alpha: 0.0),
      ],
    ).createShader(Rect.fromCircle(center: orb1Center, radius: 150));
    canvas.drawCircle(orb1Center, 150, paint);

    // Bottom-left cyan orb
    final orb2Center = Offset(
      size.width * 0.15 + cos(animValue * 2 * pi) * 22,
      size.height * 0.75 + sin(animValue * 2 * pi) * 26,
    );
    paint.shader = RadialGradient(
      colors: [
        const Color(0xFF00E5FF).withValues(alpha: 0.12),
        const Color(0xFF00E5FF).withValues(alpha: 0.0),
      ],
    ).createShader(Rect.fromCircle(center: orb2Center, radius: 130));
    canvas.drawCircle(orb2Center, 130, paint);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) =>
      oldDelegate.animValue != animValue;
}
