import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';

/// AuthRepository için provider
/// Dependency injection ve singleton pattern sağlar
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

/// Mevcut giriş yapmış kullanıcı state'i
/// Null = giriş yapılmamış, UserModel = giriş yapılmış
final currentUserProvider = StateProvider<UserModel?>((ref) => null);

/// Authentication işlemlerinin loading durumu
/// True = yükleniyor, false = işlem tamamlandı
final authLoadingProvider = StateProvider<bool>((ref) => false);

/// Authentication hatalarını tutar
/// Null = hata yok, String = hata mesajı
final authErrorProvider = StateProvider<String?>((ref) => null);

/// AuthController için provider
/// UI katmanından auth işlemlerini yönetir
final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(ref);
});

/// Authentication işlemlerini koordine eden controller sınıfı
/// UI katmanı ile repository arasında köprü görevi görür
/// Loading ve error state'lerini yönetir
class AuthController {
  final Ref ref;
  AuthController(this.ref);

  /// Yeni kullanıcı kaydı işlemini yönetir
  /// Loading state'i kontrol eder ve hataları yakalar
  Future<void> signUp(
    String email,
    String password, {
    String role = 'customer',
  }) async {
    try {
      // Loading başlat, hataları temizle
      ref.read(authLoadingProvider.notifier).state = true;
      ref.read(authErrorProvider.notifier).state = null;

      // Repository üzerinden kayıt işlemi
      final user = await ref
          .read(authRepositoryProvider)
          .signUp(email: email, password: password, role: role);

      // Kullanıcı state'ini güncelle (customer için null olabilir - onay bekliyor)
      ref.read(currentUserProvider.notifier).state = user;
    } catch (e) {
      // Hata durumunda error state'i güncelle
      ref.read(authErrorProvider.notifier).state = e.toString();
      print('SignUp Error: $e');
      rethrow; // UI katmanının da hatayı yakalayabilmesi için
    } finally {
      // İşlem bittiğinde loading'i kapat
      ref.read(authLoadingProvider.notifier).state = false;
    }
  }

  /// Kullanıcı giriş işlemini yönetir
  /// State yönetimi ve hata kontrolü sağlar
  Future<void> signIn(String email, String password) async {
    try {
      // Loading başlat, hataları temizle
      ref.read(authLoadingProvider.notifier).state = true;
      ref.read(authErrorProvider.notifier).state = null;

      // Repository üzerinden giriş işlemi
      final user = await ref
          .read(authRepositoryProvider)
          .signIn(email: email, password: password);

      // Başarılı giriş sonrası kullanıcı state'ini güncelle
      ref.read(currentUserProvider.notifier).state = user;
    } catch (e) {
      // Hata durumunda error state'i güncelle
      ref.read(authErrorProvider.notifier).state = e.toString();
      print('SignIn Error: $e');
      rethrow;
    } finally {
      ref.read(authLoadingProvider.notifier).state = false;
    }
  }

  /// Kullanıcı çıkış işlemini yönetir
  /// State'i temizler ve repository'deki signOut'u çağırır
  Future<void> signOut() async {
    try {
      await ref.read(authRepositoryProvider).signOut();
      // Çıkış sonrası kullanıcı state'ini temizle
      ref.read(currentUserProvider.notifier).state = null;
    } catch (e) {
      print('SignOut Error: $e');
      rethrow;
    }
  }

  /// Mevcut Firebase Auth kullanıcısını kontrol eder
  /// Uygulama başlatılırken ve session restore için kullanılır
  Future<void> getCurrentUser() async {
    try {
      // Firebase Auth'dan mevcut kullanıcıyı al
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        // Giriş yapmamış kullanıcı
        ref.read(currentUserProvider.notifier).state = null;
        return;
      }

      // Kullanıcı varsa Firestore'dan detaylı bilgileri getir
      ref.read(authLoadingProvider.notifier).state = true;

      final user = await ref
          .read(authRepositoryProvider)
          .getUserFromFirestore(currentUser.uid);

      // Kullanıcı state'ini güncelle
      ref.read(currentUserProvider.notifier).state = user;
    } catch (e) {
      print('Get current user error: $e');
      // Hata durumunda kullanıcıyı çıkart
      ref.read(currentUserProvider.notifier).state = null;
    } finally {
      ref.read(authLoadingProvider.notifier).state = false;
    }
  }
}
