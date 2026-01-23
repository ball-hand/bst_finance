import 'package:cloud_firestore/cloud_firestore.dart';

class DebtModel {
  final String id;
  final String name;       // Nama Pemberi Utang / Supplier
  final double amount;
  final String branchId;
  final String note;
  final String status;     // 'paid' or 'unpaid'
  final DateTime createdAt;
  final String type;       // 'payable' (Utang Kita) or 'receivable' (Piutang)

  // [FIELD BARU]
  final String? bankName;      // BCA, Mandiri, dll
  final String? accountNumber; // 1234567890

  DebtModel({
    required this.id,
    required this.name,
    required this.amount,
    required this.branchId,
    required this.note,
    required this.status,
    required this.createdAt,
    required this.type,
    this.bankName,
    this.accountNumber,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'amount': amount,
      'branch_id': branchId,
      'note': note,
      'status': status,
      'created_at': Timestamp.fromDate(createdAt),
      'type': type,
      'bank_name': bankName,
      'account_number': accountNumber,
    };
  }

  factory DebtModel.fromMap(Map<String, dynamic> map, String id) {
    return DebtModel(
      id: id,
      name: map['name'] ?? 'Tanpa Nama',
      amount: (map['amount'] ?? 0).toDouble(),
      branchId: map['branch_id'] ?? '',
      note: map['note'] ?? '',
      status: map['status'] ?? 'unpaid',
      createdAt: (map['created_at'] as Timestamp).toDate(),
      type: map['type'] ?? 'payable',
      bankName: map['bank_name'],
      accountNumber: map['account_number'],
    );
  }
}