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
    if (grade == 'S' || grade == 'A') return AppColors.good;
    if (grade == 'B') return const Color(0xFF2E7D32);
    if (grade == 'C') return AppColors.warning;
    if (grade == 'D') return const Color(0xFFE65100);
    if (grade == 'E' || grade == 'F' || grade == 'N') return AppColors.danger;
    return const Color(0xFF9CA3AF);
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _buildCgpaBottomSheet(cgpa, creditsEarned, creditsRegistered),
      );
    }
  }

  Widget _buildCgpaBottomSheet(String cgpa, String creditsEarned, String creditsRegistered) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.cardBorder(context), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Icon(Icons.school_rounded, size: 52, color: primaryColor),
          const SizedBox(height: 12),
          Text("Your CGPA", style: TextStyle(fontSize: 16, color: AppColors.textSecondary(context))),
          const SizedBox(height: 6),
          Text(cgpa, style: TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: primaryColor, letterSpacing: -1)),
          const SizedBox(height: 6),
          Text("Credits Earned: $creditsEarned / $creditsRegistered", style: TextStyle(fontSize: 13, color: AppColors.textMuted(context))),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text("Done", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Grade History",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: AppColors.textPrimary(context),
              ),
            ),
            Text(
              "${allGrades.length} courses",
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context), fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, size: 20),
            onPressed: _shareGrades,
          ),
          const SizedBox(width: 4),
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
                      style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14),
                      decoration: InputDecoration(
                        hintText: "Search courses...",
                        hintStyle: TextStyle(color: AppColors.textMuted(context), fontSize: 14),
                        prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted(context), size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cardBorder(context)),
                  ),
                  child: Icon(Icons.filter_list_rounded, color: AppColors.textSecondary(context), size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator(color: primaryColor))
                : RefreshIndicator(
                    onRefresh: () => _fetchGrades(forceSync: true),
                    color: primaryColor,
                    child: filteredGrades.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                              Icon(Icons.history_toggle_off_rounded, size: 48, color: AppColors.textMuted(context)),
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
        backgroundColor: primaryColor,
        elevation: 2,
        icon: const Icon(Icons.calculate_rounded, color: Colors.white, size: 18),
        label: const Text("Calculate CGPA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }

  Widget _buildGradeCard(Map<String, dynamic> item) {
    final grade = item["grade"] ?? "-";
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(AppColors.isDark(context) ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _getGradeColor(grade),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  grade,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              Text(
                item["course_code"] ?? "",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item["subject"] ?? "Unknown Subject",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 12),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.scaffoldBg(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder(context)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Course Type", style: TextStyle(fontSize: 11, color: AppColors.textMuted(context))),
                Text(item["type"] ?? "-", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox(IconData icon, String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted(context)),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 10, color: AppColors.textMuted(context))),
              const SizedBox(height: 1),
              Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary(context))),
            ],
          ),
        ],
      ),
    );
  }
}
