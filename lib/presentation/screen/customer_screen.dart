import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../services/notification_service.dart';
import 'package:notification_app/presentation/screen/file_upload_webview_screen.dart';

class CustomerScreen extends ConsumerStatefulWidget {
  const CustomerScreen({super.key});

  @override
  ConsumerState<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends ConsumerState<CustomerScreen> {
  final NotificationService _notificationService = NotificationService();
  StreamSubscription<QuerySnapshot>? _selectedFilesSubscription;

  @override
  void initState() {
    super.initState();
    _setupNotificationHandling();
    _setupSelectedFilesListener();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _debugNotificationCount();
    });
  }

  @override
  void dispose() {
    _selectedFilesSubscription?.cancel();
    super.dispose();
  }

  void _debugNotificationCount() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser != null) {
      final count = await _notificationService.getUnreadNotificationCount(
        currentUser.uid,
      );
      print(
        'DEBUG: Unread notification count for ${currentUser.email}: $count',
      );
    }
  }

  void _setupSelectedFilesListener() {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    _selectedFilesSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('selected_files')
        .orderBy('selectedAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.docChanges.isNotEmpty) {
            final newFiles = snapshot.docChanges
                .where((change) => change.type == DocumentChangeType.added)
                .length;

            if (newFiles > 0 && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$newFiles yeni dosya web\'den aktarıldı!'),
                  backgroundColor: Colors.green,
                  action: SnackBarAction(
                    label: 'Görüntüle',
                    textColor: Colors.white,
                    onPressed: () => _showWebUploadedFiles(),
                  ),
                ),
              );
            }
          }
        });
  }

  void _showWebUploadedFiles() {
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
                    Icon(Icons.web, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Web\'den Yüklenen Dosyalar',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.upload_file),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FileUploadWebViewScreen(),
                          ),
                        );
                      },
                      tooltip: 'Yeni Dosya Yükle',
                    ),
                  ],
                ),
              ),

              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(currentUser.uid)
                      .collection('selected_files')
                      .orderBy('selectedAt', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error, size: 64, color: Colors.red),
                            SizedBox(height: 16),
                            Text('Hata: ${snapshot.error}'),
                          ],
                        ),
                      );
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
                            Text(
                              'Henüz web\'den dosya aktarılmamış',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        FileUploadWebViewScreen(),
                                  ),
                                );
                              },
                              icon: Icon(Icons.upload_file),
                              label: Text('İlk Dosyanızı Yükleyin'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      itemCount: files.length,
                      itemBuilder: (context, index) {
                        final doc = files[index];
                        final data = doc.data() as Map<String, dynamic>;

                        return Card(
                          margin: EdgeInsets.symmetric(vertical: 8),
                          elevation: 2,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: Text(
                                _getFileIcon(data['fileType'] ?? ''),
                                style: TextStyle(fontSize: 20),
                              ),
                            ),
                            title: Text(
                              data['fileName'] ?? 'Bilinmeyen Dosya',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Boyut: ${_formatFileSize(data['fileSize'] ?? 0)}',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                                if (data['selectedAt'] != null)
                                  Text(
                                    'Aktarıldı: ${_formatDate((data['selectedAt'] as Timestamp).toDate())}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) async {
                                switch (value) {
                                  case 'open':
                                    await _openFile(data['fileUrl']);
                                    break;
                                  case 'remove':
                                    await _removeFromSelection(doc.id);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'open',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.open_in_new,
                                        size: 18,
                                        color: Colors.blue,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Dosyayı Aç'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.remove_circle,
                                        size: 18,
                                        color: Colors.red,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Listeden Kaldır',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            onTap: () => _openFile(data['fileUrl']),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Kapat'),
                    ),
                    Spacer(),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FileUploadWebViewScreen(),
                          ),
                        );
                      },
                      icon: Icon(Icons.add),
                      label: Text('Yeni Dosya Ekle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openFile(String? fileUrl) async {
    if (fileUrl == null || fileUrl.isEmpty) {
      _showErrorMessage('Dosya URL\'si bulunamadı');
      return;
    }

    try {
      final uri = Uri.parse(fileUrl);

      bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }

      if (!launched) {
        launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }

      if (!launched) {
        _showErrorMessage('Dosya açılamadı. Lütfen manuel olarak indirin.');
      }
    } catch (e) {
      print('File open error: $e');
      _showErrorMessage('Dosya açma sırasında hata oluştu');
    }
  }

  Future<void> _removeFromSelection(String docId) async {
    try {
      final currentUser = ref.read(currentUserProvider);
      if (currentUser == null) return;

      bool? shouldRemove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Dosyayı Kaldır'),
          content: Text(
            'Bu dosyayı listenizden kaldırmak istediğinizden emin misiniz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text('Kaldır'),
            ),
          ],
        ),
      );

      if (shouldRemove == true) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('selected_files')
            .doc(docId)
            .delete();

        _showSuccessMessage('Dosya başarıyla kaldırıldı');
      }
    } catch (e) {
      _showErrorMessage(
        'Dosya kaldırma sırasında hata oluştu: ${e.toString()}',
      );
    }
  }

  void _setupNotificationHandling() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleForegroundMessage(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final messageData = message.data;
      final notificationType = messageData['type'] ?? '';

      if (notificationType == 'file_received' ||
          notificationType == 'file_uploaded' ||
          notificationType == 'file_shared') {
        _openFile(messageData['fileUrl']);
      }
    });

    FirebaseMessaging.instance.getInitialMessage().then((
      RemoteMessage? message,
    ) {
      if (message != null) {
        final messageData = message.data;
        final notificationType = messageData['type'] ?? '';

        if (notificationType == 'file_received' ||
            notificationType == 'file_uploaded' ||
            notificationType == 'file_shared') {
          _openFile(messageData['fileUrl']);
        }
      }
    });
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final messageData = message.data;
    final notificationType = messageData['type'] ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.notifications_active, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                message.notification?.title ?? 'Yeni Bildirim',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          message.notification?.body ?? 'Bildirim içeriği bulunamadı',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Kapat'),
          ),

          if (notificationType == 'file_received' ||
              notificationType == 'file_uploaded' ||
              notificationType == 'file_shared')
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _openFile(messageData['fileUrl']);
              },
              child: Text('Dosyayı Aç'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Customer Panel',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blue[700],
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.notifications_outlined, size: 24),
                _buildNotificationBadge(),
              ],
            ),
            onPressed: () => _showNotificationHistory(),
            tooltip: 'Bildirimler',
          ),

          IconButton(
            icon: Icon(Icons.logout_outlined),
            onPressed: () => _showLogoutConfirmation(),
            tooltip: 'Çıkış Yap',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: Icon(Icons.person, color: Colors.blue),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hoş Geldiniz!',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: Colors.blue[800],
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                currentUser?.email ?? "E-posta bulunamadı",
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.verified_user, color: Colors.green),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Hesabınız onaylanmış ve aktif durumda',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),

            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.folder, color: Colors.orange, size: 28),
                        SizedBox(width: 8),
                        Text(
                          'Dosya İşlemleri',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.orange[800],
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _showAdminFiles,
                            icon: Icon(Icons.admin_panel_settings),
                            label: Text('Admin Dosyaları'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _showWebUploadedFiles,
                            icon: Icon(Icons.web),
                            label: Text('Web Dosyaları'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showNotificationHistory() {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      _showErrorMessage('Kullanıcı bilgisi bulunamadı');
      return;
    }

    _notificationService.getUnreadNotificationCount(currentUser.uid).then((
      count,
    ) {
      print('DEBUG: Before showing history - Unread count: $count');
    });

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
                    Icon(Icons.history, color: Colors.indigo),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bildirim Geçmişi',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: Colors.indigo[800]),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.mark_email_read),
                      onPressed: () => _markAllAsRead(),
                      tooltip: 'Tümünü Okundu İşaretle',
                    ),
                  ],
                ),
              ),
              Divider(height: 1),

              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _notificationService.getNotificationHistory(
                    currentUser.uid,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Bildirimler yükleniyor...'),
                          ],
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      print('Bildirim geçmişi hatası: ${snapshot.error}');
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Colors.red,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Bildirimler yüklenirken hata oluştu',
                              style: TextStyle(color: Colors.red),
                            ),
                            SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: () {
                                _notificationService.createTestNotification(
                                  currentUser.uid,
                                );
                                _showSuccessMessage(
                                  'Test bildirimi oluşturuldu',
                                );
                              },
                              child: Text('Test Bildirimi Oluştur'),
                            ),
                          ],
                        ),
                      );
                    }

                    final notifications = snapshot.data?.docs ?? [];
                    print(
                      'DEBUG: Loaded ${notifications.length} notifications',
                    );

                    if (notifications.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.notifications_off,
                              size: 64,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Henüz bildirim yok',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[600],
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Admin tarafından gönderilen bildirimler burada görünecektir.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                            SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                _notificationService.createTestNotification(
                                  currentUser.uid,
                                );
                                _showSuccessMessage(
                                  'Test bildirimi oluşturuldu',
                                );
                              },
                              child: Text('Test Bildirimi Oluştur'),
                            ),
                          ],
                        ),
                      );
                    }

                    // Bildirim listesi - her bildirim için özelleştirilmiş ListTile
                    return ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: notifications.length,
                      itemBuilder: (context, index) {
                        final doc = notifications[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final isRead = data['isRead'] ?? false;
                        final notificationData =
                            data['data'] as Map<String, dynamic>? ?? {};
                        final notificationType = notificationData['type'] ?? '';

                        return Card(
                          margin: EdgeInsets.symmetric(vertical: 6),
                          elevation: isRead
                              ? 1
                              : 3, // Okunmamış bildirimlerde daha yüksek elevation
                          color: isRead
                              ? Colors.grey[50]
                              : Colors
                                    .blue[50], // Renk kodlaması ile görsel ayrım
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isRead
                                  ? Colors.grey[300]
                                  : Colors.blue[100],
                              child: Icon(
                                _getNotificationIcon(data['data']),
                                color: isRead
                                    ? Colors.grey[600]
                                    : Colors.blue[700],
                                size: 20,
                              ),
                            ),
                            title: Text(
                              data['title'] ?? 'Başlık Yok',
                              style: TextStyle(
                                fontWeight: isRead
                                    ? FontWeight.normal
                                    : FontWeight
                                          .bold, // Okunmamış bildirimlerde kalın yazı
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(height: 4),
                                Text(
                                  data['body'] ?? 'İçerik yok',
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 14,
                                  ),
                                ),
                                // Gönderilme tarihi (varsa) - formatlanmış tarih gösterimi
                                if (data['sentAt'] != null)
                                  Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: Text(
                                      _formatDate(
                                        (data['sentAt'] as Timestamp).toDate(),
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            // Trailing: Okundu göstergesi ve bildirim tipine göre işlem menüsü
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Okunmamış bildirim için mavi nokta göstergesi
                                if (!isRead)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                    ),
                                    margin: EdgeInsets.only(right: 8),
                                  ),

                                // Dosya bildirimleri için özel işlem menüsü
                                if (notificationType == 'file_received' ||
                                    notificationType == 'file_uploaded' ||
                                    notificationType == 'file_shared')
                                  PopupMenuButton<String>(
                                    onSelected: (value) async {
                                      switch (value) {
                                        case 'open':
                                          await _openFile(
                                            notificationData['fileUrl'],
                                          );
                                          break;
                                        case 'delete':
                                          await _deleteNotification(doc.id);
                                          break;
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
                                        value: 'open',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.open_in_new,
                                              size: 18,
                                              color: Colors.blue,
                                            ),
                                            SizedBox(width: 8),
                                            Text('Dosyayı Aç'),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.delete,
                                              size: 18,
                                              color: Colors.red,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Bildirimi Sil',
                                              style: TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  // Normal bildirimler için basit check ikonu
                                  Icon(
                                    Icons.check,
                                    color: Colors.grey,
                                    size: 16,
                                  ),
                              ],
                            ),
                            // ListTile'a tıklandığında okunmamış bildirimleri okundu işaretle
                            onTap: () {
                              if (!isRead) {
                                _notificationService.markNotificationAsRead(
                                  doc.id,
                                );
                              }
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // Alt aksiyonlar: Dialog kapatma ve toplu işlemler
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Kapat'),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _markAllAsRead(),
                        icon: Icon(Icons.done_all, size: 18),
                        label: Text('Tümünü Okundu İşaretle'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Admin'den gelen dosyaları gösteren dialog
  /// Sadece 'file_received' tipindeki bildirimleri filtreler
  /// Dosya açma ve görüntüleme işlevleri sağlar
  void _showAdminFiles() {
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
              // Dialog başlığı
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.admin_panel_settings, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Admin\'den Gelen Dosyalar',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  // Sadece bu kullanıcıya gönderilen dosya bildirimlerini getir
                  stream: FirebaseFirestore.instance
                      .collection('notifications')
                      .where('recipientUid', isEqualTo: currentUser.uid)
                      .where('data.type', isEqualTo: 'file_received')
                      .orderBy('sentAt', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(child: Text('Hata: ${snapshot.error}'));
                    }

                    final fileNotifications = snapshot.data?.docs ?? [];

                    // Admin'den dosya almamışsa boş durum göster
                    if (fileNotifications.isEmpty) {
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
                            Text('Henüz admin\'den dosya almadınız'),
                          ],
                        ),
                      );
                    }

                    // Admin dosyalarını listele
                    return ListView.builder(
                      itemCount: fileNotifications.length,
                      itemBuilder: (context, index) {
                        final doc = fileNotifications[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final fileData =
                            data['data'] as Map<String, dynamic>? ?? {};

                        return Card(
                          margin: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.shade100,
                              child: Icon(
                                Icons.file_present,
                                color: Colors.orange,
                              ),
                            ),
                            title: Text(
                              fileData['fileName'] ?? 'Bilinmeyen Dosya',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Gönderilme: ${data['sentAt'] != null ? _formatDate((data['sentAt'] as Timestamp).toDate()) : 'Bilinmiyor'}',
                            ),
                            // Dosya açma butonu
                            trailing: ElevatedButton.icon(
                              onPressed: () => _openFile(fileData['fileUrl']),
                              icon: Icon(Icons.open_in_new, size: 16),
                              label: Text('Aç'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
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

  /// Tüm bildirimleri okundu olarak işaretler
  /// NotificationService aracılığıyla batch operation yapar
  /// UI güncellenmesi için setState çağrır
  Future<void> _markAllAsRead() async {
    try {
      final currentUser = ref.read(currentUserProvider);
      if (currentUser == null) return;

      // Batch olarak tüm bildirimleri okundu işaretle
      await _notificationService.markAllNotificationsAsRead(currentUser.uid);
      _showSuccessMessage('Tüm bildirimler okundu olarak işaretlendi');

      // Notification badge'ini güncellemek için setState
      setState(() {});
    } catch (e) {
      _showErrorMessage(
        'Bildirimler işaretlenirken hata oluştu: ${e.toString()}',
      );
    }
  }

  /// Çıkış onay dialog'unu gösterir
  /// Kullanıcı onayı aldıktan sonra AuthController.signOut çağrır
  /// Session temizleme ve FCM token silme işlemleri otomatik yapılır
  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.logout, color: Colors.red),
            SizedBox(width: 8),
            Text('Çıkış Yap'),
          ],
        ),
        content: Text('Hesabınızdan çıkış yapmak istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // AuthController aracılığıyla güvenli çıkış
              ref.read(authControllerProvider).signOut();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Çıkış Yap'),
          ),
        ],
      ),
    );
  }

  /// Bildirim türüne göre uygun ikonu döndürür
  /// Null safety ile defensive programming uygular
  /// Switch-case yapısı ile extensible ikon mapping
  IconData _getNotificationIcon(Map<String, dynamic>? data) {
    if (data == null) return Icons.notifications;

    final type = data['type'] ?? '';
    switch (type) {
      case 'file_shared':
      case 'file_received':
        return Icons.file_present; // Dosya bildirimleri için klasör ikonu
      case 'admin_message':
        return Icons
            .admin_panel_settings; // Admin mesajları için yönetici ikonu
      case 'file_uploaded':
        return Icons.cloud_upload; // Yükleme bildirimleri için bulut ikonu
      default:
        return Icons.notifications; // Bilinmeyen tipler için varsayılan ikon
    }
  }

  /// Dosya türüne göre emoji ikonu döndürür
  /// MIME type veya dosya uzantısından çıkarım yapar
  /// UI'da görsel zenginlik için emoji kullanır
  String _getFileIcon(String fileType) {
    // Resim dosyaları için
    if (fileType.toLowerCase().contains('image') ||
        fileType.toLowerCase().contains('jpg') ||
        fileType.toLowerCase().contains('png') ||
        fileType.toLowerCase().contains('jpeg')) {
      return '🖼️';
    }
    // PDF dosyaları için
    if (fileType.toLowerCase().contains('pdf')) return '📕';
    // Word dosyaları için
    if (fileType.toLowerCase().contains('word') ||
        fileType.toLowerCase().contains('docx') ||
        fileType.toLowerCase().contains('doc')) {
      return '📘';
    }
    // Metin dosyaları için
    if (fileType.toLowerCase().contains('text') ||
        fileType.toLowerCase().contains('txt')) {
      return '📄';
    }
    // Arşiv dosyaları için
    if (fileType.toLowerCase().contains('zip') ||
        fileType.toLowerCase().contains('rar') ||
        fileType.toLowerCase().contains('archive')) {
      return '🗜️';
    }
    // Excel dosyaları için
    if (fileType.toLowerCase().contains('excel') ||
        fileType.toLowerCase().contains('xls')) {
      return '📊';
    }
    return '📄'; // Varsayılan dosya ikonu
  }

  /// Byte cinsinden dosya boyutunu kullanıcı dostu formata çevirir
  /// Binary (1024) hesaplama kullanır: B, KB, MB, GB
  /// Matematiksel logaritma ile doğru birim hesaplaması
  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';

    const suffixes = ['B', 'KB', 'MB', 'GB'];
    // Log(1024) ile hangi birim kullanılacağını hesapla
    var i = (log(bytes) / log(1024)).floor();
    // Overflow önlemi için suffix array sınırını kontrol et
    if (i >= suffixes.length) i = suffixes.length - 1;

    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  /// DateTime'ı kullanıcı dostu formata çevirir
  /// Akıllı tarih gösterimi: Bugün, Dün, Geçen hafta, Tam tarih
  /// Türkçe lokalizasyon ile gün isimleri
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateToFormat = DateTime(date.year, date.month, date.day);

    // Bugün mü?
    if (dateToFormat == today) {
      return 'Bugün ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    // Dün mü?
    else if (dateToFormat == today.subtract(Duration(days: 1))) {
      return 'Dün ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    // Son 7 gün içinde mi?
    else if (now.difference(date).inDays < 7) {
      const days = [
        'Pazartesi',
        'Salı',
        'Çarşamba',
        'Perşembe',
        'Cuma',
        'Cumartesi',
        'Pazar',
      ];
      return '${days[date.weekday - 1]} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    // 7 günden eski için tam tarih
    else {
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
  }

  /// Başarı mesajı gösterir (yeşil SnackBar)
  /// Mounted kontrolü ile memory leak önler
  /// Icon ile görsel feedback sağlar
  void _showSuccessMessage(String message) {
    if (!mounted) return; // Widget dispose edilmişse gösterme

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating, // Modern floating style
      ),
    );
  }

  /// Hata mesajı gösterir (kırmızı SnackBar)
  /// Daha uzun süre görünür kalması için duration ayarlanmış
  /// Error icon ile görsel feedback
  void _showErrorMessage(String message) {
    if (!mounted) return; // Widget dispose edilmişse gösterme

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: Duration(
          seconds: 4,
        ), // Hata mesajları daha uzun süre görünsün
      ),
    );
  }

  /// Okunmamış bildirim sayısını kırmızı badge olarak gösterir
  /// FutureBuilder ile async data loading
  /// 99+ limiti ile UI overflow önlemi
  Widget _buildNotificationBadge() {
    final currentUser = ref.watch(currentUserProvider);

    if (currentUser == null) return SizedBox.shrink();

    return FutureBuilder<int>(
      future: _notificationService.getUnreadNotificationCount(currentUser.uid),
      builder: (context, snapshot) {
        // Debug bilgisi için log
        if (snapshot.hasData) {
          print('DEBUG: Notification badge count: ${snapshot.data}');
        }

        if (snapshot.hasError) {
          print('DEBUG: Notification badge error: ${snapshot.error}');
          return SizedBox.shrink(); // Hata durumunda badge gösterme
        }

        final count = snapshot.data ?? 0;

        // Bildirim yoksa badge gösterme
        if (count <= 0) {
          return SizedBox.shrink();
        }

        // Kırmızı circular badge
        return Positioned(
          right: -2,
          top: -2,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            constraints: BoxConstraints(minWidth: 18, minHeight: 18),
            child: Text(
              count > 99 ? '99+' : count.toString(), // 99+ overflow koruması
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }

  /// Belirli bir bildirimi silme işlemi
  /// Kullanıcı onayı aldıktan sonra Firestore'dan hard delete yapar
  /// Cascade etki yoktur, sadece bildirim kaydı silinir
  Future<void> _deleteNotification(String notificationId) async {
    try {
      // Kullanıcıdan silme onayı al
      bool? shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Bildirimi Sil'),
          content: Text('Bu bildirimi silmek istediğinizden emin misiniz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text('Sil'),
            ),
          ],
        ),
      );

      // Onay verilmişse silme işlemini gerçekleştir
      if (shouldDelete == true) {
        // Firestore'dan bildirimi kalıcı olarak sil
        await FirebaseFirestore.instance
            .collection('notifications')
            .doc(notificationId)
            .delete();

        _showSuccessMessage('Bildirim silindi');
      }
    } catch (e) {
      _showErrorMessage('Bildirim silinirken hata oluştu: ${e.toString()}');
    }
  }
}
