import 'package:flutter/foundation.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/socket_guard_service.dart';
import 'package:sechat_app/features/chat/services/message_storage_service.dart';
import 'package:sechat_app/features/chat/models/message.dart' as msg;
import 'package:sechat_app/core/services/encryption_service.dart';

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
      print(
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
        print('📤 UnifiedMessageService: ✅ Message encrypted successfully');
      } catch (e) {
        print('📤 UnifiedMessageService: ❌ Failed to encrypt message: $e');
        return MessageSendResult.failure('Failed to encrypt message: $e');
      }

      // Create API-compliant payload with encrypted body
      final payload = {
        'type': 'message:send', // Required by current server
        'messageId': messageId,
        'conversationId':
            senderConversationId, // Server expects sender's sessionId per updated API docs
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
        // Store the encrypted message in database for security
        final encryptedMessage = msg.Message(
          id: messageId,
          conversationId:
              senderConversationId, // Store locally with sender's ID per bidirectional system
          senderId: _sessionService.currentSessionId ?? '',
          recipientId: recipientId,
          type: msg.MessageType.text,
          content: {
            'text':
                encryptedResult['data']!, // Store encrypted text in database
            'decryptedText': body, // Store decrypted text for quick access
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
        print(
            '📤 UnifiedMessageService: ✅ Encrypted message saved to database: $messageId');

        // Notify listeners for outgoing message
        print(
            '📤 UnifiedMessageService: 🔔 Calling notifyListeners() for outgoing message on instance: ${this.hashCode}');
        print('📤 UnifiedMessageService: 🔍 Has listeners: ${hasListeners}');
        notifyListeners();
        print(
            '📤 UnifiedMessageService: ✅ notifyListeners() called for outgoing message');
      } catch (e) {
        print(
            '📤 UnifiedMessageService: ⚠️ Failed to save message to database: $e');
        // Continue with sending even if database save fails
      }

      // Send via socket service
      final success = await _sendViaSocket(payload);

      if (success) {
        _messageStates[messageId]?.status = msg.MessageStatus.sent;
        print(
            '📤 UnifiedMessageService: ✅ Message sent successfully: $messageId');
        return MessageSendResult.success();
      } else {
        return MessageSendResult.failure('Socket send failed');
      }
    } catch (e) {
      print('📤 UnifiedMessageService: ❌ Error sending message: $e');
      return MessageSendResult.failure('Failed to send message: $e');
    }
  }

  /// Send message via socket with retry logic
  Future<bool> _sendViaSocket(Map<String, dynamic> payload) async {
    try {
      // Use the existing SeSocketService.sendMessage method
      _socketService.sendMessage(
        messageId: payload['messageId'],
        recipientId: payload['toUserIds']
            [0], // Get recipient from toUserIds array
        body: payload['body'],
        conversationId: null, // Let SeSocketService handle conversationId
      );

      return true;
    } catch (e) {
      print('📤 UnifiedMessageService: Socket send error: $e');
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
    // CRITICAL: Use sender's ID as conversation ID per bidirectional system
    // Each user maintains their own conversation folder with the other person's messages
    final senderConversationId = _sessionService.currentSessionId ?? '';
    final fromUserId = _sessionService.currentSessionId ?? '';

    return msg.Message(
      id: messageId,
      conversationId:
          senderConversationId, // Use sender's ID as conversation ID per bidirectional system
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
      print(
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
      print(
          '📤 UnifiedMessageService: 📥 Handling incoming message: $messageId');

      String decryptedBody = body;

      // CRITICAL: Decrypt message if it's encrypted
      if (isEncrypted && body.isNotEmpty) {
        try {
          final decryptedData =
              await EncryptionService.decryptAesCbcPkcs7(body);
          if (decryptedData != null && decryptedData.containsKey('text')) {
            decryptedBody = decryptedData['text'] as String;
            print('📤 UnifiedMessageService: ✅ Message decrypted successfully');
          } else {
            print(
                '📤 UnifiedMessageService: ⚠️ Failed to decrypt message or invalid format');
            decryptedBody = '[Encrypted Message]'; // Fallback
          }
        } catch (e) {
          print('📤 UnifiedMessageService: ❌ Failed to decrypt message: $e');
          decryptedBody = '[Encrypted Message]'; // Fallback
        }
      }

      // CRITICAL: For incoming messages, conversation ID should be the SENDER's ID
      // This implements the bidirectional conversation system where each user maintains their own folder
      final senderConversationId = fromUserId;

      // Create message object for incoming message - store ENCRYPTED in database
      final message = msg.Message(
        id: messageId,
        conversationId:
            senderConversationId, // Use sender's ID as conversation ID per bidirectional system
        senderId: fromUserId,
        recipientId: _sessionService.currentSessionId ?? '',
        type: msg.MessageType.text,
        content: {
          'text': body, // Store encrypted text in database
          'decryptedText':
              decryptedBody, // Store decrypted text for quick access
          'checksum': checksum, // Integrity check
        },
        status: msg.MessageStatus.delivered,
        timestamp: timestamp,
        deliveredAt: DateTime.now(),
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
      print(
          '📤 UnifiedMessageService: ✅ Incoming message saved to database: $messageId');

      // Notify listeners
      print(
          '📤 UnifiedMessageService: 🔔 Calling notifyListeners() for incoming message on instance: ${this.hashCode}');
      print('📤 UnifiedMessageService: 🔍 Has listeners: ${hasListeners}');
      notifyListeners();
      print('📤 UnifiedMessageService: ✅ notifyListeners() called');
    } catch (e) {
      print(
          '📤 UnifiedMessageService: ❌ Failed to handle incoming message: $e');
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
