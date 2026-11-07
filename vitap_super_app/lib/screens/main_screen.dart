import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_theme.dart';
import 'timetable_screen.dart';
import 'attendance_screen.dart';
import 'more_screen.dart';
import 'home_dashboard_screen.dart';
import 'settings_screen.dart';
import '../services/api_service.dart';
import '../services/update_service.dart';
import '../widgets/otp_dialog.dart';

class MainScreen extends StatefulWidget {
  final String username;

  const MainScreen({super.key, required this.username});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 3; // Default to Dashboard
  DateTime? lastBackPressed;

  late final List<Widget> _screens;
  final ValueNotifier<String> _semesterNotifier = ValueNotifier("");

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ApiService.onOtpRequired = () => showReAuthOtpDialog(context);
    _screens = [
      TimetableScreen(username: widget.username, semesterNotifier: _semesterNotifier),
      AttendanceScreen(username: widget.username, semesterNotifier: _semesterNotifier),
      MoreScreen(username: widget.username, semesterNotifier: _semesterNotifier),
      HomeDashboardScreen(username: widget.username),
      SettingsScreen(
        username: widget.username,
        onSemesterChanged: (newId) {
          _semesterNotifier.value = newId;
        },
      ),
    ];

    // Check for updates smoothly in the background on app launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkAndShow(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _semesterNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      UpdateService.checkAndShow(context);
    }
  }

  Future<bool> _onWillPop() async {
    if (_currentIndex != 3) {
      setState(() => _currentIndex = 3); // Back goes to Dashboard
      return false;
    }

    final now = DateTime.now();
    if (lastBackPressed == null ||
        now.difference(lastBackPressed!) > const Duration(seconds: 2)) {
      lastBackPressed = now;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Press back again to exit"),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = Theme.of(context).colorScheme.primary;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: AppColors.cardBg(context),
            border: Border(
              top: BorderSide(
                color: AppColors.cardBorder(context),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.15,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    _navItem(Icons.calendar_today, Icons.calendar_today_outlined, "Timetable", 0, activeColor),
                    _navItem(Icons.people, Icons.people_outline, "Attendance", 1, activeColor),
                    _navItem(Icons.menu_book, Icons.menu_book_outlined, "More", 2, activeColor),
                    _navItem(Icons.home_rounded, Icons.home_outlined, "Home", 3, activeColor),
                    _navItem(Icons.settings, Icons.settings_outlined, "Settings", 4, activeColor),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData filledIcon, IconData outlinedIcon, String label, int index, Color activeColor) {
    final isSelected = _currentIndex == index;
    final inactiveColor = AppColors.textMuted(context);

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_currentIndex != index) {
            HapticFeedback.selectionClick();
            setState(() => _currentIndex = index);
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              padding: EdgeInsets.symmetric(
                horizontal: isSelected ? 16 : 0,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: isSelected ? activeColor.withOpacity(0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isSelected ? filledIcon : outlinedIcon,
                size: 22,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? activeColor : inactiveColor,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
