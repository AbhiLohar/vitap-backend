import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';
import 'exam_schedule_screen.dart';
import 'credit_progress_screen.dart';
import 'marks_screen.dart';
import 'grade_history_screen.dart';
import 'gpa_screen.dart';
import 'faculty_search_screen.dart';
import 'digital_assignments_screen.dart';
import 'payments_screen.dart';
import 'vtop_webview_screen.dart';
import 'outing_screen.dart';
import 'course_page_screen.dart';
import 'profile_screen.dart';
import 'mess_menu_screen.dart';

class MoreScreen extends StatefulWidget {
  final String username;
  final ValueNotifier<String>? semesterNotifier;

  const MoreScreen({super.key, required this.username, this.semesterNotifier});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String? _semesterId;

  @override
  void initState() {
    super.initState();
    _loadSemester();
    widget.semesterNotifier?.addListener(_onSemesterChanged);
  }

  @override
  void dispose() {
    widget.semesterNotifier?.removeListener(_onSemesterChanged);
    super.dispose();
  }

  void _onSemesterChanged() {
    if (mounted) {
      _loadSemester();
    }
  }

  Future<void> _loadSemester() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _semesterId = prefs.getString('semesterId');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text("Services & Tools"),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.scaffoldBg(context),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Academic Tools Section ──────────────────────────────
              _sectionHeader(context, "Academic Records & Tools"),
              const SizedBox(height: 8),

              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBg(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder(context), width: 1),
                ),
                child: Column(
                  children: [
                    _menuItem(
                      context,
                      icon: Icons.donut_large_rounded,
                      iconColor: AppColors.good,
                      title: "Credit Progress",
                      subtitle: "Completed, left & basket credits",
                      isFirst: true,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreditProgressScreen(username: widget.username))),
                    ),
                    _divider(context),
                    _menuItem(
                      context,
                      icon: Icons.analytics_outlined,
                      iconColor: AppColors.orange,
                      title: "Marks",
                      subtitle: "Internal, lab & external marks",
                      onTap: () => _navigateToMarks(context),
                    ),
                    _divider(context),
                    _menuItem(
                      context,
                      icon: Icons.person_outline_rounded,
                      iconColor: AppColors.accent,
                      title: "Student Profile",
                      subtitle: "Personal information & proctor details",
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(username: widget.username))),
                    ),
                    _divider(context),
                    _menuItem(
                      context,
                      icon: Icons.history_edu_rounded,
                      iconColor: AppColors.purple,
                      title: "Grade History",
                      subtitle: "Course-wise grades & credits",
                      onTap: () => _navigateToGradeHistory(context),
                    ),
                    _divider(context),
                    _menuItem(
                      context,
                      icon: Icons.show_chart_rounded,
                      iconColor: Theme.of(context).colorScheme.primary,
                      title: "GPA Analytics",
                      subtitle: "Track GPA and CGPA performance",
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GPAScreen(username: widget.username))),
                    ),
                    _divider(context),
                    _menuItem(
                      context,
                      icon: Icons.event_note_rounded,
                      iconColor: AppColors.pink,
                      title: "Exam Schedule",
                      subtitle: "Upcoming exams, slots & venues",
                      onTap: () => _navigateToExamSchedule(context),
                    ),
                    _divider(context),
                    _menuItem(
                      context,
                      icon: Icons.assignment_turned_in_outlined,
                      iconColor: AppColors.orange,
                      title: "Digital Assignments",
                      subtitle: "Status & submission deadlines",
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DigitalAssignmentsScreen(username: widget.username))),
                    ),
                    _divider(context),
                    _menuItem(
                      context,
                      icon: Icons.person_search_rounded,
                      iconColor: AppColors.accent,
                      title: "Faculty Directory",
                      subtitle: "Search faculty emails & cabin numbers",
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FacultySearchScreen(username: widget.username))),
                    ),
                    _divider(context),
                    _menuItem(
                      context,
                      icon: Icons.receipt_long_rounded,
                      iconColor: AppColors.teal,
                      title: "Payments & Fees",
                      subtitle: "Fee receipts & payment transaction records",
                      isLast: true,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentsScreen(username: widget.username))),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Campus & VTOP Section ──────────────────────────────
              _sectionHeader(context, "Campus & Services"),
              const SizedBox(height: 8),

              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBg(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder(context), width: 1),
                ),
                child: Column(
                  children: [
                    _menuItem(
                      context,
                      icon: Icons.menu_book_rounded,
                      iconColor: AppColors.accent,
                      title: "Course Page",
                      subtitle: "Syllabus and reference material",
                      isFirst: true,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CoursePageScreen(username: widget.username))),
                    ),
                    _divider(context),
                    _menuItem(
                      context,
                      icon: Icons.restaurant_rounded,
                      iconColor: AppColors.orange,
                      title: "Mess Menu",
                      subtitle: "Weekly mess menus & dietary updates",
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessMenuScreen())),
                    ),
                    _divider(context),
                    _menuItem(
                      context,
                      icon: Icons.directions_walk_rounded,
                      iconColor: AppColors.good,
                      title: "Outing Management",
                      subtitle: "General & weekend outing leave requests",
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OutingScreen(username: widget.username))),
                    ),
                    _divider(context),
                    _menuItem(
                      context,
                      icon: Icons.open_in_browser_rounded,
                      iconColor: Theme.of(context).colorScheme.primary,
                      title: "VTOP Portal WebView",
                      subtitle: "Open official portal with authenticated session",
                      isLast: true,
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "Official",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VtopWebViewScreen(username: widget.username),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary(context),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _menuItem(
    BuildContext context, {
    required IconData icon,
    Color? iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    bool isFirst = false,
    bool isLast = false,
    required VoidCallback onTap,
  }) {
    final effectiveColor = iconColor ?? Theme.of(context).colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.vertical(
          top: isFirst ? const Radius.circular(16) : Radius.zero,
          bottom: isLast ? const Radius.circular(16) : Radius.zero,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: effectiveColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: effectiveColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context),
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                trailing,
                const SizedBox(width: 6),
              ],
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted(context),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) => Divider(
        height: 1,
        indent: 64,
        endIndent: 0,
        color: AppColors.cardBorder(context),
      );

  void _navigateToMarks(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MarksScreen(username: widget.username),
      ),
    );
  }

  void _navigateToGradeHistory(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GradeHistoryScreen(username: widget.username),
      ),
    );
  }

  void _navigateToExamSchedule(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExamScheduleScreen(username: widget.username),
      ),
    );
  }
}
