import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../services/error_formatter.dart';
import '../services/notification_service.dart';
import '../widgets/glass_card.dart';
import 'notes_calendar_screen.dart';

class TimetableScreen extends StatefulWidget {
  final String username;
  final ValueNotifier<String>? semesterNotifier;

  const TimetableScreen({super.key, required this.username, this.semesterNotifier});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen>
    with AutomaticKeepAliveClientMixin {
  List timetable = [];
  bool isLoading = true;
  String currentSemester = "Fetching...";

  late DateTime today;
  late ValueNotifier<int> selectedDayNotifier;
  late List<DateTime> weekDays;
  late PageController _pageController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    today = DateTime.now();
    int initialDay = today.weekday <= 6 ? today.weekday - 1 : 0;
    selectedDayNotifier = ValueNotifier<int>(initialDay);
    _buildWeekDays();
    _pageController = PageController(initialPage: selectedDayNotifier.value);
    fetchTimetable();
    widget.semesterNotifier?.addListener(_onSemesterChanged);
  }

  @override
  void dispose() {
    _pageController.dispose();
    selectedDayNotifier.dispose();
    widget.semesterNotifier?.removeListener(_onSemesterChanged);
    super.dispose();
  }

  void _onSemesterChanged() {
    if (mounted) {
      fetchTimetable(forceRefresh: true);
    }
  }

  void _buildWeekDays() {
    // Find Monday of the current week
    final monday = today.subtract(Duration(days: today.weekday - 1));
    weekDays = List.generate(6, (i) => monday.add(Duration(days: i))); // Mon-Sat
    selectedDayNotifier.value = today.weekday <= 6 ? today.weekday - 1 : 0;
  }

  Future<void> fetchTimetable({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final semesterId = prefs.getString('semesterId');
    final semName = prefs.getString('semesterName') ?? "Default Semester";

    if (mounted) {
      setState(() {
        currentSemester = semName;
        if (timetable.isEmpty) isLoading = true;
      });
    }

    try {
      final data = await ApiService.getTimetable(
        widget.username, 
        semesterId: semesterId, 
        forceSync: forceRefresh,
        onSync: (freshData) {
          if (mounted) {
            setState(() {
              timetable = freshData;
              isLoading = false;
            });
          }
          NotificationService.instance.scheduleTimetableNotifications(freshData);
        }
      );
      
      if (mounted) {
        setState(() {
          timetable = data;
          isLoading = false;
        });
      }
      NotificationService.instance.scheduleTimetableNotifications(data);
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

  String _dayAbbr(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days[weekday];
  }

  List _getFilteredTimetable(int dayIndex) {
    if (timetable.isEmpty) return [];
    
    final days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
    final selectedDayName = days[dayIndex];
    
    final filtered = timetable.where((item) {
      final itemDay = (item["day"] ?? "").toString().toLowerCase();
      final subject = (item["subject"] ?? "").toString().toUpperCase();
      final courseCode = (item["course_code"] ?? "").toString().toUpperCase();
      final slot = (item["slot"] ?? "").toString().toUpperCase();
      
      // Exclude Extracurricular/Club slots as they are free hours
      if (subject.contains("CLUB") || subject.contains("ECS") || 
          courseCode.contains("CLUB") || courseCode.contains("ECS") ||
          slot.contains("CLUB") || slot.contains("ECS")) {
        return false;
      }
      
      return itemDay.contains(selectedDayName.toLowerCase());
    }).toList();

    // Sort by time
    filtered.sort((a, b) {
      final timeA = (a["time"] ?? "00:00").toString();
      final timeB = (b["time"] ?? "00:00").toString();
      return timeA.compareTo(timeB);
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      body: SafeArea(
        child: Column(
          children: [
            // Header with subtle gradient
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
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            "Timetable",
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
                    GestureDetector(
                      onTap: () async {
                        final DateTime? picked = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NotesCalendarScreen(initialDate: today),
                          ),
                        );
                        if (picked != null) {
                          setState(() {
                            today = picked;
                            _buildWeekDays();
                          });
                          _pageController.jumpToPage(selectedDayNotifier.value);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.cardBg(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.cardBorder(context)),
                        ),
                        child: Icon(Icons.calendar_month,
                            color: AppColors.primary, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Day selector — pill-shaped
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.cardBg(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder(context)),
                ),
                child: ValueListenableBuilder<int>(
                  valueListenable: selectedDayNotifier,
                  builder: (context, selectedIndex, _) {
                    return Row(
                      children: List.generate(weekDays.length, (i) {
                        final day = weekDays[i];
                        final isSelected = i == selectedIndex;
                        final isToday = day.day == DateTime.now().day &&
                            day.month == DateTime.now().month &&
                            day.year == DateTime.now().year;

                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              selectedDayNotifier.value = i;
                              _pageController.jumpToPage(i);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                gradient: isSelected ? AppColors.primaryGradient : null,
                                color: isSelected ? null : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: AppColors.primary.withOpacity(0.25),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    "${day.day}",
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? Colors.white
                                          : isToday
                                              ? AppColors.primary
                                              : AppColors.textPrimary(context),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _dayAbbr(i),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                      color: isSelected
                                          ? Colors.white70
                                          : AppColors.textSecondary(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 4),

            // Class count indicator
            if (!isLoading)
              ValueListenableBuilder<int>(
                valueListenable: selectedDayNotifier,
                builder: (context, selectedIndex, _) {
                  final currentDayCount = _getFilteredTimetable(selectedIndex).length;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "$currentDayCount ${currentDayCount == 1 ? 'class' : 'classes'}",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

            const SizedBox(height: 4),

            // Timetable cards
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) => selectedDayNotifier.value = index,
                itemCount: weekDays.length,
                itemBuilder: (context, pageIndex) {
                  final filteredTT = _getFilteredTimetable(pageIndex);
                  
                  return isLoading && timetable.isEmpty
                      ? _buildSkeletonLoading()
                      : filteredTT.isEmpty
                          ? RefreshIndicator(
                              onRefresh: () => fetchTimetable(forceRefresh: true),
                              color: AppColors.primary,
                              child: ListView(
                                physics: const AlwaysScrollableScrollPhysics(
                                    parent: BouncingScrollPhysics()),
                                children: [
                                  SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                                  Icon(Icons.weekend_outlined,
                                      size: 48, color: AppColors.textMuted(context)),
                                  const SizedBox(height: 12),
                                  Center(
                                    child: Text("No classes today",
                                        style: TextStyle(
                                          color: AppColors.textSecondary(context),
                                          fontSize: 15,
                                        )),
                                  ),
                                  const SizedBox(height: 4),
                                  Center(
                                    child: Text("Enjoy your free time! 🏖️",
                                        style: TextStyle(
                                          color: AppColors.textMuted(context),
                                          fontSize: 13,
                                        )),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () => fetchTimetable(forceRefresh: true),
                              color: AppColors.primary,
                              child: ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(
                                    parent: BouncingScrollPhysics()),
                                padding: const EdgeInsets.only(bottom: 20),
                                itemCount: filteredTT.length,
                                itemBuilder: (context, index) {
                                  return _lectureCard(filteredTT[index], index);
                                },
                              ),
                            );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isClassRunning(String? start, String? end, String day) {
    if (start == null || end == null || start.isEmpty || end.isEmpty) return false;
    
    final now = DateTime.now();
    // Check if it's the correct day
    final days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
    if (days[now.weekday - 1].toLowerCase() != day.toLowerCase()) return false;

    try {
      final startTime = _parseTime(start);
      final endTime = _parseTime(end);
      final nowTime = TimeOfDay.fromDateTime(now);

      final nowMinutes = nowTime.hour * 60 + nowTime.minute;
      final startMinutes = startTime.hour * 60 + startTime.minute;
      final endMinutes = endTime.hour * 60 + endTime.minute;

      return nowMinutes >= startMinutes && nowMinutes <= endMinutes;
    } catch (e) {
      return false;
    }
  }

  TimeOfDay _parseTime(String time) {
    final parts = time.split(':');
    if (parts.length < 2) return const TimeOfDay(hour: 0, minute: 0);
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  Widget _lectureCard(Map<String, dynamic> item, int index) {
    final type = (item["type"] ?? "LECTURE").toString().toUpperCase();
    final isLab = type.contains("LAB") || type.contains("PRACTICAL");
    final isActive = _isClassRunning(item["time"], item["end_time"], item["day"] ?? "");
    final cardAccent = isLab ? AppColors.teal : AppColors.primary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: isActive 
          ? Border.all(color: AppColors.primary, width: 2)
          : null,
        boxShadow: isActive ? [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.15),
            blurRadius: 12,
            spreadRadius: 1,
          )
        ] : null,
      ),
      child: GlassCard(
        accentColor: isActive ? AppColors.primary : cardAccent.withOpacity(0.5),
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Type badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isLab ? AppColors.teal : AppColors.accent).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isLab ? Icons.science_outlined : Icons.menu_book, 
                          size: 14, color: isLab ? AppColors.teal : AppColors.accent),
                      const SizedBox(width: 4),
                      Text(
                        type,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isLab ? AppColors.teal : AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_filled, size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          "LIVE",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // Subject name
            Text(
              item["subject"] ?? "Unknown Subject",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context),
              ),
            ),
            
            const SizedBox(height: 4),
            
            // Faculty name
            Text(
              item["faculty"] ?? "Unknown Faculty",
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary(context),
                fontStyle: FontStyle.italic,
              ),
            ),

            const SizedBox(height: 12),

            // Venue + Course code row
            Row(
              children: [
                Expanded(
                  child: _chip(context, Icons.location_on_outlined, item["room"] ?? "-"),
                ),
                const SizedBox(width: 8),
                _chip(context, Icons.tag, item["course_code"] ?? "-"),
              ],
            ),

            const SizedBox(height: 8),

            // Time + Slot row
            Row(
              children: [
                Expanded(
                  child: _chip(
                    context,
                    Icons.access_time, 
                    "${_formatTime12Hour(item["time"]?.toString())} - ${_formatTime12Hour(item["end_time"]?.toString())}"
                  ),
                ),
                const SizedBox(width: 8),
                _chip(context, Icons.calendar_today_outlined, item["slot"] ?? "-"),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime12Hour(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty || timeStr == "-") return "-";
    try {
      final parts = timeStr.split(RegExp(r'[\s:]'));
      if (parts.length < 2) return timeStr;
      
      int hour = int.parse(parts[0]);
      final minStr = parts[1];
      
      String period = "AM";
      if (hour >= 12) {
        period = "PM";
        if (hour > 12) hour -= 12;
      } else if (hour == 0) {
        hour = 12;
      }
      
      final hourStr = hour.toString().padLeft(2, '0');
      return "$hourStr:$minStr $period";
    } catch (e) {
      return timeStr;
    }
  }

  Widget _chip(BuildContext context, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary(context)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary(context)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoading() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 4,
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 140,
        decoration: BoxDecoration(
          color: AppColors.cardBg(context).withOpacity(0.5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.cardBorder(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(width: 80, height: 20, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(6))),
                  Container(width: 40, height: 20, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(6))),
                ],
              ),
              const SizedBox(height: 12),
              Container(width: 200, height: 18, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 8),
              Container(width: 120, height: 14, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.05), borderRadius: BorderRadius.circular(4))),
              const Spacer(),
              Row(
                children: [
                  Expanded(child: Container(height: 32, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.05), borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(width: 8),
                  Expanded(child: Container(height: 32, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.05), borderRadius: BorderRadius.circular(10)))),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

}
