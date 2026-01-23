import 'package:cloud_firestore/cloud_firestore.dart';

class EmployeeModel {
  final String id;
  final String name;
  final String branchId; // 'bst_box', 'm_alfa', 'saufa'
  final double salary;
  final int payDate; // Tanggal gajian (misal: 4, 18, 25)
  final DateTime? lastPaidAt; // Kapan terakhir dibayar?

  EmployeeModel({
    required this.id,
    required this.name,
    required this.branchId,
    required this.salary,
    required this.payDate,
    this.lastPaidAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'branch_id': branchId,
      'salary': salary,
      'pay_date': payDate,
      'last_paid_at': lastPaidAt != null ? Timestamp.fromDate(lastPaidAt!) : null,
    };
  }

  factory EmployeeModel.fromMap(Map<String, dynamic> map, String id) {
    return EmployeeModel(
      id: id,
      name: map['name'] ?? '',
      branchId: map['branch_id'] ?? 'bst_box',
      salary: (map['salary'] ?? 0).toDouble(),
      payDate: map['pay_date'] ?? 1,
      lastPaidAt: map['last_paid_at'] != null
          ? (map['last_paid_at'] as Timestamp).toDate()
          : null,
    );
  }

  // --- LOGIKA STATUS GAJI ---
  // Cek apakah bulan ini sudah dibayar?
  bool get isPaidThisMonth {
    if (lastPaidAt == null) return false;
    final now = DateTime.now();
    return lastPaidAt!.month == now.month && lastPaidAt!.year == now.year;
  }

  // Cek apakah telat bayar? (Belum bayar DAN tanggal sekarang > tanggal gajian)
  bool get isLate {
    if (isPaidThisMonth) return false;
    final now = DateTime.now();
    return now.day > payDate;
  }

  // Hitung berapa hari telatnya
  int get daysLate {
    if (!isLate) return 0;
    return DateTime.now().day - payDate;
  }
}