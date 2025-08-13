import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notification_app/presentation/screen/admin_screen.dart';
import 'package:notification_app/presentation/screen/customer_screen.dart';
import 'package:notification_app/presentation/services/get_token.dart';
import 'firebase_options.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/screen/login_screen.dart';

/// Uygulamanın giriş noktası
/// Firebase initialization ve FCM token alımını başlatır
Future<void> main() async {
  // Widget binding'inin hazır olduğundan emin olur (Firebase için gerekli)
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase'i platform özel ayarları ile başlatır
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // FCM token'ı alır ve bildirim izinlerini ister
  await FirebaseApi().requestAndGetToken();

  // Riverpod state yönetimi ile uygulamayı başlatır
  runApp(ProviderScope(child: MyApp()));
}

/// Ana uygulama widget'ı
/// Kullanıcı authentication durumuna göre doğru ekranı gösterir
class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    // Uygulama başlatıldığında mevcut kullanıcıyı kontrol et
    _checkCurrentUser();
  }

  /// Mevcut kullanıcı session'ını kontrol eder
  /// Kısa bir delay ile auth controller'ın hazır olmasını bekler
  void _checkCurrentUser() async {
    // AuthController'ın provider olarak hazır olmasını bekle
    await Future.delayed(Duration(milliseconds: 100));
    final authController = ref.read(authControllerProvider);
    await authController.getCurrentUser();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final isLoading = ref.watch(authLoadingProvider);

    // Loading durumunda basit bir loading ekranı göster
    if (isLoading) {
      return MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // Kullanıcı durumuna göre ekran yönlendirmesi:
      // 1. Giriş yapmamış -> Login ekranı
      // 2. Admin rolü -> Admin paneli
      // 3. Customer rolü -> Customer paneli
      home: currentUser == null
          ? LoginScreen()
          : currentUser.role == 'admin'
          ? AdminScreen()
          : CustomerScreen(),
    );
  }
}
