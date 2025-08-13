import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/encryption_error_handler.dart';
import '../services/se_session_service.dart';

class EncryptionService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _privateKeyKey = 'private_key';
  static const String _publicKeyKey = 'public_key';
  static const String _keyPairVersion = 'key_pair_version';

  // Keep a cache of recipient public keys to avoid frequent storage access
  static final Map<String, String> _recipientPublicKeysCache = {};
  static final Random _secureRandom = Random.secure();

  /// Generate AES key pair for end-to-end encryption
  static Future<Map<String, String>> generateKeyPair() async {
    final random = Random.secure();

    // Generate AES key (256-bit)
    final aesKey = List<int>.generate(32, (i) => random.nextInt(256));
    final aesKeyBase64 = base64Encode(aesKey);

    // Generate IV (Initialization Vector)
    final iv = List<int>.generate(16, (i) => random.nextInt(256));
    final ivBase64 = base64Encode(iv);

    // Store keys securely
    await _storage.write(key: _publicKeyKey, value: aesKeyBase64);
    await _storage.write(key: _privateKeyKey, value: ivBase64);

    // Store version information for key rotation
    final currentVersion = await _storage.read(key: _keyPairVersion) ?? '0';
    final newVersion = (int.tryParse(currentVersion) ?? 0) + 1;
    await _storage.write(key: _keyPairVersion, value: newVersion.toString());

    return {
      'publicKey': aesKeyBase64,
      'privateKey': ivBase64,
      'version': newVersion.toString()
    };
  }

  /// Get user's public key (to share with others)
  static Future<String?> getPublicKey() async {
    return await _storage.read(key: _publicKeyKey);
  }

  /// Get user's private key (for decryption)
  static Future<String?> getPrivateKey() async {
    try {
      // First try to get from SeSessionService (current implementation)
      final sessionService = SeSessionService();
      final decryptedPrivateKey = await sessionService.getDecryptedPrivateKey();

      if (decryptedPrivateKey != null && decryptedPrivateKey.isNotEmpty) {
        print(
            '🔒 EncryptionService: ✅ Successfully retrieved private key from session service');
        return decryptedPrivateKey;
      } else {
        print(
            '🔒 EncryptionService: No private key available from session service');
      }

      // Fallback: try to get from FlutterSecureStorage (legacy)
      print('🔒 EncryptionService: Falling back to FlutterSecureStorage');
      return await _storage.read(key: _privateKeyKey);
    } catch (e) {
      print('🔒 EncryptionService: Error getting private key: $e');
      return null;
    }
  }

  /// Get current key pair version
  static Future<String> getKeyPairVersion() async {
    return await _storage.read(key: _keyPairVersion) ?? '1';
  }

  /// Store recipient's public key
  static Future<void> storeRecipientPublicKey(
      String userId, String publicKey) async {
    await _storage.write(key: 'recipient_key_$userId', value: publicKey);
    // Update cache
    _recipientPublicKeysCache[userId] = publicKey;
  }

  /// Get recipient's public key
  static Future<String?> getRecipientPublicKey(String userId) async {
    // Check cache first
    if (_recipientPublicKeysCache.containsKey(userId)) {
      return _recipientPublicKeysCache[userId];
    }

    // Not in cache, check storage
    final key = await _storage.read(key: 'recipient_key_$userId');
    if (key != null) {
      // Update cache
      _recipientPublicKeysCache[userId] = key;
    }
    return key;
  }

  /// Delete recipient's public key
  static Future<void> deleteRecipientPublicKey(String userId) async {
    await _storage.delete(key: 'recipient_key_$userId');
    _recipientPublicKeysCache.remove(userId);
  }

  /// Encrypt message with recipient's public key (AES key)
  static String encryptMessage(String message, String recipientPublicKey) {
    try {
      // Parse recipient's AES key
      final aesKeyBytes = base64Decode(recipientPublicKey);

      // Debug: Log key details
      print(
          '🔒 EncryptionService: Encrypting with key length: ${aesKeyBytes.length} bytes (${aesKeyBytes.length * 8} bits)');
      print(
          '🔒 EncryptionService: Key format: ${recipientPublicKey.substring(0, 20)}...');

      // Validate key length for AES
      if (aesKeyBytes.length != 16 &&
          aesKeyBytes.length != 24 &&
          aesKeyBytes.length != 32) {
        throw Exception(
            'Invalid AES key length: ${aesKeyBytes.length} bytes. Expected 16, 24, or 32 bytes (128, 192, or 256 bits)');
      }

      // Generate random IV for this message
      final random = _secureRandom;
      final iv = List<int>.generate(16, (i) => random.nextInt(256));

      // Create AES cipher
      final cipher = CBCBlockCipher(AESEngine());
      final params = ParametersWithIV(
        KeyParameter(aesKeyBytes),
        Uint8List.fromList(iv),
      );
      cipher.init(true, params);

      // Encrypt message
      final messageBytes = utf8.encode(message);
      final paddedMessage = _padMessage(messageBytes);

      // Debug: Log encryption details
      print(
          '🔒 EncryptionService: - Original message length: ${messageBytes.length} bytes');
      print(
          '🔒 EncryptionService: - Padded message length: ${paddedMessage.length} bytes');
      print(
          '🔒 EncryptionService: - Padding added: ${paddedMessage.length - messageBytes.length} bytes');

      // Process the entire padded message in chunks
      final encryptedBytes = _encryptAESBlocks(paddedMessage, aesKeyBytes, iv);

      // Combine IV and encrypted data
      final combined = Uint8List.fromList([...iv, ...encryptedBytes]);

      // Debug: Show the final encrypted data structure
      print('🔒 EncryptionService: Final encrypted data:');
      print('🔒 EncryptionService: - IV length: ${iv.length} bytes');
      print(
          '🔒 EncryptionService: - Encrypted content length: ${encryptedBytes.length} bytes');
      print(
          '🔒 EncryptionService: - Combined length: ${combined.length} bytes');

      // Safe substring operation for base64 result
      final base64Result = base64Encode(combined);
      final previewLength = base64Result.length > 50 ? 50 : base64Result.length;
      print(
          '🔒 EncryptionService: - Base64 result: ${base64Result.substring(0, previewLength)}...');

      return base64Encode(combined);
    } catch (e) {
      throw Exception('Encryption failed: $e');
    }
  }

  /// Encrypt data in multiple AES blocks
  static Uint8List _encryptAESBlocks(
      List<int> paddedMessage, List<int> key, List<int> iv) {
    try {
      final blockSize = 16;
      final cipher = CBCBlockCipher(AESEngine());
      final params = ParametersWithIV(
        KeyParameter(Uint8List.fromList(key)),
        Uint8List.fromList(iv),
      );
      cipher.init(true, params);

      // Process the entire message in blocks
      final encryptedBytes = cipher.process(Uint8List.fromList(paddedMessage));

      print(
          '🔒 EncryptionService: - Encrypted ${paddedMessage.length} bytes to ${encryptedBytes.length} bytes');

      return encryptedBytes;
    } catch (e) {
      throw Exception('AES block encryption failed: $e');
    }
  }

  /// Decrypt message with own private key (IV)
  static Future<String> decryptMessage(String encryptedMessage) async {
    try {
      final privateKey = await getPrivateKey();
      if (privateKey == null) throw Exception('Private key not found');

      // Parse AES key and IV
      final aesKeyBytes = base64Decode(privateKey);
      final encryptedBytes = base64Decode(encryptedMessage);

      // Debug: Log data lengths
      print('🔒 EncryptionService: Decrypting message:');
      print(
          '🔒 EncryptionService: - Private key length: ${aesKeyBytes.length} bytes');
      print(
          '🔒 EncryptionService: - Encrypted data length: ${encryptedBytes.length} bytes');
      print('🔒 EncryptionService: - Expected IV length: 16 bytes');
      print(
          '🔒 EncryptionService: - Expected encrypted content length: ${encryptedBytes.length - 16} bytes');

      // Validate data length
      if (encryptedBytes.length < 16) {
        throw Exception(
            'Encrypted data too short: ${encryptedBytes.length} bytes (need at least 16 bytes for IV)');
      }

      // Extract IV and encrypted data
      final iv = encryptedBytes.sublist(0, 16);
      final encryptedData = encryptedBytes.sublist(16);

      print('🔒 EncryptionService: - IV extracted: ${iv.length} bytes');
      print(
          '🔒 EncryptionService: - Encrypted content extracted: ${encryptedData.length} bytes');

      // Create AES cipher
      final cipher = CBCBlockCipher(AESEngine());
      final params = ParametersWithIV(
        KeyParameter(aesKeyBytes),
        Uint8List.fromList(iv),
      );
      cipher.init(false, params);

      // Decrypt the entire encrypted data
      final decryptedBytes = _decryptAESBlocks(encryptedData, aesKeyBytes, iv);

      // Debug: Log decryption details
      print(
          '🔒 EncryptionService: - Decrypted bytes length: ${decryptedBytes.length}');
      if (decryptedBytes.length > 0) {
        print(
            '🔒 EncryptionService: - Last byte (padding indicator): ${decryptedBytes.last}');
        print(
            '🔒 EncryptionService: - Last few bytes: ${decryptedBytes.sublist(decryptedBytes.length > 4 ? decryptedBytes.length - 4 : 0)}');

        // Debug: Show the full decrypted content
        print(
            '🔒 EncryptionService: - Full decrypted bytes: ${decryptedBytes}');

        // Try to decode as UTF-8 to see what the content looks like
        try {
          final decodedContent = utf8.decode(decryptedBytes);
          print('🔒 EncryptionService: - Decoded content: $decodedContent');
        } catch (e) {
          print('🔒 EncryptionService: - Could not decode as UTF-8: $e');
        }
      }

      final unpaddedMessage = _unpadMessage(decryptedBytes.toList());
      print(
          '🔒 EncryptionService: - Unpadded message length: ${unpaddedMessage.length}');

      return utf8.decode(unpaddedMessage);
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }

  /// Decrypt data in multiple AES blocks
  static Uint8List _decryptAESBlocks(
      List<int> encryptedData, List<int> key, List<int> iv) {
    try {
      final blockSize = 16;
      final cipher = CBCBlockCipher(AESEngine());
      final params = ParametersWithIV(
        KeyParameter(Uint8List.fromList(key)),
        Uint8List.fromList(iv),
      );
      cipher.init(false, params);

      // Process the entire encrypted data
      final decryptedBytes = cipher.process(Uint8List.fromList(encryptedData));

      print(
          '🔒 EncryptionService: - Decrypted ${encryptedData.length} bytes to ${decryptedBytes.length} bytes');

      return decryptedBytes;
    } catch (e) {
      throw Exception('AES block decryption failed: $e');
    }
  }

  /// Encrypt any data object with recipient's public key
  static Future<String> encryptData(
      Map<String, dynamic> data, String recipientId) async {
    try {
      // Get recipient's public key
      final recipientPublicKey = await getRecipientPublicKey(recipientId);
      if (recipientPublicKey == null) {
        final errorType = EncryptionErrorType.keyMissing;
        EncryptionErrorHandler.instance.logError(
            'Recipient public key not found for $recipientId',
            type: errorType);
        throw Exception('Recipient public key not found');
      }

      // Convert data to JSON string
      final jsonData = json.encode(data);

      // Debug: Log the message being encrypted
      print('🔒 EncryptionService: Encrypting message:');
      print('🔒 EncryptionService: - JSON data: $jsonData');
      print(
          '🔒 EncryptionService: - JSON length: ${jsonData.length} characters');

      // Debug: Show the actual bytes being encrypted
      final messageBytes = utf8.encode(jsonData);
      print(
          '🔒 EncryptionService: - Message bytes: ${messageBytes.sublist(0, messageBytes.length > 20 ? 20 : messageBytes.length)}...');
      if (messageBytes.length > 20) {
        print(
            '🔒 EncryptionService: - Last 10 bytes: ${messageBytes.sublist(messageBytes.length - 10)}');
      }

      // Encrypt the JSON string
      return encryptMessage(jsonData, recipientPublicKey);
    } catch (e) {
      final errorType = e is Exception
          ? EncryptionErrorHandler.instance.handleException(e)
          : EncryptionErrorType.encryptionFailed;

      EncryptionErrorHandler.instance
          .logError('Data encryption failed: $e', type: errorType);
      throw Exception('Data encryption failed: $e');
    }
  }

  /// Decrypt data object with own private key
  static Future<Map<String, dynamic>?> decryptData(String encryptedData) async {
    try {
      // Decrypt the data
      final decryptedJson = await decryptMessage(encryptedData);

      // Parse JSON string back to Map
      return json.decode(decryptedJson) as Map<String, dynamic>;
    } catch (e) {
      final errorType = e is Exception
          ? EncryptionErrorHandler.instance.handleException(e)
          : EncryptionErrorType.decryptionFailed;

      EncryptionErrorHandler.instance
          .logError('Decryption failed: $e', type: errorType);
      return null;
    }
  }

  /// Decrypt data with retry mechanism and error handling
  static Future<Map<String, dynamic>?> decryptDataWithRetry(
      String encryptedData,
      {int maxRetries = 2}) async {
    int attempts = 0;

    while (attempts <= maxRetries) {
      try {
        attempts++;

        // Try to decrypt the data
        final result = await decryptData(encryptedData);

        if (result != null) {
          return result;
        } else if (attempts <= maxRetries) {
          // Wait before retrying
          await Future.delayed(Duration(milliseconds: 500 * attempts));
          continue;
        }
      } catch (e) {
        if (attempts <= maxRetries) {
          // Wait before retrying
          await Future.delayed(Duration(milliseconds: 500 * attempts));
          continue;
        } else {
          EncryptionErrorHandler.instance.logError(
              'Decryption failed after $maxRetries retries: $e',
              type: EncryptionErrorType.decryptionFailed);
          return null;
        }
      }
    }

    return null;
  }

  /// Generate checksum for data integrity verification
  static String generateChecksum(Map<String, dynamic> data) {
    final jsonData = json.encode(data);
    final bytes = utf8.encode(jsonData);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verify data integrity using checksum
  static bool verifyChecksum(Map<String, dynamic> data, String checksum) {
    final calculatedChecksum = generateChecksum(data);
    return calculatedChecksum == checksum;
  }

  /// Create encrypted payload with all necessary metadata
  static Future<Map<String, dynamic>> createEncryptedPayload(
      Map<String, dynamic> data, String recipientId) async {
    try {
      // Encrypt the data
      final encryptedData = await encryptData(data, recipientId);

      // Generate checksum for integrity verification
      final checksum = generateChecksum(data);

      // Get current key version
      final keyVersion = await getKeyPairVersion();

      // Create payload with metadata
      return {
        'encrypted': true,
        'data': encryptedData,
        'checksum': checksum,
        'version': keyVersion,
        'algorithm': 'AES-256-CBC',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
    } catch (e) {
      final errorType = e is Exception
          ? EncryptionErrorHandler.instance.handleException(e)
          : EncryptionErrorType.encryptionFailed;

      EncryptionErrorHandler.instance
          .logError('Failed to create encrypted payload: $e', type: errorType);

      // Rethrow with more context
      throw Exception('Failed to create encrypted payload: $e');
    }
  }

  /// Create encrypted payload with retry mechanism
  static Future<Map<String, dynamic>> createEncryptedPayloadWithRetry(
      Map<String, dynamic> data, String recipientId,
      {int maxRetries = 2}) async {
    int attempts = 0;
    Exception? lastException;

    while (attempts <= maxRetries) {
      try {
        attempts++;
        return await createEncryptedPayload(data, recipientId);
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());

        if (attempts <= maxRetries) {
          // Wait before retrying
          await Future.delayed(Duration(milliseconds: 500 * attempts));
          continue;
        }
      }
    }

    // If we get here, all attempts failed
    final errorType = EncryptionErrorType.encryptionFailed;
    EncryptionErrorHandler.instance.logError(
        'Failed to create encrypted payload after $maxRetries retries',
        type: errorType);

    throw lastException ??
        Exception(
            'Failed to create encrypted payload after $maxRetries retries');
  }

  // PKCS7 padding
  static List<int> _padMessage(List<int> message) {
    try {
      final blockSize = 16;

      // Calculate padding length
      int paddingLength;
      if (message.length % blockSize == 0) {
        // Message is exactly block-aligned, add a full block of padding
        paddingLength = blockSize;
      } else {
        // Message needs partial padding
        paddingLength = blockSize - (message.length % blockSize);
      }

      // Create padding bytes (all with the same value)
      final padding = List<int>.filled(paddingLength, paddingLength);

      // Debug: Log padding details
      print('🔒 EncryptionService: PKCS7 Padding:');
      print('🔒 EncryptionService: - Message length: ${message.length} bytes');
      print('🔒 EncryptionService: - Block size: $blockSize bytes');
      print(
          '🔒 EncryptionService: - Message % blockSize: ${message.length % blockSize}');
      print('🔒 EncryptionService: - Padding length: $paddingLength bytes');
      print(
          '🔒 EncryptionService: - Final length: ${message.length + paddingLength} bytes');

      return [...message, ...padding];
    } catch (e) {
      throw Exception('PKCS7 padding failed: $e');
    }
  }

  // PKCS7 unpadding
  static List<int> _unpadMessage(List<int> message) {
    try {
      if (message.isEmpty) {
        throw Exception('Cannot unpad empty message');
      }

      final paddingLength = message.last;

      // Validate padding length
      if (paddingLength <= 0 || paddingLength > 16) {
        throw Exception(
            'Invalid padding length: $paddingLength (expected 1-16)');
      }

      // Validate that we have enough bytes for the padding
      if (message.length < paddingLength) {
        throw Exception(
            'Message too short for padding length: ${message.length} < $paddingLength');
      }

      // Validate that all padding bytes have the correct value
      for (int i = message.length - paddingLength; i < message.length; i++) {
        if (message[i] != paddingLength) {
          throw Exception(
              'Invalid padding byte at position $i: ${message[i]} (expected $paddingLength)');
        }
      }

      return message.sublist(0, message.length - paddingLength);
    } catch (e) {
      throw Exception('PKCS7 unpadding failed: $e');
    }
  }

  // Generate device ID
  static Future<String> getDeviceId() async {
    // Always check storage first
    final storedId = await _storage.read(key: 'device_id');
    if (storedId != null && storedId.isNotEmpty) {
      return storedId;
    }
    // For web platform, use a simple UUID
    final newId =
        kIsWeb ? const Uuid().v4() : await _generatePlatformDeviceId();
    await _storage.write(key: 'device_id', value: newId);
    return newId;
  }

  static Future<String> _generatePlatformDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id ?? const Uuid().v4();
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? const Uuid().v4();
      } else {
        return const Uuid().v4();
      }
    } catch (e) {
      // Fallback to UUID if device info fails
      return const Uuid().v4();
    }
  }

  // Hash password
  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // Verify message integrity
  static String generateMessageHash(String message) {
    final bytes = utf8.encode(message);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Generate a random test key for development/testing
  static Future<String> generateTestKey(String userId) async {
    final random = _secureRandom;
    final keyBytes = List<int>.generate(32, (i) => random.nextInt(256));
    final key = base64Encode(keyBytes);

    // Store for future use
    await storeRecipientPublicKey(userId, key);

    return key;
  }

  /// Clear all stored keys (for logout/security)
  static Future<void> clearAllKeys() async {
    try {
      // Get all keys
      final allKeys = await _storage.readAll();

      // Delete only encryption-related keys
      for (final key in allKeys.keys) {
        if (key.startsWith('recipient_key_') ||
            key == _privateKeyKey ||
            key == _publicKeyKey ||
            key == _keyPairVersion) {
          await _storage.delete(key: key);
        }
      }

      // Clear cache
      _recipientPublicKeysCache.clear();
    } catch (e) {
      final errorType = EncryptionErrorType.storageError;
      EncryptionErrorHandler.instance
          .logError('Error clearing encryption keys: $e', type: errorType);
    }
  }

  /// Rotate encryption keys and notify contacts
  static Future<bool> rotateKeys({bool notifyContacts = true}) async {
    try {
      // Backup existing keys
      final oldPublicKey = await getPublicKey();
      final oldPrivateKey = await getPrivateKey();
      final oldVersion = await getKeyPairVersion();

      if (oldPublicKey != null && oldPrivateKey != null) {
        await _storage.write(
            key: 'backup_public_key_$oldVersion', value: oldPublicKey);
        await _storage.write(
            key: 'backup_private_key_$oldVersion', value: oldPrivateKey);
      }

      // Generate new keys
      await generateKeyPair();

      // If notifyContacts is true, we would send key updates to all contacts
      // This would be implemented in KeyExchangeService

      return true;
    } catch (e) {
      final errorType = EncryptionErrorType.storageError;
      EncryptionErrorHandler.instance
          .logError('Failed to rotate encryption keys: $e', type: errorType);
      return false;
    }
  }

  /// Try to recover from key failure using backup keys
  static Future<bool> tryKeyRecovery(String recipientId) async {
    try {
      // Check if we have any backup keys
      final allKeys = await _storage.readAll();
      final backupKeys = allKeys.keys
          .where((key) =>
              key.startsWith('backup_public_key_') ||
              key.startsWith('backup_private_key_'))
          .toList();

      if (backupKeys.isEmpty) {
        return false;
      }

      // Find the latest backup version
      int latestVersion = 0;
      for (final key in backupKeys) {
        if (key.startsWith('backup_public_key_')) {
          final version = int.tryParse(key.split('_').last) ?? 0;
          if (version > latestVersion) {
            latestVersion = version;
          }
        }
      }

      if (latestVersion == 0) {
        return false;
      }

      // Try to use the backup keys
      final backupPublicKey =
          await _storage.read(key: 'backup_public_key_$latestVersion');
      final backupPrivateKey =
          await _storage.read(key: 'backup_private_key_$latestVersion');

      if (backupPublicKey == null || backupPrivateKey == null) {
        return false;
      }

      // Temporarily restore the backup keys
      await _storage.write(key: _publicKeyKey, value: backupPublicKey);
      await _storage.write(key: _privateKeyKey, value: backupPrivateKey);
      await _storage.write(
          key: _keyPairVersion, value: latestVersion.toString());

      return true;
    } catch (e) {
      final errorType = EncryptionErrorType.storageError;
      EncryptionErrorHandler.instance
          .logError('Failed to recover encryption keys: $e', type: errorType);
      return false;
    }
  }

  /// Test encryption/decryption with a recipient
  static Future<bool> testEncryptionWithRecipient(String recipientId) async {
    try {
      // Test data
      final testData = {
        'message': 'test_message',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Create encrypted payload
      final payload = await createEncryptedPayload(testData, recipientId);

      // Extract encrypted data
      final encryptedData = payload['data'] as String;

      // Try to decrypt it back
      final decryptedData = await decryptData(encryptedData);

      if (decryptedData == null) {
        EncryptionErrorHandler.instance.logError(
            'Encryption test failed: decryption returned null',
            type: EncryptionErrorType.decryptionFailed);
        return false;
      }

      // Verify contents
      final isValid = decryptedData['message'] == 'test_message';
      if (!isValid) {
        EncryptionErrorHandler.instance.logError(
            'Encryption test failed: content verification failed',
            type: EncryptionErrorType.checksumVerificationFailed);
      }
      return isValid;
    } catch (e) {
      final errorType = e is Exception
          ? EncryptionErrorHandler.instance.handleException(e)
          : EncryptionErrorType.unknownError;

      EncryptionErrorHandler.instance
          .logError('Encryption test failed: $e', type: errorType);
      return false;
    }
  }

  /// Verify encryption setup with a recipient and attempt recovery if needed
  static Future<bool> verifyEncryptionSetup(String recipientId) async {
    try {
      // First try a normal encryption test
      final testResult = await testEncryptionWithRecipient(recipientId);

      if (testResult) {
        return true;
      }

      // If test failed, try key recovery
      final recoverySuccess = await tryKeyRecovery(recipientId);
      if (!recoverySuccess) {
        EncryptionErrorHandler.instance.logError(
            'Encryption verification failed and recovery was not possible',
            type: EncryptionErrorType.keyMissing);
        return false;
      }

      // Try the test again with recovered keys
      final retestResult = await testEncryptionWithRecipient(recipientId);
      if (!retestResult) {
        EncryptionErrorHandler.instance.logError(
            'Encryption verification failed even after key recovery',
            type: EncryptionErrorType.encryptionFailed);

        // Generate new keys as a last resort
        await rotateKeys();
        return false;
      }

      return true;
    } catch (e) {
      final errorType = e is Exception
          ? EncryptionErrorHandler.instance.handleException(e)
          : EncryptionErrorType.unknownError;

      EncryptionErrorHandler.instance
          .logError('Encryption verification failed: $e', type: errorType);
      return false;
    }
  }
}
