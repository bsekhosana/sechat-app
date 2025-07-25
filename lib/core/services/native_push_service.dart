import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'airnotifier_service.dart';

class NativePushService {
  static final NativePushService _instance = NativePushService._internal();
  factory NativePushService() => _instance;
  NativePushService._internal();

  static NativePushService get instance => _instance;

  static const MethodChannel _channel = MethodChannel('push_notifications');
  String? _deviceToken;
  bool _isInitialized = false;

  // Initialize the service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Set up method call handler
      _channel.setMethodCallHandler(_handleMethodCall);

      _isInitialized = true;
      print('📱 NativePushService: Initialized successfully');
    } catch (e) {
      print('📱 NativePushService: Error initializing: $e');
    }
  }

  // Handle method calls from native side
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onDeviceTokenReceived':
        await _handleDeviceTokenReceived(call.arguments as String);
        break;
      case 'onDeviceTokenError':
        await _handleDeviceTokenError(call.arguments as String);
        break;
      case 'onRemoteNotificationReceived':
        await _handleRemoteNotificationReceived(
            call.arguments as Map<String, dynamic>);
        break;
      default:
        print('📱 NativePushService: Unknown method call: ${call.method}');
    }
  }

  // Handle device token received from native side
  Future<void> _handleDeviceTokenReceived(String token) async {
    try {
      _deviceToken = token;
      print('📱 NativePushService: Device token received: $token');

      // Get current Session ID from AirNotifier service
      final sessionId = AirNotifierService.instance.currentSessionId;

      // Register device with AirNotifier (with Session ID if available)
      if (_deviceToken != null && sessionId != null) {
        final success = await AirNotifierService.instance.registerDeviceToken(
          deviceToken: _deviceToken!,
          sessionId: sessionId,
        );

        if (success) {
          print(
              '📱 NativePushService: ✅ Device token registered with AirNotifier for Session ID: $sessionId');
        } else {
          print(
              '📱 NativePushService: ❌ Failed to register device token with AirNotifier for Session ID: $sessionId');
        }
      } else if (_deviceToken != null) {
        print(
            '📱 NativePushService: ⚠️ Device token received but no Session ID available yet');
        // Store token for later registration when Session ID becomes available
        await _storeDeviceTokenForLaterRegistration(_deviceToken!);
      }
    } catch (e) {
      print('📱 NativePushService: Error handling device token: $e');
    }
  }

  // Handle device token error
  Future<void> _handleDeviceTokenError(String error) async {
    print('📱 NativePushService: Device token error: $error');
  }

  // Handle remote notification received
  Future<void> _handleRemoteNotificationReceived(
      Map<String, dynamic> userInfo) async {
    try {
      print('📱 NativePushService: Remote notification received: $userInfo');

      // Process the notification data
      final data = userInfo['data'] as Map<String, dynamic>? ?? userInfo;

      // Handle different notification types
      final type = data['type'] as String?;
      switch (type) {
        case 'invitation':
          await _handleInvitationNotification(data);
          break;
        case 'message':
          await _handleMessageNotification(data);
          break;
        case 'typing':
          await _handleTypingNotification(data);
          break;
        default:
          print('📱 NativePushService: Unknown notification type: $type');
      }
    } catch (e) {
      print('📱 NativePushService: Error handling remote notification: $e');
    }
  }

  // Handle invitation notification
  Future<void> _handleInvitationNotification(Map<String, dynamic> data) async {
    print('📱 NativePushService: Processing invitation notification: $data');
    // The PushNotificationHandler will handle this
  }

  // Handle message notification
  Future<void> _handleMessageNotification(Map<String, dynamic> data) async {
    print('📱 NativePushService: Processing message notification: $data');
    // The PushNotificationHandler will handle this
  }

  // Handle typing notification
  Future<void> _handleTypingNotification(Map<String, dynamic> data) async {
    print('📱 NativePushService: Processing typing notification: $data');
    // The PushNotificationHandler will handle this
  }

  // Store device token for later registration when Session ID becomes available
  Future<void> _storeDeviceTokenForLaterRegistration(String token) async {
    try {
      // Store in secure storage for later use
      final storage = const FlutterSecureStorage();
      await storage.write(key: 'pending_device_token', value: token);
      print('📱 NativePushService: Stored device token for later registration');
    } catch (e) {
      print('📱 NativePushService: Error storing device token: $e');
    }
  }

  // Register stored device token when Session ID becomes available
  Future<void> registerStoredDeviceToken(String sessionId) async {
    try {
      if (_deviceToken != null) {
        final success = await AirNotifierService.instance.registerDeviceToken(
          deviceToken: _deviceToken!,
          sessionId: sessionId,
        );

        if (success) {
          print(
              '📱 NativePushService: ✅ Stored device token registered for Session ID: $sessionId');
        } else {
          print(
              '📱 NativePushService: ❌ Failed to register stored device token for Session ID: $sessionId');
        }
      } else {
        // Check if there's a stored token
        final storage = const FlutterSecureStorage();
        final storedToken = await storage.read(key: 'pending_device_token');

        if (storedToken != null) {
          final success = await AirNotifierService.instance.registerDeviceToken(
            deviceToken: storedToken,
            sessionId: sessionId,
          );

          if (success) {
            print(
                '📱 NativePushService: ✅ Pending device token registered for Session ID: $sessionId');
            // Clear the stored token
            await storage.delete(key: 'pending_device_token');
          } else {
            print(
                '📱 NativePushService: ❌ Failed to register pending device token for Session ID: $sessionId');
          }
        }
      }
    } catch (e) {
      print('📱 NativePushService: Error registering stored device token: $e');
    }
  }

  // Get current device token
  String? get deviceToken => _deviceToken;

  // Check if device token is available
  bool get hasDeviceToken => _deviceToken != null;
}
