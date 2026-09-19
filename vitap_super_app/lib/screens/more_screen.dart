import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';
import '../widgets/glass_card.dart';
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
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with gradient
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.primary.withOpacity(0.04),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Column(
                        children: [
                          Text("More",
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary(context),
                                  letterSpacing: -0.3)),
                          const SizedBox(height: 2),
                          Text("Academic tools & VTOP links",
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary(context))),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Academic Tools
                _sectionTitle(context, "Academic Tools", Icons.school_outlined),
                const SizedBox(height: 8),

                GlassCard(
                  accentColor: AppColors.primary.withOpacity(0.4),
                  margin: EdgeInsets.zero,
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    _menuItem(context,
                        icon: Icons.trending_up_outlined,
                        iconColor: AppColors.teal,
                        title: "Credit Progress",
                        subtitle: "View completed, left & total credits",
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreditProgressScreen(username: widget.username)))),
                    _divider(context),
                    _menuItem(context,
                        icon: Icons.assignment_outlined,
                        iconColor: AppColors.orange,
                        title: "Marks",
                        subtitle: "View your internal & external marks",
                        onTap: () => _navigateToMarks(context)),
                    _divider(context),
                    _menuItem(context,
                        icon: Icons.person_outline,
                        iconColor: AppColors.teal,
                        title: "Student Profile",
                        subtitle: "View your profile and mentor details",
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(username: widget.username)))),
                    _divider(context),
                    _menuItem(context,
                        icon: Icons.history,
                        iconColor: AppColors.purple,
                        title: "Grade History",
                        subtitle: "View complete grade history",
                        onTap: () => _navigateToGradeHistory(context)),
                    _divider(context),
                    _menuItem(context,
                        icon: Icons.show_chart,
                        iconColor: AppColors.accent,
                        title: "GPA Analytics",
                        subtitle: "Track your GPA performance",
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GPAScreen(username: widget.username)))),
                    _divider(context),
                    _menuItem(context,
                        icon: Icons.event_note_outlined,
                        iconColor: AppColors.pink,
                        title: "Exam Schedule",
                        subtitle: "View your upcoming exams",
                        onTap: () => _navigateToExamSchedule(context)),
                    _divider(context),
                    _menuItem(context,
                        icon: Icons.assignment_turned_in_outlined,
                        iconColor: AppColors.orange,
                        title: "Digital Assignments",
                        subtitle: "View & check DA status",
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DigitalAssignmentsScreen(username: widget.username)))),
                    _divider(context),
                    _menuItem(context,
                        icon: Icons.person_search_outlined,
                        iconColor: AppColors.accent,
                        title: "Faculty Search",
                        subtitle: "Find faculty details & rooms",
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FacultySearchScreen(username: widget.username)))),
                    _divider(context),
                    _menuItem(context,
                        icon: Icons.receipt_long_outlined,
                        iconColor: AppColors.primary,
                        title: "Payments",
                        subtitle: "View fee receipts & history",
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentsScreen(username: widget.username)))),
                  ]),
                ),

                const SizedBox(height: 24),

                // VTOP section
                _sectionTitle(context, "VTOP & Campus", Icons.language_outlined),
                const SizedBox(height: 8),

                GlassCard(
                  accentColor: AppColors.accent.withOpacity(0.4),
                  margin: EdgeInsets.zero,
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    _menuItem(context,
                        icon: Icons.description_outlined,
                        iconColor: AppColors.accent,
                        title: "Course Page",
                        subtitle: "View course details for current sem",
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CoursePageScreen(username: widget.username)))),
                    _divider(context),
                    _menuItem(context,
                        icon: Icons.restaurant_menu_outlined,
                        iconColor: AppColors.orange,
                        title: "Mess Menu",
                        subtitle: "View daily mess menu & upload schedules",
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessMenuScreen()))),
                    _divider(context),
                    _menuItem(context,
                        icon: Icons.directions_walk_outlined,
                        iconColor: AppColors.teal,
                        title: "Outing Status",
                        subtitle: "Check your outing/leave history",
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OutingScreen(username: widget.username)))),
                    _divider(context),
                    _menuItem(context,
                        icon: Icons.open_in_browser,
                        iconColor: AppColors.primary,
                        title: "VTOP WebView",
                        subtitle: "Open VTOP portal with auto-login",
                          trailing: _externalBadge(context),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VtopWebViewScreen(username: widget.username),
                              ),
                            );
                          }),
                  ]),
                ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context))),
      ],
    );
  }

  Widget _externalBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.open_in_new, size: 10, color: AppColors.accent),
          const SizedBox(width: 3),
          Text("External",
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              )),
        ],
      ),
    );
  }


  Widget _menuItem(BuildContext context,
      {required IconData icon,
      Color? iconColor,
      required String title,
      required String subtitle,
      Widget? trailing,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (iconColor ?? AppColors.textSecondary(context)).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor ?? AppColors.textSecondary(context)),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary(context))),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary(context))),
              ])),
          if (trailing != null) ...[
            trailing,
            const SizedBox(width: 6),
          ],
          Icon(Icons.chevron_right,
              color: AppColors.textMuted(context), size: 20),
        ]),
      ),
    );
  }

  Widget _divider(BuildContext context) =>
      Divider(height: 1, indent: 60, color: AppColors.cardBorder(context));

  void _openUrl(String title, String url) async {
    final uri = Uri.parse(url);
    try {
      // Try inAppBrowserView first, fall back to external browser
      final launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!launched) {
        // Fallback to external browser
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // Last fallback: try external application
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e2) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Could not open $title: $e2")));
      }
    }
  }

  void _navigateToMarks(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MarksScreen(username: widget.username),
      ),
    );
  }

  void _navigateToGrades(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GradeHistoryScreen(username: widget.username),
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
            builder: (_) => ExamScheduleScreen(username: widget.username)));
  }
}



// Generic data list screen
class _DataListScreen extends StatefulWidget {
  final String title;
  final Future<List> Function(bool forceSync) fetchFunction;
  final Widget Function(Map<String, dynamic> item) cardBuilder;

  const _DataListScreen({
    required this.title,
    required this.fetchFunction,
    required this.cardBuilder,
  });

  @override
  State<_DataListScreen> createState() => _DataListScreenState();
}

class _DataListScreenState extends State<_DataListScreen> {
  late Future<List> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.fetchFunction(false);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.fetchFunction(true);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(title: Text(widget.title), backgroundColor: AppColors.scaffoldBg(context)),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.primary,
        child: FutureBuilder<List>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary));
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                  Icon(Icons.inbox_outlined,
                      size: 48, color: AppColors.textMuted(context)),
                  const SizedBox(height: 12),
                  Center(
                    child: Text("No ${widget.title} data available",
                        style: TextStyle(color: AppColors.textSecondary(context))),
                  ),
                ],
              );
            }
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()
              ),
              padding: const EdgeInsets.all(16),
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.cardBorder(context)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: widget.cardBuilder(Map<String, dynamic>.from(snapshot.data![index])),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
