import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';

class MarksScreen extends StatefulWidget {
  final String username;
  const MarksScreen({super.key, required this.username});

  @override
  State<MarksScreen> createState() => _MarksScreenState();
}

class _MarksScreenState extends State<MarksScreen> {
  List<dynamic> allMarks = [];
  bool isLoading = true;
  String? semesterId;
  final List<String> markTypes = ["Theory", "Lab", "Project"];
  late ValueNotifier<String> selectedTypeNotifier;
  late PageController _pageController;
  String lastSynced = "Just now";

  @override
  void initState() {
    super.initState();
    selectedTypeNotifier = ValueNotifier<String>(markTypes.first);
    _pageController = PageController(initialPage: 0);
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
    await _fetchMarks();
  }

  Future<void> _fetchMarks({bool forceSync = false}) async {
    if (mounted && allMarks.isEmpty) setState(() => isLoading = true);
    try {
      final data = await ApiService.getMarks(
        widget.username, 
        semesterId: semesterId, 
        forceSync: forceSync,
        onSync: (freshData) {
          if (mounted) {
            setState(() {
              allMarks = freshData;
              isLoading = false;
            });
          }
        }
      );
      if (mounted) {
        setState(() {
          allMarks = data;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  List<dynamic> _getFilteredMarks(String typeFilter) {
    return allMarks.where((m) {
      final type = (m["type"] ?? "").toString().toUpperCase();
      if (typeFilter == "Theory") return type.contains("TH") || type == "ETH" || type == "THEORY";
      if (typeFilter == "Lab") return type.contains("LA") || type.contains("LO") || type == "ELA" || type == "LAB";
      if (typeFilter == "Project") return type.contains("PJ") || type.contains("PRJ") || type.contains("PBL") || type.contains("J") || type.contains("PROJ") || type.contains("STS") || type == "PROJECT";
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Marks",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              "Grouped by Subject",
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 28),
            onPressed: () => _fetchMarks(forceSync: true),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          // Tab Selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.cardBg(context),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: AppColors.cardBorder(context)),
              ),
              child: ValueListenableBuilder<String>(
                valueListenable: selectedTypeNotifier,
                builder: (context, selectedType, _) {
                  return Row(
                    children: markTypes.asMap().entries.map((entry) {
                      final index = entry.key;
                      final type = entry.value;
                      final isSelected = selectedType == type;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            selectedTypeNotifier.value = type;
                            _pageController.jumpToPage(index);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              gradient: isSelected ? AppColors.primaryGradient : null,
                              borderRadius: BorderRadius.circular(26),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              type,
                              style: TextStyle(
                                color: isSelected ? Colors.white : AppColors.textSecondary(context),
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 14,
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
          const SizedBox(height: 24),
          
          Expanded(
            child: isLoading
                ? _buildShimmer()
                : PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) => selectedTypeNotifier.value = markTypes[index],
                    itemCount: markTypes.length,
                    itemBuilder: (context, pageIndex) {
                      final typeFilter = markTypes[pageIndex];
                      final fMarks = _getFilteredMarks(typeFilter);

                      return RefreshIndicator(
                        onRefresh: () => _fetchMarks(forceSync: true),
                        color: AppColors.primary,
                        child: fMarks.isEmpty
                            ? _buildEmptyState(typeFilter)
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                itemCount: fMarks.length,
                                itemBuilder: (context, index) {
                                  return _MarksCard(item: fMarks[index], index: index);
                                },
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String typeFilter) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Icon(Icons.inbox_outlined, size: 64, color: AppColors.textMuted(context)),
        const SizedBox(height: 16),
        Center(
          child: Text(
            "No $typeFilter marks available",
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 140,
        decoration: BoxDecoration(
          color: AppColors.cardBg(context).withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder(context)),
        ),
      ),
    );
  }
}

class _MarksCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final int index;
  const _MarksCard({required this.item, required this.index});

  @override
  State<_MarksCard> createState() => _MarksCardState();
}

class _MarksCardState extends State<_MarksCard> {
  bool isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final components = widget.item["details"] as List<dynamic>? ?? [];
    
    double internalScored = 0.0;
    double internalMax = 0.0;
    double fatScored = 0.0;
    double fatMax = 0.0;

    for (var c in components) {
      String title = (c["mark_title"] ?? c["name"] ?? "").toString().toUpperCase();
      double scored = double.tryParse((c["scored_mark"] ?? c["marks"] ?? "0").toString()) ?? 0.0;
      double maxMark = double.tryParse((c["max_mark"] ?? c["max"] ?? "0").toString()) ?? 0.0;

      if (title.contains("FAT") || title.contains("FINAL")) {
        fatScored += scored;
        fatMax += maxMark;
      } else {
        internalScored += scored;
        internalMax += maxMark;
      }
    }

    // Convert Internal to 60 weightage and FAT to 40 weightage
    double convertedInternal = internalMax > 0 ? (internalScored / internalMax) * 60.0 : 0.0;
    double convertedFat = fatMax > 0 ? (fatScored / fatMax) * 40.0 : 0.0;
    
    double displayTotal = convertedInternal + convertedFat;
    double displayMax = (internalMax > 0 ? 60.0 : 0.0) + (fatMax > 0 ? 40.0 : 0.0);
    
    if (components.isEmpty) {
      displayTotal = 0.0;
      displayMax = 0.0;
    }

    return TweenAnimationBuilder(
      duration: Duration(milliseconds: 300 + (widget.index * 50)),
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, double value, child) {
        return Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.cardBg(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder(context)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: Column(
                  children: [
                    InkWell(
                      onTap: () => setState(() => isExpanded = !isExpanded),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.item["subject"] ?? "Unknown",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary(context),
                                          height: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        widget.item["faculty"] ?? "Unknown",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textSecondary(context),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    widget.item["course_code"] ?? "",
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      displayTotal.toStringAsFixed(1).replaceAll(".0", ""),
                                      style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary(context),
                                      ),
                                    ),
                                    Text(
                                      "/${displayMax.toStringAsFixed(0)}",
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textSecondary(context).withOpacity(0.4),
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Icon(
                                  isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                  color: AppColors.textMuted(context),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isExpanded)
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Column(
                          children: [
                            const Divider(color: Color(0xFF2A2A2A)),
                            const SizedBox(height: 12),
                            ...components.map((c) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      c["mark_title"] ?? c["name"] ?? "Internal",
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary(context),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    "${c["scored_mark"] ?? c["marks"] ?? "-"}/${c["max_mark"] ?? c["max"] ?? "-"}",
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary(context),
                                    ),
                                  ),
                                  if ((c["status"] ?? "").toString().isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      c["status"].toString().toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: c["status"].toString().toLowerCase().contains("pass") 
                                            ? AppColors.teal 
                                            : AppColors.orange,
                                      ),
                                    ),
                                  ]
                                ],
                              ),
                            )),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
