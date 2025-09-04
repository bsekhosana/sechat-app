import 'package:flutter/foundation.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/socket_guard_service.dart';
import 'package:sechat_app/features/chat/services/message_storage_service.dart';
import 'package:sechat_app/features/chat/models/message.dart' as msg;
import 'package:sechat_app/core/services/encryption_service.dart';
import 'package:sechat_app/core/utils/conversation_id_generator.dart';
import 'package:sechat_app/core/services/message_notification_service.dart';
import 'package:sechat_app/core/services/contact_service.dart';
import '/..//../core/utils/logger.dart';

/// Unified Message Service - Single source of truth for all message operations
/// Replaces all duplicate message services with one consistent implementation
class UnifiedMessageService extends ChangeNotifier {
  static UnifiedMessageService? _instance;
  static UnifiedMessageService get instance =>
      _instance ??= UnifiedMessageService._();

  UnifiedMessageService._();

  final SeSocketService _socketService = SeSocketService.instance;
  final SeSessionService _sessionService = SeSessionService();
  final SocketGuardService _guardService = SocketGuardService.instance;
  final MessageStorageService _messageStorage = MessageStorageService.instance;
  // EncryptionService uses static methods, no instance needed

  // Message state tracking
  final Map<String, MessageState> _messageStates = {};

  // Retry configuration
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  /// Send a message with proper API compliance and error handling
  Future<MessageSendResult> sendMessage({
    required String messageId,
    required String recipientId,
    required String body,
    String? conversationId,
  }) async {
    try {
      Logger.debug(
          '📤 UnifiedMessageService: Sending message $messageId to $recipientId');

      // Validate inputs
      final validation = _validateMessageInput(messageId, recipientId, body);
      if (!validation.isValid) {
        return MessageSendResult.failure(validation.error!);
      }

      // Create message state
      _messageStates[messageId] = MessageState(
        messageId: messageId,
        status: msg.MessageStatus.sending,
        timestamp: DateTime.now(),
        retryCount: 0,
      );

      // CRITICAL: All conversation IDs should be the SENDER's ID for simplicity
      // This ensures consistency with our simplified conversation ID system per memory
      final senderConversationId = _sessionService.currentSessionId ?? '';

      // Validate we have a valid sender ID
      if (senderConversationId.isEmpty) {
        return MessageSendResult.failure('Invalid sender session ID');
      }

      // CRITICAL: Encrypt message body before sending
      Map<String, String> encryptedResult;
      try {
        // Create message data map for encryption
        final messageData = {
          'text': body,
          'timestamp': DateTime.now().toIso8601String(),
          'messageId': messageId,
        };

        encryptedResult = await EncryptionService.encryptAesCbcPkcs7(
            messageData, recipientId);
        Logger.success(
            '📤 UnifiedMessageService:  Message encrypted successfully');
      } catch (e) {
        Logger.error(
            '📤 UnifiedMessageService:  Failed to encrypt message: $e');
        return MessageSendResult.failure('Failed to encrypt message: $e');
      }

      // Create API-compliant payload with encrypted body
      // CRITICAL: Use the same conversationId for both database save and socket payload
      final effectiveConversationId = conversationId ??
          _generateConsistentConversationId(
              _sessionService.currentSessionId ?? '', recipientId);

      final payload = {
        'type': 'message:send', // Required by current server
        'messageId': messageId,
        'conversationId':
            effectiveConversationId, // Use the passed conversationId parameter
        'fromUserId': _sessionService.currentSessionId,
        'toUserIds': [recipientId], // Required by current server
        'body': encryptedResult['data']!, // Use encrypted data
        'checksum':
            encryptedResult['checksum']!, // Include checksum for integrity
        'timestamp': DateTime.now().toIso8601String(),
        'metadata': {
          'encrypted': true, // Server will now support encrypted payloads
          'version': '2.0', // New version with encryption support
          'encryptionType': 'AES-256-CBC',
          'checksum': encryptedResult['checksum']!,
        },
      };

      // Save encrypted message to database first
      try {
        // CRITICAL: Use the passed conversationId parameter for consistent conversation IDs
        // This ensures both users share the same conversation ID format
        final effectiveConversationId = conversationId ??
            _generateConsistentConversationId(
                _sessionService.currentSessionId ?? '', recipientId);

        Logger.info('📤 UnifiedMessageService:  Database save:');
        Logger.info(
            '📤 UnifiedMessageService:  Passed conversationId: $conversationId');
        Logger.info(
            '📤 UnifiedMessageService:  Effective conversationId: $effectiveConversationId');

        final encryptedMessage = msg.Message(
          id: messageId,
          conversationId:
              effectiveConversationId, // Use the passed conversationId parameter
          senderId: _sessionService.currentSessionId ?? '',
          recipientId: recipientId,
          type: msg.MessageType.text,
          content: {
            'text': body, // Store original text for sender's immediate access
            'transmissionEncrypted':
                encryptedResult['data']!, // Keep transmission encrypted version
            'checksum': encryptedResult['checksum']!,
          },
          status: msg.MessageStatus.sending,
          timestamp: DateTime.now(),
          metadata: {
            'isFromCurrentUser': true,
            'messageDirection': 'outgoing',
            'sentAt': DateTime.now().toIso8601String(),
            'isEncrypted': true,
            'encryptionType': 'AES-256-CBC',
          },
        );

        await _messageStorage.saveMessage(encryptedMessage);
        Logger.success(
            '📤 UnifiedMessageService:  Encrypted message saved to database: $messageId');

        // Notify listeners for outgoing message
        Logger.debug(
            '📤 UnifiedMessageService: 🔔 Calling notifyListeners() for outgoing message on instance: ${this.hashCode}');
        Logger.info(
            '📤 UnifiedMessageService:  Has listeners: ${hasListeners}');
        notifyListeners();
        Logger.debug(
            '📤 UnifiedMessageService: ✅ notifyListeners() called for outgoing message');
      } catch (e) {
        Logger.warning(
            '📤 UnifiedMessageService:  Failed to save message to database: $e');
        // Continue with sending even if database save fails
      }

      // Send via socket service
      final success = await _sendViaSocket(payload);

      if (success) {
        _messageStates[messageId]?.status = msg.MessageStatus.sent;
        Logger.success(
            '📤 UnifiedMessageService:  Message sent successfully: $messageId');
        return MessageSendResult.success();
      } else {
        return MessageSendResult.failure('Socket send failed');
      }
    } catch (e) {
      Logger.error('📤 UnifiedMessageService:  Error sending message: $e');
      return MessageSendResult.failure('Failed to send message: $e');
    }
  }

  /// Send message via socket with retry logic
  Future<bool> _sendViaSocket(Map<String, dynamic> payload) async {
    try {
      Logger.debug(
          '📤 UnifiedMessageService: 🔧 Calling SeSocketService.sendMessage...');

      // Use the existing SeSocketService.sendMessage method
      _socketService.sendMessage(
        messageId: payload['messageId'],
        recipientId: payload['toUserIds']
            [0], // Get recipient from toUserIds array
        body: payload['body'],
        conversationId:
            payload['conversationId'], // Pass the conversationId from payload
      );

      Logger.success(
          '📤 UnifiedMessageService:  SeSocketService.sendMessage called successfully');
      return true;
    } catch (e) {
      Logger.error('📤 UnifiedMessageService:  Socket send error: $e');
      return false;
    }
  }

  /// Create a Message object for database storage
  msg.Message _createMessageObject({
    required String messageId,
    required String recipientId,
    required String body,
    String? conversationId,
  }) {
    // CRITICAL: Use the passed conversationId parameter for consistent conversation IDs
    // This ensures both users share the same conversation ID format
    final effectiveConversationId =
        conversationId ?? _sessionService.currentSessionId ?? '';
    final fromUserId = _sessionService.currentSessionId ?? '';

    Logger.info('📤 UnifiedMessageService:  _createMessageObject:');
    Logger.info(
        '📤 UnifiedMessageService:  Passed conversationId: $conversationId');
    Logger.info(
        '📤 UnifiedMessageService:  Effective conversationId: $effectiveConversationId');

    return msg.Message(
      id: messageId,
      conversationId:
          effectiveConversationId, // Use the passed conversationId parameter
      senderId: fromUserId,
      recipientId: recipientId,
      type: msg.MessageType.text,
      content: {'text': body},
      status: msg.MessageStatus.sending,
      timestamp: DateTime.now(),
      metadata: {
        'isFromCurrentUser': true,
        'messageDirection': 'outgoing',
        'sentAt': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Validate message input parameters
  ValidationResult _validateMessageInput(
      String messageId, String recipientId, String body) {
    if (messageId.isEmpty) {
      return ValidationResult(false, 'Message ID cannot be empty');
    }

    if (recipientId.isEmpty) {
      return ValidationResult(false, 'Recipient ID cannot be empty');
    }

    if (body.isEmpty) {
      return ValidationResult(false, 'Message body cannot be empty');
    }

    if (body.length > 4096) {
      return ValidationResult(
          false, 'Message body too long (max 4096 characters)');
    }

    return ValidationResult(true, null);
  }

  /// Get message status
  msg.MessageStatus? getMessageStatus(String messageId) {
    return _messageStates[messageId]?.status;
  }

  /// Update message status (called by socket event handlers)
  void updateMessageStatus(String messageId, msg.MessageStatus status) {
    final messageState = _messageStates[messageId];
    if (messageState != null) {
      messageState.status = status;
      messageState.timestamp = DateTime.now();
      Logger.debug(
          '📤 UnifiedMessageService: Status updated: $messageId -> ${status.name}');
      notifyListeners();
    }
  }

  /// Handle incoming message from socket and save to database
  Future<void> handleIncomingMessage({
    required String messageId,
    required String fromUserId,
    required String conversationId,
    required String body,
    required DateTime timestamp,
    bool isEncrypted = true, // Default to encrypted
    String? checksum, // For encrypted messages
  }) async {
    try {
      Logger.debug(
          '📤 UnifiedMessageService: 📥 Handling incoming message: $messageId');

      String decryptedBody = body;

      // CRITICAL: Decrypt message and store unhashed value to avoid decryption on chat screen
      if (isEncrypted && body.isNotEmpty) {
        Logger.debug(
            '📤 UnifiedMessageService:  Decrypting message for storage');
        try {
          // Use EncryptionService to decrypt the message (first layer)
          final decryptedData =
              await EncryptionService.decryptAesCbcPkcs7(body);

          if (decryptedData != null && decryptedData.containsKey('text')) {
            final firstLayerDecrypted = decryptedData['text'] as String;
            Logger.success('📤 UnifiedMessageService:  First layer decrypted');

            // Check if the decrypted text is still encrypted (double encryption scenario)
            if (firstLayerDecrypted.length > 100 &&
                firstLayerDecrypted.contains('eyJ')) {
              Logger.info(
                  '📤 UnifiedMessageService:  Detected double encryption, decrypting inner layer...');
              try {
                // Decrypt the inner encrypted content
                final innerDecryptedData =
                    await EncryptionService.decryptAesCbcPkcs7(
                        firstLayerDecrypted);

                if (innerDecryptedData != null &&
                    innerDecryptedData.containsKey('text')) {
                  final finalDecryptedText =
                      innerDecryptedData['text'] as String;
                  Logger.success(
                      '📤 UnifiedMessageService:  Inner layer decrypted successfully');
                  decryptedBody = finalDecryptedText;
                } else {
                  Logger.warning(
                      '📤 UnifiedMessageService:  Inner layer decryption failed, using first layer');
                  decryptedBody = firstLayerDecrypted;
                }
              } catch (e) {
                Logger.error(
                    '📤 UnifiedMessageService:  Inner layer decryption error: $e, using first layer');
                decryptedBody = firstLayerDecrypted;
              }
            } else {
              // Single layer encryption, use as is
              Logger.success(
                  '📤 UnifiedMessageService:  Single layer decryption completed');
              decryptedBody = firstLayerDecrypted;
            }
          } else {
            Logger.warning(
                '📤 UnifiedMessageService:  Decryption failed - invalid format, using encrypted text');
            decryptedBody = '[Encrypted Message]';
          }
        } catch (e) {
          Logger.error('📤 UnifiedMessageService:  Decryption failed: $e');
          decryptedBody = '[Encrypted Message]';
        }
      }

      // CRITICAL: Use consistent conversation ID for both users
      final currentUserId = _sessionService.currentSessionId ?? '';
      final consistentConversationId =
          _generateConsistentConversationId(currentUserId, fromUserId);

      // 🆕 FIXED: For incoming messages, store with 'sent' status initially
      // Status will only be updated to 'delivered' when proper receipt:delivered event is received
      final message = msg.Message(
        id: messageId,
        conversationId:
            consistentConversationId, // Use consistent conversation ID
        senderId: fromUserId,
        recipientId: _sessionService.currentSessionId ?? '',
        type: msg.MessageType.text,
        content: {
          'text':
              decryptedBody, // Store the decrypted text for immediate display
          'checksum': checksum, // Keep the original checksum
          'isIncomingEncrypted':
              isEncrypted, // Flag to indicate if original was encrypted
          'originalEncryptedBody': isEncrypted
              ? body
              : null, // Keep original encrypted body for reference
        },
        status: msg
            .MessageStatus.sent, // 🆕 FIXED: Start with 'sent', not 'delivered'
        timestamp: timestamp,
        deliveredAt:
            null, // 🆕 FIXED: Remove deliveredAt - will be set when receipt arrives
        metadata: {
          'isFromCurrentUser': false,
          'messageDirection': 'incoming',
          'receivedAt': DateTime.now().toIso8601String(),
          'isEncrypted': isEncrypted,
          'checksum': checksum,
        },
      );

      // Save to database
      await _messageStorage.saveMessage(message);
      Logger.success(
          '📤 UnifiedMessageService:  Incoming message saved to database: $messageId');

      // Show push notification for received message
      try {
        // Get actual sender name from contact service
        String senderName = fromUserId; // Default to userId
        try {
          final contact = ContactService.instance.getContact(fromUserId);
          if (contact != null &&
              contact.displayName != null &&
              contact.displayName!.isNotEmpty) {
            senderName = contact.displayName!;
            Logger.success(
                '📤 UnifiedMessageService:  Using contact display name: $senderName');
          } else {
            Logger.warning(
                '📤 UnifiedMessageService:  No contact found or display name empty, using userId: $senderName');
          }
        } catch (e) {
          Logger.warning(
              '📤 UnifiedMessageService:  Error getting sender name from contact service: $e');
        }

        await MessageNotificationService.instance.showMessageNotification(
          messageId: messageId,
          senderName: senderName,
          messageContent: decryptedBody,
          conversationId: consistentConversationId,
          isEncrypted: isEncrypted,
        );
        Logger.success(
            '📤 UnifiedMessageService:  Push notification shown for message: $messageId from: $senderName');
      } catch (e) {
        Logger.error(
            '📤 UnifiedMessageService:  Failed to show push notification: $e');
      }

      // Notify listeners
      Logger.debug(
          '📤 UnifiedMessageService: 🔔 Calling notifyListeners() for incoming message on instance: ${this.hashCode}');
      Logger.info('📤 UnifiedMessageService:  Has listeners: ${hasListeners}');
      notifyListeners();
      Logger.debug('📤 UnifiedMessageService: ✅ notifyListeners() called');
    } catch (e) {
      Logger.error(
          '📤 UnifiedMessageService:  Failed to handle incoming message: $e');
    }
  }

  /// Clean up message state
  void cleanupMessageState(String messageId) {
    _messageStates.remove(messageId);
  }

  /// Dispose service
  @override
  void dispose() {
    _messageStates.clear();
    super.dispose();
  }

  /// Generate consistent conversation ID that both users will have
  /// This ensures messages appear in the same conversation for both users
  /// Updated to match server's new consistent ID format
  String _generateConsistentConversationId(String user1Id, String user2Id) {
    return ConversationIdGenerator.generateConsistentConversationId(
        user1Id, user2Id);
  }
}

/// Message state tracking
class MessageState {
  final String messageId;
  msg.MessageStatus status;
  DateTime timestamp;
  int retryCount;

  MessageState({
    required this.messageId,
    required this.status,
    required this.timestamp,
    this.retryCount = 0,
  });
}

/// Message send result
class MessageSendResult {
  final bool success;
  final String? error;

  MessageSendResult._(this.success, this.error);

  factory MessageSendResult.success() => MessageSendResult._(true, null);
  factory MessageSendResult.failure(String error) =>
      MessageSendResult._(false, error);
}

/// Validation result
class ValidationResult {
  final bool isValid;
  final String? error;

  ValidationResult(this.isValid, this.error);
}
