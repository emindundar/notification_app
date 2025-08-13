import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

/// Kullanıcı giriş ve kayıt işlemleri için ana ekran
/// Authentication state yönetimi ve form validasyonu içerir
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  /// Şifre görünürlük kontrolü
  bool _obscurePassword = true;

  /// Son kayıt işlemi sonrası gösterilecek mesaj
  String? _lastRegistrationMessage;

  @override
  void dispose() {
    // Memory leak önlemek için controller'ları temizle
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  /// Form alanlarının doldurulma kontrolü
  /// Boş alan varsa kullanıcıya hata dialog'u gösterir
  bool _validateFields() {
    if (emailController.text.trim().isEmpty) {
      _showErrorDialog('Eksik Bilgi', 'Lütfen e-posta adresinizi girin.');
      return false;
    }
    if (passwordController.text.isEmpty) {
      _showErrorDialog('Eksik Bilgi', 'Lütfen şifrenizi girin.');
      return false;
    }
    return true;
  }

  /// E-posta format validasyonu
  /// Regex pattern ile temel format kontrolü yapar
  bool _validateEmail(String email) {
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    return emailRegex.hasMatch(email);
  }

  /// Hata mesajlarını dialog ile gösterir
  /// Tutarlı UI deneyimi için merkezi hata gösterimi
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Riverpod state'lerini dinle
    final isLoading = ref.watch(authLoadingProvider);
    final error = ref.watch(authErrorProvider);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          "NotificationApp",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blue[700],
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 40),

              // Uygulama logosu ve karşılama
              _buildWelcomeSection(),

              SizedBox(height: 40),

              // Hata mesajı (varsa)
              if (error != null) _buildErrorCard(error),

              // Kayıt başarı mesajı (varsa)
              if (_lastRegistrationMessage != null)
                _buildInfoCard(_lastRegistrationMessage!),

              // Login formu
              _buildLoginForm(isLoading),

              SizedBox(height: 20),

              // Bilgilendirme kartı
              _buildInfoSection(),

              SizedBox(height: 20),

              // Footer bilgi
              Center(
                child: Text(
                  'Sorun yaşıyorsanız lütfen yöneticinizle iletişime geçin',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Karşılama bölümü widget'ı
  Widget _buildWelcomeSection() {
    return Container(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.blue[100],
            child: Icon(
              Icons.notifications_active,
              size: 40,
              color: Colors.blue[700],
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Hoş Geldiniz',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          Text(
            'Lütfen giriş yapınız',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  /// Hata kartı widget'ı
  Widget _buildErrorCard(String error) {
    return Container(
      margin: EdgeInsets.only(bottom: 20),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              error,
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bilgilendirme kartı widget'ı
  Widget _buildInfoCard(String message) {
    return Container(
      margin: EdgeInsets.only(bottom: 20),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_empty, color: Colors.orange),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.orange.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Login formu widget'ı
  /// E-posta, şifre alanları ve giriş/kayıt butonları
  Widget _buildLoginForm(bool isLoading) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // E-posta alanı
            TextField(
              controller: emailController,
              decoration: InputDecoration(
                labelText: "E-posta Adresi",
                hintText: "ornek@email.com",
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue, width: 2),
                ),
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            SizedBox(height: 20),

            // Şifre alanı
            TextField(
              controller: passwordController,
              decoration: InputDecoration(
                labelText: "Şifre",
                hintText: "Şifrenizi girin",
                prefixIcon: Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue, width: 2),
                ),
              ),
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleSignIn(), // Enter tuşu ile giriş
            ),
            SizedBox(height: 30),

            // Butonlar veya loading
            if (isLoading)
              Container(
                height: 50,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Giriş butonu
                  ElevatedButton(
                    onPressed: _handleSignIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.login),
                        SizedBox(width: 8),
                        Text(
                          "Giriş Yap",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),

                  // Kayıt butonu
                  OutlinedButton(
                    onPressed: _handleSignUp,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.green),
                      foregroundColor: Colors.green,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_add),
                        SizedBox(width: 8),
                        Text(
                          "Yeni Hesap Oluştur",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Bilgilendirme bölümü
  Widget _buildInfoSection() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Önemli Bilgi',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Yeni kayıt olan kullanıcılar admin onayı bekledikten sonra giriş yapabilir. Onay süreci genellikle birkaç saat sürer.',
              style: TextStyle(color: Colors.blue[700], fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  /// Giriş işlemini başlatır
  /// Form validasyonu sonrası AuthController çağırır
  Future<void> _handleSignIn() async {
    if (!_validateFields()) return;

    try {
      ref.read(authErrorProvider.notifier).state = null;

      await ref
          .read(authControllerProvider)
          .signIn(emailController.text.trim(), passwordController.text);
    } catch (e) {
      print('Login error caught in UI: $e');
      // Hata AuthController tarafından handle edilir
    }
  }

  /// Kayıt işlemini başlatır
  /// Detaylı validasyon ve başarı mesajı gösterimi
  Future<void> _handleSignUp() async {
    if (!_validateFields()) return;

    // E-posta format kontrolü
    if (!_validateEmail(emailController.text.trim())) {
      _showErrorDialog(
        'Geçersiz E-posta',
        'Lütfen geçerli bir e-posta adresi girin.',
      );
      return;
    }

    // Şifre uzunluk kontrolü
    if (passwordController.text.length < 6) {
      _showErrorDialog('Zayıf Şifre', 'Şifre en az 6 karakter olmalıdır.');
      return;
    }

    try {
      ref.read(authErrorProvider.notifier).state = null;

      await ref
          .read(authControllerProvider)
          .signUp(
            emailController.text.trim(),
            passwordController.text,
            role: 'customer', // Varsayılan rol customer
          );

      // Başarılı kayıt sonrası mesaj ve form temizleme
      setState(() {
        _lastRegistrationMessage =
            'Kayıt işleminiz tamamlandı! Hesabınızın admin tarafından onaylanması bekleniyor. Onay sonrası giriş yapabileceksiniz.';
      });

      emailController.clear();
      passwordController.clear();

      // Başarı dialog'u göster
      _showSuccessDialog();
    } catch (e) {
      print('SignUp error caught in UI: $e');
      // Hata AuthController tarafından handle edilir
    }
  }

  /// Başarılı kayıt dialog'u
  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Kayıt Başarılı'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hesabınız oluşturuldu!'),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.hourglass_empty,
                        color: Colors.orange,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Onay Bekleniyor',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[800],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Hesabınızın admin tarafından onaylanması gerekiyor. Onay sonrasında normal şekilde giriş yapabileceksiniz.',
                    style: TextStyle(color: Colors.orange[700], fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Tamam'),
          ),
        ],
      ),
    );
  }
}
