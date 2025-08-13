import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import '../../data/models/user_model.dart';
import '../services/notification_service.dart';
import '../providers/auth_provider.dart';

/// Admin kullanıcıları için yönetim paneli ekranı
/// Dosya yükleme, bildirim gönderme, kullanıcı onaylama ve istatistik işlemleri
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  final NotificationService _notificationService = NotificationService();

  /// Dosya yükleme durumu kontrolü
  bool _isUploading = false;

  /// Yüklenen dosyanın download URL'i
  String? _uploadedFileUrl;

  /// Yüklenen dosyanın adı
  String? _fileName;

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    // Admin yetkisi kontrolü - sadece admin rolündeki kullanıcılar erişebilir
    if (currentUser?.role != 'admin') {
      return Scaffold(
        appBar: AppBar(
          title: Text('Yetkisiz Erişim'),
          actions: [
            IconButton(
              icon: Icon(Icons.logout),
              onPressed: () {
                ref.read(authControllerProvider).signOut();
              },
            ),
          ],
        ),
        body: Center(
          child: Text('Bu sayfaya erişim yetkiniz bulunmamaktadır.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Admin Panel',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blue[700],
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () {
              ref.read(authControllerProvider).signOut();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Kullanıcı onay bekleme paneli
              _buildPendingApprovalCard(),
              SizedBox(height: 16),

              // Dosya yükleme ve paylaşma paneli
              _buildFileUploadCard(),
              SizedBox(height: 16),

              // Manuel bildirim gönderme paneli
              _buildManualNotificationCard(),
              SizedBox(height: 16),

              // İstatistik paneli
              _buildStatsCard(),
            ],
          ),
        ),
      ),
    );
  }

  /// Onay bekleyen kullanıcıları gösteren kart bileşeni
  /// Real-time Firestore stream ile güncellenir
  Widget _buildPendingApprovalCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Üyelik Onayı Bekleyenler',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 16),
            // Real-time stream ile onay bekleyen kullanıcıları dinle
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('role', isEqualTo: 'customer')
                  .where('isApproved', isEqualTo: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Text('Hata: ${snapshot.error}');
                }

                final pendingUsers = snapshot.data?.docs ?? [];

                // Onay bekleyen kullanıcı yoksa başarı mesajı göster
                if (pendingUsers.isEmpty) {
                  return Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 8),
                        Text(
                          'Onay bekleyen kullanıcı yok',
                          style: TextStyle(color: Colors.green.shade800),
                        ),
                      ],
                    ),
                  );
                }

                // Onay bekleyen kullanıcıları listele
                return Container(
                  height: 200,
                  child: ListView.builder(
                    itemCount: pendingUsers.length,
                    itemBuilder: (context, index) {
                      final userDoc = pendingUsers[index];
                      final userData = userDoc.data() as Map<String, dynamic>;

                      return Card(
                        elevation: 2,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.orange.shade100,
                            child: Icon(Icons.person, color: Colors.orange),
                          ),
                          title: Text(
                            userData['email'] ?? 'E-posta bulunamadı',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Kayıt Tarihi: ${userData['createdAt'] != null ? (userData['createdAt'] as Timestamp).toDate().toString().split(' ')[0] : 'Bilinmiyor'}',
                          ),
                          trailing: ElevatedButton(
                            onPressed: () =>
                                _approveUser(userDoc.id, userData['email']),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            child: Text('Onayla'),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Dosya yükleme ve paylaşma paneli
  Widget _buildFileUploadCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dosya Paylaşımı',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isUploading ? null : _pickAndUploadFile,
                    icon: Icon(Icons.upload_file),
                    label: Text(
                      _isUploading ? 'Yükleniyor...' : 'Dosya Seç ve Yükle',
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showMyUploadedFiles,
                    icon: Icon(Icons.folder_open),
                    label: Text('Yüklediklerim'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            // Yükleme progress bar'ı
            if (_isUploading)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: LinearProgressIndicator(),
              ),
            // Yükleme tamamlandıktan sonra bildirim gönderme seçenekleri
            if (_uploadedFileUrl != null && _fileName != null)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dosya başarıyla yüklendi: $_fileName'),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _sendFileNotificationToCustomers,
                            icon: Icon(Icons.notifications_active),
                            label: Text('Tüm Customer\'lara Bildirim'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                _showSendFileToSpecificCustomerDialog(
                                  _fileName!,
                                  _uploadedFileUrl!,
                                ),
                            icon: Icon(Icons.person_pin),
                            label: Text('Belirli Customer\'a Gönder'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Manuel bildirim gönderme paneli
  Widget _buildManualNotificationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manuel Bildirim Gönder',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showSendEmailNotificationDialog(context),
                    icon: Icon(Icons.person_pin),
                    label: Text('Belirli Customer\'a'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// İstatistik paneli
  Widget _buildStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'İstatistikler',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _showCustomerStats,
              icon: Icon(Icons.people),
              label: Text('Customer İstatistiklerini Gör'),
            ),
          ],
        ),
      ),
    );
  }

  /// Kullanıcı onaylama işlemi
  /// Firestore'da isApproved field'ını true yapar
  Future<void> _approveUser(String userUid, String userEmail) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userUid).update({
        'isApproved': true,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $userEmail onaylandı!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Onay sırasında hata: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Admin'in yüklediği dosyaları gösteren dialog
  /// Sadece admin'in kendi dosyalarını listeler
  void _showMyUploadedFiles() {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.folder, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Yüklediğim Dosyalar',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  // Sadece bu admin'in yüklediği dosyaları getir
                  stream: FirebaseFirestore.instance
                      .collection('admin_files')
                      .where('uploadedBy', isEqualTo: currentUser.uid)
                      .orderBy('uploadedAt', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(child: Text('Hata: ${snapshot.error}'));
                    }

                    final files = snapshot.data?.docs ?? [];

                    if (files.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open,
                              size: 64,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text('Henüz dosya yüklenmemiş'),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: files.length,
                      itemBuilder: (context, index) {
                        final doc = files[index];
                        final data = doc.data() as Map<String, dynamic>;

                        return Card(
                          margin: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: Icon(
                                Icons.insert_drive_file,
                                color: Colors.blue,
                              ),
                            ),
                            title: Text(
                              data['fileName'] ?? 'Bilinmeyen Dosya',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Yüklenme: ${data['uploadedAt'] != null ? (data['uploadedAt'] as Timestamp).toDate().toString().split('.')[0] : 'Bilinmiyor'}',
                            ),
                            trailing: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _showSendFileToSpecificCustomerDialog(
                                  data['fileName'],
                                  data['fileUrl'],
                                );
                              },
                              icon: Icon(Icons.send, size: 16),
                              label: Text('Gönder'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Kapat'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Belirli customer'a dosya gönderme dialog'u
  /// E-posta adresi girilerek hedef customer seçilir
  void _showSendFileToSpecificCustomerDialog(String fileName, String fileUrl) {
    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.send, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(child: Text('Dosya Gönder')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gönderilecek dosya bilgisi
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.file_present, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Gönderilecek Dosya: $fileName',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            // E-posta adresi input field'ı
            TextField(
              controller: emailController,
              decoration: InputDecoration(
                labelText: 'Customer E-posta Adresi',
                hintText: 'ornek@email.com',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (emailController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Lütfen e-posta adresi girin')),
                );
                return;
              }

              Navigator.pop(dialogContext);
              await _sendFileToSpecificCustomer(
                emailController.text.trim(),
                fileName,
                fileUrl,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: Text('Gönder'),
          ),
        ],
      ),
    );
  }

  /// Belirli customer'a dosya gönderme işlemi
  /// NotificationService aracılığıyla cloud function çağırır
  Future<void> _sendFileToSpecificCustomer(
    String customerEmail,
    String fileName,
    String fileUrl,
  ) async {
    try {
      final result = await _notificationService.sendFileToSpecificCustomer(
        customerEmail: customerEmail,
        fileName: fileName,
        fileUrl: fileUrl,
        title: 'Yeni Dosya Aldınız',
        message: '$fileName adlı dosya size gönderildi.',
      );

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Dosya başarıyla gönderildi!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        String errorMessage;
        if (result['userFound'] == false) {
          errorMessage = '❌ Bu e-posta adresine sahip kullanıcı bulunamadı';
        } else {
          errorMessage = '❌ ${result['message'] ?? 'Dosya gönderilemedi'}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Hata oluştu: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Dosya seçme ve Firebase Storage'a yükleme işlemi
  /// File picker kullanarak dosya seçimi, storage upload ve metadata kaydetme
  Future<void> _pickAndUploadFile() async {
    try {
      // File picker ile dosya seç
      FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result != null) {
        File file = File(result.files.single.path!);
        String fileName = result.files.single.name;
        final currentUser = ref.read(currentUserProvider);

        setState(() {
          _isUploading = true;
          _fileName = fileName;
        });

        // Firebase Storage'a yükle
        String filePath =
            'admin_files/${currentUser?.uid}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
        UploadTask uploadTask = FirebaseStorage.instance
            .ref()
            .child(filePath)
            .putFile(file);

        TaskSnapshot snapshot = await uploadTask;
        String downloadUrl = await snapshot.ref.getDownloadURL();

        // Firestore'a dosya metadata'sını kaydet
        await FirebaseFirestore.instance.collection('admin_files').add({
          'fileName': fileName,
          'fileUrl': downloadUrl,
          'uploadedBy': currentUser?.uid,
          'uploadedAt': FieldValue.serverTimestamp(),
          'filePath': filePath,
        });

        setState(() {
          _uploadedFileUrl = downloadUrl;
          _isUploading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dosya başarıyla yüklendi: $fileName')),
        );
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Dosya yükleme hatası: $e')));
    }
  }

  /// Tüm customer'lara dosya bildirimi gönderme
  /// NotificationService.shareFile kullanarak toplu bildirim
  Future<void> _sendFileNotificationToCustomers() async {
    if (_uploadedFileUrl == null || _fileName == null) return;

    try {
      final currentUser = ref.read(currentUserProvider);

      bool success = await _notificationService.shareFile(
        fileName: _fileName!,
        fileUrl: _uploadedFileUrl!,
        sharedBy: currentUser?.uid ?? '',
        shareWithRole: 'customer',
        description: 'Admin tarafından paylaşılan dosya',
      );

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dosya paylaşıldı ve bildirimler gönderildi!'),
          ),
        );
        // Başarılı gönderim sonrası state temizle
        setState(() {
          _uploadedFileUrl = null;
          _fileName = null;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dosya paylaşma sırasında hata oluştu')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  /// Belirli customer'a manuel bildirim gönderme dialog'u
  /// Başlık, mesaj ve hedef e-posta adresi girişi
  void _showSendEmailNotificationDialog(BuildContext context) {
    final emailController = TextEditingController();
    final titleController = TextEditingController();
    final messageController = TextEditingController();

    titleController.text = 'Admin Bildirimi'; // Varsayılan başlık
    final pageContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.person_pin, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(child: Text('Belirli Customer\'a Bildirim Gönder')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // E-posta adresi input
              TextField(
                controller: emailController,
                decoration: InputDecoration(
                  labelText: 'Customer E-posta Adresi',
                  hintText: 'ornek@email.com',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              SizedBox(height: 16),
              // Başlık input
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: 'Başlık',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
              ),
              SizedBox(height: 16),
              // Mesaj input (çok satırlı)
              TextField(
                controller: messageController,
                decoration: InputDecoration(
                  labelText: 'Mesaj',
                  hintText: 'Bildiriminiz...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.message),
                ),
                maxLines: 4,
              ),
              SizedBox(height: 16),
              // Bilgilendirme mesajı
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bu bildirim sadece belirtilen e-posta adresine sahip customer\'a gönderilecektir.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Form validasyonu
              if (emailController.text.trim().isEmpty ||
                  titleController.text.trim().isEmpty ||
                  messageController.text.trim().isEmpty) {
                ScaffoldMessenger.of(pageContext).showSnackBar(
                  SnackBar(content: Text('Lütfen tüm alanları doldurun')),
                );
                return;
              }

              // E-posta format kontrolü
              final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
              if (!emailRegex.hasMatch(emailController.text.trim())) {
                ScaffoldMessenger.of(pageContext).showSnackBar(
                  SnackBar(content: Text('Geçerli bir e-posta adresi girin')),
                );
                return;
              }

              Navigator.pop(dialogContext);

              // Loading dialog göster
              showDialog(
                context: pageContext,
                barrierDismissible: false,
                builder: (context) => Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Bildirim gönderiliyor...'),
                        ],
                      ),
                    ),
                  ),
                ),
              );

              try {
                // NotificationService aracılığıyla bildirim gönder
                final result = await _notificationService
                    .sendNotificationByEmail(
                      customerEmail: emailController.text.trim(),
                      notificationMessage: messageController.text.trim(),
                      title: titleController.text.trim(),
                    );

                Navigator.pop(pageContext); // Loading dialog'u kapat

                if (!mounted) return;

                // Sonuç kontrolü ve kullanıcıya geri bildirim
                if (result['success'] == true) {
                  ScaffoldMessenger.of(pageContext).showSnackBar(
                    SnackBar(
                      content: Text('✅ Bildirim başarıyla gönderildi!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  String errorMessage;
                  if (result['userFound'] == false) {
                    errorMessage =
                        '❌ Bu e-posta adresine sahip kullanıcı bulunamadı';
                  } else {
                    errorMessage =
                        '❌ ${result['message'] ?? 'Bildirim gönderilemedi'}';
                  }

                  ScaffoldMessenger.of(pageContext).showSnackBar(
                    SnackBar(
                      content: Text(errorMessage),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                Navigator.pop(pageContext); // Loading dialog'u kapat

                if (!mounted) return;

                ScaffoldMessenger.of(pageContext).showSnackBar(
                  SnackBar(
                    content: Text('❌ Hata oluştu: ${e.toString()}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text('Gönder'),
          ),
        ],
      ),
    );
  }

  /// Customer istatistiklerini gösteren dialog
  /// Toplam, aktif, son kayıt olan kullanıcı sayıları
  void _showCustomerStats() async {
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final customers = await authRepo.getUsersByRole('customer');

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.analytics, color: Colors.blue),
              SizedBox(width: 8),
              Text('Customer İstatistikleri'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatRow(
                  'Toplam Customer Sayısı',
                  '${customers.length}',
                  Icons.people,
                ),
                SizedBox(height: 12),
                _buildStatRow(
                  'Aktif Customer Sayısı',
                  '${customers.where((c) => c.lastSeen != null && DateTime.now().difference(c.lastSeen!).inDays < 7).length}',
                  Icons.people_alt,
                  color: Colors.green,
                ),
                SizedBox(height: 12),
                _buildStatRow(
                  'Bu Hafta Aktif',
                  '${customers.where((c) => c.lastSeen != null && DateTime.now().difference(c.lastSeen!).inDays < 7).length}',
                  Icons.today,
                  color: Colors.blue,
                ),
                SizedBox(height: 16),
                Text(
                  'Son Kayıt Olanlar:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                ..._getRecentCustomers(customers),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Tamam'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('İstatistik yükleme hatası: $e')));
    }
  }

  /// İstatistik satırı widget'ı oluşturur
  /// Label, değer, ikon ve renk ile özelleştirilebilir
  Widget _buildStatRow(
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (color ?? Colors.blue).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (color ?? Colors.blue).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color ?? Colors.blue, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w500)),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color ?? Colors.blue,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  /// Son kayıt olan customer'ları listeleyen widget'lar döndürür
  /// En son 5 customer'ı gösterir
  List<Widget> _getRecentCustomers(List<UserModel> customers) {
    final recentCustomers = customers
        .where((c) => c.createdAt != null)
        .toList();

    // Kayıt tarihine göre sırala (en yeni önce)
    recentCustomers.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));

    // İlk 5'ini al ve widget listesi oluştur
    return recentCustomers
        .take(5)
        .map(
          (customer) => Padding(
            padding: EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(Icons.person, size: 16, color: Colors.grey),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    customer.email,
                    style: TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }
}
