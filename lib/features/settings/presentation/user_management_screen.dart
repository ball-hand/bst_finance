import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../data/user_repository.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final UserRepository _repo = UserRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Manajemen User Akses"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _repo.getUsersStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final users = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final data = users[index].data() as Map<String, dynamic>;
              final uid = users[index].id;
              return _buildUserCard(data, uid);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddUserDialog(),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text("Tambah Admin Cabang", style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> data, String uid) {
    String role = data['role'] ?? 'user';
    String branch = (data['branch_id'] ?? '-').toString().toUpperCase();
    bool isOwner = role == 'owner';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isOwner ? AppColors.primary : Colors.orange,
            child: Icon(isOwner ? Icons.shield : Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['name'] ?? 'No Name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(data['email'] ?? '-', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isOwner ? Colors.blue[50] : Colors.orange[50],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isOwner ? "OWNER (PUSAT)" : "ADMIN CABANG: $branch",
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isOwner ? AppColors.primary : Colors.orange[800]
                    ),
                  ),
                )
              ],
            ),
          ),
          if (!isOwner) // Owner tidak bisa dihapus
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () async {
                // Konfirmasi Hapus
                await _repo.deleteUserUnlink(uid);
                setState(() {});
              },
            )
        ],
      ),
    );
  }

  // DIALOG TAMBAH USER
  void _showAddUserDialog() {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String selectedBranch = 'bst_box';
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Buat Akun Cabang"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Nama Admin")),
                  TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: "Email Login")),
                  TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Password")),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedBranch,
                    decoration: const InputDecoration(labelText: "Tugas di Cabang", border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'bst_box', child: Text("Box Factory")),
                      DropdownMenuItem(value: 'm_alfa', child: Text("Maint. Alfa")),
                      DropdownMenuItem(value: 'saufa', child: Text("Saufa Olshop")),
                    ],
                    onChanged: (val) => selectedBranch = val!,
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
                ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    if (emailCtrl.text.isEmpty || passCtrl.text.isEmpty) return;
                    setState(() => isLoading = true);

                    try {
                      await _repo.createBranchUser(
                        email: emailCtrl.text.trim(),
                        password: passCtrl.text.trim(),
                        name: nameCtrl.text,
                        branchId: selectedBranch,
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("User Berhasil Dibuat!")));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                        setState(() => isLoading = false);
                      }
                    }
                  },
                  child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator()) : const Text("Buat User"),
                )
              ],
            );
          },
        );
      },
    );
  }
}