import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/avatar_service.dart';

/// Beautiful avatar picker screen shown as a modal bottom sheet.
/// Displays a grid of 12 DiceBear character avatars + option to upload photo.
class AvatarPickerSheet extends StatefulWidget {
  final String username;
  final String name;

  const AvatarPickerSheet({
    super.key,
    required this.username,
    required this.name,
  });

  @override
  State<AvatarPickerSheet> createState() => _AvatarPickerSheetState();

  /// Show this as a modal bottom sheet
  static Future<void> show(BuildContext context, {required String username, required String name}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AvatarPickerSheet(username: username, name: name),
    );
  }
}

class _AvatarPickerSheetState extends State<AvatarPickerSheet> {
  String? _selectedChoice;

  @override
  void initState() {
    super.initState();
    _selectedChoice = AvatarService.instance.currentChoice;
  }

  bool _isSelected(String seed) {
    return _selectedChoice == 'dicebear:$seed';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.cardBorder(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Choose Avatar",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Select a character or upload your photo",
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                // Current preview
                ValueListenableBuilder<String?>(
                  valueListenable: AvatarService.instance.avatarNotifier,
                  builder: (context, choice, _) {
                    return AvatarService.buildAvatar(
                      choice: choice,
                      name: widget.name,
                      size: 56,
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Action buttons row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: _actionButton(
                    context,
                    icon: Icons.photo_library_outlined,
                    label: "Upload Photo",
                    color: AppColors.teal,
                    onTap: () async {
                      await AvatarService.instance.selectPhoto();
                      if (mounted) {
                        setState(() => _selectedChoice = AvatarService.instance.currentChoice);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _actionButton(
                    context,
                    icon: Icons.delete_outline,
                    label: "Remove",
                    color: AppColors.red,
                    onTap: () async {
                      await AvatarService.instance.removeAvatar();
                      if (mounted) {
                        setState(() => _selectedChoice = null);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(child: Divider(color: AppColors.cardBorder(context))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    "OR PICK AN AVATAR",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMuted(context),
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: AppColors.cardBorder(context))),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Avatar grid
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                bottom: 24 + bottomPadding,
              ),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.85,
                ),
                itemCount: AvatarService.predefinedAvatars.length,
                itemBuilder: (context, index) {
                  final avatar = AvatarService.predefinedAvatars[index];
                  final seed = avatar['seed']!;
                  final label = avatar['label']!;
                  final isSelected = _isSelected(seed);

                  return GestureDetector(
                    onTap: () async {
                      await AvatarService.instance.selectAvatar(seed);
                      if (mounted) {
                        setState(() => _selectedChoice = 'dicebear:$seed');
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withOpacity(0.1)
                            : AppColors.cardBg(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.cardBorder(context),
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              ClipOval(
                                child: Image.network(
                                  AvatarService.getAvatarUrl(seed, size: 120),
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      gradient: AppColors.primaryGradient,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.person, color: Colors.white, size: 28),
                                  ),
                                  loadingBuilder: (_, child, progress) {
                                    if (progress == null) return child;
                                    return SizedBox(
                                      width: 52,
                                      height: 52,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              if (isSelected)
                                Container(
                                  width: 18,
                                  height: 18,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.check, size: 12, color: Colors.white),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textSecondary(context),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
