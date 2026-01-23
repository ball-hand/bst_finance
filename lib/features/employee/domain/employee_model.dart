import 'package:cloud_firestore/cloud_firestore.dart';

class EmployeeModel {
  final String id;
  final String name;
  final String position;    // Jabatan: Kasir, Staff, dll
  final String branchId;    // ID Database: m_alfa
  final String branchName;  // [BARU] Nama Layar: Cabang Alfamart
  final double baseSalary;
  final String phoneNumber; // [BARU] No WA
  final int paydayDate;
  final DateTime joinedDate; // [BARU] Tanggal Masuk
  final DateTime? lastPaidAt; // Kapan terakhir dibayar?

  EmployeeModel({
    required this.id,
    required this.name,
    required this.position,
    required this.branchId,
    required this.branchName,
    required this.baseSalary,
    required this.phoneNumber,
    required this.paydayDate,
    required this.joinedDate,
    this.lastPaidAt,
  });

  factory EmployeeModel.fromMap(Map<String, dynamic> map, String id) {
    return EmployeeModel(
      id: id,
      name: map['name'] ?? '',
      position: map['position'] ?? 'Staff',
      branchId: map['branch_id'] ?? 'bst_box',
      branchName: map['branch_name'] ?? 'Cabang',
      baseSalary: (map['base_salary'] ?? 0).toDouble(),
      phoneNumber: map['phone_number'] ?? '-',
      paydayDate: map['payday_date'] ?? 1,
      joinedDate: (map['joined_date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastPaidAt: map['last_paid_at'] != null
          ? (map['last_paid_at'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'position': position,
      'branch_id': branchId,
      'branch_name': branchName,
      'base_salary': baseSalary,
      'phone_number': phoneNumber,
      'payday_date': paydayDate,
      'joined_date': Timestamp.fromDate(joinedDate),
      'last_paid_at': lastPaidAt != null ? Timestamp.fromDate(lastPaidAt!) : null,
    };
  }

  // Helper: Cek apakah bulan ini sudah gajian?
  bool get isPaidThisMonth {
    if (lastPaidAt == null) return false;
    final now = DateTime.now();
    return lastPaidAt!.month == now.month && lastPaidAt!.year == now.year;
  }
}