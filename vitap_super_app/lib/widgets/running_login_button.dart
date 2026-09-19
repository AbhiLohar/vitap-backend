import 'dart:math';
import 'package:flutter/material.dart';

enum LoginButtonStatus {
  idle,
  running,
  entering,
  failed,
}

class RunningLoginButtonController extends ChangeNotifier {
  LoginButtonStatus _status = LoginButtonStatus.idle;
  String _statusMessage = "Connecting to VTOP...";
  VoidCallback? _onEnterComplete;

  LoginButtonStatus get status => _status;
  String get statusMessage => _statusMessage;

  void startRunning({String message = "Connecting to VTOP..."}) {
    _status = LoginButtonStatus.running;
    _statusMessage = message;
    notifyListeners();
  }

  void updateMessage(String message) {
    _statusMessage = message;
    notifyListeners();
  }

  void enterRoom({required VoidCallback onComplete}) {
    // Guard against duplicate invocations
    if (_status == LoginButtonStatus.entering) return;
    _status = LoginButtonStatus.entering;
    _onEnterComplete = onComplete;
    notifyListeners();
  }

  void fail() {
    _status = LoginButtonStatus.failed;
    notifyListeners();
  }

  void reset() {
    _status = LoginButtonStatus.idle;
    _onEnterComplete = null;
    notifyListeners();
  }

  void _triggerEnterComplete() {
    _onEnterComplete?.call();
  }
}

class RunningLoginButton extends StatefulWidget {
  final RunningLoginButtonController controller;
  final VoidCallback onPressed;
  final String label;

  const RunningLoginButton({
    super.key,
    required this.controller,
    required this.onPressed,
    this.label = "Sign In",
  });

  @override
  State<RunningLoginButton> createState() => _RunningLoginButtonState();
}

class _RunningLoginButtonState extends State<RunningLoginButton>
    with TickerProviderStateMixin {
  late AnimationController _runLoopController;
  late AnimationController _enterController;
  late AnimationController _failController;

  LoginButtonStatus _lastStatus = LoginButtonStatus.idle;

  @override
  void initState() {
    super.initState();

    // Continuous running sprint cycle (~620ms per stride cycle)
    _runLoopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..repeat();

    // Enter room animation (door swings open, runner dashes in, door shuts)
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );
    _enterController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.controller._triggerEnterComplete();
      }
    });

    // Fail skid animation (runner slides to stop, door flashes red)
    _failController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _failController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) {
            widget.controller.reset();
          }
        });
      }
    });

    widget.controller.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    final status = widget.controller.status;

    // Only handle state changes once to avoid duplicate triggers / animation restarts
    if (status != _lastStatus) {
      _lastStatus = status;

      if (status == LoginButtonStatus.running) {
        if (!_runLoopController.isAnimating) {
          _runLoopController.repeat();
        }
        _enterController.reset();
        _failController.reset();
      } else if (status == LoginButtonStatus.entering) {
        // Run entering sequence strictly once from 0.0
        _enterController.forward(from: 0.0);
      } else if (status == LoginButtonStatus.failed) {
        _runLoopController.stop();
        _failController.forward(from: 0.0);
      } else if (status == LoginButtonStatus.idle) {
        // Do NOT reset _enterController immediately so AnimatedSwitcher can smoothly
        // cross-fade without popping the runner back to start during the exit animation.
        Future.delayed(const Duration(milliseconds: 320), () {
          if (mounted && widget.controller.status == LoginButtonStatus.idle) {
            _enterController.reset();
            _failController.reset();
            if (!_runLoopController.isAnimating) {
              _runLoopController.repeat();
            }
          }
        });
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _runLoopController.dispose();
    _enterController.dispose();
    _failController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.controller.status;
    final isIdle = status == LoginButtonStatus.idle;

    return SizedBox(
      height: 56,
      width: double.infinity,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: isIdle ? _buildIdleButton() : _buildAnimatedStage(),
      ),
    );
  }

  Widget _buildIdleButton() {
    return Container(
      key: const ValueKey("idle_button"),
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF7C4DFF),
            Color(0xFF651FFF),
            Color(0xFF00E5FF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C4DFF).withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: widget.onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.login_rounded,
              size: 20,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedStage() {
    return Container(
      key: const ValueKey("animated_stage"),
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1322),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.controller.status == LoginButtonStatus.failed
              ? const Color(0xFFFF5252).withValues(alpha: 0.8)
              : const Color(0xFF7C4DFF).withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.controller.status == LoginButtonStatus.failed
                ? const Color(0xFFFF5252).withValues(alpha: 0.25)
                : const Color(0xFF00E5FF).withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            // Custom Painted Running Scene
            Positioned.fill(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _runLoopController,
                  _enterController,
                  _failController,
                ]),
                builder: (context, child) {
                  return CustomPaint(
                    painter: _RunnerScenePainter(
                      status: widget.controller.status,
                      runCycle: _runLoopController.value,
                      enterProgress: _enterController.value,
                      failProgress: _failController.value,
                    ),
                  );
                },
              ),
            ),

            // Subtle Status Subtitle Overlay
            Positioned(
              left: 18,
              top: 7,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: widget.controller.status == LoginButtonStatus.failed
                    ? 0.0
                    : 0.85,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF00E5FF),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF00E5FF),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.controller.statusMessage,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB0BEC5),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunnerScenePainter extends CustomPainter {
  final LoginButtonStatus status;
  final double runCycle; // 0.0 to 1.0 (looping)
  final double enterProgress; // 0.0 to 1.0
  final double failProgress; // 0.0 to 1.0

  _RunnerScenePainter({
    required this.status,
    required this.runCycle,
    required this.enterProgress,
    required this.failProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Generous floor placement leaving over 13px of headroom at top
    final yGround = size.height - 11.0;

    // 1. Draw track floor and speed lines
    _drawTrack(canvas, size, yGround);

    // 2. Draw the Doorway / Room on the right side
    final doorX = size.width - 36.0;
    _drawDoorAndRoom(canvas, size, doorX, yGround);

    // 3. Draw the Runner Character with scaled headroom
    _drawRunner(canvas, size, doorX, yGround);
  }

  void _drawTrack(Canvas canvas, Size size, double yGround) {
    // Glowing neon ground line
    final groundPaint = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, yGround), Offset(size.width, yGround), groundPaint);

    final neonGroundPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0x007C4DFF),
          Color(0x8000E5FF),
          Color(0x507C4DFF),
        ],
      ).createShader(Rect.fromLTWH(0, yGround - 1, size.width, 2))
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(0, yGround), Offset(size.width, yGround), neonGroundPaint);

    // Speed dashes on ground if running
    if (status == LoginButtonStatus.running || status == LoginButtonStatus.entering) {
      final dashSpeed = (runCycle * 36.0);
      final dashPaint = Paint()
        ..color = const Color(0x6000E5FF)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;

      for (double x = size.width; x >= 0; x -= 32) {
        final dashX = (x - dashSpeed) % size.width;
        if (dashX > 15 && dashX < size.width - 50) {
          canvas.drawLine(
            Offset(dashX, yGround + 3.5),
            Offset(dashX - 9, yGround + 3.5),
            dashPaint,
          );
        }
      }
    }
  }

  void _drawDoorAndRoom(Canvas canvas, Size size, double doorX, double yGround) {
    const doorW = 20.0;
    const doorH = 28.0;
    final doorTop = yGround - doorH;
    final doorRect = Rect.fromLTWH(doorX - doorW / 2, doorTop, doorW, doorH);

    // Calculate door open angle (0.0 = closed, 1.0 = wide open)
    double doorOpen = 0.0;
    if (status == LoginButtonStatus.entering) {
      if (enterProgress < 0.35) {
        // Door swings open as runner approaches
        doorOpen = (enterProgress / 0.35).clamp(0.0, 1.0);
        doorOpen = Curves.easeOutCubic.transform(doorOpen);
      } else if (enterProgress < 0.70) {
        // Door remains open while runner enters
        doorOpen = 1.0;
      } else if (enterProgress <= 1.0) {
        // Door shuts behind runner
        final closeProg = ((enterProgress - 0.70) / 0.25).clamp(0.0, 1.0);
        doorOpen = 1.0 - Curves.bounceOut.transform(closeProg);
      }
    }

    // A. Room Interior Glow Beam (spills out onto floor when door opens)
    if (doorOpen > 0.02) {
      final lightSpread = 45.0 * doorOpen;
      final lightPath = Path()
        ..moveTo(doorX - doorW / 2 + 2, doorTop + 3)
        ..lineTo(doorX - doorW / 2 - lightSpread, yGround)
        ..lineTo(doorX + doorW / 2, yGround)
        ..lineTo(doorX + doorW / 2 - 2, doorTop + 3)
        ..close();

      final lightPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [
            const Color(0xFF00E5FF).withValues(alpha: 0.45 * doorOpen),
            const Color(0xFF7C4DFF).withValues(alpha: 0.18 * doorOpen),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(doorX - lightSpread - 4, doorTop, lightSpread + 8, doorH + 6));

      canvas.drawPath(lightPath, lightPaint);
    }

    // B. Inside the Doorway (Glowing room portal)
    final insideRRect = RRect.fromRectAndRadius(doorRect, const Radius.circular(4));
    final insidePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: doorOpen > 0.05
            ? const [
                Color(0xFF00E5FF),
                Color(0xFF7C4DFF),
              ]
            : const [
                Color(0xFF1E293B),
                Color(0xFF0F172A),
              ],
      ).createShader(doorRect);
    canvas.drawRRect(insideRRect, insidePaint);

    // C. Door Frame Outer Border
    final framePaint = Paint()
      ..color = status == LoginButtonStatus.failed
          ? const Color(0xFFFF5252)
          : const Color(0xFF475569)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(insideRRect, framePaint);

    // D. The 3D Swinging Door Panel
    final hingeX = doorX + doorW / 2;
    final swingX = (doorX - doorW / 2) + (doorW * 0.85 * doorOpen);
    final swingTop = doorTop + (1.8 * doorOpen);
    final swingBottom = yGround - (1.8 * doorOpen);

    final panelPath = Path()
      ..moveTo(swingX, swingTop)
      ..lineTo(hingeX, doorTop)
      ..lineTo(hingeX, yGround)
      ..lineTo(swingX, swingBottom)
      ..close();

    final panelPaint = Paint()
      ..color = status == LoginButtonStatus.failed
          ? const Color(0xFF2A1520)
          : const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;
    canvas.drawPath(panelPath, panelPaint);

    final panelBorderPaint = Paint()
      ..color = status == LoginButtonStatus.failed
          ? const Color(0xFFFF5252).withValues(alpha: 0.9)
          : const Color(0xFF64748B)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(panelPath, panelBorderPaint);

    // Door knob / handle
    if (doorOpen < 0.7) {
      final knobX = swingX + (hingeX - swingX) * 0.25;
      final knobY = doorTop + doorH * 0.55;
      final knobPaint = Paint()
        ..color = status == LoginButtonStatus.failed
            ? const Color(0xFFFF5252)
            : const Color(0xFFFFD54F)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(knobX, knobY), 1.6, knobPaint);
    }

    // Success lock flash on closed door after enter
    if (status == LoginButtonStatus.entering && enterProgress > 0.85) {
      final pulse = ((enterProgress - 0.85) / 0.15).clamp(0.0, 1.0);
      final checkPaint = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: (1.0 - pulse) * 0.9)
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      // Draw checkmark on door
      final checkPath = Path()
        ..moveTo(doorX - 3.5, doorTop + doorH * 0.52)
        ..lineTo(doorX - 0.8, doorTop + doorH * 0.57)
        ..lineTo(doorX + 4.5, doorTop + doorH * 0.45);
      canvas.drawPath(checkPath, checkPaint);
    }

    // Top indicator portal light above door
    final lampPaint = Paint()
      ..color = status == LoginButtonStatus.failed
          ? const Color(0xFFFF5252)
          : (doorOpen > 0.2 ? const Color(0xFF00E5FF) : const Color(0xFF64748B))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(doorX, doorTop - 3.0), 1.8, lampPaint);
  }

  void _drawRunner(Canvas canvas, Size size, double doorX, double yGround) {
    // Determine Runner X position based on state
    double runnerX;
    double runnerOpacity = 1.0;

    if (status == LoginButtonStatus.running) {
      // Runner runs steadily across middle lane
      runnerX = size.width * 0.35 + sin(runCycle * 2 * pi) * 3.5;
    } else if (status == LoginButtonStatus.entering) {
      // Runner sprints from mid lane straight into the doorway
      final startX = size.width * 0.35;
      final targetX = doorX;
      if (enterProgress < 0.70) {
        final t = Curves.easeInOutCubic.transform(enterProgress / 0.70);
        runnerX = startX + (targetX - startX) * t;
      } else {
        runnerX = targetX;
        // Dissolves into room light smoothly
        final fadeT = ((enterProgress - 0.65) / 0.15).clamp(0.0, 1.0);
        runnerOpacity = (1.0 - fadeT).clamp(0.0, 1.0);
      }
    } else if (status == LoginButtonStatus.failed) {
      // Runner skids forward slightly to a stop
      final skidT = Curves.easeOutQuad.transform(failProgress);
      runnerX = size.width * 0.35 + 18.0 * skidT;
    } else {
      runnerX = size.width * 0.35;
    }

    if (runnerOpacity <= 0.01) return;

    // Dynamic kinematics scaled gracefully with plenty of headroom
    final theta = runCycle * 2 * pi;
    final isSkidding = status == LoginButtonStatus.failed;

    // Gentle bounce (1.6px max)
    final bounce = isSkidding
        ? 0.0
        : -sin(theta * 2).abs() * 1.6;

    final hipX = runnerX;
    // Base hip at yGround - 13.0 leaves over 13px clearance above the head
    final hipY = yGround - 13.0 + bounce;

    // Forward torso lean (increases during sprint / enter)
    final lean = isSkidding ? -0.2 : (status == LoginButtonStatus.entering ? 0.32 : 0.22);
    const torsoLen = 10.0;
    final neckX = hipX + sin(lean) * torsoLen;
    final neckY = hipY - cos(lean) * torsoLen;

    const headDist = 3.8;
    const headRadius = 3.4;
    final headX = neckX + sin(lean) * headDist;
    final headY = neckY - cos(lean) * headDist;

    // Colors
    final primaryColor = Colors.white.withValues(alpha: runnerOpacity);
    final farLimbColor = const Color(0xFF81D4FA).withValues(alpha: runnerOpacity * 0.65);

    final linePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final farLinePaint = Paint()
      ..color = farLimbColor
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Legs Kinematics (compact, athletic)
    const thighLen = 6.8;
    const calfLen = 6.8;

    void drawLeg(double phase, Paint paint) {
      if (isSkidding) {
        // Both legs brace forward for a slide stop
        final isFront = phase == theta;
        final legAngle = isFront ? 0.60 : 0.38;
        final kX = hipX + sin(legAngle) * thighLen;
        final kY = hipY + cos(legAngle) * thighLen;
        final fX = kX + sin(legAngle + 0.25) * calfLen;
        final fY = min(yGround, kY + cos(legAngle + 0.25) * calfLen);

        canvas.drawLine(Offset(hipX, hipY), Offset(kX, kY), paint);
        canvas.drawLine(Offset(kX, kY), Offset(fX, fY), paint);
        canvas.drawLine(Offset(fX, fY), Offset(fX + 2.5, fY), paint);
        return;
      }

      // Fluid kinematic cycle
      final hipAngle = sin(phase) * 0.70 + 0.12;
      final kX = hipX + sin(hipAngle) * thighLen;
      final kY = hipY + cos(hipAngle) * thighLen;

      final kneeBend = max(0.1, sin(phase - 0.5) * 0.9 + 0.45);
      final ankleAngle = hipAngle - kneeBend;
      final fX = kX + sin(ankleAngle) * calfLen;
      final fY = min(yGround, kY + cos(ankleAngle) * calfLen);

      canvas.drawLine(Offset(hipX, hipY), Offset(kX, kY), paint);
      canvas.drawLine(Offset(kX, kY), Offset(fX, fY), paint);
      // Foot stroke
      canvas.drawLine(Offset(fX, fY), Offset(fX + 2.8, fY), paint);
    }

    // Arms Kinematics
    const armLen1 = 5.5;
    const armLen2 = 5.0;

    void drawArm(double phase, Paint paint) {
      if (isSkidding) {
        const armAngle = -0.65;
        final eX = neckX + sin(armAngle) * armLen1;
        final eY = neckY + cos(armAngle) * armLen1;
        final hX = eX + sin(armAngle - 0.35) * armLen2;
        final hY = eY + cos(armAngle - 0.35) * armLen2;
        canvas.drawLine(Offset(neckX, neckY), Offset(eX, eY), paint);
        canvas.drawLine(Offset(eX, eY), Offset(hX, hY), paint);
        return;
      }

      final armAngle = sin(phase) * 0.70 - 0.2;
      final eX = neckX + sin(armAngle) * armLen1;
      final eY = neckY + cos(armAngle) * armLen1;

      const forearmAngleOffset = 1.25;
      final fAngle = armAngle + forearmAngleOffset;
      final hX = eX + sin(fAngle) * armLen2;
      final hY = eY + cos(fAngle) * armLen2;

      canvas.drawLine(Offset(neckX, neckY), Offset(eX, eY), paint);
      canvas.drawLine(Offset(eX, eY), Offset(hX, hY), paint);
    }

    // Draw Far Arm & Far Leg (layered behind body)
    drawArm(theta, farLinePaint);
    drawLeg(theta + pi, farLinePaint);

    // Torso Spine
    canvas.drawLine(Offset(hipX, hipY), Offset(neckX, neckY), linePaint);

    // Head (with ample clearance from the top border)
    final headPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(headX, headY), headRadius, headPaint);

    // Speed visor accent
    final visorPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: runnerOpacity)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(headX - 0.8, headY - 1.2),
      Offset(headX + 3.8, headY - 0.8),
      visorPaint,
    );

    // Draw Near Leg & Near Arm (layered in front)
    drawLeg(theta, linePaint);
    drawArm(theta + pi, linePaint);

    // Speed wind trail behind runner
    if (!isSkidding && runnerOpacity > 0.4) {
      final trailPaint = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.35 * runnerOpacity)
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(hipX - 5.0, hipY - 1.5),
        Offset(hipX - 15.0, hipY - 1.5),
        trailPaint,
      );
      canvas.drawLine(
        Offset(neckX - 6.0, neckY + 1.5),
        Offset(neckX - 18.0, neckY + 1.5),
        trailPaint,
      );
    }

    // Skid marks & Surprise "!" on failure
    if (isSkidding) {
      // Smoke / skid particles
      final skidPaint = Paint()
        ..color = const Color(0xFFFF5252).withValues(alpha: 0.6)
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(hipX - 11.0, yGround - 1),
        Offset(hipX + 2.0, yGround - 1),
        skidPaint,
      );

      // Exclamation Mark above head
      final alertPaint = Paint()
        ..color = const Color(0xFFFF5252)
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(headX + 7.0, headY - 11.0),
        Offset(headX + 7.0, headY - 6.0),
        alertPaint,
      );
      canvas.drawCircle(Offset(headX + 7.0, headY - 3.5), 1.0, alertPaint..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant _RunnerScenePainter oldDelegate) {
    return oldDelegate.runCycle != runCycle ||
        oldDelegate.enterProgress != enterProgress ||
        oldDelegate.failProgress != failProgress ||
        oldDelegate.status != status;
  }
}
