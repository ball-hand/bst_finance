import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../models/transaction_model.dart';
import '../../../../core/constants/app_colors.dart';

class TransactionCard extends StatelessWidget {
  final TransactionModel transaction;

  const TransactionCard({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isExpense = transaction.type == 'expense';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isExpense ? AppColors.error.withOpacity(0.1) : AppColors.success.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isExpense ? Icons.arrow_downward : Icons.arrow_upward,
            color: isExpense ? AppColors.error : AppColors.success,
            size: 20,
          ),
        ),
        title: Text(
          transaction.category,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(transaction.description, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              DateFormat('dd MMM yyyy, HH:mm').format(transaction.date),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: Text(
          NumberFormat.currency(locale: 'id_ID', symbol: isExpense ? '-Rp ' : '+Rp ', decimalDigits: 0)
              .format(transaction.amount),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isExpense ? AppColors.error : AppColors.success,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}