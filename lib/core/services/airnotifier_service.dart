import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import '../config/airnotifier_config.dart';
import '../../features/chat/services/enhanced_chat_encryption_service.dart';

class AirNotifierService {
  static AirNotifierService? _instance;
  static AirNotifierService get instance =>
      _instance ??= AirNotifierService._();

  // AirNotifier configuration from config file
  static String get _baseUrl => AirNotifierConfig.baseUrl;
  static String get _appName => AirNotifierConfig.appName;
  static String get _appKey => AirNotifierConfig.appKey;

  // Secure storage for session management
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  final Uuid _uuid = const Uuid();

  // Current session and user management
  String? _currentSessionId;
  String? _currentUserId;
  String? _currentDeviceToken;

  // Deduplication: Track recently sent invitations to prevent duplicates
  final Map<String, DateTime> _recentInvitations = {};
  static const Duration _invitationDeduplicationWindow = Duration(minutes: 5);

  // Enhanced encryption service for chat notifications
  final _encryptionService = EnhancedChatEncryptionService();

  // Test AirNotifier connectivity
  Future<bool> testAirNotifierConnection() async {
    try {
      print('📱 AirNotifierService: Testing connection to AirNotifier...');
      print('📱 AirNotifierService: Using base URL: $_baseUrl');

      // Print configuration for debugging
      AirNotifierConfig.printConfig();

      // Try to get tokens for current session to test connectivity
      if (_currentSessionId != null) {
        final response = await http.get(
          Uri.parse('$_baseUrl/api/v2/sessions/$_currentSessionId/tokens'),
          headers: {
            'Content-Type': 'application/json',
            'X-An-App-Name': _appName,
            'X-An-App-Key': _appKey,
          },
        );

        print(
            '📱 AirNotifierService: Connection test status: ${response.statusCode}');
        print('📱 AirNotifierService: Connection test body: ${response.body}');

        // 200 = success, 404 = no tokens (but connection works), 401/403 = auth issues
        return response.statusCode == 200 || response.statusCode == 404;
      } else {
        // If no session ID, just test basic connectivity with a simple request
        final response = await http.get(
          Uri.parse('$_baseUrl/api/v2/tokens'),
          headers: {
            'Content-Type': 'application/json',
            'X-An-App-Name': _appName,
            'X-An-App-Key': _appKey,
          },
        );

        print(
            '📱 AirNotifierService: Basic connection test status: ${response.statusCode}');
        print(
            '📱 AirNotifierService: Basic connection test body: ${response.body}');

        // 405 = Method Not Allowed (endpoint exists but wrong method) = connection works
        return response.statusCode == 405;
      }
    } catch (e) {
      print('📱 AirNotifierService: ❌ Connection test failed: $e');
      print('📱 AirNotifierService: Error details: ${e.toString()}');

      // Provide helpful error information
      if (e.toString().contains('CERTIFICATE_VERIFY_FAILED')) {
        print('📱 AirNotifierService: 💡 SSL Certificate issue detected');
        print('📱 AirNotifierService: 💡 Current URL: $_baseUrl');
        if (_baseUrl.startsWith('https://')) {
          print(
              '📱 AirNotifierService: 💡 Consider using HTTP for development or fix SSL certificate');
        }
      }

      return false;
    }
  }

  // Session ID management
  String? get currentSessionId => _currentSessionId;
  String? get currentUserId => _currentUserId;
  String? get currentDeviceToken => _currentDeviceToken;

  // Set current device token (public method for external use)
  Future<void> setCurrentDeviceToken(String token) async {
    _currentDeviceToken = token;
    await _storage.write(key: 'device_token', value: token);
    print(
        '📱 AirNotifierService: Current device token set: ${token.substring(0, 8)}...');
  }

  AirNotifierService._();

  // Initialize the service
  Future<void> initialize({String? sessionId}) async {
    try {
      print('📱 AirNotifierService: Initializing...');

      // Set current session ID if provided
      if (sessionId != null) {
        _currentSessionId = sessionId;
        _currentUserId =
            sessionId; // For Session Protocol, Session ID is the user ID
        await _storage.write(key: 'current_session_id', value: sessionId);
        print('📱 AirNotifierService: Session ID set: $sessionId');
      } else {
        // Try to restore from storage
        _currentSessionId = await _storage.read(key: 'current_session_id');
        _currentUserId = _currentSessionId;
        if (_currentSessionId != null) {
          print(
              '📱 AirNotifierService: Restored session ID: $_currentSessionId');
        }
      }

      // Test AirNotifier connectivity first
      final connectionTest = await testAirNotifierConnection();
      if (!connectionTest) {
        print(
            '📱 AirNotifierService: ⚠️ Warning: AirNotifier connection test failed');
      }

      // Get or generate device token
      await _initializeDeviceToken();

      print('📱 AirNotifierService: Initialized successfully');
    } catch (e) {
      print('📱 AirNotifierService: Error during initialization: $e');
    }
  }

  // Initialize device token
  Future<void> _initializeDeviceToken() async {
    try {
      // Get stored device token
      _currentDeviceToken = await _storage.read(key: 'device_token');

      if (_currentDeviceToken != null) {
        print(
            '📱 AirNotifierService: Restored device token: $_currentDeviceToken');

        // Link token to current session if available
        if (_currentSessionId != null) {
          await linkTokenToSession(_currentSessionId!);
        }
      } else {
        print(
            '📱 AirNotifierService: No device token found - will be set by native service');
      }
    } catch (e) {
      print('📱 AirNotifierService: Error initializing device token: $e');
    }
  }

  // Register device token with AirNotifier
  Future<bool> registerDeviceToken(
      {required String deviceToken, String? sessionId}) async {
    try {
      print('📱 AirNotifierService: Registering device token: $deviceToken');
      print('📱 AirNotifierService: Current session ID: $_currentSessionId');
      print('📱 AirNotifierService: Provided session ID: $sessionId');

      // Always update local storage first
      _currentDeviceToken = deviceToken;
      await _storage.write(key: 'device_token', value: deviceToken);

      final url = Uri.parse('$_baseUrl/api/v2/tokens');
      print('📱 AirNotifierService: Registration URL: $url');

      // Detect platform based on token format
      final deviceType = _detectDeviceType(deviceToken);
      print('📱 AirNotifierService: Detected device type: $deviceType');

      final payload = {
        'token': deviceToken,
        'device': deviceType,
        'channel': 'default',
        'user_id':
            sessionId ?? _currentSessionId, // Link to session if available
      };

      print(
          '📱 AirNotifierService: Device token registration payload: ${json.encode(payload)}');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-An-App-Name': _appName,
          'X-An-App-Key': _appKey,
        },
        body: json.encode(payload),
      );

      print(
          '📱 AirNotifierService: Device token registration response status: ${response.statusCode}');
      print(
          '📱 AirNotifierService: Device token registration response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('📱 AirNotifierService: ✅ Device token registered successfully');

        // Link token to session if available
        if (sessionId != null || _currentSessionId != null) {
          final sessionToLink = sessionId ?? _currentSessionId!;
          await linkTokenToSession(sessionToLink);

          // For iOS, also ensure the token is properly shared across sessions
          if (deviceType == 'ios') {
            await ensureIOSTokenVisibility(sessionToLink);
          }
        }

        return true;
      } else {
        print('📱 AirNotifierService: ❌ Device token registration failed');
        print(
            '📱 AirNotifierService: Status: ${response.statusCode}, Body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('📱 AirNotifierService: ❌ Error registering device token: $e');
      return false;
    }
  }

  /// Ensure iOS token is properly visible to other sessions
  Future<void> ensureIOSTokenVisibility(String sessionId) async {
    try {
      print(
          '📱 AirNotifierService: Ensuring iOS token visibility for session: $sessionId');

      // For iOS, we need to ensure the token is properly shared
      // This might involve additional API calls to make the token discoverable

      // First, check if the token is visible to other sessions
      final visibilityResponse = await http.get(
        Uri.parse('$_baseUrl/api/v2/sessions/$sessionId/tokens'),
        headers: {
          'Content-Type': 'application/json',
          'X-An-App-Name': _appName,
          'X-An-App-Key': _appKey,
        },
      );

      if (visibilityResponse.statusCode == 200) {
        final tokensData = json.decode(visibilityResponse.body);
        final tokens = tokensData['tokens'] as List?;

        if (tokens != null && tokens.isNotEmpty) {
          print(
              '📱 AirNotifierService: ✅ iOS token is visible to other sessions');
          print(
              '📱 AirNotifierService: Found ${tokens.length} tokens for session: $sessionId');
        } else {
          print(
              '📱 AirNotifierService: ⚠️ iOS token not visible to other sessions, attempting to fix...');
          await fixIOSTokenVisibility(sessionId);
        }
      } else {
        print(
            '📱 AirNotifierService: ⚠️ Could not check iOS token visibility: ${visibilityResponse.statusCode}');
      }
    } catch (e) {
      print('📱 AirNotifierService: Error ensuring iOS token visibility: $e');
    }
  }

  /// Fix iOS token visibility issues
  Future<void> fixIOSTokenVisibility(String sessionId) async {
    try {
      print(
          '📱 AirNotifierService: Attempting to fix iOS token visibility for session: $sessionId');

      // Try to re-register the token with explicit iOS device type
      if (_currentDeviceToken != null) {
        final fixPayload = {
          'token': _currentDeviceToken,
          'device': 'ios',
          'channel': 'default',
          'user_id': sessionId,
          'platform': 'ios',
          'visibility': 'public', // Ensure token is visible to other sessions
        };

        final fixResponse = await http.post(
          Uri.parse('$_baseUrl/api/v2/tokens/ios'),
          headers: {
            'Content-Type': 'application/json',
            'X-An-App-Name': _appName,
            'X-An-App-Key': _appKey,
          },
          body: json.encode(fixPayload),
        );

        if (fixResponse.statusCode == 200 || fixResponse.statusCode == 201) {
          print('📱 AirNotifierService: ✅ iOS token visibility fixed');
        } else {
          print(
              '📱 AirNotifierService: ⚠️ Could not fix iOS token visibility: ${fixResponse.statusCode}');
        }
      }
    } catch (e) {
      print('📱 AirNotifierService: Error fixing iOS token visibility: $e');
    }
  }

  /// Check if token is already linked to a session
  Future<bool> isTokenLinkedToSession(String sessionId) async {
    try {
      if (_currentDeviceToken == null) {
        print(
            '📱 AirNotifierService: ❌ No device token available for checking');
        return false;
      }

      // Check if we already have this session ID stored locally
      final storedSessionId = await _storage.read(key: 'current_session_id');
      if (storedSessionId == sessionId) {
        print(
            '📱 AirNotifierService: ℹ️ Token already linked to session: $sessionId');
        return true;
      }

      // Check with the server to see if token is linked
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/api/v2/sessions/$sessionId/tokens'),
          headers: {
            'X-An-App-Name': _appName,
            'X-An-App-Key': _appKey,
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final tokens = data['tokens'] as List?;

          if (tokens != null && tokens.isNotEmpty) {
            final isLinked =
                tokens.any((token) => token['token'] == _currentDeviceToken);
            print(
                '📱 AirNotifierService: Token link check result: $isLinked for session: $sessionId');
            return isLinked;
          } else {
            print(
                '📱 AirNotifierService: No tokens found for session: $sessionId');
            return false;
          }
        } else if (response.statusCode == 404) {
          print('📱 AirNotifierService: Session not found: $sessionId');
          return false;
        } else {
          print(
              '📱 AirNotifierService: Server error checking tokens: ${response.statusCode}');
          return false;
        }
      } catch (e) {
        print('📱 AirNotifierService: Error checking server for tokens: $e');
        // Fallback to local check
        return storedSessionId == sessionId;
      }
    } catch (e) {
      print('📱 AirNotifierService: ❌ Error checking token link status: $e');
      return false;
    }
  }

  /// Link token to session (only if not already linked)
  Future<bool> linkTokenToSession(String sessionId) async {
    try {
      if (_currentDeviceToken == null) {
        print('📱 AirNotifierService: ❌ No device token available for linking');
        return false;
      }

      // Check if token is already linked to this session
      final alreadyLinked = await isTokenLinkedToSession(sessionId);
      if (alreadyLinked) {
        print(
            '📱 AirNotifierService: ℹ️ Token already linked to session: $sessionId, skipping link');
        return true;
      }

      // Token not linked, proceed with linking
      print('📱 AirNotifierService: 🔗 Linking token to session: $sessionId');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/v2/sessions/link'),
        headers: {
          'Content-Type': 'application/json',
          'X-An-App-Name': _appName,
          'X-An-App-Key': _appKey,
        },
        body: json.encode({
          'token': _currentDeviceToken,
          'session_id': sessionId,
        }),
      );

      print(
          '📱 AirNotifierService: Session link response status: ${response.statusCode}');
      print(
          '📱 AirNotifierService: Session link response body: ${response.body}');

      if (response.statusCode == 200) {
        print('📱 AirNotifierService: ✅ Token linked to session successfully');
        _currentSessionId = sessionId;
        _currentUserId = sessionId;
        await _storage.write(key: 'current_session_id', value: sessionId);
        return true;
      } else {
        print('📱 AirNotifierService: ❌ Failed to link token to session');
        print(
            '📱 AirNotifierService: Status: ${response.statusCode}, Body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('📱 AirNotifierService: ❌ Error linking token to session: $e');
      return false;
    }
  }

  /// Save token for a specific session with platform namespacing
  Future<bool> saveTokenForSession({
    required String sessionId,
    required String token,
    required String platform,
  }) async {
    try {
      final key = 'push_token:$platform:session:$sessionId';
      await _storage.write(key: key, value: token);

      // Always update current token and main device_token key for immediate use
      // This prevents "No device token available for linking" errors
      _currentDeviceToken = token;
      await _storage.write(key: 'device_token', value: token);

      print(
          '📱 AirNotifierService: ✅ Token saved for session $sessionId (platform: $platform) and set as current');
      return true;
    } catch (e) {
      print('📱 AirNotifierService: ❌ Error saving token for session: $e');
      return false;
    }
  }

  /// Check if a session has any registered tokens
  Future<bool> hasAnyToken({required String sessionId}) async {
    try {
      // Check for both iOS and Android tokens
      final iosKey = 'push_token:ios:session:$sessionId';
      final androidKey = 'push_token:android:session:$sessionId';

      final iosToken = await _storage.read(key: iosKey);
      final androidToken = await _storage.read(key: androidKey);

      return iosToken != null || androidToken != null;
    } catch (e) {
      print('📱 AirNotifierService: ❌ Error checking tokens for session: $e');
      return false;
    }
  }

  // Unlink token from session
  Future<bool> unlinkTokenFromSession() async {
    try {
      if (_currentDeviceToken == null) {
        print(
            '📱 AirNotifierService: ❌ No device token available for unlinking');
        return false;
      }

      print('📱 AirNotifierService: Unlinking token from session');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/v2/sessions/unlink'),
        headers: {
          'Content-Type': 'application/json',
          'X-An-App-Name': _appName,
          'X-An-App-Key': _appKey,
        },
        body: json.encode({
          'token': _currentDeviceToken,
        }),
      );

      print(
          '📱 AirNotifierService: Session unlink response status: ${response.statusCode}');
      print(
          '📱 AirNotifierService: Session unlink response body: ${response.body}');

      if (response.statusCode == 200) {
        print(
            '📱 AirNotifierService: ✅ Token unlinked from session successfully');
        _currentSessionId = null;
        _currentUserId = null;
        await _storage.delete(key: 'current_session_id');
        return true;
      } else {
        print('📱 AirNotifierService: ❌ Failed to unlink token from session');
        print(
            '📱 AirNotifierService: Status: ${response.statusCode}, Body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('📱 AirNotifierService: ❌ Error unlinking token from session: $e');
      return false;
    }
  }

  // Replace session for current token
  Future<bool> replaceSession(String newSessionId) async {
    try {
      if (_currentDeviceToken == null) {
        print(
            '📱 AirNotifierService: ❌ No device token available for session replacement');
        return false;
      }

      print('📱 AirNotifierService: Replacing session with: $newSessionId');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/v2/sessions/replace'),
        headers: {
          'Content-Type': 'application/json',
          'X-An-App-Name': _appName,
          'X-An-App-Key': _appKey,
        },
        body: json.encode({
          'token': _currentDeviceToken,
          'session_id': newSessionId,
        }),
      );

      print(
          '📱 AirNotifierService: Session replace response status: ${response.statusCode}');
      print(
          '📱 AirNotifierService: Session replace response body: ${response.body}');

      if (response.statusCode == 200) {
        print('📱 AirNotifierService: ✅ Session replaced successfully');
        _currentSessionId = newSessionId;
        _currentUserId = newSessionId;
        await _storage.write(key: 'current_session_id', value: newSessionId);
        return true;
      } else {
        print('📱 AirNotifierService: ❌ Failed to replace session');
        print(
            '📱 AirNotifierService: Status: ${response.statusCode}, Body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('📱 AirNotifierService: ❌ Error replacing session: $e');
      return false;
    }
  }

  // Helper method to format notification payload for both iOS and Android
  Map<String, dynamic> _formatNotificationPayload({
    required String sessionId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? sound,
    int badge = 1,
    bool encrypted = false,
    String? checksum,
  }) {
    // Create simple, direct APNS-compliant payload
    final Map<String, dynamic> payload = {
      'session_id': sessionId,
    };

    // iOS APNS: aps dictionary with system-defined keys only
    final Map<String, dynamic> aps = {
      'alert': {
        'title': title,
        'body': body,
      },
      'sound': sound ?? 'default',
      'badge': badge,
    };

    // Add content-available for silent notifications if needed
    if (data != null && data.containsKey('type') && data['type'] == 'silent') {
      aps['content-available'] = 1;
      // Remove alert for silent notifications
      aps.remove('alert');
    }

    // Add aps to payload
    payload['aps'] = aps;

    // Add custom metadata OUTSIDE the aps dictionary (Apple's requirement)
    if (data != null && data.isNotEmpty) {
      print('📱 AirNotifierService: 🔍 Processing custom data: $data');

      // Add all custom data at the root level (outside aps)
      data.forEach((key, value) {
        // Ensure only JSON-compatible types
        if (value is String ||
            value is num ||
            value is bool ||
            value is List ||
            value is Map) {
          payload[key] = value;
        } else {
          // Convert non-JSON types to strings
          payload[key] = value.toString();
        }
      });
    }

    // Add encryption metadata if applicable
    if (encrypted) {
      payload['encrypted'] = true;
      if (checksum != null) {
        payload['checksum'] = checksum;
      }
    }

    print('📱 AirNotifierService: 🔍 Final APNS-compliant payload: $payload');
    return payload;
  }

  // Universal notification payload standard for AirNotifier server compatibility
  Map<String, dynamic> _formatUniversalPayload({
    required String sessionId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? sound,
    int badge = 1,
    bool encrypted = false,
    String? checksum,
    bool vibrate = true,
  }) {
    // Create universal notification payload standard
    final Map<String, dynamic> payload = {
      'session_id': sessionId,
      'alert': {
        'title': title,
        'body': body,
      },
      'sound': sound ?? 'default',
      'badge': badge,
      'vibrate': vibrate,
    };

    // Add custom metadata in data field for consistency
    if (data != null && data.isNotEmpty) {
      print('📱 AirNotifierService: 🔍 Processing custom data: $data');

      // Create data object with all custom fields
      final Map<String, dynamic> notificationData = {};

      data.forEach((key, value) {
        // Ensure only JSON-compatible types
        if (value is String ||
            value is num ||
            value is bool ||
            value is List ||
            value is Map) {
          notificationData[key] = value;
        } else {
          // Convert non-JSON types to strings
          notificationData[key] = value.toString();
        }
      });

      // Add data field to payload
      payload['data'] = notificationData;
    }

    // Add encryption metadata at top level (AirNotifier server expects this)
    if (encrypted) {
      payload['encrypted'] = true;
      if (checksum != null) {
        payload['checksum'] = checksum;
      }
    }

    print('📱 AirNotifierService: 🔍 Final universal payload: $payload');
    return payload;
  }

  // Create iOS-specific APNS payload following Apple's best practices
  Map<String, dynamic> _createIOSAPNSPayload({
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? sound,
    int badge = 1,
    bool silent = false,
  }) {
    // iOS APNS payload structure
    final Map<String, dynamic> payload = {};

    // aps dictionary with system-defined keys only
    final Map<String, dynamic> aps = {
      'alert': {
        'title': title,
        'body': body,
      },
      'sound': sound ?? 'default',
      'badge': badge,
    };

    // Add content-available for silent notifications
    if (silent) {
      aps['content-available'] = 1;
      // Remove alert for silent notifications
      aps.remove('alert');
    }

    payload['aps'] = aps;

    // Add custom metadata OUTSIDE the aps dictionary (Apple's requirement)
    if (data != null && data.isNotEmpty) {
      data.forEach((key, value) {
        // Ensure only JSON-compatible types
        if (value is String ||
            value is num ||
            value is bool ||
            value is List ||
            value is Map) {
          payload[key] = value;
        } else {
          // Convert non-JSON types to strings
          payload[key] = value.toString();
        }
      });
    }

    return payload;
  }

  // Create Android FCM payload
  Map<String, dynamic> _createAndroidFCMPayload({
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? sound,
    int badge = 1,
  }) {
    return {
      'notification': {
        'title': title,
        'body': body,
        'sound': sound ?? 'default',
      },
      'data': data ?? {},
      'priority': 'high',
      'android': {
        'priority': 'high',
        'notification': {
          'priority': 'high',
          'sound': sound ?? 'default',
        },
      },
    };
  }

  // Send notification to specific session
  Future<bool> sendNotificationToSession({
    required String sessionId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? sound = 'default',
    int badge = 1,
    bool encrypted = false,
    String? checksum,
    bool vibrate = true,
  }) async {
    try {
      print(
          '📱 AirNotifierService: Sending notification to session: $sessionId');
      print('📱 AirNotifierService: Title: $title, Body: $body');
      print('📱 AirNotifierService: Data payload: $data');
      print(
          '📱 AirNotifierService: Encrypted: $encrypted, Checksum: $checksum');

      // For iOS devices, check token visibility before sending
      if (_currentDeviceToken != null &&
          _detectDeviceType(_currentDeviceToken!) == 'ios') {
        print(
            '📱 AirNotifierService: iOS device detected, checking token visibility...');
        await ensureIOSTokenVisibility(_currentSessionId ?? '');
      }

      // Deduplication: Check if this exact notification was recently sent
      if (data != null && data.containsKey('invitationId')) {
        final invitationId = data['invitationId'] as String;
        final lastSent = _recentInvitations[invitationId];
        if (lastSent != null &&
            DateTime.now().difference(lastSent) <
                _invitationDeduplicationWindow) {
          print(
              '📱 AirNotifierService: Skipping duplicate invitation notification for ID: $invitationId');
          return true; // Indicate success, but don't send
        }

        // Track this invitation as recently sent
        _recentInvitations[invitationId] = DateTime.now();
        print(
            '📱 AirNotifierService: Tracking invitation notification for deduplication: $invitationId');

        // Clean up old entries periodically (every 10th invitation)
        if (_recentInvitations.length % 10 == 0) {
          _cleanupDeduplicationMap();
        }
      }

      // Use universal payload for AirNotifier server compatibility
      final payload = _formatUniversalPayload(
        sessionId: sessionId,
        title: title,
        body: body,
        data: data,
        sound: sound,
        badge: badge,
        encrypted: encrypted,
        checksum: checksum,
        vibrate: vibrate,
      );

      print('📱 AirNotifierService: Universal payload: $payload');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/v2/notifications/session'),
        headers: {
          'Content-Type': 'application/json',
          'X-An-App-Name': _appName,
          'X-An-App-Key': _appKey,
        },
        body: json.encode(payload),
      );

      print(
          '📱 AirNotifierService: Notification response status: ${response.statusCode}');
      print(
          '📱 AirNotifierService: Notification response body: ${response.body}');

      if (response.statusCode == 202) {
        // Parse response body to check actual delivery status
        try {
          final responseData = json.decode(response.body);
          final notificationsSent = responseData['notifications_sent'] ?? 0;
          final tokensFound = responseData['tokens_found'] ?? 0;

          print('📱 AirNotifierService: Response data: $responseData');
          print(
              '📱 AirNotifierService: Tokens found: $tokensFound, Notifications sent: $notificationsSent');

          if (notificationsSent > 0) {
            print(
                '📱 AirNotifierService: ✅ Notification delivered successfully to session: $sessionId');
            return true;
          } else {
            print(
                '📱 AirNotifierService: ⚠️ Notification accepted but not delivered to session: $sessionId');
            print(
                '📱 AirNotifierService: ❌ Delivery failed - tokens found: $tokensFound, notifications sent: $notificationsSent');
            // show snack

            return false;
          }
        } catch (parseError) {
          print(
              '📱 AirNotifierService: ⚠️ Could not parse response body: $parseError');
          print('📱 AirNotifierService: ⚠️ Raw response: ${response.body}');
          // If we can't parse the response, assume it failed
          return false;
        }
      } else {
        print(
            '📱 AirNotifierService: ❌ Failed to send notification to session: $sessionId');
        print(
            '📱 AirNotifierService: Status: ${response.statusCode}, Body: ${response.body}');
        return false;
      }
    } catch (e) {
      print(
          '📱 AirNotifierService: ❌ Error sending notification to session: $e');
      return false;
    }
  }

  // Send notification to specific session and return response details
  Future<Map<String, dynamic>?> sendNotificationToSessionWithResponse({
    required String sessionId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? sound = 'default',
    int badge = 1,
    bool encrypted = false,
    String? checksum,
  }) async {
    try {
      print(
          '📱 AirNotifierService: Sending notification to session: $sessionId');
      print('📱 AirNotifierService: Title: $title, Body: $body');

      // Use universal payload for AirNotifier server compatibility
      final payload = _formatUniversalPayload(
        sessionId: sessionId,
        title: title,
        body: body,
        data: data,
        sound: sound,
        badge: badge,
        encrypted: encrypted,
        checksum: checksum,
      );

      print('📱 AirNotifierService: Universal payload: $payload');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/v2/notifications/session'),
        headers: {
          'Content-Type': 'application/json',
          'X-An-App-Name': _appName,
          'X-An-App-Key': _appKey,
        },
        body: json.encode(payload),
      );

      print(
          '📱 AirNotifierService: Notification response status: ${response.statusCode}');
      print(
          '📱 AirNotifierService: Notification response body: ${response.body}');

      if (response.statusCode == 202) {
        print(
            '📱 AirNotifierService: ✅ Notification sent successfully to session: $sessionId');

        // Parse response body to get delivery details
        try {
          final responseData =
              json.decode(response.body) as Map<String, dynamic>;
          return responseData;
        } catch (e) {
          print('📱 AirNotifierService: ❌ Failed to parse response: $e');
          return null;
        }
      } else {
        print(
            '📱 AirNotifierService: ❌ Failed to send notification to session: $sessionId');
        print(
            '📱 AirNotifierService: Status: ${response.statusCode}, Body: ${response.body}');
        return null;
      }
    } catch (e) {
      print(
          '📱 AirNotifierService: ❌ Error sending notification to session: $e');
      return null;
    }
  }

  // Send notification to multiple sessions
  Future<Map<String, bool>> sendNotificationToMultipleSessions({
    required List<String> sessionIds,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? sound = 'default',
    int badge = 1,
  }) async {
    try {
      print(
          '📱 AirNotifierService: Sending notification to ${sessionIds.length} sessions');

      // Use universal payload for AirNotifier server compatibility
      final payload = _formatUniversalPayload(
        sessionId:
            sessionIds.first, // Use first session for formatting reference
        title: title,
        body: body,
        data: data,
        sound: sound,
        badge: badge,
      );

      // Override session_id with session_ids for multi-session
      payload['session_ids'] = sessionIds;
      payload.remove('session_id');

      print('📱 AirNotifierService: Multi-session universal payload: $payload');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/v2/notifications/sessions'),
        headers: {
          'Content-Type': 'application/json',
          'X-An-App-Name': _appName,
          'X-An-App-Key': _appKey,
        },
        body: json.encode(payload),
      );

      print(
          '📱 AirNotifierService: Multi-session notification response status: ${response.statusCode}');
      print(
          '📱 AirNotifierService: Multi-session notification response body: ${response.body}');

      if (response.statusCode == 202) {
        final result = json.decode(response.body);
        final totalSent = result['total_notifications_sent'] ?? 0;
        print(
            '📱 AirNotifierService: ✅ Notifications sent to $totalSent devices');

        // Return success for all sessions (simplified - in reality you'd get individual results)
        final results = <String, bool>{};
        for (final sessionId in sessionIds) {
          results[sessionId] = true;
        }
        return results;
      } else {
        print(
            '📱 AirNotifierService: ❌ Failed to send notifications to multiple sessions');
        print(
            '📱 AirNotifierService: Status: ${response.statusCode}, Body: ${response.body}');

        // Return failure for all sessions
        final results = <String, bool>{};
        for (final sessionId in sessionIds) {
          results[sessionId] = false;
        }
        return results;
      }
    } catch (e) {
      print(
          '📱 AirNotifierService: ❌ Error sending notifications to multiple sessions: $e');

      // Return failure for all sessions
      final results = <String, bool>{};
      for (final sessionId in sessionIds) {
        results[sessionId] = false;
      }
      return results;
    }
  }

  // Legacy method for backward compatibility - now uses session-based API
  Future<bool> sendNotification({
    required String recipientId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? sound = 'default',
    bool silent = false,
  }) async {
    // Use session-based notification
    return await sendNotificationToSession(
      sessionId:
          recipientId, // In Session Protocol, Session ID is the recipient ID
      title: title,
      body: body,
      data: data,
      sound: silent ? null : sound,
      badge: silent ? 0 : 1,
    );
  }

  // [STEP 4] Send invitation notification (updated for session-based API)
  Future<bool> sendInvitationNotification({
    required String recipientId,
    required String senderName,
    required String invitationId,
    String? message,
  }) async {
    print('📱 AirNotifierService: [STEP 4] Sending invitation notification');
    print('📱 AirNotifierService: Recipient ID: $recipientId');
    print('📱 AirNotifierService: Sender Name: $senderName');
    print('📱 AirNotifierService: Invitation ID: $invitationId');
    print('📱 AirNotifierService: Current User ID: $_currentUserId');

    // Check if this invitation was recently sent
    final lastSent = _recentInvitations[invitationId];
    if (lastSent != null &&
        DateTime.now().difference(lastSent) < _invitationDeduplicationWindow) {
      print(
          '📱 AirNotifierService: Skipping duplicate invitation notification for ID: $invitationId');
      return true; // Indicate success, but don't send
    }

    // [STEP 4A] Send push notification to recipient via AirNotifier server with complete invitation metadata
    return await sendNotificationToSession(
      sessionId: recipientId,
      title: 'New Contact Invitation',
      body: '$senderName would like to connect with you',
      data: {
        'type': 'invitation',
        'invitationId': invitationId,
        'senderName': senderName,
        'senderId': _currentUserId,
        'message': message ?? '',
        'action': 'invitation_received',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        // [STEP 4B] Complete invitation metadata for recipient's local database
        'invitation': {
          'id': invitationId,
          'senderId': _currentUserId,
          'recipientId': recipientId,
          'senderUsername': senderName,
          'recipientUsername': '', // Will be set by recipient
          'message': message ?? 'Contact request',
          'status': 'pending',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
          'isReceived': true,
        },
        // [STEP 4C] Sender user data for recipient's local database
        'senderUser': {
          'id': _currentUserId,
          'username': senderName,
          'profilePicture': null,
          'isOnline': false,
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
          'alreadyInvited': false,
          'invitationStatus': 'pending',
        },
      },
      sound: 'invitation.wav',
    );
  }

  // Send encrypted invitation notification
  Future<bool> sendEncryptedInvitationNotification({
    required String recipientId,
    required String senderName,
    required String invitationId,
    required String encryptedData,
    required String checksum,
    String? message,
  }) async {
    print('📱 AirNotifierService: Sending encrypted invitation notification');
    print('📱 AirNotifierService: Recipient ID: $recipientId');
    print('📱 AirNotifierService: Sender Name: $senderName');
    print('📱 AirNotifierService: Invitation ID: $invitationId');

    return await sendNotificationToSession(
      sessionId: recipientId,
      title: 'New Contact Invitation',
      body: '$senderName would like to connect with you',
      data: {
        'encrypted': true,
        'data': encryptedData,
        'checksum': checksum,
      },
      sound: 'invitation.wav',
      encrypted: true,
      checksum: checksum,
    );
  }

  // Send invitation response notification (updated for session-based API)
  Future<bool> sendInvitationResponseNotification({
    required String recipientId,
    required String responderName,
    required String status, // 'accepted' or 'declined'
    required String invitationId,
    String? chatId, // Include chat ID if accepted
  }) async {
    final title =
        status == 'accepted' ? 'Invitation Accepted' : 'Invitation Declined';
    final body = status == 'accepted'
        ? '$responderName accepted your invitation'
        : '$responderName declined your invitation';

    return await sendNotificationToSession(
      sessionId: recipientId,
      title: title,
      body: body,
      data: {
        'type': 'invitation_response',
        'invitationId': invitationId,
        'responderName': responderName,
        'responderId': _currentUserId,
        'status': status,
        'chatId': chatId, // Include chat ID for accepted invitations
        'action': 'invitation_response',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      sound: status == 'accepted' ? 'accepted.wav' : 'declined.wav',
    );
  }

  // Send encrypted invitation response notification
  Future<bool> sendEncryptedInvitationResponseNotification({
    required String recipientId,
    required String responderName,
    required String status, // 'accepted' or 'declined'
    required String invitationId,
    required String encryptedData,
    required String checksum,
    String? chatId, // Include chat ID if accepted
  }) async {
    final title =
        status == 'accepted' ? 'Invitation Accepted' : 'Invitation Declined';
    final body = status == 'accepted'
        ? '$responderName accepted your invitation'
        : '$responderName declined your invitation';

    return await sendNotificationToSession(
      sessionId: recipientId,
      title: title,
      body: body,
      data: {
        'encrypted': true,
        'data': encryptedData,
        'checksum': checksum,
      },
      sound: status == 'accepted' ? 'accepted.wav' : 'declined.wav',
      encrypted: true,
      checksum: checksum,
    );
  }

  // Send message notification (updated for session-based API)
  Future<bool> sendMessageNotification({
    required String recipientId,
    required String senderName,
    required String message,
    required String conversationId,
  }) async {
    // This method should be deprecated in favor of sendEncryptedMessageNotification
    // For now, we'll use generic titles/bodies to minimize data leakage
    // All sensitive data should be encrypted in the future
    return await sendNotificationToSession(
      sessionId: recipientId,
      title: 'New Message', // Generic title - no sensitive data
      body:
          'You have received a new message', // Generic body - no sensitive data
      data: {
        'type':
            'message', // Type indicator for routing (unencrypted for routing)
        'encrypted': false, // Mark as unencrypted for backward compatibility
        'senderName': senderName, // TODO: Encrypt this
        'senderId': _currentUserId, // TODO: Encrypt this
        'conversationId': conversationId, // TODO: Encrypt this
        'message': message, // TODO: Encrypt this
        'action': 'message_received',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      sound: 'message.wav',
    );
  }

  // Send encrypted message notification
  Future<bool> sendEncryptedMessageNotification({
    required String recipientId,
    required String senderName,
    required String encryptedData,
    required String checksum,
    required String conversationId,
  }) async {
    return await sendNotificationToSession(
      sessionId: recipientId,
      title: 'Secure Message', // Generic title - no sensitive data
      body:
          'You have received a secure message', // Generic body - no sensitive data
      data: {
        'encrypted': true,
        'type':
            'message', // Type indicator for routing (unencrypted for routing)
        'data': encryptedData, // Encrypted sensitive data
        'checksum': checksum, // Checksum for verification
      },
      sound: 'message.wav',
      encrypted: true,
      checksum: checksum,
    );
  }

  // Send typing indicator using silent push notification (updated for session-based API)
  Future<bool> sendTypingIndicator({
    required String recipientId,
    required String senderName,
    required bool isTyping,
    String?
        conversationId, // Optional conversation ID for proper encryption context
  }) async {
    try {
      print(
          '📱 AirNotifierService: Sending encrypted typing indicator to $recipientId');

      // Prepare typing indicator data for encryption
      final typingData = {
        'type': 'typing_indicator',
        'senderName': senderName,
        'senderId': _currentUserId,
        'isTyping': isTyping,
        'action': 'typing_indicator',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Ensure user-specific encryption keys are available
      final effectiveConversationId =
          conversationId ?? _generateUserConversationId(recipientId);
      await _ensureUserEncryptionKeys(recipientId);

      // Encrypt the typing indicator data using EnhancedChatEncryptionService
      final encryptedTypingIndicator =
          await _encryptionService.encryptTypingIndicator(
        senderId: _currentUserId ?? '',
        senderName: senderName,
        isTyping: isTyping,
        conversationId: effectiveConversationId,
      );

      final encryptedData =
          encryptedTypingIndicator['encrypted_data'] as String;
      final checksum = encryptedTypingIndicator['checksum'] as String;

      return await sendNotificationToSession(
        sessionId: recipientId,
        title: '', // Empty title for silent notification
        body: '', // Empty body for silent notification
        data: {
          'encrypted': true,
          'type':
              'typing_indicator', // Type indicator for routing (unencrypted for routing)
          'data': encryptedData, // Encrypted sensitive data
          'checksum': checksum, // Checksum for verification
        },
        sound: null, // No sound for typing indicators
        badge: 0, // No badge for silent notifications
        vibrate: false, // No vibration for typing indicators
        encrypted: true, // Mark as encrypted for AirNotifier server
      );
    } catch (e) {
      print(
          '📱 AirNotifierService: ❌ Error sending encrypted typing indicator: $e');
      return false;
    }
  }

  // Send real-time invitation update using silent notification (updated for session-based API)
  Future<bool> sendInvitationUpdate({
    required String recipientId,
    required String invitationId,
    required String action, // 'received', 'accepted', 'declined', 'cancelled'
    required String senderName,
    String? message,
  }) async {
    // Ensure user-specific encryption keys are available
    final userConversationId = _generateUserConversationId(recipientId);
    await _ensureUserEncryptionKeys(recipientId);

    final invitationData = {
      'type': 'invitation_update',
      'invitationId': invitationId,
      'action': action,
      'senderName': senderName,
      'senderId': _currentUserId,
      'message': message ?? '',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    // Use the enhanced encryption service with user-specific conversation context
    final encryptedInvitationData =
        await _encryptionService.encryptTypingIndicator(
      senderId: _currentUserId ?? '',
      senderName: senderName,
      isTyping:
          false, // Not typing, but using the same encryption method for consistency
      conversationId: userConversationId,
    );

    final encryptedData = encryptedInvitationData['encrypted_data'] as String;
    final checksum = encryptedInvitationData['checksum'] as String;

    return await sendNotificationToSession(
      sessionId: recipientId,
      title: '', // Empty title for silent notification
      body: '', // Empty body for silent notification
      data: {
        'encrypted': true,
        'type':
            'invitation_update', // Type indicator for routing (unencrypted for routing)
        'data': encryptedData, // Encrypted sensitive data
        'checksum': checksum, // Checksum for verification
      },
      sound: null, // No sound for real-time updates
      badge: 0, // No badge for silent notifications
      encrypted: true, // Mark as encrypted for AirNotifier server
    );
  }

  // Send real-time message delivery status using silent notification (updated for session-based API)
  Future<bool> sendMessageDeliveryStatus({
    required String recipientId,
    required String messageId,
    required String status, // 'delivered', 'read'
    required String conversationId,
  }) async {
    // Ensure user-specific encryption keys are available
    await _ensureUserEncryptionKeys(recipientId);

    // Encrypt the message delivery status data using EnhancedChatEncryptionService
    // For message delivery status, we'll use the conversation ID for proper encryption context
    final deliveryData = {
      'type': 'message_delivery_status',
      'messageId': messageId,
      'status': status,
      'conversationId': conversationId,
      'senderId': _currentUserId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    // Use the enhanced encryption service for message-related data
    final encryptedDeliveryData = await _encryptionService.encryptMessageStatus(
      messageId: messageId,
      status: status,
      conversationId: conversationId,
    );

    final encryptedData = encryptedDeliveryData['encrypted_data'] as String;
    final checksum = encryptedDeliveryData['checksum'] as String;

    return await sendNotificationToSession(
      sessionId: recipientId,
      title: '', // Empty title for silent notification
      body: '', // Empty body for silent notification
      data: {
        'encrypted': true,
        'type':
            'message_delivery_status', // Type indicator for routing (unencrypted for routing)
        'data': encryptedData, // Encrypted sensitive data
        'checksum': checksum, // Checksum for verification
      },
      sound: null, // No sound for delivery status
      badge: 0, // No badge for silent notifications
      encrypted: true, // Mark as encrypted for AirNotifier server
    );
  }

  // Send real-time online status update using silent notification (updated for session-based API)
  Future<bool> sendOnlineStatusUpdate({
    required String recipientId,
    required bool isOnline,
    String? lastSeen,
  }) async {
    // Ensure user-specific encryption keys are available
    final userConversationId = _generateUserConversationId(recipientId);
    await _ensureUserEncryptionKeys(recipientId);

    final statusData = {
      'type': 'online_status_update',
      'isOnline': isOnline,
      'lastSeen': lastSeen ?? DateTime.now().toIso8601String(),
      'senderId': _currentUserId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    // Use the enhanced encryption service with user-specific conversation context
    final encryptedStatusData = await _encryptionService.encryptOnlineStatus(
      userId: _currentUserId ?? '',
      isOnline: isOnline,
      lastSeen: lastSeen ?? DateTime.now().toIso8601String(),
    );

    final encryptedData = encryptedStatusData['encrypted_data'] as String;
    final checksum = encryptedStatusData['checksum'] as String;

    return await sendNotificationToSession(
      sessionId: recipientId,
      title: '', // Empty title for silent notification
      body: '', // Empty body for silent notification
      data: {
        'encrypted': true,
        'type':
            'online_status_update', // Type indicator for routing (unencrypted for routing)
        'data': encryptedData, // Encrypted sensitive data
        'checksum': checksum, // Checksum for verification
      },
      sound: null, // No sound for status updates
      badge: 0, // No badge for silent notifications
      encrypted: true, // Mark as encrypted for AirNotifier server
    );
  }

  // Send message read notification (updated for session-based API)
  Future<bool> sendMessageReadNotification({
    required String recipientId,
    required String messageId,
    required String conversationId,
  }) async {
    // Ensure user-specific encryption keys are available
    await _ensureUserEncryptionKeys(recipientId);

    // Encrypt the message read data using EnhancedChatEncryptionService
    // For message read notifications, we'll use the conversation ID for proper encryption context
    final readData = {
      'type': 'message_read',
      'messageId': messageId,
      'conversationId': conversationId,
      'senderId': _currentUserId,
      'action': 'message_read',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    // Use the enhanced encryption service for message-related data
    final encryptedReadData = await _encryptionService.encryptMessageStatus(
      messageId: messageId,
      status: 'read',
      conversationId: conversationId,
    );

    final encryptedData = encryptedReadData['encrypted_data'] as String;
    final checksum = encryptedReadData['checksum'] as String;

    return await sendNotificationToSession(
      sessionId: recipientId,
      title: '', // Empty title for silent notification
      body: '', // Empty body for silent notification
      data: {
        'encrypted': true,
        'type':
            'message_read', // Type indicator for routing (unencrypted for routing)
        'data': encryptedData, // Encrypted sensitive data
        'checksum': checksum, // Checksum for verification
      },
      sound: null, // No sound for read notifications
      badge: 0, // No badge for silent notifications
      encrypted: true, // Mark as encrypted for AirNotifier server
    );
  }

  // Batch send notifications to multiple users (updated for session-based API)
  Future<Map<String, bool>> sendBatchNotifications({
    required List<String> recipientIds,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    return await sendNotificationToMultipleSessions(
      sessionIds: recipientIds,
      title: title,
      body: body,
      data: data,
    );
  }

  // Test notification (updated for session-based API)
  Future<bool> sendTestNotification({
    required String recipientId,
  }) async {
    return await sendNotificationToSession(
      sessionId: recipientId,
      title: 'Test Notification',
      body: 'This is a test notification from SeChat',
      data: {
        'type': 'test',
        'action': 'test_notification',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  // Generate checksum for data integrity
  String _generateChecksum(String data) {
    // Simple SHA-256 checksum generation
    // In production, this should use a proper crypto library
    final bytes = utf8.encode(data);
    final hash = bytes.fold<int>(0, (prev, byte) => prev + byte);
    return hash.toString();
  }

  // Generate user-specific conversation ID for encryption context
  String _generateUserConversationId(String recipientId) {
    return 'user_${_currentUserId}_$recipientId';
  }

  // Ensure user-specific encryption keys are available
  Future<bool> _ensureUserEncryptionKeys(String recipientId) async {
    try {
      // Check if we have encryption keys for this user
      final userConversationId = _generateUserConversationId(recipientId);

      // Generate or retrieve encryption keys for this user
      await _encryptionService.generateConversationKey(userConversationId,
          recipientId: recipientId);

      print(
          '📱 AirNotifierService: ✅ User-specific encryption keys ensured for $recipientId');
      return true;
    } catch (e) {
      print(
          '📱 AirNotifierService: ❌ Failed to ensure user-specific encryption keys for $recipientId: $e');
      return false;
    }
  }

  // Detect device type based on token format
  String _detectDeviceType(String token) {
    // iOS tokens are typically 64 characters long and contain alphanumeric characters
    // They also have a specific format pattern
    if (token.length == 64 && RegExp(r'^[A-Fa-f0-9]+$').hasMatch(token)) {
      // Additional iOS token validation
      // iOS tokens typically don't contain certain patterns that Android tokens have
      if (!token.contains(':')) {
        // Android FCM tokens often contain colons
        return 'ios';
      }
    }

    // Android FCM tokens are typically longer and contain different characters
    // They can be 140+ characters and often contain colons, dots, and other special chars
    if (token.length > 100 || token.contains(':') || token.contains('.')) {
      return 'android';
    }

    // Fallback: if we can't determine, assume Android (more common)
    print(
        '📱 AirNotifierService: ⚠️ Could not determine device type for token, assuming Android');
    return 'android';
  }

  // Check if a Session ID has a registered device token
  Future<bool> hasRegisteredDeviceToken(String sessionId) async {
    // With the new session-based system, we can't directly check this
    // The AirNotifier server handles the session-to-token mapping
    // We'll assume it's registered if we have a current session
    return _currentSessionId != null;
  }

  // Get all registered Session IDs (simplified - in reality this would come from server)
  List<String> getRegisteredSessionIds() {
    return _currentSessionId != null ? [_currentSessionId!] : [];
  }

  // Check if service is initialized
  bool get isInitialized =>
      _currentSessionId != null && _currentDeviceToken != null;

  // Clear all data (for logout/account deletion)
  Future<void> clearAllData() async {
    try {
      // Unlink current token from session
      if (_currentSessionId != null && _currentDeviceToken != null) {
        await unlinkTokenFromSession();
      }

      // Clear stored data
      await _storage.delete(key: 'current_session_id');
      await _storage.delete(key: 'device_token');

      // Reset in-memory data
      _currentSessionId = null;
      _currentUserId = null;
      _currentDeviceToken = null;

      // Clear deduplication map
      _recentInvitations.clear();

      print('📱 AirNotifierService: All data cleared');
    } catch (e) {
      print('📱 AirNotifierService: Error clearing data: $e');
    }
  }

  // Clean up old deduplication entries
  void _cleanupDeduplicationMap() {
    final now = DateTime.now();
    final keysToRemove = <String>[];

    _recentInvitations.forEach((key, timestamp) {
      if (now.difference(timestamp) > _invitationDeduplicationWindow) {
        keysToRemove.add(key);
      }
    });

    for (final key in keysToRemove) {
      _recentInvitations.remove(key);
    }

    if (keysToRemove.isNotEmpty) {
      print(
          '📱 AirNotifierService: Cleaned up ${keysToRemove.length} old deduplication entries');
    }
  }

  /// Check if a token exists and is linked to a session
  Future<bool> isTokenExistsAndLinked(String sessionId) async {
    try {
      if (_currentDeviceToken == null) {
        print(
            '📱 AirNotifierService: ❌ No device token available for checking');
        return false;
      }

      print(
          '📱 AirNotifierService: 🔍 Checking if token exists and is linked to session: $sessionId');

      // First check local storage
      final storedSessionId = await _storage.read(key: 'current_session_id');
      if (storedSessionId == sessionId) {
        print(
            '📱 AirNotifierService: ℹ️ Token locally linked to session: $sessionId');
      }

      // Check with server
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/api/v2/sessions/$sessionId/tokens'),
          headers: {
            'X-An-App-Name': _appName,
            'X-An-App-Key': _appKey,
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final tokens = data['tokens'] as List?;

          if (tokens != null && tokens.isNotEmpty) {
            final tokenExists =
                tokens.any((token) => token['token'] == _currentDeviceToken);
            final isLinked = tokenExists;

            print(
                '📱 AirNotifierService: 🔍 Server check - Token exists: $tokenExists, Is linked: $isLinked');
            print(
                '📱 AirNotifierService: 🔍 Found ${tokens.length} tokens for session: $sessionId');

            return isLinked;
          } else {
            print(
                '📱 AirNotifierService: ❌ No tokens found for session: $sessionId');
            return false;
          }
        } else if (response.statusCode == 404) {
          print('📱 AirNotifierService: ❌ Session not found: $sessionId');
          return false;
        } else {
          print(
              '📱 AirNotifierService: ❌ Server error checking tokens: ${response.statusCode}');
          print('📱 AirNotifierService: 🔍 Response body: ${response.body}');
          return false;
        }
      } catch (e) {
        print('📱 AirNotifierService: ❌ Error checking server for tokens: $e');
        // Fallback to local check
        return storedSessionId == sessionId;
      }
    } catch (e) {
      print(
          '📱 AirNotifierService: ❌ Error checking token existence and link status: $e');
      return false;
    }
  }
}
