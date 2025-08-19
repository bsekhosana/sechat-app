import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sechat_app/core/services/encryption_service.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:uuid/uuid.dart';
import 'package:sechat_app/core/services/se_shared_preference_service.dart';
import 'package:sechat_app/features/chat/models/chat_conversation.dart';
import 'package:sechat_app/features/chat/services/message_storage_service.dart';
import 'package:sechat_app/features/notifications/services/notification_manager_service.dart';

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

      // Send key exchange request via socket service
      final success = await SeSocketService().sendKeyExchangeRequest(
        recipientId: recipientId,
        requestData: keyExchangeRequestData,
      );

      if (success) {
        print(
            '🔑 KeyExchangeService: ✅ Key exchange request sent successfully to $recipientId');

        // Create a local record of the sent request
        await _createLocalSentRequest(
            requestId, currentUserId, recipientId, requestPhrase);

        return true;
      } else {
        print(
            '🔑 KeyExchangeService: ❌ Failed to send key exchange request to $recipientId');
        // Remove from pending exchanges if failed
        await _removePendingExchange(recipientId);
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

  /// Process key exchange request from another user
  /// This method should NOT automatically send a response
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
      final success = await SeSocketService().sendKeyExchangeResponse(
        recipientId: senderId,
        accepted: false,
        responseData: {
          'type': 'key_exchange_declined',
          'senderId': currentUserId,
          'recipientId': senderId,
          'requestVersion': keyVersion,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'responseId': const Uuid().v4(),
        },
      );

      if (success) {
        print(
            '🔑 KeyExchangeService: ✅ Key exchange decline sent successfully to $senderId');
      } else {
        print(
            '🔑 KeyExchangeService: ❌ Failed to send key exchange decline to $senderId');
      }

      return success;
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

      final success = await SeSocketService().sendMessage(
        recipientId: contactId,
        message: 'Encryption keys have been updated',
        conversationId: 'key_rotation_$contactId',
        messageId: 'key_rotation_${DateTime.now().millisecondsSinceEpoch}',
        metadata: {
          'type': 'key_rotation_notice',
          'sender_id': currentUserId,
          'new_key_version': await EncryptionService.getKeyPairVersion(),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'notice_id': const Uuid().v4(),
        },
      );

      if (success) {
        print(
            '🔑 KeyExchangeService: ✅ Key rotation notice sent to $contactId');
      } else {
        print(
            '🔑 KeyExchangeService: ❌ Failed to send key rotation notice to $contactId');
      }

      return success;
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
          participant1Id: SeSessionService().currentSessionId!,
          participant2Id: userSessionId,
          displayName: userName,
          conversationId:
              receivedConversationId, // Use their conversation ID for matching
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
          participant1Id: SeSessionService().currentSessionId!,
          participant2Id: userSessionId,
          displayName: userName,
          conversationId: conversationId,
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

  /// Create a new conversation
  Future<ChatConversation?> _createConversation({
    required String participant1Id,
    required String participant2Id,
    required String displayName,
    String? conversationId,
  }) async {
    try {
      final conversation = ChatConversation(
        id: conversationId ?? const Uuid().v4(),
        participant1Id: participant1Id,
        participant2Id: participant2Id,
        displayName: displayName,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Save to database
      await MessageStorageService.instance.saveConversation(conversation);

      print('🔑 KeyExchangeService: ✅ Conversation saved to database');

      // Notify chat list provider to update UI immediately
      try {
        if (_onConversationCreated != null) {
          _onConversationCreated!(conversation);
          print(
              '🔑 KeyExchangeService: ✅ Chat list provider notified via callback');
        } else {
          print(
              '🔑 KeyExchangeService: ⚠️ No conversation created callback set');
        }
      } catch (e) {
        print(
            '🔑 KeyExchangeService: ⚠️ Failed to notify chat list provider: $e');
      }

      // Create notification for new conversation
      try {
        final notificationManager = NotificationManagerService();
        final currentUserId = SeSessionService().currentSessionId;
        final otherUserId =
            participant1Id == currentUserId ? participant2Id : participant1Id;

        await notificationManager.createKeyExchangeNotification(
          type: 'conversation_created',
          senderId: otherUserId,
          senderName: displayName,
          message: 'A new conversation has been created with $displayName',
          metadata: {
            'conversationId': conversation.id,
            'participant1Id': participant1Id,
            'participant2Id': participant2Id,
            'displayName': displayName,
          },
        );
        print(
            '🔑 KeyExchangeService: ✅ Notification created for new conversation');
      } catch (e) {
        print('🔑 KeyExchangeService: ⚠️ Failed to create notification: $e');
      }

      return conversation;
    } catch (e) {
      print('🔑 KeyExchangeService: Error creating conversation: $e');
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
        if (SeSocketService().isReadyToSend()) {
          print(
              '🔑 KeyExchangeService: 🔍 Socket ready, sending user_data_exchange event');
          SeSocketService().emit('user_data_exchange', payload);
          print(
              '🔑 KeyExchangeService: ✅ Initial user data sent to $recipientId');

          // Add a small delay to ensure the event is processed
          await Future.delayed(const Duration(milliseconds: 100));
          print(
              '🔑 KeyExchangeService: ⏱️ Event sent, waiting for processing...');
        } else {
          print('🔑 KeyExchangeService: ❌ Socket not ready to send');
          print(
              '🔑 KeyExchangeService: 🔍 Socket status: ${SeSocketService().getSocketStatus()}');
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
        // Send via socket
        final payload = {
          'recipientId': recipientId,
          'encryptedData': encryptedData,
          'timestamp': DateTime.now().toIso8601String(),
        };

        SeSocketService().emit('user_data_exchange', payload);
        print(
            '🔑 KeyExchangeService: ✅ User data response sent to $recipientId');
      } else {
        print('🔑 KeyExchangeService: ❌ Failed to encrypt user data');
      }
    } catch (e) {
      print('🔑 KeyExchangeService: Error sending user data response: $e');
    }
  }
}
