import 'package:cloud_firestore/cloud_firestore.dart';

class DebtRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 1. TAMBAH UTANG MANUAL
  Future<void> addDebt({
    required String name,
    required double amount,
    required String branchId,
    required String note,
  }) async {
    await _firestore.collection('debts').add({
      'name': name,
      'amount': amount,
      'branch_id': branchId,
      'note': note,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  // 2. BAYAR UTANG (CICIL / LUNAS)
  Future<void> payDebt({
    required String debtId,
    required String debtName,
    required double payAmount,
    required double currentDebtAmount,
    required String branchId,
  }) async {
    // Pelunasan utang selalu ambil dari KAS PUSAT
    const String sourceWalletId = 'main_cash';

    final walletRef = _firestore.collection('wallets').doc(sourceWalletId);
    final debtRef = _firestore.collection('debts').doc(debtId);
    final txRef = _firestore.collection('transactions').doc();

    return _firestore.runTransaction((tx) async {
      // A. Cek Saldo Pusat Cukup Gak?
      final walletSnap = await tx.get(walletRef);
      if (!walletSnap.exists) throw Exception("Kas Pusat tidak ditemukan");

      final currentBalance = (walletSnap.get('balance') ?? 0).toDouble();
      if (currentBalance < payAmount) {
        throw Exception("Saldo Kas Pusat tidak cukup untuk membayar utang ini!");
      }

      // B. Update Saldo Pusat (Berkurang)
      tx.update(walletRef, {'balance': currentBalance - payAmount});

      // C. Update Utang
      double sisaUtang = currentDebtAmount - payAmount;
      if (sisaUtang <= 100) { // Toleransi receh, anggap lunas
        tx.delete(debtRef); // Hapus data utang
      } else {
        tx.update(debtRef, {'amount': sisaUtang}); // Update sisa
      }

      // D. Catat Transaksi Pengeluaran
      tx.set(txRef, {
        'amount': payAmount,
        'type': 'expense',
        'category': 'Pelunasan Utang',
        'description': 'Bayar $debtName ($branchId)',
        'wallet_id': sourceWalletId,
        'related_branch_id': branchId,
        'date': FieldValue.serverTimestamp(),
        'user_id': 'system_debt_pay',
      });
    });
  }
}