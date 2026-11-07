import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/theme_manager.dart';
import '../services/logs_service.dart';
import '../services/error_formatter.dart';
import '../services/avatar_service.dart';
import 'login_screen.dart';
import 'logs_screen.dart';
import 'notifications_screen.dart';
import 'avatar_picker_screen.dart';
import '../services/notification_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../services/update_service.dart';

class SettingsScreen extends StatefulWidget {
  final String username;
  final Function(String)? onSemesterChanged;

  const SettingsScreen({super.key, required this.username, this.onSemesterChanged});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool biometricEnabled = false;
  bool isSyncing = false;
  bool obscurePassword = true;
  String currentSemester = "Fetching...";
  bool isChangingSemester = false;
  Map<String, dynamic>? profile;

  @override
  void initState() { 
    super.initState(); 
    _loadPrefs(); 
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    try {
      final data = await ApiService.getProfile(widget.username);
      if (mounted) {
        setState(() {
          profile = data;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      biometricEnabled = prefs.getBool("biometricEnabled") ?? false;
      currentSemester = prefs.getString("semesterName") ?? "Default Semester";
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  void _signOut() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Sign Out", style: TextStyle(color: AppColors.textPrimary(context), fontWeight: FontWeight.w700, fontSize: 18)),
        content: Text("Are you sure you want to sign out? Your cached offline data will be cleared.", style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14)),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel", style: TextStyle(color: AppColors.textSecondary(context), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try { ApiService.logout(widget.username); } catch (_) {}
              CacheService.clear();
              LogsService.add("User signed out: ${widget.username}");
              final prefs = await SharedPreferences.getInstance();
              const storage = FlutterSecureStorage();
              await prefs.remove('username'); 
              await storage.delete(key: 'password');
              await prefs.remove('semesterId'); 
              await prefs.remove('semesterName');
              if (mounted) { 
                Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false); 
              }
            },
            child: const Text("Sign Out"),
          ),
        ],
      ),
    );
  }

  void _showAppQrCode() {
    const String downloadUrl = UpdateService.directApkDownloadUrl;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.cardBg(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Share VTOP Super App",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Scan with your mobile camera to download the APK directly.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context)),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder(context)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: downloadUrl,
                  version: QrVersions.auto,
                  size: 180.0,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text("Copy Link"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary(context),
                        side: BorderSide(color: AppColors.cardBorder(context)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(text: downloadUrl));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.cardBg(context),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            content: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: AppColors.good, size: 20),
                                const SizedBox(width: 10),
                                Text(
                                  "Download link copied to clipboard",
                                  style: TextStyle(color: AppColors.textPrimary(context), fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text("Share"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Share.share(
                          "🚀 Download VTOP Super App (Latest APK):\n$downloadUrl\n\nAccess your timetable, attendance, marks, mess menu & more seamlessly!",
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text("Dismiss", style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeSemester() async {
    setState(() => isChangingSemester = true);
    try {
      final semesters = await ApiService.getSemesters(widget.username);
      if (semesters.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not fetch semesters")));
        setState(() => isChangingSemester = false);
        return;
      }
      if (!mounted) return;
      setState(() => isChangingSemester = false);
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: AppColors.cardBorder(context), width: 1)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textMuted(context).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  "Select Semester",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Choose active academic term to view data for",
                  style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 320,
                  child: ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    itemCount: semesters.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final sem = semesters[index];
                      final isSelected = currentSemester == sem['name'];
                      return InkWell(
                        onTap: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('semesterId', sem['id']);
                          await prefs.setString('semesterName', sem['name']);
                          setState(() => currentSemester = sem['name']);
                          CacheService.clear();
                          LogsService.add("Semester changed to: ${sem['name']}");
                          
                          ApiService.preloadAllData(widget.username, semesterId: sem['id']);
                          
                          if (widget.onSemesterChanged != null) {
                            widget.onSemesterChanged!(sem['id']);
                          }
                          
                          if (mounted) { 
                            Navigator.pop(ctx); 
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text("Active semester set to ${sem['name']}"),
                              behavior: SnackBarBehavior.floating,
                            )); 
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : AppColors.cardBorder(context),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  sem['name'],
                                  style: TextStyle(
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : AppColors.textPrimary(context),
                                    fontSize: 14.5,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle_rounded,
                                    color: Theme.of(context).colorScheme.primary, size: 20),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ErrorFormatter.format(e))));
      setState(() => isChangingSemester = false);
    }
  }

  void _selectTheme() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: AppColors.cardBorder(context), width: 1)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted(context).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              "Appearance",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Customize the visual theme of the app",
              style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
            ),
            const SizedBox(height: 20),
            _themeOption(context, "Light (Clean)", Icons.light_mode_outlined, 'light', const Color(0xFFF7F8FA), const Color(0xFF172554)),
            const SizedBox(height: 10),
            _themeOption(context, "Dark", Icons.dark_mode_outlined, 'dark', const Color(0xFF0F1117), const Color(0xFF7B93C9)),
            const SizedBox(height: 10),
            _themeOption(context, "Nightfall (OLED)", Icons.nights_stay_outlined, 'nightfall', const Color(0xFF080A10), const Color(0xFF8BA3D9)),
            const SizedBox(height: 10),
            _themeOption(context, "Sakura", Icons.spa_outlined, 'sakura', const Color(0xFFFFF7F9), const Color(0xFFE8457C)),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _themeOption(BuildContext context, String title, IconData icon, String themeId, Color bgColor, Color primaryColor) {
    final isSelected = ThemeManager.instance.currentTheme.value == themeId;
    return InkWell(
      onTap: () {
        ThemeManager.instance.setTheme(themeId);
        LogsService.add("Theme changed to: $themeId");
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : AppColors.cardBorder(context),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.cardBorder(context)),
              ),
              child: Center(child: Icon(icon, color: primaryColor, size: 18)),
            ),
            const SizedBox(width: 14),
            Text(
              title,
              style: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : AppColors.textPrimary(context),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14.5,
              ),
            ),
            const Spacer(),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text("Settings"),
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
              // ── Profile Banner ───────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardBg(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder(context), width: 1),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => AvatarPickerSheet.show(
                        context,
                        username: widget.username,
                        name: profile?["name"] ?? widget.username,
                      ),
                      child: ValueListenableBuilder<String?>(
                        valueListenable: AvatarService.instance.avatarNotifier,
                        builder: (context, choice, _) {
                          return AvatarService.buildAvatar(
                            choice: choice,
                            name: profile?["name"] ?? widget.username,
                            size: 52,
                            showBorder: true,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile?["name"] ?? widget.username,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            currentSemester,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.cardBorder(context)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: isChangingSemester ? null : _changeSemester,
                      child: isChangingSemester
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text("Change Sem", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context))),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Account Details ──────────────────────────────────
              _sectionHeader("VTOP Credentials"),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBg(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder(context), width: 1),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.badge_outlined, size: 20, color: AppColors.textSecondary(context)),
                          const SizedBox(width: 14),
                          Text(
                            "Application No",
                            style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context)),
                          ),
                          const Spacer(),
                          Text(
                            widget.username.toUpperCase(),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context)),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, indent: 48, color: AppColors.cardBorder(context)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.textSecondary(context)),
                          const SizedBox(width: 14),
                          Text(
                            "Password",
                            style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context)),
                          ),
                          const Spacer(),
                          Text(
                            obscurePassword ? "••••••••••••" : "Stored securely",
                            style: TextStyle(fontSize: 14, color: AppColors.textPrimary(context), letterSpacing: obscurePassword ? 1.5 : 0),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(
                              obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              size: 18,
                              color: AppColors.textMuted(context),
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => setState(() => obscurePassword = !obscurePassword),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── General Preferences ──────────────────────────────
              _sectionHeader("Preferences"),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBg(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder(context), width: 1),
                ),
                child: Column(
                  children: [
                    _chevronItem(
                      icon: Icons.palette_outlined,
                      title: "Appearance & Theme",
                      onTap: _selectTheme,
                    ),
                    _settingDivider(context),
                    _toggleItem(
                      icon: Icons.fingerprint_rounded,
                      title: "Biometric Unlock",
                      subtitle: "Secure app launch with fingerprint / Face ID",
                      value: biometricEnabled,
                      onChanged: (v) {
                        setState(() => biometricEnabled = v);
                        _saveBool("biometricEnabled", v);
                      },
                    ),
                    _settingDivider(context),
                    _chevronItem(
                      icon: Icons.notifications_none_rounded,
                      title: "Notification Settings",
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── System & Diagnostics ─────────────────────────────
              _sectionHeader("System & Data"),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBg(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder(context), width: 1),
                ),
                child: Column(
                  children: [
                    InkWell(
                      onTap: isSyncing
                          ? null
                          : () async {
                              setState(() => isSyncing = true);
                              LogsService.add("Manual sync started");
                              try {
                                final prefs = await SharedPreferences.getInstance();
                                final semId = prefs.getString('semesterId');
                                CacheService.clear();

                                final keys = prefs.getKeys();
                                final cachePrefixes = ['timetable_', 'marks_', 'grades_', 'profile_', 'curriculum_', 'outing_', 'payments_', 'examtypes_', 'examsched_'];
                                for (var key in keys) {
                                  if (cachePrefixes.any((prefix) => key.startsWith(prefix))) {
                                    await prefs.remove(key);
                                  }
                                }
                                await ApiService.preloadAllData(widget.username, semesterId: semId);

                                try {
                                  final attendanceData = await ApiService.getAttendance(widget.username, semesterId: semId, forceSync: false);
                                  await NotificationService.instance.checkAttendanceAlerts(attendanceData);
                                  await NotificationService.instance.checkMarksAlerts();
                                } catch (_) {}

                                LogsService.add("Manual sync completed successfully");
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("All academic data refreshed from VTOP"),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              } catch (e) {
                                LogsService.add("Manual sync failed: $e");
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Sync failed: ${ErrorFormatter.format(e)}")),
                                  );
                                }
                              }
                              if (mounted) setState(() => isSyncing = false);
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Icon(Icons.sync_rounded, size: 20, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Force Data Sync",
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary(context),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isSyncing ? "Refreshing data from portal..." : "Clear local cache & pull fresh data",
                                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                                  ),
                                ],
                              ),
                            ),
                            if (isSyncing)
                              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            else
                              Icon(Icons.chevron_right_rounded, color: AppColors.textMuted(context), size: 20),
                          ],
                        ),
                      ),
                    ),
                    _settingDivider(context),
                    _chevronItem(
                      icon: Icons.terminal_rounded,
                      title: "Diagnostic Logs",
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LogsScreen())),
                    ),
                    _settingDivider(context),
                    _chevronItem(
                      icon: Icons.qr_code_2_rounded,
                      title: "Share App with Classmates",
                      onTap: _showAppQrCode,
                    ),
                    _settingDivider(context),
                    InkWell(
                      onTap: _signOut,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            const Icon(Icons.logout_rounded, size: 20, color: AppColors.red),
                            const SizedBox(width: 14),
                            const Text(
                              "Sign Out",
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Check for Updates ─────────────────────────────────
              Center(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.system_update_rounded, size: 16),
                  label: const Text("Check for Updates"),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.cardBorder(context)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    foregroundColor: AppColors.textPrimary(context),
                  ),
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                            SizedBox(width: 12),
                            Text("Checking GitHub Releases..."),
                          ],
                        ),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    await UpdateService.checkAndShow(context, isManual: true);
                  },
                ),
              ),

              const SizedBox(height: 20),

              // ── Footer ───────────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    FutureBuilder<String>(
                      future: UpdateService.getCurrentVersion(),
                      builder: (context, snap) {
                        final ver = snap.data ?? UpdateService.fallbackVersion;
                        return Text(
                          "VTOP Super App v$ver",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted(context)),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Designed with care for VIT-AP", style: TextStyle(fontSize: 11, color: AppColors.textMuted(context))),
                      ],
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

  Widget _sectionHeader(String title) {
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

  Widget _toggleItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary(context)),
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
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _chevronItem({required IconData icon, required String title, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textSecondary(context)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textMuted(context)),
          ],
        ),
      ),
    );
  }

  Widget _settingDivider(BuildContext context) => Divider(
        height: 1,
        indent: 48,
        endIndent: 0,
        color: AppColors.cardBorder(context),
      );
}
