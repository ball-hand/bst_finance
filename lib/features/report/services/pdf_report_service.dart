import 'dart:typed_data';
import 'package:flutter/services.dart'; // Untuk load font jika perlu
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

import '../../../models/transaction_model.dart';

class PdfReportService {
  // Fungsi Utama untuk Generate PDF
  Future<void> generateAndPrintPdf({
    required DateTime startDate,
    required DateTime endDate,
    required List<TransactionModel> transactions,
    required double totalIncome,
    required double totalExpense,
    required double netProfit,
  }) async {
    final pdf = pw.Document();

    // 1. SIAPKAN DATA PER CABANG
    // Kita kelompokkan transaksi berdasarkan cabang (relatedBranchId)
    final Map<String, List<TransactionModel>> groupedData = {};
    final List<String> branches = ['pusat', 'bst_box', 'm_alfa', 'saufa'];

    // Inisialisasi map
    for (var b in branches) { groupedData[b] = []; }

    // Isi data
    for (var tx in transactions) {
      String branch = tx.relatedBranchId ?? 'pusat';
      // Fallback jika ada data lama yg null
      if (!branches.contains(branch)) branch = 'pusat';
      groupedData[branch]!.add(tx);
    }

    // Hitung Summary per Cabang untuk Grafik
    Map<String, Map<String, double>> chartData = {};
    for (var branch in branches) {
      double inc = groupedData[branch]!.where((t) => t.type == 'income').fold(0.0, (sum, t) => sum + t.amount);
      double exp = groupedData[branch]!.where((t) => t.type == 'expense').fold(0.0, (sum, t) => sum + t.amount);
      chartData[branch] = {'income': inc, 'expense': exp};
    }

    // 2. BUAT HALAMAN 1 (EXECUTIVE SUMMARY)
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(startDate, endDate),
              pw.SizedBox(height: 20),
              _buildScoreCards(totalIncome, totalExpense, netProfit),
              pw.SizedBox(height: 30),
              pw.Text("Grafik Performa Cabang (Pemasukan vs Pengeluaran)", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              _buildBarChart(chartData), // Grafik Batang Custom
              pw.Spacer(),
              _buildFooter(1),
            ],
          );
        },
      ),
    );

    // 3. BUAT HALAMAN DETAIL PER CABANG
    int pageCount = 2;
    for (var branchKey in branches) {
      final branchTxs = groupedData[branchKey] ?? [];
      if (branchTxs.isEmpty) continue; // Skip jika tidak ada data

      // Hitung total spesifik cabang ini
      double bIncome = branchTxs.where((t) => t.type == 'income').fold(0, (sum, t) => sum + t.amount);
      double bExpense = branchTxs.where((t) => t.type == 'expense').fold(0, (sum, t) => sum + t.amount);
      String branchName = branchKey.toUpperCase().replaceAll('_', ' ');

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          header: (context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("Laporan: $branchName", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                pw.Text("Total Masuk: ${_formatRupiah(bIncome)} | Keluar: ${_formatRupiah(bExpense)}", style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                pw.SizedBox(height: 20),
              ]
          ),
          footer: (context) => _buildFooter(context.pageNumber),
          build: (context) => [
            _buildTransactionTable(branchTxs),
          ],
        ),
      );
      pageCount++;
    }

    // 4. PRINT / SHARE
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  // --- WIDGET HELPER PDF ---

  pw.Widget _buildHeader(DateTime start, DateTime end) {
    String period = "${DateFormat('dd MMM yyyy').format(start)} s/d ${DateFormat('dd MMM yyyy').format(end)}";
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text("LAPORAN KEUANGAN EKSEKUTIF", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text("Loganes App Finance", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text("Periode Laporan:", style: const pw.TextStyle(fontSize: 10)),
            pw.Text(period, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ],
        )
      ],
    );
  }

  pw.Widget _buildScoreCards(double income, double expense, double net) {
    return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _scoreCard("Total Aset Bersih", net, PdfColors.blue600, isMain: true),
          pw.SizedBox(width: 10),
          _scoreCard("Total Pemasukan", income, PdfColors.green600),
          pw.SizedBox(width: 10),
          _scoreCard("Total Pengeluaran", expense, PdfColors.red600),
        ]
    );
  }

  pw.Widget _scoreCard(String title, double amount, PdfColor color, {bool isMain = false}) {
    return pw.Expanded(
        child: pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: isMain ? color : PdfColors.white,
              borderRadius: pw.BorderRadius.circular(8),
              border: isMain ? null : pw.Border.all(color: color, width: 2),
            ),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(title, style: pw.TextStyle(color: isMain ? PdfColors.white : PdfColors.grey700, fontSize: 10)),
                  pw.SizedBox(height: 5),
                  pw.Text(_formatRupiah(amount), style: pw.TextStyle(color: isMain ? PdfColors.white : color, fontSize: 14, fontWeight: pw.FontWeight.bold)),
                ]
            )
        )
    );
  }

  // LOGIKA MENGGAMBAR CHART SECARA MANUAL DI PDF
  pw.Widget _buildBarChart(Map<String, Map<String, double>> data) {
    // 1. Cari nilai tertinggi untuk skala grafik
    double maxValue = 0;
    data.forEach((key, value) {
      if (value['income']! > maxValue) maxValue = value['income']!;
      if (value['expense']! > maxValue) maxValue = value['expense']!;
    });
    if (maxValue == 0) maxValue = 1; // Prevent division by zero

    return pw.Container(
        height: 200,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: data.entries.map((entry) {
            double hIncome = (entry.value['income']! / maxValue) * 150;
            double hExpense = (entry.value['expense']! / maxValue) * 150;

            return pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        // Bar Pemasukan (Hijau)
                        pw.Container(width: 20, height: hIncome, color: PdfColors.green600),
                        pw.SizedBox(width: 2),
                        // Bar Pengeluaran (Merah)
                        pw.Container(width: 20, height: hExpense, color: PdfColors.red600),
                      ]
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(entry.key.toUpperCase().substring(0, 3), style: const pw.TextStyle(fontSize: 8)), // Label: PUS, BOX, MAI
                ]
            );
          }).toList(),
        )
    );
  }

  pw.Widget _buildTransactionTable(List<TransactionModel> txs) {
    return pw.Table.fromTextArray(
      headers: ['TANGGAL', 'KATEGORI', 'KETERANGAN', 'NOMINAL'],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey800),
      cellAlignment: pw.Alignment.centerLeft,
      data: txs.map((tx) {
        bool isIncome = tx.type == 'income';
        return [
          DateFormat('yyyy-MM-dd').format(tx.date),
          tx.category,
          tx.description,
          (isIncome ? "+ " : "- ") + _formatRupiah(tx.amount),
        ];
      }).toList(),
      cellStyle: const pw.TextStyle(fontSize: 9),
    );
  }

  pw.Widget _buildFooter(int pageNum) {
    return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text("Loganes Finance - Confidential", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
          pw.Text("Hal $pageNum", style: const pw.TextStyle(fontSize: 8)),
        ]
    );
  }

  String _formatRupiah(double amount) {
    return NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0).format(amount);
  }
}