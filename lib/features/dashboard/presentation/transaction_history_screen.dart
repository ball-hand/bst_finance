import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/transaction_model.dart';
import '../../transactions/presentation/add_transaction_screen.dart';
import '../../transactions/data/transaction_repository.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  // Filter State
  String _selectedType = 'all'; // all, income, expense
  DateTime? _startDate;
  DateTime? _endDate;

  // User Data
  String _userRole = 'admin_branch';
  String _userBranchId = 'bst_box';

  @override
  void initState() {
    super.initState();
    _initUser();
  }

  void _initUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _userRole = doc['role'] ?? 'admin_branch';
          _userBranchId = doc['branch_id'] ?? 'bst_box';
        });
      }
    }
  }

  // --- QUERY DATABASE ---
  Query _buildQuery() {
    Query query = FirebaseFirestore.instance.collection('transactions')
        .where('deleted_at', isNull: true)
        .orderBy('date', descending: true);

    // 1. Filter Role (Owner lihat semua, Admin lihat cabang sendiri)
    if (_userRole != 'owner') {
      query = query.where('related_branch_id', isEqualTo: _userBranchId);
    }

    // 2. Filter Tipe (Income/Expense)
    if (_selectedType != 'all') {
      query = query.where('type', isEqualTo: _selectedType);
    }

    // 3. Filter Tanggal
    if (_startDate != null && _endDate != null) {
      // Set jam ke awal dan akhir hari
      DateTime start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day, 0, 0, 0);
      DateTime end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
      query = query.where('date', isGreaterThanOrEqualTo: start)
          .where('date', isLessThanOrEqualTo: end);
    }

    return query;
  }

  // --- DELETE LOGIC ---
  Future<void> _deleteTransaction(String id) async {
    bool confirm = await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("Hapus Transaksi?"),
          content: const Text("Saldo akan dikembalikan (Reverse)."),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(c,false), child: const Text("Batal")),
            TextButton(onPressed: ()=>Navigator.pop(c,true), child: const Text("Hapus", style: TextStyle(color: Colors.red))),
          ],
        )
    ) ?? false;

    if (confirm) {
      try {
        await TransactionRepository().deleteTransaction(id);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Transaksi dihapus & Saldo dikembalikan.")));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Riwayat Transaksi", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _buildQuery().snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text("Belum ada transaksi"));

          // --- LOGIC PERHITUNGAN HEADER (FIXED) ---
          double totalIncome = 0;
          double totalExpense = 0;

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            double amount = (data['amount'] ?? 0).toDouble();
            String type = data['type'];
            String category = (data['category'] ?? '').toString().toLowerCase();

            // FILTER: Jangan hitung Mutasi/Top Up/Suntikan Modal di Header
            bool isTransfer = category.contains('mutasi') ||
                category.contains('top up') ||
                category.contains('suntikan') ||
                category.contains('internal');

            if (!isTransfer) {
              if (type == 'income') totalIncome += amount;
              else totalExpense += amount;
            }
          }
          // ------------------------------------------

          return Column(
            children: [
              // HEADER SUMMARY
              _buildSummaryHeader(totalIncome, totalExpense),

              // LIST TRANSAKSI
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (c, i) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final id = docs[index].id;
                    final tx = TransactionModel.fromMap(data, id);
                    return _buildTransactionCard(tx);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildSummaryHeader(double income, double expense) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))]),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Pemasukan (Real)", style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text(_formatRupiah(income), style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 18)),
            ]),
          ),
          Container(width: 1, height: 40, color: Colors.grey[300]),
          const SizedBox(width: 20),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Pengeluaran (Real)", style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text(_formatRupiah(expense), style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 18)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(TransactionModel tx) {
    bool isIncome = tx.type == 'income';

    // Cek apakah ini transfer (untuk visual label)
    bool isTransfer = tx.category.toLowerCase().contains('mutasi') ||
        tx.category.toLowerCase().contains('top up') ||
        tx.category.toLowerCase().contains('suntikan');

    return InkWell(
      onTap: () {
        // Edit hanya bisa jika bukan transfer (transfer editnya kompleks)
        if (!isTransfer) {
          Navigator.push(context, MaterialPageRoute(builder: (c) => AddTransactionScreen(transactionToEdit: tx)));
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: isTransfer ? Colors.blue[50] : (isIncome ? Colors.green[50] : Colors.red[50]),
                  shape: BoxShape.circle
              ),
              child: Icon(
                isTransfer ? Icons.swap_horiz : (isIncome ? Icons.arrow_downward : Icons.arrow_upward),
                color: isTransfer ? Colors.blue : (isIncome ? Colors.green : Colors.red),
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(tx.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(DateFormat('dd MMM yyyy, HH:mm').format(tx.date), style: TextStyle(color: Colors.grey[400], fontSize: 10)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                    "${isIncome ? '+ ' : '- '}${_formatRupiah(tx.amount)}",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isTransfer ? Colors.blue : (isIncome ? Colors.green : Colors.red)
                    )
                ),
                if (!isTransfer) // Tombol hapus hanya muncul jika bukan transfer (opsional, biar aman)
                  InkWell(
                    onTap: () => _deleteTransaction(tx.id),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Icon(Icons.delete_outline, size: 18, color: Colors.grey[400]),
                    ),
                  )
              ],
            )
          ],
        ),
      ),
    );
  }

  void _showFilterDialog() {
    showModalBottomSheet(context: context, builder: (c) {
      return Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Filter Transaksi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 20),
            const Text("Tipe:"),
            Row(
              children: [
                _filterChip("Semua", 'all'),
                const SizedBox(width: 10),
                _filterChip("Pemasukan", 'income'),
                const SizedBox(width: 10),
                _filterChip("Pengeluaran", 'expense'),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  onPressed: () async {
                    final picked = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2030));
                    if (picked != null) {
                      setState(() { _startDate = picked.start; _endDate = picked.end; });
                      Navigator.pop(context);
                    }
                  },
                  child: Text(_startDate == null ? "Pilih Tanggal" : "${DateFormat('dd/MM').format(_startDate!)} - ${DateFormat('dd/MM').format(_endDate!)}")
              ),
            ),
            const SizedBox(height: 10),
            if (_startDate != null)
              Center(child: TextButton(onPressed: (){ setState(() { _startDate = null; _endDate = null; }); Navigator.pop(context); }, child: const Text("Reset Filter"))),
          ],
        ),
      );
    });
  }

  Widget _filterChip(String label, String value) {
    bool selected = _selectedType == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (s) {
        setState(() => _selectedType = value);
        Navigator.pop(context);
      },
    );
  }

  String _formatRupiah(double amount) => NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);
}