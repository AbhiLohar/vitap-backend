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
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text("Payment History"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary(context),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadData(forceRefresh: true),
        color: AppColors.primary,
        child: _isLoading && _payments.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _payments.isEmpty
                ? ListView(
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                      Center(
                        child: Column(
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 64, color: AppColors.textMuted(context)),
                            const SizedBox(height: 16),
                            Text("No payment records found", style: TextStyle(color: AppColors.textSecondary(context))),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _payments.length,
                    itemBuilder: (context, index) {
                      final p = _payments[index];
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassCard(
                          accentColor: AppColors.primary.withOpacity(0.3),
                          padding: EdgeInsets.zero,
                          child: Theme(
                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              title: Text(
                                p["description"] ?? "Fee Payment",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  "₹${p["amount"] ?? "0"}",
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  child: Column(
                                    children: [
                                      const Divider(height: 16, color: Colors.white10),
                                      _row(context, Icons.confirmation_number_outlined, "Receipt No", p["receipt_no"] ?? "-"),
                                      const SizedBox(height: 8),
                                      _row(context, Icons.calendar_today, "Date", p["date"] ?? "-"),
                                      const SizedBox(height: 8),
                                      _row(context, Icons.payment, "Mode", p["payment_mode"] ?? "-"),
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
