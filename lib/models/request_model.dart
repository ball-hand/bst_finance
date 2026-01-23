import 'package:cloud_firestore/cloud_firestore.dart';

class RequestModel {
  final String id;
  final double amount;
  final String type; // 'income' atau 'expense'
  final String category;
  final String description;
  final String walletId; // Dompet asal request (misal Petty Cash BST)
  final String status; // 'pending', 'approved', 'rejected'
  final DateTime date;
  final String requesterName; // Siapa yang minta

  RequestModel({
    required this.id,
    required this.amount,
    required this.type,
    required this.category,
    required this.description,
    required this.walletId,
    required this.status,
    required this.date,
    required this.requesterName,
  });

  Map<String, dynamic> toMap() {
    return {
      'amount': amount,
      'type': type,
      'category': category,
      'description': description,
      'wallet_id': walletId,
      'status': status,
      'date': Timestamp.fromDate(date),
      'requester_name': requesterName,
    };
  }

  factory RequestModel.fromMap(Map<String, dynamic> map, String id) {
    return RequestModel(
      id: id,
      amount: (map['amount'] ?? 0).toDouble(),
      type: map['type'] ?? 'expense',
      category: map['category'] ?? '',
      description: map['description'] ?? '',
      walletId: map['wallet_id'] ?? '',
      status: map['status'] ?? 'pending',
      date: (map['date'] as Timestamp).toDate(),
      requesterName: map['requester_name'] ?? 'Admin',
    );
  }
}