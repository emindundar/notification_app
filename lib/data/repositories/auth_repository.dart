import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:notification_app/presentation/services/token_save.dart';
import '../models/user_model.dart';

/// Firebase Authentication ve Firestore işlemlerini yöneten repository sınıfı
/// Kullanıcı kayıt, giriş, onay işlemleri ve token yönetimini kapsar
class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Yeni kullanıcı kaydı oluşturur
  /// Customer'lar için onay bekletir, admin'ler otomatik aktif olur
  Future<UserModel?> signUp({
    required String email,
    required String password,
    String role = "customer",
  }) async {
    try {
      // E-posta adresini normalize et (küçük harf, boşluksuz)
      String normalizedEmail = email.trim().toLowerCase();

      // Firebase Auth ile kullanıcı oluştur
      UserCredential credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      if (credential.user == null) {
        throw Exception('User creation failed');
      }

      // Kullanıcı modelini oluştur
      UserModel newUser = UserModel(
        uid: credential.user!.uid,
        email: normalizedEmail,
        role: role,
        isApproved: role == 'admin', // Admin'ler otomatik onaylı
        createdAt: DateTime.now(),
        lastSeen: DateTime.now(),
      );

      // Firestore'a kullanıcı bilgilerini kaydet
      await _firestore
          .collection('users')
          .doc(newUser.uid)
          .set(newUser.toMap());

      // Customer'lar için onay bekletme işlemi
      if (role == 'customer') {
        await _auth.signOut(); // Onay bekleyen customer'ı çıkart
        print('Customer registered but needs approval: ${normalizedEmail}');
        return null; // Onay bekliyor, giriş yapamaz
      }

      // Admin için token kaydet ve dinleyici başlat
      await saveTokenToFirestore(newUser.uid);
      setupTokenRefreshListener(newUser.uid);

      return newUser;
    } on FirebaseAuthException catch (e) {
      print('Firebase Auth Error: ${e.code} - ${e.message}');

      // Firebase hata kodlarını Türkçe mesajlara çevir
      String errorMessage;
      switch (e.code) {
        case 'email-already-in-use':
          errorMessage = 'Bu e-posta adresi zaten kullanımda';
          break;
        case 'weak-password':
          errorMessage = 'Şifre çok zayıf. En az 6 karakter olmalı';
          break;
        case 'invalid-email':
          errorMessage = 'Geçersiz e-posta adresi';
          break;
        default:
          errorMessage = 'Kayıt hatası: ${e.message}';
      }
      throw Exception(errorMessage);
    } catch (e) {
      print('SignUp Error: $e');
      rethrow;
    }
  }

  /// Kullanıcı giriş işlemini gerçekleştirir
  /// Onaylanmamış customer'ların girişini engeller
  Future<UserModel?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      String normalizedEmail = email.trim().toLowerCase();

      // Firebase Auth ile giriş yap
      UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      if (credential.user == null) {
        throw Exception('Login failed');
      }

      // Firestore'dan kullanıcı bilgilerini getir
      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(credential.user!.uid)
          .get();

      if (!doc.exists) {
        await _auth.signOut();
        throw Exception('Kullanıcı kaydı bulunamadı. Lütfen kayıt olun.');
      }

      final data = doc.data();
      if (data == null) {
        await _auth.signOut();
        throw Exception('Kullanıcı verileri bulunamadı');
      }

      UserModel user = UserModel.fromMap(data as Map<String, dynamic>);

      // Customer onay kontrolü
      if (user.role == 'customer' && !user.isApproved) {
        await _auth.signOut();
        throw Exception(
          'Hesabınız henüz admin tarafından onaylanmamıştır.\nOnay işlemi tamamlandıktan sonra giriş yapabileceksiniz.',
        );
      }

      // Son görülme zamanını güncelle
      await _updateLastSeen(user.uid);

      // FCM token'ı kaydet ve dinleyici başlat
      await saveTokenToFirestore(user.uid);
      setupTokenRefreshListener(user.uid);

      print('User signed in successfully: ${user.email} (${user.role})');
      return user;
    } on FirebaseAuthException catch (e) {
      print('Firebase Auth Error: ${e.code} - ${e.message}');

      // Firebase hata kodlarını Türkçe mesajlara çevir
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'Bu e-posta adresine kayıtlı kullanıcı bulunamadı';
          break;
        case 'wrong-password':
          errorMessage = 'Hatalı şifre';
          break;
        case 'invalid-email':
          errorMessage = 'Geçersiz e-posta adresi';
          break;
        case 'user-disabled':
          errorMessage = 'Bu hesap devre dışı bırakılmış';
          break;
        default:
          errorMessage = 'Giriş hatası: ${e.message}';
      }
      throw Exception(errorMessage);
    } catch (e) {
      print('SignIn Error: $e');
      rethrow;
    }
  }

  /// Kullanıcının oturumunu kapatır
  /// FCM token'ı temizler
  Future<void> signOut() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Çıkış yaparken cihaz token'ını kaldır
        await removeDeviceToken(user.uid);
      }
      await _auth.signOut();
    } catch (e) {
      print('SignOut Error: $e');
      rethrow;
    }
  }

  /// Kullanıcının son görülme zamanını günceller
  /// Aktiflik takibi için kullanılır
  Future<void> _updateLastSeen(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Update Last Seen Error: $e');
    }
  }

  /// Belirli role sahip kullanıcıları getirir
  /// İstatistik ve yönetim amaçlı kullanılır
  Future<List<UserModel>> getUsersByRole(String role) async {
    try {
      QuerySnapshot querySnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: role)
          .get();

      return querySnapshot.docs
          .map((doc) => UserModel.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Get Users By Role Error: $e');
      return [];
    }
  }

  /// Admin onayı bekleyen customer'ları getirir
  /// Admin panelinde kullanılır
  Future<List<UserModel>> getPendingApprovalUsers() async {
    try {
      QuerySnapshot querySnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'customer')
          .where('isApproved', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .get();

      List<UserModel> pendingUsers = querySnapshot.docs
          .map((doc) => UserModel.fromMap(doc.data() as Map<String, dynamic>))
          .toList();

      print('Found ${pendingUsers.length} users pending approval');
      return pendingUsers;
    } catch (e) {
      print('Get Pending Approval Users Error: $e');
      return [];
    }
  }

  /// Kullanıcıyı onaylar (isApproved = true)
  /// Admin tarafından customer onaylama işlemi
  Future<void> approveUser(String userUid) async {
    try {
      await _firestore.collection('users').doc(userUid).update({
        'isApproved': true,
      });
      print('User $userUid approved successfully');
    } catch (e) {
      print('Approve User Error: $e');
      rethrow;
    }
  }

  /// Kullanıcı onayını geri çeker (isApproved = false)
  /// Admin tarafından onay iptal işlemi
  Future<void> rejectUser(String userUid) async {
    try {
      await _firestore.collection('users').doc(userUid).update({
        'isApproved': false,
      });
      print('User $userUid approval rejected');
    } catch (e) {
      print('Reject User Error: $e');
      rethrow;
    }
  }

  /// E-posta adresine göre kullanıcı bulur
  /// Bildirim gönderme işlemlerinde kullanılır
  Future<UserModel?> getUserByEmail(String email) async {
    try {
      String normalizedEmail = email.trim().toLowerCase();

      QuerySnapshot querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      return UserModel.fromMap(
        querySnapshot.docs.first.data() as Map<String, dynamic>,
      );
    } catch (e) {
      print('Get User By Email Error: $e');
      return null;
    }
  }

  /// UID ile Firestore'dan kullanıcı bilgilerini getirir
  /// Session kontrolü ve mevcut kullanıcı getirme işlemi
  Future<UserModel?> getUserFromFirestore(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(uid)
          .get();

      if (!doc.exists) return null;

      final data = doc.data();
      if (data == null) return null;

      UserModel user = UserModel.fromMap(data as Map<String, dynamic>);

      // Onaylanmamış customer'ları otomatik çıkart
      if (user.role == 'customer' && !user.isApproved) {
        await _auth.signOut();
        return null;
      }

      // Son görülme zamanını güncelle
      await _updateLastSeen(user.uid);

      // Token kaydet ve dinleyici başlat
      await saveTokenToFirestore(user.uid);
      setupTokenRefreshListener(user.uid);

      return user;
    } catch (e) {
      print('Get user from Firestore error: $e');
      return null;
    }
  }
}
