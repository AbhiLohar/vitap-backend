import 'dart:io';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const UpdateDialog({super.key, required this.info});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _dontAskAgain = false;
  bool _isDownloading = false;
  bool _isInstalling = false;
  bool _needsPermission = false;
  bool _isCancelled = false;
  String? _errorMessage;
  String _statusText = "Downloading update...";

  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  File? _downloadedApkFile;

  String _formatMb(int bytes) {
    if (bytes <= 0) return "0 MB";
    final mb = bytes / (1024 * 1024);
    return "${mb.toStringAsFixed(1)} MB";
  }

  void _onUpdateNow() async {
    setState(() {
      _isDownloading = true;
      _isInstalling = false;
      _needsPermission = false;
      _errorMessage = null;
      _isCancelled = false;
      _progress = 0.0;
      _receivedBytes = 0;
      _totalBytes = 0;
      _statusText = "Connecting to server...";
    });

    final targetUrl = widget.info.apkDownloadUrl ?? widget.info.releasePageUrl;

    // If it's not a direct APK link, fall back to browser
    if (!targetUrl.toLowerCase().endsWith('.apk') && !targetUrl.contains('/download/')) {
      await UpdateService.launchDownload(targetUrl);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    try {
      final file = await UpdateService.downloadApk(
        targetUrl,
        onProgress: (received, total, progress) {
          if (!mounted || _isCancelled) return;
          setState(() {
            _receivedBytes = received;
            _totalBytes = total;
            _progress = progress;
            _statusText = "Downloading: ${(_progress * 100).toInt()}%";
          });
        },
        isCancelled: () => _isCancelled,
      );

      if (!mounted || _isCancelled) return;

      _downloadedApkFile = file;
      await _triggerInstall(file);
    } catch (e) {
      if (!mounted || _isCancelled) return;
      setState(() {
        _isDownloading = false;
        _isInstalling = false;
        final rawError = e.toString().replaceFirst("Exception: ", "");
        if (rawError.contains("ClientConnection closed") ||
            rawError.contains("Connection closed") ||
            rawError.contains("SocketException") ||
            rawError.contains("ClientException") ||
            rawError.contains("timeout") ||
            rawError.contains("interrupted")) {
          _errorMessage = "Network connection interrupted while downloading. Tap 'Retry' or 'Download via Browser'.";
        } else {
          _errorMessage = rawError;
        }
      });
    }
  }

  Future<void> _triggerInstall(File file) async {
    setState(() {
      _isInstalling = true;
      _statusText = "Opening Package Installer...";
    });

    try {
      // 1. Check if "Install unknown apps" permission is granted on Android 8+
      final canInstall = await UpdateService.canRequestPackageInstalls();
      if (!canInstall) {
        setState(() {
          _isDownloading = false;
          _isInstalling = false;
          _needsPermission = true;
        });
        return;
      }

      // 2. Record installed version and launch native Package Installer
      await UpdateService.recordInstalledVersion(widget.info.latestVersion);
      final launched = await UpdateService.installApk(file.path);
      if (!launched) {
        throw Exception("Could not start installer");
      }

      if (_dontAskAgain) {
        await UpdateService.ignoreVersion(widget.info.latestVersion);
      }

      // Close dialog as system installer is now displayed over the app
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _isInstalling = false;
        _errorMessage = "Installation failed: ${e.toString().replaceFirst('Exception: ', '')}";
      });
    }
  }

  void _onCancelDownload() {
    setState(() {
      _isCancelled = true;
      _isDownloading = false;
      _isInstalling = false;
      _progress = 0.0;
    });
  }

  void _onLater() async {
    if (_dontAskAgain) {
      await UpdateService.ignoreVersion(widget.info.latestVersion);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;

    return Dialog(
      backgroundColor: AppColors.cardBg(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 16,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Header Icon & Title
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isDownloading || _isInstalling
                      ? Icons.downloading_rounded
                      : Icons.system_update_alt_rounded,
                  size: 40,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isDownloading
                  ? "Downloading Update"
                  : _isInstalling
                      ? "Installing Update..."
                      : "Update Available!",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 10),

            // Version Comparison Badge
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.scaffoldBg(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.cardBorder(context)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "v${info.currentVersion}",
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted(context),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.primary),
                    ),
                    Text(
                      "v${info.latestVersion}",
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Main Content Area: Downloading vs Normal vs Permission
            if (_isDownloading || _isInstalling) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 10,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _statusText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  Text(
                    _totalBytes > 0
                        ? "${_formatMb(_receivedBytes)} / ${_formatMb(_totalBytes)}"
                        : "${(_progress * 100).toInt()}%",
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: _onCancelDownload,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: AppColors.cardBorder(context)),
                ),
                child: const Text("Cancel Download"),
              ),
            ] else if (_needsPermission) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.security_rounded, color: Colors.amber, size: 28),
                    const SizedBox(height: 8),
                    Text(
                      "Install Permission Needed",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary(context),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "To install the downloaded APK, please enable 'Allow from this source' for VTOP Super App in Android Settings.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => UpdateService.openInstallSettings(),
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text("Open Settings to Allow"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  if (_downloadedApkFile != null) {
                    _triggerInstall(_downloadedApkFile!);
                  } else {
                    _onUpdateNow();
                  }
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text("I have enabled it — Install Now"),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ] else ...[
              // Release Notes Box
              Text(
                "What's New:",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.scaffoldBg(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.cardBorder(context)),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Text(
                    info.releaseNotes.trim().isEmpty
                        ? "Performance improvements and bug fixes."
                        : info.releaseNotes.trim(),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Error Message Banner (if any)
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Don't ask again checkbox
              Row(
                children: [
                  SizedBox(
                    height: 24,
                    width: 24,
                    child: Checkbox(
                      value: _dontAskAgain,
                      activeColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (val) => setState(() => _dontAskAgain = val ?? false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _dontAskAgain = !_dontAskAgain),
                      child: Text(
                        "Don't remind me again for this version",
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Action Buttons
              ElevatedButton(
                onPressed: _onUpdateNow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _errorMessage != null ? Icons.refresh_rounded : Icons.download_rounded,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _errorMessage != null ? "Retry Update" : "Update Now",
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _onLater,
                      child: Text(
                        "Later",
                        style: TextStyle(color: AppColors.textMuted(context), fontSize: 13),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        final targetUrl = widget.info.apkDownloadUrl ?? widget.info.releasePageUrl;
                        UpdateService.launchDownload(targetUrl);
                      },
                      icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                      label: const Text(
                        "Download via Browser",
                        style: TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
  }
}
