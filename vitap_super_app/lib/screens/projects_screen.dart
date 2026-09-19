import 'package:flutter/material.dart';
import '../config/app_theme.dart';

class ProjectsScreen extends StatelessWidget {
  final String username;
  const ProjectsScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.purple.withOpacity(0.15), AppColors.primary.withOpacity(0.08)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: AppColors.purple.withOpacity(0.1), blurRadius: 16, offset: const Offset(0, 4))],
                  ),
                  child: const Icon(Icons.rocket_launch_outlined, size: 48, color: AppColors.purple),
                ),
                const SizedBox(height: 24),
                Text("Projects", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context), letterSpacing: -0.3)),
                const SizedBox(height: 8),
                Text("Your projects and assignments will appear here.\nStay tuned for updates!", textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context), height: 1.5)),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [AppColors.purple.withOpacity(0.12), AppColors.primary.withOpacity(0.08)]),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.purple.withOpacity(0.3)),
                  ),
                  child: const Text("Coming Soon", style: TextStyle(color: AppColors.purple, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
