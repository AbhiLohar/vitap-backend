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
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text("GPA Analytics"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _semesters.isEmpty
              ? const Center(child: Text("No grade data available."))
              : SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryCard(),
                      const SizedBox(height: 24),
                      Text("Performance Graph", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
                      const SizedBox(height: 16),
                      _buildGraph(),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Semester Breakdown", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() => _sortNewestFirst = !_sortNewestFirst),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Row(
                                children: [
                                  Icon(Icons.swap_vert_rounded, size: 18, color: AppColors.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    _sortNewestFirst ? "Newest First" : "Chronological",
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildSemesterList(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSummaryCard() {
    return GlassCard(
      accentColor: AppColors.primary,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              children: [
                Text("Overall CGPA", style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  _overallCGPA,
                  style: const TextStyle(color: AppColors.primary, fontSize: 32, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Container(width: 1, height: 50, color: AppColors.cardBorder(context)),
            Column(
              children: [
                Text("Total Semesters", style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14)),
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

  Widget _buildGraph() {
    if (_semesters.isEmpty) return const SizedBox.shrink();

    double minGpa = 10.0;
    for (var sem in _semesters) {
      if (sem.gpa < minGpa && sem.gpa > 0) minGpa = sem.gpa;
      if (sem.cgpa < minGpa && sem.cgpa > 0) minGpa = sem.cgpa;
    }
    minGpa = (minGpa - 0.5).clamp(0.0, 10.0);

    return Container(
      height: 300,
      padding: const EdgeInsets.only(right: 16, left: 0, top: 24, bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder(context)),
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
              strokeWidth: 1,
              dashArray: [5, 5],
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(value.toStringAsFixed(1), style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  int idx = value.toInt();
                  if (idx >= 0 && idx < _semesters.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
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
              getTooltipColor: (touchedSpot) => AppColors.primary,
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
              color: AppColors.accent,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: _touchedIndex == index ? 6 : 4,
                    color: AppColors.accent,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.accent.withOpacity(0.1),
              ),
            ),
            // CGPA Line
            LineChartBarData(
              spots: _semesters.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.cgpa)).toList(),
              isCurved: true,
              color: AppColors.primary,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: _touchedIndex == index ? 6 : 4,
                    color: AppColors.primary,
                    strokeWidth: 2,
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

  Widget _buildSemesterList() {
    final displayList = _sortNewestFirst ? _semesters.reversed.toList() : _semesters;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: displayList.length,
      itemBuilder: (context, index) {
        final sem = displayList[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.cardBg(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder(context)),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "Sem ${sem.semNumber}",
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
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
                        fontSize: 15.5,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  "${sem.courses.length} Courses • ${sem.creditsEarned.toStringAsFixed(1)} Credits • CGPA: ${sem.cgpa.toStringAsFixed(2)}",
                  style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12.5),
                ),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  sem.gpa.toStringAsFixed(2),
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 16),
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
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    course["subject"] ?? "Unknown",
                                    style: TextStyle(color: AppColors.textPrimary(context), fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "${course["course_code"]} • ${course["credits"]} Cr",
                                    style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: gradeColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: gradeColor.withOpacity(0.3)),
                              ),
                              child: Text(
                                grade,
                                style: TextStyle(color: gradeColor, fontWeight: FontWeight.bold),
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
      case 'S': return Colors.green;
      case 'A': return Colors.lightGreen;
      case 'B': return Colors.blue;
      case 'C': return Colors.orange;
      case 'D': return Colors.deepOrange;
      case 'E': return Colors.redAccent;
      case 'F': return Colors.red;
      case 'N': return Colors.red;
      default: return Colors.grey;
    }
  }
}
