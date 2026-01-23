import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../models/request_model.dart';

class RequestRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<QuerySnapshot> getPendingRequests() {
    return _firestore
        .collection('requests')
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  Future<void> createRequest(RequestModel request) async {
    await _firestore.collection('requests').add(request.toMap());

    await _sendNotification(
        toBranch: 'owner',
        title: "Permintaan Dana Baru",
        message: "${request.requesterName} meminta dana untuk: ${request.description} sebesar Rp ${NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(request.amount)}",
        type: 'request_new'
    );
  }
  Future<void> _sendNotification({
    required String toBranch,
    required String title,
    required String message,
    required String type,
  }) async {
    await _firestore.collection('notifications').add({
      'to_branch': toBranch, // Field ini yang akan dicari oleh HP Owner
      'title': title,
      'message': message,
      'type': type,
      'is_read': false,
      'date': FieldValue.serverTimestamp(),
    });
  }


  // --- FUNGSI APPROVE REQUEST (LENGKAP) ---
  Future<void> approveRequest({
    required String requestId,
    required double requestedAmount,
    required double approvedAmount, // Nominal yang disetujui Owner
    required String category,
    required String description,
    required String requesterName,
    required String requestType,    // 'repayment' atau 'expense'
    String? relatedDebtId,          // ID Utang (jika tipe repayment)
  }) async {
    final walletRef = _firestore.collection('wallets').doc('main_cash');
    final requestRef = _firestore.collection('requests').doc(requestId);

    // 1. Ekstrak Branch ID dari nama requester (Contoh: "Admin bst_box" -> "bst_box")
    String relatedBranchId = 'pusat';
    if (requesterName.contains('Admin ')) {
      relatedBranchId = requesterName.replaceAll('Admin ', '').trim();
    }

    await _firestore.runTransaction((tx) async {
      // 2. Cek Saldo Pusat
      final walletSnap = await tx.get(walletRef);
      if (!walletSnap.exists) throw Exception("Kas Pusat tidak ditemukan");
      double currentBalance = (walletSnap.get('balance') ?? 0).toDouble();

      if (currentBalance < approvedAmount) {
        throw Exception("Saldo Kas Pusat tidak cukup!");
      }

      // 3. Potong Saldo Pusat (Uang Keluar)
      tx.update(walletRef, {'balance': currentBalance - approvedAmount});

      // 4. Update Status Request jadi Approved
      tx.update(requestRef, {
        'status': 'approved',
        'approved_amount': approvedAmount,
      });

      // 5. Catat Transaksi Pengeluaran di History
      final newTxRef = _firestore.collection('transactions').doc();
      tx.set(newTxRef, {
        'amount': approvedAmount,
        'type': 'expense',
        'category': category,
        'description': "$description (Approved)",
        'wallet_id': 'main_cash',
        'related_branch_id': relatedBranchId,
        'date': FieldValue.serverTimestamp(),
        'user_id': 'owner_approval',
      });

      // --- LOGIKA UTAMA (PERCABANGAN) ---

      if (requestType == 'repayment' && relatedDebtId != null) {
        // === SKENARIO A: PELUNASAN UTANG ===
        // Kurangi Utang Lama. JANGAN buat utang baru.

        final debtRef = _firestore.collection('debts').doc(relatedDebtId);
        final debtSnap = await tx.get(debtRef);

        if (debtSnap.exists) {
          double currentDebtAmount = (debtSnap.get('amount') ?? 0).toDouble();

          // Kurangi utang dengan nominal yang DISETUJUI owner
          double newDebtAmount = currentDebtAmount - approvedAmount;

          // Pastikan tidak minus (jaga-jaga)
          if (newDebtAmount < 0) newDebtAmount = 0;

          tx.update(debtRef, {
            'amount': newDebtAmount,
            // Jika sisa 0 -> Lunas (paid), Jika sisa > 0 -> Belum Lunas (unpaid)
            'status': newDebtAmount == 0 ? 'paid' : 'unpaid',
          });
        }

      } else {
        // === SKENARIO B: PERMINTAAN DANA BIASA (EXPENSE) ===
        // Jika uang yang dikasih kurang dari permintaan, sisanya jadi UTANG BARU.

        double gap = requestedAmount - approvedAmount;
        if (gap > 0) {
          // Update request untuk simpan info gap
          tx.update(requestRef, {'debt_amount': gap});

          // Buat Utang Baru
          final debtRef = _firestore.collection('debts').doc();
          tx.set(debtRef, {
            'branch_id': relatedBranchId,
            'amount': gap, // Sisa yang tidak dikasih jadi utang
            'description': "Sisa request: $description",
            'original_request_id': requestId,
            'date': FieldValue.serverTimestamp(),
            'status': 'unpaid',
          });
        }
      }
    });

    // 6. KIRIM NOTIFIKASI KE CABANG
    // (Kode ini berjalan SETELAH transaksi sukses)
    await _sendNotification(
        toBranch: relatedBranchId,
        title: "Permintaan Disetujui",
        message: "Request '$description' senilai Rp ${NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0).format(approvedAmount)} telah disetujui.",
        type: 'approval_approved'
    );
  }


  Future<void> rejectRequest(String requestId, String branchId, String description) async {
    await _firestore.collection('requests').doc(requestId).update({'status': 'rejected'});

    // Kirim Notifikasi
    await _sendNotification(
        toBranch: branchId,
        title: "Permintaan Ditolak",
        message: "Request $description tidak disetujui oleh Owner.",
        type: 'approval_rejected'
    );
  }
}