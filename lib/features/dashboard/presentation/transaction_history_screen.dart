import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// --- IMPORT INTERNAL (Sesuaikan path jika berbeda) ---
import '../../../models/transaction_model.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/pdf_report_service.dart';
import '../../transactions/presentation/add_transaction_screen.dart';
import '../logic/dashboard_cubit.dart';


class TransactionHistoryScreen extends StatefulWidget {
  // Parameter ini opsional.
  // Jika dikirim dari dashboard, proses loading akan lebih cepat.
  final String? branchId;
  const TransactionHistoryScreen({super.key, this.branchId});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  // --- STATE FILTER ---
  DateTimeRange _selectedRange = DateTimeRange(
    start: DateTime(DateTime.now().year, DateTime.now().month, 1),
    end: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59),
  );
  String _filterLabel = "Bulan Ini";

  // --- STATE HAK AKSES ---
  String _selectedBranch = 'all'; // Default sementara
  bool _isLoadingAccess = true;   // Loading saat cek user
  bool _isOwner = true;           // Default dianggap owner dulu

  final List<Map<String, String>> _branches = [
    {'id': 'all', 'name': 'Semua Cabang'},
    {'id': 'pusat', 'name': 'Kantor Pusat'},
    {'id': 'bst_box', 'name': 'Box Factory'},
    {'id': 'm_alfa', 'name': 'Maint. Alfa'},
    {'id': 'saufa', 'name': 'Saufa Olshop'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchUserAccess(); // Cek siapa yang login saat layar dibuka
  }

  // --- LOGIKA CEK USER ---
  Future<void> _fetchUserAccess() async {
    // 1. Cek jika parameter widget sudah membawa ID (Fast Load)
    if (widget.branchId != null && widget.branchId!.isNotEmpty) {
      if (mounted) {
        setState(() {
          _selectedBranch = widget.branchId!;
          _isOwner = false; // Karena spesifik cabang, pasti bukan owner (mode view cabang)
          _isLoadingAccess = false;
        });
      }
      return;
    }

    // 2. Jika parameter kosong, ambil data real-time dari Firestore User
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

        if (doc.exists && mounted) {
          final data = doc.data() as Map<String, dynamic>;
          final role = data['role'] ?? 'owner';
          final dbBranchId = data['branch_id'] ?? 'pusat';

          setState(() {
            if (role == 'admin_branch') {
              // Jika Admin Cabang: Kunci ke cabangnya
              _selectedBranch = dbBranchId;
              _isOwner = false;
            } else {
              // Jika Owner: Bebaskan akses
              _isOwner = true;
              _selectedBranch = 'all';
            }
          });
        }
      } catch (e) {
        print("Gagal ambil data user: $e");
      }
    }

    if (mounted) setState(() => _isLoadingAccess = false);
  }

  // --- LOGIKA HAPUS (DELETE) ---
  void _confirmDelete(BuildContext context, String txId) {
    showDialog(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: "Hapus Transaksi?",
        content: "Saldo akan dikembalikan ke dompet asal. Data yang dihapus tidak dapat dikembalikan.",
        confirmText: "Hapus & Refund",
        confirmColor: Colors.red,
        onConfirm: () {
          // 1. Panggil Cubit untuk Hapus
          context.read<DashboardCubit>().deleteTransaction(txId);

          // 2. Tampilkan Notifikasi Simpel
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Transaksi berhasil dihapus."),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }

  // --- MODAL DETAIL TRANSAKSI ---
  void _showDetailModal(BuildContext context, TransactionModel tx) {
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) {
          return Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),

                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("Detail Transaksi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: tx.type == 'income' ? Colors.green.shade50 : Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                    child: Text(tx.type == 'income' ? "PEMASUKAN" : "PENGELUARAN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: tx.type == 'income' ? Colors.green : Colors.red)),
                  )
                ]),
                const SizedBox(height: 16),

                _detailRow(Icons.category, "Kategori", tx.category),
                _detailRow(Icons.description, "Keterangan", tx.description.isEmpty ? '-' : tx.description),
                _detailRow(Icons.calendar_today, "Tanggal", DateFormat('dd MMMM yyyy, HH:mm').format(tx.date)),
                _detailRow(Icons.attach_money, "Nominal", NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(tx.amount), isBold: true),
                if(tx.walletId != null) _detailRow(Icons.wallet, "Dompet", "...${tx.walletId!.substring(tx.walletId!.length > 5 ? tx.walletId!.length - 5 : 0)}"),

                const Divider(height: 32),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                    icon: const Icon(Icons.delete_outline), label: const Text("Hapus"),
                    onPressed: () { Navigator.pop(ctx); _confirmDelete(context, tx.id); },
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                    icon: const Icon(Icons.edit), label: const Text("Edit"),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(context, MaterialPageRoute(builder: (c) => AddTransactionScreen(branchId: widget.branchId, transactionToEdit: tx))).then((_) => setState((){}));
                    },
                  )),
                ])
              ],
            ),
          );
        }
    );
  }

  Widget _detailRow(IconData icon, String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ])
      ]),
    );
  }

  // --- FILTER TANGGAL ---
  void _handleDateFilter(String value) async {
    DateTime now = DateTime.now();
    DateTime start = now;
    DateTime end = now;
    if (value == 'month') { start = DateTime(now.year, now.month, 1); _filterLabel = "Bulan Ini"; }
    else if (value == 'today') { start = now; _filterLabel = "Hari Ini"; }
    else if (value == 'week') { start = now.subtract(const Duration(days: 6)); _filterLabel = "7 Hari Terakhir"; }
    else if (value == 'last_month') { start = DateTime(now.year, now.month - 1, 1); end = DateTime(now.year, now.month, 0); _filterLabel = "Bulan Lalu"; }
    else if (value == 'custom') {
      final picked = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2030), initialDateRange: _selectedRange);
      if (picked != null) { start = picked.start; end = picked.end; _filterLabel = "Custom"; } else return;
    }
    setState(() { _selectedRange = DateTimeRange(start: start, end: end); });
  }

  // --- PDF SHARE ---
  Future<void> _sharePdf(List<TransactionModel> data) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Menyiapkan PDF...")));
    try {
      final pdfData = await PdfReportService().generateExecutiveReport(
        transactions: data, startDate: _selectedRange.start, endDate: _selectedRange.end, branchFilter: _selectedBranch,
      );
      await Printing.sharePdf(bytes: pdfData, filename: 'Laporan_BST_${DateFormat('ddMM').format(_selectedRange.start)}.pdf');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal PDF: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    DateTime start = DateTime(_selectedRange.start.year, _selectedRange.start.month, _selectedRange.start.day, 0, 0, 0);
    DateTime end = DateTime(_selectedRange.end.year, _selectedRange.end.month, _selectedRange.end.day, 23, 59, 59);

    // BlocListener: Mendengarkan respon sukses/gagal dari Cubit
    return BlocListener<DashboardCubit, DashboardState>(
      listener: (context, state) {
        if (state is DashboardSuccess) {
          // Jika sukses (hapus/restore), refresh UI lokal
          setState(() {});
        } else if (state is DashboardError) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: Colors.red));
        }
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text("Laporan & Riwayat", style: TextStyle(color: Colors.black)),
          backgroundColor: Colors.white, elevation: 0, iconTheme: const IconThemeData(color: Colors.black),
        ),
        body: Column(
          children: [
            // --- BAGIAN FILTER (ATAS) ---
            Container(
              padding: const EdgeInsets.all(16), color: Colors.white,
              child: Row(children: [

                // 1. DROPDOWN CABANG (Cerdas: Auto Lock)
                Expanded(
                    flex: 4,
                    child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          // Jika user bukan owner (terkunci), beri warna abu-abu
                          color: _isOwner ? Colors.white : Colors.grey.shade200,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _isLoadingAccess
                            ? const Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                            : DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedBranch,
                              isExpanded: true,
                              // LOGIKA KUNCI: Jika _isOwner = FALSE, maka onChanged = NULL (Terkunci)
                              onChanged: _isOwner
                                  ? (val) => setState(() => _selectedBranch = val!)
                                  : null,
                              items: _branches.map((b) => DropdownMenuItem(
                                  value: b['id'],
                                  child: Text(b['name']!, style: const TextStyle(fontSize: 13))
                              )).toList(),
                            )
                        )
                    )
                ),

                const SizedBox(width: 8),

                // 2. FILTER TANGGAL
                Expanded(flex: 3, child: PopupMenuButton<String>(onSelected: _handleDateFilter, itemBuilder: (context) => [const PopupMenuItem(value: 'today', child: Text("Hari Ini")), const PopupMenuItem(value: 'week', child: Text("7 Hari Terakhir")), const PopupMenuItem(value: 'month', child: Text("Bulan Ini")), const PopupMenuItem(value: 'last_month', child: Text("Bulan Lalu")), const PopupMenuItem(value: 'custom', child: Text("Custom..."))], child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.calendar_today, size: 14, color: Colors.grey), const SizedBox(width: 4), Text(_filterLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))])))),
              ]),
            ),

            // --- BAGIAN KONTEN (BAWAH) ---
            Expanded(
              child: StreamBuilder<List<TransactionModel>>(
                stream: Stream.fromFuture(TransactionRepository().getTransactionsByDateRange(
                    startDate: start,
                    endDate: end,
                    // Pastikan query menggunakan cabang yang sudah tervalidasi
                    branchId: _selectedBranch == 'all' ? null : _selectedBranch
                )),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                  // Filter sampah (jangan tampilkan yang sudah dihapus)
                  final transactions = (snapshot.data ?? []).where((t) => t.deletedAt == null).toList();

                  // Hitung Ringkasan
                  double income = 0;
                  double expense = 0;
                  for (var tx in transactions) {
                    if (tx.category.toLowerCase().contains('top up')) continue;
                    if (tx.type == 'income') income += tx.amount; else expense += tx.amount;
                  }
                  double profit = income - expense;

                  return Column(
                    children: [
                      // KARTU RINGKASAN
                      Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]), child: Column(children: [const Text("Laba Rugi Periode Ini", style: TextStyle(color: Colors.grey)), Text(NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(profit), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: profit >= 0 ? Colors.green : Colors.red)), const Divider(height: 24), Row(children: [Expanded(child: _buildStat("Pemasukan", income, Colors.green)), Container(width: 1, height: 30, color: Colors.grey[300]), Expanded(child: _buildStat("Pengeluaran", expense, Colors.red))]), const SizedBox(height: 16), SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: transactions.isEmpty ? null : () => _sharePdf(transactions), icon: const Icon(Icons.share), label: const Text("SHARE LAPORAN"), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary)))])),

                      // LIST DATA
                      Expanded(
                        child: transactions.isEmpty
                            ? const Center(child: Text("Tidak ada data."))
                            : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: transactions.length,
                          separatorBuilder: (c, i) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final tx = transactions[i];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              onTap: () => _showDetailModal(context, tx),
                              leading: CircleAvatar(backgroundColor: tx.type == 'income' ? Colors.green.shade50 : Colors.red.shade50, child: Icon(tx.type == 'income' ? Icons.arrow_downward : Icons.arrow_upward, color: tx.type == 'income' ? Colors.green : Colors.red, size: 20)),
                              title: Text(tx.category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text(DateFormat('dd MMM HH:mm').format(tx.date), style: const TextStyle(fontSize: 12)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(tx.amount), style: TextStyle(fontWeight: FontWeight.bold, color: tx.type == 'income' ? Colors.green : Colors.red)), const Text("Tap detail", style: TextStyle(fontSize: 9, color: Colors.grey))]),
                                  const SizedBox(width: 8),
                                  // Tombol Hapus Cepat
                                  IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey), onPressed: () => _confirmDelete(context, tx.id))
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, double val, Color color) => Column(children: [Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)), Text(NumberFormat.compact(locale: 'id_ID').format(val), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16))]);
}

// --- WIDGET KONFIRMASI (Bisa ditaruh file terpisah, tapi disini juga oke) ---
class ConfirmationDialog extends StatelessWidget {
  final String title;
  final String content;
  final VoidCallback onConfirm;
  final String confirmText;
  final Color confirmColor;

  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.content,
    required this.onConfirm,
    this.confirmText = "Ya, Hapus",
    this.confirmColor = Colors.red,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Batal", style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: confirmColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () {
            Navigator.of(context).pop(); // Tutup dialog
            onConfirm(); // Jalankan aksi
          },
          child: Text(confirmText, style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}