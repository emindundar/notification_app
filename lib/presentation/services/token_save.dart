import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:uuid/uuid.dart';
import 'get_token.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FCM token'ını Firestore'a kaydetme işlemi
/// Cihaz bazlı token yönetimi için devices alt koleksiyonu kullanır
Future<void> saveTokenToFirestore(String uid) async {
  FirebaseApi firebaseApi = FirebaseApi();
  final token = await firebaseApi.requestAndGetToken();
  if (token == null) return; // Token alınamazsa işlemi durdur

  final deviceId = await getDeviceId(); // Benzersiz cihaz ID'si

  // Kullanıcının devices alt koleksiyonunda cihaz dokümantı
  final deviceDocRef = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('devices')
      .doc(deviceId);

  // Token ve cihaz bilgilerini kaydet/güncelle
  await deviceDocRef.set({
    'token': token,
    'platform': Platform.operatingSystem, // iOS, Android, etc.
    'lastSeen': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true)); // Mevcut verileri koru, sadece güncelle
}

/// FCM token yenileme dinleyicisini kurar
/// Token değiştiğinde otomatik güncelleme sağlar
void setupTokenRefreshListener(String uid) {
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    final deviceId = await getDeviceId();
    final deviceDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('devices')
        .doc(deviceId);

    // Yeni token ile güncelle
    await deviceDocRef.update({
      'token': newToken,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  });
}

/// Kullanıcı çıkış yaparken cihaz token'ını temizler
/// Gereksiz bildirimleri önlemek için önemli
Future<void> removeDeviceToken(String uid) async {
  final deviceId = await getDeviceId();
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('devices')
      .doc(deviceId)
      .delete();
}

/// Benzersiz cihaz ID'si oluşturur veya mevcut olanı getirir
/// SharedPreferences ile kalıcı saklar, UUID4 ile benzersizlik garantir
Future<String> getDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  const key = 'install_id';

  // Mevcut ID varsa kullan
  String? id = prefs.getString(key);
  if (id != null) return id;

  // Yoksa yeni UUID oluştur ve kaydet
  id = const Uuid().v4();
  await prefs.setString(key, id);
  return id;
}
