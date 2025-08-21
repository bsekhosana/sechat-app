import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sechat_app/core/services/encryption_service.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:uuid/uuid.dart';
import 'package:sechat_app/core/services/se_shared_preference_service.dart';
import 'package:sechat_app/features/chat/models/chat_conversation.dart';
import 'package:sechat_app/features/chat/services/message_storage_service.dart';
import 'package:sechat_app/features/notifications/services/notification_manager_service.dart';
import 'package:sechat_app/core/utils/conversation_id_generator.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';

/// Service to handle secure key exchange between users
class KeyExchangeService {
  static KeyExchangeService? _instance;
  static KeyExchangeService get instance =>
      _instance ??= KeyExchangeService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _keyExchangePrefix = 'key_exchange_';
  static const String _pendingExchangesKey = 'pending_key_exchanges';

  // Callback for when conversations are created
  Function(ChatConversation)? _onConversationCreated;

  // Private constructor
  KeyExchangeService._();

  /// Set callback for when conversations are created
  void setOnConversationCreated(Function(ChatConversation) callback) {
    _onConversationCreated = callback;
  }

  /// Initialize user's encryption keys if they don't exist
  Future<Map<String, String>> ensureKeysExist() async {
    try {
      // Get keys from session service (current implementation)
      final sessionService = SeSessionService();
      final currentSession = sessionService.currentSession;

      if (currentSession != null) {
        // Keys already exist in session
        final publicKey = currentSession.publicKey;
        final privateKey = await EncryptionService.getPrivateKey();
        final version = await EncryptionService.getKeyPairVersion();

        print('🔑 KeyExchangeService: Using existing keys from session');
        return {
          'publicKey': publicKey,
          'privateKey': privateKey ?? '',
          'version': version,
        };
      }

      // No keys exist, generate them via session service
      print(
          '🔑 KeyExchangeService: No keys found, generating new keys via session service');
      await sessionService.regenerateProperKeys();

      // Get the newly generated keys
      final newSession = sessionService.currentSession;
      if (newSession?.publicKey != null) {
        final publicKey = newSession!.publicKey;
        final privateKey = await EncryptionService.getPrivateKey();
        final version = await EncryptionService.getKeyPairVersion();

        print('🔑 KeyExchangeService: New keys generated successfully');
        return {
          'publicKey': publicKey,
          'privateKey': privateKey ?? '',
          'version': version,
        };
      } else {
        throw Exception('Failed to generate new keys');
      }
    } catch (e) {
      print('🔑 KeyExchangeService: Error ensuring keys exist: $e');
      throw Exception('Failed to ensure keys exist: $e');
    }
  }

  /// Request key exchange with another user
  Future<bool> requestKeyExchange(String recipientId,
      {String? requestPhrase}) async {
    try {
      print('🔑 KeyExchangeService: Requesting key exchange with $recipientId');

      // Ensure we have our own keys
      final ourKeys = await ensureKeysExist();
      final currentUserId = SeSessionService().currentSessionId;

      if (currentUserId == null) {
        throw Exception('User not logged in');
      }

      // Generate request ID
      final requestId = const Uuid().v4();

      // Create the key exchange request data
      final keyExchangeRequestData = {
        'type': 'key_exchange_request',
        'senderId': currentUserId,
        'publicKey': ourKeys['publicKey'],
        'version': ourKeys['version'],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'requestId': requestId,
        'requestPhrase': requestPhrase ?? 'New encryption key exchange request',
      };

      // Store pending exchange
      await _addPendingExchange(recipientId);

      // Send the key exchange request via socket
      try {
        SeSocketService.instance.sendKeyExchangeRequest(
          recipientId: recipientId,
          publicKey: ourKeys['publicKey']!,
          requestId: requestId,
          requestPhrase: requestPhrase ?? 'New encryption key exchange request',
        );

        print(
            '🔑 KeyExchangeService: ✅ Key exchange request sent successfully to $recipientId');

        // CRITICAL FIX: Automatically set up ChannelSocketService listeners for the recipient
        // This ensures we can receive responses and future events from this user
        try {
          final channelSocketService = SeSocketService.instance;

          // Set up listeners for this specific recipient
          channelSocketService.setupContactListeners([recipientId]);
          print(
              '🔑 KeyExchangeService: ✅ Set up ChannelSocketService listeners for recipient: $recipientId');
        } catch (e) {
          print(
              '🔑 KeyExchangeService: ⚠️ Warning: Could not set up ChannelSocketService listeners: $e');
          // Don't fail the entire request if listener setup fails
        }

        // Create a local record of the sent request
        await _createLocalSentRequest(
            requestId, currentUserId, recipientId, requestPhrase);

        return true;
      } catch (e) {
        print('🔑 KeyExchangeService: Error sending key exchange request: $e');
        return false;
      }
    } catch (e) {
      print('🔑 KeyExchangeService: Error requesting key exchange: $e');
      return false;
    }
  }

  /// Resend key exchange request to another user
  Future<bool> resendKeyExchangeRequest(String recipientId,
      {String? requestPhrase}) async {
    try {
      print(
          '🔑 KeyExchangeService: Resending key exchange request to $recipientId');

      // Remove any existing pending exchange first
      await _removePendingExchange(recipientId);

      // Request new key exchange
      return await requestKeyExchange(recipientId,
          requestPhrase: requestPhrase);
    } catch (e) {
      print('🔑 KeyExchangeService: Error resending key exchange request: $e');
      return false;
    }
  }

  /// Create a local record of the sent key exchange request
  Future<void> _createLocalSentRequest(String requestId, String senderId,
      String recipientId, String? requestPhrase) async {
    try {
      final prefsService = SeSharedPreferenceService();
      final existingRequests =
          await prefsService.getJsonList('key_exchange_requests') ?? [];

      final sentRequest = {
        'id': requestId,
        'fromSessionId': senderId,
        'toSessionId': recipientId,
        'requestPhrase': requestPhrase ?? 'New encryption key exchange request',
        'status': 'sent',
        'timestamp': DateTime.now().toIso8601String(),
        'type': 'key_exchange_request',
      };

      existingRequests.add(sentRequest);
      await prefsService.setJsonList('key_exchange_requests', existingRequests);

      print('🔑 KeyExchangeService: ✅ Local sent request record created');
    } catch (e) {
      print('🔑 KeyExchangeService: Error creating local sent request: $e');
    }
  }

  /// Process incoming key exchange request from another user
  /// It should only store the request and let the user manually accept/decline
  Future<bool> processKeyExchangeRequest(Map<String, dynamic> request) async {
    try {
      print('🔑 KeyExchangeService: Processing key exchange request');
      print('🔑 KeyExchangeService: 📋 Incoming request data: $request');
      print(
          '🔑 KeyExchangeService: 🔍 Available keys: ${request.keys.toList()}');

      final senderId = request['senderId'] as String?;
      final senderPublicKey = request['publicKey'] as String?;
      final keyVersion = request['version']?.toString();

      print('🔑 KeyExchangeService: 🔍 Extracted senderId: $senderId');
      print(
          '🔑 KeyExchangeService: 🔍 Extracted senderPublicKey: $senderPublicKey');
      print('🔑 KeyExchangeService: 🔍 Extracted keyVersion: $keyVersion');

      if (senderId == null || senderPublicKey == null) {
        throw Exception('Invalid key exchange request');
      }

      // Store sender's public key
      await EncryptionService.storeRecipientPublicKey(
          senderId, senderPublicKey);
      print('🔑 KeyExchangeService: Stored public key for $senderId');

      // CRITICAL FIX: Ensure SeSocketService is initialized and listening for incoming events
      // This is needed because the recipient must be able to receive KER responses
      try {
        final seSocketService = SeSocketService.instance;

        // Check if SeSocketService is already connected
        if (!seSocketService.isConnected) {
          print(
              '🔑 KeyExchangeService: 🔌 SeSocketService not connected, cannot receive incoming events');
        } else {
          print('🔑 KeyExchangeService: ✅ SeSocketService already connected');
        }
      } catch (e) {
        print(
            '🔑 KeyExchangeService: ⚠️ Warning: Could not initialize SeSocketService: $e');
        // Don't fail the entire request if SeSocketService initialization fails
      }

      // CRITICAL FIX: Automatically set up ChannelSocketService listeners for the sender
      // This ensures we can receive future events from this user
      try {
        final channelSocketService = SeSocketService.instance;

        // Set up listeners for this specific sender
        channelSocketService.setupContactListeners([senderId]);
        print(
            '🔑 KeyExchangeService: ✅ Set up ChannelSocketService listeners for sender: $senderId');
      } catch (e) {
        print(
            '🔑 KeyExchangeService: ⚠️ Warning: Could not set up ChannelSocketService listeners: $e');
        // Don't fail the entire request if listener setup fails
      }

      // IMPORTANT: Do NOT automatically send a response
      // The user should manually accept/decline the request
      print(
          '🔑 KeyExchangeService: ✅ Key exchange request stored successfully');
      print(
          '🔑 KeyExchangeService: ℹ️ User must manually accept/decline the request');

      return true;
    } catch (e) {
      print('🔑 KeyExchangeService: Error processing key exchange request: $e');
      return false;
    }
  }

  /// Decline key exchange request from another user
  Future<bool> declineKeyExchangeRequest(Map<String, dynamic> request) async {
    try {
      print('🔑 KeyExchangeService: Declining key exchange request');

      final senderId = request['senderId'] as String?;
      final keyVersion = request['version']?.toString();

      if (senderId == null) {
        throw Exception('Invalid key exchange request');
      }

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        throw Exception('User not logged in');
      }

      // Send decline response via socket service
      SeSocketService.instance.sendKeyExchangeResponse(
        recipientId: senderId,
        publicKey: '', // No public key needed for decline
        responseId: const Uuid().v4(),
      );

      print(
          '🔑 KeyExchangeService: ✅ Key exchange decline sent successfully to $senderId');

      // CRITICAL FIX: Automatically set up ChannelSocketService listeners for the sender
      // This ensures we can receive future events from this user
      try {
        final channelSocketService = SeSocketService.instance;

        // Set up listeners for this specific sender
        channelSocketService.setupContactListeners([senderId]);
        print(
            '🔑 KeyExchangeService: ✅ Set up ChannelSocketService listeners for sender: $senderId');
      } catch (e) {
        print(
            '🔑 KeyExchangeService: ⚠️ Warning: Could not set up ChannelSocketService listeners: $e');
        // Don't fail the entire decline if listener setup fails
      }

      return true;
    } catch (e) {
      print('🔑 KeyExchangeService: Error declining key exchange request: $e');
      return false;
    }
  }

  /// Process key exchange response from another user
  Future<bool> processKeyExchangeResponse(Map<String, dynamic> response) async {
    try {
      print('🔑 KeyExchangeService: Processing key exchange response');
      print('🔑 KeyExchangeService: 📋 Response data: $response');
      print(
          '🔑 KeyExchangeService: 🔍 Available keys: ${response.keys.toList()}');

      final senderId = response['senderId'] as String?;
      final senderPublicKey = response['publicKey'] as String?;
      final responseType = response['type'] as String?;

      print('🔑 KeyExchangeService: 🔍 Extracted senderId: $senderId');
      print(
          '🔑 KeyExchangeService: 🔍 Extracted senderPublicKey: $senderPublicKey');
      print('🔑 KeyExchangeService: 🔍 Extracted responseType: $responseType');

      if (senderId == null || senderPublicKey == null) {
        throw Exception('Invalid key exchange response');
      }

      // Store sender's public key
      await EncryptionService.storeRecipientPublicKey(
          senderId, senderPublicKey);
      print('🔑 KeyExchangeService: ✅ Stored public key for $senderId');

      // CRITICAL FIX: Ensure SeSocketService is initialized and listening for incoming events
      // This is needed because the recipient must be able to receive future events
      try {
        final seSocketService = SeSocketService.instance;

        // Check if SeSocketService is already connected
        if (!seSocketService.isConnected) {
          print(
              '🔑 KeyExchangeService: 🔌 SeSocketService not connected, cannot receive incoming events');
        } else {
          print('🔑 KeyExchangeService: ✅ SeSocketService already connected');
        }
      } catch (e) {
        print(
            '🔑 KeyExchangeService: ⚠️ Warning: Could not initialize SeSocketService: $e');
        // Don't fail the entire response processing if SeSocketService initialization fails
      }

      // CRITICAL FIX: Automatically set up ChannelSocketService listeners for the sender
      // This ensures we can receive future events from this user
      try {
        final channelSocketService = SeSocketService.instance;

        // Set up listeners for this specific sender
        channelSocketService.setupContactListeners([senderId]);
        print(
            '🔑 KeyExchangeService: ✅ Set up ChannelSocketService listeners for sender: $senderId');
      } catch (e) {
        print(
            '🔑 KeyExchangeService: ⚠️ Warning: Could not set up ChannelSocketService listeners: $e');
        // Don't fail the entire response processing if listener setup fails
      }

      // Remove from pending exchanges
      await _removePendingExchange(senderId);

      // If this is an acceptance response, send encrypted user data to complete the exchange
      if (responseType == 'key_exchange_accepted' ||
          responseType == 'key_exchange_response') {
        print(
            '🔑 KeyExchangeService: ✅ Key exchange accepted, sending encrypted user data');
        await _sendInitialUserData(senderId);
      } else {
        print(
            '🔑 KeyExchangeService: ℹ️ Response type is not acceptance: $responseType');
      }

      return true;
    } catch (e) {
      print(
          '🔑 KeyExchangeService: ❌ Error processing key exchange response: $e');
      return false;
    }
  }

  /// Check if we have a public key for a user
  Future<bool> hasPublicKeyForUser(String userId) async {
    final publicKey = await EncryptionService.getRecipientPublicKey(userId);
    return publicKey != null;
  }

  /// Initiate key exchange if necessary
  Future<bool> ensureKeyExchangeWithUser(String userId) async {
    try {
      // Check if we already have their key
      final hasKey = await hasPublicKeyForUser(userId);
      if (hasKey) {
        // We already have their key
        return true;
      }

      // Check if exchange is pending
      final isPending = await _isExchangePending(userId);
      if (isPending) {
        print(
            '🔑 KeyExchangeService: Key exchange with $userId already pending');
        return true;
      }

      // Request new key exchange
      return await requestKeyExchange(userId);
    } catch (e) {
      print('🔑 KeyExchangeService: Error ensuring key exchange: $e');
      return false;
    }
  }

  /// Generate test keys for all pending exchanges (for development/testing)
  Future<void> generateTestKeysForPendingExchanges() async {
    try {
      final pendingExchanges = await _getPendingExchanges();

      for (final userId in pendingExchanges) {
        print('🔑 KeyExchangeService: Generating test key for $userId');
        await EncryptionService.generateTestKey(userId);
        await _removePendingExchange(userId);
      }

      print(
          '🔑 KeyExchangeService: Generated test keys for ${pendingExchanges.length} pending exchanges');
    } catch (e) {
      print('🔑 KeyExchangeService: Error generating test keys: $e');
    }
  }

  /// Add pending key exchange
  Future<void> _addPendingExchange(String userId) async {
    final pendingExchanges = await _getPendingExchanges();

    if (!pendingExchanges.contains(userId)) {
      pendingExchanges.add(userId);
      await _savePendingExchanges(pendingExchanges);
    }
  }

  /// Remove pending key exchange
  Future<void> _removePendingExchange(String userId) async {
    final pendingExchanges = await _getPendingExchanges();

    if (pendingExchanges.contains(userId)) {
      pendingExchanges.remove(userId);
      await _savePendingExchanges(pendingExchanges);
    }
  }

  /// Check if exchange is pending
  Future<bool> _isExchangePending(String userId) async {
    final pendingExchanges = await _getPendingExchanges();
    return pendingExchanges.contains(userId);
  }

  /// Get all pending key exchanges
  Future<List<String>> _getPendingExchanges() async {
    try {
      final pendingExchangesJson =
          await _storage.read(key: _pendingExchangesKey);

      if (pendingExchangesJson == null) {
        return [];
      }

      final List<dynamic> decoded = jsonDecode(pendingExchangesJson);
      return decoded.map((e) => e.toString()).toList();
    } catch (e) {
      print('🔑 KeyExchangeService: Error getting pending exchanges: $e');
      return [];
    }
  }

  /// Save pending exchanges
  Future<void> _savePendingExchanges(List<String> exchanges) async {
    try {
      final json = jsonEncode(exchanges);
      await _storage.write(key: _pendingExchangesKey, value: json);
    } catch (e) {
      print('🔑 KeyExchangeService: Error saving pending exchanges: $e');
    }
  }

  /// Clear all pending exchanges
  Future<void> clearAllPendingExchanges() async {
    try {
      await _storage.delete(key: _pendingExchangesKey);
    } catch (e) {
      print('🔑 KeyExchangeService: Error clearing pending exchanges: $e');
    }
  }

  /// Rotate keys and notify contacts
  Future<bool> rotateKeys() async {
    try {
      // Generate new keys via session service
      final sessionService = SeSessionService();
      await sessionService.regenerateProperKeys();

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        throw Exception('User not logged in');
      }

      // Get the new key version
      final version = await EncryptionService.getKeyPairVersion();
      print('🔑 KeyExchangeService: Rotated keys to version $version');

      // TODO: In a real implementation, you would get the list of contacts
      // and notify each one about the key change. For now, we'll just log it.
      print(
          '🔑 KeyExchangeService: Key rotation completed. Contacts will need to re-exchange keys on next communication.');

      return true;
    } catch (e) {
      print('🔑 KeyExchangeService: Error rotating keys: $e');
      return false;
    }
  }

  /// Notify a specific contact about key rotation
  Future<bool> notifyKeyRotation(String contactId) async {
    try {
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        throw Exception('User not logged in');
      }

      // Send key rotation notice via socket
      SeSocketService.instance.sendMessage(
        contactId,
        'Encryption keys have been updated',
        messageId: 'key_rotation_${DateTime.now().millisecondsSinceEpoch}',
      );

      print('🔑 KeyExchangeService: ✅ Key rotation notice sent to $contactId');

      return true;
    } catch (e) {
      print('🔑 KeyExchangeService: Error notifying key rotation: $e');
      return false;
    }
  }

  /// Process user data exchange after key exchange completion
  Future<bool> processUserDataExchange({
    required String senderId,
    required String encryptedData,
    String? conversationId,
  }) async {
    try {
      print('🔑 KeyExchangeService: 🚀 Starting to process user data exchange');
      print('🔑 KeyExchangeService: 🔍 Sender ID: $senderId');
      print(
          '🔑 KeyExchangeService: 🔍 Encrypted data length: ${encryptedData.length}');
      print('🔑 KeyExchangeService: 🔍 Conversation ID: $conversationId');

      // Decrypt the user data
      final decryptedData = await EncryptionService.decryptData(encryptedData);

      if (decryptedData == null) {
        print('🔑 KeyExchangeService: ❌ Failed to decrypt user data');
        return false;
      }

      // Parse the decrypted data
      final userData = Map<String, dynamic>.from(decryptedData);
      final userName = userData['userName'] as String?;
      final userSessionId = userData['sessionId'] as String?;
      final receivedConversationId = userData['conversationId'] as String?;

      if (userName == null || userSessionId == null) {
        print('🔑 KeyExchangeService: ❌ Invalid user data format');
        return false;
      }

      print(
          '🔑 KeyExchangeService: ✅ Decrypted user data: $userName ($userSessionId)');

      // If we received a conversation ID, this is the final response from the recipient
      // Create a matching conversation using their ID
      if (receivedConversationId != null) {
        print(
            '🔑 KeyExchangeService: 📋 Received conversation ID: $receivedConversationId');

        final conversation = await _createConversation(
          recipientId: receivedConversationId,
        );

        if (conversation != null) {
          print(
              '🔑 KeyExchangeService: ✅ Matching conversation created: ${conversation.id}');
          return true;
        } else {
          print(
              '🔑 KeyExchangeService: ❌ Failed to create matching conversation');
          return false;
        }
      } else {
        // This is the initial user data from the sender, create conversation and send response
        final conversation = await _createConversation(
          recipientId: userSessionId,
        );

        if (conversation != null) {
          print(
              '🔑 KeyExchangeService: ✅ Conversation created: ${conversation.id}');

          // Send our user data back to complete the exchange
          await _sendUserDataResponse(senderId, conversation.id);

          return true;
        } else {
          print('🔑 KeyExchangeService: ❌ Failed to create conversation');
          return false;
        }
      }
    } catch (e) {
      print('🔑 KeyExchangeService: Error processing user data exchange: $e');
      return false;
    }
  }

  /// Create a new conversation after successful key exchange
  Future<ChatConversation?> _createConversation({
    required String recipientId,
  }) async {
    try {
      // Use recipient ID as conversation ID
      final conversationId = recipientId;

      print('🔑 KeyExchangeService: Creating conversation: $conversationId');

      // Create conversation object
      final conversation = ChatConversation(
        id: conversationId,
        participant1Id: SeSessionService().currentSessionId ?? '',
        participant2Id: recipientId,
        displayName: recipientId, // Will be updated when user data is loaded
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastMessageAt: null,
        lastMessageId: null,
        lastMessagePreview: null,
        lastMessageType: null,
        unreadCount: 0,
        isArchived: false,
        isMuted: false,
        isPinned: false,
        metadata: null,
        lastSeen: null,
        isTyping: false,
        typingStartedAt: null,
        notificationsEnabled: true,
        soundEnabled: true,
        vibrationEnabled: true,
        readReceiptsEnabled: true,
        typingIndicatorsEnabled: true,
        lastSeenEnabled: true,
      );

      // Save conversation to storage
      await MessageStorageService.instance.saveConversation(conversation);

      print('🔑 KeyExchangeService: ✅ Conversation created: $conversationId');
      return conversation;
    } catch (e) {
      print('🔑 KeyExchangeService: ❌ Failed to create conversation: $e');
      return null;
    }
  }

  /// Send initial user data after key exchange acceptance (from initial sender)
  Future<void> _sendInitialUserData(String recipientId) async {
    try {
      print(
          '🔑 KeyExchangeService: 🚀 Starting to send initial user data to $recipientId');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🔑 KeyExchangeService: ❌ Current user ID is null');
        return;
      }

      // Get current user's name from session
      final currentSession = SeSessionService().currentSession;
      final userName = currentSession?.displayName ?? 'User $currentUserId';

      print(
          '🔑 KeyExchangeService: 🔍 Current user: $userName ($currentUserId)');

      // Create user data payload
      final userData = {
        'userName': userName,
        'sessionId': currentUserId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      print('🔑 KeyExchangeService: 📋 User data payload: $userData');

      // Encrypt the user data
      final encryptedData = await EncryptionService.encryptData(
        userData,
        recipientId,
      );

      if (encryptedData != null) {
        // Send via socket
        final payload = {
          'recipientId': recipientId,
          'encryptedData': encryptedData,
          'timestamp': DateTime.now().toIso8601String(),
        };

        print('🔑 KeyExchangeService: 📤 Sending payload via socket: $payload');

        // Check if socket is ready before sending
        if (SeSocketService.instance.isReadyToSend) {
          print(
              '🔑 KeyExchangeService: 🔍 Socket ready, sending user_data_exchange event');

          // CRITICAL FIX: Use channel-based event format and set up listeners
          try {
            // Use SeSocketService for user data exchange
            SeSocketService.instance.sendUserDataExchange(
              recipientId: recipientId,
              encryptedData: encryptedData,
            );
            print(
                '🔑 KeyExchangeService: ✅ Initial user data sent to $recipientId using ChannelSocketService');

            print(
                '🔑 KeyExchangeService: ✅ Initial user data sent to $recipientId using SeSocketService');
          } catch (e) {
            print(
                '🔑 KeyExchangeService: ⚠️ Warning: Could not send user data exchange: $e');
          }

          // Add a small delay to ensure the event is processed
          await Future.delayed(const Duration(milliseconds: 100));
          print(
              '🔑 KeyExchangeService: ⏱️ Event sent, waiting for processing...');
        } else {
          print('🔑 KeyExchangeService: ❌ Socket not ready to send');
          print(
              '🔑 KeyExchangeService: 🔍 Socket status: ${SeSocketService.instance.getSocketStatus()}');
        }
      } else {
        print('🔑 KeyExchangeService: ❌ Failed to encrypt initial user data');
      }
    } catch (e) {
      print('🔑 KeyExchangeService: ❌ Error sending initial user data: $e');
    }
  }

  /// Send user data response to complete the exchange
  Future<void> _sendUserDataResponse(
      String recipientId, String conversationId) async {
    try {
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) return;

      // Get current user's name from session
      final currentSession = SeSessionService().currentSession;
      final userName = currentSession?.displayName ?? 'User $currentUserId';

      // Create user data payload
      final userData = {
        'userName': userName,
        'sessionId': currentUserId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'conversationId':
            conversationId, // Include conversation ID for matching
      };

      // Encrypt the user data
      final encryptedData = await EncryptionService.encryptData(
        userData,
        recipientId,
      );

      if (encryptedData != null) {
        // CRITICAL: Use the correct server event format: user_data_exchange:send
        try {
          SeSocketService.instance.emit('user_data_exchange:send', {
            'recipientId': recipientId,
            'senderId': currentUserId,
            'encryptedData': encryptedData,
            'conversationId': conversationId,
            'timestamp': DateTime.now().toIso8601String(),
          });
          print(
              '🔑 KeyExchangeService: ✅ User data response sent to $recipientId using user_data_exchange:send');
        } catch (e) {
          print(
              '🔑 KeyExchangeService: ❌ Error sending user data response: $e');
        }
      } else {
        print('🔑 KeyExchangeService: ❌ Failed to encrypt user data');
      }
    } catch (e) {
      print('🔑 KeyExchangeService: Error sending user data response: $e');
    }
  }

  /// Handle user data exchange from other users
  Future<void> handleUserDataExchange(Map<String, dynamic> data) async {
    try {
      final senderId = data['senderId'] as String?;
      final encryptedData = data['encryptedData'] as String?;

      if (senderId == null || encryptedData == null) {
        print('🔑 KeyExchangeService: ❌ Invalid user data exchange data');
        return;
      }

      print(
          '🔑 KeyExchangeService: 🔍 Processing user data exchange from $senderId');

      // Decrypt the user data
      final decryptedData = await EncryptionService.decryptData(encryptedData);
      if (decryptedData == null) {
        print('🔑 KeyExchangeService: ❌ Failed to decrypt user data');
        return;
      }

      // Parse the decrypted data
      final userData = Map<String, dynamic>.from(decryptedData);
      final userName = userData['userName']?.toString() ?? 'Unknown User';
      final userSessionId = userData['sessionId']?.toString() ?? senderId;

      print(
          '🔑 KeyExchangeService: ✅ User data decrypted: $userName ($userSessionId)');

      // Create conversation locally
      final conversationId =
          await _createConversationLocally(senderId, userName);
      print(
          '🔑 KeyExchangeService: ✅ Conversation created locally: $conversationId');

      // CRITICAL: Store the sender's public key for future encryption
      // This should have been received in key_exchange:response, but let's ensure it's stored
      final senderPublicKey = await _getSenderPublicKey(senderId);
      if (senderPublicKey != null) {
        print('🔑 KeyExchangeService: ✅ Sender public key found and stored');
      } else {
        print(
            '🔑 KeyExchangeService: ⚠️ Warning: Sender public key not found, will try to retrieve from storage');
      }

      // Send conversation:created response with our encrypted display name
      if (conversationId != null) {
        await _sendConversationCreatedResponse(senderId, conversationId);
      }

      // Notify UI that conversation was created
      if (_onConversationCreated != null) {
        final conversation = ChatConversation(
          id: conversationId,
          participant1Id: SeSessionService().currentSessionId!,
          participant2Id: senderId,
          displayName: userName,
          unreadCount: 0,
          isOnline: false,
          lastSeen: null,
        );
        _onConversationCreated!(conversation);
      }
    } catch (e) {
      print('🔑 KeyExchangeService: ❌ Error handling user data exchange: $e');
      rethrow;
    }
  }

  /// Create conversation locally in the database
  Future<String?> _createConversationLocally(
      String participantId, String participantName) async {
    try {
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) return null;

      // Generate conversation ID
      final conversationId = currentUserId;

      // Create conversation in database
      final conversation = ChatConversation(
        participant1Id: currentUserId,
        participant2Id: participantId,
        displayName: participantName,
        unreadCount: 0,
        isOnline: false,
        lastSeen: DateTime.now(),
      );

      // Save to database
      await MessageStorageService.instance.saveConversation(conversation);

      print(
          '🔑 KeyExchangeService: ✅ Conversation saved to database: $conversationId');
      return conversationId;
    } catch (e) {
      print('🔑 KeyExchangeService: ❌ Error creating conversation locally: $e');
      return null;
    }
  }

  /// Send conversation created response with encrypted user data
  Future<void> _sendConversationCreatedResponse(
      String recipientId, String conversationIdLocal) async {
    try {
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) return;

      final currentSession = SeSessionService().currentSession;
      final userName = currentSession?.displayName ?? 'User $currentUserId';

      // Create user data payload with our display name
      final userData = {
        'userName': userName,
        'sessionId': currentUserId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'conversationId': conversationIdLocal,
      };

      // Encrypt our user data using the recipient's public key
      final encryptedData =
          await EncryptionService.encryptData(userData, recipientId);
      if (encryptedData == null) {
        print(
            '🔑 KeyExchangeService: ❌ Failed to encrypt user data for conversation response');
        return;
      }

      // Send conversation:created event with our encrypted data
      SeSocketService.instance.emit('conversation:created', {
        'recipientId': recipientId,
        'senderId': currentUserId,
        'conversation_id_local': conversationIdLocal,
        'encryptedUserData': encryptedData,
        'timestamp': DateTime.now().toIso8601String(),
      });

      print(
          '🔑 KeyExchangeService: ✅ Conversation created response sent with encrypted user data');
    } catch (e) {
      print(
          '🔑 KeyExchangeService: ❌ Error sending conversation created response: $e');
    }
  }

  /// Handle conversation created event from other users (completes the key exchange flow)
  Future<void> handleConversationCreated(Map<String, dynamic> data) async {
    try {
      final senderId = data['senderId'] as String?;
      final conversationId = data['conversation_id_local'] as String?;
      final encryptedUserData = data['encryptedUserData'] as String?;

      if (senderId == null ||
          conversationId == null ||
          encryptedUserData == null) {
        print('🔑 KeyExchangeService: ❌ Invalid conversation created data');
        return;
      }

      print(
          '🔑 KeyExchangeService: 🔍 Processing conversation created from $senderId');

      // Decrypt the sender's user data
      final decryptedData =
          await EncryptionService.decryptData(encryptedUserData);
      if (decryptedData == null) {
        print('🔑 KeyExchangeService: ❌ Failed to decrypt sender user data');
        return;
      }

      // Parse the decrypted data
      final userData = Map<String, dynamic>.from(decryptedData);
      final userName = userData['userName']?.toString() ?? 'Unknown User';
      final userSessionId = userData['sessionId']?.toString() ?? senderId;

      print(
          '🔑 KeyExchangeService: ✅ Sender user data decrypted: $userName ($userSessionId)');

      // Create conversation locally using the sender's ID as the conversation ID
      final localConversationId =
          await _createConversationLocally(senderId, userName);
      if (localConversationId != null) {
        print(
            '🔑 KeyExchangeService: ✅ Conversation created locally: $localConversationId');

        // Notify UI that conversation was created
        if (_onConversationCreated != null) {
          final conversation = ChatConversation(
            id: localConversationId,
            participant1Id: SeSessionService().currentSessionId!,
            participant2Id: senderId,
            displayName: userName,
            unreadCount: 0,
            isOnline: false,
            lastSeen: null,
          );
          _onConversationCreated!(conversation);
        }
      } else {
        print('🔑 KeyExchangeService: ❌ Failed to create conversation locally');
      }
    } catch (e) {
      print('🔑 KeyExchangeService: ❌ Error handling conversation created: $e');
      rethrow;
    }
  }

  /// Get the public key for a specific sender from storage
  Future<String?> _getSenderPublicKey(String senderId) async {
    try {
      // Try to get the public key from encryption service storage
      return await EncryptionService.getRecipientPublicKey(senderId);
    } catch (e) {
      print(
          '🔑 KeyExchangeService: ⚠️ Could not retrieve public key for $senderId: $e');
      return null;
    }
  }
}
