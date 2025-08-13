import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Firebase Cloud Messaging (FCM) token yönetimi için API sınıfı
/// Push notification izinleri ve token alma işlemlerini handle eder
class FirebaseApi {
  final fcm = FirebaseMessaging.instance;

  /// Bildirim izni ister ve FCM token'ı alır
  /// iOS ve Android için farklı izin seviyeleri destekler
  Future<String?> requestAndGetToken() async {
    // Bildirim izinlerini iste
    NotificationSettings settings = await fcm.requestPermission(
      alert: true, // Banner bildirimleri
      badge: true, // App icon badge
      sound: true, // Bildirim sesi
      provisional: false, // iOS provisional bildirimleri (false = kesin izin)
    );

    // İzin reddedilmişse null döndür
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      print('Kullanıcı bildirim iznini reddetti');
      return null;
    }

    // FCM token'ı al ve döndür
    String? token = await fcm.getToken();
    print('FCM token: $token');
    return token;
  }
}

/// Uygulama kapalıyken gelen bildirimleri handle eden background handler
/// Firebase.initializeApp() çağrısı gerekli (isolate farklı olduğu için)
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background isolate'de Firebase'i başlat
  await Firebase.initializeApp();
  print('Yeni bir bildirim geldi: ${message.messageId}');
}
