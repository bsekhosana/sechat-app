import 'dart:convert';
import 'dart:math';
import '../models/message.dart';
import '/../core/utils/logger.dart';

/// Simplified encryption service for text-based chat messages only
class ChatEncryptionService {
  static ChatEncryptionService? _instance;
  static ChatEncryptionService get instance =>
      _instance ??= ChatEncryptionService._();

  ChatEncryptionService._();

  /// Simple encryption key for demo purposes
  static const String _demoKey = 'sechat_demo_key_2024';

  /// Encrypt a text message
  Future<Map<String, dynamic>> encryptTextMessage(Message message) async {
    try {
      Logger.debug(
          ' ChatEncryptionService: Encrypting text message: ${message.id}');

      // Extract text content
      final textContent = message.content['text'] as String? ?? '';
      if (textContent.isEmpty) {
        throw Exception('Message content is empty');
      }

      // Create encryption payload
      final payload = {
        'type': 'text',
        'content': textContent,
        'timestamp': message.timestamp.millisecondsSinceEpoch,
        'message_id': message.id,
        'conversation_id': message.conversationId,
        'sender_id': message.senderId,
        'recipient_id': message.recipientId,
      };

      // Simple encryption (for demo purposes)
      final encryptedData = _simpleEncrypt(payload.toString(), _demoKey);

      // Create checksum for integrity
      final checksum = _generateChecksum(encryptedData);

      final result = {
        'encrypted_data': encryptedData,
        'checksum': checksum,
        'message_id': message.id,
        'type': 'text',
        'timestamp': message.timestamp.millisecondsSinceEpoch,
      };

      Logger.success(
          ' ChatEncryptionService:  Text message encrypted successfully');
      return result;
    } catch (e) {
      Logger.error(
          ' ChatEncryptionService:  Failed to encrypt text message: $e');
      rethrow;
    }
  }

  /// Decrypt a text message
  Future<Map<String, dynamic>> decryptTextMessage(
      Map<String, dynamic> encryptedData) async {
    try {
      Logger.debug(' ChatEncryptionService: Decrypting text message');

      final encryptedContent = encryptedData['encrypted_data'] as String;
      final checksum = encryptedData['checksum'] as String;
      final messageId = encryptedData['message_id'] as String;

      // Verify checksum
      final expectedChecksum = _generateChecksum(encryptedContent);
      if (checksum != expectedChecksum) {
        throw Exception('Checksum verification failed');
      }

      // Decrypt the content
      final decryptedContent = _simpleDecrypt(encryptedContent, _demoKey);

      // Parse the decrypted content
      final payload = _parseDecryptedPayload(decryptedContent);

      Logger.success(
          ' ChatEncryptionService:  Text message decrypted successfully');
      return payload;
    } catch (e) {
      Logger.error(
          ' ChatEncryptionService:  Failed to decrypt text message: $e');
      rethrow;
    }
  }

  /// Parse decrypted payload
  Map<String, dynamic> _parseDecryptedPayload(String decryptedContent) {
    try {
      // Simple parsing for basic content structure
      final content = <String, dynamic>{};

      // Extract basic information
      if (decryptedContent.contains('type: text')) {
        content['type'] = 'text';
      }

      // Extract text content (simplified parsing)
      if (decryptedContent.contains('content:')) {
        final contentStart = decryptedContent.indexOf('content:') + 8;
        final contentEnd = decryptedContent.indexOf(',', contentStart);
        if (contentEnd != -1) {
          content['text'] =
              decryptedContent.substring(contentStart, contentEnd).trim();
        }
      }

      return content;
    } catch (e) {
      Logger.error(
          ' ChatEncryptionService:  Failed to parse decrypted payload: $e');
      return {'type': 'text', 'text': 'Decryption failed'};
    }
  }

  /// Generate encryption key for a conversation
  Future<String> generateConversationKey(String conversationId) async {
    try {
      // Generate a simple key based on conversation ID
      final random = Random();
      final key = 'conv_${conversationId}_${random.nextInt(999999)}';

      Logger.success(
          ' ChatEncryptionService:  Conversation key generated: $conversationId');
      return key;
    } catch (e) {
      Logger.error(
          ' ChatEncryptionService:  Failed to generate conversation key: $e');
      rethrow;
    }
  }

  /// Verify message integrity
  Future<bool> verifyMessageIntegrity(Message message, String checksum) async {
    try {
      final expectedChecksum = _generateChecksum(message.content.toString());

      final isValid = checksum == expectedChecksum;
      Logger.success(
          ' ChatEncryptionService:  Message integrity verified: $isValid');
      return isValid;
    } catch (e) {
      Logger.error(
          ' ChatEncryptionService:  Failed to verify message integrity: $e');
      return false;
    }
  }

  /// Simple encryption method (for demo purposes)
  String _simpleEncrypt(String data, String key) {
    final bytes = utf8.encode(data);
    final keyBytes = utf8.encode(key);

    final encrypted = <int>[];
    for (int i = 0; i < bytes.length; i++) {
      encrypted.add(bytes[i] ^ keyBytes[i % keyBytes.length]);
    }

    return base64.encode(encrypted);
  }

  /// Simple decryption method (for demo purposes)
  String _simpleDecrypt(String encryptedData, String key) {
    final encrypted = base64.decode(encryptedData);
    final keyBytes = utf8.encode(key);

    final decrypted = <int>[];
    for (int i = 0; i < encrypted.length; i++) {
      decrypted.add(encrypted[i] ^ keyBytes[i % keyBytes.length]);
    }

    return utf8.decode(decrypted);
  }

  /// Generate checksum for data integrity
  String _generateChecksum(String data) {
    final bytes = utf8.encode(data);
    int checksum = 0;

    for (final byte in bytes) {
      checksum = (checksum + byte) % 65521; // Simple checksum algorithm
    }

    return checksum.toRadixString(16).padLeft(4, '0');
  }
}
