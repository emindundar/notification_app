import 'package:cloud_firestore/cloud_firestore.dart';

/// Kullanıcı veri modelini temsil eden sınıf
/// Firestore database ile etkileşim için serialize/deserialize metodları içerir
class UserModel {
  /// Kullanıcının benzersiz Firebase Auth UID'si
  final String uid;

  /// Kullanıcının e-posta adresi (normalize edilmiş)
  final String email;

  /// Kullanıcı rolü: 'admin' veya 'customer'
  final String role;

  /// Admin tarafından onaylanma durumu
  /// Customer'lar için false, admin'ler için otomatik true
  final bool isApproved;

  /// Hesap oluşturulma tarihi
  final DateTime? createdAt;

  /// Son aktif olma tarihi (her giriş/çıkışta güncellenir)
  final DateTime? lastSeen;

  UserModel({
    required this.uid,
    required this.email,
    required this.role,
    this.isApproved = false,
    this.createdAt,
    this.lastSeen,
  });

  /// Firestore dökümanından UserModel nesnesi oluşturur
  /// Null değerleri için varsayılan değerler atar
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      role: map['role'] ?? 'customer', // Varsayılan rol customer
      isApproved: map['isApproved'] ?? false,
      // Firestore Timestamp'ı DateTime'a çevir
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : null,
      lastSeen: map['lastSeen'] != null
          ? (map['lastSeen'] as Timestamp).toDate()
          : null,
    );
  }

  /// UserModel nesnesini Firestore'a kaydetmek için Map'e çevirir
  /// Server timestamp kullanarak tutarlı zaman kaydı sağlar
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'role': role,
      'isApproved': isApproved,
      // Mevcut createdAt yoksa server timestamp kullan
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      // lastSeen her zaman server timestamp ile güncellenir
      'lastSeen': FieldValue.serverTimestamp(),
    };
  }

  /// Mevcut nesnenin kopyasını belirli alanları değiştirerek oluşturur
  /// Immutable pattern için kullanılır
  UserModel copyWith({
    String? uid,
    String? email,
    String? role,
    bool? isApproved,
    DateTime? createdAt,
    DateTime? lastSeen,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      role: role ?? this.role,
      isApproved: isApproved ?? this.isApproved,
      createdAt: createdAt ?? this.createdAt,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
