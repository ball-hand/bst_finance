import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/constants/app_colors.dart';
import '../../debts/presentation/debt_list_screen.dart';

class NotificationScreen extends StatefulWidget {
  final String branchId;
  const NotificationScreen({super.key, required this.branchId});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _markAllAsRead(); // Opsional: Tandai terbaca saat dibuka
  }

  // Menandai semua notifikasi sebagai terbaca saat layar dibuka
  Future<void> _markAllAsRead() async {
    final query = FirebaseFirestore.instance
        .collection('notifications')
        .where('to_branch', whereIn: [widget.branchId, 'all'])
        .where('is_read', isEqualTo: false);

    final snapshot = await query.get();
    final batch = FirebaseFirestore.instance.batch();

    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {'is_read': true});
    }
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pusat Notifikasi", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: "Pesan Masuk"),
            Tab(text: "Jatuh Tempo (H-3)"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNotificationList(),
          _buildDebtReminderList(),
        ],
      ),
    );
  }

  // --- TAB 1: LIST NOTIFIKASI UMUM ---
  Widget _buildNotificationList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('to_branch', whereIn: [widget.branchId, 'all'])
          .orderBy('date', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("Belum ada notifikasi baru"));
        }

        final docs = snapshot.data!.docs;
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (c, i) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;

            // [FIX CRASH] Safe parsing untuk Timestamp
            DateTime date;
            if (data['date'] != null) {
              date = (data['date'] as Timestamp).toDate();
            } else {
              date = DateTime.now();
            }

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue.shade50,
                child: const Icon(Icons.notifications, color: Colors.blue, size: 20),
              ),
              title: Text(data['title'] ?? 'Info', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data['message'] ?? '-', maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(DateFormat('dd MMM HH:mm').format(date), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
              isThreeLine: true,
            );
          },
        );
      },
    );
  }

  // --- TAB 2: LIST JATUH TEMPO (FIX ERROR NULL) ---
  Widget _buildDebtReminderList() {
    // Ambil utang yang belum lunas
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('debts')
          .where('branch_id', isEqualTo: widget.branchId == 'owner' ? 'pusat' : widget.branchId) // Sesuaikan logika owner
          .where('status', isEqualTo: 'unpaid')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData) return const Center(child: Text("Data tidak ditemukan"));

        // Filter Manual untuk H-3 di sisi Client (Lebih fleksibel)
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        final dueDebts = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;

          // [FIX CRASH DISINI] Handle jika created_at NULL
          Timestamp? ts = data['created_at'];
          DateTime createdAt = ts != null ? ts.toDate() : DateTime.now(); // Default ke NOW jika null

          DateTime dueDate = createdAt.add(const Duration(days: 30)); // Asumsi tempo 30 hari
          DateTime dueDateDate = DateTime(dueDate.year, dueDate.month, dueDate.day);

          int daysLeft = dueDateDate.difference(today).inDays;

          // Tampilkan jika H-3 sampai Terlewat (Minus)
          return daysLeft <= 3;
        }).toList();

        if (dueDebts.isEmpty) {
          return const Center(child: Text("Tidak ada tagihan yang mendekati jatuh tempo."));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: dueDebts.length,
          itemBuilder: (context, index) {
            final data = dueDebts[index].data() as Map<String, dynamic>;
            final debtId = dueDebts[index].id;

            // Parsing Ulang untuk Tampilan
            Timestamp? ts = data['created_at'];
            DateTime createdAt = ts != null ? ts.toDate() : DateTime.now();
            DateTime dueDate = createdAt.add(const Duration(days: 30));
            int daysLeft = DateTime(dueDate.year, dueDate.month, dueDate.day).difference(today).inDays;

            Color statusColor = daysLeft < 0 ? Colors.red : Colors.orange;
            String statusText = daysLeft < 0 ? "Telat ${daysLeft.abs()} Hari" : "$daysLeft Hari Lagi";

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 32),
                title: Text(data['name'] ?? 'Utang', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Nominal: Rp ${(data['amount'] ?? 0)}\nJatuh Tempo: ${DateFormat('dd MMM yyyy').format(dueDate)}"),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                onTap: () {
                  // Navigasi ke Detail Utang
                  Navigator.push(context, MaterialPageRoute(
                      builder: (c) => DebtListScreen(branchId: widget.branchId)
                  ));
                },
              ),
            );
          },
        );
      },
    );
  }
}