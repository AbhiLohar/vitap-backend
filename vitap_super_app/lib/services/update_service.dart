import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api_config.dart';
import '../widgets/update_dialog.dart';
import 'notification_service.dart';

class UpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String releaseTitle;
  final String releaseNotes;
  final String? apkDownloadUrl;
  final String releasePageUrl;
  final DateTime? publishedAt;

  UpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseTitle,
    required this.releaseNotes,
    this.apkDownloadUrl,
    required this.releasePageUrl,
    this.publishedAt,
  });
}

class UpdateService {
  // GitHub repository details
  static const String repoOwner = "AbhiLohar";
  static const String repoName = "vitap-backend";

  // Central compile-time version for this app release
  static const String currentAppVersion = "1.0.6";
  static const int currentVersionCode = 7;
  static const String fallbackVersion = currentAppVersion;

  // Native Android package installer channel
  static const MethodChannel _installerChannel =
      MethodChannel("com.example.vitap_super_app/installer");

  // Multi-tier URLs
  // Tier 1: Fastly CDN raw file - zero rate limits, cached globally
  static const String cdnVersionUrl =
      "https://raw.githubusercontent.com/$repoOwner/$repoName/main/version.json";

  // Tier 2: Backend API endpoint
  static String get backendVersionUrl => "${ApiConfig.baseUrl}/app/version";

  // Tier 3: GitHub Web UI redirect (no 60 req/hr API restriction)
  static const String releasesWebUrl =
      "https://github.com/$repoOwner/$repoName/releases/latest";

  // Direct APK download URL for the latest release (used for QR code & direct sharing)
  static const String directApkDownloadUrl =
      "https://github.com/$repoOwner/$repoName/releases/latest/download/app-release.apk";

  // Tier 4: GitHub REST API (fallback)
  static const String releasesApiUrl =
      "https://api.github.com/repos/$repoOwner/$repoName/releases/latest";

  static const String _prefLastCheckKey = "last_update_check_time";
  static const String _prefIgnoredVersionKey = "ignored_update_version";
  static const String prefInstalledVersionKey = "last_installed_version";

  /// Compares two semver version strings (e.g. "1.0.1" vs "1.0.0").
  /// Returns > 0 if v1 > v2, < 0 if v1 < v2, 0 if equal.
  static int compareVersions(String v1, String v2) {
    List<int> parse(String v) {
      final clean = v.trim().toLowerCase().replaceAll(RegExp(r'^[v\s]+'), '');
      final mainPart = clean.split('+').first.split('-').first;
      return mainPart
          .split('.')
          .map((part) => int.tryParse(part) ?? 0)
          .toList();
    }

    final p1 = parse(v1);
    final p2 = parse(v2);
    final maxLen = p1.length > p2.length ? p1.length : p2.length;

    for (int i = 0; i < maxLen; i++) {
      final num1 = i < p1.length ? p1[i] : 0;
      final num2 = i < p2.length ? p2[i] : 0;
      if (num1 != num2) {
        return num1.compareTo(num2);
      }
    }
    return 0;
  }

  /// Get the current installed app version.
  static Future<String> getCurrentVersion() async {
    String detectedVersion = "";

    // 1. Try native Android packageManager via our installer channel (most accurate, zero caching)
    if (Platform.isAndroid) {
      try {
        final res = await _installerChannel.invokeMapMethod<String, dynamic>('getAppVersion');
        if (res != null) {
          final ver = res['versionName']?.toString().trim();
          if (ver != null && ver.isNotEmpty) {
            detectedVersion = ver.replaceAll(RegExp(r'^[v\s]+'), '');
          }
        }
      } catch (_) {}
    }

    // 2. Try PackageInfo plugin
    if (detectedVersion.isEmpty) {
      try {
        final info = await PackageInfo.fromPlatform();
        final ver = info.version.trim();
        if (ver.isNotEmpty && ver != "0.0.0") {
          detectedVersion = ver.replaceAll(RegExp(r'^[v\s]+'), '');
        }
      } catch (_) {}
    }

    // 3. Check SharedPreferences for last recorded installed version (safeguard if user updated
    // while app process was kept alive in background)
    try {
      final prefs = await SharedPreferences.getInstance();
      final installedVer = prefs.getString(prefInstalledVersionKey)?.trim();
      if (installedVer != null && installedVer.isNotEmpty) {
        if (detectedVersion.isEmpty || compareVersions(installedVer, detectedVersion) > 0) {
          detectedVersion = installedVer;
        }
      }
    } catch (_) {}

    // 4. If detected version is still empty or older than this binary's compiled version,
    // default to the compile-time currentAppVersion
    if (detectedVersion.isEmpty || compareVersions(currentAppVersion, detectedVersion) > 0) {
      detectedVersion = currentAppVersion;
    }

    return detectedVersion;
  }

  /// Check whether the app has permission to install unknown apps (Android 8.0+)
  static Future<bool> canRequestPackageInstalls() async {
    try {
      final res = await _installerChannel.invokeMethod<bool>('canRequestPackageInstalls');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Open Android settings to toggle "Allow from this source" for VTOP Super App
  static Future<void> openInstallSettings() async {
    try {
      await _installerChannel.invokeMethod('openInstallSettings');
    } catch (_) {}
  }

  /// Trigger the native Android package installer using FileProvider
  static Future<bool> installApk(String filePath) async {
    try {
      final res = await _installerChannel.invokeMethod<bool>('installApk', {'filePath': filePath});
      return res ?? false;
    } catch (e) {
      rethrow;
    }
  }

  /// Downloads the release APK into local app cache with live byte progress
  static Future<File> downloadApk(
    String downloadUrl, {
    required void Function(int receivedBytes, int totalBytes, double progress) onProgress,
    bool Function()? isCancelled,
    http.Client? customClient,
  }) async {
    final client = customClient ?? http.Client();
    try {
      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/app-update.apk');
      if (await apkFile.exists()) {
        try {
          await apkFile.delete();
        } catch (_) {}
      }

      final request = http.Request('GET', Uri.parse(downloadUrl));
      request.followRedirects = true;
      request.headers['Accept'] = '*/*';
      request.headers['User-Agent'] = 'VTOP-Super-App';

      final response = await client.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception("Server responded with HTTP ${response.statusCode} while downloading update");
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      final sink = apkFile.openWrite();

      await for (final chunk in response.stream) {
        if (isCancelled != null && isCancelled()) {
          await sink.close();
          try {
            await apkFile.delete();
          } catch (_) {}
          throw Exception("Download cancelled");
        }
        sink.add(chunk);
        receivedBytes += chunk.length;
        final progress = totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
        onProgress(receivedBytes, totalBytes, progress);
      }

      await sink.flush();
      await sink.close();

      return apkFile;
    } finally {
      if (customClient == null) {
        client.close();
      }
    }
  }

  /// Tier 1: GitHub Raw CDN (Fastly CDN - zero rate limits)
  static Future<UpdateInfo?> _fetchFromCdn(String currentVersion) async {
    try {
      final response = await http.get(
        Uri.parse(cdnVersionUrl),
        headers: {
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final rawVer = (data["version"] ?? "").toString();
        final latestVersion = rawVer.replaceAll(RegExp(r'^[v\s]+'), '').trim();
        if (latestVersion.isEmpty) return null;

        final releaseTitle = (data["title"] ?? "Version $latestVersion").toString();
        final releaseNotes = (data["notes"] ?? "Bug fixes and improvements.").toString();
        final apkUrl = (data["apkUrl"] as String?) ??
            "https://github.com/$repoOwner/$repoName/releases/download/v$latestVersion/app-release.apk";
        final releasePageUrl = (data["releaseUrl"] ?? releasesWebUrl).toString();
        final publishedStr = data["publishedAt"] as String?;
        final publishedAt = publishedStr != null ? DateTime.tryParse(publishedStr) : null;

        return UpdateInfo(
          hasUpdate: compareVersions(latestVersion, currentVersion) > 0,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          releaseTitle: releaseTitle,
          releaseNotes: releaseNotes,
          apkDownloadUrl: apkUrl,
          releasePageUrl: releasePageUrl,
          publishedAt: publishedAt,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Tier 2: FastAPI Backend (/app/version)
  static Future<UpdateInfo?> _fetchFromBackend(String currentVersion) async {
    try {
      final response = await http.get(
        Uri.parse(backendVersionUrl),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final rawVer = (data["version"] ?? "").toString();
        final latestVersion = rawVer.replaceAll(RegExp(r'^[v\s]+'), '').trim();
        if (latestVersion.isEmpty) return null;

        final releaseTitle = (data["title"] ?? "Version $latestVersion").toString();
        final releaseNotes = (data["notes"] ?? "Bug fixes and improvements.").toString();
        final apkUrl = (data["apkUrl"] as String?) ??
            "https://github.com/$repoOwner/$repoName/releases/download/v$latestVersion/app-release.apk";
        final releasePageUrl = (data["releaseUrl"] ?? releasesWebUrl).toString();
        final publishedStr = data["publishedAt"] as String?;
        final publishedAt = publishedStr != null ? DateTime.tryParse(publishedStr) : null;

        return UpdateInfo(
          hasUpdate: compareVersions(latestVersion, currentVersion) > 0,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          releaseTitle: releaseTitle,
          releaseNotes: releaseNotes,
          apkDownloadUrl: apkUrl,
          releasePageUrl: releasePageUrl,
          publishedAt: publishedAt,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Tier 3: GitHub Web UI 302 Redirect (inspects Location header, no API rate limits)
  static Future<UpdateInfo?> _fetchFromWebRedirect(String currentVersion) async {
    try {
      final client = http.Client();
      try {
        final headReq = http.Request('HEAD', Uri.parse(releasesWebUrl))
          ..followRedirects = false;
        var streamed = await client.send(headReq).timeout(const Duration(seconds: 6));

        // If HEAD is rejected or redirects with body, try GET with followRedirects: false
        if (streamed.statusCode != 302 && streamed.statusCode != 301) {
          final getReq = http.Request('GET', Uri.parse(releasesWebUrl))
            ..followRedirects = false;
          streamed = await client.send(getReq).timeout(const Duration(seconds: 6));
        }

        final location = streamed.headers['location'] ?? '';
        if (location.isNotEmpty) {
          final tagMatch = RegExp(r'releases/tag/([^/?#]+)').firstMatch(location);
          if (tagMatch != null) {
            final tag = tagMatch.group(1)!;
            final latestVersion = tag.replaceAll(RegExp(r'^[v\s]+'), '').trim();
            final directApk =
                "https://github.com/$repoOwner/$repoName/releases/download/$tag/app-release.apk";
            final pageUrl = "https://github.com/$repoOwner/$repoName/releases/tag/$tag";

            return UpdateInfo(
              hasUpdate: compareVersions(latestVersion, currentVersion) > 0,
              currentVersion: currentVersion,
              latestVersion: latestVersion,
              releaseTitle: "Version $latestVersion",
              releaseNotes: "A new update for VTOP Super App is available! Tap Update Now to download the latest APK.",
              apkDownloadUrl: directApk,
              releasePageUrl: pageUrl,
            );
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return null;
  }

  /// Tier 4: GitHub REST API (gracefully catches 403 without throwing)
  static Future<UpdateInfo?> _fetchFromGitHubApi(String currentVersion) async {
    try {
      final response = await http.get(
        Uri.parse(releasesApiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'VTOP-Super-App',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final rawTag = (data["tag_name"] ?? "").toString();
        final latestVersion = rawTag.replaceAll(RegExp(r'^[v\s]+'), '').trim();
        final releaseTitle = (data["name"] ?? "Version $latestVersion").toString();
        final releaseNotes = (data["body"] ?? "Bug fixes and improvements.").toString();
        final htmlUrl = (data["html_url"] ?? releasesWebUrl).toString();
        final publishedStr = data["published_at"] as String?;
        final publishedAt = publishedStr != null ? DateTime.tryParse(publishedStr) : null;

        String? apkUrl;
        final assets = data["assets"] as List<dynamic>? ?? [];
        for (final asset in assets) {
          if (asset is Map<String, dynamic>) {
            final name = (asset["name"] ?? "").toString().toLowerCase();
            final downloadUrl = (asset["browser_download_url"] ?? "").toString();
            if (name.endsWith(".apk") && downloadUrl.isNotEmpty) {
              apkUrl = downloadUrl;
              if (name.contains("release")) break;
            }
          }
        }

        return UpdateInfo(
          hasUpdate: compareVersions(latestVersion, currentVersion) > 0,
          currentVersion: currentVersion,
          latestVersion: latestVersion.isNotEmpty ? latestVersion : currentVersion,
          releaseTitle: releaseTitle,
          releaseNotes: releaseNotes,
          apkDownloadUrl: apkUrl ?? "https://github.com/$repoOwner/$repoName/releases/download/$rawTag/app-release.apk",
          releasePageUrl: htmlUrl,
          publishedAt: publishedAt,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Check for any new APK version across multi-tiered fallbacks.
  static Future<UpdateInfo?> checkForUpdate({bool isManual = false}) async {
    final prefs = await SharedPreferences.getInstance();

    // Throttling for automatic background checks (at most once every 15 mins)
    if (!isManual) {
      final lastCheckMillis = prefs.getInt(_prefLastCheckKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastCheckMillis < const Duration(minutes: 15).inMilliseconds) {
        return null;
      }
      await prefs.setInt(_prefLastCheckKey, now);
    }

    final currentVersion = await getCurrentVersion();

    // 1. Tier 1: Fastly CDN raw JSON (fastest, zero rate limits)
    UpdateInfo? info = await _fetchFromCdn(currentVersion);

    // 2. Tier 2: Backend API endpoint
    info ??= await _fetchFromBackend(currentVersion);

    // 3. Tier 3: GitHub Web UI redirect (bypasses GitHub REST API limits)
    info ??= await _fetchFromWebRedirect(currentVersion);

    // 4. Tier 4: GitHub REST API (handles 403 silently)
    info ??= await _fetchFromGitHubApi(currentVersion);

    // If completely offline or all network requests failed:
    if (info == null) {
      if (isManual) {
        throw Exception("Unable to reach update servers. Please check your internet connection.");
      }
      return null;
    }

    // Check if user previously muted notifications for this version
    if (info.hasUpdate && !isManual) {
      final ignoredVersion = prefs.getString(_prefIgnoredVersionKey);
      if (ignoredVersion == info.latestVersion) {
        return null;
      }
    }

    return info;
  }

  /// Launch APK download in the device browser / download manager (as fallback)
  static Future<bool> launchDownload(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Ignore update reminders for this version
  static Future<void> ignoreVersion(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefIgnoredVersionKey, version);
    } catch (_) {}
  }

  /// Record that an APK update was launched/installed
  static Future<void> recordInstalledVersion(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clean = version.replaceAll(RegExp(r'^[v\s]+'), '').trim();
      await prefs.setString(prefInstalledVersionKey, clean);
    } catch (_) {}
  }

  /// Auto-check on app startup or manual trigger
  static Future<void> checkAndShow(BuildContext context, {bool isManual = false}) async {
    try {
      final info = await checkForUpdate(isManual: isManual);
      if (!context.mounted) return;

      if (info != null && info.hasUpdate) {
        // 1. Post persistent Android system status bar notification (tap to download)
        try {
          NotificationService.instance.showUpdateNotification(info);
        } catch (_) {}

        // 2. Display modal dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => UpdateDialog(info: info),
        );
      } else if (isManual) {
        final current = info?.currentVersion ?? fallbackVersion;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "VTOP Super App is up to date (v$current)!",
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (isManual && context.mounted) {
        final message = e.toString().replaceFirst("Exception: ", "");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.orangeAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(message)),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}
