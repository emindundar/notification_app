import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Bildirim gönderme ve yönetme işlemleri için servis sınıfı
/// Cloud Functions ve Firestore entegrasyonu sağlar
class NotificationService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Belirli role sahip tüm kullanıcılara bildirim gönderir
  /// Cloud Function aracılığıyla toplu bildirim işlemi
  Future<Map<String, dynamic>> sendNotificationToRole({
    required String role,
    required String title,
    required String body,
  }) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable(
        'sendNotificationToRole',
      );

      final result = await callable.call({
        'role': role,
        'title': title,
        'body': body,
      });

      // Cloud Function'dan dönen sonucu parse et
      return {
        'success': result.data['success'] ?? false,
        'successCount': result.data['successCount'] ?? 0,
        'failureCount': result.data['failureCount'] ?? 0,
        'message': result.data['message'] ?? '',
      };
    } catch (e) {
      print('Send Notification To Role Error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// E-posta adresine göre spesifik kullanıcıya bildirim gönderir
  /// Cloud Function ile hedef kullanıcı bulma ve bildirim gönderme
  Future<Map<String, dynamic>> sendNotificationByEmail({
    required String customerEmail,
    required String notificationMessage,
    String title = "Yeni Bildirim",
  }) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable(
        'sendNotificationByEmail',
      );

      final result = await callable.call({
        'customerEmail': customerEmail.trim().toLowerCase(),
        'notificationMessage': notificationMessage,
        'title': title,
      });

      return {
        'success': result.data['success'] ?? false,
        'successCount': result.data['successCount'] ?? 0,
        'failureCount': result.data['failureCount'] ?? 0,
        'message': result.data['message'] ?? '',
        'userFound': result.data['userFound'] ?? false, // Kullanıcı bulundu mu?
      };
    } catch (e) {
      print('Send Notification By Email Error: $e');
      return {'success': false, 'error': e.toString(), 'userFound': false};
    }
  }

  /// Belirli customer'a dosya gönderme bildirimi
  /// Dosya bilgileri ile birlikte özel bildirim türü
  Future<Map<String, dynamic>> sendFileToSpecificCustomer({
    required String customerEmail,
    required String fileName,
    required String fileUrl,
    String title = "Yeni Dosya",
    String message = "Size yeni bir dosya gönderildi",
  }) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable(
        'sendFileToSpecificCustomer',
      );

      final result = await callable.call({
        'customerEmail': customerEmail.trim().toLowerCase(),
        'fileName': fileName,
        'fileUrl': fileUrl,
        'title': title,
        'message': message,
      });

      return {
        'success': result.data['success'] ?? false,
        'successCount': result.data['successCount'] ?? 0,
        'failureCount': result.data['failureCount'] ?? 0,
        'message': result.data['message'] ?? '',
        'userFound': result.data['userFound'] ?? false,
      };
    } catch (e) {
      print('Send File To Specific Customer Error: $e');
      return {'success': false, 'error': e.toString(), 'userFound': false};
    }
  }

  /// Dosya paylaşma işlemi
  /// Firestore'a shared_files kaydı oluşturur
  Future<bool> shareFile({
    required String fileName,
    required String fileUrl,
    required String sharedBy,
    required String shareWithRole,
    String? description,
  }) async {
    try {
      // Paylaşılan dosya bilgilerini Firestore'a kaydet
      await _firestore.collection('shared_files').add({
        'fileName': fileName,
        'fileUrl': fileUrl,
        'sharedBy': sharedBy,
        'shareWithRole': shareWithRole,
        'description': description,
        'sharedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      print('Share File Error: $e');
      return false;
    }
  }

  /// Kullanıcının okunmamış bildirim sayısını getirir
  /// Badge gösterimi için kullanılır
  Future<int> getUnreadNotificationCount(String uid) async {
    if (uid.isEmpty) return 0;

    try {
      QuerySnapshot querySnapshot = await _firestore
          .collection('notifications')
          .where('recipientUid', isEqualTo: uid)
          .where('isRead', isEqualTo: false)
          .get();

      print(
        'DEBUG: Unread notifications count for $uid: ${querySnapshot.docs.length}',
      );
      return querySnapshot.docs.length;
    } catch (e) {
      print('Get Unread Notification Count Error: $e');
      return 0;
    }
  }

  /// Kullanıcının bildirim geçmişini real-time stream olarak döndürür
  /// UI'da StreamBuilder ile kullanılır
  Stream<QuerySnapshot> getNotificationHistory(String uid) {
    if (uid.isEmpty) {
      return Stream.empty();
    }

    print('DEBUG: Getting notification history for user: $uid');

    try {
      return _firestore
          .collection('notifications')
          .where('recipientUid', isEqualTo: uid)
          .orderBy('sentAt', descending: true)
          .limit(50) // Performans için limit
          .snapshots();
    } catch (e) {
      print('Get Notification History Error: $e');
      return Stream.empty();
    }
  }

  /// Belirli bir bildirimi okundu olarak işaretler
  /// Kullanıcı etkileşimi sonrası çağrılır
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
      });

      print('DEBUG: Notification $notificationId marked as read');
    } catch (e) {
      print('Mark Notification As Read Error: $e');
    }
  }

  /// Kullanıcının tüm bildirimlerini okundu olarak işaretler
  /// Batch işlem ile performans optimizasyonu
  Future<void> markAllNotificationsAsRead(String uid) async {
    if (uid.isEmpty) return;

    try {
      // Okunmamış bildirimleri getir
      QuerySnapshot unreadNotifications = await _firestore
          .collection('notifications')
          .where('recipientUid', isEqualTo: uid)
          .where('isRead', isEqualTo: false)
          .get();

      // Batch işlem oluştur
      WriteBatch batch = _firestore.batch();

      // Her bildirimi batch'e ekle
      for (QueryDocumentSnapshot doc in unreadNotifications.docs) {
        batch.update(doc.reference, {'isRead': true});
      }

      // Batch'i execute et
      await batch.commit();
      print('DEBUG: All notifications marked as read for user: $uid');
    } catch (e) {
      print('Mark All Notifications As Read Error: $e');
    }
  }

  /// Test amaçlı bildirim oluşturur
  /// Debug ve development sürecinde kullanılır
  Future<void> createTestNotification(String uid) async {
    if (uid.isEmpty) return;

    try {
      await _firestore.collection('notifications').add({
        'recipientUid': uid,
        'title': 'Test Bildirimi',
        'body': 'Bu test amaçlı bir bildirimidir',
        'sentAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'data': {
          'type': 'test',
          'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      });
      print('DEBUG: Test notification created for user: $uid');
    } catch (e) {
      print('Create Test Notification Error: $e');
    }
  }
}
