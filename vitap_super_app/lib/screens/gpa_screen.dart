import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class GPAScreen extends StatefulWidget {
  final String username;
  const GPAScreen({super.key, required this.username});

  @override
  State<GPAScreen> createState() => _GPAScreenState();
}

class SemesterData {
  final int semNumber;
  final String name;
  final double gpa;
  final double cgpa;
  final double creditsEarned;
  final List<dynamic> courses;

  SemesterData({
    required this.semNumber,
    required this.name,
    required this.gpa,
    required this.cgpa,
    required this.creditsEarned,
    required this.courses,
  });
}

class _GPAScreenState extends State<GPAScreen> {
  bool _isLoading = true;
  bool _sortNewestFirst = false;
  String _overallCGPA = "N/A";
  List<SemesterData> _semesters = [];
  int? _touchedIndex;

  @override
  void initState() {
    super.initState();
    _fetchAndCalculateGPA();
  }

  double _gradeToPoints(String grade) {
    switch (grade.toUpperCase()) {
      case 'S': return 10.0;
      case 'A': return 9.0;
      case 'B': return 8.0;
      case 'C': return 7.0;
      case 'D': return 6.0;
      case 'E': return 5.0;
      case 'F': return 0.0;
      case 'N': return 0.0;
      default: return -1.0; // Represents non-GPA impacting grades (P, W, U)
    }
  }

  int _getExamMonthSortKey(String rawMonth) {
    final lower = rawMonth.toLowerCase().trim();

    // 1. Extract 4-digit or 2-digit year
    int year = 0;
    final yearMatch = RegExp(r'(20\d\d)').firstMatch(lower);
    if (yearMatch != null) {
      year = int.tryParse(yearMatch.group(1)!) ?? 0;
    } else {
      final shortYearMatch = RegExp(r'[-/\s](\d{2})\b').firstMatch(lower);
      if (shortYearMatch != null) {
        year = 2000 + (int.tryParse(shortYearMatch.group(1)!) ?? 0);
      }
    }

    // 2. Extract month
    int month = 0;
    if (lower.contains("jan")) {
      month = 1;
    } else if (lower.contains("feb")) {
      month = 2;
    } else if (lower.contains("mar")) {
      month = 3;
    } else if (lower.contains("apr")) {
      month = 4;
    } else if (lower.contains("may")) {
      month = 5;
    } else if (lower.contains("jun")) {
      month = 6;
    } else if (lower.contains("jul")) {
      month = 7;
    } else if (lower.contains("aug")) {
      month = 8;
    } else if (lower.contains("sep")) {
      month = 9;
    } else if (lower.contains("oct")) {
      month = 10;
    } else if (lower.contains("nov")) {
      month = 11;
    } else if (lower.contains("dec")) {
      month = 12;
    } else if (lower.contains("win")) {
      month = 1;
    } else if (lower.contains("sum")) {
      month = 6;
    } else if (lower.contains("fall")) {
      month = 7;
    } else {
      final numMatch = RegExp(r'\b(0?[1-9]|1[0-2])\b').firstMatch(lower);
      if (numMatch != null) {
        month = int.tryParse(numMatch.group(1)!) ?? 0;
      }
    }

    return year * 100 + month;
  }

  Future<void> _fetchAndCalculateGPA() async {
    try {
      final gradesData = await ApiService.getGrades(widget.username);
      if (gradesData.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final overallCGPA = gradesData["cgpa"] ?? "N/A";
      final courses = List<dynamic>.from(gradesData["courses"] ?? []);

      // Group by exam_month
      Map<String, List<dynamic>> groupedCourses = {};
      for (var course in courses) {
        final month = (course["exam_month"] ?? "Unknown").toString().trim();
        if (month.isEmpty) continue;
        if (!groupedCourses.containsKey(month)) {
          groupedCourses[month] = [];
        }
        groupedCourses[month]!.add(course);
      }

      // Sort semesters chronologically by year and month
      final sortedEntries = groupedCourses.entries.toList()
        ..sort((a, b) => _getExamMonthSortKey(a.key).compareTo(_getExamMonthSortKey(b.key)));

      List<SemesterData> calculatedSemesters = [];
      double cumulativePoints = 0.0;
      double cumulativeCredits = 0.0;
      int semNumber = 1;

      for (var entry in sortedEntries) {
        double semPoints = 0.0;
        double semCredits = 0.0;

        for (var course in entry.value) {
          final points = _gradeToPoints((course["grade"] ?? "").toString());
          if (points >= 0.0) {
            final credStr = (course["credits"] ?? "0").toString();
            final cred = double.tryParse(credStr) ?? 0.0;
            semPoints += (points * cred);
            semCredits += cred;
            
            cumulativePoints += (points * cred);
            cumulativeCredits += cred;
          }
        }

        final gpa = semCredits > 0 ? (semPoints / semCredits) : 0.0;
        final cgpa = cumulativeCredits > 0 ? (cumulativePoints / cumulativeCredits) : 0.0;

        calculatedSemesters.add(SemesterData(
          semNumber: semNumber++,
          name: entry.key,
          gpa: double.parse(gpa.toStringAsFixed(2)),
          cgpa: double.parse(cgpa.toStringAsFixed(2)),
          creditsEarned: semCredits,
          courses: entry.value,
        ));
      }

      if (mounted) {
        setState(() {
          _overallCGPA = overallCGPA;
          _semesters = calculatedSemesters;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          "GPA Analytics",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: AppColors.textPrimary(context),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _semesters.isEmpty
              ? const Center(child: Text("No grade data available."))
              : SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryCard(primaryColor),
                      const SizedBox(height: 24),
                      Text("Performance Graph", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: AppColors.textPrimary(context))),
                      const SizedBox(height: 12),
                      _buildGraph(primaryColor),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Semester Breakdown", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: AppColors.textPrimary(context))),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() => _sortNewestFirst = !_sortNewestFirst),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Row(
                                children: [
                                  Icon(Icons.swap_vert_rounded, size: 16, color: primaryColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    _sortNewestFirst ? "Newest First" : "Chronological",
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryColor),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildSemesterList(primaryColor),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSummaryCard(Color primaryColor) {
    return GlassCard(
      accentColor: primaryColor,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              children: [
                Text("Overall CGPA", style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  _overallCGPA,
                  style: TextStyle(color: primaryColor, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                ),
              ],
            ),
            Container(width: 1, height: 44, color: AppColors.cardBorder(context)),
            Column(
              children: [
                Text("Total Semesters", style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  "${_semesters.length}",
                  style: TextStyle(color: AppColors.textPrimary(context), fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraph(Color primaryColor) {
    if (_semesters.isEmpty) return const SizedBox.shrink();

    double minGpa = 10.0;
    for (var sem in _semesters) {
      if (sem.gpa < minGpa && sem.gpa > 0) minGpa = sem.gpa;
      if (sem.cgpa < minGpa && sem.cgpa > 0) minGpa = sem.cgpa;
    }
    minGpa = (minGpa - 0.5).clamp(0.0, 10.0);

    return Container(
      height: 280,
      padding: const EdgeInsets.only(right: 16, left: 0, top: 20, bottom: 8),
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
      child: LineChart(
        LineChartData(
          minY: minGpa,
          maxY: 10.0,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 0.5,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppColors.cardBorder(context),
              strokeWidth: 0.8,
              dashArray: [4, 4],
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: Text(value.toStringAsFixed(1), style: TextStyle(color: AppColors.textSecondary(context), fontSize: 11)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  int idx = value.toInt();
                  if (idx >= 0 && idx < _semesters.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text("Sem ${idx + 1}", style: TextStyle(color: AppColors.textSecondary(context), fontSize: 10)),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (touchedSpot) => primaryColor,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final semIndex = spot.x.toInt();
                  final semName = (semIndex >= 0 && semIndex < _semesters.length)
                      ? _semesters[semIndex].name
                      : "Sem ${semIndex + 1}";
                  return LineTooltipItem(
                    "$semName\n${spot.barIndex == 0 ? 'GPA' : 'CGPA'}: ${spot.y.toStringAsFixed(2)}",
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  );
                }).toList();
              },
            ),
            handleBuiltInTouches: true,
            touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
              if (response != null && response.lineBarSpots != null && event.isInterestedForInteractions) {
                setState(() => _touchedIndex = response.lineBarSpots![0].spotIndex);
              } else {
                setState(() => _touchedIndex = null);
              }
            },
          ),
          lineBarsData: [
            // GPA Line
            LineChartBarData(
              spots: _semesters.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.gpa)).toList(),
              isCurved: true,
              color: AppColors.secondary,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: _touchedIndex == index ? 5 : 3.5,
                    color: AppColors.secondary,
                    strokeWidth: 1.5,
                    strokeColor: Colors.white,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.secondary.withOpacity(0.08),
              ),
            ),
            // CGPA Line
            LineChartBarData(
              spots: _semesters.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.cgpa)).toList(),
              isCurved: true,
              color: primaryColor,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: _touchedIndex == index ? 5 : 3.5,
                    color: primaryColor,
                    strokeWidth: 1.5,
                    strokeColor: Colors.white,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSemesterList(Color primaryColor) {
    final displayList = _sortNewestFirst ? _semesters.reversed.toList() : _semesters;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: displayList.length,
      itemBuilder: (context, index) {
        final sem = displayList[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
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
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "Sem ${sem.semNumber}",
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      sem.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context),
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  "${sem.courses.length} Courses • ${sem.creditsEarned.toStringAsFixed(1)} Credits • CGPA: ${sem.cgpa.toStringAsFixed(2)}",
                  style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12),
                ),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  sem.gpa.toStringAsFixed(2),
                  style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: sem.courses.map((course) {
                      final grade = course["grade"] ?? "-";
                      final gradeColor = _getGradeColor(grade.toString());
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    course["subject"] ?? "Unknown",
                                    style: TextStyle(color: AppColors.textPrimary(context), fontWeight: FontWeight.w500, fontSize: 13),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "${course["course_code"]} • ${course["credits"]} Cr",
                                    style: TextStyle(color: AppColors.textSecondary(context), fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: gradeColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: gradeColor.withOpacity(0.2)),
                              ),
                              child: Text(
                                grade,
                                style: TextStyle(color: gradeColor, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getGradeColor(String grade) {
    switch (grade.toUpperCase()) {
      case 'S':
      case 'A':
        return AppColors.good;
      case 'B':
        return const Color(0xFF2E7D32);
      case 'C':
        return AppColors.warning;
      case 'D':
        return const Color(0xFFE65100);
      case 'E':
      case 'F':
      case 'N':
        return AppColors.danger;
      default:
        return const Color(0xFF9CA3AF);
    }
  }
}
