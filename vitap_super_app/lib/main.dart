import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'config/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'services/theme_manager.dart';
import 'services/avatar_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
  await ThemeManager.instance.init();
  await AvatarService.instance.init();
  await NotificationService.instance.init();
  runApp(const VitapApp());
}

class VitapApp extends StatefulWidget {
  const VitapApp({super.key});

  @override
  State<VitapApp> createState() => _VitapAppState();
}

class _VitapAppState extends State<VitapApp> with WidgetsBindingObserver {
  bool _isLocked = false;
  bool _isAuthenticating = false;
  DateTime? _backgroundTime;
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused) {
      if (!_isAuthenticating) {
        _backgroundTime = DateTime.now();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_isAuthenticating) return;
      
      if (_backgroundTime != null) {
        final diff = DateTime.now().difference(_backgroundTime!);
        _backgroundTime = null;
        
        // Only lock if we were in the background for more than 2 seconds.
        // This prevents locking when immediately returning from system dialogs/pickers.
        if (diff.inSeconds >= 2) {
          final prefs = await SharedPreferences.getInstance();
          final enabled = prefs.getBool('biometricEnabled') ?? false;
          final username = prefs.getString('username');
          
          if (enabled && username != null && username.isNotEmpty && !_isLocked) {
            setState(() {
              _isLocked = true;
            });
            _authenticate();
          }
        }
      }
    }
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    _isAuthenticating = true;
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Authenticate to access VTOP',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      if (authenticated) {
        setState(() {
          _isLocked = false;
        });
      }
    } catch (e) {
      // ignore
    } finally {
      // Wait a tiny bit before allowing lifecycle to trigger locks again
      await Future.delayed(const Duration(milliseconds: 500));
      _isAuthenticating = false;
    }
  }

  Future<Widget> _getInitialScreen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const storage = FlutterSecureStorage();

      // Detect fresh install: SharedPreferences is always wiped on uninstall,
      // but FlutterSecureStorage (Android Keystore) can persist.
      // If 'app_installed' flag is missing, this is a fresh install → clear
      // stale keystore credentials and force the login screen.
      final bool alreadyInstalled = prefs.getBool('app_installed') ?? false;
      if (!alreadyInstalled) {
        // Fresh install — wipe any stale secure storage from a previous install
        await storage.deleteAll();
        await prefs.remove('username');
        await prefs.setBool('app_installed', true);
        return const LoginScreen();
      }

      final username = prefs.getString('username');
      if (username != null && username.isNotEmpty) {
        return MainScreen(username: username);
      }
    } catch (_) {}
    return const LoginScreen();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: ThemeManager.instance.currentTheme,
      builder: (context, themeName, child) {
         ThemeData? theme;
         ThemeData? darkTheme;
         ThemeMode mode = ThemeMode.system;
         
         if (themeName == 'light') { 
           mode = ThemeMode.light; 
           theme = AppTheme.lightTheme; 
         } else if (themeName == 'nightfall') { 
           mode = ThemeMode.dark; 
           theme = AppTheme.nightfallTheme; 
           darkTheme = AppTheme.nightfallTheme; 
         } else if (themeName == 'sakura') { 
           mode = ThemeMode.light; 
           theme = AppTheme.sakuraTheme; 
         } else { 
           mode = ThemeMode.dark; 
           theme = AppTheme.lightTheme; 
           darkTheme = AppTheme.darkTheme; 
         }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'VITAP Super App',
          theme: theme,
          darkTheme: darkTheme,
          themeMode: mode,
          builder: (context, child) {
            return Stack(
              children: [
                if (child != null) child,
                if (_isLocked)
                  Material(
                    color: AppColors.scaffoldBg(context),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_outline, size: 80, color: AppColors.primary),
                          const SizedBox(height: 20),
                          Text(
                            "App Locked",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary(context),
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 30),
                          ElevatedButton.icon(
                            onPressed: _authenticate,
                            icon: const Icon(Icons.fingerprint),
                            label: const Text("Unlock"),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
          home: FutureBuilder<Widget>(
            future: _getInitialScreen(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              return snapshot.data ?? const LoginScreen();
            },
          ),
        );
      },
    );
  }
}