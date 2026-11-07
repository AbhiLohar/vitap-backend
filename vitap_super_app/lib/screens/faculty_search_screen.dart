import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../services/error_formatter.dart';
import '../widgets/glass_card.dart';

class FacultySearchScreen extends StatefulWidget {
  final String username;

  const FacultySearchScreen({super.key, required this.username});

  @override
  State<FacultySearchScreen> createState() => _FacultySearchScreenState();
}

class _FacultySearchScreenState extends State<FacultySearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List _allFaculties = [];
  List _displayedFaculties = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _fetchInitialData() async {
    try {
      final results = await ApiService.getAllFaculties(widget.username);
      if (mounted) {
        setState(() {
          _allFaculties = results;
          _displayedFaculties = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorFormatter.format(e))),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final text = _searchController.text.trim().toLowerCase();
    if (text.isEmpty) {
      setState(() {
        _displayedFaculties = _allFaculties;
      });
      return;
    }

    setState(() {
      _displayedFaculties = _allFaculties.where((f) {
        final name = (f["name"] ?? "").toString().toLowerCase();
        final empId = (f["emp_id"] ?? "").toString().toLowerCase();
        final school = (f["school"] ?? "").toString().toLowerCase();
        return name.contains(text) || empId.contains(text) || school.contains(text);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          "Faculty Search",
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
      body: Column(
        children: [
          // Search bar with auto-suggest
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.cardBg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cardBorder(context)),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Search by faculty name or ID...",
                  hintStyle: TextStyle(color: AppColors.textMuted(context), fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded, color: primaryColor, size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted(context)),
                          onPressed: () {
                            _searchController.clear();
                            _searchFocus.unfocus();
                            setState(() {
                              _displayedFaculties = _allFaculties;
                            });
                          },
                        )
                      : null,
                ),
              ),
            ),
          ),

          // Results list
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: primaryColor, strokeWidth: 2.5))
                : _displayedFaculties.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 64,
                              color: AppColors.textMuted(context),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "No faculty found matching your search",
                              style: TextStyle(color: AppColors.textSecondary(context)),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _displayedFaculties.length,
                        itemBuilder: (context, index) {
                          final f = _displayedFaculties[index];
                          return _FacultyCard(
                            faculty: Map<String, dynamic>.from(f),
                            index: index,
                            username: widget.username,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _FacultyCard extends StatefulWidget {
  final Map<String, dynamic> faculty;
  final int index;
  final String username;
  const _FacultyCard({required this.faculty, required this.index, required this.username});

  @override
  State<_FacultyCard> createState() => _FacultyCardState();
}

class _FacultyCardState extends State<_FacultyCard> {
  bool _isLoadingDetails = false;

  Future<void> _showDetails() async {
    final empId = widget.faculty["emp_id"]?.toString() ?? "";
    if (empId.isEmpty) return;

    setState(() => _isLoadingDetails = true);
    try {
      final details = await ApiService.getFacultyDetails(widget.username, empId);
      if (!mounted) return;
      
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _FacultyDetailsSheet(details: details),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorFormatter.format(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return TweenAnimationBuilder(
      duration: Duration(milliseconds: 300 + (widget.index * 50)),
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, double value, child) {
        return Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: _showDetails,
                child: GlassCard(
                  accentColor: primaryColor.withOpacity(0.4),
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: primaryColor.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    (widget.faculty["name"] ?? "F").toString().isNotEmpty
                                        ? (widget.faculty["name"] ?? "F").toString().substring(0, 1)
                                        : "F",
                                    style: TextStyle(
                                      color: primaryColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.faculty["name"] ?? "Unknown",
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary(context),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.faculty["designation"] ?? "",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _infoRow(context, Icons.school_outlined, widget.faculty["school"] ?? "-"),
                          if (widget.faculty["emp_id"] != null && widget.faculty["emp_id"].toString().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            _infoRow(context, Icons.badge_outlined, "ID: ${widget.faculty["emp_id"]}"),
                          ],
                        ],
                      ),
                      if (_isLoadingDetails)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black12,
                            child: Center(
                              child: CircularProgressIndicator(color: primaryColor, strokeWidth: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String text) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Icon(icon, size: 14, color: primaryColor.withOpacity(0.8)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary(context)),
          ),
        ),
      ],
    );
  }
}

class _FacultyDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> details;
  const _FacultyDetailsSheet({required this.details});

  @override
  Widget build(BuildContext context) {
    final officeHours = (details["office_hours"] as List?) ?? [];
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    return Container(
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            details["name"] ?? "Details",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            details["designation"] ?? "",
            style: TextStyle(
              fontSize: 13,
              color: primaryColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          
          if ((details["department"] ?? "").toString().isNotEmpty)
            _buildDetailRow(context, Icons.business_outlined, "Department", details["department"], primaryColor),
          
          if ((details["school_centre"] ?? "").toString().isNotEmpty)
            _buildDetailRow(context, Icons.school_outlined, "School/Centre", details["school_centre"], primaryColor),
            
          if ((details["email"] ?? "").toString().isNotEmpty)
            _buildDetailRow(context, Icons.email_outlined, "Email", details["email"], primaryColor),
            
          if ((details["cabin_number"] ?? "").toString().isNotEmpty)
            _buildDetailRow(context, Icons.meeting_room_outlined, "Cabin", details["cabin_number"], primaryColor),
            
          if (officeHours.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              "Office Hours",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardBg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cardBorder(context)),
              ),
              child: Column(
                children: officeHours.map((oh) => Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(Icons.access_time_rounded, size: 15, color: AppColors.textSecondary(context)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          oh["day"] ?? "",
                          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 13),
                        ),
                      ),
                      Text(
                        oh["timings"] ?? "",
                        style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, IconData icon, String label, String value, Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
