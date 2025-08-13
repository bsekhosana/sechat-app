import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sechat_app/core/services/encryption_service.dart';
import 'package:sechat_app/core/services/airnotifier_service.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:uuid/uuid.dart';
import 'package:sechat_app/core/services/se_shared_preference_service.dart';

/// Service to handle secure key exchange between users
class KeyExchangeService {
  static KeyExchangeService? _instance;
  static KeyExchangeService get instance =>
      _instance ??= KeyExchangeService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _keyExchangePrefix = 'key_exchange_';
  static const String _pendingExchangesKey = 'pending_key_exchanges';

  // Private constructor
  KeyExchangeService._();

  /// Initialize user's encryption keys if they don't exist
  Future<Map<String, String>> ensureKeysExist() async {
    try {
      // Get keys from session service (current implementation)
      final sessionService = SeSessionService();
      final currentSession = sessionService.currentSession;

      if (currentSession != null && currentSession.publicKey != null) {
        // Keys already exist in session
        final publicKey = currentSession.publicKey!;
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
        final publicKey = newSession!.publicKey!;
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
        'sender_id': currentUserId,
        'public_key': ourKeys['publicKey'],
        'version': ourKeys['version'],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'request_id': requestId,
        'request_phrase':
            requestPhrase ?? 'New encryption key exchange request',
      };

      // Store pending exchange
      await _addPendingExchange(recipientId);

      // Send key exchange request via AirNotifier notification
      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: recipientId,
        title: 'Key Exchange Request',
        body: requestPhrase ?? 'New encryption key exchange request',
        data: keyExchangeRequestData,
        sound: null, // Silent notification
        badge: 0, // No badge
        encrypted:
            false, // Key exchange requests are not encrypted (chicken and egg problem)
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
  Future<bool> processKeyExchangeRequest(Map<String, dynamic> request) async {
    try {
      print('🔑 KeyExchangeService: Processing key exchange request');

      final senderId = request['sender_id'] as String?;
      final senderPublicKey = request['public_key'] as String?;
      final keyVersion = request['version'] as String?;

      if (senderId == null || senderPublicKey == null) {
        throw Exception('Invalid key exchange request');
      }

      // Store sender's public key
      await EncryptionService.storeRecipientPublicKey(
          senderId, senderPublicKey);
      print('🔑 KeyExchangeService: Stored public key for $senderId');

      // Ensure we have our own keys
      final ourKeys = await ensureKeysExist();
      final currentUserId = SeSessionService().currentSessionId;

      if (currentUserId == null) {
        throw Exception('User not logged in');
      }

      // Format key exchange response
      final keyExchangeResponse = {
        'type': 'key_exchange_response',
        'sender_id': currentUserId,
        'recipient_id': senderId,
        'public_key': ourKeys['publicKey'],
        'version': ourKeys['version'],
        'request_version': keyVersion,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Send key exchange response via AirNotifier notification
      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: senderId,
        title: 'Key Exchange Response',
        body: 'Encryption key exchange response received',
        data: {
          'type': 'key_exchange_response',
          'sender_id': currentUserId,
          'recipient_id': senderId,
          'public_key': ourKeys['publicKey'],
          'version': ourKeys['version'],
          'request_version': keyVersion,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'response_id': const Uuid().v4(),
        },
        sound: null, // Silent notification
        badge: 0, // No badge
        encrypted:
            false, // Key exchange responses are not encrypted (chicken and egg problem)
      );

      if (success) {
        print(
            '🔑 KeyExchangeService: ✅ Key exchange response sent successfully to $senderId');
      } else {
        print(
            '🔑 KeyExchangeService: ❌ Failed to send key exchange response to $senderId');
      }

      return success;
    } catch (e) {
      print('🔑 KeyExchangeService: Error processing key exchange request: $e');
      return false;
    }
  }

  /// Process key exchange response from another user
  Future<bool> processKeyExchangeResponse(Map<String, dynamic> response) async {
    try {
      print('🔑 KeyExchangeService: Processing key exchange response');

      final senderId = response['sender_id'] as String?;
      final senderPublicKey = response['public_key'] as String?;

      if (senderId == null || senderPublicKey == null) {
        throw Exception('Invalid key exchange response');
      }

      // Store sender's public key
      await EncryptionService.storeRecipientPublicKey(
          senderId, senderPublicKey);
      print('🔑 KeyExchangeService: Stored public key for $senderId');

      // Remove from pending exchanges
      await _removePendingExchange(senderId);

      return true;
    } catch (e) {
      print(
          '🔑 KeyExchangeService: Error processing key exchange response: $e');
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

      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: contactId,
        title: 'Key Rotation Notice',
        body: 'Encryption keys have been updated',
        data: {
          'type': 'key_rotation_notice',
          'sender_id': currentUserId,
          'new_key_version': await EncryptionService.getKeyPairVersion(),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'notice_id': const Uuid().v4(),
        },
        sound: null, // Silent notification
        badge: 0, // No badge
        encrypted: false, // Key rotation notices are not encrypted
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
}
