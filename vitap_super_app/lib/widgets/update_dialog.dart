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

  void _onUpdateNow() async {
    setState(() => _isDownloading = true);
    final targetUrl = widget.info.apkDownloadUrl ?? widget.info.releasePageUrl;
    
    final success = await UpdateService.launchDownload(targetUrl);
    if (!mounted) return;

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not launch download link. Opening GitHub release page...")),
      );
      await UpdateService.launchDownload(widget.info.releasePageUrl);
    }
    
    if (_dontAskAgain) {
      await UpdateService.ignoreVersion(widget.info.latestVersion);
    }
    
    if (mounted) {
      Navigator.of(context).pop();
    }
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
                child: const Icon(
                  Icons.system_update_alt_rounded,
                  size: 40,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Update Available!",
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
              onPressed: _isDownloading ? null : _onUpdateNow,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 2,
              ),
              child: _isDownloading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.download_rounded, size: 18),
                        SizedBox(width: 8),
                        Text(
                          "Update Now",
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
                  child: TextButton(
                    onPressed: () => UpdateService.launchDownload(info.releasePageUrl),
                    child: const Text(
                      "View on GitHub",
                      style: TextStyle(color: AppColors.primary, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
