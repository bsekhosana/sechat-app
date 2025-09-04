import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';

import '../utils/encryption_error_handler.dart';
import '../services/se_session_service.dart';
import 'package:sechat_app//../core/utils/logger.dart';

class EncryptionService {
  // ===== Public API =====

  /// Encrypts a JSON-serializable map using AES-256-CBC/PKCS7.
  /// Returns { "data": base64(envelopeJson), "checksum": sha256(json) }.
  static Future<Map<String, String>> encryptAesCbcPkcs7(
    Map<String, dynamic> jsonMap,
    String recipientId,
  ) async {
    try {
      // 1) Serialize cleartext
      final plain = utf8.encode(json.encode(jsonMap));
      final keyBytes =
          await _getSymmetricKeyForRecipient(recipientId); // 32 bytes
      final ivBytes = _secureRandomBytes(16);

      // 2) Encrypt
      final cipherText =
          _aesCbcPkcs7Encrypt(Uint8List.fromList(plain), keyBytes, ivBytes);

      // 3) Build envelope
      final envelope = {
        "v": 1,
        "alg": "AES-256-CBC/PKCS7",
        "iv": base64Encode(ivBytes),
        "ct": base64Encode(cipherText),
      };
      final envelopeB64 = base64Encode(utf8.encode(json.encode(envelope)));

      // 4) Checksum on plaintext for integrity (what your receiver will recompute)
      final checksum = sha256.convert(plain).toString();

      _log('encryptAesCbcPkcs7',
          'plain=${plain.length}B, ct=${cipherText.length}B, iv=16B, envB64=${envelopeB64.length} chars');

      return {"data": envelopeB64, "checksum": checksum};
    } catch (e) {
      final errorType = EncryptionErrorType.encryptionFailed;
      EncryptionErrorHandler.instance
          .logError('Failed to encrypt data: $e', type: errorType);
      throw Exception('Failed to encrypt data: $e');
    }
  }

  /// Decrypts base64(envelopeJson) and returns a JSON map.
  static Future<Map<String, dynamic>?> decryptAesCbcPkcs7(
    String encryptedBase64,
  ) async {
    try {
      final envJson = utf8.decode(base64Decode(encryptedBase64));
      final env = json.decode(envJson) as Map<String, dynamic>;

      final v = env["v"];
      final alg = env["alg"];
      final ivB64 = env["iv"] as String?;
      final ctB64 = env["ct"] as String?;

      if (v != 1 ||
          alg != "AES-256-CBC/PKCS7" ||
          ivB64 == null ||
          ctB64 == null) {
        throw StateError("Invalid envelope format");
      }

      final iv = base64Decode(ivB64);
      final ct = base64Decode(ctB64);

      // You must obtain the correct key for the current session/recipient here.
      final keyBytes =
          await _getOwnSymmetricKey(); // 32 bytes (recipient's key)

      final plainBytes = _aesCbcPkcs7Decrypt(ct, keyBytes, iv);
      final plainStr = utf8.decode(plainBytes);

      _log('decryptAesCbcPkcs7',
          'ct=${ct.length}B, iv=${iv.length}B, plain=${plainBytes.length}B, preview=${_preview(plainStr)}');

      return json.decode(plainStr) as Map<String, dynamic>;
    } catch (e) {
      final errorType = EncryptionErrorType.decryptionFailed;
      EncryptionErrorHandler.instance
          .logError('Failed to decrypt data: $e', type: errorType);
      _log('decryptAesCbcPkcs7', 'ERROR: $e');
      return null;
    }
  }

  // ===== Legacy API Compatibility =====

  /// Legacy method for backward compatibility
  static Future<String> encryptData(
      Map<String, dynamic> data, String recipientId) async {
    final result = await encryptAesCbcPkcs7(data, recipientId);
    return result['data']!;
  }

  /// Legacy method for backward compatibility
  static Future<Map<String, dynamic>?> decryptData(String encryptedData) async {
    return await decryptAesCbcPkcs7(encryptedData);
  }

  /// Legacy method for backward compatibility
  static Future<Map<String, dynamic>> createEncryptedPayload(
      Map<String, dynamic> data, String recipientId) async {
    final result = await encryptAesCbcPkcs7(data, recipientId);
    return {
      'encrypted': true,
      'data': result['data']!,
      'checksum': result['checksum']!,
      'version': '1',
      'algorithm': 'AES-256-CBC/PKCS7',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  // ===== Internals =====

  static Uint8List _aesCbcPkcs7Encrypt(
      Uint8List plain, Uint8List key, Uint8List iv) {
    _assertKeyIv(key, iv);
    final c = _paddedCipher(true, key, iv);
    final out = c.process(plain); // processes ALL bytes, PKCS7 handled
    return Uint8List.fromList(out);
  }

  static Uint8List _aesCbcPkcs7Decrypt(
      Uint8List ct, Uint8List key, Uint8List iv) {
    _assertKeyIv(key, iv);
    final c = _paddedCipher(false, key, iv);
    final out = c.process(ct); // processes ALL bytes, PKCS7 handled
    return Uint8List.fromList(out);
  }

  static PaddedBlockCipher _paddedCipher(
      bool forEncryption, Uint8List key, Uint8List iv) {
    final params =
        PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
      ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
      null,
    );
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
    cipher.init(forEncryption, params);
    return cipher;
  }

  static void _assertKeyIv(Uint8List key, Uint8List iv) {
    if (key.length != 32) {
      throw ArgumentError('AES-256 key must be 32 bytes, got ${key.length}');
    }
    if (iv.length != 16) {
      throw ArgumentError('AES-CBC IV must be 16 bytes, got ${iv.length}');
    }
  }

  static Uint8List _secureRandomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
    // (For production, prefer FortunaRandom seeded from OS.)
  }

  // === Key Management Implementation ===

  /// Get symmetric key for recipient (32 bytes)
  static Future<Uint8List> _getSymmetricKeyForRecipient(
      String recipientId) async {
    try {
      // Get recipient's public key from storage
      final recipientPublicKey = await getRecipientPublicKey(recipientId);
      if (recipientPublicKey == null) {
        throw Exception('Recipient public key not found for $recipientId');
      }

      // For now, use the recipient's public key as the symmetric key
      // In production, this should be derived via ECDH or KDF
      final keyBytes = base64Decode(recipientPublicKey);

      // Ensure it's 32 bytes for AES-256
      if (keyBytes.length != 32) {
        // If not 32 bytes, pad or truncate to 32 bytes
        final adjustedKey = Uint8List(32);
        final copyLength = keyBytes.length > 32 ? 32 : keyBytes.length;
        adjustedKey.setRange(0, copyLength, keyBytes);
        // Fill remaining bytes with zeros if needed
        if (copyLength < 32) {
          adjustedKey.fillRange(copyLength, 32, 0);
        }
        return adjustedKey;
      }

      return keyBytes;
    } catch (e) {
      throw Exception('Failed to get symmetric key for recipient: $e');
    }
  }

  /// Get own symmetric key (32 bytes)
  static Future<Uint8List> _getOwnSymmetricKey() async {
    try {
      // Get current user's private key from session service
      final privateKey = await getPrivateKey();
      if (privateKey == null) {
        throw Exception('Private key not found');
      }

      // For now, use the private key as the symmetric key
      // In production, this should be derived via ECDH or KDF
      final keyBytes = base64Decode(privateKey);

      // Ensure it's 32 bytes for AES-256
      if (keyBytes.length != 32) {
        // If not 32 bytes, pad or truncate to 32 bytes
        final adjustedKey = Uint8List(32);
        final copyLength = keyBytes.length > 32 ? 32 : keyBytes.length;
        adjustedKey.setRange(0, copyLength, keyBytes);
        // Fill remaining bytes with zeros if needed
        if (copyLength < 32) {
          adjustedKey.fillRange(copyLength, 32, 0);
        }
        return adjustedKey;
      }

      return keyBytes;
    } catch (e) {
      throw Exception('Failed to get own symmetric key: $e');
    }
  }

  // ===== Legacy Key Management Methods =====

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
        Logger.success(
            ' EncryptionService:  Successfully retrieved private key from session service');
        return decryptedPrivateKey;
      } else {
        Logger.debug(
            ' EncryptionService: No private key available from session service');
      }

      // Fallback: try to get from FlutterSecureStorage (legacy)
      Logger.debug(' EncryptionService: Falling back to FlutterSecureStorage');
      return await _storage.read(key: _privateKeyKey);
    } catch (e) {
      Logger.debug(' EncryptionService: Error getting private key: $e');
      return null;
    }
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

  /// Clear ALL recipient public keys (for account deletion)
  static Future<void> clearAllRecipientPublicKeys() async {
    try {
      Logger.info(' EncryptionService:  Clearing all recipient public keys...');

      // Get all keys from secure storage
      final allKeys = await _storage.readAll();
      final recipientKeys =
          allKeys.keys.where((key) => key.startsWith('recipient_key_'));

      // Delete each recipient key
      for (final key in recipientKeys) {
        await _storage.delete(key: key);
        Logger.success(' EncryptionService:  Deleted recipient key: $key');
      }

      // Clear the cache
      _recipientPublicKeysCache.clear();

      Logger.info(' EncryptionService:  All recipient public keys cleared');
    } catch (e) {
      Logger.error(
          ' EncryptionService:  Error clearing recipient public keys: $e');
      rethrow;
    }
  }

  // ===== Utility Methods =====

  static String _preview(String s) =>
      s.length <= 64 ? s : '${s.substring(0, 64)}…';
  static void _log(String tag, String msg) =>
      Logger.debug(' EncryptionService[$tag] $msg');

  // ===== Storage and Cache =====

  static const _storage = FlutterSecureStorage();
  static const _publicKeyKey = 'public_key';
  static const _privateKeyKey = 'private_key';
  static const _keyPairVersion = 'key_pair_version';
  static final Map<String, String> _recipientPublicKeysCache =
      <String, String>{};

  // ===== Legacy Methods for Backward Compatibility =====

  /// Legacy method - use encryptAesCbcPkcs7 instead
  @deprecated
  static String encryptMessage(String message, String recipientPublicKey) {
    throw UnimplementedError('Use encryptAesCbcPkcs7 instead');
  }

  /// Legacy method - use decryptAesCbcPkcs7 instead
  @deprecated
  static Future<String> decryptMessage(String encryptedMessage) async {
    throw UnimplementedError('Use decryptAesCbcPkcs7 instead');
  }

  /// Legacy method - use encryptAesCbcPkcs7 instead
  @deprecated
  static Future<Map<String, dynamic>?> decryptDataWithRetry(
      String encryptedData,
      {int maxRetries = 2}) async {
    throw UnimplementedError('Use decryptAesCbcPkcs7 instead');
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

  /// Get current key pair version
  static Future<String> getKeyPairVersion() async {
    return await _storage.read(key: _keyPairVersion) ?? '1';
  }

  /// Generate device ID
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
    final random = Random.secure();
    final keyBytes = List<int>.generate(32, (i) => random.nextInt(256));
    final key = base64Encode(keyBytes);

    // Store for future use
    await _storage.write(key: 'test_key_$userId', value: key);
    return key;
  }

  /// Get a test key for development/testing
  static Future<String?> getTestKey(String userId) async {
    return await _storage.read(key: 'test_key_$userId');
  }

  /// Delete a test key
  static Future<void> deleteTestKey(String userId) async {
    await _storage.delete(key: 'test_key_$userId');
  }

  /// Test encryption/decryption round-trip
  static Future<bool> testEncryptionRoundTrip(String testData) async {
    try {
      final testMap = {
        'test': testData,
        'timestamp': DateTime.now().millisecondsSinceEpoch
      };
      final encrypted = await encryptAesCbcPkcs7(testMap, 'test_user');
      final decrypted = await decryptAesCbcPkcs7(encrypted['data']!);

      if (decrypted == null) return false;

      return decrypted['test'] == testData;
    } catch (e) {
      Logger.debug(' EncryptionService: Test round-trip failed: $e');
      return false;
    }
  }
}
