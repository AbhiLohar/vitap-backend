import 'package:flutter/material.dart';
import 'dart:math';
import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../services/error_formatter.dart';

class CreditProgressScreen extends StatefulWidget {
  final String username;
  const CreditProgressScreen({super.key, required this.username});

  @override
  State<CreditProgressScreen> createState() => _CreditProgressScreenState();
}

class _CreditProgressScreenState extends State<CreditProgressScreen> with SingleTickerProviderStateMixin {
  bool isLoading = true;
  Map<String, dynamic> summary = {"earned": "0", "total": "0", "left": "0"};
  List distribution = [];
  String? errorMessage;
  String cgpa = "...";
  
  late AnimationController _animController;
  late Animation<double> _progressAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _progressAnim = Tween<double>(begin: 0, end: 0).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _fetchCredits();
  }
  
  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _fetchCredits({bool forceSync = false}) async {
    if (mounted && distribution.isEmpty) setState(() { isLoading = true; errorMessage = null; });
    
    // Fetch CGPA in parallel
    ApiService.getCgpa(widget.username, forceSync: forceSync).then((data) {
      String fetchedCgpa = "0.0";
      final c = data["cgpa"];
      if (c is Map) {
        fetchedCgpa = c["cgpa"]?.toString() ?? "0.0";
      } else if (c != null) {
        fetchedCgpa = c.toString();
      }
      
      if (fetchedCgpa == "0.0" || fetchedCgpa == "N/A" || fetchedCgpa == "0") {
        throw Exception("Invalid CGPA");
      }
      
      if (mounted) setState(() => cgpa = fetchedCgpa);
    }).catchError((_) {
      // Fallback to getGrades if getCgpa fails or returns 0.0
      ApiService.getGrades(widget.username, forceSync: forceSync).then((gradesData) {
        if (mounted) {
          setState(() {
            final gradesMap = gradesData["grades"] is Map ? gradesData["grades"] : gradesData;
            final c = gradesMap["cgpa"]?.toString();
            cgpa = (c != null && c != "0.0" && c != "0") ? c : "N/A";
          });
        }
      }).catchError((_) {
        if (mounted) setState(() => cgpa = "N/A");
      });
    });

    try {
      final data = await ApiService.getCurriculum(
        widget.username,
        forceSync: forceSync,
        onSync: (freshData) {
          if (mounted) {
            setState(() {
              summary = freshData["summary"] ?? {"earned": "0", "total": "0", "left": "0"};
              distribution = freshData["distribution"] as List? ?? [];
              isLoading = false;
            });
            _progressAnim = Tween<double>(begin: 0, end: _progressPercent).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
            _animController.forward(from: 0);
          }
        }
      );
      if (mounted) {
        setState(() {
          summary = data["summary"] ?? {"earned": "0", "total": "0", "left": "0"};
          distribution = data["distribution"] as List? ?? [];
          isLoading = false;
        });
        _progressAnim = Tween<double>(begin: 0, end: _progressPercent).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
        _animController.forward(from: 0);
      }
    } catch (e) {
      if (mounted) setState(() { isLoading = false; errorMessage = ErrorFormatter.format(e); });
    }
  }

  double get _earnedNum => double.tryParse(summary["earned"].toString()) ?? 0;
  double get _totalNum {
    final t = double.tryParse(summary["total"].toString()) ?? 0;
    return t > 0 ? t : 160;
  }
  double get _leftNum => double.tryParse(summary["left"].toString()) ?? 0;
  double get _progressPercent => (_earnedNum / _totalNum).clamp(0.0, 1.0);
  
  String get _healthScore {
    if (_progressPercent >= 0.8) return "Excellent";
    if (_progressPercent >= 0.5) return "Good";
    if (_progressPercent >= 0.25) return "Fair";
    return "Needs Attention";
  }
  
  Color get _healthColor {
    if (_progressPercent >= 0.8) return AppColors.teal;
    if (_progressPercent >= 0.5) return AppColors.primary;
    if (_progressPercent >= 0.25) return AppColors.orange;
    return AppColors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text("Credit Progress", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.primary))
          : errorMessage != null
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: _fetchCredits,
                  color: AppColors.primary,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeroSection(),
                        const SizedBox(height: 20),
                        _buildDeficitAlert(),
                        const SizedBox(height: 24),
                        _sectionTitle("Detailed Breakdown"),
                        const SizedBox(height: 12),
                        if (_validDistribution.isNotEmpty)
                          _buildDistributionTable()
                        else
                          _emptyDistribution(),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildHeroSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: _healthColor.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Credit Health", style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(color: _healthColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text(_healthScore, style: TextStyle(color: _healthColor, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified, size: 16, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text("${(_progressPercent * 100).toStringAsFixed(1)}%", style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          
          AnimatedBuilder(
            animation: _progressAnim,
            builder: (context, child) {
              return SizedBox(
                height: 180,
                width: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      height: 180,
                      width: 180,
                      child: CustomPaint(
                        painter: _CirclePainter(progress: _progressAnim.value, color: _healthColor, bgColor: AppColors.cardBorder(context)),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _earnedNum.toStringAsFixed(0),
                          style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: AppColors.textPrimary(context), height: 1.0),
                        ),
                        Text("Earned", style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context))),
                      ],
                    ),
                  ],
                ),
              );
            }
          ),
          
          const SizedBox(height: 32),
          
          // Stats Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _statBox("Total", _totalNum.toStringAsFixed(0), AppColors.textPrimary(context)),
              Container(width: 1, height: 40, color: AppColors.cardBorder(context)),
              _statBox("Remaining", _leftNum.toStringAsFixed(0), AppColors.orange),
              Container(width: 1, height: 40, color: AppColors.cardBorder(context)),
              _statBox("CGPA", cgpa, AppColors.teal),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
      ],
    );
  }

  Widget _buildDeficitAlert() {
    if (_leftNum <= 0) return const SizedBox.shrink();
    
    bool isHighDeficit = _progressPercent < 0.3;
    Color alertColor = isHighDeficit ? AppColors.red : AppColors.orange;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: alertColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: alertColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(isHighDeficit ? Icons.warning_amber_rounded : Icons.info_outline, color: alertColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isHighDeficit ? "Critical Deficit" : "Credits Remaining",
                  style: TextStyle(fontWeight: FontWeight.bold, color: alertColor),
                ),
                const SizedBox(height: 4),
                Text(
                  "You need ${_leftNum.toStringAsFixed(0)} more credits to complete your degree requirements.",
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List get _validDistribution {
    const invalidNames = {"ETL", "TH", "LO", "PJT", "NCC", "ETP", "SS", "OC", "AUDIT"};
    return distribution.where((item) {
      if (item is! Map) return false;
      final cat = item["category"]?.toString().trim() ?? "";
      if (cat.isEmpty) return false;
      if (invalidNames.contains(cat.toUpperCase())) return false;
      if (cat.toLowerCase().contains("total") || cat.toLowerCase().contains("grand")) return false;
      return true;
    }).toList();
  }

  Widget _buildDistributionTable() {
    final distList = _validDistribution;
    if (distList.isEmpty) return _emptyDistribution();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // VTOP Credits Distribution banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: const Color(0xFFE53935).withOpacity(0.08),
            child: const Center(
              child: Text(
                "CREDITS DISTRIBUTION",
                style: TextStyle(
                  color: Color(0xFFE53935),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
          // Column Headers
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: AppColors.primary.withOpacity(0.12),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    "Sl.No.",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textPrimary(context)),
                  ),
                ),
                Expanded(
                  child: Text(
                    "Category",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textPrimary(context)),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    "Total Cr",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textPrimary(context)),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    "Earned Cr",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textPrimary(context)),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    "View",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: AppColors.textPrimary(context)),
                  ),
                ),
              ],
            ),
          ),
          // Data Rows
          ...distList.asMap().entries.map((entry) {
            final int index = entry.key;
            final cat = Map<String, dynamic>.from(entry.value);
            final String name = cat["category"] ?? "Unknown";
            final double earned = double.tryParse(cat["earned"].toString()) ?? 0;
            final double required = double.tryParse(cat["required"].toString()) ?? 0;
            final bool isEven = index % 2 == 1;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: isEven ? AppColors.scaffoldBg(context).withOpacity(0.4) : Colors.transparent,
                border: Border(
                  bottom: BorderSide(color: AppColors.cardBorder(context).withOpacity(0.5), width: 0.8),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(
                      "${index + 1}.",
                      style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      required.toStringAsFixed(0),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      earned.toStringAsFixed(1),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: earned >= required && required > 0 ? AppColors.teal : AppColors.textPrimary(context),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Center(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => _showCoursesBottomSheet(context, cat),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E88E5), // Official VTOP blue plus button
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF1E88E5).withOpacity(0.35),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.add, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          // Row 5: Total Credits summary row (matching official VTOP)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              border: Border(
                top: BorderSide(color: AppColors.cardBorder(context), width: 1.2),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    "${distList.length + 1}.",
                    style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: Text(
                    "Total Credits",
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    _totalNum.toStringAsFixed(0),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    _earnedNum.toStringAsFixed(1),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 36),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCoursesBottomSheet(BuildContext context, Map<String, dynamic> cat) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CoursesBottomSheet(cat: cat),
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: AppColors.textMuted(context)),
          const SizedBox(height: 16),
          Text("Failed to load credits", style: TextStyle(fontSize: 16, color: AppColors.textPrimary(context))),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _fetchCredits,
            child: const Text("Retry"),
          ),
        ],
      ),
    );
  }

  Widget _emptyDistribution() => const Center(child: Text("No data available."));
  
  Widget _sectionTitle(String title) {
    return Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context)));
  }
}

class _CoursesBottomSheet extends StatefulWidget {
  final Map<String, dynamic> cat;
  const _CoursesBottomSheet({required this.cat});

  @override
  State<_CoursesBottomSheet> createState() => _CoursesBottomSheetState();
}

class _CoursesBottomSheetState extends State<_CoursesBottomSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _getGradeColor(String grade) {
    switch (grade.toUpperCase()) {
      case "S": return const Color(0xFFF59E0B);
      case "A": return const Color(0xFF10B981);
      case "B": return const Color(0xFF3B82F6);
      case "C": return const Color(0xFF8B5CF6);
      case "D": return const Color(0xFFEC4899);
      case "E": return const Color(0xFF6B7280);
      default: return AppColors.teal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final String name = widget.cat["category"] ?? "Category";
    final double required = double.tryParse(widget.cat["required"]?.toString() ?? "0") ?? 0;
    final double earned = double.tryParse(widget.cat["earned"]?.toString() ?? "0") ?? 0;
    final List allCourses = widget.cat["courses"] as List? ?? [];

    final filteredCourses = allCourses.where((c) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final code = (c["course_code"] ?? "").toString().toLowerCase();
      final subj = (c["subject"] ?? "").toString().toLowerCase();
      return code.contains(q) || subj.contains(q);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              height: 4,
              width: 44,
              decoration: BoxDecoration(
                color: AppColors.cardBorder(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Category Header & Progress Badge
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${allCourses.length} Completed Course${allCourses.length == 1 ? '' : 's'}",
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: Text(
                    "${earned.toStringAsFixed(1)} / ${required.toStringAsFixed(0)} Cr",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Optional search bar if multiple courses
          if (allCourses.length > 4)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.scaffoldBg(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorder(context)),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary(context)),
                  decoration: InputDecoration(
                    hintText: "Search course code or title...",
                    hintStyle: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                    prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => setState(() {
                              _searchCtrl.clear();
                              _searchQuery = "";
                            }),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          // Course List
          Expanded(
            child: filteredCourses.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.school_outlined, size: 48, color: AppColors.textSecondary(context).withOpacity(0.5)),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isNotEmpty
                              ? "No courses matching '$_searchQuery'"
                              : "No completed courses found for this category.",
                          style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    itemCount: filteredCourses.length,
                    separatorBuilder: (context, index) => const Divider(height: 16),
                    itemBuilder: (context, index) {
                      final course = Map<String, dynamic>.from(filteredCourses[index]);
                      final grade = course["grade"]?.toString().trim() ?? "-";
                      final gradeColor = _getGradeColor(grade);
                      final type = course["type"]?.toString().trim() ?? "";
                      final credits = course["credits"]?.toString().trim() ?? "";

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Course Code
                          SizedBox(
                            width: 76,
                            child: Text(
                              course["course_code"]?.toString() ?? "",
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Title & Badges
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  course["subject"]?.toString() ?? "",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary(context),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (type.isNotEmpty) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withOpacity(0.08),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          type,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textSecondary(context),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    if (credits.isNotEmpty)
                                      Text(
                                        "$credits Cr",
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.textSecondary(context),
                                        ),
                                      ),
                                    if (course["exam_month"] != null && course["exam_month"].toString().isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        "• ${course["exam_month"]}",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary(context).withOpacity(0.8),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Grade Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: gradeColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: gradeColor.withOpacity(0.3)),
                            ),
                            child: Text(
                              grade,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: gradeColor,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CirclePainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color bgColor;

  _CirclePainter({required this.progress, required this.color, required this.bgColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2) - 10;
    
    final bgPaint = Paint()
      ..color = bgColor
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke;
      
    canvas.drawCircle(center, radius, bgPaint);
    
    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
      
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CirclePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
