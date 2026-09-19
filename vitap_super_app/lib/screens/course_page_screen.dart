import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class CoursePageScreen extends StatefulWidget {
  final String username;

  const CoursePageScreen({super.key, required this.username});

  @override
  State<CoursePageScreen> createState() => _CoursePageScreenState();
}

class _CoursePageScreenState extends State<CoursePageScreen> {
  List _courses = [];
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
      
      final data = await ApiService.getCourses(
        widget.username, 
        semesterId: _semesterId,
        forceSync: forceRefresh,
      );
      
      setState(() {
        _courses = data;
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
        title: const Text("Courses"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary(context),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadData(forceRefresh: true),
        color: AppColors.primary,
        child: _isLoading && _courses.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _courses.isEmpty
                ? ListView(
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                      Center(
                        child: Column(
                          children: [
                            Icon(Icons.library_books_outlined, size: 64, color: AppColors.textMuted(context)),
                            const SizedBox(height: 16),
                            Text("No courses found for this semester", style: TextStyle(color: AppColors.textSecondary(context))),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _courses.length,
                    itemBuilder: (context, index) {
                      final c = _courses[index];
                      final isLab = (c["type"] ?? "").toString().toLowerCase().contains("lab");
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassCard(
                          accentColor: (isLab ? AppColors.teal : AppColors.primary).withOpacity(0.3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: (isLab ? AppColors.teal : AppColors.primary).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      isLab ? Icons.science_outlined : Icons.menu_book_outlined,
                                      size: 20,
                                      color: isLab ? AppColors.teal : AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c["subject"] ?? "Unknown Subject",
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary(context),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          c["course_code"] ?? "-",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary(context),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _badge(context, c["type"] ?? "Theory", isLab ? AppColors.teal : AppColors.accent),
                                  const SizedBox(width: 8),
                                  // Can add more info like credits if available
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

  Widget _badge(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
