import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../services/error_formatter.dart';
import '../services/avatar_service.dart';
import '../widgets/glass_card.dart';
import 'attendance_screen.dart';
import 'timetable_screen.dart';
import 'digital_assignments_screen.dart';
import 'exam_schedule_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'login_screen.dart';
import 'credit_progress_screen.dart';
import 'mess_menu_screen.dart';
import '../services/mess_menu_service.dart';

class HomeDashboardScreen extends StatefulWidget {
  final String username;
  const HomeDashboardScreen({super.key, required this.username});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  Map<String, dynamic>? profile;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (mounted && profile == null) setState(() => isLoading = true);
    try {
      final p = await ApiService.getProfile(
        widget.username,
        forceSync: forceRefresh,
        onSync: (freshData) {
          if (mounted) setState(() { profile = freshData; isLoading = false; });
        }
      );
      if (mounted) {
        setState(() {
          profile = p;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(
            children: [
              const Icon(Icons.wifi_off_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ErrorFormatter.format(e),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ));
      }
    }
  }

  void _showProfileMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: AppColors.cardBg(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted(context).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text('Profile', style: TextStyle(color: AppColors.textPrimary(context))),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen(username: widget.username)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text('Settings', style: TextStyle(color: AppColors.textPrimary(context))),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => SettingsScreen(username: widget.username, onSemesterChanged: (_) {})));
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Logout', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(context);
                  ApiService.logout(widget.username); // fire and forget
                  final prefs = await SharedPreferences.getInstance();
                  const storage = FlutterSecureStorage();
                  await prefs.remove('username'); 
                  await storage.delete(key: 'password');
                  await prefs.remove('semesterId'); 
                  await prefs.remove('semesterName');
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                      (route) => false,
                    );
                  }
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadData(forceRefresh: true),
          color: AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Welcome back,",
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            profile?["name"] ?? widget.username,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => _showProfileMenu(context),
                        child: ValueListenableBuilder<String?>(
                          valueListenable: AvatarService.instance.avatarNotifier,
                          builder: (context, choice, _) {
                            return AvatarService.buildAvatar(
                              choice: choice,
                              name: profile?["name"] ?? widget.username,
                              size: 42,
                              showBorder: false,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Quick Stats / Highlights
                  Row(
                    children: [
                      Expanded(
                        child: _buildHighlightCard(
                          context,
                          title: "Attendance",
                          subtitle: "Check Status",
                          icon: Icons.check_circle_outline,
                          color: AppColors.teal,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceScreen(username: widget.username))),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildHighlightCard(
                          context,
                          title: "Timetable",
                          subtitle: "Today's Classes",
                          icon: Icons.calendar_view_day,
                          color: AppColors.orange,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TimetableScreen(username: widget.username))),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildHighlightCard(
                          context,
                          title: "Assignments",
                          subtitle: "Pending DAs",
                          icon: Icons.assignment_outlined,
                          color: AppColors.purple,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DigitalAssignmentsScreen(username: widget.username))),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildHighlightCard(
                          context,
                          title: "Exams",
                          subtitle: "Schedule",
                          icon: Icons.event_note_outlined,
                          color: AppColors.pink,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExamScheduleScreen(username: widget.username))),
                        ),
                      ),
                    ],
                  ),
                  
                  // Next Meal Preview Card
                  const SizedBox(height: 16),
                  FutureBuilder<Map<String, dynamic>>(
                    future: MessMenuService.getUpcomingMeal('special'),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || (snapshot.data!['items'] as List).isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final data = snapshot.data!;
                      final meal = data['meal'] as String;
                      final items = List<String>.from(data['items'] as List);
                      final emoji = MessMenuService.mealEmoji[meal] ?? '🍽️';
                      final time = MessMenuService.mealTimeDisplay[meal] ?? '';
                      final previewItems = items.take(4).toList();
                      return GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessMenuScreen())),
                        child: GlassCard(
                          accentColor: AppColors.orange.withOpacity(0.5),
                          margin: EdgeInsets.zero,
                          child: Row(
                            children: [
                              Text(emoji, style: const TextStyle(fontSize: 32)),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(meal, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
                                        const SizedBox(width: 8),
                                        Text(time, style: TextStyle(fontSize: 11, color: AppColors.textMuted(context))),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      previewItems.join(' • '),
                                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right, color: AppColors.textMuted(context)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  Text(
                    "Overview",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  GlassCard(
                    accentColor: AppColors.primary.withOpacity(0.2),
                    child: Column(
                      children: [
                        const Icon(Icons.insights, size: 48, color: AppColors.primary),
                        const SizedBox(height: 16),
                        Text(
                          "Your academic journey at a glance.",
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.textSecondary(context),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CreditProgressScreen(username: widget.username),
                                ),
                              );
                            },
                            child: const Text("View Analytics", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightCard(BuildContext context, {required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.cardBorder(context)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 4),
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
    );
  }
}
