import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/responsive_layout.dart';
import '../dashboard/presentation/dashboard_screen.dart';
import 'logic/auth_cubit.dart'; // Pastikan path ini benar sesuai folder Anda

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controller untuk mengambil teks inputan
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Variable untuk menyembunyikan password
  bool _isObscure = true;
  // GlobalKey untuk validasi form (misal: email kosong)
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // BlocConsumer: Pendengar setia perubahan state (Loading/Sukses/Gagal)
    return BlocConsumer<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state is AuthSuccess) {
          // 1. Tampilkan Pesan Sukses
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Login Berhasil! Mengalihkan..."),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 1), // Persingkat durasi
            ),
          );

          // 2. Tunggu sebentar (opsional) lalu Pindah Halaman
          Future.delayed(const Duration(seconds: 1), () {
            // Import file dashboard dulu di paling atas:
            // import '../../dashboard/presentation/dashboard_screen.dart';

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const DashboardScreen()),
            );
          });
        } else if (state is AuthFailure) {
          // Tampilkan pesan error jika gagal
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.error,
            ),
          );
        }
      },
      builder: (context, state) {
        // Tampilan Utama
        return Scaffold(
          backgroundColor: Colors.white,
          body: ResponsiveLayout(
            // Tampilan HP
            mobileBody: _buildLoginForm(context, state, isTablet: false),
            // Tampilan Tablet (Card di tengah)
            tabletBody: Center(
              child: SizedBox(
                width: 500,
                child: Card(
                  elevation: 5,
                  shadowColor: AppColors.primary.withOpacity(0.2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: _buildLoginForm(context, state, isTablet: true),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoginForm(BuildContext context, AuthState state, {required bool isTablet}) {
    // Cek apakah sedang loading
    final isLoading = state is AuthLoading;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. HEADER (Logo & Judul)
                Icon(
                    Icons.account_balance_wallet_rounded,
                    size: isTablet ? 100 : 80,
                    color: AppColors.primary
                ),
                const SizedBox(height: 16),
                Text(
                  "BST FINANCE",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isTablet ? 28 : 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Sistem Keuangan Multi cabang",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 40),

                // 2. INPUT EMAIL
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  enabled: !isLoading, // Matikan input jika sedang loading
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Email wajib diisi';
                    }
                    if (!value.contains('@')) {
                      return 'Format email tidak valid';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: "Email Perusahaan",
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                ),
                const SizedBox(height: 16),

                // 3. INPUT PASSWORD
                TextFormField(
                  controller: _passwordController,
                  obscureText: _isObscure,
                  enabled: !isLoading,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Password wajib diisi';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: "Password",
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_isObscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () {
                        setState(() {
                          _isObscure = !_isObscure;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                ),
                const SizedBox(height: 24),

                // 4. TOMBOL LOGIN (Dengan Loading State)
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isLoading
                        ? null // Matikan tombol jika loading
                        : () {
                      // Jalankan validasi form dulu
                      if (_formKey.currentState!.validate()) {
                        // Panggil Cubit untuk Login
                        context.read<AuthCubit>().login(
                          _emailController.text.trim(),
                          _passwordController.text.trim(),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: isLoading
                        ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2
                      ),
                    )
                        : const Text(
                      "Log In",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}