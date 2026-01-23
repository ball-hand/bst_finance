import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/wallet_model.dart';
import '../../../models/transaction_model.dart';

class WalletDetailScreen extends StatelessWidget {
  final WalletModel wallet;

  const WalletDetailScreen({super.key, required this.wallet});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Rincian Dompet", style: TextStyle(fontSize: 14, color: Colors.black54)),
            Text(wallet.name, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          // HEADER SALDO
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            color: Colors.grey[50],
            child: Column(
              children: [
                const Text("Saldo Saat Ini", style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Text(
                  NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(wallet.balance),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // LIST MUTASI TRANSAKSI
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('transactions')
                  .where('wallet_id', isEqualTo: wallet.id) // Filter Khusus Dompet Ini
                  .orderBy('date', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) return const Center(child: Text("Belum ada mutasi dana."));

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final tx = TransactionModel.fromMap(docs[index].data() as Map<String, dynamic>, docs[index].id);
                    bool isIncome = tx.type == 'income';

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: isIncome ? AppColors.greenSoft : AppColors.redSoft,
                        child: Icon(
                          isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                          color: isIncome ? AppColors.success : AppColors.error,
                          size: 20,
                        ),
                      ),
                      title: Text(tx.description.isNotEmpty ? tx.description : tx.category, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(DateFormat('dd MMM yyyy, HH:mm').format(tx.date)),
                      trailing: Text(
                        (isIncome ? "+ " : "- ") + NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(tx.amount),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isIncome ? AppColors.success : AppColors.error,
                            fontSize: 15
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          )
        ],
      ),
    );
  }
}