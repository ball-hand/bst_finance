import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/transaction_model.dart';
// Pastikan nama file service PDF Anda sesuai.
// Jika di report_screen.dart pakai PdfService, sesuaikan di sini.
import '../services/pdf_report_service.dart';

class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  // --- STATE FILTER ---
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  String _selectedBranch = 'bst_box'; // Default

  // Data User
  String _userRole = 'admin_branch';
  String _userBranchId = 'bst_box';
  bool _isLoading = true;

  // Opsi Cabang (Hanya untuk Owner)
  final List<Map<String, String>> _branches = [
    {'id': 'bst_box', 'name': 'Box Factory'},
    {'id': 'm_alfa', 'name': 'Maint. Alfa'},
    {'id': 'saufa', 'name': 'Saufa Olshop'},
    {'id': 'pusat', 'name': 'Kantor Pusat'},
  ];

  @override
  void initState() {
    super.initState();
    _checkUserRole();
  }

  void _checkUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        if (mounted) {
          setState(() {
            _userRole = doc['role'] ?? 'admin_branch';
            _userBranchId = doc['branch_id'] ?? 'bst_box';

            // Jika Admin Cabang, kunci pilihan cabang ke miliknya sendiri
            if (_userRole != 'owner') {
              _selectedBranch = _userBranchId;
            }
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tentukan Range Tanggal (Awal Bulan - Akhir Bulan)
    DateTime start = DateTime(_selectedYear, _selectedMonth, 1);
    DateTime end = DateTime(_selectedYear, _selectedMonth + 1, 0, 23, 59, 59);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Laporan Bulanan", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _buildFilters(), // Filter Bulan/Tahun/Cabang

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('transactions')
                  .where('date', isGreaterThanOrEqualTo: start)
                  .where('date', isLessThanOrEqualTo: end)
              // Filter Cabang (Related Branch agar Pemasukan Pusat yg tagged cabang ini tetap masuk)
                  .where('related_branch_id', isEqualTo: _selectedBranch)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                // --- HITUNG MANUAL (Agregasi) ---
                double totalIncome = 0;
                double totalExpense = 0;
                Map<String, double> categoryExpense = {};

                // List Transaksi Bersih (Tanpa Mutasi) untuk PDF
                List<TransactionModel> cleanTransactions = [];

                for (var doc in docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  double amount = (data['amount'] ?? 0).toDouble();
                  String type = data['type'] ?? 'expense';
                  String cat = data['category'] ?? 'Lain-lain';

                  // --- [PERBAIKAN LOGIKA] EXCLUDE TRANSFER ---
                  // Abaikan transaksi yang sifatnya mutasi internal
                  bool isTransfer = cat.toLowerCase().contains('top up') ||
                      cat.toLowerCase().contains('mutasi') ||
                      cat.toLowerCase().contains('internal');

                  if (isTransfer) continue; // SKIP (Jangan dihitung)

                  // Masukkan ke list bersih
                  cleanTransactions.add(TransactionModel.fromMap(data, doc.id));

                  if (type == 'income') {
                    totalIncome += amount;
                  } else {
                    totalExpense += amount;
                    // Hitung per kategori
                    if (categoryExpense.containsKey(cat)) {
                      categoryExpense[cat] = categoryExpense[cat]! + amount;
                    } else {
                      categoryExpense[cat] = amount;
                    }
                  }
                }

                double netProfit = totalIncome - totalExpense;

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // 1. SCOREBOARD (Rangkuman Angka)
                    _buildScoreBoard(totalIncome, totalExpense, netProfit),
                    const SizedBox(height: 24),

                    // 2. ANALISA KATEGORI PENGELUARAN
                    const Text("Pengeluaran per Kategori", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    if (categoryExpense.isEmpty)
                      const Padding(padding: EdgeInsets.all(20), child: Center(child: Text("- Tidak ada pengeluaran operasional -", style: TextStyle(color: Colors.grey))))
                    else
                      ...categoryExpense.entries.map((e) => _buildCategoryItem(e.key, e.value, totalExpense)).toList(),

                    const SizedBox(height: 30),

                    // --- TOMBOL EXPORT PDF ---
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black, // Warna hitam agar elegan seperti PDF
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.print),
                        label: const Text("CETAK LAPORAN PDF (Real Report)"),
                        onPressed: () async {
                          // Panggil Service PDF dengan Data Bersih
                          await PdfReportService().generateAndPrintPdf(
                            startDate: start,
                            endDate: end,
                            transactions: cleanTransactions, // Pakai list yg sudah difilter
                            totalIncome: totalIncome,
                            totalExpense: totalExpense,
                            netProfit: netProfit,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Center(child: Text("* Transaksi Top Up/Mutasi tidak dihitung dalam laporan ini.", style: TextStyle(fontSize: 10, color: Colors.grey))),
                    const SizedBox(height: 40),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            children: [
              // DROPDOWN BULAN
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  value: _selectedMonth,
                  decoration: const InputDecoration(labelText: "Bulan", border: OutlineInputBorder(), isDense: true),
                  items: List.generate(12, (index) => DropdownMenuItem(value: index + 1, child: Text(DateFormat('MMMM', 'id_ID').format(DateTime(2022, index + 1))))),
                  onChanged: (val) => setState(() => _selectedMonth = val!),
                ),
              ),
              const SizedBox(width: 10),
              // DROPDOWN TAHUN
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<int>(
                  value: _selectedYear,
                  decoration: const InputDecoration(labelText: "Tahun", border: OutlineInputBorder(), isDense: true),
                  items: [2024, 2025, 2026].map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList(),
                  onChanged: (val) => setState(() => _selectedYear = val!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // DROPDOWN CABANG (Hanya aktif jika Owner)
          DropdownButtonFormField<String>(
            value: _selectedBranch,
            decoration: const InputDecoration(labelText: "Filter Cabang", border: OutlineInputBorder(), isDense: true, filled: true),
            items: _branches.map((b) => DropdownMenuItem(value: b['id'], child: Text(b['name']!))).toList(),
            onChanged: _userRole == 'owner'
                ? (val) => setState(() => _selectedBranch = val!)
                : null, // Disable jika bukan owner
          ),
        ],
      ),
    );
  }

  Widget _buildScoreBoard(double income, double expense, double net) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildStatCard("Pemasukan", income, AppColors.success, Icons.arrow_downward)),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard("Pengeluaran", expense, AppColors.error, Icons.arrow_upward)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: net >= 0 ? AppColors.primary : Colors.orange[800],
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: (net >= 0 ? AppColors.primary : Colors.orange).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("LABA / RUGI BERSIH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text(
                _formatRupiah(net),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildStatCard(String title, double amount, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(_formatRupiah(amount), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildCategoryItem(String category, double amount, double totalExpense) {
    // Hindari pembagian dengan nol
    double percentage = totalExpense == 0 ? 0 : (amount / totalExpense);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(category, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(_formatRupiah(amount), style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: percentage,
            backgroundColor: Colors.grey[100],
            color: AppColors.error.withOpacity(0.7),
            minHeight: 6,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 4),
          Align(alignment: Alignment.centerRight, child: Text("${(percentage * 100).toStringAsFixed(1)}%", style: TextStyle(fontSize: 10, color: Colors.grey[600])))
        ],
      ),
    );
  }

  String _formatRupiah(double amount) => NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);
}