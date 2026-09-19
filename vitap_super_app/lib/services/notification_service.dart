import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/note_model.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (details) {},
    );

    final androidImplementation = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> _showNotification(String title, String body, int id) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'vitap_alerts',
      'VTOP Alerts',
      channelDescription: 'Alerts for attendance and academic updates',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  Future<void> checkAttendanceAlerts(List<dynamic> attendanceData) async {
    final prefs = await SharedPreferences.getInstance();
    final alertEnabled = prefs.getBool('attendanceAlert') ?? true;
    if (!alertEnabled) return;

    int lowAttendanceCount = 0;
    for (var course in attendanceData) {
      if (course['percentage'] != null) {
        String percStr = course['percentage'].toString().replaceAll('%', '');
        double? perc = double.tryParse(percStr);
        if (perc != null && perc < 75.0) {
          lowAttendanceCount++;
        }
      }
    }

    if (lowAttendanceCount > 0) {
      await _showNotification(
        'Low Attendance Warning',
        'You have $lowAttendanceCount subject(s) with attendance below 75%.',
        1,
      );
    }
  }

  Future<void> checkMarksAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    final alertEnabled = prefs.getBool('markAlert') ?? false;
    if (!alertEnabled) return;

    await _showNotification(
      'Marks Sync Complete',
      'Marks and grades have been synchronized successfully.',
      2,
    );
  }

  Future<void> cancelTimetableNotifications() async {
    // We use IDs starting from 1000 for timetable
    // However, it's easier to just track and cancel them or just cancel all
    // To be safe and since we don't have other scheduled notifications, we can just cancel all
    // OR we can cancel specific IDs based on slots. Let's cancel all for now since only class reminders are scheduled.
    await _plugin.cancelAll();
  }

  Future<void> scheduleTimetableNotifications(List<dynamic> timetableData) async {
    await cancelTimetableNotifications();

    final prefs = await SharedPreferences.getInstance();
    final alertEnabled = prefs.getBool('classReminderAlert') ?? true;
    if (!alertEnabled) return;

    final delayMinutes = prefs.getInt('classReminderDelay') ?? 10;

    const days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

    for (var item in timetableData) {
      final subject = item["subject"]?.toString();
      final courseCode = item["course_code"]?.toString();
      final timeStr = item["time"]?.toString();
      final dayStr = item["day"]?.toString();
      final room = item["room"]?.toString();

      if (subject == null || timeStr == null || dayStr == null) continue;

      // Exclude Extracurricular/Club slots as they are free hours
      if (subject.toUpperCase().contains("CLUB") || subject.toUpperCase().contains("ECS") || 
          (courseCode != null && (courseCode.toUpperCase().contains("CLUB") || courseCode.toUpperCase().contains("ECS")))) {
        continue;
      }

      int weekday = days.indexWhere((d) => d.toLowerCase() == dayStr.toLowerCase()) + 1; // 1 (Mon) - 7 (Sun)
      if (weekday < 1 || weekday > 7) continue;

      try {
        // Split by '-' to only process the start time
        final startTimeStr = timeStr.split('-')[0].trim().toUpperCase();
        
        final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(startTimeStr);
        if (match == null) continue;
        
        int hour = int.parse(match.group(1)!);
        final minute = int.parse(match.group(2)!);

        if (startTimeStr.contains("PM") && hour < 12) {
          hour += 12;
        } else if (startTimeStr.contains("AM") && hour == 12) {
          hour = 0;
        }

        // Backend now sends proper 24-hour format times, no implicit conversion needed

        final now = tz.TZDateTime.now(tz.local);
        
        // Find next occurrence of this weekday and time
        var scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, 
            now.day + (weekday - now.weekday) % 7, hour, minute);
            
        if (scheduledDate.isBefore(now)) {
            scheduledDate = scheduledDate.add(const Duration(days: 7));
        }
        
        // Subtract delay
        final alertTime = scheduledDate.subtract(Duration(minutes: delayMinutes));

        // Generate unique ID for this slot to avoid overlaps
        final notificationId = 1000 + item.hashCode.abs() % 100000;

        await _plugin.zonedSchedule(
          id: notificationId,
          title: '📅 Class Starting Soon',
          body: 'Your $subject (${courseCode ?? ""}) class begins at $room in $delayMinutes minutes',
          scheduledDate: alertTime,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'class_reminders',
              'Class Reminders',
              channelDescription: 'Notifications for upcoming classes',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexact,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime, // Repeats weekly
        );
      } catch (e) {
        debugPrint('Error scheduling notification: $e');
      }
    }
  }

  // --- Personal Notes Reminders ---

  int _getNoteNotificationId(String noteId) {
    // Generate a consistent ID based on the note ID string
    return 20000 + noteId.hashCode.abs() % 100000;
  }

  Future<void> scheduleNoteReminder(Note note) async {
    if (note.reminderTime == null) return;

    final id = _getNoteNotificationId(note.id);
    
    // Calculate the absolute DateTime
    final now = DateTime.now();
    final scheduledDate = DateTime(
      note.date.year,
      note.date.month,
      note.date.day,
      note.reminderTime!.hour,
      note.reminderTime!.minute,
    );

    // If the scheduled time is in the past, don't schedule
    if (scheduledDate.isBefore(now)) return;

    final tzDate = tz.TZDateTime.from(scheduledDate, tz.local);

    try {
      await _plugin.zonedSchedule(
        id: id,
        title: '📝 Reminder: ${note.title}',
        body: note.description.isNotEmpty ? note.description : 'You have a note scheduled for this time.',
        scheduledDate: tzDate,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'personal_notes',
            'Personal Notes',
            channelDescription: 'Reminders for your personal calendar notes',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: null, // one-off notification
      );
    } catch (e) {
      debugPrint('Error scheduling note reminder: $e');
    }
  }

  Future<void> cancelNoteReminder(String noteId) async {
    final id = _getNoteNotificationId(noteId);
    await _plugin.cancel(id: id);
  }
}

