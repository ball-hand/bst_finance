import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'notification_service.dart';

class FCMService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  // 1. Inisialisasi Permission & Listener
  Future<void> init() async {
    // Minta Izin (Khusus iOS & Android 13+)
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted permission');
    }

    // Listener saat aplikasi sedang dibuka (Foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');
      print('Message data: ${message.data}');

      if (message.notification != null) {
        // Tampilkan sebagai Popup Lokal (karena FCM tidak otomatis muncul popup jika app sedang dibuka)
        NotificationService().showPopupNotification(
          message.notification!.title ?? 'Info',
          message.notification!.body ?? '-',
        );
      }
    });

    // Simpan Token ke Firestore
    await _saveDeviceToken();
  }

  // 2. Simpan Token HP ke Database User
  // Agar nanti server tahu harus kirim notif ke HP yang mana
  Future<void> _saveDeviceToken() async {
    String? token = await _firebaseMessaging.getToken();
    User? user = FirebaseAuth.instance.currentUser;

    if (token != null && user != null) {
      print("FCM TOKEN: $token"); // Debugging: Copy ini untuk tes di Console

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'fcm_token': token,
        'last_token_update': FieldValue.serverTimestamp(),
      });
    }
  }
}