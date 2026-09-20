import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../services/error_formatter.dart';
import '../widgets/glass_card.dart';



class OutingScreen extends StatefulWidget {
  final String username;

  const OutingScreen({super.key, required this.username});

  @override
  State<OutingScreen> createState() => _OutingScreenState();
}

class _OutingScreenState extends State<OutingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List _generalOutings = [];
  List _weekendOutings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (mounted && (_generalOutings.isEmpty && _weekendOutings.isEmpty)) {
      setState(() => _isLoading = true);
    }
    try {
      final generalFuture = ApiService.getOuting(
        widget.username, 
        forceSync: forceRefresh,
        onSync: (freshData) {
          if (mounted) setState(() { _generalOutings = freshData; _isLoading = false; });
        }
      );
      final weekendFuture = ApiService.getWeekendOuting(
        widget.username, 
        forceSync: forceRefresh,
        onSync: (freshData) {
          if (mounted) setState(() { _weekendOutings = freshData; _isLoading = false; });
        }
      );
      
      final results = await Future.wait([generalFuture, weekendFuture]);
      if (mounted) {
        setState(() {
          _generalOutings = results[0];
          _weekendOutings = results[1];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Error loading outings: ${ErrorFormatter.format(e)}"),
          backgroundColor: AppColors.red,
        ));
      }
    }
  }

  Future<void> _deleteOuting(String id, bool isWeekend) async {
    // Show confirmation dialog first
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline, color: AppColors.red, size: 22),
            ),
            const SizedBox(width: 12),
            Text("Delete Request", style: TextStyle(color: AppColors.textPrimary(ctx), fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "Are you sure you want to delete this outing request? This action cannot be undone.",
          style: TextStyle(color: AppColors.textSecondary(ctx), fontSize: 14, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("Cancel", style: TextStyle(color: AppColors.textSecondary(ctx), fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
      Map<String, dynamic> res;
      if (isWeekend) {
        res = await ApiService.deleteWeekendOuting(widget.username, id);
      } else {
        res = await ApiService.deleteGeneralOuting(widget.username, id);
      }
      Navigator.pop(context); // pop loading
      
      final msg = (res["message"] ?? "").toString().toLowerCase();
      bool isSuccess = false;
      
      if (res["status"] == "success" || res["status"] == true) {
        isSuccess = true;
      } else if (res["status"] == "error" || res["status"] == false) {
        isSuccess = false;
      } else {
        if (msg.contains("success") || (msg.contains("deleted") && !msg.contains("fail") && !msg.contains("error") && !msg.contains("not") && !msg.contains("could not"))) {
          isSuccess = true;
        }
      }

      if (isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Deleted successfully"),
          backgroundColor: AppColors.primary,
        ));
        _loadData(forceRefresh: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res["message"] ?? "Failed to delete"),
          backgroundColor: AppColors.red,
        ));
      }
    } catch (e) {
      Navigator.pop(context); // pop loading
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ErrorFormatter.format(e)),
        backgroundColor: AppColors.red,
      ));
    }
  }



  void _showApplyModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ApplyOutingSheet(username: widget.username),
    ).then((value) {
      // The sheet only pops with a result on SUCCESS (errors stay in-sheet)
      if (value == null) return; // User swiped down / cancelled

      String message = "";
      bool success = false;

      if (value is Map<String, dynamic>) {
        success = value["success"] == true;
        message = (value["message"] ?? "").toString();
      } else if (value is String && value.isNotEmpty) {
        success = true;
        message = value;
      }

      if (success) {
        // Invalidate cache and reload immediately
        ApiService.clearOutingCache(widget.username);
        _loadData(forceRefresh: true);

        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => _OutingSuccessPage(
              message: message.isNotEmpty ? message : "Outing applied successfully!",
            ),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 300),
          ),
        ).then((_) {
          // Re-fetch when returning from success screen to ensure latest VTOP state is displayed
          _loadData(forceRefresh: true);
        });
      } else {
        _loadData(forceRefresh: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text("Outing Status"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary(context),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary(context),
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: "General"),
            Tab(text: "Weekend"),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showApplyModal,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add),
        label: const Text("Apply New"),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOutingList(_generalOutings, false),
          _buildOutingList(_weekendOutings, true),
        ],
      ),
    );
  }

  Widget _buildOutingList(List outings, bool isWeekend) {
    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      color: AppColors.primary,
      child: _isLoading && outings.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : outings.isEmpty
              ? ListView(
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.directions_walk_outlined, size: 64, color: AppColors.textMuted(context)),
                          const SizedBox(height: 16),
                            Text(
                              "No outing history found\n(For Dayscholars, outing data is not applicable)",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary(context), height: 1.5),
                            ),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: outings.length,
                  itemBuilder: (context, index) {
                    final o = outings[index];
                    final status = (o["status"] ?? "").toString().toLowerCase();
                    final isApproved = status.contains("approved") || status.contains("success") || status.contains("accepted");
                    final isPending = status.contains("pending") || status.contains("waiting");
                    final isRejected = status.contains("rejected");
                    final id = (o["bookingId"] ?? o["leaveId"] ?? o["id"] ?? "").toString();
                    
                    Color statusColor = AppColors.red; // default fallback
                    if (isApproved) statusColor = Colors.green;
                    else if (isPending) statusColor = AppColors.orange;
                    else if (isRejected) statusColor = AppColors.red;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GlassCard(
                        accentColor: statusColor.withOpacity(0.3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isApproved ? Icons.check_circle_outline : Icons.pending_actions,
                                    size: 18,
                                    color: statusColor,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        o["type"] ?? (isWeekend ? "Weekend Outing" : "General Outing"),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary(context),
                                        ),
                                      ),
                                      if (o["purpose"] != null && o["purpose"].toString().isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2, bottom: 2),
                                          child: Text(
                                            o["purpose"],
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.teal,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        o["status"] ?? "Unknown",
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: statusColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isPending && id.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: AppColors.red),
                                    onPressed: () => _deleteOuting(id, isWeekend),
                                    tooltip: "Delete Request",
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: _stat(context, Icons.logout, "Out Date", o["out_date"] ?? "-")),
                                Expanded(child: _stat(context, Icons.login, "In Date", o["in_date"] ?? "-")),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _infoRow(context, Icons.location_on_outlined, "Place: ${o["place"] ?? "-"}"),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _stat(BuildContext context, IconData icon, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: AppColors.textMuted(context)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, color: AppColors.textMuted(context))),
          ],
        ),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
      ],
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context)),
          ),
        ),
      ],
    );
  }
}

// ─── Apply Outing Form Sheet ──────────────────────────────────────────────

class _ApplyOutingSheet extends StatefulWidget {
  final String username;
  const _ApplyOutingSheet({required this.username});

  @override
  State<_ApplyOutingSheet> createState() => _ApplyOutingSheetState();
}

class _ApplyOutingSheetState extends State<_ApplyOutingSheet> {
  bool _isWeekend = false;
  final _formKey = GlobalKey<FormState>();
  
  final _placeController = TextEditingController();
  final _purposeController = TextEditingController();
  final _contactController = TextEditingController();
  
  String _selectedWeekendPlace = 'Vijayawada';
  String _selectedWeekendSlot = '9:30 AM- 3:30PM';

  DateTime? _outDate;
  TimeOfDay? _outTime;
  DateTime? _inDate;
  TimeOfDay? _inTime;
  
  bool _isSubmitting = false;
  String? _errorMessage;  // Inline error shown inside the sheet

  static const List<String> outingPlaces = ['Vijayawada', 'Guntur', 'Tenali', 'Eluru', 'Others'];
  static const List<String> outingTimeSlots = ['9:30 AM- 3:30PM', '10:30 AM- 4:30PM', '11:30 AM- 5:30PM', '12:30 PM- 6:30PM'];

  String _formatDate(DateTime? d) => d == null ? "" : DateFormat('dd-MMM-yyyy').format(d);
  
  String _formatTime(TimeOfDay? t) {
    if (t == null) return "";
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return "$h:$m";
  }

  bool _validateGeneralTime(TimeOfDay? time) {
    if (time == null) return false;
    final int hour = time.hour;
    final int minute = time.minute;
    if ((hour > 6 || (hour == 6 && minute >= 0)) && (hour < 22 || (hour == 22 && minute == 0))) {
      return true;
    }
    return false;
  }

  /// Check if we're past the deadline for the upcoming weekend.
  /// Sunday deadline: preceding Friday 11:59 PM.
  /// Monday deadline: preceding Sunday 11:59 PM.
  bool _isWeekendDeadlinePassed(DateTime targetDate) {
    final now = DateTime.now();
    if (targetDate.weekday == DateTime.sunday) {
      // For Sunday, deadline is the preceding Friday at 11:59 PM
      final friday = DateTime(targetDate.year, targetDate.month, targetDate.day).subtract(const Duration(days: 2));
      final deadline = DateTime(friday.year, friday.month, friday.day, 23, 59, 59);
      return now.isAfter(deadline);
    } else if (targetDate.weekday == DateTime.monday) {
      // For Monday, deadline is the preceding Sunday at 11:59 PM
      final sunday = DateTime(targetDate.year, targetDate.month, targetDate.day).subtract(const Duration(days: 1));
      final deadline = DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59);
      return now.isAfter(deadline);
    }
    return true;
  }

  /// Only allow Sunday (7) and Monday (1) in the date picker for weekend outings.
  /// Also blocks dates whose Friday 11:59 PM deadline has already passed.
  bool _weekendSelectableDayPredicate(DateTime day) {
    if (day.weekday != DateTime.sunday && day.weekday != DateTime.monday) {
      return false;
    }
    // Block if the Friday deadline for this weekend has passed
    return !_isWeekendDeadlinePassed(day);
  }

  Future<void> _submit() async {
    // Clear previous error
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;
    
    if (_outDate == null) {
      setState(() => _errorMessage = "Please select an Out Date");
      return;
    }

    if (_isWeekend) {
      if (_isWeekendDeadlinePassed(_outDate!)) {
        final dayStr = _outDate!.weekday == DateTime.sunday ? "Sunday" : "Monday";
        setState(() => _errorMessage = "Deadline has passed for this $dayStr. Please select another weekend.");
        return;
      }
    }

    if (!_isWeekend) {
      if (_outTime == null || _inDate == null || _inTime == null) {
        setState(() => _errorMessage = "Please select both In and Out Dates & Times");
        return;
      }
      if (!_validateGeneralTime(_outTime) || !_validateGeneralTime(_inTime)) {
        setState(() => _errorMessage = "General outing time must be between 06:00 AM and 10:00 PM");
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    
    try {
      Map<String, dynamic> res;
      if (_isWeekend) {
        res = await ApiService.applyWeekendOuting(
          username: widget.username,
          place: _selectedWeekendPlace,
          purpose: _purposeController.text,
          outDate: _formatDate(_outDate),
          outTime: _selectedWeekendSlot,
          contact: _contactController.text,
        );
      } else {
        res = await ApiService.applyGeneralOuting(
          username: widget.username,
          place: _placeController.text,
          purpose: _purposeController.text,
          outDate: _formatDate(_outDate),
          outTime: _formatTime(_outTime),
          inDate: _formatDate(_inDate),
          inTime: _formatTime(_inTime),
        );
      }
      
      final msg = (res["message"] ?? "").toString().trim();
      final statusStr = (res["status"] ?? "").toString().toLowerCase();
      
      // Determine success/failure: must be explicit success and no failure keywords
      final msgLower = msg.toLowerCase();
      bool isError = (statusStr != "success") ||
          msgLower.startsWith("error") || 
          msgLower.contains("failed") || 
          msgLower.contains("unable to") || 
          msgLower.contains("rejected") ||
          msgLower.contains("expired") ||
          msgLower.contains("check outing history");

      if (isError) {
        // Show error INSIDE the sheet — do NOT close it
        String errorMsg = msg.isNotEmpty ? msg : "Failed to apply for outing";
        // Clean "Error: " prefix for display
        if (errorMsg.toLowerCase().startsWith("error:")) {
          errorMsg = errorMsg.substring(6).trim();
        } else if (errorMsg.toLowerCase().startsWith("error")) {
          errorMsg = errorMsg.substring(5).trim();
        }
        if (mounted) {
          setState(() {
            _isSubmitting = false;
            _errorMessage = errorMsg;
          });
        }
        return; // DON'T close the sheet
      }
      
      // Success — clear cache immediately and close the sheet
      await ApiService.clearOutingCache(widget.username);

      String successMsg = msg;
      if (successMsg.toLowerCase().startsWith("error:")) {
        successMsg = successMsg.substring(6).trim();
      } else if (successMsg.toLowerCase().startsWith("error")) {
        successMsg = successMsg.substring(5).trim();
      }
      successMsg = successMsg.replaceAll(RegExp(r'[.\s]*Please check.*$', caseSensitive: false), '').trim();
      if (successMsg.isEmpty) successMsg = "Outing application submitted successfully!";
      
      if (mounted) {
        Navigator.pop(context, {"success": true, "message": successMsg});
      }
    } catch (e) {
      // Show network/exception error INSIDE the sheet
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = ErrorFormatter.format(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20, right: 20, top: 20,
      ),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: AppColors.textMuted(context).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text("Apply Outing", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
                const SizedBox(height: 20),
                
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<bool>(
                        title: const Text("General"),
                        value: false,
                        groupValue: _isWeekend,
                        onChanged: (v) => setState(() => _isWeekend = v!),
                        activeColor: AppColors.primary,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<bool>(
                        title: const Text("Weekend"),
                        value: true,
                        groupValue: _isWeekend,
                        onChanged: (v) => setState(() => _isWeekend = v!),
                        activeColor: AppColors.primary,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Form fields change based on outing type
                if (_isWeekend) ...[
                  _SmoothDropdown(
                    label: "Choose place of visit*",
                    value: _selectedWeekendPlace,
                    items: outingPlaces,
                    onChanged: (v) => setState(() => _selectedWeekendPlace = v),
                  ),
                ] else ...[
                  TextFormField(
                    controller: _placeController,
                    decoration: const InputDecoration(labelText: "Place of Visit*", border: OutlineInputBorder()),
                    validator: (v) => v!.isEmpty ? "Required" : null,
                  ),
                ],
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _purposeController,
                  decoration: const InputDecoration(labelText: "Purpose of Visit*", border: OutlineInputBorder()),
                  validator: (v) => v!.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 16),
                
                if (_isWeekend) ...[
                  // Weekend deadline info banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.amber, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Weekend outing can only be applied for Sunday (Deadline: Friday 11:59 PM) & Monday (Deadline: Sunday 11:59 PM).",
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context), height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _DateTimePicker(
                          label: "Date (Sun/Mon only)*",
                          date: _outDate,
                          time: null,
                          onDatePicked: (d) => setState(() => _outDate = d),
                          onTimePicked: (_) {},
                          selectableDayPredicate: _weekendSelectableDayPredicate,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SmoothDropdown(
                    label: "Choose Time*",
                    value: _selectedWeekendSlot,
                    items: outingTimeSlots,
                    onChanged: (v) => setState(() => _selectedWeekendSlot = v),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _contactController,
                    decoration: const InputDecoration(labelText: "Contact Number*", border: OutlineInputBorder()),
                    keyboardType: TextInputType.phone,
                    validator: (v) => v!.isEmpty ? "Required" : null,
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: _DateTimePicker(
                          label: "Out Date*",
                          date: _outDate,
                          time: _outTime,
                          onDatePicked: (d) => setState(() => _outDate = d),
                          onTimePicked: (t) => setState(() => _outTime = t),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _DateTimePicker(
                          label: "In Date*",
                          date: _inDate,
                          time: _inTime,
                          onDatePicked: (d) => setState(() => _inDate = d),
                          onTimePicked: (t) => setState(() => _inTime = t),
                        ),
                      ),
                    ],
                  ),
                ],
                
                const SizedBox(height: 16),

                // Inline error banner — shown inside the sheet
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.red.withOpacity(0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.red, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.red,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _errorMessage = null),
                          child: const Icon(Icons.close, color: AppColors.red, size: 18),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("Submit Application", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateTimePicker extends StatelessWidget {
  final String label;
  final DateTime? date;
  final TimeOfDay? time; // Pass null for Date-only pickers
  final ValueChanged<DateTime> onDatePicked;
  final ValueChanged<TimeOfDay> onTimePicked;
  final bool Function(DateTime)? selectableDayPredicate;

  const _DateTimePicker({
    required this.label,
    required this.date,
    required this.time,
    required this.onDatePicked,
    required this.onTimePicked,
    this.selectableDayPredicate,
  });

  @override
  Widget build(BuildContext context) {
    final dStr = date == null ? "Select Date" : DateFormat('dd-MMM-yyyy').format(date!);
    
    // We determine if we should show time based on whether the parent passed a time value or wants time picking.
    // If we only need date, the parent passes time=null and doesn't expect time updates in UI (Weekend Outing).
    final bool showTime = label.contains("Out Date") || label.contains("In Date");

    final tStr = time == null ? "Select Time" : "${time!.hour.toString().padLeft(2,'0')}:${time!.minute.toString().padLeft(2,'0')}";

    // Find a valid initial date for the picker
    DateTime initialDate = date ?? DateTime.now();
    if (selectableDayPredicate != null && !selectableDayPredicate!(initialDate)) {
      // Find the next valid date
      for (int i = 1; i <= 30; i++) {
        final candidate = DateTime.now().add(Duration(days: i));
        if (selectableDayPredicate!(candidate)) {
          initialDate = candidate;
          break;
        }
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final d = await showDatePicker(
              context: context, 
              initialDate: initialDate, 
              firstDate: DateTime.now().subtract(const Duration(days: 1)), 
              lastDate: DateTime.now().add(const Duration(days: 30)),
              selectableDayPredicate: selectableDayPredicate,
            );
            if (d != null) onDatePicked(d);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(border: Border.all(color: AppColors.cardBorder(context)), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [const Icon(Icons.calendar_today, size: 16), const SizedBox(width: 8), Expanded(child: Text(dStr, style: const TextStyle(fontSize: 13)))]),
          ),
        ),
        if (showTime) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: time ?? TimeOfDay.now());
              if (t != null) onTimePicked(t);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(border: Border.all(color: AppColors.cardBorder(context)), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [const Icon(Icons.access_time, size: 16), const SizedBox(width: 8), Expanded(child: Text(tStr, style: const TextStyle(fontSize: 13)))]),
            ),
          ),
        ]
      ],
    );
  }
}

class _SmoothDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const _SmoothDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
        const SizedBox(height: 8),
        InkWell(
          onTap: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              builder: (ctx) => Container(
                decoration: BoxDecoration(
                  color: AppColors.scaffoldBg(context),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 16),
                      Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.textMuted(context).withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text("Select ${label.replaceAll('*', '')}", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
                      const SizedBox(height: 16),
                      ...items.map((item) => ListTile(
                        title: Text(item, style: TextStyle(color: AppColors.textPrimary(context))),
                        trailing: item == value ? Icon(Icons.check_circle, color: AppColors.primary) : null,
                        onTap: () {
                          onChanged(item);
                          Navigator.pop(ctx);
                        },
                      )),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.cardBorder(context)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(child: Text(value, style: const TextStyle(fontSize: 15))),
                Icon(Icons.arrow_drop_down, color: AppColors.textSecondary(context)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}


// ─── Full-Screen Outing Success Page ─────────────────────────────────────────

class _OutingSuccessPage extends StatefulWidget {
  final String message;
  const _OutingSuccessPage({required this.message});

  @override
  State<_OutingSuccessPage> createState() => _OutingSuccessPageState();
}

class _OutingSuccessPageState extends State<_OutingSuccessPage>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _checkAnim;

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _scaleAnim = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );
    _checkAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
      ),
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    // Start animations in sequence
    _scaleController.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _fadeController.forward();
    });

    // Auto navigate back after 3.5 seconds
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      body: SafeArea(
        child: InkWell(
          onTap: () => Navigator.pop(context),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated success circle
                  ScaleTransition(
                    scale: _scaleAnim,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF11998E).withValues(alpha: 0.4),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: AnimatedBuilder(
                        animation: _checkAnim,
                        builder: (_, __) => Icon(
                          Icons.check_rounded,
                          color: Colors.white.withValues(alpha: _checkAnim.value),
                          size: 60,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Title
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: const Text(
                      "Outing Applied! 🎉",
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Message
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: Text(
                      widget.message,
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textSecondary(context),
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Subtitle
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: Text(
                      "Your request is being processed.",
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Back button
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text("Back to Outing Status"),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: Text(
                      "Tap anywhere or wait to go back",
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted(context),
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
  }
}
