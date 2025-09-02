import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:sechat_app/core/services/encryption_service.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/ui_service.dart';
import 'package:uuid/uuid.dart';
import 'package:sechat_app/core/services/se_shared_preference_service.dart';
import 'package:sechat_app/core/services/contact_service.dart';
import 'package:sechat_app/features/chat/models/chat_conversation.dart';
import 'package:sechat_app/features/chat/services/message_storage_service.dart';
import 'package:sechat_app/features/key_exchange/providers/key_exchange_request_provider.dart';
import 'package:sechat_app/core/services/presence_manager.dart';
import 'package:sechat_app/core/utils/conversation_id_generator.dart';
import 'package:sechat_app/main.dart';

/// Service to handle secure key exchange between users
class KeyExchangeService {
  static KeyExchangeService? _instance;
  static KeyExchangeService get instance =>
      _instance ??= KeyExchangeService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _pendingExchangesKey = 'pending_key_exchanges';

  // Callback for when conversations are created
  Function(ChatConversation)? _onConversationCreated;

  // Callback for when user data is exchanged
  Function(String senderId, String displayName)? _onUserDataExchange;

  // Private constructor
  KeyExchangeService._();

  // Store decrypted user data for conversation creation
  Map<String, dynamic>? _decryptedUserData;

  // Track processed user data exchanges to prevent duplicates
  final Set<String> _processedUserDataExchanges = {};

  /// Set callback for when conversations are created
  void setOnConversationCreated(Function(ChatConversation) callback) {
    _onConversationCreated = callback;
  }

  /// Set callback for when user data is exchanged
  void setOnUserDataExchange(
      Function(String senderId, String displayName) callback) {
    _onUserDataExchange = callback;
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
      final _ = {
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

        // show snackbar
        UIService().showSnack(
            'Key exchange request sent successfully to $recipientId',
            isError: false,
            duration: const Duration(seconds: 4));

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
      final responseStatus =
          response['response'] as String?; // Add response status check

      print('🔑 KeyExchangeService: 🔍 Extracted senderId: $senderId');
      print(
          '🔑 KeyExchangeService: 🔍 Extracted senderPublicKey: $senderPublicKey');
      print('🔑 KeyExchangeService: 🔍 Extracted responseType: $responseType');
      print(
          '🔑 KeyExchangeService: 🔍 Extracted responseStatus: $responseStatus');

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

      // If this is an acceptance response, process the encrypted user data and create conversation
      // Check both responseType (legacy) and responseStatus (new format)
      final isAccepted = (responseType == 'key_exchange_accepted' ||
          responseType == 'key_exchange_response' ||
          responseStatus == 'accepted');

      if (isAccepted) {
        print(
            '🔑 KeyExchangeService: ✅ Key exchange accepted, processing encrypted user data');
        print(
            '🔑 KeyExchangeService: 🔍 Response type: $responseType, Response status: $responseStatus');

        // Check if the response includes encrypted user data
        final encryptedUserData = response['encryptedUserData'] as String?;
        final receivedConversationId = response['conversationId'] as String?;

        print(
            '🔑 KeyExchangeService: 🔍 Encrypted user data present: ${encryptedUserData != null}');
        print(
            '🔑 KeyExchangeService: 🔍 Received conversation ID: $receivedConversationId');

        if (encryptedUserData != null) {
          print(
              '🔑 KeyExchangeService: 🔍 Found encrypted user data, processing...');

          // Generate conversation ID locally if not provided by server
          final conversationId = receivedConversationId ??
              _generateConsistentConversationId(
                  SeSessionService().currentSessionId!, senderId);

          print(
              '🔑 KeyExchangeService: 🔍 Using conversation ID: $conversationId');

          // Process the encrypted user data to create conversation
          print(
              '🔑 KeyExchangeService: 🚀 About to call processUserDataExchange...');
          print(
              '🔑 KeyExchangeService: 🔍 Parameters - senderId: $senderId, encryptedData: ${encryptedUserData.substring(0, 50)}..., conversationId: $conversationId');
          final success = await processUserDataExchange(
            senderId: senderId,
            encryptedData: encryptedUserData,
            conversationId: conversationId,
          );
          print(
              '🔑 KeyExchangeService: 🔍 processUserDataExchange returned: $success');

          if (success) {
            print(
                '🔑 KeyExchangeService: ✅ Conversation created from accept event');

            // Send back our user data to complete the exchange
            await _sendInitialUserData(senderId);
          } else {
            print(
                '🔑 KeyExchangeService: ❌ Failed to create conversation from accept event');
          }
        } else {
          print(
              '🔑 KeyExchangeService: ℹ️ No encrypted user data in accept event, using fallback');
          // Fallback to old method
          await _sendInitialUserData(senderId);
        }

        // CRITICAL: Notify KeyExchangeRequestProvider about the acceptance for UI updates
        try {
          // Get the provider instance from the main context (same instance the UI is listening to)
          final provider = Provider.of<KeyExchangeRequestProvider>(
              navigatorKey.currentContext!,
              listen: false);
          print(
              '🔑 KeyExchangeService: 🔍 Got provider instance from context: ${provider.hashCode}');
          await provider.handleKeyExchangeAccepted(response);
          print(
              '🔑 KeyExchangeService: ✅ Notified KeyExchangeRequestProvider about acceptance');
        } catch (e) {
          print(
              '🔑 KeyExchangeService: ❌ Error notifying KeyExchangeRequestProvider: $e');
        }
      } else {
        print(
            '🔑 KeyExchangeService: ℹ️ Response is not acceptance - Type: $responseType, Status: $responseStatus');
      }

      return true;
    } catch (e) {
      print(
          '🔑 KeyExchangeService: ❌ Error processing key exchange response: $e');
      return false;
    }
  }

  /// Handle key exchange error events
  Future<void> handleKeyExchangeError(Map<String, dynamic> errorData) async {
    try {
      print('🔑 KeyExchangeService: Handling key exchange error');
      print('🔑 KeyExchangeService: Error data: $errorData');

      final errorCode = errorData['errorCode']?.toString();
      final requestId = errorData['requestId']?.toString();
      final recipientId = errorData['recipientId']?.toString();

      // Remove from pending exchanges if it was a request we sent
      if (recipientId != null) {
        await _removePendingExchange(recipientId);
        print(
            '🔑 KeyExchangeService: Removed pending exchange for $recipientId due to error');
      }

      // Update local request status to failed
      if (requestId != null) {
        await _updateRequestStatus(requestId, 'failed');
        print(
            '🔑 KeyExchangeService: Updated request $requestId status to failed');
      }

      // Notify KeyExchangeRequestProvider about the error
      try {
        // Import the provider to handle UI updates
        final provider = KeyExchangeRequestProvider();
        provider.handleKeyExchangeError(errorData);
        print(
            '🔑 KeyExchangeService: Notified KeyExchangeRequestProvider about error');
      } catch (e) {
        print(
            '🔑 KeyExchangeService: Error notifying KeyExchangeRequestProvider: $e');
      }

      // Log the error for debugging
      print(
          '🔑 KeyExchangeService: Key exchange failed with error: $errorCode');
    } catch (e) {
      print('🔑 KeyExchangeService: Error handling key exchange error: $e');
    }
  }

  /// Handle key exchange declined events
  Future<void> handleKeyExchangeDeclined(
      Map<String, dynamic> declineData) async {
    try {
      print('🔑 KeyExchangeService: Handling key exchange declined');
      print('🔑 KeyExchangeService: Decline data: $declineData');

      final senderId = declineData['senderId']?.toString();
      final requestId = declineData['requestId']?.toString();
      final reason = declineData['reason']?.toString();

      // Remove from pending exchanges if it was a request we sent
      if (senderId != null) {
        await _removePendingExchange(senderId);
        print(
            '🔑 KeyExchangeService: Removed pending exchange for $senderId due to decline');
      }

      // Update local request status to declined
      if (requestId != null) {
        await _updateRequestStatus(requestId, 'declined');
        print(
            '🔑 KeyExchangeService: Updated request $requestId status to declined');
      }

      // Notify KeyExchangeRequestProvider about the decline
      try {
        final provider = KeyExchangeRequestProvider();
        await provider.handleKeyExchangeDeclined(declineData);
        print(
            '🔑 KeyExchangeService: Notified KeyExchangeRequestProvider about decline');
      } catch (e) {
        print(
            '🔑 KeyExchangeService: Error notifying KeyExchangeRequestProvider: $e');
      }

      // Log the decline for debugging
      print(
          '🔑 KeyExchangeService: Key exchange declined by $senderId: $reason');
    } catch (e) {
      print('🔑 KeyExchangeService: Error handling key exchange decline: $e');
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

  /// Update request status in local storage
  Future<void> _updateRequestStatus(String requestId, String status) async {
    try {
      // This would typically update the status in the KeyExchangeRequestProvider
      // For now, we'll just log the status update
      print(
          '🔑 KeyExchangeService: Updating request $requestId status to $status');

      // TODO: Implement actual status update in KeyExchangeRequestProvider
      // This could involve notifying the provider to update the request status
    } catch (e) {
      print('🔑 KeyExchangeService: Error updating request status: $e');
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
        messageId: 'key_rotation_${DateTime.now().millisecondsSinceEpoch}',
        recipientId: contactId,
        body: 'Encryption keys have been updated',
        conversationId:
            contactId, // CRITICAL: Use recipient's sessionId as conversationId
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
      print(
          '🔑 KeyExchangeService: 🔍 Current session ID: ${SeSessionService().currentSessionId}');
      print(
          '🔑 KeyExchangeService: 🔍 Method parameters validated successfully');
      print(
          '🔑 KeyExchangeService: 🔍 Method entry point reached successfully');

      // Decrypt the user data
      print('🔑 KeyExchangeService: 🔐 Attempting to decrypt user data...');
      print('🔑 KeyExchangeService: 🔐 Encrypted data: $encryptedData');
      print(
          '🔑 KeyExchangeService: 🔐 Calling EncryptionService.decryptData...');
      final decryptedData = await EncryptionService.decryptData(encryptedData);
      print('🔑 KeyExchangeService: 🔐 Decryption result: $decryptedData');
      print(
          '🔑 KeyExchangeService: 🔐 Decryption completed, checking result...');

      if (decryptedData == null) {
        print('🔑 KeyExchangeService: ❌ Failed to decrypt user data');
        return false;
      }

      print('🔑 KeyExchangeService: 🔐 User data decrypted successfully');
      print('🔑 KeyExchangeService: 🔐 Decrypted data: $decryptedData');

      // Parse the decrypted data
      final userData = Map<String, dynamic>.from(decryptedData);
      print('🔑 KeyExchangeService: 🔐 Parsed user data: $userData');

      final userName = userData['userName'] as String?;
      final userSessionId = userData['sessionId'] as String?;
      final receivedConversationId = userData['conversationId'] as String?;

      print('🔑 KeyExchangeService: 🔐 Extracted userName: $userName');
      print(
          '🔑 KeyExchangeService: 🔐 Extracted userSessionId: $userSessionId');
      print(
          '🔑 KeyExchangeService: 🔐 Extracted receivedConversationId: $receivedConversationId');

      if (userName == null || userSessionId == null) {
        print('🔑 KeyExchangeService: ❌ Invalid user data format');
        return false;
      }

      print(
          '🔑 KeyExchangeService: ✅ Decrypted user data: $userName ($userSessionId)');

      // Store decrypted data for conversation creation
      print(
          '🔑 KeyExchangeService: 💾 Storing decrypted user data for conversation creation...');
      _decryptedUserData = decryptedData;
      print(
          '🔑 KeyExchangeService: 💾 _decryptedUserData set to: $_decryptedUserData');

      // If we received a conversation ID, this is the final response from the recipient
      // Create a matching conversation using their ID
      if (receivedConversationId != null) {
        print(
            '🔑 KeyExchangeService: 📋 Received conversation ID: $receivedConversationId');

        await _createConversation(
          recipientId:
              userSessionId, // ✅ Use the actual user ID, not the conversation ID
          conversationId:
              receivedConversationId, // ✅ Pass the conversation ID separately
        );

        print('🔑 KeyExchangeService: ✅ Matching conversation created');
        return true;
      } else {
        // This is the initial user data from the sender, create conversation and send response
        await _createConversation(
          recipientId: userSessionId,
        );

        print('🔑 KeyExchangeService: ✅ Conversation created');

        // Send our user data back to complete the exchange
        await _sendUserDataResponse(senderId, userSessionId);

        return true;
      }
    } catch (e) {
      print('🔑 KeyExchangeService: Error processing user data exchange: $e');
      return false;
    }
  }

  /// Create conversation after successful key exchange
  Future<void> _createConversation(
      {required String recipientId, String? conversationId}) async {
    try {
      print('🔑 KeyExchangeService: Creating conversation: $recipientId');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🔑 KeyExchangeService: ❌ No current session ID');
        return;
      }

      // Get display name from decrypted user data if available
      String? displayName;
      print(
          '🔑 KeyExchangeService: 🔍 _decryptedUserData: $_decryptedUserData');
      if (_decryptedUserData != null) {
        displayName = _decryptedUserData!['userName'] as String?;
        print(
            '🔑 KeyExchangeService: 🔍 Using display name from user data: $displayName');
      } else {
        print(
            '🔑 KeyExchangeService: ⚠️ _decryptedUserData is null, will use fallback display name');
        displayName = 'User $recipientId';
      }

      // CRITICAL: Use provided conversation ID if available, otherwise generate one
      final finalConversationId = conversationId ??
          _generateConsistentConversationId(currentUserId, recipientId);

      print(
          '🔑 KeyExchangeService: 🔍 Using conversation ID: $finalConversationId');
      print('🔑 KeyExchangeService: 🔍 Current user ID: $currentUserId');
      print('🔑 KeyExchangeService: 🔍 Recipient ID: $recipientId');

      // Create conversation with proper display name and consistent ID
      final conversation = ChatConversation(
        id: finalConversationId, // Use the final conversation ID
        participant1Id: currentUserId,
        participant2Id: recipientId,
        displayName: displayName, // Set the display name from user data
        metadata: {
          'user_names': {
            recipientId: displayName ?? 'Unknown User',
            currentUserId:
                SeSessionService().currentSession?.displayName ?? 'You',
          },
          'key_exchange_completed': true,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      print(
          '🔑 KeyExchangeService: 🔍 Created conversation object: ${conversation.id}');
      print(
          '🔑 KeyExchangeService: 🔍 Conversation participants: ${conversation.participant1Id} <-> ${conversation.participant2Id}');

      // Save to storage
      print(
          '🔑 KeyExchangeService: 💾 Saving conversation to MessageStorageService...');
      await MessageStorageService.instance.saveConversation(conversation);
      print(
          '🔑 KeyExchangeService: ✅ Conversation saved to storage: ${conversation.id}');

      // Notify UI that conversation was created
      print(
          '🔑 KeyExchangeService: 🔔 Checking conversation creation callback...');
      if (_onConversationCreated != null) {
        print(
            '🔑 KeyExchangeService: 🔔 Calling conversation creation callback...');
        _onConversationCreated!(conversation);
        print('🔑 KeyExchangeService: ✅ UI notified of conversation creation');
      } else {
        print(
            '🔑 KeyExchangeService: ⚠️ No conversation creation callback set');
      }

      print(
          '🔑 KeyExchangeService: ✅ Conversation created and saved to storage');
    } catch (e) {
      print('🔑 KeyExchangeService: ❌ Error creating conversation: $e');
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

      // CRITICAL: Generate consistent conversation ID for both users
      final consistentConversationId =
          _generateConsistentConversationId(currentUserId, recipientId);

      // Create user data payload
      final userData = {
        'userName': userName,
        'sessionId': currentUserId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'conversationId':
            consistentConversationId, // Include conversation ID for matching
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
        if (SeSocketService.instance.isConnected) {
          print(
              '🔑 KeyExchangeService: 🔍 Socket connected, sending user_data_exchange event');

          // Use SeSocketService for user data exchange
          try {
            // CRITICAL: Generate consistent conversation ID for both users
            final currentUserIdForExchange =
                SeSessionService().currentSessionId ?? '';
            final consistentConversationId = _generateConsistentConversationId(
                currentUserIdForExchange, recipientId);

            SeSocketService.instance.sendUserDataExchange(
              recipientId: recipientId,
              encryptedData: encryptedData,
              conversationId: consistentConversationId, // Add conversation ID
            );
            print(
                '🔑 KeyExchangeService: ✅ Initial user data sent to $recipientId using SeSocketService with conversationId: $consistentConversationId');
          } catch (e) {
            print(
                '🔑 KeyExchangeService: ⚠️ Warning: Could not send user data exchange: $e');
          }

          // Add a small delay to ensure the event is processed
          await Future.delayed(const Duration(milliseconds: 100));
          print(
              '🔑 KeyExchangeService: ⏱️ Event sent, waiting for processing...');
        } else {
          print('🔑 KeyExchangeService: ❌ Socket not connected');
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

      // CRITICAL: Generate consistent conversation ID for both users
      final consistentConversationId =
          _generateConsistentConversationId(currentUserId, recipientId);

      // Create user data payload
      final userData = {
        'userName': userName,
        'sessionId': currentUserId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'conversationId':
            consistentConversationId, // Include conversation ID for matching
      };

      // Encrypt the user data
      final encryptedData = await EncryptionService.encryptData(
        userData,
        recipientId,
      );

      if (encryptedData != null) {
        // Check socket connection before sending
        if (SeSocketService.instance.isConnected) {
          // Use the correct server event format: user_data_exchange:send
          try {
            SeSocketService.instance.emit('user_data_exchange:send', {
              'recipientId': recipientId,
              'senderId': currentUserId,
              'encryptedData': encryptedData,
              'conversationId': consistentConversationId,
              'timestamp': DateTime.now().toIso8601String(),
            });
            print(
                '🔑 KeyExchangeService: ✅ User data response sent to $recipientId using user_data_exchange:send');
          } catch (e) {
            print(
                '🔑 KeyExchangeService: ❌ Error sending user data response: $e');
          }
        } else {
          print(
              '🔑 KeyExchangeService: ⚠️ Socket not connected, cannot send user data response');
        }
      } else {
        print('🔑 KeyExchangeService: ❌ Failed to encrypt user data');
      }
    } catch (e) {
      print('🔑 KeyExchangeService: Error sending user data response: $e');
    }
  }

  /// Generate consistent conversation ID that both users will have
  /// This ensures messages appear in the same conversation for both users
  /// Updated to match server's new consistent ID format
  String _generateConsistentConversationId(String user1Id, String user2Id) {
    return ConversationIdGenerator.generateConsistentConversationId(
        user1Id, user2Id);
  }

  /// Handle user data exchange data received from socket
  Future<void> handleUserDataExchange(Map<String, dynamic> data) async {
    try {
      print('🔑 KeyExchangeService: 🔍🔍🔍 USER DATA EXCHANGE HANDLER CALLED!');
      print('🔑 KeyExchangeService: 🔍🔍🔍 Data: $data');
      print('🔑 KeyExchangeService: 🔍🔍🔍 Data keys: ${data.keys.toList()}');

      final senderId = data['senderId'] as String?;
      final encryptedData = data['encryptedData'] as String?;
      final conversationId = data['conversationId'] as String?;

      if (senderId == null || encryptedData == null) {
        print(
            '🔑 KeyExchangeService: ❌ Missing senderId or encryptedData in user data exchange');
        return;
      }

      // Create a unique key for this exchange to prevent duplicates
      final exchangeKey = '$senderId:$encryptedData';
      if (_processedUserDataExchanges.contains(exchangeKey)) {
        print(
            '🔑 KeyExchangeService: ℹ️ User data exchange already processed for $senderId, skipping');
        return;
      }

      // CRITICAL: Check if we already have a conversation using consistent conversation ID
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId != null) {
        final consistentConversationId =
            _generateConsistentConversationId(currentUserId, senderId);

        // Check if conversation already exists by consistent ID
        final existingConversation = await MessageStorageService.instance
            .getConversation(consistentConversationId);

        if (existingConversation != null) {
          print(
              '🔑 KeyExchangeService: ℹ️ Conversation already exists with consistent ID: $consistentConversationId, skipping creation');
          return;
        }
      }

      // Decrypt the user data
      final decryptedData = await _decryptUserData(encryptedData, senderId);
      if (decryptedData == null) {
        print('🔑 KeyExchangeService: ❌ Failed to decrypt user data');
        return;
      }

      // Store decrypted data for conversation creation
      print(
          '🔑 KeyExchangeService: 💾 Storing decrypted user data for conversation creation...');
      _decryptedUserData = decryptedData;
      print(
          '🔑 KeyExchangeService: 💾 _decryptedUserData set to: $_decryptedUserData');

      print('🔑 KeyExchangeService: ✅ User data decrypted successfully');

      // Create conversation
      await _createConversation(recipientId: senderId);

      // CRITICAL: Generate consistent conversation ID for response
      final currentUserIdForResponse = SeSessionService().currentSessionId;
      final consistentConversationId = currentUserIdForResponse != null
          ? _generateConsistentConversationId(
              currentUserIdForResponse, senderId)
          : null;

      // Send response user data
      await _sendUserDataResponse(senderId, consistentConversationId ?? '');

      // CRITICAL: Add contact after successful key exchange
      _addContactAfterKeyExchange(senderId, decryptedData);

      // Mark this exchange as processed to prevent duplicates
      _processedUserDataExchanges.add(exchangeKey);
      print('🔑 KeyExchangeService: ✅ User data exchange marked as processed');
    } catch (e) {
      print('🔑 KeyExchangeService: ❌ Error handling user data exchange: $e');
    }
  }

  /// Decrypt user data received from another user
  Future<Map<String, dynamic>?> _decryptUserData(
      String encryptedData, String senderId) async {
    try {
      final decryptedData = await EncryptionService.decryptData(encryptedData);
      if (decryptedData != null) {
        return Map<String, dynamic>.from(decryptedData);
      }
      return null;
    } catch (e) {
      print('🔑 KeyExchangeService: ❌ Error decrypting user data: $e');
      return null;
    }
  }

  /// Add contact after successful key exchange
  void _addContactAfterKeyExchange(
      String contactSessionId, Map<String, dynamic> userData) {
    try {
      print(
          '🔑 KeyExchangeService: 🔗 Adding contact after successful key exchange: $contactSessionId');

      // Get display name from user data - check both userName and displayName fields
      final displayName = userData['userName'] as String? ??
          userData['displayName'] as String? ??
          contactSessionId;

      // Add contact via PresenceManager
      final presenceManager = PresenceManager.instance;
      presenceManager.addNewContact(contactSessionId, displayName);

      print(
          '🔑 KeyExchangeService: ✅ Contact added successfully: $displayName');
    } catch (e) {
      print(
          '🔑 KeyExchangeService: ❌ Error adding contact after key exchange: $e');
    }
  }

  /// Create conversation locally in the database
  Future<String?> _createConversationLocally(
      String participantId, String participantName) async {
    try {
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) return null;

      // CRITICAL: Use consistent conversation ID for both users
      final conversationId =
          _generateConsistentConversationId(currentUserId, participantId);

      // Create conversation in database
      final conversation = ChatConversation(
        id: conversationId,
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

      // Check socket connection before sending
      if (SeSocketService.instance.isConnected) {
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
      } else {
        print(
            '🔑 KeyExchangeService: ⚠️ Socket not connected, cannot send conversation created response');
      }
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
      final localConversationId = userSessionId;
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

        // CRITICAL: Trigger 2-way presence update with the new contact
        try {
          print(
              '🔑 KeyExchangeService: 🔄 Triggering 2-way presence update with new contact: $senderId');

          // Add the new contact to our contact list
          final contactService = ContactService.instance;
          await contactService.addContact(senderId, userName);

          // Trigger presence sync with the new contact
          final presenceManager = PresenceManager.instance;
          // For now, just broadcast presence to the new contact
          SeSocketService.instance
              .updatePresence(true, specificUsers: [senderId]);

          print(
              '🔑 KeyExchangeService: ✅ 2-way presence update completed for new contact: $senderId');
        } catch (e) {
          print(
              '🔑 KeyExchangeService: ⚠️ Failed to trigger presence update for new contact: $e');
        }
      } else {
        print('🔑 KeyExchangeService: ❌ Failed to create conversation locally');
      }
    } catch (e) {
      print('🔑 KeyExchangeService: ❌ Error handling conversation created: $e');
      rethrow;
    }
  }

  /// Handle key exchange accepted events (when someone accepts our request)
  Future<void> handleKeyExchangeAccepted(Map<String, dynamic> data) async {
    try {
      print('🔑 KeyExchangeService: Handling key exchange accepted');
      print('🔑 KeyExchangeService: Accept data: $data');

      final senderId = data['senderId']?.toString();
      final publicKey = data['publicKey']?.toString();
      final requestId = data['requestId']?.toString();
      final conversationId = data['conversationId']?.toString();

      if (senderId == null || publicKey == null || requestId == null) {
        print('🔑 KeyExchangeService: ❌ Invalid key exchange accept data');
        return;
      }

      print('🔑 KeyExchangeService: ✅ Key exchange accepted by $senderId');

      // Store the sender's public key for future encryption
      await _storeRecipientPublicKey(senderId, publicKey);
      print('🔑 KeyExchangeService: ✅ Stored public key for $senderId');

      // Notify KeyExchangeRequestProvider about the acceptance
      try {
        final provider = KeyExchangeRequestProvider();
        await provider.handleKeyExchangeAccepted(data);
        print(
            '🔑 KeyExchangeService: Notified KeyExchangeRequestProvider about acceptance');
      } catch (e) {
        print(
            '🔑 KeyExchangeService: ❌ Error notifying KeyExchangeRequestProvider: $e');
      }

      // Now we can send encrypted user data since we have their public key
      await _sendInitialUserData(senderId);
    } catch (e) {
      print(
          '🔑 KeyExchangeService: ❌ Error handling key exchange accepted: $e');
      rethrow;
    }
  }

  /// Handle key exchange response (when someone accepts our request)
  Future<void> handleKeyExchangeResponse(Map<String, dynamic> data) async {
    try {
      print('🔑 KeyExchangeService: 🔍 Processing key exchange response');
      print('🔑 KeyExchangeService: 🔍 Response data: $data');

      final senderId = data['senderId']?.toString();
      final publicKey = data['publicKey']?.toString();
      final responseId = data['responseId']?.toString();
      final requestVersion = data['requestVersion']?.toString();

      if (senderId == null || publicKey == null) {
        print('🔑 KeyExchangeService: ❌ Invalid key exchange response data');
        return;
      }

      print('🔑 KeyExchangeService: ✅ Received public key from $senderId');

      // CRITICAL: Store the sender's public key for future encryption
      await _storeRecipientPublicKey(senderId, publicKey);
      print('🔑 KeyExchangeService: ✅ Stored public key for $senderId');

      // Now we can send encrypted user data since we have their public key
      await _sendInitialUserData(senderId);
    } catch (e) {
      print(
          '🔑 KeyExchangeService: ❌ Error handling key exchange response: $e');
      rethrow;
    }
  }

  /// Store a recipient's public key for future encryption
  Future<void> _storeRecipientPublicKey(
      String recipientId, String publicKey) async {
    try {
      // Store the public key using EncryptionService
      await EncryptionService.storeRecipientPublicKey(recipientId, publicKey);
      print('🔑 KeyExchangeService: ✅ Public key stored for $recipientId');
    } catch (e) {
      print(
          '🔑 KeyExchangeService: ❌ Failed to store public key for $recipientId: $e');
      throw Exception('Failed to store public key: $e');
    }
  }

  /// Get a sender's public key from storage
  Future<String?> _getSenderPublicKey(String senderId) async {
    try {
      final publicKey = await EncryptionService.getRecipientPublicKey(senderId);
      return publicKey;
    } catch (e) {
      print(
          '🔑 KeyExchangeService: ❌ Failed to get public key for $senderId: $e');
      return null;
    }
  }
}
