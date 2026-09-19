import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReceiptPdfGenerator {
  static Future<Uint8List> generateReceipt(Map<String, dynamic> data) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              pw.SizedBox(height: 20),
              _buildStudentDetails(data),
              pw.SizedBox(height: 20),
              pw.Text('Fee Details', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              _buildFeeTable(data['fee'] as List?),
              pw.SizedBox(height: 10),
              _buildTotal(data),
              pw.SizedBox(height: 20),
              pw.Text('Payment Details', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              _buildPaymentTable(data['payment_details'] as List?),
              pw.Spacer(),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text('Authorized Signatory', style: const pw.TextStyle(fontSize: 12)),
              ),
              pw.SizedBox(height: 40),
              pw.Center(
                child: pw.Text(
                  'This is a computer generated receipt and does not require a physical signature.',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildHeader() {
    return pw.Center(
      child: pw.Column(
        children: [
          pw.Text('VELLORE INSTITUTE OF TECHNOLOGY - AP', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text('Beside AP Secretariat, Inavolu, Amaravati - 522237', style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 10),
          pw.Text('FEE RECEIPT', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline)),
        ],
      ),
    );
  }

  static pw.Widget _buildStudentDetails(Map<String, dynamic> data) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _detailRow('Receipt No:', data['receipt_number'] ?? '-'),
              _detailRow('Name:', data['name'] ?? '-'),
              _detailRow('Program:', data['program_name'] ?? '-'),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _detailRow('Date:', data['receipt_date'] ?? '-'),
              _detailRow('Reg. No:', data['application_number/register_number'] ?? '-'),
              _detailRow('Campus:', data['campus'] ?? '-'),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _detailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 80, child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))),
          pw.Expanded(child: pw.Text(value, style: const pw.TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  static pw.Widget _buildFeeTable(List? fees) {
    if (fees == null || fees.isEmpty) return pw.Text('No fee details available');
    
    return pw.TableHelper.fromTextArray(
      context: null,
      headers: ['S.No', 'Invoice No', 'Description', 'Amount (Rs.)'],
      data: fees.map((fee) => [
        fee['serial_number'] ?? '',
        fee['invoice_number'] ?? '',
        fee['description'] ?? '',
        fee['amount'] ?? '',
      ]).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {0: pw.Alignment.center, 3: pw.Alignment.centerRight},
    );
  }

  static pw.Widget _buildTotal(Map<String, dynamic> data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text('Grand Total: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
            pw.Text(data['grand_total'] ?? '-', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          data['amount_in_words'] ?? '',
          style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 12),
        ),
      ],
    );
  }

  static pw.Widget _buildPaymentTable(List? payments) {
    if (payments == null || payments.isEmpty) return pw.Text('No payment details available');
    
    return pw.TableHelper.fromTextArray(
      context: null,
      headers: ['Mode', 'Bank', 'Transaction ID', 'Amount'],
      data: payments.map((p) => [
        p['payment_mode'] ?? '',
        p['bank_name'] ?? '',
        p['dd_no_online_transaction_id'] ?? '',
        p['amount'] ?? '',
      ]).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    );
  }
}
