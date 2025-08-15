import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/encryption_service.dart';
import '../models/message.dart';
import '../models/media_message.dart';

/// Specialized encryption service for chat messages
class ChatEncryptionService {
  static ChatEncryptionService? _instance;
  static ChatEncryptionService get instance =>
      _instance ??= ChatEncryptionService._();

  ChatEncryptionService._();

  /// Encrypt a chat message for transmission
  Future<Map<String, dynamic>> encryptMessage(
    Message message,
    String recipientId, {
    MediaProcessingOptions? mediaOptions,
  }) async {
    try {
      print('🔐 ChatEncryptionService: Encrypting message ${message.id}');

      // Prepare message data for encryption
      final messageData = _prepareMessageData(message, mediaOptions);

      // Encrypt the message data using the existing EncryptionService
      final encryptedResult = await EncryptionService.encryptAesCbcPkcs7(
        messageData,
        recipientId,
      );

      // Create encrypted message payload
      final encryptedMessage = {
        'id': message.id,
        'conversation_id': message.conversationId,
        'sender_id': message.senderId,
        'recipient_id': message.recipientId,
        'type': message.type.name,
        'encrypted_data': encryptedResult['data'],
        'checksum': encryptedResult['checksum'],
        'timestamp': message.timestamp.millisecondsSinceEpoch,
        'message_checksum': _generateMessageChecksum(message),
        'version': '1.0',
        'algorithm': 'AES-256-CBC/PKCS7',
      };

      print('🔐 ChatEncryptionService: ✅ Message encrypted successfully');
      return encryptedMessage;
    } catch (e) {
      print('🔐 ChatEncryptionService: ❌ Failed to encrypt message: $e');
      throw Exception('Failed to encrypt message: $e');
    }
  }

  /// Decrypt a received chat message
  Future<Message?> decryptMessage(
    Map<String, dynamic> encryptedMessage,
    String currentUserId,
  ) async {
    try {
      print(
          '🔐 ChatEncryptionService: Decrypting message ${encryptedMessage['id']}');

      // Extract encrypted data
      final encryptedData = encryptedMessage['encrypted_data'] as String?;
      final checksum = encryptedMessage['checksum'] as String?;
      final messageChecksum = encryptedMessage['message_checksum'] as String?;

      if (encryptedData == null) {
        print('🔐 ChatEncryptionService: ❌ No encrypted data found');
        return null;
      }

      // Decrypt the data using the existing EncryptionService
      final decryptedData = await EncryptionService.decryptAesCbcPkcs7(
        encryptedData,
      );

      if (decryptedData == null) {
        print('🔐 ChatEncryptionService: ❌ Failed to decrypt data');
        return null;
      }

      // Verify message integrity
      if (messageChecksum != null) {
        final calculatedChecksum = _generateChecksum(decryptedData);
        if (messageChecksum != calculatedChecksum) {
          print(
              '🔐 ChatEncryptionService: ❌ Message checksum verification failed');
          return null;
        }
      }

      // Reconstruct the message from decrypted data
      final message = _reconstructMessage(decryptedData, encryptedMessage);

      // Verify the message is for the current user
      if (message.recipientId != currentUserId) {
        print('🔐 ChatEncryptionService: ❌ Message not for current user');
        return null;
      }

      print('🔐 ChatEncryptionService: ✅ Message decrypted successfully');
      return message;
    } catch (e) {
      print('🔐 ChatEncryptionService: ❌ Failed to decrypt message: $e');
      return null;
    }
  }

  /// Encrypt media file data
  Future<Map<String, dynamic>> encryptMediaMessage(
    MediaMessage mediaMessage,
    String recipientId,
    MediaProcessingOptions? mediaOptions,
  ) async {
    try {
      print(
          '🔐 ChatEncryptionService: Encrypting media message ${mediaMessage.id}');

      // Prepare media message data
      final mediaData = _prepareMediaMessageData(mediaMessage, mediaOptions);

      // Encrypt the media data
      final encryptedResult = await EncryptionService.encryptAesCbcPkcs7(
        mediaData,
        recipientId,
      );

      // Create encrypted media message payload
      final encryptedMediaMessage = {
        'id': mediaMessage.id,
        'message_id': mediaMessage.messageId,
        'type': mediaMessage.type.name,
        'encrypted_data': encryptedResult['data'],
        'checksum': encryptedResult['checksum'],
        'file_size': mediaMessage.fileSize,
        'mime_type': mediaMessage.mimeType,
        'duration': mediaMessage.duration,
        'width': mediaMessage.width,
        'height': mediaMessage.height,
        'is_compressed': mediaMessage.isCompressed,
        'timestamp': mediaMessage.createdAt.millisecondsSinceEpoch,
        'media_checksum': _generateMediaChecksum(mediaMessage),
        'version': '1.0',
        'algorithm': 'AES-256-CBC/PKCS7',
      };

      print('🔐 ChatEncryptionService: ✅ Media message encrypted successfully');
      return encryptedMediaMessage;
    } catch (e) {
      print('🔐 ChatEncryptionService: ❌ Failed to encrypt media message: $e');
      throw Exception('Failed to encrypt media message: $e');
    }
  }

  /// Decrypt media message data
  Future<MediaMessage?> decryptMediaMessage(
    Map<String, dynamic> encryptedMediaMessage,
    String currentUserId,
  ) async {
    try {
      print(
          '🔐 ChatEncryptionService: Decrypting media message ${encryptedMediaMessage['id']}');

      // Extract encrypted data
      final encryptedData = encryptedMediaMessage['encrypted_data'] as String?;
      final checksum = encryptedMediaMessage['checksum'] as String?;
      final mediaChecksum = encryptedMediaMessage['media_checksum'] as String?;

      if (encryptedData == null) {
        print('🔐 ChatEncryptionService: ❌ No encrypted media data found');
        return null;
      }

      // Decrypt the data
      final decryptedData = await EncryptionService.decryptAesCbcPkcs7(
        encryptedData,
      );

      if (decryptedData == null) {
        print('🔐 ChatEncryptionService: ❌ Failed to decrypt media data');
        return null;
      }

      // Verify media integrity
      if (mediaChecksum != null) {
        final calculatedChecksum =
            _generateMediaChecksumFromData(decryptedData);
        if (mediaChecksum != calculatedChecksum) {
          print(
              '🔐 ChatEncryptionService: ❌ Media checksum verification failed');
          return null;
        }
      }

      // Reconstruct the media message
      final mediaMessage =
          _reconstructMediaMessage(decryptedData, encryptedMediaMessage);

      print('🔐 ChatEncryptionService: ✅ Media message decrypted successfully');
      return mediaMessage;
    } catch (e) {
      print('🔐 ChatEncryptionService: ❌ Failed to decrypt media message: $e');
      return null;
    }
  }

  /// Prepare message data for encryption
  Map<String, dynamic> _prepareMessageData(
    Message message,
    MediaProcessingOptions? mediaOptions,
  ) {
    final messageData = {
      'id': message.id,
      'conversation_id': message.conversationId,
      'sender_id': message.senderId,
      'recipient_id': message.recipientId,
      'type': message.type.name,
      'content': message.content,
      'timestamp': message.timestamp.millisecondsSinceEpoch,
      'reply_to_message_id': message.replyToMessageId,
      'metadata': message.metadata,
    };

    // Add media-specific data if applicable
    if (message.isMediaMessage && mediaOptions != null) {
      messageData['media_options'] = {
        'enable_compression': mediaOptions.enableCompression,
        'generate_thumbnails': mediaOptions.generateThumbnails,
        'max_file_size': mediaOptions.maxFileSize,
        'preserve_original': mediaOptions.preserveOriginal,
      };
    }

    return messageData;
  }

  /// Prepare media message data for encryption
  Map<String, dynamic> _prepareMediaMessageData(
    MediaMessage mediaMessage,
    MediaProcessingOptions? mediaOptions,
  ) {
    return {
      'id': mediaMessage.id,
      'message_id': mediaMessage.messageId,
      'type': mediaMessage.type.name,
      'file_path': mediaMessage.filePath,
      'file_name': mediaMessage.fileName,
      'mime_type': mediaMessage.mimeType,
      'file_size': mediaMessage.fileSize,
      'duration': mediaMessage.duration,
      'width': mediaMessage.width,
      'height': mediaMessage.height,
      'is_compressed': mediaMessage.isCompressed,
      'thumbnail_path': mediaMessage.thumbnailPath,
      'metadata': mediaMessage.metadata,
      'created_at': mediaMessage.createdAt.millisecondsSinceEpoch,
      'media_options': mediaOptions?.toJson(),
    };
  }

  /// Reconstruct message from decrypted data
  Message _reconstructMessage(
    Map<String, dynamic> decryptedData,
    Map<String, dynamic> encryptedMessage,
  ) {
    return Message(
      id: decryptedData['id'] as String,
      conversationId: decryptedData['conversation_id'] as String,
      senderId: decryptedData['sender_id'] as String,
      recipientId: decryptedData['recipient_id'] as String,
      type: MessageType.values.firstWhere(
        (e) => e.name == decryptedData['type'],
        orElse: () => MessageType.text,
      ),
      content: Map<String, dynamic>.from(decryptedData['content']),
      status: MessageStatus.delivered, // Mark as delivered when decrypted
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        decryptedData['timestamp'] as int,
      ),
      replyToMessageId: decryptedData['reply_to_message_id'] as String?,
      metadata: decryptedData['metadata'] != null
          ? Map<String, dynamic>.from(decryptedData['metadata'])
          : null,
      isEncrypted: false, // Mark as decrypted
      checksum: encryptedMessage['message_checksum'] as String?,
    );
  }

  /// Reconstruct media message from decrypted data
  MediaMessage _reconstructMediaMessage(
    Map<String, dynamic> decryptedData,
    Map<String, dynamic> encryptedMediaMessage,
  ) {
    return MediaMessage(
      id: decryptedData['id'] as String,
      messageId: decryptedData['message_id'] as String,
      type: MediaType.values.firstWhere(
        (e) => e.name == decryptedData['type'],
        orElse: () => MediaType.document,
      ),
      filePath: decryptedData['file_path'] as String,
      fileName: decryptedData['file_name'] as String,
      mimeType: decryptedData['mime_type'] as String,
      fileSize: decryptedData['file_size'] as int,
      duration: decryptedData['duration'] as int?,
      width: decryptedData['width'] as int?,
      height: decryptedData['height'] as int?,
      isCompressed: decryptedData['is_compressed'] as bool? ?? false,
      thumbnailPath: decryptedData['thumbnail_path'] as String?,
      metadata: decryptedData['metadata'] != null
          ? Map<String, dynamic>.from(decryptedData['metadata'])
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        decryptedData['created_at'] as int,
      ),
      processedAt: DateTime.now(),
    );
  }

  /// Generate checksum for message data
  String _generateMessageChecksum(Message message) {
    final messageData = {
      'id': message.id,
      'conversation_id': message.conversationId,
      'sender_id': message.senderId,
      'recipient_id': message.recipientId,
      'type': message.type.name,
      'content': message.content,
      'timestamp': message.timestamp.millisecondsSinceEpoch,
    };
    return _generateChecksum(messageData);
  }

  /// Generate checksum for media message
  String _generateMediaChecksum(MediaMessage mediaMessage) {
    final mediaData = {
      'id': mediaMessage.id,
      'message_id': mediaMessage.messageId,
      'type': mediaMessage.type.name,
      'file_name': mediaMessage.fileName,
      'mime_type': mediaMessage.mimeType,
      'file_size': mediaMessage.fileSize,
      'duration': mediaMessage.duration,
      'width': mediaMessage.width,
      'height': mediaMessage.height,
      'created_at': mediaMessage.createdAt.millisecondsSinceEpoch,
    };
    return _generateChecksum(mediaData);
  }

  /// Generate checksum for media data
  String _generateMediaChecksumFromData(Map<String, dynamic> mediaData) {
    final checksumData = {
      'id': mediaData['id'],
      'message_id': mediaData['message_id'],
      'type': mediaData['type'],
      'file_name': mediaData['file_name'],
      'mime_type': mediaData['mime_type'],
      'file_size': mediaData['file_size'],
      'duration': mediaData['duration'],
      'width': mediaData['width'],
      'height': mediaData['height'],
      'created_at': mediaData['created_at'],
    };
    return _generateChecksum(checksumData);
  }

  /// Generate checksum for data integrity
  String _generateChecksum(Map<String, dynamic> data) {
    final jsonData = json.encode(data);
    final bytes = utf8.encode(jsonData);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verify message integrity
  bool verifyMessageIntegrity(Message message, String checksum) {
    final calculatedChecksum = _generateMessageChecksum(message);
    return calculatedChecksum == checksum;
  }

  /// Verify media message integrity
  bool verifyMediaMessageIntegrity(MediaMessage mediaMessage, String checksum) {
    final calculatedChecksum = _generateMediaChecksum(mediaMessage);
    return calculatedChecksum == checksum;
  }

  /// Get encryption statistics
  Map<String, dynamic> getEncryptionStats() {
    return {
      'algorithm': 'AES-256-CBC/PKCS7',
      'key_size': 256,
      'block_mode': 'CBC',
      'padding': 'PKCS7',
      'checksum_algorithm': 'SHA-256',
      'version': '1.0',
    };
  }
}

/// Media processing options for encryption
class MediaProcessingOptions {
  final bool enableCompression;
  final bool generateThumbnails;
  final int? maxFileSize;
  final Map<String, dynamic>? customCompressionSettings;
  final bool preserveOriginal;

  const MediaProcessingOptions({
    this.enableCompression = true,
    this.generateThumbnails = true,
    this.maxFileSize,
    this.customCompressionSettings,
    this.preserveOriginal = false,
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'enable_compression': enableCompression,
      'generate_thumbnails': generateThumbnails,
      'max_file_size': maxFileSize,
      'custom_compression_settings': customCompressionSettings,
      'preserve_original': preserveOriginal,
    };
  }

  /// Create from JSON
  factory MediaProcessingOptions.fromJson(Map<String, dynamic> json) {
    return MediaProcessingOptions(
      enableCompression: json['enable_compression'] as bool? ?? true,
      generateThumbnails: json['generate_thumbnails'] as bool? ?? true,
      maxFileSize: json['max_file_size'] as int?,
      customCompressionSettings: json['custom_compression_settings'] != null
          ? Map<String, dynamic>.from(json['custom_compression_settings'])
          : null,
      preserveOriginal: json['preserve_original'] as bool? ?? false,
    );
  }
}
