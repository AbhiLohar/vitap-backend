import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_theme.dart';

/// Manages user avatar selection and persistence.
/// Supports: DiceBear avatars (by seed), custom photos, or default initials.
class AvatarService {
  static final AvatarService _instance = AvatarService._internal();
  factory AvatarService() => _instance;
  AvatarService._internal();

  static AvatarService get instance => _instance;

  /// Notifies listeners when avatar changes so all screens update live.
  final ValueNotifier<String?> avatarNotifier = ValueNotifier<String?>(null);

  static const String _prefKey = 'user_avatar_choice';

  /// 12 diverse DiceBear Avataaars seeds (mix of male/female appearances)
  static const List<Map<String, String>> predefinedAvatars = [
    {'seed': 'Felix', 'label': 'Felix'},
    {'seed': 'Aneka', 'label': 'Aneka'},
    {'seed': 'Liam', 'label': 'Liam'},
    {'seed': 'Sophia', 'label': 'Sophia'},
    {'seed': 'Mason', 'label': 'Mason'},
    {'seed': 'Aria', 'label': 'Aria'},
    {'seed': 'Ethan', 'label': 'Ethan'},
    {'seed': 'Luna', 'label': 'Luna'},
    {'seed': 'Oliver', 'label': 'Oliver'},
    {'seed': 'Zara', 'label': 'Zara'},
    {'seed': 'Noah', 'label': 'Noah'},
    {'seed': 'Maya', 'label': 'Maya'},
  ];

  /// Get the DiceBear URL for a given seed
  static String getAvatarUrl(String seed, {int size = 200}) {
    return 'https://api.dicebear.com/9.x/avataaars/png?seed=$seed&size=$size&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf';
  }

  /// Initialize: load saved preference
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    avatarNotifier.value = prefs.getString(_prefKey);
  }

  /// Save a DiceBear avatar choice (stores the seed name)
  Future<void> selectAvatar(String seed) async {
    final prefs = await SharedPreferences.getInstance();
    final value = 'dicebear:$seed';
    await prefs.setString(_prefKey, value);
    avatarNotifier.value = value;
  }

  /// Save a custom photo from device gallery
  Future<void> selectPhoto() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (image == null) return;

    // Copy to app's local directory for persistence
    final appDir = await getApplicationDocumentsDirectory();
    final savedPath = '${appDir.path}/profile_avatar.jpg';
    await File(image.path).copy(savedPath);

    final prefs = await SharedPreferences.getInstance();
    final value = 'photo:$savedPath';
    await prefs.setString(_prefKey, value);
    avatarNotifier.value = value;
  }

  /// Remove avatar (reset to default initials)
  Future<void> removeAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    avatarNotifier.value = null;

    // Clean up saved photo if it exists
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/profile_avatar.jpg');
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Get the current avatar choice
  String? get currentChoice => avatarNotifier.value;

  /// Build the avatar widget based on current selection.
  /// [size] controls diameter. [name] is used for initials fallback.
  static Widget buildAvatar({
    required String? choice,
    required String name,
    double size = 80,
    bool showBorder = true,
  }) {
    Widget child;

    if (choice != null && choice.startsWith('dicebear:')) {
      final seed = choice.replaceFirst('dicebear:', '');
      child = ClipOval(
        child: Image.network(
          getAvatarUrl(seed, size: size.toInt() * 2),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialsWidget(name, size),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return SizedBox(
              width: size,
              height: size,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
          },
        ),
      );
    } else if (choice != null && choice.startsWith('photo:')) {
      final path = choice.replaceFirst('photo:', '');
      child = ClipOval(
        child: Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialsWidget(name, size),
        ),
      );
    } else {
      child = _initialsWidget(name, size);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: (choice == null) ? AppColors.primaryGradient : null,
        boxShadow: showBorder
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
        border: showBorder
            ? Border.all(color: AppColors.primary.withOpacity(0.3), width: 2)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  static Widget _initialsWidget(String name, double size) {
    final initials = name.length >= 2
        ? name.substring(0, 2).toUpperCase()
        : name.toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.35,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
