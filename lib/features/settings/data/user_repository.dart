import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class UserRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // FUNGSI CANGGIH: Membuat User Tanpa Logout
  Future<void> createBranchUser({
    required String email,
    required String password,
    required String name,
    required String branchId, // 'bst_box', 'm_alfa', 'saufa'
  }) async {
    FirebaseApp? secondaryApp;
    try {
      // 1. Buat Instance Firebase Kedua (Agar admin tidak ter-logout)
      secondaryApp = await Firebase.initializeApp(
        name: 'SecondaryApp',
        options: Firebase.app().options,
      );

      // 2. Buat Akun di Auth menggunakan Instance Kedua
      UserCredential cred = await FirebaseAuth.instanceFor(app: secondaryApp)
          .createUserWithEmailAndPassword(email: email, password: password);

      // 3. Simpan Data Profil ke Firestore Utama
      // Role otomatis 'admin_cabang' karena dibuat lewat menu ini
      await _firestore.collection('users').doc(cred.user!.uid).set({
        'name': name,
        'email': email,
        'role': 'admin_branch',
        'branch_id': branchId,
        'created_at': FieldValue.serverTimestamp(),
      });

      // 4. Logout dari instance kedua (bersih-bersih)
      await FirebaseAuth.instanceFor(app: secondaryApp).signOut();

    } catch (e) {
      throw Exception("Gagal membuat user: $e");
    } finally {
      // Hapus instance kedua agar tidak memakan memori
      if (secondaryApp != null) {
        await secondaryApp.delete();
      }
    }
  }

  // AMBIL LIST USER
  Stream<QuerySnapshot> getUsersStream() {
    return _firestore.collection('users').orderBy('created_at', descending: true).snapshots();
  }

  // HAPUS USER (Hanya hapus data di Firestore, Auth tetap ada - Limitasi Firebase Client SDK)
  // Untuk hapus Auth total biasanya butuh Cloud Functions (Backend), tapi ini cukup untuk MVP.
  Future<void> deleteUserUnlink(String uid) async {
    await _firestore.collection('users').doc(uid).delete();
  }
}