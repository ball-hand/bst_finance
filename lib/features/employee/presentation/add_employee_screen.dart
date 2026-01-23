import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/employee_repository.dart';
import '../domain/employee_model.dart';
import '../../../core/utils/currency_formatter.dart';

class AddEmployeeScreen extends StatefulWidget {
  final String branchId;
  final String branchName;
  final EmployeeModel? employeeToEdit; // Parameter untuk Edit

  const AddEmployeeScreen({
    super.key,
    required this.branchId,
    this.branchName = "Cabang",
    this.employeeToEdit,
  });

  @override
  State<AddEmployeeScreen> createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends State<AddEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _salaryCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // State untuk Dropdown
  String _selectedPosition = 'Staff';
  int _selectedPayday = 1;
  late String _selectedBranchId; // [BARU] Variable Cabang Terpilih

  // Data Pilihan
  final List<String> _positions = ['Staff', 'Kasir', 'Gudang', 'Supervisor', 'Keamanan', 'Lainnya'];
  final List<int> _dates = List.generate(31, (index) => index + 1);

  // [BARU] Daftar Cabang
  final List<Map<String, String>> _branches = [
    {'id': 'bst_box', 'name': 'Box Factory'},
    {'id': 'm_alfa', 'name': 'Maint. Alfa'},
    {'id': 'saufa', 'name': 'Saufa Olshop'},
    {'id': 'pusat', 'name': 'Kantor Pusat'},
  ];

  DateTime _joinedDate = DateTime.now();
  bool _isLoading = false;
  bool get _isEditing => widget.employeeToEdit != null;

  @override
  void initState() {
    super.initState();
    // Default cabang mengikuti parameter awal
    _selectedBranchId = widget.branchId;

    // Jika sedang Edit, isi form dengan data lama
    if (_isEditing) {
      final e = widget.employeeToEdit!;
      _nameCtrl.text = e.name;
      _phoneCtrl.text = e.phoneNumber;
      _selectedPayday = e.paydayDate;
      _joinedDate = e.joinedDate;
      _selectedBranchId = e.branchId; // [BARU] Load cabang lama

      if (_positions.contains(e.position)) {
        _selectedPosition = e.position;
      } else {
        _selectedPosition = 'Staff';
      }

      final formatter = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0);
      _salaryCtrl.text = formatter.format(e.baseSalary).trim();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      double salary = double.parse(_salaryCtrl.text.replaceAll('.', ''));

      // [BARU] Cari Nama Cabang berdasarkan ID yang dipilih
      String selectedBranchName = _branches.firstWhere(
              (b) => b['id'] == _selectedBranchId,
          orElse: () => {'name': 'Unknown'}
      )['name']!;

      final employeeData = EmployeeModel(
        id: _isEditing ? widget.employeeToEdit!.id : '',
        name: _nameCtrl.text,
        position: _selectedPosition,
        branchId: _selectedBranchId,    // [UPDATE] Pakai yang dipilih
        branchName: selectedBranchName, // [UPDATE] Pakai nama yang sesuai
        baseSalary: salary,
        phoneNumber: _phoneCtrl.text,
        paydayDate: _selectedPayday,
        joinedDate: _joinedDate,
      );

      if (_isEditing) {
        await EmployeeRepository().updateEmployee(
            widget.employeeToEdit!.id,
            employeeData.toMap()
        );
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data Pegawai Diperbarui!")));
      } else {
        await EmployeeRepository().addEmployee(employeeData);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pegawai Berhasil Ditambahkan!")));
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? "Edit Data Pegawai" : "Tambah Pegawai"),
        backgroundColor: _isEditing ? Colors.orange : Colors.blue,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [

                // [REVISI] GANTI INFO CABANG DENGAN DROPDOWN
                DropdownButtonFormField<String>(
                  value: _branches.any((b) => b['id'] == _selectedBranchId) ? _selectedBranchId : null,
                  decoration: const InputDecoration(
                    labelText: "Penempatan Cabang",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: _branches.map((b) => DropdownMenuItem(
                    value: b['id'],
                    child: Text(b['name']!),
                  )).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedBranchId = val!;
                    });
                  },
                ),
                const SizedBox(height: 20),

                // 1. NAMA
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: "Nama Lengkap", border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                  validator: (v) => v!.isEmpty ? "Wajib diisi" : null,
                ),
                const SizedBox(height: 16),

                // 2. WHATSAPP
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: "No. WhatsApp", border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)),
                  validator: (v) => v!.isEmpty ? "Wajib diisi" : null,
                ),
                const SizedBox(height: 16),

                // 3. JABATAN & TGL GAJIAN
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedPosition,
                        decoration: const InputDecoration(labelText: "Jabatan", border: OutlineInputBorder()),
                        items: _positions.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                        onChanged: (val) => setState(() => _selectedPosition = val!),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _selectedPayday,
                        decoration: const InputDecoration(labelText: "Tgl Gajian", border: OutlineInputBorder()),
                        items: _dates.map((d) => DropdownMenuItem(value: d, child: Text("Tgl $d"))).toList(),
                        onChanged: (val) => setState(() => _selectedPayday = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 4. GAJI POKOK
                TextFormField(
                  controller: _salaryCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [CurrencyInputFormatter()],
                  decoration: const InputDecoration(
                      labelText: "Gaji Pokok",
                      border: OutlineInputBorder(),
                      prefixText: "Rp ",
                      prefixIcon: Icon(Icons.monetization_on)
                  ),
                  validator: (v) => v!.isEmpty ? "Wajib diisi" : null,
                ),

                const SizedBox(height: 30),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _isEditing ? Colors.orange : Colors.blue
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                        _isEditing ? "UPDATE DATA" : "SIMPAN PEGAWAI",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}