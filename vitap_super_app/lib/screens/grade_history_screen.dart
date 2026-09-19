import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';
import 'package:share_plus/share_plus.dart';

class GradeHistoryScreen extends StatefulWidget {
  final String username;
  const GradeHistoryScreen({super.key, required this.username});

  @override
  State<GradeHistoryScreen> createState() => _GradeHistoryScreenState();
}

class _GradeHistoryScreenState extends State<GradeHistoryScreen> {
  List<dynamic> allGrades = [];
  List<dynamic> filteredGrades = [];
  Map<String, dynamic> gradeSummary = {};
  bool isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchGrades();
    _searchController.addListener(_filterGrades);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchGrades({bool forceSync = false}) async {
    setState(() => isLoading = true);
    try {
      final data = await ApiService.getGrades(widget.username, forceSync: forceSync);
      if (mounted) {
        setState(() {
          gradeSummary = data;
          final courses = data["courses"];
          allGrades = courses is List ? courses : [];
          filteredGrades = List.from(allGrades);
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _filterGrades() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      filteredGrades = allGrades.where((item) {
        final title = (item["subject"] ?? "").toString().toLowerCase();
        final code = (item["course_code"] ?? "").toString().toLowerCase();
        return title.contains(query) || code.contains(query);
      }).toList();
    });
  }

  void _shareGrades() {
    if (gradeSummary.isEmpty || allGrades.isEmpty) return;
    
    final cgpa = gradeSummary["cgpa"] ?? "N/A";
    final creditsRegistered = gradeSummary["credits_registered"] ?? "N/A";
    final creditsEarned = gradeSummary["credits_earned"] ?? "N/A";
    
    final sb = StringBuffer();
    sb.writeln("Academic Grades for ${widget.username}");
    sb.writeln("CGPA: $cgpa");
    sb.writeln("Credits Registered: $creditsRegistered | Earned: $creditsEarned");
    sb.writeln("\nCourses:");
    
    for (var grade in allGrades) {
      final code = grade["course_code"] ?? "-";
      final type = grade["course_type"] ?? "-";
      final title = grade["subject"] ?? "-";
      final credit = grade["credits"] ?? "-";
      final g = grade["grade"] ?? "-";
      sb.writeln("• $code ($type) [$credit cr]: $g - $title");
    }
    
    Share.share(sb.toString(), subject: 'My VIT-AP Grades ($cgpa CGPA)');
  }

  Color _getGradeColor(String grade) {
    grade = grade.toUpperCase().trim();
    if (grade == 'S' || grade == 'A') return Colors.green.shade400;
    if (grade == 'B') return Colors.lightGreen.shade400;
    if (grade == 'C') return Colors.orange.shade400;
    if (grade == 'D') return Colors.deepOrange.shade400;
    if (grade == 'E' || grade == 'F' || grade == 'N') return Colors.red.shade400;
    return Colors.grey.shade400;
  }

  Future<void> _showCgpaCalculator() async {
    // Use pre-fetched data if available
    String cgpa = gradeSummary["cgpa"]?.toString() ?? "N/A";
    String creditsEarned = gradeSummary["credits_earned"]?.toString() ?? "0";
    String creditsRegistered = gradeSummary["credits_registered"]?.toString() ?? "0";

    if (cgpa == "N/A") {
      // Fallback to separate API call
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      try {
        final data = await ApiService.getCgpa(widget.username);
        if (mounted) Navigator.pop(context);
        final cgpaData = data["cgpa"] ?? data;
        cgpa = cgpaData["cgpa"]?.toString() ?? "0.0";
        creditsEarned = cgpaData["total_credits"]?.toString() ?? "0";
      } catch (e) {
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to calculate CGPA")));
        }
        return;
      }
    }

    if (mounted) {
      showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.scaffoldBg(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _buildCgpaBottomSheet(cgpa, creditsEarned, creditsRegistered),
      );
    }
  }

  Widget _buildCgpaBottomSheet(String cgpa, String creditsEarned, String creditsRegistered) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.cardBorder(context), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          const Icon(Icons.school, size: 64, color: AppColors.primary),
          const SizedBox(height: 16),
          Text("Your CGPA", style: TextStyle(fontSize: 20, color: AppColors.textSecondary(context))),
          const SizedBox(height: 8),
          Text(cgpa, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 8),
          Text("Credits Earned: $creditsEarned / $creditsRegistered", style: TextStyle(fontSize: 14, color: AppColors.textMuted(context))),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(context),
              child: const Text("Awesome!", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Grade History", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text("${allGrades.length} courses", style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context), fontWeight: FontWeight.normal)),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: _shareGrades,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.cardBg(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder(context)),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(color: AppColors.textPrimary(context)),
                      decoration: InputDecoration(
                        hintText: "Search courses...",
                        hintStyle: TextStyle(color: AppColors.textMuted(context)),
                        prefixIcon: Icon(Icons.search, color: AppColors.textMuted(context)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg(context),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.cardBorder(context)),
                  ),
                  child: Icon(Icons.filter_list, color: AppColors.textSecondary(context)),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator(color: AppColors.primary))
                : RefreshIndicator(
                    onRefresh: () => _fetchGrades(forceSync: true),
                    color: AppColors.primary,
                    child: filteredGrades.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                              Icon(Icons.history_toggle_off, size: 48, color: AppColors.textMuted(context)),
                              const SizedBox(height: 12),
                              Center(child: Text("No grades found", style: TextStyle(color: AppColors.textSecondary(context)))),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredGrades.length,
                            itemBuilder: (context, index) {
                              final item = filteredGrades[index];
                              return _buildGradeCard(item);
                            },
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCgpaCalculator,
        backgroundColor: Colors.lightGreen.shade200,
        icon: const Icon(Icons.calculate_outlined, color: Colors.black87),
        label: const Text("Calculate CGPA", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildGradeCard(Map<String, dynamic> item) {
    final grade = item["grade"] ?? "-";
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _getGradeColor(grade),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              grade,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            item["subject"] ?? "Unknown Subject",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item["course_code"] ?? "",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildInfoBox(Icons.library_books_outlined, "Credits", item["credits"] ?? "-"),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildInfoBox(Icons.calendar_today_outlined, "Exam", item["exam_month"] ?? "-"),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.scaffoldBg(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Course Type", style: TextStyle(fontSize: 11, color: AppColors.textMuted(context))),
                const SizedBox(height: 4),
                Text(item["type"] ?? "-", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox(IconData icon, String title, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted(context)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 11, color: AppColors.textMuted(context))),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSecondary(context))),
            ],
          ),
        ],
      ),
    );
  }
}
