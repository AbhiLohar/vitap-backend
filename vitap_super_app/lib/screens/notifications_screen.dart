import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../widgets/glass_card.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool attendanceAlert = true;
  bool examAlert = true;
  bool markAlert = false;
  bool newsAlert = true;
  bool classReminderAlert = true;
  int classReminderDelay = 10;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      attendanceAlert = prefs.getBool("attendanceAlert") ?? true;
      examAlert = prefs.getBool("examAlert") ?? true;
      markAlert = prefs.getBool("markAlert") ?? false;
      newsAlert = prefs.getBool("newsAlert") ?? true;
      classReminderAlert = prefs.getBool("classReminderAlert") ?? true;
      classReminderDelay = prefs.getInt("classReminderDelay") ?? 10;
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Future<void> _rescheduleTimetableNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    final semesterId = prefs.getString('semesterId');
    
    if (username != null && semesterId != null) {
      final cacheKey = 'timetable_${username}_$semesterId';
      final cachedData = prefs.getString(cacheKey);
      if (cachedData != null) {
        final decoded = jsonDecode(cachedData);
        if (decoded is List) {
          await NotificationService.instance.scheduleTimetableNotifications(decoded);
        }
      }
    } else if (!classReminderAlert) {
      await NotificationService.instance.cancelTimetableNotifications();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text("Notifications"),
        backgroundColor: AppColors.scaffoldBg(context),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Academic Alerts",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            GlassCard(
              accentColor: AppColors.primary.withOpacity(0.4),
              margin: EdgeInsets.zero,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _toggleItem(
                    title: "Class Reminders",
                    subtitle: "Notify before class starts",
                    value: classReminderAlert,
                    onChanged: (v) {
                      setState(() => classReminderAlert = v);
                      _saveBool("classReminderAlert", v);
                      _rescheduleTimetableNotifications();
                    },
                    trailing: classReminderAlert
                        ? DropdownButton<int>(
                            value: classReminderDelay,
                            underline: const SizedBox(),
                            icon: const Icon(Icons.arrow_drop_down, size: 20),
                            items: [5, 10, 15, 20, 30].map((int value) {
                              return DropdownMenuItem<int>(
                                value: value,
                                child: Text("$value min", style: TextStyle(fontSize: 13, color: AppColors.textPrimary(context))),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => classReminderDelay = val);
                                _saveInt("classReminderDelay", val);
                                _rescheduleTimetableNotifications();
                              }
                            },
                          )
                        : null,
                  ),
                  _divider(),
                  _toggleItem(
                    title: "Attendance Reminders",
                    subtitle: "Notify when attendance is below 75%",
                    value: attendanceAlert,
                    onChanged: (v) {
                      setState(() => attendanceAlert = v);
                      _saveBool("attendanceAlert", v);
                    },
                  ),
                  _divider(),
                  _toggleItem(
                    title: "Exam Updates",
                    subtitle: "Notify for new exam schedules",
                    value: examAlert,
                    onChanged: (v) {
                      setState(() => examAlert = v);
                      _saveBool("examAlert", v);
                    },
                  ),
                  _divider(),
                  _toggleItem(
                    title: "Marks Released",
                    subtitle: "Notify when new marks are uploaded",
                    value: markAlert,
                    onChanged: (v) {
                      setState(() => markAlert = v);
                      _saveBool("markAlert", v);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "Campus Life",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            GlassCard(
              accentColor: AppColors.primary.withOpacity(0.4),
              margin: EdgeInsets.zero,
              padding: EdgeInsets.zero,
              child: _toggleItem(
                title: "University News",
                subtitle: "General announcements & news",
                value: newsAlert,
                onChanged: (v) {
                  setState(() => newsAlert = v);
                  _saveBool("newsAlert", v);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleItem({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary(context))),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary(context))),
              ],
            ),
          ),
          if (trailing != null) ...[
            trailing,
            const SizedBox(width: 8),
          ],
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(height: 1, indent: 16, color: AppColors.cardBorder(context));
}
