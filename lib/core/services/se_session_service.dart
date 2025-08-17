import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/export.dart' as pc;
import 'se_shared_preference_service.dart';
import '../utils/guid_generator.dart';
import 'secure_notification_service.dart';
import 'airnotifier_service.dart';

class SessionData {
  final String sessionId;
  final String publicKey;
  final String encryptedPrivateKey;
  final DateTime createdAt;
  final String displayName;
  final String? passwordHash;
  final bool isLoggedIn;

  SessionData({
    required this.sessionId,
    required this.publicKey,
    required this.encryptedPrivateKey,
    required this.createdAt,
    required this.displayName,
    this.passwordHash,
    this.isLoggedIn = false,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'publicKey': publicKey,
        'encryptedPrivateKey': encryptedPrivateKey,
        'createdAt': createdAt.toIso8601String(),
        'displayName': displayName,
        'passwordHash': passwordHash,
        'isLoggedIn': isLoggedIn,
      };

  factory SessionData.fromJson(Map<String, dynamic> json) => SessionData(
        sessionId: json['sessionId'],
        publicKey: json['publicKey'],
        encryptedPrivateKey: json['encryptedPrivateKey'],
        createdAt: DateTime.parse(json['createdAt']),
        displayName: json['displayName'],
        passwordHash: json['passwordHash'],
        isLoggedIn: json['isLoggedIn'] ?? false,
      );
}

class EncryptedMessage {
  final String sessionId;
  final String encryptedData;
  final String iv;
  final DateTime timestamp;
  final String senderId;

  EncryptedMessage({
    required this.sessionId,
    required this.encryptedData,
    required this.iv,
    required this.timestamp,
    required this.senderId,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'encryptedData': encryptedData,
        'iv': iv,
        'timestamp': timestamp.toIso8601String(),
        'senderId': senderId,
      };

  factory EncryptedMessage.fromJson(Map<String, dynamic> json) =>
      EncryptedMessage(
        sessionId: json['sessionId'],
        encryptedData: json['encryptedData'],
        iv: json['iv'],
        timestamp: DateTime.parse(json['timestamp']),
        senderId: json['senderId'],
      );
}

class SeSessionService {
  static final SeSessionService _instance = SeSessionService._internal();
  factory SeSessionService() => _instance;
  SeSessionService._internal();

  static const String _sessionKey = 'se_session_data';
  static const String _deviceKey = 'se_device_key';
  static const String _messagesKey = 'se_encrypted_messages';

  SessionData? _currentSession;
  String? _deviceEncryptionKey;
  final Map<String, List<EncryptedMessage>> _messageCache = {};

  // SharedPreferences service instance
  final SeSharedPreferenceService _prefsService = SeSharedPreferenceService();

  // Device-level encryption key (derived from device-specific data)
  Future<String> _getDeviceEncryptionKey() async {
    if (_deviceEncryptionKey != null) return _deviceEncryptionKey!;

    String? storedKey = await _prefsService.getString(_deviceKey);

    if (storedKey == null) {
      // Generate device-specific key
      final deviceInfo = await _getDeviceInfo();
      final hash = sha256.convert(utf8.encode(deviceInfo));
      storedKey = base64.encode(hash.bytes);
      await _prefsService.setString(_deviceKey, storedKey);
    }

    _deviceEncryptionKey = storedKey;
    return storedKey;
  }

  Future<String> _getDeviceInfo() async {
    // Use device-specific information for key derivation
    // This ensures the same device always generates the same key
    // Using more stable device identifiers for better persistence
    final deviceId = await _getStableDeviceId();
    return 'device_${deviceId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  // Get a stable device identifier
  Future<String> _getStableDeviceId() async {
    String? deviceId = await _prefsService.getString('device_id');

    if (deviceId == null) {
      // Generate a stable device ID
      final random = Random.secure();
      deviceId =
          base64.encode(List<int>.generate(32, (i) => random.nextInt(256)));
      await _prefsService.setString('device_id', deviceId);
    }

    return deviceId;
  }

  // Enhanced session persistence check
  Future<bool> hasPersistentSession() async {
    final sessionJson = await _prefsService.getString(_sessionKey);
    return sessionJson != null;
  }

  // Force reload session from storage
  Future<void> reloadSessionFromStorage() async {
    _currentSession = null;
    await loadSession();
  }

  // Backup session data
  Future<void> backupSession() async {
    if (_currentSession == null) return;

    final backupData = {
      'session': _currentSession!.toJson(),
      'messages': _messageCache.map((key, value) =>
          MapEntry(key, value.map((msg) => msg.toJson()).toList())),
      'backupTime': DateTime.now().toIso8601String(),
    };

    await _prefsService.setJson('se_session_backup', backupData);
  }

  // Restore session from backup
  Future<bool> restoreSessionFromBackup() async {
    final backupData = await _prefsService.getJson('se_session_backup');

    if (backupData == null) return false;

    try {
      final sessionData = SessionData.fromJson(backupData['session']);

      await _storeSession(sessionData);
      _currentSession = sessionData;

      // Restore messages
      final messagesMap = backupData['messages'] as Map<String, dynamic>;
      _messageCache.clear();

      for (final entry in messagesMap.entries) {
        final sessionId = entry.key;
        final messagesList = entry.value as List;
        _messageCache[sessionId] =
            messagesList.map((msg) => EncryptedMessage.fromJson(msg)).toList();
      }

      await _persistMessages();
      return true;
    } catch (e) {
      print('Error restoring session from backup: $e');
      return false;
    }
  }

  // Generate proper AES key pair for encryption
  Future<Map<String, String>> _generateKeyPair() async {
    final random = Random.secure();

    // Generate a proper 256-bit (32-byte) AES key
    final aesKeyBytes = List<int>.generate(32, (i) => random.nextInt(256));

    // For now, we'll use the same key for both public and private
    // In a real implementation, you'd use asymmetric encryption (RSA/ECC)
    final publicKey = base64.encode(aesKeyBytes);
    final privateKey = base64.encode(aesKeyBytes);

    return {
      'publicKey': publicKey,
      'privateKey': privateKey,
    };
  }

  // Generate 6-character password
  String _generatePassword() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(
          6, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }

  // Hash password for storage
  String _hashPassword(String password) {
    final hash = sha256.convert(utf8.encode(password));
    return base64.encode(hash.bytes);
  }

  // Verify password
  bool _verifyPassword(String password, String storedHash) {
    final hash = sha256.convert(utf8.encode(password));
    final passwordHash = base64.encode(hash.bytes);
    return passwordHash == storedHash;
  }

  // Encrypt private key with device key
  Future<String> _encryptPrivateKey(String privateKey) async {
    final deviceKey = await _getDeviceEncryptionKey();
    final key = encrypt.Key.fromBase64(deviceKey);
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));

    final encrypted = encrypter.encrypt(privateKey, iv: iv);
    return base64.encode(encrypted.bytes + iv.bytes);
  }

  // Decrypt private key with device key
  Future<String> decryptPrivateKey(String encryptedPrivateKey) async {
    final deviceKey = await _getDeviceEncryptionKey();
    final key = encrypt.Key.fromBase64(deviceKey);

    final bytes = base64.decode(encryptedPrivateKey);
    final iv = encrypt.IV(bytes.sublist(bytes.length - 16));
    final encrypted = encrypt.Encrypted(bytes.sublist(0, bytes.length - 16));

    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    return encrypter.decrypt(encrypted, iv: iv);
  }

  // Create new session
  Future<Map<String, dynamic>> createSession(String displayName) async {
    // Generate unique session GUID
    final sessionId = GuidGenerator.generateSessionGuid();

    // Generate key pair
    final keyPair = await _generateKeyPair();

    // Generate password
    final password = _generatePassword();
    final passwordHash = _hashPassword(password);

    // Encrypt private key with device key
    final encryptedPrivateKey =
        await _encryptPrivateKey(keyPair['privateKey']!);

    // Create session data
    final sessionData = SessionData(
      sessionId: sessionId,
      publicKey: keyPair['publicKey']!,
      encryptedPrivateKey: encryptedPrivateKey,
      createdAt: DateTime.now(),
      displayName: displayName,
      passwordHash: passwordHash,
      isLoggedIn: true, // User is logged in when session is created
    );

    // Store session
    await _storeSession(sessionData);
    _currentSession = sessionData;

    // Initialize notification services with new session
    await initializeNotificationServices();

    return {
      'sessionData': sessionData,
      'password': password,
    };
  }

  // Store session data
  Future<void> _storeSession(SessionData sessionData) async {
    try {
      final sessionJson = jsonEncode(sessionData.toJson());
      await _prefsService.setString(_sessionKey, sessionJson);

      // Also store individual fields for redundancy
      await _prefsService.setString(
          '${_sessionKey}_sessionId', sessionData.sessionId);
      await _prefsService.setString(
          '${_sessionKey}_displayName', sessionData.displayName);
      await _prefsService.setString(
          '${_sessionKey}_publicKey', sessionData.publicKey);
      await _prefsService.setString('${_sessionKey}_encryptedPrivateKey',
          sessionData.encryptedPrivateKey);
      await _prefsService.setString(
          '${_sessionKey}_createdAt', sessionData.createdAt.toIso8601String());
      if (sessionData.passwordHash != null) {
        await _prefsService.setString(
            '${_sessionKey}_passwordHash', sessionData.passwordHash!);
      }

      // Update current session
      _currentSession = sessionData;

      print('🔍 SeSessionService: Session data persisted successfully');
      print('🔍 SeSessionService: Session ID: ${sessionData.sessionId}');
      print('🔍 SeSessionService: Display Name: ${sessionData.displayName}');
    } catch (e) {
      print('🔍 SeSessionService: Error persisting session data: $e');
      rethrow;
    }
  }

  // Load existing session
  Future<SessionData?> loadSession() async {
    if (_currentSession != null) return _currentSession;

    try {
      // Try to load from main session JSON first
      final sessionJson = await _prefsService.getString(_sessionKey);
      if (sessionJson != null) {
        try {
          final sessionData = SessionData.fromJson(jsonDecode(sessionJson));
          _currentSession = sessionData;

          // Check and fix key formats if needed
          await _checkAndFixKeyFormats();

          return sessionData;
        } catch (e) {
          // Fall back to individual fields
        }
      }

      // Fallback: Try to reconstruct session from individual fields
      final sessionId =
          await _prefsService.getString('${_sessionKey}_sessionId');
      final displayName =
          await _prefsService.getString('${_sessionKey}_displayName');
      final publicKey =
          await _prefsService.getString('${_sessionKey}_publicKey');
      final encryptedPrivateKey =
          await _prefsService.getString('${_sessionKey}_encryptedPrivateKey');
      final createdAtStr =
          await _prefsService.getString('${_sessionKey}_createdAt');
      final passwordHash =
          await _prefsService.getString('${_sessionKey}_passwordHash');

      if (sessionId != null &&
          displayName != null &&
          publicKey != null &&
          encryptedPrivateKey != null &&
          createdAtStr != null) {
        try {
          final sessionData = SessionData(
            sessionId: sessionId,
            displayName: displayName,
            publicKey: publicKey,
            encryptedPrivateKey: encryptedPrivateKey,
            createdAt: DateTime.parse(createdAtStr),
            passwordHash: passwordHash,
          );
          _currentSession = sessionData;

          // Check and fix key formats if needed
          await _checkAndFixKeyFormats();

          return sessionData;
        } catch (e) {
          print('🔍 SeSessionService: Error reconstructing session: $e');
        }
      }

      return null;
    } catch (e) {
      print('🔍 SeSessionService: Error loading session: $e');
      return null;
    }
  }

  /// Check and fix key formats if they're in the old 256-byte format
  Future<void> _checkAndFixKeyFormats() async {
    try {
      if (_currentSession == null) return;

      final publicKeyBytes = base64.decode(_currentSession!.publicKey);
      print(
          '🔍 SeSessionService: Checking key format: ${publicKeyBytes.length} bytes');

      // If keys are in old 256-byte format, regenerate them
      if (publicKeyBytes.length == 256) {
        print(
            '🔍 SeSessionService: ⚠️ Detected old 256-byte key format, regenerating...');
        await regenerateProperKeys();
      } else if (publicKeyBytes.length == 32) {
        print('🔍 SeSessionService: ✅ Keys are in correct 32-byte format');
      } else {
        print(
            '🔍 SeSessionService: ⚠️ Unexpected key length: ${publicKeyBytes.length} bytes');
      }
    } catch (e) {
      print('🔍 SeSessionService: Error checking key formats: $e');
    }
  }

  // Get current session
  SessionData? get currentSession => _currentSession;

  // Login with display name and password
  Future<bool> login(String displayName, String password) async {
    // Load existing session
    final session = await loadSession();
    if (session == null) return false;

    // Check if display name matches
    if (session.displayName.toLowerCase() != displayName.toLowerCase()) {
      return false;
    }

    // Verify password
    if (session.passwordHash == null ||
        !_verifyPassword(password, session.passwordHash!)) {
      return false;
    }

    // Update session to logged in state
    final updatedSession = SessionData(
      sessionId: session.sessionId,
      publicKey: session.publicKey,
      encryptedPrivateKey: session.encryptedPrivateKey,
      createdAt: session.createdAt,
      displayName: session.displayName,
      passwordHash: session.passwordHash,
      isLoggedIn: true,
    );

    // Store updated session
    await _storeSession(updatedSession);
    _currentSession = updatedSession;

    // Initialize notification services with logged in session
    await initializeNotificationServices();

    return true;
  }

  // Check if user exists by display name
  Future<bool> userExists(String displayName) async {
    final session = await loadSession();
    if (session == null) return false;
    return session.displayName.toLowerCase() == displayName.toLowerCase();
  }

  // Validate session ID format
  bool isValidSessionId(String sessionId) {
    return GuidGenerator.isValidSessionGuid(sessionId);
  }

  // Check if session ID is unique (for future multi-session support)
  Future<bool> isSessionIdUnique(String sessionId) async {
    // For now, since we only support one session per device,
    // we just validate the format
    return isValidSessionId(sessionId);
  }

  // Generate a new session ID for testing or validation
  String generateNewSessionId() {
    return GuidGenerator.generateSessionGuid();
  }

  // Test session ID generation (for debugging)
  List<String> generateTestSessionIds(int count) {
    final List<String> sessionIds = [];
    for (int i = 0; i < count; i++) {
      sessionIds.add(GuidGenerator.generateSessionGuid());
    }
    return sessionIds;
  }

  // Check if user is already logged in (session exists and is valid)
  Future<bool> isUserLoggedIn() async {
    final session = await loadSession();
    if (session == null) return false;

    // Check if session has required data and is logged in
    if (session.sessionId.isNotEmpty &&
        session.displayName.isNotEmpty &&
        session.encryptedPrivateKey.isNotEmpty &&
        session.isLoggedIn) {
      print('🔍 SeSessionService: User is logged in');
      return true;
    }

    print('🔍 SeSessionService: Session found but user is not logged in');
    return false;
  }

  // Check if session has been properly logged in (has password hash)
  Future<bool> isSessionLoggedIn() async {
    final session = await loadSession();
    if (session == null) return false;

    // A session is considered "logged in" if it has a password hash
    // This indicates the user has successfully logged in at least once
    if (session.passwordHash != null && session.passwordHash!.isNotEmpty) {
      print('🔍 SeSessionService: Session has been logged in before');
      return true;
    }

    print('🔍 SeSessionService: Session exists but has not been logged in');
    return false;
  }

  // Logout - set isLoggedIn to false but keep session data and device token
  Future<bool> logout() async {
    final session = await loadSession();
    if (session == null) return false;

    // Update session to logged out state
    final updatedSession = SessionData(
      sessionId: session.sessionId,
      publicKey: session.publicKey,
      encryptedPrivateKey: session.encryptedPrivateKey,
      createdAt: session.createdAt,
      displayName: session.displayName,
      passwordHash: session.passwordHash,
      isLoggedIn: false,
    );

    // Store updated session
    await _storeSession(updatedSession);
    _currentSession = updatedSession;

    // Note: Device token is NOT deregistered on logout
    // User can still receive push notifications even when logged out
    // Token is only deregistered when account is deleted

    print(
        '🔍 SeSessionService: User logged out successfully (device token preserved)');
    return true;
  }

  // Validate session persistence and data integrity
  Future<Map<String, dynamic>> validateSessionPersistence() async {
    final result = <String, dynamic>{};

    // Check main session JSON
    final sessionJson = await _prefsService.getString(_sessionKey);
    result['hasMainJson'] = sessionJson != null;

    // Check individual fields
    result['hasSessionId'] =
        await _prefsService.getString('${_sessionKey}_sessionId') != null;
    result['hasDisplayName'] =
        await _prefsService.getString('${_sessionKey}_displayName') != null;
    result['hasPublicKey'] =
        await _prefsService.getString('${_sessionKey}_publicKey') != null;
    result['hasEncryptedPrivateKey'] =
        await _prefsService.getString('${_sessionKey}_encryptedPrivateKey') !=
            null;
    result['hasCreatedAt'] =
        await _prefsService.getString('${_sessionKey}_createdAt') != null;
    result['hasPasswordHash'] =
        await _prefsService.getString('${_sessionKey}_passwordHash') != null;

    // Check current session
    result['hasCurrentSession'] = _currentSession != null;

    // Check if session can be loaded
    final session = await loadSession();
    result['canLoadSession'] = session != null;

    if (session != null) {
      result['sessionId'] = session.sessionId;
      result['displayName'] = session.displayName;
      result['hasPasswordHash'] =
          session.passwordHash != null && session.passwordHash!.isNotEmpty;
      result['isLoggedIn'] = session.isLoggedIn;
    }

    print('🔍 SeSessionService: Session persistence validation: $result');
    return result;
  }

  // Delete current session (completely removes account and deregisters device token)
  Future<void> deleteSession() async {
    try {
      // Unregister device token from notification services (only on account deletion)
      await unregisterDeviceToken();

      // Remove main session data
      await _prefsService.remove(_sessionKey);
      await _prefsService.remove(_messagesKey);

      // Remove individual session fields
      await _prefsService.remove('${_sessionKey}_sessionId');
      await _prefsService.remove('${_sessionKey}_displayName');
      await _prefsService.remove('${_sessionKey}_publicKey');
      await _prefsService.remove('${_sessionKey}_encryptedPrivateKey');
      await _prefsService.remove('${_sessionKey}_createdAt');
      await _prefsService.remove('${_sessionKey}_passwordHash');

      // Clear session backup
      await _prefsService.remove('se_session_backup');

      // Clear current session and cache
      _currentSession = null;
      _messageCache.clear();

      print('🔍 SeSessionService: Session data completely removed');
    } catch (e) {
      print('🔍 SeSessionService: Error deleting session: $e');
      rethrow;
    }
  }

  // Encrypt data for a specific recipient
  Future<String> encryptData(String data, String recipientPublicKey) async {
    if (_currentSession == null) throw Exception('No active session');

    // Generate AES key for this message
    final aesKey = encrypt.Key.fromSecureRandom(32);
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(aesKey));

    // Encrypt the data with AES
    final encryptedData = encrypter.encrypt(data, iv: iv);

    // For demo purposes, we'll use a simple encryption of the AES key
    // In a real implementation, you'd use the recipient's public key
    final encryptedAesKey = base64.encode(aesKey.bytes);

    // Combine encrypted AES key and encrypted data
    final combined = {
      'encryptedKey': encryptedAesKey,
      'encryptedData': encryptedData.base64,
      'iv': iv.base64,
    };

    return base64.encode(utf8.encode(jsonEncode(combined)));
  }

  // Decrypt data received from a sender
  Future<String> decryptData(
      String encryptedData, String senderPublicKey) async {
    if (_currentSession == null) throw Exception('No active session');

    // Decode the combined data
    final combinedJson = utf8.decode(base64.decode(encryptedData));
    final combined = jsonDecode(combinedJson);

    // For demo purposes, we'll use a simple decryption
    // In a real implementation, you'd use your private key
    final aesKeyBytes = base64.decode(combined['encryptedKey']);
    final aesKey = encrypt.Key(Uint8List.fromList(aesKeyBytes));

    // Decrypt the data with AES
    final iv = encrypt.IV.fromBase64(combined['iv']);
    final encrypter = encrypt.Encrypter(encrypt.AES(aesKey));
    final encryptedMessage =
        encrypt.Encrypted.fromBase64(combined['encryptedData']);

    return encrypter.decrypt(encryptedMessage, iv: iv);
  }

  // Store encrypted message locally
  Future<void> storeEncryptedMessage(
      String sessionId, EncryptedMessage message) async {
    if (!_messageCache.containsKey(sessionId)) {
      _messageCache[sessionId] = [];
    }
    _messageCache[sessionId]!.add(message);

    // Persist to storage
    await _persistMessages();
  }

  // Get encrypted messages for a session
  Future<List<EncryptedMessage>> getEncryptedMessages(String sessionId) async {
    if (_messageCache.containsKey(sessionId)) {
      return _messageCache[sessionId]!;
    }

    // Load from storage
    await _loadMessages();
    return _messageCache[sessionId] ?? [];
  }

  // Persist messages to storage
  Future<void> _persistMessages() async {
    final messagesJson = _messageCache.map((key, value) =>
        MapEntry(key, value.map((msg) => msg.toJson()).toList()));
    await _prefsService.setString(_messagesKey, jsonEncode(messagesJson));
  }

  // Load messages from storage
  Future<void> _loadMessages() async {
    final messagesJson = await _prefsService.getString(_messagesKey);

    if (messagesJson != null) {
      try {
        final messagesMap = jsonDecode(messagesJson) as Map<String, dynamic>;
        _messageCache.clear();

        for (final entry in messagesMap.entries) {
          final sessionId = entry.key;
          final messagesList = entry.value as List;
          _messageCache[sessionId] = messagesList
              .map((msg) => EncryptedMessage.fromJson(msg))
              .toList();
        }
      } catch (e) {
        print('Error loading messages: $e');
      }
    }
  }

  // Clear all messages for a session
  Future<void> clearSessionMessages(String sessionId) async {
    _messageCache.remove(sessionId);
    await _persistMessages();
  }

  // Verify session integrity
  Future<bool> verifySessionIntegrity() async {
    if (_currentSession == null) return false;

    try {
      // Try to decrypt the private key
      await decryptPrivateKey(_currentSession!.encryptedPrivateKey);
      return true;
    } catch (e) {
      print('Session integrity check failed: $e');
      return false;
    }
  }

  // Get session statistics
  Map<String, dynamic> getSessionStats() {
    if (_currentSession == null) return {};

    return {
      'sessionId': _currentSession!.sessionId,
      'sessionIdValid': isValidSessionId(_currentSession!.sessionId),
      'displayName': _currentSession!.displayName,
      'createdAt': _currentSession!.createdAt.toIso8601String(),
      'totalMessages': _messageCache.values
          .fold(0, (sum, messages) => sum + messages.length),
      'activeSessions': _messageCache.length,
    };
  }

  // Export session data (for backup)
  Future<String> exportSessionData() async {
    if (_currentSession == null) throw Exception('No active session');

    final exportData = {
      'session': _currentSession!.toJson(),
      'messages': _messageCache.map((key, value) =>
          MapEntry(key, value.map((msg) => msg.toJson()).toList())),
      'exportedAt': DateTime.now().toIso8601String(),
    };

    return base64.encode(utf8.encode(jsonEncode(exportData)));
  }

  // Import session data (for restore)
  Future<void> importSessionData(String exportedData) async {
    try {
      final decodedData = utf8.decode(base64.decode(exportedData));
      final importData = jsonDecode(decodedData);

      final sessionData = SessionData.fromJson(importData['session']);
      await _storeSession(sessionData);
      _currentSession = sessionData;

      // Import messages
      final messagesMap = importData['messages'] as Map<String, dynamic>;
      _messageCache.clear();

      for (final entry in messagesMap.entries) {
        final sessionId = entry.key;
        final messagesList = entry.value as List;
        _messageCache[sessionId] =
            messagesList.map((msg) => EncryptedMessage.fromJson(msg)).toList();
      }

      await _persistMessages();
    } catch (e) {
      throw Exception('Invalid session data: $e');
    }
  }

  /// Initialize notification services with current session
  Future<void> initializeNotificationServices() async {
    try {
      print('🔍 SeSessionService: Initializing notification services...');

      if (currentSession == null) {
        print(
            '🔍 SeSessionService: No session available for notification services');
        return;
      }

      final sessionId = currentSession!.sessionId;
      print(
          '🔍 SeSessionService: Setting session ID for notifications: $sessionId');

      // Set session ID in SecureNotificationService
      await SecureNotificationService.instance.setSessionId(sessionId);

      // Initialize AirNotifier with session ID
      await AirNotifierService.instance.initialize(sessionId: sessionId);

      print(
          '🔍 SeSessionService: ✅ Notification services initialized with session: $sessionId');
    } catch (e) {
      print(
          '🔍 SeSessionService: Error initializing notification services: $e');
    }
  }

  /// Register device token with current session
  Future<void> registerDeviceToken(String deviceToken) async {
    try {
      print('🔍 SeSessionService: Registering device token: $deviceToken');

      if (currentSession == null) {
        print(
            '🔍 SeSessionService: No session available for device token registration');
        return;
      }

      final sessionId = currentSession!.sessionId;

      // Register token with SecureNotificationService
      await SecureNotificationService.instance.setDeviceToken(deviceToken);

      // Register token with AirNotifier
      await AirNotifierService.instance.registerDeviceToken(
        deviceToken: deviceToken,
        sessionId: sessionId,
      );

      print(
          '🔍 SeSessionService: ✅ Device token registered with session: $sessionId');
    } catch (e) {
      print('🔍 SeSessionService: Error registering device token: $e');
    }
  }

  /// Unregister device token from current session
  Future<void> unregisterDeviceToken() async {
    try {
      print('🔍 SeSessionService: Unregistering device token...');

      if (currentSession == null) {
        print(
            '🔍 SeSessionService: No session available for device token unregistration');
        return;
      }

      final sessionId = currentSession!.sessionId;

      // Unlink token from AirNotifier
      await AirNotifierService.instance.unlinkTokenFromSession();

      print(
          '🔍 SeSessionService: ✅ Device token unregistered from session: $sessionId');
    } catch (e) {
      print('🔍 SeSessionService: Error unregistering device token: $e');
    }
  }

  /// Get current session ID for notification services
  String? get currentSessionId => currentSession?.sessionId;

  /// Get current username
  Future<String?> getCurrentUsername() async {
    final session = await loadSession();
    return session?.displayName;
  }

  /// Check if notification services are properly configured
  Future<bool> areNotificationServicesConfigured() async {
    try {
      if (currentSession == null) {
        return false;
      }

      final sessionId = currentSession!.sessionId;
      final hasDeviceToken =
          SecureNotificationService.instance.isDeviceTokenRegistered();
      final airNotifierConnected =
          await AirNotifierService.instance.testAirNotifierConnection();

      print('🔍 SeSessionService: Notification services check:');
      print('🔍 SeSessionService: - Session ID: $sessionId');
      print('🔍 SeSessionService: - Has device token: $hasDeviceToken');
      print(
          '🔍 SeSessionService: - AirNotifier connected: $airNotifierConnected');

      return hasDeviceToken && airNotifierConnected;
    } catch (e) {
      print('🔍 SeSessionService: Error checking notification services: $e');
      return false;
    }
  }

  /// Regenerate proper AES keys for existing session (fixes old 256-byte keys)
  Future<void> regenerateProperKeys() async {
    try {
      print(
          '🔄 SeSessionService: Regenerating proper AES keys for current session');

      if (_currentSession == null) {
        print('🔄 SeSessionService: No current session to regenerate keys for');
        return;
      }

      // Generate new proper AES keys
      final newKeyPair = await _generateKeyPair();

      // Encrypt the new private key
      final encryptedPrivateKey =
          await _encryptPrivateKey(newKeyPair['privateKey']!);

      // Create new session data with updated keys
      final updatedSession = SessionData(
        sessionId: _currentSession!.sessionId,
        publicKey: newKeyPair['publicKey']!,
        encryptedPrivateKey: encryptedPrivateKey,
        createdAt: _currentSession!.createdAt,
        displayName: _currentSession!.displayName,
        passwordHash: _currentSession!.passwordHash,
        isLoggedIn: _currentSession!.isLoggedIn,
      );

      // Update the current session reference
      _currentSession = updatedSession;

      // Save the updated session
      await _storeSession(_currentSession!);

      print('🔄 SeSessionService: ✅ Proper AES keys regenerated and saved');
      print(
          '🔄 SeSessionService: New public key length: ${base64.decode(newKeyPair['publicKey']!).length} bytes');
    } catch (e) {
      print('🔄 SeSessionService: ❌ Error regenerating keys: $e');
    }
  }

  /// Get decrypted private key for encryption/decryption operations
  Future<String?> getDecryptedPrivateKey() async {
    try {
      if (_currentSession == null) {
        print('🔍 SeSessionService: No current session available');
        return null;
      }

      if (_currentSession!.encryptedPrivateKey.isEmpty) {
        print(
            '🔍 SeSessionService: No encrypted private key in current session');
        return null;
      }

      final decryptedKey =
          await decryptPrivateKey(_currentSession!.encryptedPrivateKey);
      print(
          '🔍 SeSessionService: ✅ Successfully retrieved decrypted private key');
      return decryptedKey;
    } catch (e) {
      print('🔍 SeSessionService: ❌ Error getting decrypted private key: $e');
      return null;
    }
  }
}
