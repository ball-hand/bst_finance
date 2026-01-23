import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // [FIX 1] Tambahkan ini agar NumberFormat jalan
import '../../../../models/transaction_model.dart';

class TransactionRepository {

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addTransaction(TransactionModel transaction) async {
    final walletRef = _firestore.collection('wallets').doc(transaction.walletId);

    return _firestore.runTransaction((tx) async {
      // 1. Ambil Saldo Terkini
      final walletSnap = await tx.get(walletRef);
      if (!walletSnap.exists) throw Exception("Dompet tidak ditemukan");

      double currentBalance = (walletSnap.get('balance') ?? 0).toDouble();
      double newBalance = 0;

      // 2. Hitung Saldo Baru
      if (transaction.type == 'expense') {
        if (currentBalance < transaction.amount) throw Exception("Saldo tidak cukup!");
        newBalance = currentBalance - transaction.amount;
      } else {
        newBalance = currentBalance + transaction.amount;
      }

      // 3. Update Saldo & Simpan Transaksi
      tx.update(walletRef, {'balance': newBalance});
      tx.set(_firestore.collection('transactions').doc(), transaction.toMap());

      // Cek Kas Kecil
      if (newBalance < 50000 && transaction.walletId != 'main_cash') {
        // Flagging logic if needed inside transaction
      }
    }).then((_) {
      // SETELAH TRANSAKSI SUKSES, BARU KIRIM NOTIF
      // [FIX] Tambahkan "?? 'pusat'" agar jika null, otomatis dianggap pusat
      _checkLowBalanceAfterTransaction(
          transaction.walletId,
          transaction.relatedBranchId ?? 'pusat'
      );
    });
  }

  Future<void> _checkLowBalanceAfterTransaction(String walletId, String branchId) async {
    try {
      final doc = await _firestore.collection('wallets').doc(walletId).get();
      double balance = (doc.data()?['balance'] ?? 0).toDouble();

      if (balance < 50000) {
        // Kirim Notif ke Admin Cabang itu sendiri (Peringatan)
        await _firestore.collection('notifications').add({
          'to_branch': branchId,
          'title': "⚠️ Kas Kecil Menipis!",
          'message': "Saldo dompet tersisa Rp ${NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(balance)}. Segera lakukan Top Up/Request Dana.",
          'type': 'alert_low_balance',
          'is_read': false,
          'date': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print("Gagal kirim notif low balance: $e");
    }
  }

  Stream<List<Map<String, dynamic>>> getUnpaidDebts() {
    return _firestore
        .collection('debts')
        .where('status', isEqualTo: 'unpaid') // Hanya yang belum lunas
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // Sertakan ID dokumen biar bisa dibayar nanti
        return data;
      }).toList();
    });
  }

  Future<void> topUpWallet({
    required String targetWalletId,
    required double amount,
    required String branchName, // Untuk deskripsi
  }) async {
    const String sourceWalletId = 'main_cash';

    final sourceRef = _firestore.collection('wallets').doc(sourceWalletId);
    final targetRef = _firestore.collection('wallets').doc(targetWalletId);
    final txRef = _firestore.collection('transactions').doc();

    return _firestore.runTransaction((tx) async {
      // A. Cek Saldo Pusat
      final sourceSnap = await tx.get(sourceRef);
      if (!sourceSnap.exists) throw Exception("Kas Pusat tidak ditemukan");
      double sourceBal = (sourceSnap.get('balance') ?? 0).toDouble();

      if (sourceBal < amount) {
        throw Exception("Saldo Kas Pusat tidak cukup untuk Top Up!");
      }

      // B. Ambil Saldo Target
      final targetSnap = await tx.get(targetRef);
      if (!targetSnap.exists) throw Exception("Dompet tujuan tidak ditemukan");
      double targetBal = (targetSnap.get('balance') ?? 0).toDouble();

      // C. EKSEKUSI PEMINDAHAN
      // 1. Kurangi Pusat
      tx.update(sourceRef, {'balance': sourceBal - amount});

      // 2. Tambah Cabang
      tx.update(targetRef, {'balance': targetBal + amount});

      // 3. Catat Transaksi
      tx.set(txRef, {
        'amount': amount,
        'type': 'income', // Masuk ke kas kecil
        'category': 'Top Up Kas',
        'description': 'Dana Operasional dari Pusat',
        'wallet_id': targetWalletId, // Masuk ke wallet ini
        'related_branch_id': 'pusat',
        'date': FieldValue.serverTimestamp(),
        'user_id': 'system_transfer',
      });
    });
  }



  Future<void> payEmployeeSalary({
    required String employeeId,
    required String employeeName,
    required String branchId,
    required double salary,
  }) async {
    const String walletIdSource = 'main_cash';
    final walletRef = _firestore.collection('wallets').doc(walletIdSource);
    final employeeRef = _firestore.collection('employees').doc(employeeId);
    final transactionRef = _firestore.collection('transactions').doc();

    return _firestore.runTransaction((tx) async {
      final walletSnap = await tx.get(walletRef);
      if (!walletSnap.exists) throw Exception("Kas Pusat tidak ditemukan!");
      final currentBalance = (walletSnap.get('balance') ?? 0).toDouble();

      if (currentBalance < salary) throw Exception("Saldo tidak cukup!");

      // Potong Saldo
      tx.update(walletRef, {'balance': currentBalance - salary});

      // Simpan Transaksi dengan TAGGING 'employee'
      tx.set(transactionRef, {
        'amount': salary,
        'type': 'expense',
        'category': 'Gaji Karyawan',
        'description': 'Gaji $employeeName',
        'wallet_id': walletIdSource,
        'related_branch_id': branchId,
        'date': FieldValue.serverTimestamp(),
        'user_id': 'system_payroll',

        // [PENTING] Kunci agar bisa dibatalkan nanti
        'related_id': employeeId,
        'related_type': 'employee',
        'deleted_at': null,
      });

      // Update Pegawai
      tx.update(employeeRef, {'last_paid_at': FieldValue.serverTimestamp()});
    });
  }
  // Mengambil transaksi berdasarkan rentang tanggal
  Future<List<TransactionModel>> getTransactionsByDateRange({
    required DateTime startDate,
    required DateTime endDate,
    String? type,
    String? branchId,
  }) async {
    DateTime start = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    DateTime end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    Query query = _firestore.collection('transactions')
        .where('date', isGreaterThanOrEqualTo: start)
        .where('date', isLessThanOrEqualTo: end)
        .where('deleted_at', isNull: true)
        .orderBy('date', descending: true);

    if (type != null && type != 'all') {
      query = query.where('type', isEqualTo: type);
    }
    if (branchId != null) {
      query = query.where('related_branch_id', isEqualTo: branchId);
    }

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => TransactionModel.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList();
  }
  Stream<QuerySnapshot> getDeletedTransactions() {
    return _firestore
        .collection('transactions')
        .where('deleted_at', isNull: false) // Cari yang ADA tanggal hapusnya
        .orderBy('deleted_at', descending: true)
        .snapshots();
  }
  Future<void> softDeleteTransaction(TransactionModel txData) async {
    final walletRef = _firestore.collection('wallets').doc(txData.walletId);
    final txRef = _firestore.collection('transactions').doc(txData.id);

    // Siapkan Ref untuk Employee / Debt jika ada
    DocumentReference? relatedRef;
    if (txData.relatedType == 'employee' && txData.relatedId != null) {
      relatedRef = _firestore.collection('employees').doc(txData.relatedId);
    } else if (txData.relatedType == 'debt_payment' && txData.relatedId != null) {
      relatedRef = _firestore.collection('debts').doc(txData.relatedId);
    }

    return _firestore.runTransaction((t) async {
      // --- LANGKAH 1: BACA SEMUA DATA DULU (READS) ---
      final walletSnap = await t.get(walletRef);
      if (!walletSnap.exists) throw Exception("Dompet tidak ditemukan");

      // Baca data terkait (Pegawai/Utang) jika ada
      DocumentSnapshot? relatedSnap;
      if (relatedRef != null) {
        relatedSnap = await t.get(relatedRef);
      }

      // --- LANGKAH 2: HITUNG LOGIKA (CALCULATIONS) ---

      // A. Hitung Saldo Dompet
      double currentBalance = (walletSnap.get('balance') ?? 0).toDouble();
      double newBalance = currentBalance;

      if (txData.type == 'expense') {
        newBalance += txData.amount; // Uang kembali ke dompet
      } else {
        newBalance -= txData.amount; // Uang ditarik
      }

      // --- LANGKAH 3: TULIS SEMUA DATA (WRITES) ---

      // A. Update Dompet
      t.update(walletRef, {'balance': newBalance});

      // B. Update Data Terkait (Pegawai/Utang)
      if (relatedSnap != null && relatedSnap.exists) {
        if (txData.relatedType == 'employee') {
          // Reset tanggal gajian jadi null (agar bisa digaji ulang)
          t.update(relatedRef!, {'last_paid_at': null});
        }
        else if (txData.relatedType == 'debt_payment') {
          // Kembalikan Nominal Utang
          double currentDebt = (relatedSnap.get('amount') ?? 0).toDouble();
          t.update(relatedRef!, {
            'amount': currentDebt + txData.amount, // Utang nambah lagi
            'status': 'unpaid' // Status jadi belum lunas
          });
        }
      }

      // C. Update Transaksi jadi Sampah
      t.update(txRef, {
        'deleted_at': FieldValue.serverTimestamp(),
        'description': "${txData.description} [DIBATALKAN]",
      });
    });
  }
  Future<void> deleteTransaction(String transactionId) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final txRef = _firestore.collection('transactions').doc(transactionId);
        final txSnapshot = await transaction.get(txRef);

        if (!txSnapshot.exists) throw Exception("Transaksi tidak ditemukan!");
        final data = txSnapshot.data()!;

        // Cek jika sudah dihapus
        if (data['deleted_at'] != null) return;

        final double amount = (data['amount'] ?? 0).toDouble();
        final String type = data['type'];
        final String? walletId = data['wallet_id'];

        // Update Saldo & Status
        if (walletId != null) {
          final walletRef = _firestore.collection('wallets').doc(walletId);
          final walletSnap = await transaction.get(walletRef);

          if (walletSnap.exists) {
            double currentBalance = (walletSnap.get('balance') ?? 0).toDouble();
            // REVERSE LOGIC (Hapus Pemasukan = Saldo Berkurang)
            if (type == 'income') currentBalance -= amount;
            else currentBalance += amount;

            transaction.update(walletRef, {'balance': currentBalance});
          }
        }

        // Soft Delete
        transaction.update(txRef, {
          'deleted_at': FieldValue.serverTimestamp(),
          'status': 'void',
        });
      });
    } catch (e) {
      throw Exception("Gagal menghapus: $e");
    }
  }
  // --- COPY DARI SINI ---

  // Method Restore Baru (Pakai String ID)
  Future<void> restoreTransaction(String transactionId) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final txRef = _firestore.collection('transactions').doc(transactionId);
        final txSnapshot = await transaction.get(txRef);

        if (!txSnapshot.exists) throw Exception("Transaksi tidak ditemukan!");
        final data = txSnapshot.data()!;

        // Cek jika belum dihapus (aktif), maka skip
        if (data['deleted_at'] == null) return;

        final double amount = (data['amount'] ?? 0).toDouble();
        final String type = data['type'];
        final String? walletId = data['wallet_id'];

        // Kembalikan Saldo (Restore Logic)
        if (walletId != null) {
          final walletRef = _firestore.collection('wallets').doc(walletId);
          final walletSnap = await transaction.get(walletRef);

          if (walletSnap.exists) {
            double currentBalance = (walletSnap.get('balance') ?? 0).toDouble();
            // RESTORE LOGIC (Balikin Pemasukan = Saldo Nambah lagi)
            if (type == 'income') currentBalance += amount;
            else currentBalance -= amount;

            transaction.update(walletRef, {'balance': currentBalance});
          }
        }

        // Hilangkan status deleted (Aktifkan lagi)
        transaction.update(txRef, {
          'deleted_at': null,
          'status': 'success',
        });
      });
    } catch (e) {
      throw Exception("Gagal restore: $e");
    }
  }

// --- SAMPAI SINI ---

}