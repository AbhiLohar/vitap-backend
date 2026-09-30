import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_theme.dart';

/// A custom curve for realistic shake animation on invalid OTP input
class _ShakeCurve extends Curve {
  const _ShakeCurve();

  @override
  double transform(double t) {
    return sin(t * pi * 4); // 4 oscillations
  }
}

/// Premium dark-mode cybersecurity / fintech OTP authentication dialog
class CyberOtpDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final String? accountTag;
  final Future<String?> Function(String otp)? onVerify;
  final Future<String?> Function()? onResend;
  final VoidCallback? onCancel;
  final bool autoSubmit;

  const CyberOtpDialog({
    super.key,
    this.title = "Enter your code",
    this.subtitle = "We sent a 6-digit code to verify your session.",
    this.accountTag,
    this.onVerify,
    this.onResend,
    this.onCancel,
    this.autoSubmit = true,
  });

  @override
  State<CyberOtpDialog> createState() => _CyberOtpDialogState();
}

class _CyberOtpDialogState extends State<CyberOtpDialog>
    with TickerProviderStateMixin {
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  late AnimationController _cursorController;
  late Animation<double> _cursorOpacity;

  bool _isLoading = false;
  String? _errorMessage;
  int _resendCountdown = 30;
  Timer? _resendTimer;
  bool _canResend = false;
  bool _hasClipboardCode = false;
  String? _clipboardCandidate;

  @override
  void initState() {
    super.initState();

    // Shake animation for error feedback
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shakeController, curve: const _ShakeCurve()),
    );

    // Blinking neon cursor animation
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    _cursorOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _cursorController, curve: Curves.easeInOut),
    );

    // Start resend countdown
    _startResendTimer();

    // Check clipboard for 6-digit OTP
    _checkClipboard();

    // Request keyboard focus after frame render
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });

    _otpController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _otpController.removeListener(_onTextChanged);
    _otpController.dispose();
    _focusNode.dispose();
    _shakeController.dispose();
    _cursorController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() {
      _resendCountdown = 30;
      _canResend = false;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown > 1) {
        setState(() {
          _resendCountdown--;
        });
      } else {
        setState(() {
          _resendCountdown = 0;
          _canResend = true;
        });
        timer.cancel();
      }
    });
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      final digits = text.replaceAll(RegExp(r'\D'), '');
      if (digits.length == 6 && mounted) {
        setState(() {
          _hasClipboardCode = true;
          _clipboardCandidate = digits;
        });
      }
    } catch (_) {}
  }

  void _pasteClipboardCode() {
    if (_clipboardCandidate != null && _clipboardCandidate!.length == 6) {
      _otpController.text = _clipboardCandidate!;
      setState(() {
        _hasClipboardCode = false;
      });
    }
  }

  void _onTextChanged() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
    setState(() {}); // Rebuild to update individual segmented boxes

    if (_otpController.text.length == 6 && widget.autoSubmit && !_isLoading) {
      _handleVerify();
    }
  }

  Future<void> _handleVerify() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = "Please enter the complete 6-digit code");
      _shakeController.forward(from: 0.0);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // If caller provided onVerify callback
    if (widget.onVerify != null) {
      try {
        final error = await widget.onVerify!(code);
        if (!mounted) return;
        if (error != null && error.isNotEmpty) {
          setState(() {
            _isLoading = false;
            _errorMessage = error;
          });
          _shakeController.forward(from: 0.0);
          HapticFeedback.mediumImpact();
        } else {
          // Success handled by caller
          setState(() => _isLoading = false);
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst("Exception: ", "");
        });
        _shakeController.forward(from: 0.0);
        HapticFeedback.heavyImpact();
      }
    } else {
      // Return-value mode for showReAuthOtpDialog
      Navigator.of(context).pop(code);
    }
  }

  Future<void> _handleResend() async {
    if (!_canResend || _isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (widget.onResend != null) {
      try {
        final error = await widget.onResend!();
        if (!mounted) return;
        setState(() => _isLoading = false);
        if (error != null) {
          setState(() => _errorMessage = error);
        } else {
          _startResendTimer();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF0F172A),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Color(0xFF38BDF8), size: 20),
                  SizedBox(width: 10),
                  Text("A new 6-digit code has been sent"),
                ],
              ),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = "Failed to resend code. Please try again.";
        });
      }
    } else {
      setState(() => _isLoading = false);
      _startResendTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentCode = _otpController.text;
    final activeIndex = currentCode.length.clamp(0, 5);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: AnimatedBuilder(
            animation: _shakeAnimation,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(_shakeAnimation.value * 10, 0),
                child: child,
              );
            },
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                // Dark charcoal obsidian background
                color: const Color(0xFF0F1218),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: _errorMessage != null
                      ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                      : const Color(0xFF262C38),
                  width: 1.2,
                ),
                boxShadow: [
                  // Ambient dark elevation
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.7),
                    blurRadius: 36,
                    spreadRadius: 4,
                    offset: const Offset(0, 14),
                  ),
                  // Soft cyber neon glow
                  BoxShadow(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.05),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Invisible backing text field to handle native typing, paste & IME
                  Opacity(
                    opacity: 0.0,
                    child: SizedBox(
                      width: 1,
                      height: 1,
                      child: TextField(
                        controller: _otpController,
                        focusNode: _focusNode,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        onSubmitted: (_) => _handleVerify(),
                      ),
                    ),
                  ),

                  // Interactive visible UI
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Sub-header: Security Check Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141923),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF1E293B)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.verified_user_outlined,
                              size: 13,
                              color: Color(0xFF38BDF8),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "SECURITY CHECK",
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2.0,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Title: Enter your code
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFF8FAFC),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Subtitle
                      Text(
                        widget.accountTag != null
                            ? "We sent a 6-digit code to verify ${widget.accountTag}."
                            : widget.subtitle,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.4,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Segmented 6-digit inputs with hyphen separator
                      GestureDetector(
                        onTap: () => _focusNode.requestFocus(),
                        behavior: HitTestBehavior.opaque,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            // 4 gaps of 6px (24px) + middle divider (10px + 16px margins = 26px) = 50px fixed width
                            final totalAvailable = constraints.maxWidth;
                            final boxWidth = ((totalAvailable - 52) / 6).floorToDouble().clamp(28.0, 46.0);
                            final boxHeight = (boxWidth * 1.25).clamp(36.0, 58.0);

                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Left 3 digits
                                for (int i = 0; i < 3; i++) ...[
                                  _buildDigitBox(
                                    index: i,
                                    currentCode: currentCode,
                                    activeIndex: activeIndex,
                                    width: boxWidth,
                                    height: boxHeight,
                                  ),
                                  if (i < 2) const SizedBox(width: 6),
                                ],

                                // Middle divider hyphen (matching the reference design)
                                Container(
                                  width: 10,
                                  height: 2.5,
                                  margin: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF475569),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),

                                // Right 3 digits
                                for (int i = 3; i < 6; i++) ...[
                                  _buildDigitBox(
                                    index: i,
                                    currentCode: currentCode,
                                    activeIndex: activeIndex,
                                    width: boxWidth,
                                    height: boxHeight,
                                  ),
                                  if (i < 5) const SizedBox(width: 6),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Helper hint: Enter the 6-digit code
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: Color(0xFF64748B),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Enter the 6-digit code",
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Tip: paste to fill every box at once
                      Text(
                        "Tip: paste to fill every box at once.",
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: const Color(0xFF475569),
                          fontStyle: FontStyle.italic,
                        ),
                      ),

                      // Quick 1-tap paste button if clipboard has 6 digits
                      if (_hasClipboardCode) ...[
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _pasteClipboardCode,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.paste_rounded, size: 14, color: Color(0xFF38BDF8)),
                                const SizedBox(width: 6),
                                Text(
                                  "Paste $_clipboardCandidate from clipboard",
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF38BDF8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      // Error message banner
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 18,
                                color: Color(0xFFEF4444),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFFFCA5A5),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),

                      // Primary Verify Button (High-tech glow & gradient)
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                                blurRadius: 16,
                                spreadRadius: 1,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleVerify,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.lock_open_rounded, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        "Verify Code",
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Footer Row: Resend Code Timer & Cancel Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Cancel Button
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              if (widget.onCancel != null) {
                                widget.onCancel!();
                              } else {
                                Navigator.of(context).pop(null);
                              }
                            },
                            child: Text(
                              "Cancel",
                              style: GoogleFonts.inter(
                                color: const Color(0xFF94A3B8),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),

                          // Resend Code
                          Flexible(
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: _canResend && !_isLoading ? _handleResend : null,
                              icon: Icon(
                                Icons.refresh_rounded,
                                size: 15,
                                color: _canResend
                                    ? const Color(0xFF38BDF8)
                                    : const Color(0xFF64748B),
                              ),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _canResend
                                      ? "Resend Code"
                                      : "Resend in ${_resendCountdown}s",
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _canResend
                                        ? const Color(0xFF38BDF8)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds an individual segmented OTP digit box with subtle elevation and neon focus glow
  Widget _buildDigitBox({
    required int index,
    required String currentCode,
    required int activeIndex,
    required double width,
    required double height,
  }) {
    final hasChar = index < currentCode.length;
    final char = hasChar ? currentCode[index] : '';
    final isFocused = _focusNode.hasFocus && index == activeIndex;
    final isError = _errorMessage != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: width,
      height: height,
      decoration: BoxDecoration(
        // Subtle elevated / neomorphic charcoal surface
        color: isFocused
            ? const Color(0xFF141923)
            : hasChar
                ? const Color(0xFF161B24)
                : const Color(0xFF12151C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isError
              ? const Color(0xFFEF4444)
              : isFocused
                  ? const Color(0xFF38BDF8)
                  : hasChar
                      ? const Color(0xFF38BDF8).withValues(alpha: 0.4)
                      : const Color(0xFF262C38),
          width: isFocused ? 1.8 : 1.2,
        ),
        boxShadow: isError
            ? [
                BoxShadow(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : isFocused
                ? [
                    // Soft blue neon focus glow
                    BoxShadow(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.18),
                      blurRadius: 22,
                      spreadRadius: 2,
                    ),
                  ]
                : hasChar
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
      ),
      child: Center(
        child: hasChar
            ? Text(
                char,
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFF1F5F9),
                ),
              )
            : isFocused
                // Blinking vertical neon cursor
                ? FadeTransition(
                    opacity: _cursorOpacity,
                    child: Container(
                      width: 2,
                      height: 22,
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8),
                        borderRadius: BorderRadius.circular(1),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF38BDF8).withValues(alpha: 0.8),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
      ),
    );
  }
}
