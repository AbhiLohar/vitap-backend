import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
// PDF packages removed

class PaymentsScreen extends StatefulWidget {
  final String username;

  const PaymentsScreen({super.key, required this.username});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  List _payments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getPayments(widget.username, forceSync: forceRefresh);
      setState(() {
        _payments = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          "Payment History",
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
      body: RefreshIndicator(
        onRefresh: () => _loadData(forceRefresh: true),
        color: primaryColor,
        child: _isLoading && _payments.isEmpty
            ? Center(child: CircularProgressIndicator(color: primaryColor))
            : _payments.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                      Center(
                        child: Column(
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 52, color: AppColors.textMuted(context)),
                            const SizedBox(height: 14),
                            Text("No payment records found", style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _payments.length,
                    itemBuilder: (context, index) {
                      final p = _payments[index];
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassCard(
                          accentColor: primaryColor.withOpacity(0.4),
                          padding: EdgeInsets.zero,
                          child: Theme(
                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              title: Text(
                                p["description"] ?? "Fee Payment",
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: primaryColor.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: primaryColor.withOpacity(0.15)),
                                ),
                                child: Text(
                                  "₹${p["amount"] ?? "0"}",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor,
                                  ),
                                ),
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  child: Column(
                                    children: [
                                      Divider(height: 16, color: AppColors.cardBorder(context)),
                                      _row(context, Icons.confirmation_number_outlined, "Receipt No", p["receipt_no"] ?? "-"),
                                      const SizedBox(height: 8),
                                      _row(context, Icons.calendar_today_outlined, "Date", p["date"] ?? "-"),
                                      const SizedBox(height: 8),
                                      _row(context, Icons.payment_rounded, "Mode", p["payment_mode"] ?? "-"),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted(context)),
        const SizedBox(width: 8),
        Text("$label:", style: TextStyle(fontSize: 12, color: AppColors.textMuted(context))),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary(context)),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
