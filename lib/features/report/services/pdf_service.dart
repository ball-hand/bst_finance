import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../models/transaction_model.dart';


class PdfService {

  // Fungsi Utama: Generate PDF
  static Future<void> generateTransactionReport({
    required List<TransactionModel> transactions,
    required DateTime startDate,
    required DateTime endDate,
    required String branchName, // Misal: "Pusat" atau "Cabang A"
  }) async {
    final pdf = pw.Document();

    // Format Uang (Rupiah)
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final dateFormat = DateFormat('dd/MM/yyyy');

    // Hitung Ringkasan
    double totalIncome = 0;
    double totalExpense = 0;

    for (var tx in transactions) {
      if (tx.type == 'income') {
        totalIncome += tx.amount;
      } else {
        totalExpense += tx.amount;
      }
    }
    double grandTotal = totalIncome - totalExpense;

    // Tambahkan Halaman
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // 1. HEADER LAPORAN
            _buildHeader(startDate, endDate, branchName),
            pw.SizedBox(height: 20),

            // 2. KOTAK RINGKASAN SALDO
            _buildSummary(totalIncome, totalExpense, grandTotal, currencyFormat),
            pw.SizedBox(height: 20),

            // 3. TABEL DATA
            _buildTable(transactions, dateFormat, currencyFormat),
          ];
        },
      ),
    );

    // TAMPILKAN PREVIEW PRINT
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  // --- WIDGET HELPER PDF ---

  static pw.Widget _buildHeader(DateTime start, DateTime end, String branchName) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text("LAPORAN KEUANGAN", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Text("Cabang: ${branchName.toUpperCase()}", style: const pw.TextStyle(fontSize: 14)),
        pw.Text("Periode: ${DateFormat('dd MMM yyyy').format(start)} - ${DateFormat('dd MMM yyyy').format(end)}", style: const pw.TextStyle(fontSize: 14)),
        pw.Divider(),
      ],
    );
  }

  static pw.Widget _buildSummary(double income, double expense, double total, NumberFormat fmt) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all()),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _buildSummaryItem("Total Pemasukan", fmt.format(income), PdfColors.green),
          _buildSummaryItem("Total Pengeluaran", fmt.format(expense), PdfColors.red),
          _buildSummaryItem("Saldo Akhir", fmt.format(total), total >= 0 ? PdfColors.black : PdfColors.red),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryItem(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
        pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: color)),
      ],
    );
  }

  static pw.Widget _buildTable(List<TransactionModel> transactions, DateFormat dateFmt, NumberFormat currFmt) {
    return pw.Table.fromTextArray(
      headers: ['Tanggal', 'Kategori', 'Keterangan', 'Masuk', 'Keluar'],
      border: null,
      headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
      cellHeight: 25,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
      },
      data: transactions.map((tx) {
        final isIncome = tx.type == 'income';

        // [FIX UTAMA] Tambahkan proteksi data kosong (?? '-')
        // Dan pastikan tanggal aman
        String dateStr;
        try {
          // Coba format langsung (asumsi DateTime)
          dateStr = dateFmt.format(tx.date);
        } catch (e) {
          dateStr = "-"; // Jika gagal format tanggal
        }

        return [
          dateStr,
          tx.category ?? '-', // [FIX] Jika null, ganti strip
          tx.description ?? '-', // [FIX] Jika null, ganti strip
          isIncome ? currFmt.format(tx.amount) : '-',
          !isIncome ? currFmt.format(tx.amount) : '-',
        ];
      }).toList(),
    );
  }}