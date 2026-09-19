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

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 3; // Default to Dashboard
  DateTime? lastBackPressed;

  late final List<Widget> _screens;
  final ValueNotifier<String> _semesterNotifier = ValueNotifier("");

  @override
  void initState() {
    super.initState();
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
          backgroundColor: AppColors.cardBg(context),
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
              top: BorderSide(color: AppColors.cardBorder(context), width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(Icons.calendar_today, Icons.calendar_today_outlined, "Timetable", 0),
                  _navItem(Icons.people, Icons.people_outline, "Attendance", 1),
                  _navItem(Icons.menu_book, Icons.menu_book_outlined, "More", 2),
                  _navItem(Icons.dashboard, Icons.dashboard_outlined, "Dashboard", 3),
                  _navItem(Icons.settings, Icons.settings_outlined, "Settings", 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData filledIcon, IconData outlinedIcon, String label, int index) {
    final isSelected = _currentIndex == index;

    return GestureDetector(
      onTap: () {
        if (_currentIndex != index) {
          setState(() => _currentIndex = index);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: EdgeInsets.symmetric(
                  horizontal: isSelected ? 16 : 0,
                  vertical: isSelected ? 6 : 0,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary.withOpacity(0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isSelected ? filledIcon : outlinedIcon,
                  size: 22,
                  color: isSelected ? AppColors.primary : AppColors.textMuted(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? AppColors.primary : AppColors.textMuted(context),
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 2),
              // Indicator dot
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 3,
                width: isSelected ? 16 : 0,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
