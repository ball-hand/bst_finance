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
      print("⏳ Sedang menghapus data lama...");
      await _deleteCollection('transactions');
      await _deleteCollection('debts');
      await _deleteCollection('requests');
      await _deleteCollection('notifications');
      await _deleteCollection('employees');

      // KITA HAPUS WALLETS JUGA AGAR DIBUAT ULANG DENGAN STRUKTUR BARU
      await _deleteCollection('wallets');

      print("✅ DATABASE BERHASIL DI-RESET BERSIH!");
    } catch (e) {
      throw Exception("Gagal Reset Data: $e");
    }
  }

  // --- 2. GENERATE DUMMY DATA (STRUKTUR 5 WALLET) ---
  Future<void> seedDummyData() async {
    try {
      final user = _auth.currentUser;
      String uid = user?.uid ?? 'dummy_user';
      WriteBatch batch = _db.batch();
      int batchCount = 0;

      // Helper untuk commit batch jika sudah penuh (limit 500)
      Future<void> checkBatch() async {
        batchCount++;
        if (batchCount >= 450) {
          await batch.commit();
          batch = _db.batch();
          batchCount = 0;
        }
      }

      print("🌱 Memulai Seeding Data Baru...");

      // ==========================================
      // A. BUAT 5 WALLET BAKU (HIERARKI KEUANGAN)
      // ==========================================

      // LEVEL 1: Uang Perusahaan (Penampung Pemasukan)
      // Kita kasih saldo awal besar biar enak dilihat
      batch.set(_db.collection('wallets').doc('company_wallet'), {
        'name': 'Uang Perusahaan (Main)',
        'branch_id': 'pusat',
        'balance': 500000000, // 500 Juta
        'level': 1,
        'is_active': true,
        'description': 'Semua pemasukan masuk ke sini'
      });

      // LEVEL 2: Kas Bendahara Pusat (Eksekutor Utama)
      batch.set(_db.collection('wallets').doc('treasurer_wallet'), {
        'name': 'Kas Bendahara Pusat',
        'branch_id': 'pusat',
        'balance': 150000000, // 150 Juta (Modal Awal)
        'level': 2,
        'is_active': true,
        'description': 'Untuk belanja perusahaan & topup cabang'
      });

      // LEVEL 3: Kas Harian Cabang (Operasional Receh)
      List<String> branchIds = ['bst_box', 'm_alfa', 'saufa'];
      Map<String, String> walletMap = {
        'bst_box': 'petty_box',
        'm_alfa': 'petty_alfa',
        'saufa': 'petty_saufa'
      };

      for (var branch in branchIds) {
        batch.set(_db.collection('wallets').doc(walletMap[branch]), {
          'name': 'Kas Harian ${branch.replaceAll('_', ' ').toUpperCase()}',
          'branch_id': branch,
          'balance': 5000000, // 5 Juta (Modal Harian)
          'level': 3,
          'is_active': true,
          'description': 'Khusus pengeluaran kategori Harian'
        });
      }
      await checkBatch();


      // ==========================================
      // B. DATA PEGAWAI (EMPLOYEES)
      // ==========================================
      List<String> positions = ['Staff', 'Operator', 'Sales', 'Admin'];
      for (int i = 0; i < 15; i++) {
        String empId = _db.collection('employees').doc().id;
        String branch = branchIds[_rnd.nextInt(branchIds.length)];

        batch.set(_db.collection('employees').doc(empId), {
          'name': 'Pegawai Dummy ${i + 1}',
          'position': positions[_rnd.nextInt(positions.length)],
          'branch_id': branch,
          'branch_name': branch == 'bst_box' ? 'Box Factory' : (branch == 'm_alfa' ? 'Maint. Alfa' : 'Saufa Olshop'),
          'base_salary': (30 + _rnd.nextInt(20)) * 100000, // 3jt - 5jt
          'phone_number': '0812345678$i',
          'payday_date': 25,
          'joined_date': DateTime.now().subtract(Duration(days: _rnd.nextInt(365))),
          'last_paid_at': null,
        });
        await checkBatch();
      }


      // ==========================================
      // C. DATA TRANSAKSI (TAAT ATURAN DOMPET)
      // ==========================================

      // Kategori Pengeluaran Pusat (Pakai Kas Bendahara)
      List<String> centerExpenses = ['Suntikan Modal', 'Belanja Perusahaan', 'Beban Perusahaan', 'Maintenance'];

      // Kategori Pengeluaran Cabang (Pakai Kas Harian)
      List<String> dailyExpenses = ['Harian'];

      for (int i = 0; i < 40; i++) {
        String txId = _db.collection('transactions').doc().id;
        bool isIncome = _rnd.nextBool(); // 50% Masuk, 50% Keluar

        String branch = branchIds[_rnd.nextInt(branchIds.length)];
        String walletId;
        String category;
        String description;
        double amount;
        String type;

        if (isIncome) {
          // --- PEMASUKAN ---
          // Rule: Selalu Masuk Uang Perusahaan
          type = 'income';
          walletId = 'company_wallet';
          category = ['Penjualan', 'Jasa', 'Suntikan Modal'][_rnd.nextInt(3)];
          amount = (5 + _rnd.nextInt(50)) * 100000; // 500rb - 5jt
          description = "Omzet dari $branch";
        } else {
          // --- PENGELUARAN ---
          type = 'expense';

          // Tentukan apakah ini Pengeluaran Pusat atau Harian Cabang
          if (_rnd.nextBool()) {
            // CASE 1: Pengeluaran Pusat (Belanja Besar)
            walletId = 'treasurer_wallet';
            category = centerExpenses[_rnd.nextInt(centerExpenses.length)];
            amount = (10 + _rnd.nextInt(100)) * 100000; // 1jt - 10jt
            description = "Biaya $category untuk $branch";
          } else {
            // CASE 2: Pengeluaran Harian Cabang
            walletId = walletMap[branch]!; // petty_box, dll
            category = 'Harian';
            amount = (1 + _rnd.nextInt(5)) * 50000; // 50rb - 250rb
            description = "Beli bensin/token/makan";
          }
        }

        batch.set(_db.collection('transactions').doc(txId), {
          'amount': amount,
          'type': type,
          'category': category,
          'description': description,
          'wallet_id': walletId, // <--- Sudah sesuai logic baru
          'date': DateTime.now().subtract(Duration(days: _rnd.nextInt(30))), // Data 30 hari terakhir
          'user_id': uid,
          'related_branch_id': branch,
          'deleted_at': null,
        });
        await checkBatch();
      }

      // ==========================================
      // D. DATA UTANG (LIABILITY)
      // ==========================================
      List<String> debtsName = ['Vendor Kertas', 'Toko Sparepart', 'Supplier Besi'];
      for (int i = 0; i < 5; i++) {
        String debtId = _db.collection('debts').doc().id;
        batch.set(_db.collection('debts').doc(debtId), {
          'name': debtsName[_rnd.nextInt(debtsName.length)],
          'amount': (10 + _rnd.nextInt(50)) * 100000,
          'branch_id': branchIds[_rnd.nextInt(branchIds.length)],
          'note': 'Jatuh tempo bulan depan',
          'status': 'unpaid',
          'created_at': DateTime.now().subtract(Duration(days: 5)),
          'type': 'payable'
        });
        await checkBatch();
      }

      // Commit Akhir
      await batch.commit();
      print("✅ SEEDER BARU SELESAI! (5 WALLET SYSTEM READY)");

    } catch (e) {
      throw Exception("Gagal Seed Dummy: $e");
    }
  }

  // Helper Hapus Collection
  Future<void> _deleteCollection(String colName) async {
    final snapshot = await _db.collection(colName).get();
    if (snapshot.docs.isEmpty) return;
    WriteBatch batch = _db.batch();
    int count = 0;
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
      count++;
      if (count >= 450) {
        await batch.commit();
        batch = _db.batch();
        count = 0;
      }
    }
    await batch.commit();
  }
}