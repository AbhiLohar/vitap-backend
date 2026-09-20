import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
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
  
  static const String fallbackVersion = "1.0.3";
  static const String releasesApiUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest";
  static const String releasesWebUrl = "https://github.com/$repoOwner/$repoName/releases/latest";

  static const String _prefLastCheckKey = "last_update_check_time";
  static const String _prefIgnoredVersionKey = "ignored_update_version";

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
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) {
        return info.version;
      }
    } catch (_) {}
    return fallbackVersion;
  }

  /// Check GitHub Releases for any new APK version.
  static Future<UpdateInfo?> checkForUpdate({bool isManual = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // For automatic launch checks: throttle to at most once every 15 minutes
      if (!isManual) {
        final lastCheckMillis = prefs.getInt(_prefLastCheckKey) ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastCheckMillis < const Duration(minutes: 15).inMilliseconds) {
          return null; // Recently checked, skip to save network & rate limits
        }
        await prefs.setInt(_prefLastCheckKey, now);
      }

      final currentVersion = await getCurrentVersion();

      final response = await http.get(
        Uri.parse(releasesApiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'VTOP-Super-App',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 404) {
        // No release published on GitHub yet
        return UpdateInfo(
          hasUpdate: false,
          currentVersion: currentVersion,
          latestVersion: currentVersion,
          releaseTitle: "Latest",
          releaseNotes: "No releases found on GitHub.",
          releasePageUrl: releasesWebUrl,
        );
      }

      if (response.statusCode != 200) {
        throw Exception("GitHub API returned status ${response.statusCode}");
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final rawTag = (data["tag_name"] ?? "").toString();
      final latestVersion = rawTag.replaceAll(RegExp(r'^[v\s]+'), '').trim();
      final releaseTitle = (data["name"] ?? "Version $latestVersion").toString();
      final releaseNotes = (data["body"] ?? "Bug fixes and improvements.").toString();
      final htmlUrl = (data["html_url"] ?? releasesWebUrl).toString();
      final publishedStr = data["published_at"] as String?;
      final publishedAt = publishedStr != null ? DateTime.tryParse(publishedStr) : null;

      // Find direct .apk asset download URL
      String? apkUrl;
      final assets = data["assets"] as List<dynamic>? ?? [];
      for (final asset in assets) {
        if (asset is Map<String, dynamic>) {
          final name = (asset["name"] ?? "").toString().toLowerCase();
          final downloadUrl = (asset["browser_download_url"] ?? "").toString();
          if (name.endsWith(".apk") && downloadUrl.isNotEmpty) {
            apkUrl = downloadUrl;
            // Prefer app-release.apk
            if (name.contains("release")) {
              break;
            }
          }
        }
      }

      final hasUpdate = compareVersions(latestVersion, currentVersion) > 0;

      // If user previously chose "Don't remind me again" for this exact version, ignore on auto check
      if (hasUpdate && !isManual) {
        final ignoredVersion = prefs.getString(_prefIgnoredVersionKey);
        if (ignoredVersion == latestVersion) {
          return null;
        }
      }

      return UpdateInfo(
        hasUpdate: hasUpdate,
        currentVersion: currentVersion,
        latestVersion: latestVersion.isNotEmpty ? latestVersion : currentVersion,
        releaseTitle: releaseTitle,
        releaseNotes: releaseNotes,
        apkDownloadUrl: apkUrl,
        releasePageUrl: htmlUrl,
        publishedAt: publishedAt,
      );
    } catch (e) {
      if (isManual) rethrow;
      return null;
    }
  }

  /// Launch APK download in the device browser / download manager
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
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text("You're on the latest version (v$current)!")),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (isManual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Unable to check updates: $e"),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
