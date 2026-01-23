import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:collection/collection.dart'; // Pastikan 'flutter pub add collection' jika belum
import '../../models/transaction_model.dart';

class PdfReportService {
  final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final dateFormat = DateFormat('dd MMM yyyy', 'id_ID');

  Future<Uint8List> generateExecutiveReport({
    required List<TransactionModel> transactions,
    required DateTime startDate,
    required DateTime endDate,
    required String branchFilter,
  }) async {
    final pdf = pw.Document();

    // 1. SIAPKAN DATA
    // Group transaksi berdasarkan Cabang (Branch ID)
    final Map<String, List<TransactionModel>> groupedByBranch = groupBy(transactions, (tx) {
      // Jika branchId kosong/null, anggap 'pusat' atau 'lainnya'
      return (tx.relatedBranchId != null && tx.relatedBranchId!.isNotEmpty)
          ? tx.relatedBranchId!
          : 'pusat';
    });

    // Hitung Global Total
    double totalIncome = 0;
    double totalExpense = 0;
    for (var tx in transactions) {
      if (tx.type == 'income') totalIncome += tx.amount;
      else totalExpense += tx.amount;
    }
    double netAsset = totalIncome - totalExpense;

    // 2. HALAMAN 1: RINGKASAN EKSEKUTIF
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader("LAPORAN KEUANGAN EKSEKUTIF", startDate, endDate),
              pw.SizedBox(height: 20),

              // KOTAK TOTAL BESAR
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColors.blue200),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _buildBigStat("Total Aset Bersih", netAsset, PdfColors.blue900),
                    _buildBigStat("Total Pemasukan", totalIncome, PdfColors.green800),
                    _buildBigStat("Total Pengeluaran", totalExpense, PdfColors.red800),
                  ],
                ),
              ),

              pw.SizedBox(height: 30),
              pw.Text("Performa Per Cabang", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),

              // TABEL PERFORMA CABANG (Pengganti Grafik)
              pw.Table.fromTextArray(
                headers: ['Cabang', 'Pemasukan', 'Pengeluaran', 'Profit/Rugi'],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey800),
                cellAlignment: pw.Alignment.centerRight,
                cellAlignments: {0: pw.Alignment.centerLeft},
                data: groupedByBranch.entries.map((entry) {
                  String branchName = _mapBranchName(entry.key);
                  double inc = entry.value.where((t) => t.type == 'income').fold(0, (sum, t) => sum + t.amount);
                  double exp = entry.value.where((t) => t.type == 'expense').fold(0, (sum, t) => sum + t.amount);
                  return [
                    branchName,
                    currencyFormat.format(inc),
                    currencyFormat.format(exp),
                    currencyFormat.format(inc - exp),
                  ];
                }).toList(),
              ),

              pw.Spacer(),
              _buildFooter(1),
            ],
          );
        },
      ),
    );

    // 3. HALAMAN DETAIL PER CABANG (Looping)
    int pageCount = 2;
    groupedByBranch.forEach((branchId, branchTxs) {
      // Hitung sub-total cabang
      double branchInc = branchTxs.where((t) => t.type == 'income').fold(0, (sum, t) => sum + t.amount);
      double branchExp = branchTxs.where((t) => t.type == 'expense').fold(0, (sum, t) => sum + t.amount);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => _buildBranchHeader(_mapBranchName(branchId), branchInc, branchExp),
          footer: (context) => _buildFooter(context.pageNumber),
          build: (context) {
            return [
              pw.SizedBox(height: 10),
              pw.Table.fromTextArray(
                headers: ['Tanggal', 'Kategori', 'Keterangan', 'Nominal'],
                columnWidths: {
                  0: const pw.FixedColumnWidth(80),
                  1: const pw.FixedColumnWidth(100),
                  2: const pw.FlexColumnWidth(),
                  3: const pw.FixedColumnWidth(100),
                },
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
                data: branchTxs.map((tx) {
                  final isIncome = tx.type == 'income';
                  return [
                    dateFormat.format(tx.date),
                    tx.category,
                    tx.description,
                    "${isIncome ? '+' : '-'} ${currencyFormat.format(tx.amount)}",
                  ];
                }).toList(),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignments: {
                  3: pw.Alignment.centerRight,
                },
              ),
            ];
          },
        ),
      );
      pageCount++;
    });

    return pdf.save();
  }

  // --- WIDGETS HELPER ---

  pw.Widget _buildHeader(String title, DateTime start, DateTime end) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text("Periode: ${dateFormat.format(start)} s/d ${dateFormat.format(end)}", style: const pw.TextStyle(fontSize: 12)),
        pw.Text("Generated by BST Finance App", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.Divider(),
      ],
    );
  }

  pw.Widget _buildBranchHeader(String branchName, double inc, double exp) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text("Laporan: ${branchName.toUpperCase()}", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
          pw.Text("Total Masuk: ${currencyFormat.format(inc)} | Keluar: ${currencyFormat.format(exp)}", style: const pw.TextStyle(fontSize: 12)),
          pw.Divider(color: PdfColors.grey300),
        ],
      ),
    );
  }

  pw.Widget _buildBigStat(String label, double value, PdfColor color) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.Text(currencyFormat.format(value), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: color)),
      ],
    );
  }

  pw.Widget _buildFooter(int pageNum) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 20),
      child: pw.Text("BST Finance - Confidential | Hal $pageNum", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
    );
  }

  String _mapBranchName(String id) {
    switch (id.toLowerCase()) {
      case 'pusat': return 'KANTOR PUSAT';
      case 'bst_box': return 'BOX FACTORY';
      case 'm_alfa': return 'MAINTENANCE ALFA';
      case 'saufa': return 'SAUFA OLSHOP';
      default: return id.toUpperCase();
    }
  }
}