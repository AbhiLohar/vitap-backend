import 'package:flutter/material.dart';
import 'cyber_otp_dialog.dart';

/// Legacy export and backwards-compatible wrapper for CyberOtpDialog
class OtpDialog extends StatelessWidget {
  const OtpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return const CyberOtpDialog(
      title: "Session Expired",
      subtitle: "Please enter the 6-digit OTP sent to your registered email to continue.",
    );
  }
}

/// Displays the premium cyber OTP authentication dialog when background session expires
Future<String?> showReAuthOtpDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.8),
    builder: (context) => const CyberOtpDialog(
      title: "Session Expired",
      subtitle: "Please enter the 6-digit OTP sent to your registered email to continue.",
    ),
  );
}
