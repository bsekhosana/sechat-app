import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';

class AirNotifierService {
  static AirNotifierService? _instance;
  static AirNotifierService get instance =>
      _instance ??= AirNotifierService._();

  // AirNotifier configuration
  static const String _baseUrl = 'https://push.strapblaque.com';
  static const String _appName = 'sechat';
  static const String _appKey = 'ebea679133a7adfb9c4cd1f8b6a4fdc9';

  // Secure storage for session management
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  final Uuid _uuid = const Uuid();

  // Current session and user management
  String? _currentSessionId;
  String? _currentUserId;
  String? _currentDeviceToken;

  // Session ID management
  String? get currentSessionId => _currentSessionId;
  String? get currentUserId => _currentUserId;
  String? get currentDeviceToken => _currentDeviceToken;

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

      _currentDeviceToken = deviceToken;
      await _storage.write(key: 'device_token', value: deviceToken);

      final url = Uri.parse('$_baseUrl/api/v2/tokens');

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

  // Link token to session
  Future<bool> linkTokenToSession(String sessionId) async {
    try {
      if (_currentDeviceToken == null) {
        print('📱 AirNotifierService: ❌ No device token available for linking');
        return false;
      }

      print('📱 AirNotifierService: Linking token to session: $sessionId');

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

  // Send notification to specific session
  Future<bool> sendNotificationToSession({
    required String sessionId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? sound = 'default',
    int badge = 1,
  }) async {
    try {
      print(
          '📱 AirNotifierService: Sending notification to session: $sessionId');
      print('📱 AirNotifierService: Title: $title, Body: $body');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/v2/notifications/session'),
        headers: {
          'Content-Type': 'application/json',
          'X-An-App-Name': _appName,
          'X-An-App-Key': _appKey,
        },
        body: json.encode({
          'session_id': sessionId,
          'alert': {
            'title': title,
            'body': body,
          },
          'sound': sound,
          'badge': badge,
          'extra': data ?? {},
        }),
      );

      print(
          '📱 AirNotifierService: Notification response status: ${response.statusCode}');
      print(
          '📱 AirNotifierService: Notification response body: ${response.body}');

      if (response.statusCode == 202) {
        print(
            '📱 AirNotifierService: ✅ Notification sent successfully to session: $sessionId');
        return true;
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

      final response = await http.post(
        Uri.parse('$_baseUrl/api/v2/notifications/sessions'),
        headers: {
          'Content-Type': 'application/json',
          'X-An-App-Name': _appName,
          'X-An-App-Key': _appKey,
        },
        body: json.encode({
          'session_ids': sessionIds,
          'alert': {
            'title': title,
            'body': body,
          },
          'sound': sound,
          'badge': badge,
          'extra': data ?? {},
        }),
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

  // Send invitation notification (updated for session-based API)
  Future<bool> sendInvitationNotification({
    required String recipientId,
    required String senderName,
    required String invitationId,
    String? message,
  }) async {
    print('📱 AirNotifierService: Sending invitation notification');
    print('📱 AirNotifierService: Recipient ID: $recipientId');
    print('📱 AirNotifierService: Sender Name: $senderName');
    print('📱 AirNotifierService: Invitation ID: $invitationId');
    print('📱 AirNotifierService: Current User ID: $_currentUserId');

    return await sendNotificationToSession(
      sessionId: recipientId,
      title: 'New Contact Invitation',
      body: '$senderName wants to connect with you',
      data: {
        'type': 'invitation',
        'invitationId': invitationId,
        'senderName': senderName,
        'senderId': _currentUserId,
        'message': message ?? '',
        'action': 'invitation_received',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      sound: 'invitation.wav',
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

  // Send message notification (updated for session-based API)
  Future<bool> sendMessageNotification({
    required String recipientId,
    required String senderName,
    required String message,
    required String conversationId,
  }) async {
    return await sendNotificationToSession(
      sessionId: recipientId,
      title: senderName,
      body: message.length > 100 ? '${message.substring(0, 100)}...' : message,
      data: {
        'type': 'message',
        'senderName': senderName,
        'senderId': _currentUserId,
        'conversationId': conversationId,
        'message': message,
        'action': 'message_received',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      sound: 'message.wav',
    );
  }

  // Send typing indicator using silent push notification (updated for session-based API)
  Future<bool> sendTypingIndicator({
    required String recipientId,
    required String senderName,
    required bool isTyping,
  }) async {
    return await sendNotificationToSession(
      sessionId: recipientId,
      title: '', // Empty title for silent notification
      body: '', // Empty body for silent notification
      data: {
        'type': 'typing_indicator',
        'senderName': senderName,
        'senderId': _currentUserId,
        'isTyping': isTyping,
        'action': 'typing_indicator',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      sound: null, // No sound for typing indicators
      badge: 0, // No badge for silent notifications
    );
  }

  // Send real-time invitation update using silent notification (updated for session-based API)
  Future<bool> sendInvitationUpdate({
    required String recipientId,
    required String invitationId,
    required String action, // 'received', 'accepted', 'declined', 'cancelled'
    required String senderName,
    String? message,
  }) async {
    return await sendNotificationToSession(
      sessionId: recipientId,
      title: '', // Empty title for silent notification
      body: '', // Empty body for silent notification
      data: {
        'type': 'invitation_update',
        'invitationId': invitationId,
        'action': action,
        'senderName': senderName,
        'senderId': _currentUserId,
        'message': message ?? '',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      sound: null, // No sound for real-time updates
      badge: 0, // No badge for silent notifications
    );
  }

  // Send real-time message delivery status using silent notification (updated for session-based API)
  Future<bool> sendMessageDeliveryStatus({
    required String recipientId,
    required String messageId,
    required String status, // 'delivered', 'read'
    required String conversationId,
  }) async {
    return await sendNotificationToSession(
      sessionId: recipientId,
      title: '', // Empty title for silent notification
      body: '', // Empty body for silent notification
      data: {
        'type': 'message_delivery_status',
        'messageId': messageId,
        'status': status,
        'conversationId': conversationId,
        'senderId': _currentUserId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      sound: null, // No sound for delivery status
      badge: 0, // No badge for silent notifications
    );
  }

  // Send real-time online status update using silent notification (updated for session-based API)
  Future<bool> sendOnlineStatusUpdate({
    required String recipientId,
    required bool isOnline,
    String? lastSeen,
  }) async {
    return await sendNotificationToSession(
      sessionId: recipientId,
      title: '', // Empty title for silent notification
      body: '', // Empty body for silent notification
      data: {
        'type': 'online_status_update',
        'isOnline': isOnline,
        'lastSeen': lastSeen ?? DateTime.now().toIso8601String(),
        'senderId': _currentUserId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      sound: null, // No sound for status updates
      badge: 0, // No badge for silent notifications
    );
  }

  // Send message read notification (updated for session-based API)
  Future<bool> sendMessageReadNotification({
    required String recipientId,
    required String messageId,
    required String conversationId,
  }) async {
    return await sendNotificationToSession(
      sessionId: recipientId,
      title: '', // Empty title for silent notification
      body: '', // Empty body for silent notification
      data: {
        'type': 'message_read',
        'messageId': messageId,
        'conversationId': conversationId,
        'senderId': _currentUserId,
        'action': 'message_read',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      sound: null, // No sound for read notifications
      badge: 0, // No badge for silent notifications
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

  // Detect device type based on token format
  String _detectDeviceType(String token) {
    // iOS tokens are typically 64 characters long and contain alphanumeric characters
    if (token.length == 64 && RegExp(r'^[A-Fa-f0-9]+$').hasMatch(token)) {
      return 'ios';
    }
    // Android FCM tokens are typically longer and contain different characters
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

      print('📱 AirNotifierService: All data cleared');
    } catch (e) {
      print('📱 AirNotifierService: Error clearing data: $e');
    }
  }
}
