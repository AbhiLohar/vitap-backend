import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../services/error_formatter.dart';
import '../widgets/glass_card.dart';
import '../widgets/stat_box.dart';

class AttendanceScreen extends StatefulWidget {
  final String username;
  final ValueNotifier<String>? semesterNotifier;

  const AttendanceScreen({super.key, required this.username, this.semesterNotifier});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with AutomaticKeepAliveClientMixin {
  List allSubjects = [];
  bool isLoading = true;
  late ValueNotifier<int> selectedFilterNotifier; // 0=All, 1=Class, 2=Lab
  String currentSemester = "Fetching...";
  late PageController _pageController;
  
  // Capstone/SDP attendance
  bool hasCapstone = false;
  Map<String, dynamic>? capstoneData;
  bool isLoadingCapstone = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    selectedFilterNotifier = ValueNotifier<int>(0);
    _pageController = PageController(initialPage: selectedFilterNotifier.value);
    fetchAttendance();
    widget.semesterNotifier?.addListener(_onSemesterChanged);
  }

  @override
  void dispose() {
    _pageController.dispose();
    selectedFilterNotifier.dispose();
    widget.semesterNotifier?.removeListener(_onSemesterChanged);
    super.dispose();
  }

  void _onSemesterChanged() {
    if (mounted) {
      fetchAttendance(forceRefresh: true);
    }
  }

  Future<void> fetchAttendance({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final semesterId = prefs.getString('semesterId');
    final semName = prefs.getString('semesterName') ?? "Default Semester";
    
    if (mounted) {
      setState(() {
        currentSemester = semName;
        if (allSubjects.isEmpty) isLoading = true;
        if (forceRefresh) capstoneData = null;
      });
    }

    try {
      final data = await ApiService.getAttendance(
        widget.username, 
        semesterId: semesterId, 
        forceSync: forceRefresh,
        onSync: (freshData) {
          if (mounted) {
            setState(() {
              allSubjects = freshData;
              isLoading = false;
            });
          }
          // Check capstone availability after sync
          _checkCapstoneAvailability();
        }
      );
      
      if (mounted) {
        setState(() {
          allSubjects = data;
          isLoading = false;
        });
      }
      // Check capstone availability
      _checkCapstoneAvailability();
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(
            children: [
              const Icon(Icons.wifi_off_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ErrorFormatter.format(e),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ));
      }
    }
  }

  Future<void> _checkCapstoneAvailability() async {
    final prefs = await SharedPreferences.getInstance();
    final semesterId = prefs.getString('semesterId');
    final hasCap = await ApiService.hasCapstoneAttendance(widget.username, semesterId: semesterId);
    if (mounted && hasCap != hasCapstone) {
      setState(() => hasCapstone = hasCap);
    }
  }

  Future<void> _fetchCapstoneData({bool forceSync = false, bool showSheet = true}) async {
    if (isLoadingCapstone) return;
    setState(() => isLoadingCapstone = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final semesterId = prefs.getString('semesterId');
      final data = await ApiService.getCapstoneAttendance(
        widget.username,
        semesterId: semesterId,
        forceSync: forceSync,
      );
      if (mounted) {
        setState(() {
          capstoneData = data;
          isLoadingCapstone = false;
        });
        if (data['available'] == true && (data['present'] != null || data['percentage'] != null)) {
          if (showSheet) _showCapstoneDetailSheet(context, data);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data['message'] ?? 'Capstone attendance could not be loaded.'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoadingCapstone = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ErrorFormatter.format(e)),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
      }
    }
  }

  List _getFilteredSubjects(int filterIndex) {
    if (filterIndex == 0) {
      return allSubjects;
    } else if (filterIndex == 1) {
      // Class/Theory filter
      return allSubjects
          .where((s) =>
              (s["type"] ?? "").toString().toLowerCase().contains("theory") ||
              (s["type"] ?? "").toString().toLowerCase().contains("lecture") ||
              (s["type"] ?? "").toString().toLowerCase().contains("class"))
          .toList();
    } else {
      // Lab filter
      return allSubjects
          .where((s) =>
              (s["type"] ?? "").toString().toLowerCase().contains("lab") ||
              (s["type"] ?? "").toString().toLowerCase().contains("practical"))
          .toList();
    }
  }

  double parsePercent(String value) {
    return double.tryParse(value.replaceAll("%", "").trim()) ?? 0;
  }

  /// Calculate classes that can be missed to stay above 75%
  int _classesCanMiss(int present, int total) {
    if (total == 0) return 0;
    // present / (total + x) >= 0.75 => x = (present / 0.75) - total
    int canMiss = ((present / 0.75) - total).floor();
    return canMiss > 0 ? canMiss : 0;
  }

  /// Calculate classes that need to be attended to reach 75%
  int _classesToAttend(int present, int total) {
    if (total == 0) return 0;
    // (present + x) / (total + x) >= 0.75 => x = 3 * total - 4 * present
    int need = (3 * total) - (4 * present);
    return need > 0 ? need : 0;
  }

  void _showCalculatorBottomSheet(BuildContext context, String subjectName, int currentPresent, int currentTotal) {
    int simPresent = currentPresent;
    int simTotal = currentTotal;
    double targetPercentage = 75.0; // Default target

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            double simPercent = simTotal == 0 ? 0 : (simPresent / simTotal) * 100;
            
            // Calculate classes that can be missed for TARGET
            int canMiss = 0;
            if (simTotal > 0) {
              canMiss = ((simPresent / (targetPercentage / 100)) - simTotal).floor();
              if (canMiss < 0) canMiss = 0;
            }
            
            // Calculate classes that need to be attended for TARGET
            int needAttend = 0;
            if (simTotal > 0) {
               // (present + x) / (total + x) >= target/100
               // present + x >= target/100 * total + target/100 * x
               // x(1 - target/100) >= target/100 * total - present
               // x >= (target/100 * total - present) / (1 - target/100)
               double targetFrac = targetPercentage / 100;
               double x = (targetFrac * simTotal - simPresent) / (1 - targetFrac);
               needAttend = x.ceil();
               if (needAttend < 0) needAttend = 0;
            }
            
            bool isDanger = simPercent < targetPercentage;

            return Container(
              padding: const EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 40),
              decoration: BoxDecoration(
                color: AppColors.cardBg(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: AppColors.cardBorder(context)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textMuted(context).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Attendance Calculator",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subjectName,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Target: ${targetPercentage.toInt()}%", style: TextStyle(color: AppColors.textPrimary(context), fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Slider(
                          value: targetPercentage,
                          min: 50,
                          max: 100,
                          divisions: 10,
                          activeColor: AppColors.primary,
                          onChanged: (val) {
                            setModalState(() { targetPercentage = val; });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Circular percent indicator
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.badgeBg(simPercent),
                        width: 4,
                      ),
                      color: AppColors.badgeBg(simPercent).withOpacity(0.1),
                    ),
                    child: Text(
                      "${simPercent.toStringAsFixed(1)}%",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.badgeText(simPercent),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Attended classes modifier
                      Column(
                        children: [
                          Text("Attended", style: TextStyle(color: AppColors.textSecondary(context))),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: AppColors.red),
                                onPressed: simPresent > 0 ? () {
                                  setModalState(() {
                                    simPresent--;
                                    simTotal--;
                                  });
                                } : null,
                              ),
                              SizedBox(
                                width: 35,
                                child: Text("$simPresent", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, color: AppColors.teal),
                                onPressed: () {
                                  setModalState(() {
                                    simPresent++;
                                    simTotal++;
                                  });
                                },
                              ),
                            ],
                          )
                        ],
                      ),
                      
                      // Missed classes modifier
                      Column(
                        children: [
                          Text("Missed", style: TextStyle(color: AppColors.textSecondary(context))),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: AppColors.red),
                                onPressed: (simTotal > simPresent) ? () {
                                  setModalState(() {
                                    simTotal--;
                                  });
                                } : null,
                              ),
                              SizedBox(
                                width: 35,
                                child: Text("${simTotal - simPresent}", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, color: AppColors.teal),
                                onPressed: () {
                                  setModalState(() {
                                    simTotal++;
                                  });
                                },
                              ),
                            ],
                          )
                        ],
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: (isDanger ? AppColors.red : AppColors.teal).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isDanger ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                          color: isDanger ? AppColors.red : AppColors.teal,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isDanger 
                                ? "You need to attend $needAttend more class${needAttend == 1 ? '' : 'es'} to reach 75%"
                                : "You can miss $canMiss more class${canMiss == 1 ? '' : 'es'} and stay above 75%",
                            style: TextStyle(
                              color: isDanger ? AppColors.red : AppColors.teal,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                    
                  const SizedBox(height: 24),
                  
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppColors.cardBorder(context)),
                        ),
                      ),
                      onPressed: () {
                         setModalState(() {
                           simPresent = currentPresent;
                           simTotal = currentTotal;
                         });
                      },
                      child: Text("Reset to Current", style: TextStyle(color: AppColors.textPrimary(context), fontSize: 15)),
                    ),
                  ),
                ],
              ),
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      body: SafeArea(
        child: Column(
          children: [
            // Header with gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primary.withOpacity(0.04),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  children: [
                    Text(
                      "Attendance",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currentSemester,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Filter tabs — pill-shaped container
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.cardBg(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.cardBorder(context)),
                ),
                child: ValueListenableBuilder<int>(
                  valueListenable: selectedFilterNotifier,
                  builder: (context, selectedIndex, _) {
                    return Row(
                      children: [
                        _filterTab("All", Icons.filter_list, 0, selectedIndex),
                        const SizedBox(width: 4),
                        _filterTab("Theory", Icons.menu_book, 1, selectedIndex),
                        const SizedBox(width: 4),
                        _filterTab("Lab", Icons.science_outlined, 2, selectedIndex),
                      ],
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Attendance cards & Danger Zone via PageView
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) => selectedFilterNotifier.value = index,
                itemCount: 3,
                itemBuilder: (context, pageIndex) {
                  final filteredSubjects = _getFilteredSubjects(pageIndex);
                  int dangerCount = filteredSubjects.where((s) => parsePercent(s["attendance"] ?? "0") < 75).length;

                  return Column(
                    children: [
                      if (dangerCount > 0)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.red.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.red.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: AppColors.red),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "Danger Zone! You have $dangerCount subject${dangerCount > 1 ? 's' : ''} below 75%.",
                                  style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),

                      Expanded(
                        child: isLoading && allSubjects.isEmpty
                            ? _buildSkeletonLoading()
                            : filteredSubjects.isEmpty && !hasCapstone
                                ? RefreshIndicator(
                                    onRefresh: () => fetchAttendance(forceRefresh: true),
                                    color: AppColors.primary,
                                    child: ListView(
                                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                      children: [
                                        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                                        Icon(Icons.inbox_outlined, size: 48, color: AppColors.textMuted(context)),
                                        const SizedBox(height: 12),
                                        Center(child: Text("No data available", style: TextStyle(color: AppColors.textSecondary(context), fontSize: 15))),
                                      ],
                                    ),
                                  )
                                : RefreshIndicator(
                                    onRefresh: () => fetchAttendance(forceRefresh: true),
                                    color: AppColors.primary,
                                    child: ListView.builder(
                                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                      padding: const EdgeInsets.only(bottom: 20),
                                      itemCount: filteredSubjects.length + (hasCapstone && pageIndex == 0 ? 1 : 0),
                                      itemBuilder: (context, index) {
                                        // Show capstone card at the top on "All" tab
                                        if (hasCapstone && pageIndex == 0 && index == 0) {
                                          return _capstoneCard();
                                        }
                                        final adjustedIndex = hasCapstone && pageIndex == 0 ? index - 1 : index;
                                        return _attendanceCard(filteredSubjects[adjustedIndex], adjustedIndex);
                                      },
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
      ),
    );
  }

  Widget _filterTab(String label, IconData icon, int index, int selectedIndex) {
    final isSelected = selectedIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          selectedFilterNotifier.value = index;
          _pageController.jumpToPage(index);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected ? AppColors.primaryGradient : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (index != 0) ...[
                Icon(icon,
                    size: 15,
                    color: isSelected ? Colors.white : AppColors.textMuted(context)),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? Colors.white : AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAttendanceDetailSheet(BuildContext context, Map<String, dynamic> subject, String subjectName, int presentInt, int totalInt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _AttendanceDetailBottomSheet(
          subject: subject,
          subjectName: subjectName,
          presentInt: presentInt,
          totalInt: totalInt,
          username: widget.username,
          calculatorBuilder: (context) {
            _showCalculatorBottomSheet(context, subjectName, presentInt, totalInt);
          },
        );
      },
    );
  }

  Widget _capstoneCard() {
    final rawPct = (capstoneData?['percentage'] ?? '').toString();
    final cachedPct = rawPct.isNotEmpty ? (rawPct.endsWith('%') ? rawPct : '$rawPct%') : '';
    final pctNum = double.tryParse(cachedPct.replaceAll('%', '').trim()) ?? 0;
    final hasCachedData = capstoneData != null && 
        capstoneData!['available'] == true && 
        (capstoneData!['present'] != null || cachedPct.isNotEmpty);
    
    return GestureDetector(
      onTap: () {
        if (hasCachedData) {
          _showCapstoneDetailSheet(context, capstoneData!);
        } else {
          _fetchCapstoneData(forceSync: true, showSheet: true);
        }
      },
      child: GlassCard(
        accentColor: AppColors.teal,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.teal.withValues(alpha: 0.22),
                    AppColors.teal.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.assignment_outlined, size: 22, color: AppColors.teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Capstone/SDP Attendance",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hasCachedData && cachedPct.isNotEmpty
                        ? "${capstoneData!['title'] ?? 'Capstone'} • $cachedPct Attendance"
                        : "Tap to view capstone attendance",
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isLoadingCapstone)
              const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
              )
            else if (hasCachedData && cachedPct.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.badgeBg(pctNum).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.badgeBg(pctNum).withValues(alpha: 0.35)),
                ),
                child: Text(
                  cachedPct,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.badgeText(pctNum),
                  ),
                ),
              )
            else
              Icon(Icons.chevron_right_rounded, color: AppColors.textMuted(context), size: 22),
          ],
        ),
      ),
    );
  }

  void _showCapstoneDetailSheet(BuildContext context, Map<String, dynamic> data) {
    final title = data['title'] ?? 'Capstone';
    final guideStatus = data['guide_evaluation_status'] ?? '-';
    final regDate = data['date_of_registration'] ?? '-';
    final present = data['present']?.toString() ?? '0';
    final onDuty = data['on_duty']?.toString() ?? '0';
    final absent = data['absent']?.toString() ?? '0';
    final rawPct = (data['percentage'] ?? '').toString();
    final pctStr = rawPct.isNotEmpty ? (rawPct.endsWith('%') ? rawPct : '$rawPct%') : '0%';
    final pctNum = double.tryParse(pctStr.replaceAll('%', '').trim()) ?? 0;
    
    final presentNum = int.tryParse(present) ?? 0;
    final odNum = int.tryParse(onDuty) ?? 0;
    final absentNum = int.tryParse(absent) ?? 0;
    final total = (data['total_classes'] is int && data['total_classes'] > 0)
        ? data['total_classes'] as int
        : (presentNum + odNum + absentNum);

    final punches = (data['punches'] as List?) ?? [];
    String activeFilter = "All";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // Filter punch list
            final filteredPunches = punches.where((p) {
              if (activeFilter == "All") return true;
              final st = (p['status'] ?? '').toString().toLowerCase();
              if (activeFilter == "Present") return st.contains('present');
              if (activeFilter == "On Duty") return st.contains('duty');
              if (activeFilter == "Absent") return st.contains('absent');
              return true;
            }).toList();

            final screenHeight = MediaQuery.of(context).size.height;
            final sheetHeight = (screenHeight * 0.76).clamp(420.0, 700.0);

            return SafeArea(
              top: false,
              child: Container(
                height: sheetHeight,
                decoration: BoxDecoration(
                  color: AppColors.cardBg(context),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border.all(color: AppColors.cardBorder(context)),
                ),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top bar
                  const SizedBox(height: 12),
                  Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textMuted(context).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Fixed Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.teal.withValues(alpha: 0.22),
                                AppColors.teal.withValues(alpha: 0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.assignment_outlined, size: 22, color: AppColors.teal),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "$title Attendance",
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "CAPSTONE / SDP • Fall 2026-27",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary(context),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 22),
                          tooltip: "Re-fetch",
                          color: AppColors.teal,
                          onPressed: () async {
                            Navigator.pop(ctx);
                            _fetchCapstoneData(forceSync: true, showSheet: true);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(color: AppColors.cardBorder(context), height: 1),

                  // Scrollable Body
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      children: [
                        // 1. HERO ATTENDANCE CARD (Clean & Spacious)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.scaffoldBg(context),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.cardBorder(context)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  // Percentage Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: AppColors.badgeBg(pctNum).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: AppColors.badgeBg(pctNum).withValues(alpha: 0.35)),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          pctStr,
                                          style: TextStyle(
                                            fontSize: 26,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.badgeText(pctNum),
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                        Text(
                                          pctNum >= 75 ? "On Track" : "Low Attendance",
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.badgeText(pctNum).withValues(alpha: 0.85),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Progress summary
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Attendance Overview",
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary(context),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "${presentNum + odNum} attended out of $total sessions",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary(context),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: total > 0 ? (presentNum + odNum) / total : (pctNum / 100).clamp(0.0, 1.0),
                                            minHeight: 6,
                                            backgroundColor: AppColors.cardBorder(context),
                                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.badgeBg(pctNum)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Divider(color: AppColors.cardBorder(context), height: 1),
                              const SizedBox(height: 12),
                              // 4 stats neatly laid out
                              Row(
                                children: [
                                  Expanded(child: _capstoneStatItem("Present", present, AppColors.teal)),
                                  Expanded(child: _capstoneStatItem("On Duty", onDuty, AppColors.primary)),
                                  Expanded(child: _capstoneStatItem("Absent", absent, AppColors.red)),
                                  Expanded(child: _capstoneStatItem("Total", total.toString(), AppColors.textPrimary(context))),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // 2. GUIDE & REGISTRATION DETAILS
                        if (guideStatus != '-' || regDate != '-') ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.scaffoldBg(context),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.cardBorder(context)),
                            ),
                            child: Column(
                              children: [
                                if (guideStatus != '-')
                                  _capstoneInfoRow("Guide Status", guideStatus),
                                if (guideStatus != '-' && regDate != '-')
                                  Divider(color: AppColors.cardBorder(context), height: 16),
                                if (regDate != '-')
                                  _capstoneInfoRow("Registration", regDate),
                              ],
                            ),
                          ),
                        ],

                        // 3. PUNCH HISTORY
                        if (punches.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Punch History (${punches.length})",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                              Text(
                                "${filteredPunches.length} shown",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Filter chips
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: ["All", "Present", "On Duty", "Absent"].map((filter) {
                                final isSelected = activeFilter == filter;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    label: Text(filter),
                                    selected: isSelected,
                                    onSelected: (_) {
                                      setSheetState(() => activeFilter = filter);
                                    },
                                    backgroundColor: AppColors.scaffoldBg(context),
                                    selectedColor: AppColors.teal.withValues(alpha: 0.2),
                                    labelStyle: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                      color: isSelected ? AppColors.teal : AppColors.textSecondary(context),
                                    ),
                                    side: BorderSide(
                                      color: isSelected ? AppColors.teal : AppColors.cardBorder(context),
                                    ),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Punch items
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.scaffoldBg(context),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.cardBorder(context)),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: filteredPunches.length,
                              separatorBuilder: (context, index) => Divider(color: AppColors.cardBorder(context), height: 1),
                              itemBuilder: (context, idx) {
                                final punch = filteredPunches[idx];
                                final status = (punch['status'] ?? '').toString();
                                final isOD = status.toLowerCase().contains('duty');
                                final isAbsent = status.toLowerCase().contains('absent');
                                final isPresent = status.toLowerCase().contains('present');
                                final isHoliday = status.toLowerCase().contains('holiday') || status.toLowerCase().contains('no instructional');
                                final statusColor = isPresent 
                                    ? AppColors.teal 
                                    : (isOD 
                                        ? AppColors.primary 
                                        : (isAbsent 
                                            ? AppColors.red 
                                            : (isHoliday ? AppColors.textMuted(context) : AppColors.teal)));

                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  child: Row(
                                    children: [
                                      // Calendar icon
                                      Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textMuted(context)),
                                      const SizedBox(width: 8),
                                      Text(
                                        punch['date'] ?? '',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary(context),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        punch['day'] ?? '',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary(context),
                                        ),
                                      ),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: statusColor.withValues(alpha: 0.2)),
                                        ),
                                        child: Text(
                                          status,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
  }

  Widget _capstoneStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary(context),
          ),
        ),
      ],
    );
  }

  Widget _capstoneInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(label, style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context), fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value, style: TextStyle(fontSize: 13, color: AppColors.textPrimary(context))),
        ),
      ],
    );
  }

  Widget _attendanceCard(Map<String, dynamic> subject, int index) {
    final percent = parsePercent(subject["attendance"] ?? "0");
    final courseCode = subject["course_code"] ?? "";
    final subjectName = subject["subject"] ?? "Unknown";
    final totalClasses = subject["total_classes"] ?? "-";
    final present = subject["present"] ?? "-";
    final isLab = (subject["type"] ?? "").toString().toLowerCase().contains("lab");

    // Calculate classes that can be missed
    int presentInt = int.tryParse(present.toString()) ?? 0;
    int totalInt = int.tryParse(totalClasses.toString()) ?? 0;
    int canMiss = _classesCanMiss(presentInt, totalInt);
    int needToAttend = _classesToAttend(presentInt, totalInt);
    bool isDanger = percent < 75;

    return GestureDetector(
      onTap: () {
        if (totalClasses != "-") {
          _showAttendanceDetailSheet(context, subject, subjectName, presentInt, totalInt);
        }
      },
      child: GlassCard(
        accentColor: (isLab ? AppColors.teal : AppColors.primary).withOpacity(0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: icon + code + name + badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        (isLab ? AppColors.teal : AppColors.primary).withOpacity(0.15),
                        (isLab ? AppColors.teal : AppColors.primary).withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                      isLab ? Icons.science_outlined : Icons.menu_book,
                      size: 18,
                      color: isLab ? AppColors.teal : AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (courseCode.isNotEmpty)
                        Text(
                          courseCode,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      Text(
                        subjectName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                // Attendance badge with gradient
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.badgeBg(percent),
                        AppColors.badgeBg(percent).withOpacity(0.5),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.badgeText(percent).withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    "${percent.toStringAsFixed(0)}%",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.badgeText(percent),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Stat boxes row
            Row(
              children: [
                Expanded(
                  child: StatBox(
                    icon: Icons.check_circle_outline,
                    iconColor: AppColors.teal,
                    value: present != "-" && totalClasses != "-"
                        ? "$present/$totalClasses"
                        : "-",
                    label: "Present",
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatBox(
                    icon: isDanger ? Icons.warning_amber_rounded : Icons.skip_next_outlined,
                    iconColor: isDanger ? AppColors.red : AppColors.orange,
                    value: totalInt > 0 ? (isDanger ? "$needToAttend" : "$canMiss") : "-",
                    label: isDanger ? "Need" : "Can Miss",
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatBox(
                    icon: Icons.percent,
                    iconColor: AppColors.primary,
                    value: "${percent.toStringAsFixed(0)}%",
                    label: "Overall",
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonLoading() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 5,
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 120,
        decoration: BoxDecoration(
          color: AppColors.cardBg(context).withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8))),
                  const SizedBox(width: 12),
                  Expanded(child: Container(height: 16, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(4)))),
                  const SizedBox(width: 12),
                  Container(width: 50, height: 24, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8))),
                ],
              ),
              const Spacer(),
              Row(
                children: List.generate(3, (i) => Expanded(
                  child: Container(margin: EdgeInsets.only(right: i < 2 ? 8 : 0), height: 40, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.05), borderRadius: BorderRadius.circular(8))),
                )),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Attendance Detail Bottom Sheet (Tabbed: Calculator + Day-wise) ──────────

class _AttendanceDetailBottomSheet extends StatefulWidget {
  final Map<String, dynamic> subject;
  final String subjectName;
  final int presentInt;
  final int totalInt;
  final String username;
  final void Function(BuildContext) calculatorBuilder;

  const _AttendanceDetailBottomSheet({
    required this.subject,
    required this.subjectName,
    required this.presentInt,
    required this.totalInt,
    required this.username,
    required this.calculatorBuilder,
  });

  @override
  State<_AttendanceDetailBottomSheet> createState() => _AttendanceDetailBottomSheetState();
}

class _AttendanceDetailBottomSheetState extends State<_AttendanceDetailBottomSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List _detailRecords = [];
  bool _isLoadingDetail = false;
  bool _detailFetched = false;
  String? _detailError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_detailFetched) {
        _fetchDetail();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetail({bool forceSync = false}) async {
    final courseId = widget.subject["course_id"] ?? "";
    final courseType = widget.subject["course_type_code"] ?? "";
    
    if (courseId.isEmpty || courseType.isEmpty) {
      setState(() {
        _detailError = "Course detail not available";
        _detailFetched = true;
      });
      return;
    }

    setState(() {
      _isLoadingDetail = true;
      _detailError = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final semId = prefs.getString('semesterId') ?? "";
      
      final records = await ApiService.getAttendanceDetail(
        widget.username,
        semesterId: semId,
        courseId: courseId,
        courseType: courseType,
        forceSync: forceSync,
      );
      
      if (mounted) {
        setState(() {
          _detailRecords = records;
          _isLoadingDetail = false;
          _detailFetched = true;
          _detailError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // If we already have records, keep them visible instead of showing error
          if (_detailRecords.isEmpty) {
            _detailError = "Unable to fetch details. Pull down to retry.";
          }
          _isLoadingDetail = false;
          _detailFetched = true;
        });
      }
    }
  }

  double parsePercent(String value) {
    return double.tryParse(value.replaceAll("%", "").trim()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final percent = parsePercent(widget.subject["attendance"] ?? "0");
    final courseCode = widget.subject["course_code"] ?? "";
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textMuted(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withOpacity(0.15),
                        AppColors.primary.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.analytics_outlined, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.subjectName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (courseCode.isNotEmpty)
                        Text(
                          courseCode,
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.badgeBg(percent),
                        AppColors.badgeBg(percent).withOpacity(0.5),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    "${percent.toStringAsFixed(0)}%",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.badgeText(percent),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Tab bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.scaffoldBg(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textSecondary(context),
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: "Calculator"),
                Tab(text: "Day-wise"),
              ],
            ),
          ),

          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Calculator
                _buildCalculatorTab(),
                // Tab 2: Day-wise detail
                _buildDaywiseTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalculatorTab() {
    return StatefulBuilder(
      builder: (context, setCalcState) {
        int simPresent = widget.presentInt;
        int simTotal = widget.totalInt;
        
        return _CalculatorContent(
          initialPresent: widget.presentInt,
          initialTotal: widget.totalInt,
          subjectName: widget.subjectName,
        );
      },
    );
  }

  Widget _buildDaywiseTab() {
    if (_isLoadingDetail) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text("Fetching attendance details...", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_detailError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.red.withOpacity(0.5)),
            const SizedBox(height: 12),
            Text(_detailError!, style: TextStyle(color: AppColors.textSecondary(context))),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                _detailFetched = false;
                _fetchDetail();
              },
              icon: const Icon(Icons.refresh, color: AppColors.primary),
              label: const Text("Retry", style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      );
    }

    if (!_detailFetched) {
      // Auto-fetch when tab is first shown
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchDetail());
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_detailRecords.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _fetchDetail(forceSync: true),
        color: AppColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.15),
            Icon(Icons.inbox_outlined, size: 48, color: AppColors.textMuted(context)),
            const SizedBox(height: 12),
            Center(child: Text("No records found", style: TextStyle(color: AppColors.textSecondary(context)))),
            const SizedBox(height: 8),
            Center(child: Text("Pull down to refresh", style: TextStyle(color: AppColors.textMuted(context), fontSize: 12))),
          ],
        ),
      );
    }

    // Count present/absent
    int presentCount = _detailRecords.where((r) => (r["status"] ?? "").toString().toLowerCase() == "present").length;
    int absentCount = _detailRecords.where((r) => (r["status"] ?? "").toString().toLowerCase() == "absent").length;

    return Column(
      children: [
        // Summary row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              _summaryChip(Icons.check_circle, AppColors.teal, "Present: $presentCount"),
              const SizedBox(width: 8),
              _summaryChip(Icons.cancel, AppColors.red, "Absent: $absentCount"),
              const SizedBox(width: 8),
              _summaryChip(Icons.class_, AppColors.primary, "Total: ${_detailRecords.length}"),
            ],
          ),
        ),
        
        // Column headers
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(
            children: [
              SizedBox(width: 32, child: Text("#", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textSecondary(context)))),
              Expanded(flex: 3, child: Text("Date", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textSecondary(context)))),
              Expanded(flex: 3, child: Text("Day / Time", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textSecondary(context)))),
              Expanded(flex: 2, child: Text("Status", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textSecondary(context)))),
            ],
          ),
        ),

        // Records list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
            physics: const BouncingScrollPhysics(),
            itemCount: _detailRecords.length,
            itemBuilder: (context, index) {
              final record = _detailRecords[index];
              final status = (record["status"] ?? "").toString();
              final isPresent = status.toLowerCase() == "present";
              final isAbsent = status.toLowerCase() == "absent";
              final statusColor = isPresent ? AppColors.teal : (isAbsent ? AppColors.red : AppColors.orange);
              final remark = (record["remark"] ?? "").toString();

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: index.isEven ? Colors.transparent : AppColors.scaffoldBg(context).withOpacity(0.5),
                  border: Border(
                    bottom: BorderSide(color: AppColors.cardBorder(context).withOpacity(0.3)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text(
                            record["serial"] ?? "${index + 1}",
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            record["date"] ?? "-",
                            style: TextStyle(fontSize: 13, color: AppColors.textPrimary(context), fontWeight: FontWeight.w500),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            record["day_time"] ?? "-",
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              status,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (remark.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 32, top: 4),
                        child: Text(
                          remark,
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted(context), fontStyle: FontStyle.italic),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _summaryChip(IconData icon, Color color, String text) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Calculator Tab Content ─────────────────────────────────────────────────

class _CalculatorContent extends StatefulWidget {
  final int initialPresent;
  final int initialTotal;
  final String subjectName;

  const _CalculatorContent({
    required this.initialPresent,
    required this.initialTotal,
    required this.subjectName,
  });

  @override
  State<_CalculatorContent> createState() => _CalculatorContentState();
}

class _CalculatorContentState extends State<_CalculatorContent> {
  late int simPresent;
  late int simTotal;

  @override
  void initState() {
    super.initState();
    simPresent = widget.initialPresent;
    simTotal = widget.initialTotal;
  }

  int _classesCanMiss(int attended, int total) {
    if (total == 0) return 0;
    int canMiss = 0;
    while (true) {
      double newPct = (attended / (total + canMiss + 1)) * 100;
      if (newPct < 75) break;
      canMiss++;
      if (canMiss > 200) break;
    }
    return canMiss;
  }

  int _classesToAttend(int attended, int total) {
    if (total == 0) return 0;
    double pct = (attended / total) * 100;
    if (pct >= 75) return 0;
    int need = 0;
    while (true) {
      need++;
      double newPct = ((attended + need) / (total + need)) * 100;
      if (newPct >= 75) break;
      if (need > 200) break;
    }
    return need;
  }

  @override
  Widget build(BuildContext context) {
    double simPct = simTotal > 0 ? (simPresent / simTotal) * 100 : 0;
    int canMiss = _classesCanMiss(simPresent, simTotal);
    int needAttend = _classesToAttend(simPresent, simTotal);
    bool isDanger = simPct < 75;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Simulated percentage display
          Text(
            "${simPct.toStringAsFixed(1)}%",
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: isDanger ? AppColors.red : AppColors.teal,
            ),
          ),
          Text("Simulated Attendance", style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13)),
          
          const SizedBox(height: 24),
          
          // Present / Absent controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(
                children: [
                  Text("Present", style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: AppColors.red),
                        onPressed: () {
                          setState(() { if (simPresent > 0) simPresent--; });
                        },
                      ),
                      SizedBox(
                        width: 35,
                        child: Text("$simPresent", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: AppColors.teal),
                        onPressed: () {
                          setState(() { simPresent++; simTotal++; });
                        },
                      ),
                    ],
                  ),
                ],
              ),
              Column(
                children: [
                  Text("Absent", style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: AppColors.red),
                        onPressed: () {
                          setState(() { if (simTotal > simPresent) simTotal--; });
                        },
                      ),
                      SizedBox(
                        width: 35,
                        child: Text("${simTotal - simPresent}", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: AppColors.teal),
                        onPressed: () {
                          setState(() { simTotal++; });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Status message
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: (isDanger ? AppColors.red : AppColors.teal).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  isDanger ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  color: isDanger ? AppColors.red : AppColors.teal,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isDanger
                        ? "You need to attend $needAttend more class${needAttend == 1 ? '' : 'es'} to reach 75%"
                        : "You can miss $canMiss more class${canMiss == 1 ? '' : 'es'} and stay above 75%",
                    style: TextStyle(
                      color: isDanger ? AppColors.red : AppColors.teal,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Reset button
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppColors.cardBorder(context)),
                ),
              ),
              onPressed: () {
                setState(() {
                  simPresent = widget.initialPresent;
                  simTotal = widget.initialTotal;
                });
              },
              child: Text("Reset to Current", style: TextStyle(color: AppColors.textPrimary(context), fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
