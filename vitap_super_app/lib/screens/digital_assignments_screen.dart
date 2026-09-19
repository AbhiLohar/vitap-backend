import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class DigitalAssignmentsScreen extends StatefulWidget {
  final String username;

  const DigitalAssignmentsScreen({super.key, required this.username});

  @override
  State<DigitalAssignmentsScreen> createState() => _DigitalAssignmentsScreenState();
}

class _DigitalAssignmentsScreenState extends State<DigitalAssignmentsScreen> {
  List _assignments = [];
  bool _isLoading = true;
  String? _semesterId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _semesterId = prefs.getString('semesterId');
      
      final daFuture = ApiService.getDigitalAssignments(
        widget.username, 
        semesterId: _semesterId,
        forceSync: forceRefresh,
      );

      final ttFuture = ApiService.getTimetable(
        widget.username,
        semesterId: _semesterId,
        forceSync: false, // Don't force sync timetable just for DA
      );

      final results = await Future.wait([daFuture, ttFuture]);
      final List daData = results[0];
      final List ttData = results[1];

      // Cross-reference timetable to fetch missing Faculty and Slot details
      for (var a in daData) {
        final courseCode = a["subject"]?.toString().trim(); // "subject" holds course code in DA
        if (courseCode != null && courseCode.isNotEmpty) {
          final ttMatch = ttData.cast<Map<String, dynamic>>().firstWhere(
            (t) => t["course_code"]?.toString().trim() == courseCode,
            orElse: () => <String, dynamic>{},
          );
          if (ttMatch.isNotEmpty) {
            a["faculty"] = ttMatch["faculty"];
            a["slot"] = ttMatch["slot"];
          }
        }
      }

      setState(() {
        _assignments = daData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text("Digital Assignments"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary(context),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadData(forceRefresh: true),
        color: AppColors.primary,
        child: _isLoading && _assignments.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _assignments.isEmpty
                ? ListView(
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                      Center(
                        child: Column(
                          children: [
                            Icon(Icons.assignment_turned_in_outlined, size: 64, color: AppColors.textMuted(context)),
                            const SizedBox(height: 16),
                            Text("No assignments found", style: TextStyle(color: AppColors.textSecondary(context))),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _assignments.length,
                    itemBuilder: (context, index) {
                      final a = _assignments[index];
                      final isPending = (a["status"] ?? "").toString().toLowerCase().contains("pending");
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassCard(
                          accentColor: AppColors.primary.withOpacity(0.3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      a["type"] ?? "Unknown Subject", // "type" actually holds Course Title
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary(context),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                                    ),
                                    child: Text(
                                      a["subject"] ?? "", // "subject" actually holds Course Code
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Type: ${a["title"] ?? "-"}", // "title" holds ETH/ELA etc
                                style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context)),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  _stat(context, Icons.person, "Faculty", a["faculty"] ?? "-"),
                                  const Spacer(),
                                  _stat(context, Icons.schedule, "Slot", a["slot"] ?? "-"),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  Widget _stat(BuildContext context, IconData icon, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppColors.textMuted(context)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: AppColors.textMuted(context))),
          ],
        ),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context))),
      ],
    );
  }
}
