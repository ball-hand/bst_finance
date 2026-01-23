import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../models/transaction_model.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../../core/constants/app_colors.dart';

class TrashbinScreen extends StatelessWidget {
  const TrashbinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sampah (Trashbin)", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: TransactionRepository().getDeletedTransactions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text("Trashbin Kosong", style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (c, i) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final tx = TransactionModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);

              return _buildDeletedCard(context, tx);
            },
          );
        },
      ),
    );
  }

  Widget _buildDeletedCard(BuildContext context, TransactionModel tx) {
    bool isExpense = tx.type == 'expense';

    return Card(
      color: Colors.grey[100], // Warna abu menandakan non-aktif
      child: ListTile(
        leading: const Icon(Icons.delete_sweep, color: Colors.grey),
        title: Text(
            tx.description.replaceAll(' [DIBATALKAN]', ''),
            style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey)
        ),
        subtitle: Text(
          "Dihapus: ${tx.deletedAt != null ? DateFormat('dd MMM HH:mm').format(tx.deletedAt!) : '-'}",
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(tx.amount),
              style: const TextStyle(color: Colors.grey, decoration: TextDecoration.lineThrough),
            ),
            const SizedBox(width: 8),

            // TOMBOL RESTORE
            IconButton(
              icon: const Icon(Icons.restore, color: AppColors.primary),
              tooltip: "Pulihkan Data",
              onPressed: () => _confirmRestore(context, tx),
            )
          ],
        ),
      ),
    );
  }

  void _confirmRestore(BuildContext context, TransactionModel tx) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Pulihkan Transaksi?"),
        content: const Text("Transaksi akan dikembalikan ke Laporan Keuangan. Saldo dompet akan disesuaikan kembali."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await TransactionRepository().restoreTransaction(tx.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Berhasil dipulihkan!")));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e")));
                }
              }
            },
            child: const Text("Pulihkan"),
          )
        ],
      ),
    );
  }
}