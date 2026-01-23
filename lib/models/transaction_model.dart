import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionModel {
  final String id;
  final double amount;
  final String type; // 'income' atau 'expense'
  final String category;
  final String description;
  final String walletId;
  final DateTime date;
  final String userId;
  final String? relatedBranchId;

  // [FIELD BARU UNTUK FITUR DELETE & REVERSE]
  final DateTime? deletedAt; // Jika tidak null, berarti ada di trashbin
  final String? relatedId;   // ID Pegawai (jika gaji) atau ID Utang (jika bayar utang)
  final String? relatedType; // 'employee', 'debt_payment', 'general'

  TransactionModel({
    required this.id,
    required this.amount,
    required this.type,
    required this.category,
    required this.description,
    required this.walletId,
    required this.date,
    required this.userId,
    this.relatedBranchId,
    this.deletedAt,
    this.relatedId,
    this.relatedType,
  });

  Map<String, dynamic> toMap() {
    return {
      'amount': amount,
      'type': type,
      'category': category,
      'description': description,
      'wallet_id': walletId,
      'date': Timestamp.fromDate(date),
      'user_id': userId,
      'related_branch_id': relatedBranchId,
      'deleted_at': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null,
      'related_id': relatedId,
      'related_type': relatedType,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map, String id) {
    return TransactionModel(
      id: id,
      amount: (map['amount'] ?? 0).toDouble(),
      type: map['type'] ?? 'expense',
      category: map['category'] ?? 'Umum',
      description: map['description'] ?? '',
      walletId: map['wallet_id'] ?? '',
      date: (map['date'] as Timestamp).toDate(),
      userId: map['user_id'] ?? '',
      relatedBranchId: map['related_branch_id'],
      deletedAt: map['deleted_at'] != null ? (map['deleted_at'] as Timestamp).toDate() : null,
      relatedId: map['related_id'],
      relatedType: map['related_type'],
    );
  }
}