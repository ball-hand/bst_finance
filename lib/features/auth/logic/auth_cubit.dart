import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/auth_service.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';

// --- STATES (Kondisi Aplikasi) ---
abstract class AuthState extends Equatable {
  @override
  List<Object> get props => [];
}

class AuthInitial extends AuthState {} // Diam
class AuthLoading extends AuthState {} // Mutar-mutar
class AuthSuccess extends AuthState {
  final User user;
  final String role;     // 'owner' atau 'admin_branch'
  final String branchId; // 'pusat' atau 'bst_box'

  AuthSuccess(this.user, this.role, this.branchId);

  @override
  List<Object> get props => [user, role, branchId];
}
class AuthFailure extends AuthState {  // Gagal
  final String message;
  AuthFailure(this.message);
}


// --- CUBIT (Otak Penggerak) ---
class AuthCubit extends Cubit<AuthState> {
  final AuthService _authService;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // Tambah ini

  AuthCubit(this._authService) : super(AuthInitial());

  void login(String email, String password) async {
    emit(AuthLoading());
    try {
      final user = await _authService.login(email, password);

      if (user != null) {
        // --- LOGIKA BARU: AMBIL DATA ROLE DARI FIRESTORE ---
        final userDoc = await _firestore.collection('users').doc(user.uid).get();

        String role = 'admin_branch'; // Default
        String branchId = 'bst_box'; // Default

        if (userDoc.exists) {
          final data = userDoc.data()!;
          role = data['role'] ?? 'admin_branch';
          branchId = data['branch_id'] ?? 'bst_box';
        }

        emit(AuthSuccess(user, role, branchId));
        // ---------------------------------------------------
      } else {
        emit(AuthFailure("Login gagal, user kosong."));
      }
    } catch (e) {
      final message = e.toString().replaceAll("Exception: ", "");
      emit(AuthFailure(message));
    }
  }
}