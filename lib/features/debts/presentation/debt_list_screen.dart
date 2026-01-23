import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import Auth untuk user_id
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../debts/domain/debt_model.dart';

class DebtListScreen extends StatefulWidget {
  final String branchId;
  const DebtListScreen({super.key, required this.branchId});

  @override
  State<DebtListScreen> createState() => _DebtListScreenState();
}

class _DebtListScreenState extends State<DebtListScreen> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- LOGIKA PEMBAYARAN (CICIL ATAU LUNAS) ---
  Future<void> _processPayment(DebtModel debt, double payAmount) async {
    // Validasi
    if (payAmount <= 0) return;
    if (payAmount > debt.amount) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pembayaran melebihi sisa utang!"), backgroundColor: Colors.red));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Memproses Pembayaran...")));

    try {
      final user = FirebaseAuth.instance.currentUser;
      String walletId = "main_cash";

      await _firestore.runTransaction((tx) async {
        final debtRef = _firestore.collection('debts').doc(debt.id);
        final walletRef = _firestore.collection('wallets').doc(walletId);

        // --- 1. [FIX] LAKUKAN BACA (READ) DULUAN ---
        final walletSnap = await tx.get(walletRef);
        // (Kita baca saldo dompet sekarang, sebelum melakukan update apapun)

        // --- 2. LAKUKAN PERHITUNGAN ---
        double remaining = debt.amount - payAmount;
        bool isFullPaid = remaining <= 0;

        // --- 3. LAKUKAN SEMUA TULIS (WRITE) DI BAWAH ---

        // A. Update Data Utang
        tx.update(debtRef, {
          'amount': remaining,
          'status': isFullPaid ? 'paid' : 'unpaid',
          'last_payment_at': FieldValue.serverTimestamp(),
        });

        // B. Catat Transaksi Pengeluaran
        final txRef = _firestore.collection('transactions').doc();
        tx.set(txRef, {
          'amount': payAmount,
          'type': 'expense',
          'category': 'Bayar Utang',
          'description': isFullPaid ? "Pelunasan: ${debt.name}" : "Cicilan Utang: ${debt.name}",
          'wallet_id': walletId,
          'related_branch_id': widget.branchId,
          'date': FieldValue.serverTimestamp(),
          'user_id': user?.uid ?? 'unknown',
          'deleted_at': null,
        });

        // C. Update Saldo Dompet (Pakai data yang sudah dibaca di langkah 1)
        if (walletSnap.exists) {
          double currentBalance = (walletSnap.get('balance') ?? 0).toDouble();
          tx.update(walletRef, {'balance': currentBalance - payAmount});
        }
      });

      if (mounted) {
        Navigator.pop(context); // Tutup Dialog
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Berhasil dibayar Rp ${NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(payAmount)}"),
            backgroundColor: Colors.green
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e"), backgroundColor: Colors.red));
    }
  }

  // --- DIALOG PEMBAYARAN CANGGIH (SEPERTI APPROVAL) ---
  void _showPaymentDialog(BuildContext context, DebtModel debt) {
    final nominalCtrl = TextEditingController();
    // Default kosong agar user mikir dulu mau bayar berapa
    // nominalCtrl.text = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(debt.amount).trim();

    final List<int> percentages = [10, 25, 50, 75, 100]; // Pilihan Cepat

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (context, setStateDialog) {

            // Hitung Sisa Realtime untuk UI
            double inputVal = double.tryParse(nominalCtrl.text.replaceAll('.', '')) ?? 0;
            double sisaNanti = debt.amount - inputVal;
            if (sisaNanti < 0) sisaNanti = 0;

            return AlertDialog(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Bayar Utang", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(debt.name, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.normal)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        children: [
                          const Text("Sisa Tagihan Saat Ini", style: TextStyle(fontSize: 10, color: Colors.red)),
                          Text(NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(debt.amount), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // CHIPS PERSENTASE
                    const Text("Bayar Cepat (% dari sisa):", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: percentages.map((percent) {
                        return ActionChip(
                          label: Text(percent == 100 ? "Lunas" : "$percent%"),
                          backgroundColor: percent == 100 ? Colors.green.shade100 : Colors.blue.shade50,
                          labelStyle: TextStyle(
                              color: percent == 100 ? Colors.green.shade800 : Colors.blue.shade800,
                              fontWeight: FontWeight.bold, fontSize: 11
                          ),
                          onPressed: () {
                            double calc = debt.amount * (percent / 100);
                            String fmt = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(calc).trim();
                            setStateDialog(() { nominalCtrl.text = fmt; });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // INPUT MANUAL
                    const Text("Nominal Pembayaran"),
                    TextField(
                      controller: nominalCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [CurrencyInputFormatter()],
                      decoration: const InputDecoration(prefixText: "Rp ", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                      onChanged: (val) => setStateDialog((){}),
                    ),
                    const SizedBox(height: 10),

                    // INDIKATOR SISA
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: sisaNanti <= 0 ? Colors.green.shade50 : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8)
                      ),
                      child: Row(children: [
                        Icon(sisaNanti <= 0 ? Icons.check_circle : Icons.info, size: 16, color: sisaNanti <= 0 ? Colors.green : Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                            sisaNanti <= 0 ? "Utang akan LUNAS." : "Sisa Rp ${NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(sisaNanti)}",
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: sisaNanti <= 0 ? Colors.green.shade800 : Colors.orange.shade800)
                        )),
                      ]),
                    )
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: sisaNanti <= 0 ? Colors.green : Colors.orange),
                  onPressed: () {
                    double amount = double.tryParse(nominalCtrl.text.replaceAll('.', '')) ?? 0;
                    _processPayment(debt, amount);
                  },
                  child: Text(sisaNanti <= 0 ? "Lunasi Sekarang" : "Bayar Sebagian"),
                )
              ],
            );
          }
      ),
    );
  }

  // --- FORM INPUT/EDIT UTANG ---
  void _showDebtForm(BuildContext context, {DebtModel? debtToEdit}) {
    final nameCtrl = TextEditingController(text: debtToEdit?.name);
    final bankCtrl = TextEditingController(text: debtToEdit?.bankName);
    final rekCtrl = TextEditingController(text: debtToEdit?.accountNumber);
    final noteCtrl = TextEditingController(text: debtToEdit?.note);
    final amountCtrl = TextEditingController(text: debtToEdit != null ? NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(debtToEdit.amount).trim() : '');

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
          Text(debtToEdit == null ? "Catat Utang Vendor/Luar" : "Edit Data Utang", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Nama Pemberi Utang", border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: amountCtrl, keyboardType: TextInputType.number, inputFormatters: [CurrencyInputFormatter()], decoration: const InputDecoration(labelText: "Nominal (Rp)", prefixText: "Rp ", border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Row(children: [Expanded(child: TextField(controller: bankCtrl, decoration: const InputDecoration(labelText: "Nama Bank", border: OutlineInputBorder()))), const SizedBox(width: 12), Expanded(flex: 2, child: TextField(controller: rekCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "No. Rekening", border: OutlineInputBorder())))]),
          const SizedBox(height: 12),
          TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: "Catatan", border: OutlineInputBorder())),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary), onPressed: () async {
            if (nameCtrl.text.isEmpty || amountCtrl.text.isEmpty) return;
            final double amount = double.parse(amountCtrl.text.replaceAll('.', ''));
            final data = { 'name': nameCtrl.text, 'amount': amount, 'bank_name': bankCtrl.text, 'account_number': rekCtrl.text, 'note': noteCtrl.text, 'branch_id': widget.branchId, 'status': debtToEdit?.status ?? 'unpaid', 'type': 'payable', 'source': 'manual', 'created_at': debtToEdit?.createdAt ?? FieldValue.serverTimestamp() };
            if (debtToEdit == null) await _firestore.collection('debts').add(data); else await _firestore.collection('debts').doc(debtToEdit.id).update(data);
            if (context.mounted) Navigator.pop(context);
          }, child: Text(debtToEdit == null ? "SIMPAN DATA" : "UPDATE DATA"))),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No. Rekening disalin!"), duration: Duration(seconds: 1)));
  }

  // Helper ID Wallet (Copy dari Dashboard logic)
  String _getWalletId(String branchId) {
    switch (branchId) {
      case 'pusat': return 'main_cash';
      case 'bst_box': return 'petty_bst';
      case 'm_alfa': return 'petty_alfa';
      case 'saufa': return 'petty_saufa';
      default: return 'main_cash';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Utang: ${widget.branchId.toUpperCase().replaceAll('_', ' ')}", style: const TextStyle(color: Colors.black, fontSize: 16)), backgroundColor: Colors.white, elevation: 0, iconTheme: const IconThemeData(color: Colors.black), bottom: TabBar(controller: _tabController, labelColor: AppColors.primary, unselectedLabelColor: Colors.grey, indicatorColor: AppColors.primary, tabs: const [Tab(text: "Vendor / Manual"), Tab(text: "Sisa Approval")])),
      body: TabBarView(controller: _tabController, children: [_buildDebtList(isApprovalDebt: false), _buildDebtList(isApprovalDebt: true)]),
      floatingActionButton: FloatingActionButton(backgroundColor: AppColors.primary, child: const Icon(Icons.add, color: Colors.white), onPressed: () => _showDebtForm(context)),
    );
  }

  Widget _buildDebtList({required bool isApprovalDebt}) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('debts').where('branch_id', isEqualTo: widget.branchId).orderBy('created_at', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return Center(child: Text(isApprovalDebt ? "Tidak ada utang sisa approval" : "Tidak ada utang vendor"));
        final docs = snapshot.data!.docs.where((doc) { final data = doc.data() as Map<String, dynamic>; String source = data['source'] ?? 'manual'; return isApprovalDebt ? source == 'approval' : source != 'approval'; }).toList();
        if (docs.isEmpty) return Center(child: Text(isApprovalDebt ? "Tidak ada data di tab ini" : "Tidak ada data vendor"));
        return ListView.builder(padding: const EdgeInsets.all(16), itemCount: docs.length, itemBuilder: (context, index) { final data = docs[index].data() as Map<String, dynamic>; final debt = DebtModel.fromMap(data, docs[index].id); return _buildDebtCard(debt, isApprovalDebt); });
      },
    );
  }

  Widget _buildDebtCard(DebtModel debt, bool isApprovalDebt) {
    bool isPaid = debt.status == 'paid';
    return Card(
      margin: const EdgeInsets.only(bottom: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 2,
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(debt.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), Text(DateFormat('dd MMM yyyy').format(debt.createdAt), style: const TextStyle(fontSize: 12, color: Colors.grey))])), if(isApprovalDebt) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)), child: const Text("Approval", style: TextStyle(fontSize: 9, color: Colors.blue)))]),
        const Divider(height: 24),
        if (debt.bankName != null && debt.bankName!.isNotEmpty) ...[Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)), child: Row(children: [const Icon(Icons.account_balance, size: 20, color: Colors.grey), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(debt.bankName ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), Text(debt.accountNumber ?? '-', style: const TextStyle(fontSize: 14, fontFamily: 'monospace'))])), IconButton(icon: const Icon(Icons.copy, color: AppColors.primary, size: 20), onPressed: () => _copyToClipboard(debt.accountNumber ?? ''))])), const SizedBox(height: 12)],
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Sisa Tagihan", style: TextStyle(fontSize: 10, color: Colors.grey)), Text(NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(debt.amount), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isPaid ? Colors.green : Colors.red))]),
          if (!isPaid)
            ElevatedButton.icon(
              // [TOMBOL BAYAR CANGGIH]
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), minimumSize: Size.zero),
              onPressed: () => _showPaymentDialog(context, debt), // Buka Dialog Canggih
              icon: const Icon(Icons.payment, size: 16), // Ganti icon jadi wallet/payment
              label: const Text("Bayar"),
            )
          else const Text("LUNAS", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))
        ]),
        if (debt.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8.0), child: Text("Note: ${debt.note}", style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey))),
        if (!isApprovalDebt && !isPaid) Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _showDebtForm(context, debtToEdit: debt), icon: const Icon(Icons.edit, size: 14, color: Colors.grey), label: const Text("Edit", style: TextStyle(fontSize: 12, color: Colors.grey)))),
      ])),
    );
  }
}