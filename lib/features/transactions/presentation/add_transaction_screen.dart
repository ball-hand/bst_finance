import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// Pastikan import ini sesuai dengan struktur folder Anda
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/transaction_model.dart';

class AddTransactionScreen extends StatefulWidget {
  final String? branchId;
  final TransactionModel? transactionToEdit;

  const AddTransactionScreen({super.key, this.branchId, this.transactionToEdit});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

// Controller untuk item list
class _ItemController {
  TextEditingController name = TextEditingController();
  TextEditingController qty = TextEditingController(text: '1');
  TextEditingController price = TextEditingController();

  void dispose() {
    name.dispose();
    qty.dispose();
    price.dispose();
  }
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();

  // --- CONFIG ---
  // Pastikan ID ini sesuai dengan ID Dokumen Wallet Pusat di Firestore Anda
  final String _centralWalletDocId = 'main_cash';

  // --- STATE USER ---
  String _userRole = 'admin_branch';
  String _userBranchId = '';

  // --- STATE UI ---
  bool _isIncome = false; // Default Pengeluaran
  String? _selectedBranchId;
  String? _selectedWalletId;
  String _walletNameDisplay = "Menentukan...";
  bool _isCentralWallet = false;
  DateTime _selectedDate = DateTime.now();
  String _category = 'Harian'; // Default Kategori

  // --- LOGIC ITEM ---
  List<_ItemController> _items = [];
  double _totalEstimated = 0;
  bool _isLoading = false;
  final TextEditingController _noteController = TextEditingController();

  // LIST KATEGORI
  final List<String> _expenseCategories = ['Harian', 'Belanja Perusahaan', 'Maintenance', 'Operasional', 'Lain-lain'];
  final List<String> _incomeCategories = ['Penjualan', 'Pembayaran Invoice', 'Suntikan Modal'];

  @override
  void initState() {
    super.initState();
    _fetchUserData();

    if (widget.transactionToEdit != null) {
      _loadEditData();
    } else {
      _selectedBranchId = widget.branchId;
      _items.add(_ItemController()); // Tambah 1 baris item default
    }
  }

  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _userRole = doc['role'] ?? 'admin_branch';
          _userBranchId = doc['branch_id'] ?? 'unknown';

          // Jika Admin Cabang buat baru, kunci ke cabangnya sendiri
          if (widget.transactionToEdit == null && _userRole != 'owner') {
            _selectedBranchId = _userBranchId;
          }
        });
        _updateAutoWalletLogic();
      }
    }
  }

  void _loadEditData() {
    final tx = widget.transactionToEdit!;
    _isIncome = tx.type == 'income';
    _selectedWalletId = tx.walletId;
    _selectedDate = tx.date;
    _category = tx.category;
    _noteController.text = tx.description;
    _selectedBranchId = tx.relatedBranchId;

    // Load Item (Disederhanakan karena data item detail tdk disimpan terpisah di model lama)
    // Kita anggap deskripsi sebagai nama item untuk edit
    final itemParams = _ItemController();
    itemParams.name.text = "Edit: ${tx.description}";
    itemParams.qty.text = "1";
    itemParams.price.text = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(tx.amount).trim();
    _items.add(itemParams);

    _calculateTotal();
  }

  @override
  void dispose() {
    for (var i in _items) { i.dispose(); }
    _noteController.dispose();
    super.dispose();
  }

  // Hitung total dari semua item
  void _calculateTotal() {
    double tempTotal = 0;
    for (var item in _items) {
      double qty = double.tryParse(item.qty.text) ?? 0;
      double price = double.tryParse(item.price.text.replaceAll('.', '')) ?? 0;
      tempTotal += (qty * price);
    }
    setState(() {
      _totalEstimated = tempTotal;
    });
  }

  // --- LOGIKA CERDAS PEMILIHAN DOMPET (UNTUK TAMPILAN UI) ---
  Future<void> _updateAutoWalletLogic() async {
    if (_selectedBranchId == null) return;

    if (_isIncome) {
      // Pemasukan -> Secara visual diarahkan ke Pusat
      await _findWalletMain();
      setState(() => _isCentralWallet = true);
    } else {
      // PENGELUARAN
      if (_category == 'Harian') {
        // Harian -> Kas Kecil Cabang
        await _findWalletByBranch(_selectedBranchId!, isMain: false);
        setState(() => _isCentralWallet = false);
      } else {
        // Belanja Besar -> Kas Pusat
        await _findWalletMain();
        setState(() => _isCentralWallet = true);
      }
    }
  }

  Future<void> _findWalletByBranch(String branchId, {required bool isMain}) async {
    final query = await FirebaseFirestore.instance
        .collection('wallets')
        .where('branch_id', isEqualTo: branchId)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty && mounted) {
      setState(() {
        _selectedWalletId = query.docs.first.id;
        _walletNameDisplay = query.docs.first['name'];
      });
    } else if (branchId == 'pusat') {
      _findWalletMain();
    }
  }

  Future<void> _findWalletMain() async {
    // Coba cari by ID dulu
    final doc = await FirebaseFirestore.instance.collection('wallets').doc(_centralWalletDocId).get();
    if (doc.exists && mounted) {
      setState(() {
        _selectedWalletId = doc.id;
        _walletNameDisplay = doc.data()?['name'] ?? 'Kas Pusat';
      });
    } else {
      // Fallback search by query
      final query = await FirebaseFirestore.instance.collection('wallets').where('branch_id', isEqualTo: 'pusat').limit(1).get();
      if (query.docs.isNotEmpty && mounted) {
        setState(() {
          _selectedWalletId = query.docs.first.id;
          _walletNameDisplay = query.docs.first['name'];
        });
      }
    }
  }

  void _addItem() {
    setState(() => _items.add(_ItemController()));
  }

  void _removeItem(int index) {
    if (_items.length > 1) {
      setState(() {
        _items[index].dispose();
        _items.removeAt(index);
        _calculateTotal();
      });
    }
  }

  // --- EKSEKUSI TRANSAKSI ---
  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pilih Cabang Terlebih Dahulu")));
      return;
    }
    if (_totalEstimated <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nominal tidak boleh 0")));
      return;
    }

    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    final firestore = FirebaseFirestore.instance;

    // Siapkan Deskripsi dari Item List
    String finalDescription = "";
    if (_category == 'Suntikan Modal') {
      finalDescription = "Suntikan Modal: ${_noteController.text}";
    } else {
      finalDescription = _items.map((e) => "${e.name.text} (${e.qty.text}x)").join(", ");
      if (_noteController.text.isNotEmpty) finalDescription += " - ${_noteController.text}";
    }

    // Cek butuh approval?
    bool needsApproval = !_isIncome && _isCentralWallet && _userRole != 'owner';

    try {
      if (needsApproval) {
        // --- ALUR 1: APPROVAL (REQUEST) ---
        await firestore.collection('requests').add({
          'branch_id': _selectedBranchId,
          'requester_id': user?.uid,
          'requester_name': user?.displayName ?? 'Admin',
          'item_name': finalDescription,
          'amount': _totalEstimated,
          'category': _category,
          'wallet_target': _selectedWalletId,
          'status': 'pending',
          'created_at': FieldValue.serverTimestamp(),
          'note': _noteController.text,
        });

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Permintaan Approval Dikirim!"), backgroundColor: Colors.orange));
        }

      } else {
        // --- ALUR 2: TRANSAKSI LANGSUNG (RUN TRANSACTION) ---
        await firestore.runTransaction((transaction) async {

          // [LOGIKA FIX] Tentukan Target Dompet secara paksa di Backend
          String targetWalletId;

          if (_isIncome) {
            // Pemasukan WAJIB ke Pusat ('main_cash')
            targetWalletId = _centralWalletDocId;
          } else {
            // Pengeluaran ambil dari wallet yang terdeteksi di UI (Bisa Cabang/Pusat)
            if (_selectedWalletId == null) throw Exception("Dompet asal belum terpilih!");
            targetWalletId = _selectedWalletId!;
          }

          // Ambil data dompet
          final walletRef = firestore.collection('wallets').doc(targetWalletId);
          final walletSnap = await transaction.get(walletRef);

          if (!walletSnap.exists) {
            throw Exception("Dompet target ($targetWalletId) tidak ditemukan!");
          }

          double currentBalance = (walletSnap.get('balance') ?? 0).toDouble();

          // Hitung Saldo
          if (_isIncome) {
            currentBalance += _totalEstimated;
          } else {
            currentBalance -= _totalEstimated;
          }

          // Simpan Transaksi
          final newTxRef = firestore.collection('transactions').doc();
          transaction.set(newTxRef, {
            'amount': _totalEstimated,
            'type': _isIncome ? 'income' : 'expense',
            'category': _category,
            'description': finalDescription,
            'wallet_id': targetWalletId, // ID Dompet yang benar
            'related_branch_id': _selectedBranchId, // ID Cabang pelapor
            'date': Timestamp.fromDate(_selectedDate),
            'user_id': user?.uid ?? 'unknown',
            'created_at': FieldValue.serverTimestamp(),
            'deleted_at': null, // [FIX] Wajib ada agar muncul di history
            'status': 'success',
          });

          // Update Saldo Wallet
          transaction.update(walletRef, {'balance': currentBalance});
        });

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Transaksi Berhasil Disimpan!"), backgroundColor: Colors.green));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- UI BUILDER (RESPONSIVE) ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Input Data", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
        builder: (context, constraints) {
          // Jika Tablet (Lebar > 600)
          if (constraints.maxWidth > 600) {
            return _buildTabletLayout();
          } else {
            // Jika HP
            return _buildMobileLayout();
          }
        },
      ),
    );
  }

  // --- LAYOUT HP (1 Kolom) ---
  Widget _buildMobileLayout() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildTypeToggle(),
                  const SizedBox(height: 20),
                  _buildGeneralInfoCard(),
                  const SizedBox(height: 20),
                  _buildItemsCard(),
                ],
              ),
            ),
          ),
        ),
        _buildBottomSummary(),
      ],
    );
  }

  // --- LAYOUT TABLET (2 Kolom) ---
  Widget _buildTabletLayout() {
    return Form(
      key: _formKey,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KIRI: INPUT DATA UTAMA
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  _buildTypeToggle(),
                  const SizedBox(height: 24),
                  _buildGeneralInfoCard(),
                  const SizedBox(height: 24),
                  _buildItemsCard(),
                ],
              ),
            ),
          ),
          // KANAN: RINGKASAN & AKSI
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Ringkasan Transaksi", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text("Cabang: ${_selectedBranchId ?? '-'}", style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  Text("Kategori: $_category", style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  Text("Sumber Dana: $_walletNameDisplay", style: const TextStyle(fontSize: 16, color: Colors.grey)),
                  const Spacer(),
                  _buildBottomSummaryContent(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET KOMPONEN ---

  // Tombol Pemasukan / Pengeluaran
  Widget _buildTypeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(child: GestureDetector(
            onTap: () { setState(() { _isIncome = false; _category = 'Harian'; _updateAutoWalletLogic(); }); },
            child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: !_isIncome ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(10), boxShadow: !_isIncome ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)] : []),
                child: const Center(child: Text("Pengeluaran", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))))
        )),
        Expanded(child: GestureDetector(
            onTap: () { setState(() { _isIncome = true; _category = 'Penjualan'; _updateAutoWalletLogic(); }); },
            child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: _isIncome ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(10), boxShadow: _isIncome ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)] : []),
                child: const Center(child: Text("Pemasukan", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))))
        )),
      ]),
    );
  }

  // Kartu Informasi Dasar (Cabang, Kategori, Dompet)
  Widget _buildGeneralInfoCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Informasi Dasar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),

            // Kategori Dropdown
            DropdownButtonFormField<String>(
              value: _isIncome ? (_incomeCategories.contains(_category) ? _category : _incomeCategories.first) : (_expenseCategories.contains(_category) ? _category : _expenseCategories.first),
              decoration: InputDecoration(labelText: "Kategori", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              items: (_isIncome ? _incomeCategories : _expenseCategories).map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (val) { setState(() => _category = val!); _updateAutoWalletLogic(); },
            ),
            const SizedBox(height: 16),

            // Cabang Dropdown
            DropdownButtonFormField<String>(
              value: _selectedBranchId,
              decoration: InputDecoration(labelText: "Cabang", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), prefixIcon: const Icon(Icons.business), fillColor: Colors.blue.shade50, filled: true),
              items: const [
                DropdownMenuItem(value: 'bst_box', child: Text("Box Factory")),
                DropdownMenuItem(value: 'm_alfa', child: Text("Maint. Alfa")),
                DropdownMenuItem(value: 'saufa', child: Text("Saufa Olshop")),
                DropdownMenuItem(value: 'pusat', child: Text("Kantor Pusat")),
              ],
              onChanged: _userRole == 'owner' ? (val) { setState(() => _selectedBranchId = val); _updateAutoWalletLogic(); } : null,
            ),
            const SizedBox(height: 16),

            // Info Sumber Dana (Read Only)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _isCentralWallet ? Colors.blue.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(_isCentralWallet ? Icons.account_balance : Icons.wallet, color: _isCentralWallet ? Colors.blue : Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("Sumber Dana: $_walletNameDisplay", style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(_isCentralWallet ? "Kas Pusat" : "Kas Kecil Cabang", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ]),
                )
              ]),
            ),
            const SizedBox(height: 16),

            // Tanggal
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
                if (picked != null) setState(() => _selectedDate = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Tanggal', border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_today)),
                child: Text(DateFormat('dd MMMM yyyy').format(_selectedDate)),
              ),
            ),

            const SizedBox(height: 16),
            // Catatan
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: "Catatan Tambahan (Opsional)", border: OutlineInputBorder()),
            )
          ],
        ),
      ),
    );
  }

  // Kartu Input Barang (Dynamic List)
  Widget _buildItemsCard() {
    bool showItems = !(_isIncome && _category == 'Suntikan Modal');

    // Jika Suntikan Modal, Cuma butuh Nominal
    if (!showItems) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextFormField(
              controller: _items[0].price,
              keyboardType: TextInputType.number,
              inputFormatters: [CurrencyInputFormatter()],
              decoration: const InputDecoration(labelText: "Nominal Modal", prefixText: "Rp ", border: OutlineInputBorder()),
              onChanged: (_) { _items[0].qty.text = "1"; _calculateTotal(); },
            )
        ),
      );
    }

    // Jika item list biasa
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Detail Item", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              TextButton.icon(onPressed: _addItem, icon: const Icon(Icons.add, size: 16), label: const Text("Tambah"))
            ]),
            ...List.generate(_items.length, (index) => _buildItemRow(index)),
          ],
        ),
      ),
    );
  }

  // Baris per Item
  Widget _buildItemRow(int index) {
    final item = _items[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Row(children: [
            Expanded(child: TextFormField(
              controller: item.name,
              decoration: const InputDecoration(labelText: "Nama Item", contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true, border: OutlineInputBorder()),
              validator: (val) => val!.isEmpty ? 'Isi nama' : null,
            )),
            if(_items.length > 1) IconButton(onPressed: () => _removeItem(index), icon: const Icon(Icons.close, color: Colors.red, size: 20))
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(flex: 1, child: TextFormField(
                controller: item.qty, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Qty", contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true, border: OutlineInputBorder()),
                onChanged: (_) => _calculateTotal()
            )),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: TextFormField(
                controller: item.price, keyboardType: TextInputType.number, inputFormatters: [CurrencyInputFormatter()],
                decoration: const InputDecoration(labelText: "Harga", prefixText: "Rp ", contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8), isDense: true, border: OutlineInputBorder()),
                onChanged: (_) => _calculateTotal(), validator: (val) => val!.isEmpty ? 'Isi harga' : null
            )),
          ]),
        ],
      ),
    );
  }

  // Summary di Bawah (Mobile)
  Widget _buildBottomSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -2))]),
      child: _buildBottomSummaryContent(),
    );
  }

  // Isi Summary & Tombol Simpan
  Widget _buildBottomSummaryContent() {
    bool needsApproval = !_isIncome && _isCentralWallet && _userRole != 'owner';
    String btnText = needsApproval ? "AJUKAN APPROVAL" : "SIMPAN TRANSAKSI";
    Color btnColor = needsApproval ? Colors.orange : (_isIncome ? Colors.green : Colors.blue);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text("Total Estimasi:", style: TextStyle(color: Colors.grey)),
          Text(NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(_totalEstimated), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: btnColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: _submitTransaction,
            child: Text(btnText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        )
      ],
    );
  }
}