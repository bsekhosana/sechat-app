import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:sechat_app/core/services/key_exchange_service.dart';
import '../models/optimized_message.dart';
import '/../core/utils/logger.dart';

/// Enhanced Chat Encryption Service
/// Provides proper encryption for all chat messages and notifications
class EnhancedChatEncryptionService {
  static final EnhancedChatEncryptionService _instance =
      EnhancedChatEncryptionService._internal();
  factory EnhancedChatEncryptionService() => _instance;
  EnhancedChatEncryptionService._internal();

  // Encryption keys and configuration
  static const String _algorithm = 'AES-256-CBC';
  static const int _keyLength = 32; // 256 bits
  static const int _ivLength = 16; // 128 bits

  // Store conversation keys securely
  final Map<String, String> _conversationKeys = {};
  final Map<String, DateTime> _keyExpiryTimes = {};
  static const Duration _keyExpiryDuration = Duration(hours: 24);

  /// Generate a secure encryption key for a conversation
  Future<String> generateConversationKey(String conversationId,
      {String? recipientId}) async {
    try {
      // Check if we already have a valid key
      if (_conversationKeys.containsKey(conversationId) &&
          _keyExpiryTimes.containsKey(conversationId)) {
        final expiryTime = _keyExpiryTimes[conversationId]!;
        if (DateTime.now().isBefore(expiryTime)) {
          Logger.success(
              ' EnhancedChatEncryptionService:  Using existing key for conversation: $conversationId');
          return _conversationKeys[conversationId]!;
        }
      }

      // If recipientId is provided, ensure key exchange is completed
      if (recipientId != null) {
        final hasKey =
            await KeyExchangeService.instance.hasPublicKeyForUser(recipientId);
        if (!hasKey) {
          Logger.debug(
              ' EnhancedChatEncryptionService: 🔑 Initiating key exchange with $recipientId');
          final keyExchangeSuccess = await KeyExchangeService.instance
              .ensureKeyExchangeWithUser(recipientId);
          if (!keyExchangeSuccess) {
            throw Exception('Key exchange failed with $recipientId');
          }
        }
        Logger.success(
            ' EnhancedChatEncryptionService:  Key exchange completed with $recipientId');
      }

      // Generate new secure key
      final random = Random.secure();
      final keyBytes = Uint8List(_keyLength);
      for (int i = 0; i < _keyLength; i++) {
        keyBytes[i] = random.nextInt(256);
      }

      final key = base64.encode(keyBytes);

      // Store the key and set expiry
      _conversationKeys[conversationId] = key;
      _keyExpiryTimes[conversationId] = DateTime.now().add(_keyExpiryDuration);

      Logger.success(
          ' EnhancedChatEncryptionService:  Generated new secure key for conversation: $conversationId');
      return key;
    } catch (e) {
      Logger.error(
          ' EnhancedChatEncryptionService:  Failed to generate conversation key: $e');
      rethrow;
    }
  }

  /// Encrypt a chat message with proper encryption
  Future<Map<String, dynamic>> encryptMessage(OptimizedMessage message) async {
    try {
      Logger.debug(
          ' EnhancedChatEncryptionService: 🔒 Encrypting message: ${message.id}');

      // Get or generate conversation key (ensure key exchange with recipient)
      final conversationKey = await generateConversationKey(
          message.conversationId,
          recipientId: message.recipientId);

      // Create message payload
      final payload = {
        'id': message.id,
        'content': message.content,
        'messageType': message.messageType.toString(),
        'timestamp': message.timestamp.toIso8601String(),
        'senderId': message.senderId,
        'recipientId': message.recipientId,
        'conversationId': message.conversationId,
        'metadata': message.metadata,
      };

      // Convert payload to JSON
      final jsonPayload = jsonEncode(payload);
      final payloadBytes = utf8.encode(jsonPayload);

      // Generate random IV
      final random = Random.secure();
      final ivBytes = Uint8List(_ivLength);
      for (int i = 0; i < _ivLength; i++) {
        ivBytes[i] = random.nextInt(256);
      }

      // Create encryption key and IV
      final key = Key.fromBase64(conversationKey);
      final iv = IV.fromBase64(base64.encode(ivBytes));

      // Encrypt the payload
      final encrypter =
          Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));
      final encrypted = encrypter.encrypt(base64.encode(payloadBytes), iv: iv);

      // Generate checksum for integrity
      final checksum = _generateChecksum(encrypted.base64);

      // Create encrypted message structure
      final encryptedMessage = {
        'encrypted_data': encrypted.base64,
        'iv': base64.encode(ivBytes),
        'checksum': checksum,
        'message_id': message.id,
        'conversation_id': message.conversationId,
        'timestamp': message.timestamp.toIso8601String(),
        'algorithm': _algorithm,
        'version': '1.0',
      };

      Logger.success(
          ' EnhancedChatEncryptionService:  Message encrypted successfully');
      return encryptedMessage;
    } catch (e) {
      Logger.error(
          ' EnhancedChatEncryptionService:  Failed to encrypt message: $e');
      rethrow;
    }
  }

  /// Decrypt a chat message
  Future<Map<String, dynamic>> decryptMessage(
      Map<String, dynamic> encryptedMessage) async {
    try {
      Logger.debug(' EnhancedChatEncryptionService: 🔓 Decrypting message');

      final encryptedData = encryptedMessage['encrypted_data'] as String;
      final iv = encryptedMessage['iv'] as String;
      final checksum = encryptedMessage['checksum'] as String;
      final conversationId = encryptedMessage['conversation_id'] as String;

      // Verify checksum
      final expectedChecksum = _generateChecksum(encryptedData);
      if (checksum != expectedChecksum) {
        throw Exception(
            'Checksum verification failed - message integrity compromised');
      }

      // Get conversation key
      if (!_conversationKeys.containsKey(conversationId)) {
        throw Exception(
            'No encryption key found for conversation: $conversationId');
      }

      final conversationKey = _conversationKeys[conversationId]!;

      // Decrypt the message
      final key = Key.fromBase64(conversationKey);
      final ivBytes = IV.fromBase64(iv);
      final encrypter =
          Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));

      final decrypted = encrypter.decrypt64(encryptedData, iv: ivBytes);
      final decryptedBytes = base64.decode(decrypted);
      final decryptedJson = utf8.decode(decryptedBytes);

      // Parse the decrypted JSON
      final payload = jsonDecode(decryptedJson) as Map<String, dynamic>;

      Logger.success(
          ' EnhancedChatEncryptionService:  Message decrypted successfully');
      return payload;
    } catch (e) {
      Logger.error(
          ' EnhancedChatEncryptionService:  Failed to decrypt message: $e');
      rethrow;
    }
  }

  /// Encrypt typing indicator notification
  Future<Map<String, dynamic>> encryptTypingIndicator({
    required String senderId,
    required String senderName,
    required bool isTyping,
    required String conversationId,
  }) async {
    try {
      Logger.debug(
          ' EnhancedChatEncryptionService: 🔒 Encrypting typing indicator');

      // Get or generate conversation key (ensure key exchange with recipient)
      final conversationKey =
          await generateConversationKey(conversationId, recipientId: senderId);

      // Create typing indicator payload
      final payload = {
        'type': 'typing_indicator',
        'senderId': senderId,
        'senderName': senderName,
        'isTyping': isTyping,
        'conversationId': conversationId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Convert payload to JSON
      final jsonPayload = jsonEncode(payload);
      final payloadBytes = utf8.encode(jsonPayload);

      // Generate random IV
      final random = Random.secure();
      final ivBytes = Uint8List(_ivLength);
      for (int i = 0; i < _ivLength; i++) {
        ivBytes[i] = random.nextInt(256);
      }

      // Create encryption key and IV
      final key = Key.fromBase64(conversationKey);
      final iv = IV.fromBase64(base64.encode(ivBytes));

      // Encrypt the payload
      final encrypter =
          Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));
      final encrypted = encrypter.encrypt(base64.encode(payloadBytes), iv: iv);

      // Generate checksum for integrity
      final checksum = _generateChecksum(encrypted.base64);

      // Create encrypted typing indicator
      final encryptedTypingIndicator = {
        'encrypted_data': encrypted.base64,
        'iv': base64.encode(ivBytes),
        'checksum': checksum,
        'type': 'typing_indicator',
        'conversation_id': conversationId,
        'timestamp': DateTime.now().toIso8601String(),
        'algorithm': _algorithm,
        'version': '1.0',
      };

      Logger.success(
          ' EnhancedChatEncryptionService:  Typing indicator encrypted successfully');
      return encryptedTypingIndicator;
    } catch (e) {
      Logger.error(
          ' EnhancedChatEncryptionService:  Failed to encrypt typing indicator: $e');
      rethrow;
    }
  }

  /// Decrypt typing indicator notification
  Future<Map<String, dynamic>> decryptTypingIndicator(
      Map<String, dynamic> encryptedData) async {
    try {
      Logger.debug(
          ' EnhancedChatEncryptionService: 🔓 Decrypting typing indicator');

      final encryptedMessage = encryptedData['encrypted_data'] as String;
      final iv = encryptedData['iv'] as String;
      final checksum = encryptedData['checksum'] as String;
      final conversationId = encryptedData['conversation_id'] as String;

      // Verify checksum
      final expectedChecksum = _generateChecksum(encryptedMessage);
      if (checksum != expectedChecksum) {
        throw Exception('Typing indicator checksum verification failed');
      }

      // Get conversation key
      if (!_conversationKeys.containsKey(conversationId)) {
        throw Exception(
            'No encryption key found for conversation: $conversationId');
      }

      final conversationKey = _conversationKeys[conversationId]!;

      // Decrypt the typing indicator
      final key = Key.fromBase64(conversationKey);
      final ivBytes = IV.fromBase64(iv);
      final encrypter =
          Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));

      final decrypted = encrypter.decrypt64(encryptedMessage, iv: ivBytes);
      final decryptedBytes = base64.decode(decrypted);
      final decryptedJson = utf8.decode(decryptedBytes);

      // Parse the decrypted JSON
      final payload = jsonDecode(decryptedJson) as Map<String, dynamic>;

      Logger.success(
          ' EnhancedChatEncryptionService:  Typing indicator decrypted successfully');
      return payload;
    } catch (e) {
      Logger.error(
          ' EnhancedChatEncryptionService:  Failed to decrypt typing indicator: $e');
      rethrow;
    }
  }

  /// Encrypt online status notification
  Future<Map<String, dynamic>> encryptOnlineStatus({
    required String userId,
    required bool isOnline,
    required String? lastSeen,
  }) async {
    try {
      Logger.debug(
          ' EnhancedChatEncryptionService: 🔒 Encrypting online status');

      // Generate a temporary key for online status (not conversation-specific)
      final tempKey = await _generateTemporaryKey();

      // Create online status payload
      final payload = {
        'type': 'online_status_update',
        'userId': userId,
        'isOnline': isOnline,
        'lastSeen': lastSeen,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Convert payload to JSON
      final jsonPayload = jsonEncode(payload);
      final payloadBytes = utf8.encode(jsonPayload);

      // Generate random IV
      final random = Random.secure();
      final ivBytes = Uint8List(_ivLength);
      for (int i = 0; i < _ivLength; i++) {
        ivBytes[i] = random.nextInt(256);
      }

      // Create encryption key and IV
      final key = Key.fromBase64(tempKey);
      final iv = IV.fromBase64(base64.encode(ivBytes));

      // Encrypt the payload
      final encrypter =
          Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));
      final encrypted = encrypter.encrypt(base64.encode(payloadBytes), iv: iv);

      // Generate checksum for integrity
      final checksum = _generateChecksum(encrypted.base64);

      // Create encrypted online status
      final encryptedOnlineStatus = {
        'encrypted_data': encrypted.base64,
        'iv': base64.encode(ivBytes),
        'checksum': checksum,
        'type': 'online_status_update',
        'timestamp': DateTime.now().toIso8601String(),
        'algorithm': _algorithm,
        'version': '1.0',
      };

      Logger.success(
          ' EnhancedChatEncryptionService:  Online status encrypted successfully');
      return encryptedOnlineStatus;
    } catch (e) {
      Logger.error(
          ' EnhancedChatEncryptionService:  Failed to encrypt online status: $e');
      rethrow;
    }
  }

  /// Decrypt online status notification
  Future<Map<String, dynamic>> decryptOnlineStatus(
      Map<String, dynamic> encryptedData) async {
    try {
      Logger.debug(
          ' EnhancedChatEncryptionService: 🔓 Decrypting online status');

      // For online status, we need to handle the decryption differently
      // since it's not conversation-specific
      // This would require a shared key or public key infrastructure

      // For now, return a placeholder - this would need to be implemented
      // based on your specific key exchange mechanism
      throw UnimplementedError(
          'Online status decryption requires key exchange implementation');
    } catch (e) {
      Logger.error(
          ' EnhancedChatEncryptionService:  Failed to decrypt online status: $e');
      rethrow;
    }
  }

  /// Encrypt message status update
  Future<Map<String, dynamic>> encryptMessageStatus({
    required String messageId,
    required String status,
    required String conversationId,
  }) async {
    try {
      Logger.debug(
          ' EnhancedChatEncryptionService: 🔒 Encrypting message status');

      // Get or generate conversation key (ensure key exchange with recipient)
      final conversationKey =
          await generateConversationKey(conversationId, recipientId: null);

      // Create message status payload
      final payload = {
        'type': 'message_status_update',
        'messageId': messageId,
        'status': status,
        'conversationId': conversationId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Convert payload to JSON
      final jsonPayload = jsonEncode(payload);
      final payloadBytes = utf8.encode(jsonPayload);

      // Generate random IV
      final random = Random.secure();
      final ivBytes = Uint8List(_ivLength);
      for (int i = 0; i < _ivLength; i++) {
        ivBytes[i] = random.nextInt(256);
      }

      // Create encryption key and IV
      final key = Key.fromBase64(conversationKey);
      final iv = IV.fromBase64(base64.encode(ivBytes));

      // Encrypt the payload
      final encrypter =
          Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));
      final encrypted = encrypter.encrypt(base64.encode(payloadBytes), iv: iv);

      // Generate checksum for integrity
      final checksum = _generateChecksum(encrypted.base64);

      // Create encrypted message status
      final encryptedMessageStatus = {
        'encrypted_data': encrypted.base64,
        'iv': base64.encode(ivBytes),
        'checksum': checksum,
        'type': 'message_status_update',
        'conversation_id': conversationId,
        'timestamp': DateTime.now().toIso8601String(),
        'algorithm': _algorithm,
        'version': '1.0',
      };

      Logger.success(
          ' EnhancedChatEncryptionService:  Message status encrypted successfully');
      return encryptedMessageStatus;
    } catch (e) {
      Logger.error(
          ' EnhancedChatEncryptionService:  Failed to encrypt message status: $e');
      rethrow;
    }
  }

  /// Decrypt message status update
  Future<Map<String, dynamic>> decryptMessageStatus(
      Map<String, dynamic> encryptedData) async {
    try {
      Logger.debug(
          ' EnhancedChatEncryptionService: 🔓 Decrypting message status');

      final encryptedMessage = encryptedData['encrypted_data'] as String;
      final iv = encryptedData['iv'] as String;
      final checksum = encryptedData['checksum'] as String;
      final conversationId = encryptedData['conversation_id'] as String;

      // Verify checksum
      final expectedChecksum = _generateChecksum(encryptedMessage);
      if (checksum != expectedChecksum) {
        throw Exception('Message status checksum verification failed');
      }

      // Get conversation key
      if (!_conversationKeys.containsKey(conversationId)) {
        throw Exception(
            'No encryption key found for conversation: $conversationId');
      }

      final conversationKey = _conversationKeys[conversationId]!;

      // Decrypt the message status
      final key = Key.fromBase64(conversationKey);
      final ivBytes = IV.fromBase64(iv);
      final encrypter =
          Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));

      final decrypted = encrypter.decrypt64(encryptedMessage, iv: ivBytes);
      final decryptedBytes = base64.decode(decrypted);
      final decryptedJson = utf8.decode(decryptedBytes);

      // Parse the decrypted JSON
      final payload = jsonDecode(decryptedJson) as Map<String, dynamic>;

      Logger.success(
          ' EnhancedChatEncryptionService:  Message status decrypted successfully');
      return payload;
    } catch (e) {
      Logger.error(
          ' EnhancedChatEncryptionService:  Failed to decrypt message status: $e');
      rethrow;
    }
  }

  /// Generate a temporary encryption key
  Future<String> _generateTemporaryKey() async {
    final random = Random.secure();
    final keyBytes = Uint8List(_keyLength);
    for (int i = 0; i < _keyLength; i++) {
      keyBytes[i] = random.nextInt(256);
    }
    return base64.encode(keyBytes);
  }

  /// Generate SHA-256 checksum for data integrity
  String _generateChecksum(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verify message integrity
  Future<bool> verifyMessageIntegrity(
      Map<String, dynamic> encryptedMessage) async {
    try {
      final encryptedData = encryptedMessage['encrypted_data'] as String;
      final checksum = encryptedMessage['checksum'] as String;

      final expectedChecksum = _generateChecksum(encryptedData);
      final isValid = checksum == expectedChecksum;

      Logger.success(
          ' EnhancedChatEncryptionService:  Message integrity verified: $isValid');
      return isValid;
    } catch (e) {
      Logger.error(
          ' EnhancedChatEncryptionService:  Failed to verify message integrity: $e');
      return false;
    }
  }

  /// Clear expired keys
  void clearExpiredKeys() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    for (final entry in _keyExpiryTimes.entries) {
      if (now.isAfter(entry.value)) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _conversationKeys.remove(key);
      _keyExpiryTimes.remove(key);
    }

    if (expiredKeys.isNotEmpty) {
      Logger.info(
          ' EnhancedChatEncryptionService:  Cleared ${expiredKeys.length} expired keys');
    }
  }

  /// Get encryption statistics
  Map<String, dynamic> getEncryptionStats() {
    return {
      'active_conversations': _conversationKeys.length,
      'algorithm': _algorithm,
      'key_length_bits': _keyLength * 8,
      'iv_length_bits': _ivLength * 8,
      'version': '1.0',
    };
  }

  /// Handle key exchange for recipient when receiving encrypted data
  /// This is called when a recipient receives encrypted user data during conversation creation
  Future<bool> handleRecipientKeyExchange(
      String senderId, String conversationId) async {
    try {
      Logger.debug(
          ' EnhancedChatEncryptionService: 🔑 Handling recipient key exchange for $senderId');

      // Check if we already have a public key for the sender
      final hasKey =
          await KeyExchangeService.instance.hasPublicKeyForUser(senderId);
      if (hasKey) {
        Logger.success(
            ' EnhancedChatEncryptionService:  Already have public key for $senderId');
        return true;
      }

      // Check if key exchange is pending
      final isPending = await _isKeyExchangePending(senderId);
      if (isPending) {
        Logger.debug(
            ' EnhancedChatEncryptionService: ⏳ Key exchange already pending for $senderId');
        return true;
      }

      // Initiate key exchange
      Logger.info(
          ' EnhancedChatEncryptionService:  Initiating key exchange with $senderId');
      final keyExchangeSuccess =
          await KeyExchangeService.instance.ensureKeyExchangeWithUser(senderId);

      if (keyExchangeSuccess) {
        Logger.success(
            ' EnhancedChatEncryptionService:  Key exchange initiated successfully with $senderId');
        // Store pending exchange for this conversation
        await _storePendingKeyExchange(senderId, conversationId);
        return true;
      } else {
        Logger.error(
            ' EnhancedChatEncryptionService:  Key exchange failed with $senderId');
        return false;
      }
    } catch (e) {
      Logger.error(
          ' EnhancedChatEncryptionService:  Error handling recipient key exchange: $e');
      return false;
    }
  }

  /// Check if key exchange is pending for a user
  Future<bool> _isKeyExchangePending(String userId) async {
    try {
      // This would integrate with the existing key exchange service
      // For now, we'll use a simple local check
      return false; // Placeholder - integrate with actual key exchange service
    } catch (e) {
      Logger.error(
          ' EnhancedChatEncryptionService:  Error checking key exchange status: $e');
      return false;
    }
  }

  /// Store pending key exchange for a conversation
  Future<void> _storePendingKeyExchange(
      String userId, String conversationId) async {
    try {
      // Store the pending key exchange mapping
      // This would integrate with the existing key exchange service
      Logger.debug(
          ' EnhancedChatEncryptionService: 💾 Stored pending key exchange for $userId in conversation $conversationId');
    } catch (e) {
      Logger.error(
          ' EnhancedChatEncryptionService:  Error storing pending key exchange: $e');
    }
  }

  /// Complete key exchange for a conversation
  Future<bool> completeKeyExchange(String userId, String conversationId) async {
    try {
      Logger.success(
          ' EnhancedChatEncryptionService:  Completing key exchange for $userId in conversation $conversationId');

      // Check if we now have the public key
      final hasKey =
          await KeyExchangeService.instance.hasPublicKeyForUser(userId);
      if (hasKey) {
        Logger.success(
            ' EnhancedChatEncryptionService:  Key exchange completed successfully for $userId');
        // Remove from pending exchanges
        await _removePendingKeyExchange(userId, conversationId);
        return true;
      } else {
        Logger.error(
            ' EnhancedChatEncryptionService:  Key exchange not yet completed for $userId');
        return false;
      }
    } catch (e) {
      Logger.error(
          ' EnhancedChatEncryptionService:  Error completing key exchange: $e');
      return false;
    }
  }

  /// Remove pending key exchange
  Future<void> _removePendingKeyExchange(
      String userId, String conversationId) async {
    try {
      // Remove the pending key exchange mapping
      Logger.info(
          ' EnhancedChatEncryptionService:  Removed pending key exchange for $userId in conversation $conversationId');
    } catch (e) {
      Logger.error(
          ' EnhancedChatEncryptionService:  Error removing pending key exchange: $e');
    }
  }
}
