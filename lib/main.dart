import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // [PENTING]

// --- IMPORTS ANDA ---
import 'features/auth/data/auth_service.dart';
import 'features/auth/logic/auth_cubit.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/logic/dashboard_cubit.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'core/services/notification_service.dart';

// 1. HANDLER BACKGROUND (HARUS DI LUAR KELAS APAPUN)
// Ini yang akan dijalankan Android saat ada notifikasi masuk tapi aplikasi mati
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Menangani pesan background: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await initializeDateFormatting('id_ID', null);

  // 2. SETUP FCM BACKGROUND
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 3. INIT NOTIFIKASI LOKAL (Agar popup siap sedia)
  await NotificationService().init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>(create: (context) => AuthCubit(AuthService())),
        BlocProvider<DashboardCubit>(create: (context) => DashboardCubit()),
      ],
      child: MaterialApp(
        title: 'BST Finance',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          scaffoldBackgroundColor: Colors.white,
          useMaterial3: false,
        ),
        // Cek Login
        home: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasData) {
              return const DashboardScreen();
            }
            return const LoginScreen();
          },
        ),
      ),
    );
  }
}