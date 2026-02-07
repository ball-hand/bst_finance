import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../models/transaction_model.dart';

class TransactionRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ===============================================================
  // 1. TAMBAH TRANSAKSI BARU (ATOMIK & AMAN)
  // ===============================================================
  Future<void> addTransaction(TransactionModel transaction) async {
    final walletRef = _firestore.collection('wallets').doc(transaction.walletId);
    final transactionRef = _firestore.collection('transactions').doc();

    return _firestore.runTransaction((tx) async {
      final walletSnap = await tx.get(walletRef);
      if (!walletSnap.exists) {
        throw Exception("Dompet tujuan (ID: ${transaction.walletId}) tidak ditemukan!");
      }

      double currentBalance = (walletSnap.get('balance') ?? 0).toDouble();
      double newBalance = 0;

      if (transaction.type == 'expense') {
        if (currentBalance < transaction.amount) {
          final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
          throw Exception("Saldo tidak cukup! Sisa: ${currency.format(currentBalance)}");
        }
        newBalance = currentBalance - transaction.amount;
      } else {
        newBalance = currentBalance + transaction.amount;
      }

      tx.update(walletRef, {'balance': newBalance});

      final docId = transaction.id.isEmpty ? transactionRef.id : transaction.id;
      final docRef = _firestore.collection('transactions').doc(docId);

      tx.set(docRef, transaction.toMap());
    }).catchError((error) {
      throw error;
    });
  }

  // ===============================================================
  // 2. SOFT DELETE (REVERSE SALDO)
  // ===============================================================
  Future<void> deleteTransaction(String transactionId) async {
    return _firestore.runTransaction((tx) async {
      final txRef = _firestore.collection('transactions').doc(transactionId);
      final txSnap = await tx.get(txRef);

      if (!txSnap.exists) throw Exception("Transaksi tidak ditemukan!");

      final data = txSnap.data()!;
      if (data['deleted_at'] != null) return;

      final double amount = (data['amount'] ?? 0).toDouble();
      final String type = data['type'];
      final String walletId = data['wallet_id'];

      final walletRef = _firestore.collection('wallets').doc(walletId);
      final walletSnap = await tx.get(walletRef);

      if (walletSnap.exists) {
        double currentBalance = (walletSnap.get('balance') ?? 0).toDouble();

        if (type == 'income') {
          tx.update(walletRef, {'balance': currentBalance - amount});
        } else {
          tx.update(walletRef, {'balance': currentBalance + amount});
        }
      }

      tx.update(txRef, {
        'deleted_at': FieldValue.serverTimestamp(),
        'status': 'deleted'
      });
    });
  }

  // ===============================================================
  // 3. RESTORE (PULIHKAN DARI SAMPAH)
  // ===============================================================
  Future<void> restoreTransaction(String transactionId) async {
    return _firestore.runTransaction((tx) async {
      final txRef = _firestore.collection('transactions').doc(transactionId);
      final txSnap = await tx.get(txRef);

      if (!txSnap.exists) throw Exception("Transaksi tidak ditemukan!");
      final data = txSnap.data()!;

      if (data['deleted_at'] == null) return;

      final double amount = (data['amount'] ?? 0).toDouble();
      final String type = data['type'];
      final String walletId = data['wallet_id'];

      final walletRef = _firestore.collection('wallets').doc(walletId);
      final walletSnap = await tx.get(walletRef);

      if (walletSnap.exists) {
        double currentBalance = (walletSnap.get('balance') ?? 0).toDouble();

        if (type == 'income') {
          tx.update(walletRef, {'balance': currentBalance + amount});
        } else {
          if (currentBalance < amount) {
            final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
            throw Exception("Gagal Restore! Saldo saat ini (${currency.format(currentBalance)}) tidak cukup.");
          }
          tx.update(walletRef, {'balance': currentBalance - amount});
        }
      }

      tx.update(txRef, {
        'deleted_at': null,
        'status': 'active'
      });
    });
  }

  // ===============================================================
  // 4. GET DATA STREAMS
  // ===============================================================
  Stream<QuerySnapshot> getTransactionStream() {
    return _firestore
        .collection('transactions')
        .where('deleted_at', isNull: true)
        .orderBy('date', descending: true)
        .limit(50)
        .snapshots();
  }

  Stream<QuerySnapshot> getDeletedTransactions() {
    return _firestore
        .collection('transactions')
        .where('deleted_at', isNull: false)
        .orderBy('deleted_at', descending: true)
        .snapshots();
  }

  // ===============================================================
  // 5. [FIXED] GET BY DATE RANGE (Sesuai parameter UI Anda)
  // ===============================================================
  Future<List<TransactionModel>> getTransactionsByDateRange({
    required DateTime startDate,
    required DateTime endDate,
    String? branchId, // Opsional
    String? type,     // Opsional (income/expense)
  }) async {
    // 1. Setup Tanggal (Full Day)
    final start = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    // 2. Query Dasar
    Query query = _firestore
        .collection('transactions')
        .where('deleted_at', isNull: true) // Hanya ambil yg aktif
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end));

    // 3. Filter Cabang (Jika diminta & bukan 'semua')
    if (branchId != null && branchId != 'all' && branchId != 'pusat') {
      // Jika user minta spesifik cabang, filter by related_branch_id
      query = query.where('related_branch_id', isEqualTo: branchId);
    }

    // 4. Filter Tipe (Income/Expense)
    if (type != null && type != 'all') {
      query = query.where('type', isEqualTo: type);
    }

    // 5. Eksekusi
    // Note: Jika pakai banyak filter 'where', Firestore mungkin minta Index.
    // Cek Debug Console jika tidak muncul data (klik link index creation).
    final snapshot = await query.orderBy('date', descending: true).get();

    return snapshot.docs.map((doc) {
      return TransactionModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    }).toList();
  }
}