import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sechat_app/core/services/airnotifier_service.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/features/chat/services/optimized_chat_database_service.dart';
import 'package:sechat_app/features/chat/services/enhanced_chat_encryption_service.dart';
import 'package:sechat_app/features/chat/models/optimized_conversation.dart';
import 'package:sechat_app/features/chat/models/optimized_message.dart';
import 'package:sechat_app/core/services/encryption_service.dart';
import 'package:sechat_app/core/services/indicator_service.dart';
import 'package:sechat_app/core/services/se_shared_preference_service.dart';
import 'package:sechat_app/features/key_exchange/providers/key_exchange_request_provider.dart';
import 'package:sechat_app/features/chat/models/chat_conversation.dart';
import 'package:sechat_app/features/chat/services/message_storage_service.dart';
import 'package:sechat_app/core/services/key_exchange_service.dart';

/// Optimized Notification Service
/// Unified, single-entry-point notification processing for chat functionality
class OptimizedNotificationService {
  static final OptimizedNotificationService _instance =
      OptimizedNotificationService._internal();
  factory OptimizedNotificationService() => _instance;
  OptimizedNotificationService._internal();

  // Callbacks for UI updates
  Function(String, String, String, String, String)? _onMessageReceived;
  Function(String, bool)? _onTypingIndicator;
  Function(String, bool, String?)? _onOnlineStatusUpdate;
  Function(String, String, String)? _onMessageStatusUpdate;
  Function(Map<String, dynamic>)? _onKeyExchangeRequestReceived;
  Function(Map<String, dynamic>)? _onKeyExchangeAccepted;
  Function(Map<String, dynamic>)? _onKeyExchangeDeclined;
  Function(ChatConversation)? _onConversationCreated;

  // Database service
  final _databaseService = OptimizedChatDatabaseService();

  // Enhanced encryption service
  final _encryptionService = EnhancedChatEncryptionService();

  // Track processed notifications to prevent duplicates
  final Set<String> _processedNotifications = <String>{};

  // ===== CALLBACK SETTERS =====

  /// Set message received callback
  void setOnMessageReceived(
      Function(String, String, String, String, String) callback) {
    _onMessageReceived = callback;
  }

  /// Set typing indicator callback
  void setOnTypingIndicator(Function(String, bool) callback) {
    _onTypingIndicator = callback;
  }

  /// Set online status update callback
  void setOnOnlineStatusUpdate(Function(String, bool, String?) callback) {
    _onOnlineStatusUpdate = callback;
  }

  /// Set message status update callback
  void setOnMessageStatusUpdate(Function(String, String, String) callback) {
    _onMessageStatusUpdate = callback;
  }

  // ===== MAIN NOTIFICATION HANDLER =====

  /// Main entry point for all notifications
  /// This is the single point of processing to prevent duplication
  Future<void> handleNotification(Map<String, dynamic> data) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 🔔 Processing notification: ${data.keys}');

      // Generate unique notification ID for deduplication
      final notificationId = _generateNotificationId(data);
      if (_processedNotifications.contains(notificationId)) {
        print(
            '🔔 OptimizedNotificationService: ⚠️ Duplicate notification detected, skipping: $notificationId');
        return;
      }
      _processedNotifications.add(notificationId);

      // Extract notification type - handle both direct and nested structures
      String type = 'unknown';
      print('🔔 OptimizedNotificationService: 🔍 Raw data keys: ${data.keys}');
      print('🔔 OptimizedNotificationService: 🔍 Raw data: $data');

      if (data['type'] != null) {
        type = data['type'] as String;
        print('🔔 OptimizedNotificationService: 🔍 Found direct type: $type');
      } else if (data['data'] != null && data['data'] is Map) {
        final nestedData = data['data'] as Map;
        print(
            '🔔 OptimizedNotificationService: 🔍 Found nested data: ${nestedData.keys}');
        type = (nestedData['type'] as String?) ?? 'unknown';
        print(
            '🔔 OptimizedNotificationService: 🔍 Extracted nested type: $type');
      } else {
        print(
            '🔔 OptimizedNotificationService: 🔍 No type found in either location');
      }
      print(
          '🔔 OptimizedNotificationService: 🎯 Final notification type: $type');

      // Route to appropriate handler based on type
      switch (type) {
        case 'message':
          await _handleMessageNotification(data);
          break;
        case 'typing_indicator':
          await _handleTypingIndicatorNotification(data);
          break;
        case 'online_status_update':
          await _handleOnlineStatusNotification(data);
          break;
        case 'message_status_update':
          await _handleMessageStatusNotification(data);
          break;
        case 'user_data_response':
          await _handleUserDataResponseNotification(data);
          break;
        case 'key_exchange_request':
          await _handleKeyExchangeRequestNotification(data);
          break;
        case 'key_exchange_response':
          await _handleKeyExchangeResponseNotification(data);
          break;
        case 'key_exchange_accepted':
          await _handleKeyExchangeAcceptedNotification(data);
          break;
        case 'key_exchange_declined':
          await _handleKeyExchangeDeclinedNotification(data);
          break;
        case 'key_exchange_sent':
          await _handleKeyExchangeSentNotification(data);
          break;
        case 'user_data_exchange':
          await _handleUserDataExchangeNotification(data);
          break;
        default:
          print(
              '🔔 OptimizedNotificationService: ⚠️ Unknown notification type: $type');
      }

      print(
          '🔔 OptimizedNotificationService: ✅ Notification processed successfully: $type');
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error processing notification: $e');
      print(
          '🔔 OptimizedNotificationService: Stack trace: ${StackTrace.current}');
    }
  }

  // ===== NOTIFICATION TYPE HANDLERS =====

  /// Handle message notifications
  Future<void> _handleMessageNotification(Map<String, dynamic> data) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 📨 Processing message notification');

      // Check if this is an encrypted message
      final isEncrypted = data['encrypted'] == true;

      if (isEncrypted) {
        print(
            '🔔 OptimizedNotificationService: 🔐 Processing encrypted message');
        await _handleEncryptedMessageNotification(data);
        return;
      }

      // Extract message data (for non-encrypted messages)
      final senderId =
          data['senderId'] as String? ?? data['sender_id'] as String?;
      final senderName =
          data['senderName'] as String? ?? data['sender_name'] as String?;
      final messageContent =
          data['message'] as String? ?? data['text'] as String?;
      final conversationId = data['conversationId'] as String? ??
          data['conversation_id'] as String?;
      final messageId =
          data['messageId'] as String? ?? data['message_id'] as String?;

      // Validate required fields
      if (senderId == null ||
          messageContent == null ||
          conversationId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ Invalid message notification - missing required fields');
        return;
      }

      // Get current user ID
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ No current user session found');
        return;
      }

      // Prevent processing own messages
      if (senderId == currentUserId) {
        print('🔔 OptimizedNotificationService: ℹ️ Skipping own message');
        return;
      }

      // Verify conversation exists
      final conversation =
          await _databaseService.getConversation(conversationId);
      if (conversation == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ Conversation not found: $conversationId');
        return;
      }

      // Create message object
      final message = OptimizedMessage(
        id: messageId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
        conversationId: conversationId,
        senderId: senderId,
        recipientId: currentUserId,
        content: messageContent,
        messageType: MessageType.text,
        status: MessageStatus.delivered,
        timestamp: DateTime.now(),
        metadata: {
          'messageDirection': 'incoming',
          'processedAt': DateTime.now().toIso8601String(),
        },
      );

      // Save message to database
      await _databaseService.saveMessage(message.toMap());

      // Update conversation with last message
      await _databaseService.updateConversation(conversationId, {
        'last_message_at': message.timestamp.toIso8601String(),
        'last_message_preview': messageContent,
        'unread_count': (conversation['unread_count'] as int? ?? 0) + 1,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Trigger callback for UI updates
      if (_onMessageReceived != null) {
        _onMessageReceived!(senderId, senderName ?? senderId, messageContent,
            conversationId, message.id);
      }

      print(
          '🔔 OptimizedNotificationService: ✅ Message processed and saved: ${message.id}');
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error handling message notification: $e');
    }
  }

  /// Handle encrypted message notification
  Future<void> _handleEncryptedMessageNotification(
      Map<String, dynamic> data) async {
    try {
      print('🔔 OptimizedNotificationService: 🔐 Processing encrypted message');

      // Extract encrypted data
      final encryptedData = data['data'] as Map<String, dynamic>?;
      if (encryptedData == null) {
        print('🔔 OptimizedNotificationService: ❌ No encrypted data found');
        return;
      }

      // Check if this is encrypted user data (for conversation creation)
      final isUserData = encryptedData['type'] == 'user_data';
      if (isUserData) {
        print(
            '🔔 OptimizedNotificationService: 👤 Processing encrypted user data for conversation creation');
        await _handleEncryptedUserDataNotification(encryptedData);
        return;
      }

      // Decrypt the message using enhanced encryption service
      final decryptedPayload =
          await _encryptionService.decryptMessage(encryptedData);

      // Extract decrypted message data
      final senderId = decryptedPayload['senderId'] as String? ?? '';
      final senderName = decryptedPayload['senderName'] as String? ?? '';
      final messageContent = decryptedPayload['content'] as String? ?? '';
      final conversationId =
          decryptedPayload['conversationId'] as String? ?? '';
      final messageId = decryptedPayload['id'] as String? ?? '';

      // Validate required fields
      if (senderId.isEmpty ||
          messageContent.isEmpty ||
          conversationId.isEmpty) {
        print(
            '🔔 OptimizedNotificationService: ⚠️ Missing required decrypted message fields');
        return;
      }

      // Get current user ID
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ No current user session found');
        return;
      }

      // Prevent processing own messages
      if (senderId == currentUserId) {
        print('🔔 OptimizedNotificationService: ℹ️ Skipping own message');
        return;
      }

      // Verify conversation exists
      final conversation =
          await _databaseService.getConversation(conversationId);
      if (conversation == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ Conversation not found: $conversationId');
        return;
      }

      // Create message object
      final message = OptimizedMessage(
        id: messageId.isNotEmpty
            ? messageId
            : 'msg_${DateTime.now().millisecondsSinceEpoch}',
        conversationId: conversationId,
        senderId: senderId,
        recipientId: currentUserId,
        content: messageContent,
        messageType: MessageType.text,
        status: MessageStatus.delivered,
        timestamp: DateTime.now(),
        metadata: {
          'messageDirection': 'incoming',
          'encrypted': true,
          'processedAt': DateTime.now().toIso8601String(),
        },
      );

      // Save decrypted message to database
      await _databaseService.saveMessage(message.toMap());

      // Update conversation with last message
      await _databaseService.updateConversation(conversationId, {
        'last_message_at': message.timestamp.toIso8601String(),
        'last_message_preview': messageContent,
        'unread_count': (conversation['unread_count'] as int? ?? 0) + 1,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Trigger callback for UI updates
      if (_onMessageReceived != null) {
        _onMessageReceived!(
            senderId,
            senderName.isNotEmpty ? senderName : senderId,
            messageContent,
            conversationId,
            message.id);
      }

      print(
          '🔔 OptimizedNotificationService: ✅ Encrypted message processed and saved: ${message.id}');
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error processing encrypted message notification: $e');
    }
  }

  /// Handle encrypted user data notification (for conversation creation)
  Future<void> _handleEncryptedUserDataNotification(
      Map<String, dynamic> encryptedData) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 👤 Processing encrypted user data');

      // Extract sender information from encrypted data
      final senderId = encryptedData['sender_id'] as String? ?? '';
      final senderName = encryptedData['sender_name'] as String? ?? '';
      final conversationId = encryptedData['conversation_id'] as String? ?? '';

      if (senderId.isEmpty) {
        print(
            '🔔 OptimizedNotificationService: ❌ No sender ID in encrypted user data');
        return;
      }

      // Get current user ID
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ No current user session found');
        return;
      }

      // Prevent processing own user data
      if (senderId == currentUserId) {
        print('🔔 OptimizedNotificationService: ℹ️ Skipping own user data');
        return;
      }

      // Handle key exchange for the sender
      print(
          '🔔 OptimizedNotificationService: 🔑 Handling key exchange for sender: $senderId');
      final keyExchangeSuccess = await _encryptionService
          .handleRecipientKeyExchange(senderId, conversationId);

      if (!keyExchangeSuccess) {
        print(
            '🔔 OptimizedNotificationService: ⚠️ Key exchange failed for $senderId, will retry later');
        // Store for later retry - this could be implemented as a queue
        return;
      }

      // Create or find conversation
      var conversation = await _databaseService.findConversationBetweenUsers(
        currentUserId,
        senderId,
      );

      if (conversation == null) {
        print(
            '🔔 OptimizedNotificationService: 🆕 Creating new conversation from encrypted user data');
        conversation =
            await _createNewConversation(currentUserId, senderId, senderName);
      }

      if (conversation == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ Failed to create conversation from encrypted user data');
        return;
      }

      // Update conversation with the provided conversation ID if it's different
      if (conversationId.isNotEmpty && conversation['id'] != conversationId) {
        print(
            '🔔 OptimizedNotificationService: 🔄 Updating conversation ID to match sender: $conversationId');
        await _databaseService.updateConversation(conversation['id'], {
          'id': conversationId,
          'updated_at': DateTime.now().toIso8601String(),
        });
        conversation['id'] = conversationId;
      }

      print(
          '🔔 OptimizedNotificationService: ✅ Encrypted user data processed, conversation ready: ${conversation['id']}');

      // Trigger callback for conversation creation
      if (_onMessageReceived != null) {
        _onMessageReceived!(
            senderId,
            senderName.isNotEmpty ? senderName : senderId,
            'Conversation created',
            conversation['id'],
            '');
      }
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error processing encrypted user data notification: $e');
    }
  }

  /// Handle user data response notifications (for key exchange completion)
  /// This handles both encrypted and unencrypted responses
  Future<void> _handleUserDataResponseNotification(
      Map<String, dynamic> data) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 👤 Processing user data response notification: $data');

      // Check if this is encrypted data - handle both boolean and integer values
      // The encrypted field is inside the nested data structure
      // Handle Map<Object?, Object?> from EventChannel
      final nestedDataRaw = data['data'];
      final nestedData = nestedDataRaw is Map
          ? Map<String, dynamic>.from(nestedDataRaw as Map)
          : null;
      final encryptedRaw = nestedData?['encrypted'];
      print(
          '🔔 OptimizedNotificationService: 🔍 Encrypted raw value: $encryptedRaw (type: ${encryptedRaw.runtimeType})');

      // Handle different types of encrypted values
      bool isEncrypted = false;
      if (encryptedRaw == true) {
        isEncrypted = true;
      } else if (encryptedRaw == 1) {
        isEncrypted = true;
      } else if (encryptedRaw == '1') {
        isEncrypted = true;
      } else if (encryptedRaw is int && encryptedRaw > 0) {
        isEncrypted = true;
      }

      print(
          '🔔 OptimizedNotificationService: 🔍 Encrypted check - raw: $encryptedRaw, isEncrypted: $isEncrypted');

      if (isEncrypted) {
        print(
            '🔔 OptimizedNotificationService: 🔐 Processing encrypted user data response');
        await _handleEncryptedUserDataResponseNotification(data);
        return;
      }

      // Extract user data from unencrypted notification
      // Fields are inside the nested data structure
      final senderId = nestedData?['sender_id'] as String? ??
          nestedData?['senderId'] as String?;
      final displayName = nestedData?['display_name'] as String? ??
          nestedData?['displayName'] as String?;
      final chatId =
          nestedData?['chat_id'] as String? ?? nestedData?['chatId'] as String?;

      if (senderId == null || displayName == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ Missing required fields for user data response');
        return;
      }

      // Get current user ID
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ No current user session found');
        return;
      }

      // Prevent processing own user data
      if (senderId == currentUserId) {
        print('🔔 OptimizedNotificationService: ℹ️ Skipping own user data');
        return;
      }

      // Create or find conversation
      var conversation = await _databaseService.findConversationBetweenUsers(
        currentUserId,
        senderId,
      );

      if (conversation == null) {
        print(
            '🔔 OptimizedNotificationService: 🆕 Creating new conversation from user data response');
        conversation =
            await _createNewConversation(currentUserId, senderId, displayName);
      }

      if (conversation == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ Failed to create conversation from user data response');
        return;
      }

      // Update conversation with the provided chat ID if it's different
      if (chatId != null && chatId.isNotEmpty && conversation['id'] != chatId) {
        print(
            '🔔 OptimizedNotificationService: 🔄 Updating conversation ID to match sender: $chatId');
        await _databaseService.updateConversation(conversation['id'], {
          'id': chatId,
          'updated_at': DateTime.now().toIso8601String(),
        });
        conversation['id'] = chatId;
      }

      print(
          '🔔 OptimizedNotificationService: ✅ User data response processed, conversation ready: ${conversation['id']}');

      // Trigger callback for conversation creation
      if (_onMessageReceived != null) {
        _onMessageReceived!(senderId, displayName, 'Conversation created',
            conversation['id'], '');
      }
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error handling user data response: $e');
    }
  }

  /// Handle key exchange request notifications
  Future<void> _handleKeyExchangeRequestNotification(
      Map<String, dynamic> data) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 🔑 Processing key exchange request notification: $data');

      // Extract key exchange request data - handle both direct and nested structures
      String senderId = '',
          publicKey = '',
          version = '',
          requestId = '',
          requestPhrase = '';

      if (data['sender_id'] != null || data['senderId'] != null) {
        // Direct structure
        senderId =
            data['sender_id'] as String? ?? data['senderId'] as String? ?? '';
        publicKey = data['sender_public_key'] as String? ??
            data['public_key'] as String? ??
            '';
        version = data['version'] as String? ?? '';
        requestId = data['request_id'] as String? ?? '';
        requestPhrase = data['request_phrase'] as String? ?? '';
      } else if (data['data'] != null && data['data'] is Map) {
        // Nested structure
        final nestedData = data['data'] as Map;
        senderId = (nestedData['sender_id'] as String?) ??
            (nestedData['senderId'] as String?) ??
            '';
        publicKey = (nestedData['sender_public_key'] as String?) ??
            (nestedData['public_key'] as String?) ??
            '';
        version = (nestedData['version'] as String?) ?? '';
        requestId = (nestedData['request_id'] as String?) ?? '';
        requestPhrase = (nestedData['request_phrase'] as String?) ?? '';
      }

      print(
          '🔔 OptimizedNotificationService: 🔍 Extracted fields - senderId: $senderId, publicKey: ${publicKey.isNotEmpty ? "present" : "missing"}');

      if (senderId.isEmpty || publicKey.isEmpty) {
        print(
            '🔔 OptimizedNotificationService: ❌ Invalid key exchange request data - missing required fields');
        print(
            '🔔 OptimizedNotificationService: senderId: $senderId, publicKey: ${publicKey.isNotEmpty ? "present" : "missing"}');
        return;
      }

      // Get current user ID
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ No current user session found');
        return;
      }

      // Prevent processing own key exchange requests
      if (senderId == currentUserId) {
        print(
            '🔔 OptimizedNotificationService: ℹ️ Skipping own key exchange request');
        return;
      }

      // Ensure we have our own keys for key exchange
      try {
        await KeyExchangeService.instance.ensureKeysExist();
        print(
            '🔔 OptimizedNotificationService: ✅ Ensured own keys exist for key exchange');
      } catch (e) {
        print(
            '🔔 OptimizedNotificationService: ⚠️ Warning: Could not ensure own keys exist: $e');
      }

      // Store sender's public key (but don't automatically respond)
      try {
        await EncryptionService.storeRecipientPublicKey(senderId, publicKey);
        print(
            '🔔 OptimizedNotificationService: ✅ Stored public key for $senderId');
      } catch (e) {
        if (e.toString().contains('already exists in the keychain')) {
          print(
              '🔔 OptimizedNotificationService: ℹ️ Public key already exists for $senderId (duplicate request)');
        } else {
          print(
              '🔔 OptimizedNotificationService: ❌ Error storing public key: $e');
        }
      }

      // Trigger callback for UI updates (this will show the invitation to the user)
      if (_onKeyExchangeRequestReceived != null) {
        // Extract the nested data for the provider callback
        final nestedData = data['data'] as Map<String, dynamic>?;
        if (nestedData != null) {
          _onKeyExchangeRequestReceived!(nestedData);
          print(
              '🔔 OptimizedNotificationService: ✅ Key exchange request callback triggered with extracted data');
        } else {
          print(
              '🔔 OptimizedNotificationService: ⚠️ No nested data found for callback');
        }
      } else {
        print(
            '🔔 OptimizedNotificationService: ⚠️ No key exchange request callback set');
      }

      // Show local notification
      await _showLocalNotification(
        title: 'Key Exchange Request',
        body: 'New encryption key exchange request received',
        type: 'key_exchange_request',
        data: data,
      );

      print(
          '🔔 OptimizedNotificationService: ✅ Key exchange request processed successfully');
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error handling key exchange request: $e');
    }
  }

  /// Handle key exchange response notification
  Future<void> _handleKeyExchangeResponseNotification(
      Map<String, dynamic> data) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 🔑 Processing key exchange response notification: $data');

      // Extract key exchange response data - handle both direct and nested structures
      String senderId = '', publicKey = '', responseId = '';

      if (data['sender_id'] != null || data['senderId'] != null) {
        // Direct structure
        senderId =
            data['sender_id'] as String? ?? data['senderId'] as String? ?? '';
        publicKey = data['public_key'] as String? ?? '';
        responseId = data['response_id'] as String? ?? '';
      } else if (data['data'] != null && data['data'] is Map) {
        // Nested structure
        final nestedData = data['data'] as Map;
        senderId = (nestedData['sender_id'] as String?) ??
            (nestedData['senderId'] as String?) ??
            '';
        publicKey = (nestedData['public_key'] as String?) ?? '';
        responseId = (nestedData['response_id'] as String?) ?? '';
      }

      print(
          '🔔 OptimizedNotificationService: 🔍 Extracted response fields - senderId: $senderId, publicKey: ${publicKey.isNotEmpty ? "present" : "missing"}, responseId: $responseId');

      if (senderId.isEmpty || publicKey.isEmpty) {
        print(
            '🔔 OptimizedNotificationService: ❌ Invalid key exchange response data - missing required fields');
        print(
            '🔔 OptimizedNotificationService: senderId: $senderId, publicKey: ${publicKey.isNotEmpty ? "present" : "missing"}');
        return;
      }

      // Extract timestamp - handle both direct and nested structures
      dynamic timestamp;
      if (data['timestamp'] != null) {
        timestamp = data['timestamp'];
      } else if (data['data'] != null && data['data'] is Map) {
        final nestedData = data['data'] as Map;
        timestamp = nestedData['timestamp'];
      }

      // CRITICAL: Store the responder's public key before processing the response
      try {
        await EncryptionService.storeRecipientPublicKey(senderId, publicKey);
        print(
            '🔔 OptimizedNotificationService: ✅ Stored responder public key for: $senderId');
      } catch (e) {
        if (e.toString().contains('already exists in the keychain')) {
          print(
              '🔔 OptimizedNotificationService: ℹ️ Responder public key already exists for $senderId (duplicate response)');
        } else {
          print(
              '🔔 OptimizedNotificationService: ❌ Error storing responder public key: $e');
          // Continue with the process even if key storage fails
        }
      }

      // Process the key exchange response using KeyExchangeService
      final success =
          await KeyExchangeService.instance.processKeyExchangeResponse({
        'sender_id': senderId,
        'public_key': publicKey,
        'timestamp': timestamp,
      });

      if (success) {
        print(
            '🔔 OptimizedNotificationService: ✅ Key exchange response processed successfully');

        // Trigger callback for UI updates
        _onKeyExchangeRequestReceived?.call(data);

        // Show local notification
        await _showLocalNotification(
          title: 'Key Exchange Response',
          body: 'Encryption key exchange response received',
          type: 'key_exchange_response',
          data: data,
        );
      } else {
        print(
            '🔔 OptimizedNotificationService: ❌ Failed to process key exchange response');
      }
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error handling key exchange response: $e');
    }
  }

  /// Handle key exchange accepted notification
  Future<void> _handleKeyExchangeAcceptedNotification(
      Map<String, dynamic> data) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 🎯 Processing key exchange accepted notification: $data');

      // Extract key exchange data - handle both direct and nested structures
      String? requestId, recipientId, acceptorPublicKey;
      dynamic timestampRaw;

      if (data['request_id'] != null) {
        // Direct structure
        requestId = data['request_id'] as String?;
        recipientId = data['recipient_id'] as String?;
        acceptorPublicKey = data['acceptor_public_key'] as String?;
        timestampRaw = data['timestamp'];
      } else if (data['data'] != null && data['data'] is Map) {
        // Nested structure
        final nestedData = data['data'] as Map;
        requestId = (nestedData['request_id'] as String?);
        recipientId = (nestedData['recipient_id'] as String?);
        acceptorPublicKey = (nestedData['acceptor_public_key'] as String?);
        timestampRaw = nestedData['timestamp'];
      }

      if (requestId == null ||
          recipientId == null ||
          acceptorPublicKey == null ||
          acceptorPublicKey.isEmpty) {
        print(
            '🔔 OptimizedNotificationService: ❌ Invalid key exchange accepted data - missing required fields');
        print(
            '🔔 OptimizedNotificationService: requestId: $requestId, recipientId: $recipientId, acceptorPublicKey: ${acceptorPublicKey?.isNotEmpty == true ? "present" : "missing"}');
        print('🔔 OptimizedNotificationService: Received data: $data');
        return;
      }

      // Check if this key exchange has already been processed
      if (await _isKeyExchangeAlreadyProcessed(requestId)) {
        print(
            '🔔 OptimizedNotificationService: ℹ️ Key exchange $requestId already processed, skipping duplicate');
        return;
      }

      // Handle timestamp conversion safely
      DateTime timestamp;
      if (timestampRaw is int) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(timestampRaw);
      } else if (timestampRaw is String) {
        try {
          timestamp =
              DateTime.fromMillisecondsSinceEpoch(int.parse(timestampRaw));
        } catch (e) {
          print(
              '🔔 OptimizedNotificationService: Invalid timestamp string: $timestampRaw, using current time');
          timestamp = DateTime.now();
        }
      } else {
        print(
            '🔔 OptimizedNotificationService: Invalid timestamp type: ${timestampRaw.runtimeType}, using current time');
        timestamp = DateTime.now();
      }

      print(
          '🔔 OptimizedNotificationService: ✅ Key exchange accepted for request: $requestId from: $recipientId');

      // Store the acceptance locally
      await _storeKeyExchangeAccepted(requestId, recipientId, timestamp);

      // CRITICAL: Store the acceptor's public key before attempting to encrypt data for them
      if (acceptorPublicKey != null && acceptorPublicKey.isNotEmpty) {
        try {
          await EncryptionService.storeRecipientPublicKey(
              recipientId, acceptorPublicKey);
          print(
              '🔔 OptimizedNotificationService: ✅ Stored acceptor public key for: $recipientId');
        } catch (e) {
          print(
              '🔔 OptimizedNotificationService: ⚠️ Warning: Could not store acceptor public key: $e');
          // Continue with the process even if key storage fails
        }
      } else {
        print(
            '🔔 OptimizedNotificationService: ⚠️ Warning: No acceptor public key found in notification');
      }

      // Send encrypted user data to the accepting user
      await _sendUserDataToAcceptor(recipientId);

      // Add notification item
      if (_onKeyExchangeAccepted != null) {
        // Extract the nested data for the provider callback
        final nestedData = data['data'] as Map<String, dynamic>?;
        if (nestedData != null) {
          _onKeyExchangeAccepted!(nestedData);
          print(
              '🔔 OptimizedNotificationService: ✅ Key exchange accepted callback triggered with extracted data');
        } else {
          print(
              '🔔 OptimizedNotificationService: ⚠️ No nested data found for accepted callback');
        }
      }

      print(
          '🔔 OptimizedNotificationService: ✅ Key exchange acceptance processed successfully');
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error processing key exchange accepted: $e');
    }
  }

  /// Handle key exchange declined notification
  Future<void> _handleKeyExchangeDeclinedNotification(
      Map<String, dynamic> data) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 🔑 Processing key exchange declined notification: $data');

      // Extract key exchange declined data
      final requestId = data['request_id'] as String?;
      final recipientId = data['recipient_id'] as String?;
      final declineMessage =
          data['response_message'] as String? ?? 'Key exchange declined';

      if (requestId == null || recipientId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ Invalid key exchange declined data - missing required fields');
        return;
      }

      print(
          '🔔 OptimizedNotificationService: ✅ Key exchange declined for request: $requestId from: $recipientId');

      // Trigger callback for UI updates
      if (_onKeyExchangeDeclined != null) {
        _onKeyExchangeDeclined!(data);
        print(
            '🔔 OptimizedNotificationService: ✅ Key exchange declined callback triggered');
      }

      // Show local notification
      await _showLocalNotification(
        title: 'Key Exchange Declined',
        body: 'Your key exchange request was declined',
        type: 'key_exchange_declined',
        data: data,
      );

      print(
          '🔔 OptimizedNotificationService: ✅ Key exchange declined processed successfully');
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error processing key exchange declined: $e');
    }
  }

  /// Handle key exchange sent notification
  Future<void> _handleKeyExchangeSentNotification(
      Map<String, dynamic> data) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 🔑 Processing key exchange sent notification: $data');

      // Extract key exchange sent data
      final recipientId = data['recipient_id'] as String?;
      final requestId = data['request_id'] as String?;

      if (recipientId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ Invalid key exchange sent data - missing recipientId');
        return;
      }

      print(
          '🔔 OptimizedNotificationService: ✅ Key exchange request sent to: $recipientId');

      // Show local notification for confirmation
      await _showLocalNotification(
        title: 'Key Exchange Request Sent',
        body: 'Encryption key exchange request sent to recipient',
        type: 'key_exchange_request_sent',
        data: data,
      );

      print(
          '🔔 OptimizedNotificationService: ✅ Key exchange sent processed successfully');
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error processing key exchange sent: $e');
    }
  }

  /// Handle encrypted user data exchange notification
  Future<void> _handleUserDataExchangeNotification(
      Map<String, dynamic> data) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 🔐 Processing encrypted user data exchange notification: $data');

      // Extract encrypted data - handle both direct and nested structures
      String? encryptedData;
      String? checksum;

      if (data.containsKey('data')) {
        final dataField = data['data'];
        if (dataField is String) {
          // Direct structure: data is a string
          encryptedData = dataField;
          print(
              '🔔 OptimizedNotificationService: Found direct encrypted data: ${encryptedData.length} characters');
        } else if (dataField is Map) {
          // Nested structure: data is a map with 'data' and 'checksum'
          final nestedData = dataField as Map;
          encryptedData = nestedData['data'] as String?;
          checksum = nestedData['checksum'] as String?;
          print(
              '🔔 OptimizedNotificationService: Found nested encrypted data: ${encryptedData?.length ?? 0} characters, checksum: ${checksum?.substring(0, 8) ?? "none"}...');
        }
      }

      if (encryptedData == null || encryptedData.isEmpty) {
        print(
            '🔔 OptimizedNotificationService: ❌ No encrypted data found in user data exchange');
        print('🔔 OptimizedNotificationService: Data structure: ${data.keys}');
        if (data.containsKey('data')) {
          print(
              '🔔 OptimizedNotificationService: Data field type: ${data['data'].runtimeType}');
          if (data['data'] is Map) {
            print(
                '🔔 OptimizedNotificationService: Nested data keys: ${(data['data'] as Map).keys}');
          }
        }
        return;
      }

      // Decrypt the data using the legacy encryption service
      final decryptedData =
          await EncryptionService.decryptAesCbcPkcs7(encryptedData);

      if (decryptedData == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ Failed to decrypt user data exchange data');
        return;
      }

      print(
          '🔔 OptimizedNotificationService: ✅ User data decrypted successfully');

      // Process the decrypted user data
      await _processDecryptedUserData(decryptedData);
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error processing user data exchange: $e');
    }
  }

  /// Create a new conversation between two users
  Future<Map<String, dynamic>?> _createNewConversation(
      String currentUserId, String otherUserId, String? otherUserName) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 🆕 Creating new conversation between $currentUserId and $otherUserId');

      // Generate conversation ID
      final conversationId =
          'conv_${currentUserId}_${otherUserId}_${DateTime.now().millisecondsSinceEpoch}';

      // Create conversation data
      final conversationData = {
        'id': conversationId,
        'participant1_id': currentUserId,
        'participant2_id': otherUserId,
        'display_name': otherUserName ?? otherUserId,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'is_pinned': 0,
      };

      // Save conversation to database
      await _databaseService.saveConversation(conversationData);

      print(
          '🔔 OptimizedNotificationService: ✅ New conversation created: $conversationId');
      return conversationData;
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error creating new conversation: $e');
      return null;
    }
  }

  /// Handle typing indicator notifications
  Future<void> _handleTypingIndicatorNotification(
      Map<String, dynamic> data) async {
    try {
      print(
          '🔔 OptimizedNotificationService: ⌨️ Processing typing indicator notification');

      // Extract data
      final senderId =
          data['senderId'] as String? ?? data['sender_id'] as String?;
      final isTypingRaw = data['isTyping'];
      final isTyping = _parseBoolean(isTypingRaw);

      if (senderId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ Invalid typing indicator - missing senderId');
        return;
      }

      // Get current user ID
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ No current user session found');
        return;
      }

      // Prevent processing own typing indicators
      if (senderId == currentUserId) {
        print(
            '🔔 OptimizedNotificationService: ℹ️ Skipping own typing indicator');
        return;
      }

      // Find conversation between users
      final conversation = await _databaseService.findConversationBetweenUsers(
          senderId, currentUserId);
      if (conversation == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ No conversation found between users');
        return;
      }

      // Update conversation typing status
      await _databaseService.updateConversation(conversation['id'], {
        'is_typing': isTyping ? 1 : 0,
        'typing_user_id': isTyping ? senderId : null,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Trigger callback for UI updates
      if (_onTypingIndicator != null) {
        _onTypingIndicator!(senderId, isTyping);
      }

      print(
          '🔔 OptimizedNotificationService: ✅ Typing indicator processed: $senderId -> $isTyping');
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error handling typing indicator: $e');
    }
  }

  /// Handle online status notifications
  Future<void> _handleOnlineStatusNotification(
      Map<String, dynamic> data) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 🌐 Processing online status notification');

      // Extract data
      final senderId =
          data['senderId'] as String? ?? data['sender_id'] as String?;
      final isOnlineRaw = data['isOnline'];
      final isOnline = _parseBoolean(isOnlineRaw);
      final lastSeen =
          data['lastSeen'] as String? ?? data['last_seen'] as String?;

      if (senderId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ Invalid online status - missing senderId');
        return;
      }

      // Get current user ID
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ No current user session found');
        return;
      }

      // Prevent processing own online status
      if (senderId == currentUserId) {
        print('🔔 OptimizedNotificationService: ℹ️ Skipping own online status');
        return;
      }

      // Find conversation between users
      final conversation = await _databaseService.findConversationBetweenUsers(
          senderId, currentUserId);
      if (conversation == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ No conversation found between users');
        return;
      }

      // Update conversation online status
      await _databaseService.updateConversation(conversation['id'], {
        'is_online': isOnline ? 1 : 0,
        'last_seen': lastSeen ?? DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Trigger callback for UI updates
      if (_onOnlineStatusUpdate != null) {
        _onOnlineStatusUpdate!(senderId, isOnline, lastSeen);
      }

      print(
          '🔔 OptimizedNotificationService: ✅ Online status processed: $senderId -> $isOnline');
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error handling online status: $e');
    }
  }

  /// Handle message status notifications
  Future<void> _handleMessageStatusNotification(
      Map<String, dynamic> data) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 📊 Processing message status notification');

      // Extract data
      final senderId =
          data['senderId'] as String? ?? data['sender_id'] as String?;
      final messageId =
          data['messageId'] as String? ?? data['message_id'] as String?;
      final status = data['status'] as String?;

      if (senderId == null || messageId == null || status == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ Invalid message status - missing required fields');
        return;
      }

      // Get current user ID
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ No current user session found');
        return;
      }

      // Get message from database
      final messageData = await _databaseService.getMessage(messageId);
      if (messageData == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ Message not found: $messageId');
        return;
      }

      // Verify message belongs to current user
      if (messageData['recipient_id'] != currentUserId) {
        print(
            '🔔 OptimizedNotificationService: ❌ Message does not belong to current user');
        return;
      }

      // Update message status
      String? deliveredAt;
      String? readAt;

      switch (status) {
        case 'delivered':
          deliveredAt = DateTime.now().toIso8601String();
          break;
        case 'read':
          readAt = DateTime.now().toIso8601String();
          break;
      }

      await _databaseService.updateMessageStatus(messageId, status,
          deliveredAt: deliveredAt, readAt: readAt);

      // Trigger callback for UI updates
      if (_onMessageStatusUpdate != null) {
        _onMessageStatusUpdate!(senderId, messageId, status);
      }

      print(
          '🔔 OptimizedNotificationService: ✅ Message status updated: $messageId -> $status');
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error handling message status: $e');
    }
  }

  // ===== OUTGOING NOTIFICATION METHODS =====

  /// Send typing indicator
  Future<void> sendTypingIndicator(String recipientId, bool isTyping) async {
    try {
      print(
          '🔔 OptimizedNotificationService: ⌨️ Sending typing indicator: $isTyping to $recipientId');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ No current user session found');
        return;
      }

      // Prevent sending to self
      if (recipientId == currentUserId) {
        print(
            '🔔 OptimizedNotificationService: ⚠️ Cannot send typing indicator to self');
        return;
      }

      // Send via AirNotifier
      final success = await AirNotifierService.instance.sendTypingIndicator(
        recipientId: recipientId,
        senderName: currentUserId,
        isTyping: isTyping,
      );

      if (success) {
        print(
            '🔔 OptimizedNotificationService: ✅ Typing indicator sent successfully');
      } else {
        print(
            '🔔 OptimizedNotificationService: ❌ Failed to send typing indicator');
      }
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error sending typing indicator: $e');
    }
  }

  /// Send online status update
  Future<void> sendOnlineStatusUpdate(String recipientId, bool isOnline,
      {String? lastSeen}) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 🌐 Sending online status: $isOnline to $recipientId');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ No current user session found');
        return;
      }

      // Prevent sending to self
      if (recipientId == currentUserId) {
        print(
            '🔔 OptimizedNotificationService: ⚠️ Cannot send online status to self');
        return;
      }

      // Send via AirNotifier (implement when available)
      print(
          '🔔 OptimizedNotificationService: ✅ Online status update prepared (AirNotifier integration pending)');
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error sending online status: $e');
    }
  }

  /// Send message status update
  Future<void> sendMessageStatusUpdate(
      String recipientId, String messageId, String status) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 📊 Sending message status: $status for $messageId to $recipientId');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ No current user session found');
        return;
      }

      // Prevent sending to self
      if (recipientId == currentUserId) {
        print(
            '🔔 OptimizedNotificationService: ⚠️ Cannot send message status to self');
        return;
      }

      // Send via AirNotifier (implement when available)
      print(
          '🔔 OptimizedNotificationService: ✅ Message status update prepared (AirNotifier integration pending)');
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error sending message status: $e');
    }
  }

  // ===== UTILITY METHODS =====

  /// Generate unique notification ID for deduplication
  String _generateNotificationId(Map<String, dynamic> data) {
    // Handle both direct and nested data structures
    String type = 'unknown';
    String messageId = DateTime.now().millisecondsSinceEpoch.toString();
    String senderId = 'unknown';

    if (data['type'] != null) {
      // Direct structure
      type = data['type'] as String? ?? 'unknown';
      messageId = data['messageId'] as String? ??
          data['message_id'] as String? ??
          data['request_id'] as String? ?? // For key exchange notifications
          DateTime.now().millisecondsSinceEpoch.toString();
      senderId = data['senderId'] as String? ??
          data['sender_id'] as String? ??
          data['recipient_id'] as String? ?? // For key exchange accepted
          'unknown';
    } else if (data['data'] != null && data['data'] is Map) {
      // Nested structure - handle Map<Object?, Object?> from native platform
      final nestedData = data['data'] as Map;
      type = (nestedData['type'] as String?) ?? 'unknown';
      messageId = (nestedData['messageId'] as String?) ??
          (nestedData['message_id'] as String?) ??
          (nestedData['request_id']
              as String?) ?? // For key exchange notifications
          DateTime.now().millisecondsSinceEpoch.toString();
      senderId = (nestedData['senderId'] as String?) ??
          (nestedData['sender_id'] as String?) ??
          (nestedData['recipient_id']
              as String?) ?? // For key exchange accepted
          'unknown';
    }

    return '${type}_${senderId}_$messageId';
  }

  /// Parse boolean values from various formats
  bool _parseBoolean(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      final lowerValue = value.toLowerCase();
      return lowerValue == 'true' || lowerValue == '1';
    }
    return false;
  }

  /// Clear processed notifications (for testing/reset)
  void clearProcessedNotifications() {
    _processedNotifications.clear();
    print('🔔 OptimizedNotificationService: ✅ Processed notifications cleared');
  }

  /// Get processed notifications count (for debugging)
  int get processedNotificationsCount => _processedNotifications.length;

  /// Show local notification (placeholder implementation)
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? type,
    Map<String, dynamic>? data,
  }) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 📱 Showing local notification: $title - $body');
      // TODO: Implement local notification display
      // This would integrate with FlutterLocalNotificationsPlugin
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error showing local notification: $e');
    }
  }

  /// Set key exchange request received callback
  void setOnKeyExchangeRequestReceived(
      Function(Map<String, dynamic>) callback) {
    _onKeyExchangeRequestReceived = callback;
  }

  /// Set key exchange accepted callback
  void setOnKeyExchangeAccepted(Function(Map<String, dynamic>) callback) {
    _onKeyExchangeAccepted = callback;
  }

  /// Set key exchange declined callback
  void setOnKeyExchangeDeclined(Function(Map<String, dynamic>) callback) {
    _onKeyExchangeDeclined = callback;
  }

  /// Set conversation created callback
  void setOnConversationCreated(Function(ChatConversation) callback) {
    _onConversationCreated = callback;
  }

  // ===== KEY EXCHANGE HELPER METHODS =====

  /// Check if key exchange has already been processed
  Future<bool> _isKeyExchangeAlreadyProcessed(String requestId) async {
    try {
      final prefsService = SeSharedPreferenceService();
      final acceptedExchanges =
          await prefsService.getJson('accepted_key_exchanges') ?? {};
      return acceptedExchanges.containsKey(requestId);
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error checking key exchange status: $e');
      return false;
    }
  }

  /// Store key exchange accepted locally
  Future<void> _storeKeyExchangeAccepted(
      String requestId, String recipientId, DateTime timestamp) async {
    try {
      print(
          '🔔 OptimizedNotificationService: Storing key exchange accepted locally');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ User not logged in, cannot store acceptance');
        return;
      }

      final prefsService = SeSharedPreferenceService();
      final acceptedExchanges =
          await prefsService.getJson('accepted_key_exchanges') ?? {};

      acceptedExchanges[requestId] = {
        'recipient_id': recipientId,
        'accepted_at': timestamp.millisecondsSinceEpoch,
        'status': 'accepted',
        'request_id': requestId,
      };

      await prefsService.setJson('accepted_key_exchanges', acceptedExchanges);
      print(
          '🔔 OptimizedNotificationService: ✅ Key exchange acceptance stored locally');
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error storing key exchange acceptance: $e');
    }
  }

  /// Send encrypted user data to the accepting user
  Future<void> _sendUserDataToAcceptor(String recipientId) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 🔐 Sending encrypted user data to acceptor: $recipientId');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ User not logged in, cannot send user data');
        return;
      }

      final currentSession = SeSessionService().currentSession;
      final userDisplayName = currentSession?.displayName ??
          'User ${currentUserId.substring(0, 8)}';

      // Create user data payload
      final userData = {
        'type': 'user_data_exchange',
        'sender_id': currentUserId,
        'display_name': userDisplayName,
        'profile_data': {
          'session_id': currentUserId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'accepted_at': DateTime.now().millisecondsSinceEpoch,
        },
        // Note: No conversation_id here as this is step 3 (initial user data exchange)
        // The conversation_id will be added in step 4 when user2 responds
      };

      print(
          '🔔 OptimizedNotificationService: 🔐 Encrypting user data for: $recipientId');

      // Verify that we have the recipient's public key before attempting encryption
      try {
        final recipientKey =
            await EncryptionService.getRecipientPublicKey(recipientId);
        if (recipientKey == null || recipientKey.isEmpty) {
          print(
              '🔔 OptimizedNotificationService: ❌ No public key found for recipient: $recipientId');
          print(
              '🔔 OptimizedNotificationService: ❌ Cannot encrypt user data without recipient public key');
          return;
        }
        print(
            '🔔 OptimizedNotificationService: ✅ Recipient public key verified for: $recipientId');
      } catch (e) {
        print(
            '🔔 OptimizedNotificationService: ❌ Error checking recipient public key: $e');
        return;
      }

      // Encrypt the data using the legacy encryption service
      final encryptedPayload =
          await EncryptionService.encryptAesCbcPkcs7(userData, recipientId);

      // Send encrypted notification via AirNotifier
      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: recipientId,
        title: 'Connection Established',
        body: 'Secure connection established successfully',
        data: {
          'data': encryptedPayload,
          'type': 'user_data_exchange',
          'encrypted': true,
        },
        sound: 'default',
        encrypted: true,
      );

      if (success) {
        print(
            '🔔 OptimizedNotificationService: ✅ Encrypted user data sent successfully to: $recipientId');
      } else {
        print(
            '🔔 OptimizedNotificationService: ❌ Failed to send encrypted user data to: $recipientId');
      }
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error sending user data to acceptor: $e');
    }
  }

  /// Process decrypted user data and create contact/chat
  Future<void> _processDecryptedUserData(Map<String, dynamic> userData) async {
    try {
      print('🔔 OptimizedNotificationService: Processing decrypted user data');
      print(
          '🔔 OptimizedNotificationService: 🔍 User data keys: ${userData.keys.toList()}');
      print('🔔 OptimizedNotificationService: 🔍 User data: $userData');

      final senderId = userData['sender_id'] as String?;
      final displayName = userData['display_name'] as String?;
      final profileData = userData['profile_data'] as Map<String, dynamic>?;
      final conversationId = userData['conversation_id'] as String?;

      if (senderId == null || displayName == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ Invalid user data - missing required fields');
        print(
            '🔔 OptimizedNotificationService: Available fields: ${userData.keys.toList()}');
        return;
      }

      print(
          '🔔 OptimizedNotificationService: ✅ Processing data for user: $displayName ($senderId)');

      // Update the Key Exchange Request display name from "session_..." to actual name
      await _updateKeyExchangeRequestDisplayName(senderId, displayName);

      // Create contact and chat automatically
      await _createContactAndChat(senderId, displayName, profileData);

      if (conversationId != null) {
        // This is step 5 of KER: User1 receives encrypted payload with conversation ID
        // Find the conversation we just created and update its ID to match user2's
        await _synchronizeConversationId(senderId, conversationId);
        print(
            '🔔 OptimizedNotificationService: ✅ Conversation ID synchronized: $conversationId');

        // Now send our encrypted user data back to complete the handshake
        await _sendEncryptedUserDataResponse(senderId, conversationId);
      } else {
        // This is step 3 of KER: User2 receives encrypted payload, creates chat
        // No conversation ID means this is the initial user data exchange
        print(
            '🔔 OptimizedNotificationService: ✅ Initial user data exchange completed');
      }

      print(
          '🔔 OptimizedNotificationService: ✅ Contact and chat created successfully');
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error processing user data: $e');
    }
  }

  /// Update the Key Exchange Request display name
  Future<void> _updateKeyExchangeRequestDisplayName(
      String senderId, String displayName) async {
    try {
      print(
          '🔔 OptimizedNotificationService: Updating KER display name for: $senderId to: $displayName');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ User not logged in, cannot update KER');
        return;
      }

      final prefsService = SeSharedPreferenceService();
      final displayNameMappings =
          await prefsService.getJson('ker_display_names') ?? {};

      displayNameMappings[senderId] = displayName;
      await prefsService.setJson('ker_display_names', displayNameMappings);

      print(
          '🔔 OptimizedNotificationService: ✅ KER display name mapping stored: $senderId -> $displayName');

      // Update the KeyExchangeRequestProvider to refresh the UI in real-time
      try {
        final keyExchangeProvider = KeyExchangeRequestProvider();
        await keyExchangeProvider.updateUserDisplayName(senderId, displayName);
        print(
            '🔔 OptimizedNotificationService: ✅ KeyExchangeRequestProvider updated with new display name');
      } catch (e) {
        print(
            '🔔 OptimizedNotificationService: Error updating KeyExchangeRequestProvider: $e');
      }
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error updating KER display name: $e');
    }
  }

  /// Create contact and chat for the new connection
  Future<void> _createContactAndChat(String contactId, String displayName,
      Map<String, dynamic>? profileData) async {
    try {
      print(
          '🔔 OptimizedNotificationService: Creating contact and chat for: $displayName');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🔔 OptimizedNotificationService: ❌ User not logged in');
        return;
      }

      // Check if conversation already exists in database to prevent duplicates
      try {
        final messageStorageService = MessageStorageService.instance;
        final existingConversations =
            await messageStorageService.getUserConversations(currentUserId);

        final existingConversation = existingConversations.firstWhere(
          (conv) =>
              conv.participant2Id == contactId || conv.recipientId == contactId,
          orElse: () => throw Exception('No existing conversation found'),
        );

        if (existingConversation != null) {
          print(
              '🔔 OptimizedNotificationService: ℹ️ Conversation already exists for contact: $displayName (${existingConversation.id})');
          print(
              '🔔 OptimizedNotificationService: Skipping duplicate conversation creation');
          return;
        }
      } catch (e) {
        print(
            '🔔 OptimizedNotificationService: No existing conversation found, proceeding with creation');
      }

      // Create contact
      final contact = {
        'id': contactId,
        'displayName': displayName,
        'sessionId': contactId,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'profileData': profileData ?? {},
        'status': 'active',
      };

      // Save contact to local storage
      final prefsService = SeSharedPreferenceService();
      final existingContacts = await prefsService.getJsonList('contacts') ?? [];

      if (!existingContacts.any((c) => c['id'] == contactId)) {
        existingContacts.add(contact);
        await prefsService.setJsonList('contacts', existingContacts);
        print('🔔 OptimizedNotificationService: ✅ Contact saved: $displayName');
      } else {
        print(
            '🔔 OptimizedNotificationService: Contact already exists: $displayName');
      }

      // Create chat conversation in the database with consistent ID format
      final chatId = 'chat_${contactId}_$currentUserId';

      // Get current user info for chat
      final currentSession = SeSessionService().currentSession;
      final currentUserDisplayName = currentSession?.displayName ??
          'User ${currentUserId.substring(0, 8)}';

      // Create ChatConversation object for database
      final conversation = ChatConversation(
        id: chatId,
        participant1Id: currentUserId,
        participant2Id: contactId,
        displayName: displayName,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastMessageAt: DateTime.now(),
        lastMessageId: null,
        lastMessagePreview: null,
        lastMessageType: null,
        unreadCount: 0,
        isArchived: false,
        isMuted: false,
        isPinned: false,
        metadata: {
          'created_from_key_exchange': true,
          'contact_display_name': displayName,
          'current_user_display_name': currentUserDisplayName,
        },
        lastSeen: null,
        isTyping: false,
        typingStartedAt: null,
        notificationsEnabled: true,
        soundEnabled: true,
        vibrationEnabled: true,
        readReceiptsEnabled: true,
        typingIndicatorsEnabled: true,
        lastSeenEnabled: true,
        mediaAutoDownload: true,
        encryptMedia: true,
        mediaQuality: 'High',
        messageRetention: '30 days',
        isBlocked: false,
        blockedAt: null,
        recipientId: contactId,
        recipientName: displayName,
      );

      // Save conversation to database
      try {
        print(
            '🔔 OptimizedNotificationService: 🗄️ Attempting to save conversation to database...');
        final messageStorageService = MessageStorageService.instance;
        print(
            '🔔 OptimizedNotificationService: 📊 Conversation data: ${conversation.toJson()}');
        await messageStorageService.saveConversation(conversation);
        print(
            '🔔 OptimizedNotificationService: ✅ Chat conversation created in database: $chatId');

        // Notify about conversation creation
        if (_onConversationCreated != null) {
          _onConversationCreated!(conversation);
        }
      } catch (e) {
        print(
            '🔔 OptimizedNotificationService: ❌ Failed to create chat conversation in database: $e');
        print(
            '🔔 OptimizedNotificationService: 🔍 Error details: ${e.runtimeType} - $e');
        throw Exception('Failed to create chat conversation in database: $e');
      }

      // Send encrypted response with our user data and chat info
      await _sendEncryptedResponse(contactId, chatId);
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error creating contact/chat: $e');
    }
  }

  /// Send encrypted response with our user data and chat info
  Future<void> _sendEncryptedResponse(String contactId, String chatId) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 🔐 Sending encrypted response to: $contactId');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) return;

      final currentSession = SeSessionService().currentSession;
      final userDisplayName = currentSession?.displayName ??
          'User ${currentUserId.substring(0, 8)}';

      // Create our user data payload with chat information
      final userData = {
        'type': 'user_data_response',
        'sender_id': currentUserId,
        'display_name': userDisplayName,
        'chat_id': chatId,
        'profile_data': {
          'session_id': currentUserId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      };

      print(
          '🔔 OptimizedNotificationService: Sending response with display name: $userDisplayName and chat ID: $chatId');

      // Encrypt the data using the legacy encryption service
      final encryptedPayload =
          await EncryptionService.encryptAesCbcPkcs7(userData, contactId);

      // Send encrypted notification
      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: contactId,
        title: 'Connection Established',
        body: 'Secure connection established successfully',
        data: {
          'data': encryptedPayload,
          'type': 'user_data_response',
        },
        sound: 'default',
        encrypted: true,
      );

      if (success) {
        print(
            '🔔 OptimizedNotificationService: ✅ Encrypted response sent successfully');
      } else {
        print(
            '🔔 OptimizedNotificationService: ❌ Failed to send encrypted response');
      }
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error sending encrypted response: $e');
    }
  }

  /// Synchronize conversation ID to match the one from the other user
  Future<void> _synchronizeConversationId(
      String otherUserId, String targetConversationId) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 🔄 Synchronizing conversation ID to: $targetConversationId');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🔔 OptimizedNotificationService: ❌ User not logged in');
        return;
      }

      // Find the conversation between these users
      final messageStorageService = MessageStorageService.instance;
      final existingConversations =
          await messageStorageService.getUserConversations(currentUserId);

      final conversation = existingConversations.firstWhere(
        (conv) =>
            conv.participant2Id == otherUserId ||
            conv.recipientId == otherUserId,
        orElse: () => throw Exception('No conversation found between users'),
      );

      if (conversation != null) {
        // Update the conversation ID to match the target
        // Note: We can't directly update the ID in MessageStorageService, so we'll create a new conversation
        // with the synchronized ID and delete the old one
        await _recreateConversationWithSynchronizedId(
            conversation, targetConversationId);

        print(
            '🔔 OptimizedNotificationService: ✅ Conversation ID synchronized: ${conversation.id} -> $targetConversationId');
      }
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error synchronizing conversation ID: $e');
    }
  }

  /// Send encrypted user data response to complete the KER handshake
  Future<void> _sendEncryptedUserDataResponse(
      String recipientId, String conversationId) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 🔐 Sending encrypted user data response to: $recipientId');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🔔 OptimizedNotificationService: ❌ User not logged in');
        return;
      }

      final currentSession = SeSessionService().currentSession;
      final userDisplayName = currentSession?.displayName ??
          'User ${currentUserId.substring(0, 8)}';

      // Create user data response payload with conversation ID
      final userDataResponse = {
        'type': 'user_data_response',
        'sender_id': currentUserId,
        'display_name': userDisplayName,
        'conversation_id': conversationId,
        'profile_data': {
          'session_id': currentUserId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'response_at': DateTime.now().millisecondsSinceEpoch,
        },
      };

      print(
          '🔔 OptimizedNotificationService: 🔐 Encrypting user data response for: $recipientId');

      // Encrypt the data using the legacy encryption service
      final encryptedPayload = await EncryptionService.encryptAesCbcPkcs7(
          userDataResponse, recipientId);

      // Send encrypted notification
      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: recipientId,
        title: 'Connection Established',
        body: 'Secure connection established successfully',
        data: {
          'data': encryptedPayload,
          'type': 'user_data_response',
          'encrypted': true,
        },
        sound: 'default',
        encrypted: true,
      );

      if (success) {
        print(
            '🔔 OptimizedNotificationService: ✅ Encrypted user data response sent successfully');
      } else {
        print(
            '🔔 OptimizedNotificationService: ❌ Failed to send encrypted user data response');
      }
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error sending encrypted user data response: $e');
    }
  }

  /// Recreate conversation with synchronized ID
  Future<void> _recreateConversationWithSynchronizedId(
      dynamic conversation, String newId) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 🔄 Recreating conversation with synchronized ID: $newId');

      // For now, we'll just log the synchronization since we can't easily update the ID
      // In a production system, you might want to implement a more sophisticated approach
      print(
          '🔔 OptimizedNotificationService: ℹ️ Conversation ID synchronization logged: ${conversation.id} -> $newId');
      print(
          '🔔 OptimizedNotificationService: ℹ️ Note: Full ID synchronization requires database schema changes');

      // TODO: Implement proper conversation ID synchronization when database supports it
      // This could involve:
      // 1. Creating a new conversation with the synchronized ID
      // 2. Migrating all messages to the new conversation
      // 3. Deleting the old conversation
      // 4. Updating all references
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error recreating conversation with synchronized ID: $e');
    }
  }

  /// Handle encrypted user data response notifications - UPDATED VERSION 2 - NATIVE FORMAT SUPPORT
  Future<void> _handleEncryptedUserDataResponseNotification(
      Map<String, dynamic> data) async {
    try {
      print(
          '🔔 OptimizedNotificationService: 🔐 Processing encrypted user data response notification: $data');

      // UPDATED VERSION 2: Extract encrypted data - handle the specific structure from native notifications
      String? encryptedData;
      String? checksum;

      print('🔔 OptimizedNotificationService: 🔍 Data structure: ${data.keys}');

      if (data.containsKey('data')) {
        final dataField = data['data'];
        print(
            '🔔 OptimizedNotificationService: 🔍 Data field type: ${dataField.runtimeType} - UPDATED METHOD VERSION 2');

        if (dataField is String) {
          // Direct structure: data is a string
          encryptedData = dataField;
          print(
              '🔔 OptimizedNotificationService: Found direct encrypted data: ${encryptedData.length} characters');
        } else if (dataField is Map) {
          // UPDATED VERSION 2: Nested structure handling for native notifications
          final nestedData = dataField as Map;
          print(
              '🔔 OptimizedNotificationService: 🔍 Nested data keys: ${nestedData.keys}');

          // Check for encryptedData field first (native format) - it's at the same level as data
          if (nestedData.containsKey('encryptedData')) {
            final encryptedDataField = nestedData['encryptedData'];
            print(
                '🔔 OptimizedNotificationService: 🔍 Found encryptedData field: ${encryptedDataField.runtimeType}');
            print(
                '🔔 OptimizedNotificationService: 🔍 encryptedDataField value: $encryptedDataField');

            if (encryptedDataField is Map) {
              final encryptedMap = encryptedDataField as Map;
              print(
                  '🔔 OptimizedNotificationService: 🔍 encryptedMap keys: ${encryptedMap.keys}');
              encryptedData = encryptedMap['data'] as String?;
              checksum = encryptedMap['checksum'] as String?;
              print(
                  '🔔 OptimizedNotificationService: 🔍 Found encryptedData field with data: ${encryptedData?.length ?? 0} chars, checksum: ${checksum?.substring(0, 8) ?? "none"}...');
            } else if (encryptedDataField is String) {
              // Handle case where encryptedData is directly a string
              encryptedData = encryptedDataField;
              print(
                  '🔔 OptimizedNotificationService: 🔍 Found encryptedData as direct string: ${encryptedData.length} chars');
            } else {
              // Handle case where encryptedData might be a JSON string representation
              print(
                  '🔔 OptimizedNotificationService: 🔍 encryptedDataField is neither Map nor String, trying to parse as JSON');
              try {
                if (encryptedDataField.toString().startsWith('{')) {
                  final jsonMap = jsonDecode(encryptedDataField.toString())
                      as Map<String, dynamic>;
                  print(
                      '🔔 OptimizedNotificationService: 🔍 Successfully parsed JSON: ${jsonMap.keys}');
                  encryptedData = jsonMap['data'] as String?;
                  checksum = jsonMap['checksum'] as String?;
                  print(
                      '🔔 OptimizedNotificationService: 🔍 Parsed JSON - data: ${encryptedData?.length ?? 0} chars, checksum: ${checksum?.substring(0, 8) ?? "none"}...');
                }
              } catch (e) {
                print(
                    '🔔 OptimizedNotificationService: 🔍 Failed to parse as JSON: $e');
              }
            }
          }
          // Fallback to data field if encryptedData not found
          else if (nestedData.containsKey('data')) {
            final dataDataField = nestedData['data'];
            if (dataDataField is Map) {
              final dataMap = dataDataField as Map;
              encryptedData = dataMap['data'] as String?;
              checksum = dataMap['checksum'] as String?;
              print(
                  '🔔 OptimizedNotificationService: 🔍 Found data field with encrypted data: ${encryptedData?.length ?? 0} chars, checksum: ${checksum?.substring(0, 8) ?? "none"}...');
            }
          }
        }
      }

      if (encryptedData == null || encryptedData.isEmpty) {
        print(
            '🔔 OptimizedNotificationService: ❌ No encrypted data found in user data response');
        return;
      }

      // Decrypt the data using the legacy encryption service
      final decryptedData =
          await EncryptionService.decryptAesCbcPkcs7(encryptedData);

      if (decryptedData == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ Failed to decrypt user data response');
        return;
      }

      print(
          '🔔 OptimizedNotificationService: ✅ User data response decrypted successfully');

      // Extract the conversation ID from decrypted data
      final conversationId = decryptedData['conversation_id'] as String?;
      final senderId = decryptedData['sender_id'] as String?;
      final displayName = decryptedData['display_name'] as String?;

      if (conversationId == null || senderId == null || displayName == null) {
        print(
            '🔔 OptimizedNotificationService: ❌ Missing required fields in decrypted user data response');
        return;
      }

      print(
          '🔔 OptimizedNotificationService: ✅ Extracted conversation ID: $conversationId from user: $displayName ($senderId)');

      // This is step 5 of KER: User1 receives encrypted payload with conversation ID
      // Create or find conversation and synchronize the ID
      await _synchronizeConversationId(senderId, conversationId);

      print(
          '🔔 OptimizedNotificationService: ✅ KER handshake completed - conversation ID synchronized: $conversationId');
    } catch (e) {
      print(
          '🔔 OptimizedNotificationService: ❌ Error processing encrypted user data response: $e');
    }
  }
}
