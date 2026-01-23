import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // 1. Setting Android
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    // 2. Init Plugin
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {},
    );

    // 3. [FIX UTAMA] MEMBUAT CHANNEL SECARA PAKSA (Agar muncul di Pengaturan HP)
    final androidImplementation = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      // Minta Izin (Android 13+)
      await androidImplementation.requestNotificationsPermission();

      // Buat Channel "High Importance" SEKARANG JUGA
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel', // ID harus sama dengan yang di showPopup
        'Notifikasi Penting', // Nama yang muncul di Setting HP
        description: 'Notifikasi untuk approval dan hutang',
        importance: Importance.max, // MAX = Popup
        playSound: true,
        enableVibration: true,
      );

      await androidImplementation.createNotificationChannel(channel);
    }
  }

  // FUNGSI MEMUNCULKAN POPUP
  Future<void> showPopupNotification(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'high_importance_channel', // ID Channel
      'Notifikasi Penting', // Nama Channel
      channelDescription: 'Channel untuk notifikasi approval dan utang',
      importance: Importance.max, // MAX = Muncul Popup di atas layar
      priority: Priority.high,    // HIGH = Getar & Bunyi
      showWhen: true,
      playSound: true,
      enableVibration: true,
    );

    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond, // ID Unik (pakai waktu biar gak numpuk)
      title,
      body,
      platformChannelSpecifics,
    );
  }
}