import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';

class ExamScheduleScreen extends StatefulWidget {
  final String username;
  const ExamScheduleScreen({super.key, required this.username});
  @override
  State<ExamScheduleScreen> createState() => _ExamScheduleScreenState();
}

class _ExamScheduleScreenState extends State<ExamScheduleScreen> {
  List allSchedule = []; // All exam data fetched at once
  List examTypes = [];
  late ValueNotifier<String?> selectedTypeNotifier;
  late PageController _pageController;
  String? semesterId;
  bool isLoading = true;
  bool isTypesLoading = true;

  @override
  void initState() { 
    super.initState(); 
    selectedTypeNotifier = ValueNotifier<String?>(null);
    _pageController = PageController();
    _init(); 
  }

  @override
  void dispose() {
    selectedTypeNotifier.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    semesterId = prefs.getString('semesterId');
    await _fetchExamTypes();
    
    // Set default type
    if (examTypes.isNotEmpty) {
      selectedTypeNotifier.value = examTypes.first['id'];
    } else {
      setState(() {
        examTypes = [{'id': 'CAT-1', 'name': 'CAT-1'}, {'id': 'CAT-2', 'name': 'CAT-2'}, {'id': 'FAT', 'name': 'FAT'}];
        selectedTypeNotifier.value = 'FAT';
      });
    }
    
    // Fetch ALL exam data once (backend returns all types together)
    await _fetchAllSchedule();
  }

  void _sortExamTypes() {
    examTypes.sort((a, b) {
      final nameA = (a['name'] ?? a['id']).toString().toUpperCase().replaceAll(" ", "");
      final nameB = (b['name'] ?? b['id']).toString().toUpperCase().replaceAll(" ", "");
      
      int weightA = nameA.contains("CAT1") || nameA.contains("CAT-1") ? 1 
                  : nameA.contains("CAT2") || nameA.contains("CAT-2") ? 2 
                  : nameA.contains("FAT") ? 3 : 4;
                  
      int weightB = nameB.contains("CAT1") || nameB.contains("CAT-1") ? 1 
                  : nameB.contains("CAT2") || nameB.contains("CAT-2") ? 2 
                  : nameB.contains("FAT") ? 3 : 4;
                  
      return weightA.compareTo(weightB);
    });
  }

  Future<void> _fetchExamTypes() async {
    try {
      final types = await ApiService.getExamTypes(
        widget.username, 
        semesterId: semesterId,
        onSync: (freshData) {
          if (mounted) setState(() { examTypes = freshData; _sortExamTypes(); isTypesLoading = false; });
        }
      );
      if (mounted) setState(() { examTypes = types; _sortExamTypes(); isTypesLoading = false; });
    } catch (e) { if (mounted) setState(() => isTypesLoading = false); }
  }

  Future<void> _fetchAllSchedule({bool forceSync = false}) async {
    if (mounted && allSchedule.isEmpty) setState(() => isLoading = true);
    try {
      final data = await ApiService.getExamSchedule(
        widget.username, 
        semesterId: semesterId, 
        forceSync: forceSync,
        onSync: (freshData) {
          if (mounted) {
            setState(() { allSchedule = freshData; isLoading = false; });
            _detectExamTypes(freshData);
          }
        }
      );
      if (mounted) {
        setState(() { allSchedule = data; isLoading = false; });
        _detectExamTypes(data);
      }
    } catch (e) { if (mounted) setState(() => isLoading = false); }
  }

  void _detectExamTypes(List data) {
    if (data.isNotEmpty && examTypes.length <= 3) {
      final typesInData = data.map((e) => e["exam_type"]?.toString() ?? "").where((t) => t.isNotEmpty).toSet().toList();
      if (typesInData.isNotEmpty) {
        setState(() {
          examTypes = typesInData.map((t) => {'id': t, 'name': t}).toList();
          _sortExamTypes();
          if (selectedTypeNotifier.value == null || !typesInData.contains(selectedTypeNotifier.value)) {
            selectedTypeNotifier.value = examTypes.first['id'];
          }
        });
      }
    }
  }

  List _getFilteredSchedule(String? type) {
    if (type == null || allSchedule.isEmpty) return allSchedule;
    return allSchedule.where((item) {
      final examType = (item["exam_type"] ?? "").toString().toUpperCase();
      return examType == type.toUpperCase();
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          "Exam Schedule",
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
        centerTitle: false,
      ),
      body: Column(children: [
        if (isTypesLoading)
          LinearProgressIndicator(color: primaryColor, backgroundColor: Colors.transparent)
        else if (examTypes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.cardBg(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardBorder(context)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                child: ValueListenableBuilder<String?>(
                  valueListenable: selectedTypeNotifier,
                  builder: (context, selectedType, _) {
                    return Row(
                      children: examTypes.asMap().entries.map((entry) {
                        final index = entry.key;
                        final type = entry.value;
                        final isSelected = selectedType == type['id'];
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: GestureDetector(
                            onTap: () { 
                              selectedTypeNotifier.value = type['id']; 
                              _pageController.jumpToPage(index);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? primaryColor : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: primaryColor.withOpacity(0.2),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Text(
                                type['name'],
                                style: TextStyle(
                                  color: isSelected ? Colors.white : AppColors.textSecondary(context),
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              if (examTypes.isNotEmpty) {
                selectedTypeNotifier.value = examTypes[index]['id'];
              }
            },
            itemCount: examTypes.isEmpty ? 1 : examTypes.length,
            itemBuilder: (context, pageIndex) {
              final typeFilter = examTypes.isEmpty ? null : examTypes[pageIndex]['id'];
              final fSchedule = _getFilteredSchedule(typeFilter);

              return RefreshIndicator(
                onRefresh: () => _fetchAllSchedule(forceSync: true),
                color: primaryColor,
                child: isLoading
                    ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor))
                    : fSchedule.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                              Icon(Icons.event_busy_rounded, size: 48, color: AppColors.textMuted(context)),
                              const SizedBox(height: 12),
                              Center(child: Text("No schedule available for ${typeFilter ?? 'this type'}", style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14))),
                            ])
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: fSchedule.length,
                            itemBuilder: (context, index) => _examCard(fSchedule[index], index),
                          ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _examCard(Map<String, dynamic> item, int index) {
    // New backend returns seat_location and seat_no as separate fields
    String seatLoc = item["seat_location"] ?? "-";
    String seatNum = item["seat_no"] ?? "-";

    String daysText = "";
    Color badgeColor = Colors.grey;
    if (item["date"] != null && item["date"] != "-") {
      try {
        final parsedDate = DateFormat("dd-MMM-yyyy").parse(item["date"]);
        final now = DateTime.now();
        final diff = parsedDate.difference(DateTime(now.year, now.month, now.day)).inDays;
        
        if (diff < 0) {
          daysText = "Completed";
          badgeColor = AppColors.teal;
        } else if (diff == 0) {
          daysText = "Today";
          badgeColor = AppColors.red;
        } else if (diff == 1) {
          daysText = "Tomorrow";
          badgeColor = AppColors.orange;
        } else {
          daysText = "In $diff days";
          badgeColor = Theme.of(context).colorScheme.primary;
        }
      } catch (e) {
        daysText = "Scheduled";
      }
    } else {
      daysText = "Scheduled";
    }

    return TweenAnimationBuilder(
      duration: Duration(milliseconds: 300 + (index * 50)),
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, double value, child) {
        return Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.scaffoldBg(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.cardBorder(context)),
                        ),
                        child: Text(
                          "${item["date"] ?? "-"} • ${item["session"] ?? "-"}",
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context), fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.scaffoldBg(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.cardBorder(context)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 6, height: 6, decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle)),
                            const SizedBox(width: 5),
                            Text(daysText, style: TextStyle(fontSize: 11, color: badgeColor, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item["subject"] ?? "Unknown Subject",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item["course_code"] ?? "",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary(context)),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildGridItem(Icons.access_time_rounded, "Time", item["exam_time"] ?? "-")),
                      Expanded(child: _buildGridItem(Icons.location_on_outlined, "Venue", item["venue"] ?? "-")),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildGridItem(Icons.chair_outlined, "Seat Location", seatLoc)),
                      Expanded(child: _buildGridItem(Icons.numbers_rounded, "Seat Number", seatNum)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.scaffoldBg(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.cardBorder(context)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.access_time_rounded, size: 14, color: AppColors.textMuted(context)),
                        const SizedBox(width: 8),
                        Text(
                          "Reporting: ${item["reporting_time"] ?? "-"}",
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridItem(IconData icon, String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: AppColors.textMuted(context)),
            const SizedBox(width: 5),
            Text(title, style: TextStyle(fontSize: 11, color: AppColors.textMuted(context))),
          ],
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context)),
          ),
        ),
      ],
    );
  }
}
