import { onRequest, onCall } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";

// Firebase Admin SDK'yı başlat
initializeApp();
const db = getFirestore();
const messaging = getMessaging();

// Utility function: E-posta ile kullanıcı bulma - DÜZELTİLMİŞ
async function getUserByEmail(email) {
  try {
    // E-posta adresini normalleştir (küçük harf + trim)
    const normalizedEmail = email.trim().toLowerCase();

    const usersSnapshot = await db
      .collection('users')
      .where('email', '==', normalizedEmail)
      .limit(1)
      .get();

    if (usersSnapshot.empty) {
      console.log(`User not found with email: ${normalizedEmail}`);
      return null;
    }

    const userDoc = usersSnapshot.docs[0];
    const userData = userDoc.data();

    // Onaylı kullanıcı kontrolü
    if (userData.role === 'customer' && !userData.isApproved) {
      console.log(`User found but not approved: ${normalizedEmail}`);
      return null;
    }

    console.log(`User found: ${normalizedEmail}, UID: ${userDoc.id}`);
    return {
      uid: userDoc.id,
      ...userData
    };
  } catch (error) {
    console.error('Error getting user by email:', error);
    throw error;
  }
}

// Utility function: Belirli role sahip kullanıcıların token'larını al
async function getTokensByRole(role) {
  try {
    const usersSnapshot = await db
      .collection('users')
      .where('role', '==', role)
      .where('isApproved', '==', true) // Sadece onaylı kullanıcılar
      .get();

    const tokens = [];

    for (const userDoc of usersSnapshot.docs) {
      const devicesSnapshot = await db
        .collection('users')
        .doc(userDoc.id)
        .collection('devices')
        .get();

      devicesSnapshot.docs.forEach(deviceDoc => {
        const deviceData = deviceDoc.data();
        if (deviceData.token) {
          tokens.push({
            token: deviceData.token,
            uid: userDoc.id,
            deviceId: deviceDoc.id
          });
        }
      });
    }

    console.log(`Found ${tokens.length} tokens for role: ${role}`);
    return tokens;
  } catch (error) {
    console.error('Error getting tokens by role:', error);
    throw error;
  }
}

// Utility function: Kullanıcının token'larını al
async function getTokensByUserId(userId) {
  try {
    const devicesSnapshot = await db
      .collection('users')
      .doc(userId)
      .collection('devices')
      .get();

    const tokens = [];
    devicesSnapshot.docs.forEach(deviceDoc => {
      const deviceData = deviceDoc.data();
      if (deviceData.token) {
        tokens.push({
          token: deviceData.token,
          uid: userId,
          deviceId: deviceDoc.id
        });
      }
    });

    console.log(`Found ${tokens.length} tokens for user: ${userId}`);
    return tokens;
  } catch (error) {
    console.error('Error getting tokens by user ID:', error);
    throw error;
  }
}

// Utility function: Geçersiz token'ları temizle
async function cleanupInvalidToken(uid, deviceId) {
  try {
    await db
      .collection('users')
      .doc(uid)
      .collection('devices')
      .doc(deviceId)
      .delete();
    console.log(`Cleaned up invalid token for user ${uid}, device ${deviceId}`);
  } catch (error) {
    console.error('Error cleaning up invalid token:', error);
  }
}

// Utility function: Bildirim kaydını Firestore'a kaydet
async function saveNotificationRecord(recipientUid, title, body, data = {}) {
  try {
    const notificationRef = await db.collection('notifications').add({
      recipientUid: recipientUid,
      title: title,
      body: body,
      data: data,
      sentAt: new Date(),
      isRead: false
    });
    console.log(`Notification record saved: ${notificationRef.id} for user: ${recipientUid}`);
  } catch (error) {
    console.error('Error saving notification record:', error);
  }
}

// Cloud Function: E-posta ile belirli kullanıcıya bildirim gönder - DÜZELTİLMİŞ
export const sendNotificationByEmail = onCall(async (request) => {
  const { customerEmail, notificationMessage, title = "Yeni Bildirim" } = request.data;

  console.log(`Attempting to send notification to: ${customerEmail}`);

  if (!customerEmail || !notificationMessage) {
    throw new Error('Missing required parameters: customerEmail, notificationMessage');
  }

  try {
    // E-posta ile kullanıcıyı bul
    const user = await getUserByEmail(customerEmail);

    if (!user) {
      console.log(`User not found or not approved: ${customerEmail}`);
      return {
        success: false,
        message: `Kullanıcı bulunamadı veya onaylanmamış: ${customerEmail}`,
        successCount: 0,
        failureCount: 1,
        userFound: false
      };
    }

    // Kullanıcının token'larını al
    const tokens = await getTokensByUserId(user.uid);

    if (tokens.length === 0) {
      return {
        success: false,
        message: `Kullanıcının cihaz token'ı bulunamadı: ${customerEmail}`,
        successCount: 0,
        failureCount: 1,
        userFound: true
      };
    }

    let successCount = 0;
    let failureCount = 0;
    const invalidTokens = [];

    // Mesaj nesnesi oluştur
    const message = {
      notification: {
        title: title,
        body: notificationMessage,
      },
      data: {
        type: 'admin_message',
        senderType: 'admin',
        timestamp: Date.now().toString()
      }
    };

    // Her token'a mesaj gönder
    for (const tokenInfo of tokens) {
      try {
        message.token = tokenInfo.token;
        await messaging.send(message);
        successCount++;
        console.log(`Notification sent successfully to token: ${tokenInfo.token}`);
      } catch (error) {
        console.error(`Error sending to token ${tokenInfo.token}:`, error);
        failureCount++;

        // Geçersiz token kontrolü
        if (error.code === 'messaging/registration-token-not-registered' ||
            error.code === 'messaging/invalid-registration-token') {
          invalidTokens.push(tokenInfo);
        }
      }
    }

    // Geçersiz token'ları temizle
    for (const invalidToken of invalidTokens) {
      await cleanupInvalidToken(invalidToken.uid, invalidToken.deviceId);
    }

    // Bildirim kaydını kaydet
    await saveNotificationRecord(user.uid, title, notificationMessage, {
      type: 'admin_message',
      senderType: 'admin'
    });

    const response = {
      success: successCount > 0,
      message: successCount > 0
        ? `Bildirim başarıyla gönderildi: ${user.email}`
        : `Bildirim gönderilemedi: ${user.email}`,
      successCount: successCount,
      failureCount: failureCount,
      userFound: true
    };

    console.log(`Notification result for ${customerEmail}:`, response);
    return response;

  } catch (error) {
    console.error('Error in sendNotificationByEmail:', error);
    return {
      success: false,
      message: error.message,
      successCount: 0,
      failureCount: 1,
      userFound: false
    };
  }
});

// Cloud Function: Belirli role sahip kullanıcılara bildirim gönder
export const sendNotificationToRole = onCall(async (request) => {
  const { role, title, body, data = {} } = request.data;

  if (!role || !title || !body) {
    throw new Error('Missing required parameters: role, title, body');
  }

  try {
    const tokens = await getTokensByRole(role);

    if (tokens.length === 0) {
      return {
        success: false,
        message: `No tokens found for role: ${role}`,
        successCount: 0,
        failureCount: 0
      };
    }

    let successCount = 0;
    let failureCount = 0;
    const invalidTokens = [];

    // Mesaj nesnesi oluştur
    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        ...data,
        timestamp: Date.now().toString()
      }
    };

    // Her token'a mesaj gönder
    for (const tokenInfo of tokens) {
      try {
        message.token = tokenInfo.token;
        await messaging.send(message);
        successCount++;

        // Bildirim kaydını kaydet
        await saveNotificationRecord(tokenInfo.uid, title, body, data);
      } catch (error) {
        console.error(`Error sending to token ${tokenInfo.token}:`, error);
        failureCount++;

        // Geçersiz token kontrolü
        if (error.code === 'messaging/registration-token-not-registered' ||
            error.code === 'messaging/invalid-registration-token') {
          invalidTokens.push(tokenInfo);
        }
      }
    }

    // Geçersiz token'ları temizle
    for (const invalidToken of invalidTokens) {
      await cleanupInvalidToken(invalidToken.uid, invalidToken.deviceId);
    }

    return {
      success: true,
      message: `Sent ${successCount} notifications successfully`,
      successCount: successCount,
      failureCount: failureCount
    };

  } catch (error) {
    console.error('Error in sendNotificationToRole:', error);
    throw new Error(`Failed to send notifications: ${error.message}`);
  }
});

// Cloud Function: Belirli müşteriye dosya gönderme - DÜZELTİLMİŞ
export const sendFileToSpecificCustomer = onCall(async (request) => {
  const {
    customerEmail,
    fileName,
    fileUrl,
    title = "Yeni Dosya Aldınız",
    message = "Size yeni bir dosya gönderildi"
  } = request.data;

  console.log(`Attempting to send file to: ${customerEmail}, File: ${fileName}`);

  if (!customerEmail || !fileName || !fileUrl) {
    throw new Error('Missing required parameters: customerEmail, fileName, fileUrl');
  }

  try {
    // E-posta ile kullanıcıyı bul
    const user = await getUserByEmail(customerEmail);

    if (!user) {
      return {
        success: false,
        message: `Kullanıcı bulunamadı: ${customerEmail}`,
        successCount: 0,
        failureCount: 1,
        userFound: false
      };
    }

    // Kullanıcının token'larını al
    const tokens = await getTokensByUserId(user.uid);

    if (tokens.length === 0) {
      return {
        success: false,
        message: `Kullanıcının FCM token'ı bulunamadı: ${customerEmail}`,
        successCount: 0,
        failureCount: 1,
        userFound: true
      };
    }

    let successCount = 0;
    let failureCount = 0;
    const invalidTokens = [];

    // Mesaj nesnesi oluştur
    const notificationMessage = {
      notification: {
        title: title,
        body: `${fileName} - ${message}`,
      },
      data: {
        type: 'file_received',
        fileName: fileName,
        fileUrl: fileUrl,
        senderType: 'admin',
        timestamp: Date.now().toString()
      }
    };

    // Her token'a mesaj gönder
    for (const tokenInfo of tokens) {
      try {
        notificationMessage.token = tokenInfo.token;
        await messaging.send(notificationMessage);
        successCount++;
      } catch (error) {
        console.error(`Error sending file notification to token ${tokenInfo.token}:`, error);
        failureCount++;

        // Geçersiz token kontrolü
        if (error.code === 'messaging/registration-token-not-registered' ||
            error.code === 'messaging/invalid-registration-token') {
          invalidTokens.push(tokenInfo);
        }
      }
    }

    // Geçersiz token'ları temizle
    for (const invalidToken of invalidTokens) {
      await cleanupInvalidToken(invalidToken.uid, invalidToken.deviceId);
    }

    // Bildirim kaydını kaydet
    await saveNotificationRecord(user.uid, title, `${fileName} - ${message}`, {
      type: 'file_received',
      fileName: fileName,
      fileUrl: fileUrl,
      senderType: 'admin'
    });

    return {
      success: successCount > 0,
      message: successCount > 0
        ? `Dosya bildirimi başarıyla gönderildi: ${user.email}`
        : `Dosya bildirimi gönderilemedi: ${user.email}`,
      successCount: successCount,
      failureCount: failureCount,
      userFound: true
    };

  } catch (error) {
    console.error('Error in sendFileToSpecificCustomer:', error);
    return {
      success: false,
      message: error.message,
      successCount: 0,
      failureCount: 1,
      userFound: false
    };
  }
});

// Firestore Trigger: Dosya paylaşıldığında otomatik bildirim gönder
export const onFileShared = onDocumentCreated(
  "shared_files/{fileId}",
  async (event) => {
    const fileData = event.data?.data();

    if (!fileData) {
      console.error('No file data found');
      return;
    }

    try {
      const { fileName, fileUrl, sharedBy, shareWithRole, description } = fileData;

      // Paylaşan kullanıcının bilgilerini al
      const sharedByUser = await db.collection('users').doc(sharedBy).get();
      const sharedByUserData = sharedByUser.data();

      // Hedef role sahip kullanıcıların token'larını al
      const tokens = await getTokensByRole(shareWithRole);

      if (tokens.length === 0) {
        console.log(`No tokens found for role: ${shareWithRole}`);
        return;
      }

      // Mesaj nesnesi oluştur
      const message = {
        notification: {
          title: 'Yeni Dosya Paylaşıldı',
          body: `${fileName} adlı dosya paylaşıldı`,
        },
        data: {
          type: 'file_shared',
          fileName: fileName,
          fileUrl: fileUrl,
          senderName: sharedByUserData?.email || 'Admin',
          description: description || '',
          timestamp: Date.now().toString()
        }
      };

      let successCount = 0;
      let failureCount = 0;
      const invalidTokens = [];

      // Her token'a mesaj gönder
      for (const tokenInfo of tokens) {
        try {
          message.token = tokenInfo.token;
          await messaging.send(message);
          successCount++;

          // Bildirim kaydını kaydet
          await saveNotificationRecord(tokenInfo.uid,
            'Yeni Dosya Paylaşıldı',
            `${fileName} adlı dosya paylaşıldı`,
            message.data
          );

        } catch (error) {
          console.error(`Error sending file notification to token ${tokenInfo.token}:`, error);
          failureCount++;

          if (error.code === 'messaging/registration-token-not-registered' ||
              error.code === 'messaging/invalid-registration-token') {
            invalidTokens.push(tokenInfo);
          }
        }
      }

      // Geçersiz token'ları temizle
      for (const invalidToken of invalidTokens) {
        await cleanupInvalidToken(invalidToken.uid, invalidToken.deviceId);
      }

      console.log(`File sharing notification sent. Success: ${successCount}, Failed: ${failureCount}`);

    } catch (error) {
      console.error('Error in onFileShared trigger:', error);
    }
  }
);

// Firestore Trigger: Web'den dosya yüklendiğinde Flutter'a bildir
export const onWebFileUploaded = onDocumentCreated(
  "user_files/{fileId}",
  async (event) => {
    const fileData = event.data?.data();

    if (!fileData) {
      console.error('No file data found');
      return;
    }

    try {
      const { fileName, fileUrl, uploadedBy, fileType, uploadedAt } = fileData;

      // Kullanıcının token'larını al
      const tokens = await getTokensByUserId(uploadedBy);

      if (tokens.length === 0) {
        console.log(`No tokens found for user: ${uploadedBy}`);
        return;
      }

      // Mesaj nesnesi oluştur
      const message = {
        notification: {
          title: 'Dosya Yükleme Tamamlandı',
          body: `${fileName} başarıyla yüklendi`,
        },
        data: {
          type: 'file_uploaded',
          fileName: fileName,
          fileUrl: fileUrl,
          fileType: fileType || 'unknown',
          timestamp: Date.now().toString()
        }
      };

      // Her token'a mesaj gönder
      for (const tokenInfo of tokens) {
        try {
          message.token = tokenInfo.token;
          await messaging.send(message);

          // Bildirim kaydını kaydet
          await saveNotificationRecord(uploadedBy,
            'Dosya Yükleme Tamamlandı',
            `${fileName} başarıyla yüklendi`,
            message.data
          );

        } catch (error) {
          console.error(`Error sending file upload notification:`, error);
        }
      }

      console.log(`File upload notification sent for: ${fileName}`);

    } catch (error) {
      console.error('Error in onWebFileUploaded trigger:', error);
    }
  }
);