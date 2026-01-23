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

    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
                color: Colors.grey.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2)
            )
          ]
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
          transaction.description.isNotEmpty ? transaction.description : transaction.category,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (transaction.description.isNotEmpty && transaction.description != transaction.category)
              Text(transaction.category, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            Text(
              DateFormat('dd MMM yyyy, HH:mm').format(transaction.date),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              NumberFormat.currency(locale: 'id_ID', symbol: isExpense ? '- ' : '+ ', decimalDigits: 0)
                  .format(transaction.amount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isExpense ? AppColors.error : AppColors.success,
                fontSize: 14,
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: Colors.grey)
          ],
        ),
      ),
    );
  }
}