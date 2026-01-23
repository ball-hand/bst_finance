class WalletModel {
  final String id;
  final String name;
  final double balance;
  final String branchId;
  final bool isMain;

  WalletModel({
    required this.id,
    required this.name,
    required this.balance,
    required this.branchId,
    required this.isMain,
  });

  // Factory untuk mengubah data JSON (Firestore) jadi Object Dart
  factory WalletModel.fromMap(Map<String, dynamic> map, String id) {
    return WalletModel(
      id: id,
      name: map['name'] ?? 'Tanpa Nama',
      // Pastikan aman jika data di db tertulis int atau double
      balance: (map['balance'] ?? 0).toDouble(),
      branchId: map['branch_id'] ?? '',
      isMain: map['is_main'] ?? false,
    );
  }
}