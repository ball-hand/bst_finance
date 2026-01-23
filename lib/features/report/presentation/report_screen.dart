import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../transactions/data/transaction_repository.dart';
import '../services/excel_service.dart';
import '../services/pdf_service.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  // Default: Hari ini
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  String _selectedType = 'all'; // all, income, expense

  // Fungsi Pembantu Memilih Tanggal
  Future<void> _pickDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: Colors.blue,
            colorScheme: const ColorScheme.light(primary: Colors.blue),
            buttonTheme: const ButtonThemeData(textTheme: ButtonTextTheme.primary),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }
  bool _isLoading = false; // Untuk indikator loading

  Future<void> _generatePdf() async {
    setState(() => _isLoading = true);

    try {
      // 1. Ambil Data dari Database
      // Pastikan Anda sudah menambahkan fungsi getTransactionsByDateRange di TransactionRepository (Fase sebelumnya)
      final transactions = await TransactionRepository().getTransactionsByDateRange(
        startDate: _startDate,
        endDate: _endDate,
        type: _selectedType == 'all' ? null : _selectedType,
        // Opsional: Filter by branch jika perlu, atau biarkan null untuk ambil semua sesuai hak akses
      );

      if (transactions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tidak ada data pada periode ini.")));
        setState(() => _isLoading = false);
        return;
      }

      // 2. Panggil Service PDF
      // Kita ambil nama user/cabang sebentar (opsional, bisa hardcode dulu)
      String branchName = "Laporan User";

      await PdfService.generateTransactionReport(
        transactions: transactions,
        startDate: _startDate,
        endDate: _endDate,
        branchName: branchName,
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal membuat PDF: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generateExcel() async {
    setState(() => _isLoading = true);

    try {
      // 1. Ambil Data (Sama persis logikanya dengan PDF)
      final transactions = await TransactionRepository().getTransactionsByDateRange(
        startDate: _startDate,
        endDate: _endDate,
        type: _selectedType == 'all' ? null : _selectedType,
      );

      if (transactions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tidak ada data untuk diexport.")));
        setState(() => _isLoading = false);
        return;
      }

      // 2. Panggil Excel Service
      await ExcelService.generateExcelReport(
        transactions: transactions,
        branchName: "UserBranch", // Nanti bisa diganti nama asli cabang
        startDate: _startDate,
        endDate: _endDate,
      );

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Excel berhasil dibuka!")));

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal export Excel: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Laporan Keuangan"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. HEADER PILIHAN TANGGAL
            const Text("Pilih Periode Laporan:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _pickDateRange(context),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, color: Colors.blue, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      "${DateFormat('dd MMM yyyy').format(_startDate)} - ${DateFormat('dd MMM yyyy').format(_endDate)}",
                      style: const TextStyle(fontSize: 16),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 2. FILTER TIPE TRANSAKSI
            const Text("Tipe Transaksi:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildFilterChip('Semua', 'all'),
                const SizedBox(width: 10),
                _buildFilterChip('Pemasukan', 'income', color: Colors.green),
                const SizedBox(width: 10),
                _buildFilterChip('Pengeluaran', 'expense', color: Colors.red),
              ],
            ),

            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 10),

            // 3. TOMBOL AKSI
            const Text("Export Data:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 15),

            _buildExportButton(

              label: _isLoading ? "Membuat.....":"Cetak Laporan PDF",
              icon: Icons.picture_as_pdf,
              color: Colors.red.shade700,
              onTap: _isLoading ? () {} : _generatePdf,
            ),

            const SizedBox(height: 15),

            _buildExportButton(
              label: "Export ke Excel (.xlsx)",
              icon: Icons.table_view,
              color: Colors.green.shade700,
              onTap: _isLoading ? () {} : _generateExcel,
            ),
          ],
        ),
      ),
    );
  }

  // WIDGET HELPER: Filter Chip
  Widget _buildFilterChip(String label, String value, {Color color = Colors.blue}) {
    bool isSelected = _selectedType == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _selectedType = value);
      },
      selectedColor: color.withOpacity(0.2),
      labelStyle: TextStyle(
        color: isSelected ? color : Colors.grey,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: Colors.grey.shade100,
    );
  }

  // WIDGET HELPER: Tombol Export Besar
  Widget _buildExportButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 2,
        ),
        icon: Icon(icon, color: Colors.white),
        label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }
}