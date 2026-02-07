import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

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

  // --- CONFIG 5 WALLET ---
  final String _companyWalletId = 'company_wallet';     // Level 1
  final String _treasurerWalletId = 'treasurer_wallet'; // Level 2

  // --- STATE USER ---
  String _userRole = 'admin_branch';
  String _userBranchId = '';
  String _userName = '';

  // --- STATE UI ---
  bool _isIncome = false;
  String? _selectedBranchId;
  String? _selectedWalletId; // Dompet sasaran
  String _transactionDateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
  DateTime _selectedDate = DateTime.now();

  // --- KATEGORI ---
  String? _selectedCategory;
  final TextEditingController _customCategoryCtrl = TextEditingController();

  final List<String> _incomeCategories = ['Penjualan', 'Jasa', 'Lainnya'];
  final List<String> _expenseCategories = [
    'Harian',             // Kas Cabang
    'Belanja Perusahaan', // Kas Bendahara
    'Maintenance',
    'Gaji',
    'Lainnya'
  ];

  // --- ITEMS ---
  List<_ItemController> _items = [];
  double _totalEstimated = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initUserAndData();
    _addItem();
  }

  @override
  void dispose() {
    for (var i in _items) i.dispose();
    _customCategoryCtrl.dispose();
    super.dispose();
  }

  void _initUserAndData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _userRole = doc['role'] ?? 'admin_branch';
          _userBranchId = doc['branch_id'] ?? 'bst_box';
          _userName = doc['name'] ?? 'Staff';

          // Set Branch Awal
          if (_userRole == 'owner') {
            _selectedBranchId = widget.branchId ?? 'bst_box';
          } else {
            _selectedBranchId = _userBranchId;
          }

          if (widget.transactionToEdit != null) {
            _loadEditData();
          } else {
            // Default: Pengeluaran Harian
            _selectedCategory = 'Harian';
            _updateAutoWalletLogic();
          }
        });
      }
    }
  }

  void _loadEditData() {
    final tx = widget.transactionToEdit!;
    _isIncome = tx.type == 'income';
    _selectedBranchId = tx.relatedBranchId;
    _selectedWalletId = tx.walletId;
    _selectedDate = tx.date;
    _transactionDateStr = DateFormat('yyyy-MM-dd').format(tx.date);

    // Kategori
    List<String> targetList = _isIncome ? _incomeCategories : _expenseCategories;
    if (targetList.contains(tx.category)) {
      _selectedCategory = tx.category;
    } else {
      _selectedCategory = 'Lainnya';
      _customCategoryCtrl.text = tx.category;
    }

    _items.clear();
    // Parse deskripsi jika formatnya "Item (xQty), Item (xQty) (Dicatat oleh...)"
    String rawDesc = tx.description.split(' (Dicatat oleh:')[0];
    _items.add(_ItemController()
      ..name.text = rawDesc
      ..price.text = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(tx.amount).trim()
      ..qty.text = "1"
    );
    _calculateTotal();
    _updateAutoWalletLogic();
  }

  // --- LOGIC PENENTUAN DOMPET (SANGAT PENTING) ---
  void _updateAutoWalletLogic() {
    if (_selectedBranchId == null) return;

    setState(() {
      if (_isIncome) {
        // PEMASUKAN: Selalu Masuk Uang Perusahaan (Level 1)
        _selectedWalletId = _companyWalletId;

        if (!_incomeCategories.contains(_selectedCategory)) _selectedCategory = _incomeCategories.first;
      } else {
        // PENGELUARAN:
        if (!_expenseCategories.contains(_selectedCategory)) _selectedCategory = _expenseCategories.first;

        if (_userRole == 'owner') {
          // OWNER: Bisa pilih sumber dana via Kategori
          if (_selectedCategory == 'Harian') {
            _selectedWalletId = _getBranchWalletId(_selectedBranchId!); // Pakai Kas Cabang
          } else {
            _selectedWalletId = _treasurerWalletId; // Default pakai Kas Bendahara
          }
        } else {
          // ADMIN CABANG: Selalu pakai Kas Kecil Cabang (Level 3)
          // Admin tidak punya akses ke Kas Bendahara
          _selectedWalletId = _getBranchWalletId(_selectedBranchId!);
        }
      }
    });
  }

  String _getBranchWalletId(String branchId) {
    switch (branchId) {
      case 'm_alfa': return 'petty_alfa';
      case 'saufa': return 'petty_saufa';
      case 'bst_box': return 'petty_box';
      default: return 'petty_box';
    }
  }

  String _getWalletNameDisplay() {
    if (_selectedWalletId == _companyWalletId) return "Uang Perusahaan (Pusat)";
    if (_selectedWalletId == _treasurerWalletId) return "Kas Bendahara Pusat";
    return "Kas Kecil Cabang";
  }

  void _addItem() {
    setState(() {
      _items.add(_ItemController());
    });
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

  void _calculateTotal() {
    double total = 0;
    for (var item in _items) {
      double price = double.tryParse(item.price.text.replaceAll('.', '')) ?? 0;
      int qty = int.tryParse(item.qty.text) ?? 1;
      total += (price * qty);
    }
    setState(() {
      _totalEstimated = total;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _transactionDateStr = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_totalEstimated <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Total nominal tidak boleh 0")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final user = FirebaseAuth.instance.currentUser;

      String baseDesc = _items.map((e) => "${e.name.text} (${e.qty.text}x)").join(", ");
      String fullDesc = "$baseDesc (Dicatat oleh: $_userName)";

      String finalCategory = _selectedCategory ?? 'Umum';
      if (finalCategory == 'Lainnya') {
        finalCategory = _customCategoryCtrl.text.isNotEmpty ? _customCategoryCtrl.text : 'Lainnya';
      }

      // Validasi Saldo (Khusus Pengeluaran)
      if (!_isIncome && _selectedWalletId != null) {
        final walletDoc = await firestore.collection('wallets').doc(_selectedWalletId).get();
        double currentBalance = (walletDoc.data()?['balance'] ?? 0).toDouble();

        if (currentBalance < _totalEstimated) {
          String walletName = _getWalletNameDisplay();
          throw Exception("Saldo $walletName tidak cukup! (Sisa: ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(currentBalance)})");
        }
      }

      final txData = TransactionModel(
        id: widget.transactionToEdit?.id ?? '',
        amount: _totalEstimated,
        type: _isIncome ? 'income' : 'expense',
        category: finalCategory,
        description: fullDesc,
        walletId: _selectedWalletId!,
        date: _selectedDate,
        userId: user?.uid ?? 'unknown',
        relatedBranchId: _selectedBranchId,
        deletedAt: null,
      );

      await firestore.runTransaction((tx) async {
        final walletRef = firestore.collection('wallets').doc(_selectedWalletId);
        final walletSnap = await tx.get(walletRef);

        if (!walletSnap.exists) throw Exception("Dompet tujuan tidak ditemukan!");
        double currentBalance = (walletSnap.get('balance') ?? 0).toDouble();

        double newBalance;
        if (_isIncome) {
          newBalance = currentBalance + _totalEstimated;
        } else {
          newBalance = currentBalance - _totalEstimated;
        }

        tx.update(walletRef, {'balance': newBalance});

        final newTxRef = widget.transactionToEdit != null
            ? firestore.collection('transactions').doc(widget.transactionToEdit!.id)
            : firestore.collection('transactions').doc();

        tx.set(newTxRef, txData.toMap());
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Berhasil Disimpan!"), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: ${e.toString().replaceAll('Exception:', '')}"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isOwner = _userRole == 'owner';
    List<String> currentCategories = _isIncome ? _incomeCategories : _expenseCategories;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(_isIncome ? "Catat Pemasukan" : "Catat Pengeluaran"),
        backgroundColor: _isIncome ? AppColors.success : AppColors.error,
        elevation: 0,
      ),
      body: Column(
        children: [
          // HEADER
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                // Switch Type
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      _buildTypeButton("Pengeluaran", false),
                      _buildTypeButton("Pemasukan", true),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    // Dropdown Cabang (Owner Only)
                    if (isOwner)
                      Expanded(
                        flex: 4,
                        child: DropdownButtonFormField<String>(
                          value: _selectedBranchId,
                          decoration: const InputDecoration(labelText: "Cabang", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                          items: const [
                            DropdownMenuItem(value: 'bst_box', child: Text("Box Factory")),
                            DropdownMenuItem(value: 'm_alfa', child: Text("Maint. Alfa")),
                            DropdownMenuItem(value: 'saufa', child: Text("Saufa Olshop")),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedBranchId = val;
                              _updateAutoWalletLogic();
                            });
                          },
                        ),
                      ),
                    if (isOwner) const SizedBox(width: 10),

                    // Dropdown Kategori
                    Expanded(
                      flex: 6,
                      child: DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: "Kategori", border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                        items: currentCategories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedCategory = val;
                            _updateAutoWalletLogic();
                          });
                        },
                      ),
                    ),
                  ],
                ),

                if (_selectedCategory == 'Lainnya')
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: TextField(
                      controller: _customCategoryCtrl,
                      decoration: const InputDecoration(labelText: "Tulis Kategori...", border: OutlineInputBorder(), isDense: true),
                    ),
                  ),

                const SizedBox(height: 12),

                // INFO BOX DOMPET (Agar user sadar uang masuk/keluar darimana)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isIncome ? Colors.green[50] : Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: _isIncome ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3)
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                          _isIncome ? Icons.input : Icons.output,
                          color: _isIncome ? Colors.green : Colors.red,
                          size: 20
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                _isIncome
                                    ? "Masuk ke: ${_getWalletNameDisplay()}"
                                    : "Sumber Dana: ${_getWalletNameDisplay()}",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: _isIncome ? Colors.green[800] : Colors.red[800]
                                )
                            ),
                            Text(
                                "Dicatat oleh: $_userName",
                                style: const TextStyle(fontSize: 10, color: Colors.grey)
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),

          // LIST ITEM
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _items.length + 1,
                separatorBuilder: (c, i) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  if (index == _items.length) {
                    return _buildAddButtonAndDate();
                  }
                  return _buildItemRow(index);
                },
              ),
            ),
          ),

          // BOTTOM
          _buildBottomSummary(),
        ],
      ),
    );
  }

  Widget _buildTypeButton(String label, bool isIncomeBtn) {
    bool isActive = _isIncome == isIncomeBtn;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isIncome = isIncomeBtn;
            _updateAutoWalletLogic();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? (isIncomeBtn ? AppColors.success : AppColors.error) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemRow(int index) {
    final item = _items[index];
    return Dismissible(
      key: UniqueKey(),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _removeItem(index),
      background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: TextFormField(controller: item.name, decoration: const InputDecoration(labelText: "Keterangan", border: InputBorder.none, isDense: true), validator: (v) => v!.isEmpty ? "Wajib" : null)),
                if (_items.length > 1) IconButton(onPressed: () => _removeItem(index), icon: const Icon(Icons.close, color: Colors.red, size: 18))
              ],
            ),
            const Divider(height: 1),
            Row(
              children: [
                Expanded(flex: 2, child: TextFormField(controller: item.price, keyboardType: TextInputType.number, inputFormatters: [CurrencyInputFormatter()], decoration: const InputDecoration(prefixText: "Rp ", border: InputBorder.none, labelText: "Harga"), onChanged: (_) => _calculateTotal(), validator: (v) => v!.isEmpty ? "Wajib" : null)),
                Container(width: 1, height: 30, color: Colors.grey[300]),
                Expanded(flex: 1, child: TextFormField(controller: item.qty, textAlign: TextAlign.center, keyboardType: TextInputType.number, decoration: const InputDecoration(border: InputBorder.none, labelText: "Qty"), onChanged: (_) => _calculateTotal())),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildAddButtonAndDate() {
    return Column(
      children: [
        OutlinedButton.icon(onPressed: _addItem, icon: const Icon(Icons.add_circle_outline), label: const Text("Tambah Item"), style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 45))),
        const SizedBox(height: 16),
        InkWell(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8), color: Colors.white),
            child: Row(children: [const Icon(Icons.calendar_today, size: 18, color: Colors.grey), const SizedBox(width: 10), Text("Tanggal: $_transactionDateStr", style: const TextStyle(fontWeight: FontWeight.bold))]),
          ),
        )
      ],
    );
  }

  Widget _buildBottomSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -2))]),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Total:", style: TextStyle(color: Colors.grey)), Text(NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(_totalEstimated), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _isIncome ? AppColors.success : AppColors.error))]),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _isIncome ? AppColors.success : AppColors.error, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: _isLoading ? null : _submitTransaction, child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("SIMPAN TRANSAKSI", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)))),
        ],
      ),
    );
  }
}