import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';

/// Web tabanlı dosya yükleme arayüzü için WebView ekranı
/// External web sitesi ile Flutter app arasında dosya transferi sağlar
class FileUploadWebViewScreen extends ConsumerStatefulWidget {
  const FileUploadWebViewScreen({super.key});

  @override
  ConsumerState<FileUploadWebViewScreen> createState() =>
      _FileUploadWebViewScreenState();
}

class _FileUploadWebViewScreenState
    extends ConsumerState<FileUploadWebViewScreen> {
  late final WebViewController controller;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  /// WebView controller'ını başlatır ve ayarlarını yapar
  /// JavaScript etkinleştirme ve navigation delegate kurulumu
  void _initializeWebView() {
    const String webViewUrl = 'https://droppingsite.netlify.app/';

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // JS gerekli
      ..setBackgroundColor(const Color(0x00000000)) // Şeffaf arka plan
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Progress tracking isteğe bağlı kullanılabilir
          },
          onPageStarted: (String url) {
            setState(() {
              isLoading = true;
              errorMessage = null;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              isLoading = false;
            });
            // Sayfa yüklendikten sonra kullanıcı bilgilerini inject et
            _injectUserAuth();
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              isLoading = false;
              errorMessage =
                  'Sayfa yüklenirken hata oluştu: ${error.description}';
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(webViewUrl));
  }

  /// Mevcut kullanıcı bilgilerini web sayfasına inject eder
  /// LocalStorage ve global function çağrısı ile kimlik doğrulama
  void _injectUserAuth() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser != null) {
      await controller.runJavaScript('''
        // LocalStorage'a kullanıcı bilgilerini kaydet
        localStorage.setItem('userEmail', '${currentUser.email}');
        localStorage.setItem('userUid', '${currentUser.uid}');
        localStorage.setItem('userRole', '${currentUser.role}');
        
        // Web sayfasının session başlatma fonksiyonunu çağır (varsa)
        if (typeof window.initializeUserSession === 'function') {
          window.initializeUserSession('${currentUser.email}', '${currentUser.uid}');
        }
      ''');
    }
  }

  /// Firestore'dan dosya değişikliklerini dinler
  /// Yeni dosya aktarımlarında kullanıcıya bildirim gösterir
  void _setupFileListener() {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    // selected_files koleksiyonunu dinle
    FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('selected_files')
        .snapshots()
        .listen((snapshot) {
          if (snapshot.docs.isNotEmpty) {
            _showSnackBar(
              'Yeni dosyalar aktarıldı! Customer ekranından görüntüleyebilirsiniz.',
              isSuccess: true,
            );
          }
        });
  }

  /// SnackBar mesajı gösterir
  /// Başarı durumunda customer ekranına yönlendirme seçeneği sunar
  void _showSnackBar(String message, {bool isSuccess = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
        action: isSuccess
            ? SnackBarAction(
                label: 'Customer\'a Git',
                textColor: Colors.white,
                onPressed: () {
                  Navigator.pop(context); // WebView'dan çık
                },
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dosya Yükleme'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        actions: [
          // Sayfa yenileme butonu
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              controller.reload();
            },
            tooltip: 'Sayfayı Yenile',
          ),
          // Yardım butonu
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              _showHelpDialog();
            },
            tooltip: 'Yardım',
          ),
        ],
      ),
      body: Column(
        children: [
          // Loading progress bar
          if (isLoading)
            Container(
              height: 4,
              child: const LinearProgressIndicator(
                backgroundColor: Colors.grey,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
            ),

          // WebView veya hata widget'ı
          Expanded(
            child: errorMessage != null
                ? _buildErrorWidget()
                : WebViewWidget(controller: controller),
          ),
        ],
      ),
      // Dosya dinleme butonu
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _setupFileListener();
          _showSnackBar('Dosya aktarımı dinleniyor...', isSuccess: true);
        },
        child: const Icon(Icons.sync),
        tooltip: 'Dosya Dinlemeyi Başlat',
      ),
    );
  }

  /// Hata durumunda gösterilecek widget
  /// Yeniden deneme ve geri dönme seçenekleri sunar
  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Sayfa Yüklenemedi',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  errorMessage = null;
                });
                _initializeWebView(); // WebView'ı yeniden başlat
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Yeniden Dene'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Geri Dön'),
            ),
          ],
        ),
      ),
    );
  }

  /// Kullanım talimatları dialog'u
  /// Dosya yükleme süreciyle ilgili detaylı bilgi verir
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dosya Yükleme Yardımı'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Bu sayfada dosyalarınızı yükleyebilir ve Flutter uygulamanıza aktarabilirsiniz.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 16),
              Text(
                'Nasıl Kullanılır:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('1. Web sayfasında giriş yapın (Flutter hesabınızla aynı)'),
              Text('2. Dosyalarınızı sürükle-bırak veya seçerek yükleyin'),
              Text('3. Yüklenen dosyalardan istediğinizi seçin'),
              Text('4. "Flutter\'a Aktar" butonuna tıklayın'),
              Text('5. Customer ekranında dosyalarınızı görüntüleyin'),
              SizedBox(height: 16),
              Text(
                'Desteklenen Formatlar:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('PDF, JPG, PNG, DOCX, TXT, ZIP'),
              SizedBox(height: 16),
              Text(
                'Not: Maksimum dosya boyutu 10MB\'dir.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anladım'),
          ),
        ],
      ),
    );
  }
}
