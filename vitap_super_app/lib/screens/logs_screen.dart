import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/logs_service.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  @override
  Widget build(BuildContext context) {
    final logs = LogsService.logs.reversed.toList();

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text("App Logs"),
        backgroundColor: AppColors.scaffoldBg(context),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () {
              setState(() {
                LogsService.clear();
              });
            },
            tooltip: "Clear Logs",
          ),
        ],
      ),
      body: logs.isEmpty
          ? Center(
              child: Text(
                "No logs recorded yet.",
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
            )
          : ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              separatorBuilder: (_, _) => Divider(color: AppColors.cardBorder(context), height: 1),
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    logs[index],
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              },
            ),
    );
  }
}
