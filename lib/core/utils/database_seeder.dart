import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

class DatabaseSeeder {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Random _rnd = Random();

  // --- 1. FITUR RESET DATA (BERSIH-BERSIH) ---
  Future<void> clearAllData() async {
    try {
      await _deleteCollection('transactions');
      await _deleteCollection('debts');
      await _deleteCollection('requests');
      await _deleteCollection('notifications');
      await _deleteCollection('employees');

      // RESET Semua Saldo Dompet ke 0
      final wallets = await _db.collection('wallets').get();
      WriteBatch batch = _db.batch();
      for (var doc in wallets.docs) {
        batch.update(doc.reference, {'balance': 0});
      }
      await batch.commit();

      print("✅ DATABASE BERHASIL DI-RESET BERSIH!");
    } catch (e) {
      throw Exception("Gagal Reset Data: $e");
    }
  }

  // --- 2. GENERATE DUMMY DATA (VERSI TERBARU) ---
  Future<void> seedDummyData() async {
    try {
      final user = _auth.currentUser;
      String uid = user?.uid ?? 'dummy_user';
      WriteBatch batch = _db.batch();
      int batchCount = 0;

      Future<void> checkBatch() async {
        batchCount++;
        if (batchCount >= 450) {
          await batch.commit();
          batch = _db.batch();
          batchCount = 0;
        }
      }

      // --- A. DATA CABANG & DOMPET (PASTIKAN ID SESUAI) ---
      // Mapping ID Cabang -> ID Dompet (PENTING AGAR TOMBOL TOPUP MUNCUL)
      List<Map<String, String>> branches = [
        {'id': 'pusat', 'name': 'Kantor Pusat', 'wallet': 'main_cash'},
        {'id': 'bst_box', 'name': 'Box Factory', 'wallet': 'petty_bst'}, // ID wallet diperbaiki
        {'id': 'm_alfa', 'name': 'Maint. Alfa', 'wallet': 'petty_alfa'},
        {'id': 'saufa', 'name': 'Saufa Olshop', 'wallet': 'petty_saufa'},
      ];

      // Set Saldo Awal
      for (var b in branches) {
        double modal = b['id'] == 'pusat' ? 500000000 : 10000000; // Pusat 500jt, Cabang 10jt
        batch.set(_db.collection('wallets').doc(b['wallet']), {
          'balance': modal,
          'name': b['id'] == 'pusat' ? 'Kas Pusat' : 'Kas Kecil ${b['name']}',
          'branch_id': b['id'],
          'is_main': b['id'] == 'pusat',
          'updated_at': FieldValue.serverTimestamp(),
        });
        await checkBatch();
      }

      // --- B. PEGAWAI (EMPLOYEES) ---
      List<String> names = ['Budi Santoso', 'Siti Aminah', 'Rudi Hartono', 'Dewi Persik', 'Joko Anwar', 'Andi Saputra', 'Rina Wati', 'Eko Prasetyo', 'Sari Indah', 'Dedi Kurniawan'];
      List<String> positions = ['Staff', 'Kasir', 'Teknisi', 'Sales', 'Admin'];

      for (int i = 0; i < names.length; i++) {
        var branch = branches[_rnd.nextInt(branches.length)];
        String empId = _db.collection('employees').doc().id;

        batch.set(_db.collection('employees').doc(empId), {
          'name': names[i],
          'position': positions[_rnd.nextInt(positions.length)],
          'branch_id': branch['id'],
          'branch_name': branch['name'],
          'base_salary': 3000000 + (_rnd.nextInt(10) * 500000),
          'phone_number': '0812${_rnd.nextInt(99999999)}',
          'joined_date': DateTime.now().subtract(Duration(days: _rnd.nextInt(1000))),
        });
        await checkBatch();
      }

      // --- C. TRANSAKSI (30 HARI TERAKHIR) ---
      DateTime now = DateTime.now();
      for (int i = 30; i >= 0; i--) {
        DateTime txDate = now.subtract(Duration(days: i));

        for (var b in branches) {
          if (b['id'] == 'pusat') continue;

          // 1. Pemasukan (Sales)
          if (_rnd.nextInt(10) > 1) {
            double income = (5 + _rnd.nextInt(45)) * 100000;
            String txId = _db.collection('transactions').doc().id;
            batch.set(_db.collection('transactions').doc(txId), {
              'amount': income,
              'type': 'income',
              'category': 'Penjualan',
              'description': 'Omzet Harian ${b['name']}',
              'wallet_id': b['wallet'],
              'related_branch_id': b['id'],
              'date': txDate.add(Duration(hours: 10 + _rnd.nextInt(8))),
              'user_id': uid,
              'deleted_at': null,
            });
            await checkBatch();
          }

          // 2. Pengeluaran Kecil
          if (_rnd.nextBool()) {
            double expense = (2 + _rnd.nextInt(15)) * 10000;
            String txId = _db.collection('transactions').doc().id;
            batch.set(_db.collection('transactions').doc(txId), {
              'amount': expense,
              'type': 'expense',
              'category': _rnd.nextBool() ? 'Konsumsi' : 'Transportasi',
              'description': 'Biaya Ops Harian',
              'wallet_id': b['wallet'],
              'related_branch_id': b['id'],
              'date': txDate.add(Duration(hours: 12 + _rnd.nextInt(5))),
              'user_id': uid,
              'deleted_at': null,
            });
            await checkBatch();
          }
        }
      }

      // --- D. UTANG (DEBTS) - UPDATE BESAR ---
      // Tipe 1: Utang Vendor (Manual) -> Masuk Tab 1
      List<String> vendors = ['Supplier Kertas', 'Toko Bangunan Jaya', 'Vendor IT', 'Catering Bu Ani'];
      List<String> banks = ['BCA', 'BRI', 'Mandiri', 'BNI'];

      for (int i = 0; i < 5; i++) {
        var b = branches[1 + _rnd.nextInt(3)]; // Cabang acak
        String debtId = _db.collection('debts').doc().id;
        bool isPaid = _rnd.nextBool();

        batch.set(_db.collection('debts').doc(debtId), {
          'name': vendors[_rnd.nextInt(vendors.length)],
          'amount': (10 + _rnd.nextInt(90)) * 50000,
          'branch_id': b['id'],
          'note': 'Jatuh tempo minggu depan',
          'status': isPaid ? 'paid' : 'unpaid',
          'created_at': DateTime.now().subtract(Duration(days: _rnd.nextInt(10))),
          'type': 'payable',

          // FIELD BARU UTANG MANUAL
          'source': 'manual',
          'bank_name': banks[_rnd.nextInt(banks.length)],
          'account_number': '${_rnd.nextInt(999999999)}',
        });
        await checkBatch();
      }

      // Tipe 2: Sisa Approval (Otomatis) -> Masuk Tab 2
      for (int i = 0; i < 3; i++) {
        var b = branches[1 + _rnd.nextInt(3)];
        String debtId = _db.collection('debts').doc().id;
        double sisa = (5 + _rnd.nextInt(20)) * 10000;

        batch.set(_db.collection('debts').doc(debtId), {
          'name': "Sisa Approval: Belanja Alat",
          'amount': sisa,
          'branch_id': b['id'],
          'note': 'Total minta 1jt, cair 500rb',
          'status': 'unpaid',
          'created_at': DateTime.now().subtract(Duration(days: _rnd.nextInt(5))),
          'type': 'payable',

          // FIELD BARU UTANG APPROVAL
          'source': 'approval',
          'bank_name': null, // Approval biasanya tidak ada bank di sini
          'account_number': null,
        });
        await checkBatch();
      }

      // --- E. APPROVAL REQUESTS ---
      List<String> items = ['Servis AC', 'Beli Kertas', 'Ganti Oli Mobil', 'Pulsa Modem'];
      for (int i = 0; i < 8; i++) {
        var b = branches[1 + _rnd.nextInt(3)];
        String status = ['pending', 'approved', 'rejected'][_rnd.nextInt(3)];
        double amount = (2 + _rnd.nextInt(10)) * 100000;

        String reqId = _db.collection('requests').doc().id;
        batch.set(_db.collection('requests').doc(reqId), {
          'branch_id': b['id'],
          'branch_name': b['name'],
          'requester_id': uid,
          'item_name': items[_rnd.nextInt(items.length)],
          'amount': amount,
          'category': 'Operasional',
          'note': 'Segera butuh',
          'status': status,
          'created_at': DateTime.now().subtract(Duration(days: _rnd.nextInt(7))),
          'approved_amount': status == 'approved' ? amount : 0,
        });
        await checkBatch();
      }

      await batch.commit();
      print("✅ MEGA SEEDER V3 SELESAI!");

    } catch (e) {
      throw Exception("Gagal Seed Dummy: $e");
    }
  }

  Future<void> _deleteCollection(String colName) async {
    final snapshot = await _db.collection(colName).get();
    if (snapshot.docs.isEmpty) return;
    WriteBatch batch = _db.batch();
    int count = 0;
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
      count++;
      if (count >= 400) {
        await batch.commit();
        batch = _db.batch();
        count = 0;
      }
    }
    await batch.commit();
  }
}