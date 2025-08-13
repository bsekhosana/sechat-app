import 'package:sechat_app/core/services/airnotifier_service.dart';
import 'package:sechat_app/core/services/encryption_service.dart';
import 'package:sechat_app/core/services/simple_notification_service.dart';
import 'package:sechat_app/core/services/key_exchange_service.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/utils/guid_generator.dart';

/// Service to handle end-to-end encrypted notifications
class SecureNotificationService {
  static SecureNotificationService? _instance;
  static SecureNotificationService get instance =>
      _instance ??= SecureNotificationService._();

  // Private constructor
  SecureNotificationService._();

  // Cache the last typing indicator sent time for rate limiting
  final Map<String, DateTime> _lastTypingIndicatorSent = {};
  // Typing indicator cooldown duration
  static const Duration typingIndicatorCooldown = Duration(seconds: 2);

  /// Initialize secure notification service
  Future<void> initialize() async {
    try {
      // Ensure encryption keys exist
      await KeyExchangeService.instance.ensureKeysExist();
      print('🔒 SecureNotificationService: Initialized successfully');
    } catch (e) {
      print('🔒 SecureNotificationService: Error during initialization: $e');
    }
  }

  /// Wait for key exchange to complete with timeout
  Future<bool> _waitForKeyExchange(String recipientId) async {
    const maxWaitTime = Duration(seconds: 10);
    const checkInterval = Duration(milliseconds: 200);
    final startTime = DateTime.now();

    while (DateTime.now().difference(startTime) < maxWaitTime) {
      // Check if we now have a public key for this user
      if (await KeyExchangeService.instance.hasPublicKeyForUser(recipientId)) {
        // Verify the key is valid by testing encryption
        try {
          final testData = {'test': 'key_exchange_verification'};
          final encrypted =
              await EncryptionService.encryptAesCbcPkcs7(testData, recipientId);
          if (encrypted['data'] != null) {
            print(
                '🔒 SecureNotificationService: Key exchange verified successfully');
            return true;
          }
        } catch (e) {
          print('🔒 SecureNotificationService: Key verification failed: $e');
        }
      }

      // Wait before checking again
      await Future.delayed(checkInterval);
    }

    print(
        '🔒 SecureNotificationService: Key exchange timeout after ${maxWaitTime.inSeconds}s');
    return false;
  }

  /// Send encrypted message notification
  Future<bool> sendEncryptedMessage({
    required String recipientId,
    required String senderName,
    required String message,
    required String conversationId,
    String? messageId,
  }) async {
    try {
      // Ensure key exchange with recipient
      final keyExchangeSuccess = await KeyExchangeService.instance
          .ensureKeyExchangeWithUser(recipientId);
      if (!keyExchangeSuccess) {
        print(
            '🔒 SecureNotificationService: Key exchange failed, cannot encrypt message');
        return false;
      }

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🔒 SecureNotificationService: User not logged in');
        return false;
      }

      // Use provided message ID or generate a new one
      final finalMessageId = messageId ?? GuidGenerator.generateShortId();

      // Create message data
      final messageData = {
        'type': 'message',
        'message_id': finalMessageId,
        'sender_id': currentUserId,
        'sender_name': senderName,
        'message': message,
        'conversation_id': conversationId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'handshake_step': 1, // Step 1: Sent
      };

      // Create encrypted payload
      final encryptedPayload = await EncryptionService.createEncryptedPayload(
          messageData, recipientId);

      // Send via notification service
      return await SimpleNotificationService.instance.sendEncryptedMessage(
        recipientId: recipientId,
        senderName: senderName,
        message: message,
        conversationId: conversationId,
        encryptedData: encryptedPayload['data'] as String,
        checksum: encryptedPayload['checksum'] as String,
        messageId: finalMessageId,
      );
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error sending encrypted message: $e');
      return false;
    }
  }

  /// Send encrypted delivery receipt notification (handshake step 2)
  Future<bool> sendEncryptedDeliveryReceipt({
    required String recipientId,
    required String messageId,
    required String conversationId,
  }) async {
    try {
      // Ensure key exchange with recipient
      final keyExchangeSuccess = await KeyExchangeService.instance
          .ensureKeyExchangeWithUser(recipientId);
      if (!keyExchangeSuccess) {
        print(
            '🔒 SecureNotificationService: Key exchange failed, cannot encrypt delivery receipt');
        return false;
      }

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🔒 SecureNotificationService: User not logged in');
        return false;
      }

      // Create receipt data
      final receiptData = {
        'type': 'delivery_receipt',
        'message_id': messageId,
        'recipient_id': currentUserId,
        'conversation_id': conversationId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'handshake_step': 2, // Step 2: Delivered
      };

      // Create encrypted payload
      final encryptedPayload = await EncryptionService.createEncryptedPayload(
          receiptData, recipientId);

      // Send silent notification via AirNotifier
      final success =
          await SimpleNotificationService.instance.sendMessageDeliveryStatus(
        recipientId: recipientId,
        messageId: messageId,
        status: 'delivered',
        conversationId: conversationId,
        encryptedData: encryptedPayload['data'] as String,
        checksum: encryptedPayload['checksum'] as String,
      );

      return success;
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error sending encrypted delivery receipt: $e');
      return false;
    }
  }

  /// Send encrypted read receipt notification (handshake step 3)
  Future<bool> sendEncryptedReadReceipt({
    required String recipientId,
    required List<String> messageIds,
    required String conversationId,
  }) async {
    try {
      // Ensure key exchange with recipient
      final keyExchangeSuccess = await KeyExchangeService.instance
          .ensureKeyExchangeWithUser(recipientId);
      if (!keyExchangeSuccess) {
        print(
            '🔒 SecureNotificationService: Key exchange failed, cannot encrypt read receipt');
        return false;
      }

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🔒 SecureNotificationService: User not logged in');
        return false;
      }

      // Create receipt data
      final receiptData = {
        'type': 'read_receipt',
        'message_ids': messageIds,
        'recipient_id': currentUserId,
        'conversation_id': conversationId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'handshake_step': 3, // Step 3: Read
      };

      // Create encrypted payload
      final encryptedPayload = await EncryptionService.createEncryptedPayload(
          receiptData, recipientId);

      // Send silent notification via AirNotifier
      final success =
          await SimpleNotificationService.instance.sendMessageReadNotification(
        recipientId: recipientId,
        messageIds: messageIds,
        conversationId: conversationId,
        encryptedData: encryptedPayload['data'] as String,
        checksum: encryptedPayload['checksum'] as String,
      );

      return success;
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error sending encrypted read receipt: $e');
      return false;
    }
  }

  /// Send encrypted typing indicator
  Future<bool> sendEncryptedTypingIndicator({
    required String recipientId,
    required bool isTyping,
    required String conversationId,
  }) async {
    try {
      // Rate limit typing indicators to avoid notification spam
      final now = DateTime.now();
      final lastSent = _lastTypingIndicatorSent[recipientId];

      if (lastSent != null &&
          now.difference(lastSent) < typingIndicatorCooldown) {
        // Too soon, skip this update
        return true; // Return true to avoid error handling
      }

      // Update last sent time
      _lastTypingIndicatorSent[recipientId] = now;

      // Ensure key exchange with recipient
      final keyExchangeSuccess = await KeyExchangeService.instance
          .ensureKeyExchangeWithUser(recipientId);
      if (!keyExchangeSuccess) {
        print(
            '🔒 SecureNotificationService: Key exchange failed, cannot encrypt typing indicator');
        return false;
      }

      final currentUserId = SeSessionService().currentSessionId;
      final username = await SeSessionService().getCurrentUsername();

      if (currentUserId == null || username == null) {
        print('🔒 SecureNotificationService: User not logged in');
        return false;
      }

      // Create typing data
      final typingData = {
        'type': 'typing_indicator',
        'sender_id': currentUserId,
        'sender_name': username,
        'is_typing': isTyping,
        'conversation_id': conversationId,
        'timestamp': now.millisecondsSinceEpoch,
      };

      // Create encrypted payload
      final encryptedPayload = await EncryptionService.createEncryptedPayload(
          typingData, recipientId);

      // Send silent notification via AirNotifier
      final success =
          await SimpleNotificationService.instance.sendTypingIndicator(
        recipientId: recipientId,
        isTyping: isTyping,
        conversationId: conversationId,
        encryptedData: encryptedPayload['data'] as String,
        checksum: encryptedPayload['checksum'] as String,
      );

      return success;
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error sending encrypted typing indicator: $e');
      return false;
    }
  }

  /// Send encrypted invitation update (cancellation, etc.)
  Future<bool> sendEncryptedInvitationUpdate({
    required String recipientId,
    required String senderName,
    required String invitationId,
    required String action,
    String? message,
  }) async {
    try {
      // Ensure key exchange with recipient
      final keyExchangeSuccess = await KeyExchangeService.instance
          .ensureKeyExchangeWithUser(recipientId);
      if (!keyExchangeSuccess) {
        print(
            '🔒 SecureNotificationService: Key exchange failed, cannot encrypt invitation update');
        return false;
      }

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🔒 SecureNotificationService: User not logged in');
        return false;
      }

      // Create invitation update data
      final updateData = {
        'type': 'invitation_update',
        'invitationId': invitationId,
        'sender_id': currentUserId,
        'sender_name': senderName,
        'action': action,
        'message': message ?? '$senderName $action the invitation',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Create encrypted payload
      final encryptedPayload = await EncryptionService.createEncryptedPayload(
        updateData,
        recipientId,
      );

      // Send via AirNotifier
      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: recipientId,
        title: '', // Silent notification
        body: '', // Silent notification
        data: {
          'data': encryptedPayload['data'] as String,
          'type': 'invitation_update',
          'action': action,
          'silent': true,
        },
        sound: null, // No sound
        badge: 0, // No badge
        encrypted: true,
        checksum: encryptedPayload['checksum'] as String,
      );

      return success;
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error sending encrypted invitation update: $e');
      return false;
    }
  }

  /// Send encrypted online status update
  Future<bool> sendEncryptedOnlineStatus({
    required String recipientId,
    required bool isOnline,
  }) async {
    try {
      // Ensure key exchange with recipient
      final keyExchangeSuccess = await KeyExchangeService.instance
          .ensureKeyExchangeWithUser(recipientId);
      if (!keyExchangeSuccess) {
        print(
            '🔒 SecureNotificationService: Key exchange failed, cannot encrypt online status');
        return false;
      }

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🔒 SecureNotificationService: User not logged in');
        return false;
      }

      final now = DateTime.now();

      // Create status data
      final statusData = {
        'type': 'online_status',
        'user_id': currentUserId,
        'is_online': isOnline,
        'last_seen': now.toIso8601String(),
        'timestamp': now.millisecondsSinceEpoch,
      };

      // Create encrypted payload
      final encryptedPayload = await EncryptionService.createEncryptedPayload(
          statusData, recipientId);

      // Send silent notification via AirNotifier
      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: recipientId,
        title: '', // Silent notification
        body: '', // Silent notification
        data: {
          'data': encryptedPayload['data'] as String,
          'type': 'online_status',
          'isOnline': isOnline,
          'lastSeen': now.toIso8601String(),
          'silent': true,
        },
        sound: null, // No sound
        badge: 0, // No badge
        encrypted: true,
        checksum: encryptedPayload['checksum'] as String,
      );

      return success;
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error sending encrypted online status: $e');
      return false;
    }
  }

  /// Process encrypted notification
  Future<Map<String, dynamic>?> processEncryptedNotification(
      Map<String, dynamic> notificationData) async {
    try {
      print('🔒 SecureNotificationService: Processing encrypted notification');

      // Extract encrypted data
      final encryptedData = notificationData['data'] as String?;
      final checksum = notificationData['checksum'] as String?;

      if (encryptedData == null) {
        print('🔒 SecureNotificationService: No encrypted data found');
        return null;
      }

      // Decrypt the data using the new encryption service
      final decryptedData =
          await EncryptionService.decryptAesCbcPkcs7(encryptedData);
      if (decryptedData == null) {
        print('🔒 SecureNotificationService: Failed to decrypt data');
        return null;
      }

      // Verify checksum if provided
      if (checksum != null) {
        final isValid =
            EncryptionService.verifyChecksum(decryptedData, checksum);
        if (!isValid) {
          print('🔒 SecureNotificationService: Checksum verification failed');
          return null;
        }
      }

      print(
          '🔒 SecureNotificationService: Successfully decrypted notification');
      return decryptedData;
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error processing encrypted notification: $e');
      return null;
    }
  }
}

/// Extension to SimpleNotificationService to add encrypted notification support
extension EncryptedNotifications on SimpleNotificationService {
  // Use AirNotifierService for sending notifications
  Future<bool> sendNotificationToSession({
    required String sessionId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? sound,
    int badge = 0,
    bool encrypted = false,
    String? checksum,
  }) async {
    return await AirNotifierService.instance.sendNotificationToSession(
      sessionId: sessionId,
      title: title,
      body: body,
      data: data,
      sound: sound,
      badge: badge,
      encrypted: encrypted,
      checksum: checksum,
    );
  }

  /// Send encrypted message delivery status (handshake step 2)
  Future<bool> sendMessageDeliveryStatus({
    required String recipientId,
    required String messageId,
    required String status,
    required String conversationId,
    required String encryptedData,
    required String checksum,
  }) async {
    try {
      return await sendNotificationToSession(
        sessionId: recipientId,
        title: '', // Empty title for silent notification
        body: '', // Empty body for silent notification
        data: {
          'data': encryptedData,
          'type': 'message_delivery_status',
          'silent': true,
        },
        sound: null, // No sound for delivery status
        badge: 0, // No badge for silent notifications
        encrypted: true,
        checksum: checksum,
      );
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error sending message delivery status: $e');
      return false;
    }
  }

  /// Send encrypted message read notification (handshake step 3)
  Future<bool> sendMessageReadNotification({
    required String recipientId,
    required List<String> messageIds,
    required String conversationId,
    required String encryptedData,
    required String checksum,
  }) async {
    try {
      return await sendNotificationToSession(
        sessionId: recipientId,
        title: '', // Empty title for silent notification
        body: '', // Empty body for silent notification
        data: {
          'data': encryptedData,
          'type': 'message_read',
          'silent': true,
        },
        sound: null, // No sound for read notifications
        badge: 0, // No badge for silent notifications
        encrypted: true,
        checksum: checksum,
      );
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error sending message read notification: $e');
      return false;
    }
  }

  /// Send encrypted typing indicator
  Future<bool> sendTypingIndicator({
    required String recipientId,
    required bool isTyping,
    required String conversationId,
    required String encryptedData,
    required String checksum,
  }) async {
    try {
      return await sendNotificationToSession(
        sessionId: recipientId,
        title: '', // Empty title for silent notification
        body: '', // Empty body for silent notification
        data: {
          'data': encryptedData,
          'type': 'typing_indicator',
          'silent': true,
        },
        sound: null, // No sound for typing indicators
        badge: 0, // No badge for silent notifications
        encrypted: true,
        checksum: checksum,
      );
    } catch (e) {
      print('🔔 SimpleNotificationService: Error sending typing indicator: $e');
      return false;
    }
  }

  /// Send encrypted online status update
  Future<bool> sendOnlineStatusUpdate({
    required String recipientId,
    required bool isOnline,
    required String lastSeen,
    required String encryptedData,
    required String checksum,
  }) async {
    try {
      return await sendNotificationToSession(
        sessionId: recipientId,
        title: '', // Empty title for silent notification
        body: '', // Empty body for silent notification
        data: {
          'data': encryptedData,
          'type': 'online_status_update',
          'silent': true,
        },
        sound: null, // No sound for status updates
        badge: 0, // No badge for silent notifications
        encrypted: true,
        checksum: checksum,
      );
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error sending online status update: $e');
      return false;
    }
  }
}
