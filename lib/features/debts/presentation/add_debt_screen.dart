import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../data/debt_repository.dart';

class AddDebtScreen extends StatefulWidget {
  const AddDebtScreen({super.key});

  @override
  State<AddDebtScreen> createState() => _AddDebtScreenState();
}

class _AddDebtScreenState extends State<AddDebtScreen> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  String _selectedBranch = 'bst_box'; // Default cabang
  bool _isLoading = false;

  final List<Map<String, String>> _branches = [
    {'id': 'bst_box', 'name': 'Box Factory'},
    {'id': 'm_alfa', 'name': 'Maint. Alfa'},
    {'id': 'saufa', 'name': 'Saufa Olshop'},
  ];

  void _submit() async {
    if (_nameController.text.isEmpty || _amountController.text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await DebtRepository().addDebt(
        name: _nameController.text,
        amount: double.parse(_amountController.text),
        branchId: _selectedBranch,
        note: _noteController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Utang Berhasil Disimpan")));
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Catat Utang Manual"), backgroundColor: AppColors.error, foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Nama Kreditur / Supplier", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Nominal Utang (Rp)", border: OutlineInputBorder())
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField(
              value: _selectedBranch,
              items: _branches.map((b) => DropdownMenuItem(value: b['id'], child: Text(b['name']!))).toList(),
              onChanged: (val) => setState(() => _selectedBranch = val as String),
              decoration: const InputDecoration(labelText: "Beban Cabang", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(controller: _noteController, decoration: const InputDecoration(labelText: "Catatan (Jatuh Tempo)", border: OutlineInputBorder())),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("SIMPAN UTANG"),
              ),
            )
          ],
        ),
      ),
    );
  }
}