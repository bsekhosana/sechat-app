import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

class EncryptionService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _privateKeyKey = 'private_key';
  static const String _publicKeyKey = 'public_key';

  // Generate AES key pair for end-to-end encryption
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

    return {'publicKey': aesKeyBase64, 'privateKey': ivBase64};
  }

  static Future<String?> getPublicKey() async {
    return await _storage.read(key: _publicKeyKey);
  }

  static Future<String?> getPrivateKey() async {
    return await _storage.read(key: _privateKeyKey);
  }

  // Encrypt message with recipient's public key (AES key)
  static String encryptMessage(String message, String recipientPublicKey) {
    try {
      // Parse recipient's AES key
      final aesKeyBytes = base64Decode(recipientPublicKey);

      // Generate random IV for this message
      final random = Random.secure();
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
      final encryptedBytes = cipher.process(Uint8List.fromList(paddedMessage));

      // Combine IV and encrypted data
      final combined = Uint8List.fromList([...iv, ...encryptedBytes]);

      return base64Encode(combined);
    } catch (e) {
      throw Exception('Encryption failed: $e');
    }
  }

  // Decrypt message with own private key (IV)
  static Future<String> decryptMessage(String encryptedMessage) async {
    try {
      final privateKey = await getPrivateKey();
      if (privateKey == null) throw Exception('Private key not found');

      // Parse AES key and IV
      final aesKeyBytes = base64Decode(privateKey);
      final encryptedBytes = base64Decode(encryptedMessage);

      // Extract IV and encrypted data
      final iv = encryptedBytes.sublist(0, 16);
      final encryptedData = encryptedBytes.sublist(16);

      // Create AES cipher
      final cipher = CBCBlockCipher(AESEngine());
      final params = ParametersWithIV(
        KeyParameter(aesKeyBytes),
        Uint8List.fromList(iv),
      );
      cipher.init(false, params);

      // Decrypt message
      final decryptedBytes = cipher.process(Uint8List.fromList(encryptedData));
      final unpaddedMessage = _unpadMessage(decryptedBytes.toList());

      return utf8.decode(unpaddedMessage);
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }

  // PKCS7 padding
  static List<int> _padMessage(List<int> message) {
    final blockSize = 16;
    final paddingLength = blockSize - (message.length % blockSize);
    final padding = List<int>.filled(paddingLength, paddingLength);
    return [...message, ...padding];
  }

  // PKCS7 unpadding
  static List<int> _unpadMessage(List<int> message) {
    final paddingLength = message.last;
    return message.sublist(0, message.length - paddingLength);
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
}
