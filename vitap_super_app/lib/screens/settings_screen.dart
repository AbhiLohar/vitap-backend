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
import '../widgets/glass_card.dart';
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text("Sign Out", style: TextStyle(color: AppColors.textPrimary(context))),
        content: Text("Are you sure you want to sign out?", style: TextStyle(color: AppColors.textSecondary(context))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel", style: TextStyle(color: AppColors.textMuted(context)))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try { ApiService.logout(widget.username); } catch (_) {}
              CacheService.clear();
              LogsService.add("User signed out: ${widget.username}");
              final prefs = await SharedPreferences.getInstance();
              const storage = FlutterSecureStorage();
              await prefs.remove('username'); 
              await storage.delete(key: 'password');
              await prefs.remove('semesterId'); await prefs.remove('semesterName');
              if (mounted) { Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false); }
            },
            child: const Text("Sign Out", style: TextStyle(color: AppColors.red)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Share VTOP Super App",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Scan with your phone camera or QR scanner to download the APK directly.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context)),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: downloadUrl,
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text("Copy Link"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(text: downloadUrl));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF1E293B),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            content: const Row(
                              children: [
                                Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
                                SizedBox(width: 10),
                                Expanded(child: Text("Direct download link copied to clipboard!")),
                              ],
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text("Share"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
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
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text("Close", style: TextStyle(color: AppColors.textSecondary(context))),
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
        context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (ctx) {
          return Container(
            decoration: BoxDecoration(color: AppColors.cardBg(context), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text("Select Semester", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
              const SizedBox(height: 8),
              Text("Choose your active semester", style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14)),
              const SizedBox(height: 24),
              SizedBox(height: 300, child: ListView.separated(
                physics: const BouncingScrollPhysics(), itemCount: semesters.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
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
                      
                      // Trigger parallel preloading for the new semester
                      ApiService.preloadAllData(widget.username, semesterId: sem['id']);
                      
                      if (widget.onSemesterChanged != null) {
                        widget.onSemesterChanged!(sem['id']);
                      }
                      
                      if (mounted) { 
                        Navigator.pop(ctx); 
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Changed to ${sem['name']}"))); 
                      }
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary.withOpacity(0.1) : AppColors.scaffoldBg(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: isSelected ? AppColors.primary : AppColors.cardBorder(context)),
                      ),
                      child: Text(sem['name'], style: TextStyle(color: isSelected ? AppColors.primary : AppColors.textPrimary(context), fontSize: 16, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
                    ),
                  );
                },
              )),
            ]),
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
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(color: AppColors.cardBg(context), borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("Select Theme", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
          const SizedBox(height: 20),
          _themeOption(context, "Dark (Default)", Icons.dark_mode, 'dark', const Color(0xFF0F0F0F), AppColors.primary),
          const SizedBox(height: 12),
          _themeOption(context, "Light", Icons.light_mode, 'light', const Color(0xFFF2F4F8), AppColors.primary),
          const SizedBox(height: 12),
          _themeOption(context, "Nightfall", Icons.nights_stay, 'nightfall', const Color(0xFF090A0F), const Color(0xFF6366F1)),
          const SizedBox(height: 12),
          _themeOption(context, "Sakura", Icons.spa, 'sakura', const Color(0xFFFFF7F9), const Color(0xFFF472B6)),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _themeOption(BuildContext context, String title, IconData icon, String themeId, Color bgColor, Color primaryColor) {
    final isSelected = ThemeManager.instance.currentTheme.value == themeId;
    return InkWell(
      onTap: () { ThemeManager.instance.setTheme(themeId); LogsService.add("Theme changed to: $themeId"); Navigator.pop(context); },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withOpacity(0.1) : AppColors.scaffoldBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? primaryColor : AppColors.cardBorder(context)),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder(context)),
            ),
            child: Center(child: Icon(icon, color: primaryColor, size: 20)),
          ),
          const SizedBox(width: 16),
          Text(title, style: TextStyle(color: isSelected ? primaryColor : AppColors.textPrimary(context), fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, fontSize: 16)),
          const Spacer(),
          if (isSelected) Icon(Icons.check_circle, color: primaryColor, size: 22),
        ]),
      ),
    );
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Profile header
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.primary.withOpacity(0.04), Colors.transparent]),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: Column(children: [
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
                            size: 56,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(profile?["name"] ?? widget.username, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context))),
                    const SizedBox(height: 2),
                    Text(currentSemester, style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context))),
                  ])),
                ),
              ),



              const SizedBox(height: 20),
              // Account card
              Container(
                width: double.infinity, padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.cardBg(context), borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.cardBorder(context)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.primary.withOpacity(0.15), AppColors.accent.withOpacity(0.08)]), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.account_box_outlined, color: AppColors.primary, size: 22)),
                    const SizedBox(width: 12),
                    Text("VTOP Account", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
                  ]),
                  const SizedBox(height: 20),
                  _accountRow(context, Icons.person_outline, "Username", widget.username),
                  const SizedBox(height: 14),
                  Row(children: [
                    Icon(Icons.key, size: 18, color: AppColors.textSecondary(context)),
                    const SizedBox(width: 10),
                    Text("Password  ", style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14)),
                    Expanded(child: Text(obscurePassword ? "••••••••••" : "hidden", style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14))),
                    GestureDetector(
                      onTap: () => setState(() => obscurePassword = !obscurePassword),
                      child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: AppColors.scaffoldBg(context), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.cardBorder(context))),
                        child: Icon(obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: AppColors.textSecondary(context))),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  Center(child: OutlinedButton(
                    onPressed: isChangingSemester ? null : _changeSemester,
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: BorderSide(color: AppColors.primary.withOpacity(0.5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10)),
                    child: isChangingSemester ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("Change Semester"),
                  )),
                ]),
              ),

              const SizedBox(height: 20),
              _sectionLabel("App Settings"),
              const SizedBox(height: 8),
              GlassCard(accentColor: AppColors.primary.withOpacity(0.4), margin: EdgeInsets.zero, padding: EdgeInsets.zero,
                child: Column(children: [
                  InkWell(onTap: _selectTheme, child: _dropdownItem(icon: Icons.dark_mode_outlined, title: "Theme", subtitle: "Choose light, dark, or follow system.")),
                  _settingDivider(context),
                  _chevronItem(icon: Icons.notifications_outlined, title: "Notification Management", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
                  _settingDivider(context),
                  _chevronItem(icon: Icons.list_alt, title: "Logs", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LogsScreen()))),
                  _settingDivider(context),
                  _chevronItem(icon: Icons.share_outlined, title: "Share App", onTap: _showAppQrCode),
                  _settingDivider(context),
                  _toggleItem(icon: Icons.fingerprint, title: "Biometric Login", subtitle: "Use fingerprint/face ID to unlock", value: biometricEnabled, onChanged: (v) { setState(() => biometricEnabled = v); _saveBool("biometricEnabled", v); }),
                  _settingDivider(context),
                  InkWell(
                    onTap: isSyncing ? null : () async {
                      setState(() => isSyncing = true);
                      LogsService.add("Manual sync started");
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        final semId = prefs.getString('semesterId');
                        CacheService.clear();
                        
                        // Clear all persistent cache keys from SharedPreferences
                        final keys = prefs.getKeys();
                        final cachePrefixes = ['timetable_', 'marks_', 'grades_', 'profile_', 'curriculum_', 'outing_', 'payments_', 'examtypes_', 'examsched_'];
                        for (var key in keys) {
                          if (cachePrefixes.any((prefix) => key.startsWith(prefix))) {
                            await prefs.remove(key);
                          }
                        }
                        await ApiService.preloadAllData(widget.username, semesterId: semId);
                        
                        // Check for notifications
                        try {
                          final attendanceData = await ApiService.getAttendance(widget.username, semesterId: semId, forceSync: false);
                          await NotificationService.instance.checkAttendanceAlerts(attendanceData);
                          await NotificationService.instance.checkMarksAlerts();
                        } catch (_) {}

                        LogsService.add("Manual sync completed successfully");
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All data synced successfully!")));
                      } catch (e) {
                        LogsService.add("Manual sync failed: $e");
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sync failed: ${ErrorFormatter.format(e)}")));
                      }
                      if (mounted) setState(() => isSyncing = false);
                    },
                    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(children: [
                        Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: isSyncing
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.cloud_sync_outlined, size: 18, color: AppColors.primary)),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text("Sync Now", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary(context))),
                          Text(isSyncing ? "Syncing..." : "Force refresh all data from VTOP", style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
                        ])),
                      ]),
                    ),
                  ),
                  _settingDivider(context),
                  InkWell(onTap: _signOut, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(children: [
                      Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: AppColors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: Icon(Icons.logout, size: 18, color: AppColors.red)),
                      const SizedBox(width: 14),
                      Text("Sign Out", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.red)),
                    ]),
                  )),
                ]),
              ),

              const SizedBox(height: 24),
              // Check for Updates Button
              Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                            SizedBox(width: 12),
                            Text("Checking for updates..."),
                          ],
                        ),
                        duration: Duration(seconds: 1),
                      ),
                    );
                    await UpdateService.checkAndShow(context, isManual: true);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.system_update_alt_rounded, size: 16, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text(
                          "Check for Updates",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // App version & links
              Center(child: Column(children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openUrl("https://github.com/AbhiLohar/vitap-backend"),
                    child: _socialIcon(context, Icons.code),
                  ),
                  const SizedBox(width: 20),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _showAppQrCode,
                    child: _socialIcon(context, Icons.qr_code),
                  ),
                  const SizedBox(width: 20),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Camera feature coming soon")));
                    },
                    child: _socialIcon(context, Icons.camera_alt_outlined),
                  ),
                ]),
                const SizedBox(height: 16),
                FutureBuilder<String>(
                  future: UpdateService.getCurrentVersion(),
                  builder: (context, snap) {
                    final ver = snap.data ?? UpdateService.fallbackVersion;
                    return Text("VTOP Super App v$ver", style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)));
                  },
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Created by ", style: TextStyle(fontSize: 11, color: AppColors.textMuted(context))),
                    InkWell(
                      onTap: () => _openUrl("https://github.com/AbhiLohar"),
                      child: Text("AbhishekLohar", style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.bold)),
                    ),
                    Text(" with ❤️ for VIT-AP students", style: TextStyle(fontSize: 11, color: AppColors.textMuted(context))),
                  ],
                ),
              ])),
              const SizedBox(height: 30),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context)));

  Widget _toggleItem({required IconData icon, required String title, String? subtitle, required bool value, required ValueChanged<bool> onChanged, bool hasInfo = false}) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Icon(icon, size: 20, color: AppColors.textSecondary(context)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary(context))),
            if (hasInfo) ...[const SizedBox(width: 4), Icon(Icons.info_outline, size: 14, color: AppColors.textMuted(context))],
          ]),
          if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
        ])),
        Switch(value: value, onChanged: onChanged),
      ]),
    );
  }

  Widget _dropdownItem({required IconData icon, required String title, String? subtitle}) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(icon, size: 20, color: AppColors.textSecondary(context)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary(context))),
          if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
        ])),
        Icon(Icons.unfold_more, size: 20, color: AppColors.textMuted(context)),
      ]),
    );
  }

  Widget _chevronItem({required IconData icon, required String title, required VoidCallback onTap}) {
    return InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(icon, size: 20, color: AppColors.textSecondary(context)),
        const SizedBox(width: 14),
        Expanded(child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary(context)))),
        Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted(context)),
      ]),
    ));
  }

  Widget _accountRow(BuildContext context, IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, size: 18, color: AppColors.textSecondary(context)),
      const SizedBox(width: 10),
      Text("$label  ", style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14)),
      Text(value, style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14)),
    ]);
  }

  Widget _socialIcon(BuildContext context, IconData icon) {
    return Container(padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.cardBg(context), AppColors.primary.withOpacity(0.05)]),
        borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder(context))),
      child: Icon(icon, size: 22, color: AppColors.textSecondary(context)),
    );
  }

  Widget _settingDivider(BuildContext context) => Divider(height: 1, indent: 50, color: AppColors.cardBorder(context));

  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
