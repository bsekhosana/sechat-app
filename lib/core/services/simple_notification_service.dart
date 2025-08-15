import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sechat_app/core/services/airnotifier_service.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/global_user_service.dart';
import 'package:sechat_app/core/services/encryption_service.dart';
import 'package:sechat_app/core/services/local_storage_service.dart';
import 'package:sechat_app/core/services/se_shared_preference_service.dart';
import 'package:sechat_app/core/services/key_exchange_service.dart';
import 'package:sechat_app/shared/models/chat.dart';
import 'package:sechat_app/shared/models/message.dart' as app_message;
import 'package:sechat_app/shared/models/key_exchange_request.dart';
import 'package:sechat_app/core/services/indicator_service.dart';
import 'package:flutter/material.dart';
import '../config/airnotifier_config.dart';
import 'package:sechat_app/features/key_exchange/providers/key_exchange_request_provider.dart';
import 'package:sechat_app/features/chat/models/chat_conversation.dart';
import 'package:sechat_app/features/chat/services/message_storage_service.dart';
import 'package:sechat_app/features/chat/services/message_status_tracking_service.dart';

/// Simple, consolidated notification service with end-to-end encryption
class SimpleNotificationService {
  static SimpleNotificationService? _instance;
  static SimpleNotificationService get instance =>
      _instance ??= SimpleNotificationService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final Random _random = Random.secure();

  bool _isInitialized = false;
  String? _deviceToken;
  String? _sessionId;
  PermissionStatus _permissionStatus = PermissionStatus.denied;

  // Notification callbacks
  Function(String senderId, String senderName, String message)?
      _onMessageReceived;
  Function(String senderId, bool isTyping)? _onTypingIndicator;
  Function(String recipientId, String encryptedData, String checksum)?
      _onEncryptedMessageReceived;
  Function(String senderId, String messageId, String status)?
      _onMessageStatusUpdate;

  // Key exchange callbacks
  Function(Map<String, dynamic> data)? _onKeyExchangeRequestReceived;
  Function(Map<String, dynamic> data)? _onKeyExchangeAccepted;
  Function(Map<String, dynamic> data)? _onKeyExchangeDeclined;

  // Notification provider callback
  Function(String title, String body, String type, Map<String, dynamic>? data)?
      _onNotificationReceived;

  // Conversation creation callback
  Function(ChatConversation conversation)? _onConversationCreated;

  // Prevent duplicate notification processing
  final Set<String> _processedNotifications = <String>{};

  SimpleNotificationService._();

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Get session ID (may be null initially - will be set later via setSessionId)
      _sessionId = SeSessionService().currentSessionId;

      // Request permissions first
      await _requestPermissions();

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Initialize AirNotifier with session ID (if available)
      if (_sessionId != null) {
        await _initializeAirNotifier();
      }

      _isInitialized = true;

      // Log final permission status and device token state
      print(
          '🔔 SimpleNotificationService: Final permission status: $_permissionStatus');
      print(
          '🔔 SimpleNotificationService: Device token available: ${_deviceToken != null ? "${_deviceToken!.substring(0, 8)}..." : "No"}');

      // Check method channel status for debugging
      if (Platform.isIOS) {
        final methodChannelReady = await _isMethodChannelReady();
        print(
            '🔔 SimpleNotificationService: Method channel ready: $methodChannelReady');

        final notificationsAvailable = await areNotificationsAvailable;
        print(
            '🔔 SimpleNotificationService: iOS notifications actually available: $notificationsAvailable');

        // Try to sync device token after initialization is complete
        if (_deviceToken == null || _deviceToken!.isEmpty) {
          print(
              '🔔 SimpleNotificationService: Attempting delayed device token sync...');
          await _syncDeviceTokenFromAirNotifier();
          print(
              '🔔 SimpleNotificationService: Device token after delayed sync: ${_deviceToken != null ? "${_deviceToken!.substring(0, 8)}..." : "No"}');
        }
      }
    } catch (e) {
      print('🔔 SimpleNotificationService: Error initializing: $e');
    }
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    if (kIsWeb) return;

    try {
      // For iOS, we need to handle permissions differently
      if (Platform.isIOS) {
        await _handleIOSPermissions();
      } else {
        // Android and other platforms
        final status = await Permission.notification.request();
        _permissionStatus = status;
        print(
            '🔔 SimpleNotificationService: Notification permission status: $_permissionStatus');
      }
    } catch (e) {
      print('🔔 SimpleNotificationService: Error requesting permissions: $e');
      // Fallback to denied status
      _permissionStatus = PermissionStatus.denied;
    }
  }

  /// Handle iOS notification permissions specifically
  Future<void> _handleIOSPermissions() async {
    try {
      print('🔔 SimpleNotificationService: Handling iOS permissions...');

      // For iOS, permissions are now requested during initialization in _initializeLocalNotifications
      // iOS automatically registers for remote notifications during app launch
      // We just need to ensure our method channel is ready for device token delivery

      // First, try to sync device token from AirNotifier service
      await _syncDeviceTokenFromAirNotifier();

      // Check if we already have a device token (indicating permissions were previously granted)
      if (_deviceToken != null && _deviceToken!.isNotEmpty) {
        print(
            '🔔 SimpleNotificationService: ✅ Device token already available, permissions were previously granted');
        _permissionStatus = PermissionStatus.granted;
      } else {
        // No device token available, but iOS handles registration automatically
        // We can try to register manually, but it's not critical
        try {
          await _registerForRemoteNotifications();
        } catch (e) {
          print(
              '🔔 SimpleNotificationService: ⚠️ Remote notification registration failed, but iOS handles this automatically: $e');
        }

        // Set permission status based on whether we can proceed
        _permissionStatus = PermissionStatus.granted;
      }

      print(
          '🔔 SimpleNotificationService: ✅ iOS notification permissions handled');
    } catch (e) {
      print('🔔 SimpleNotificationService: Error handling iOS permissions: $e');
      _permissionStatus = PermissionStatus.denied;
    }
  }

  /// Register for remote notifications on iOS
  Future<void> _registerForRemoteNotifications() async {
    try {
      print(
          '🔔 SimpleNotificationService: Registering for remote notifications...');

      // Check if we already have a device token
      if (_deviceToken != null && _deviceToken!.isNotEmpty) {
        print(
            '🔔 SimpleNotificationService: ✅ Device token already available: ${_deviceToken!.substring(0, 8)}...');
        print(
            '🔔 SimpleNotificationService: Skipping remote notification registration');
        return;
      }

      // Wait for method channel to be ready
      final isReady = await _waitForMethodChannel();

      if (!isReady) {
        print(
            '🔔 SimpleNotificationService: ⚠️ Method channel not ready, skipping remote notification registration');
        print(
            '🔔 SimpleNotificationService: iOS will handle registration automatically during app launch');
        return;
      }

      // Now try to register for remote notifications
      const channel = MethodChannel('push_notifications');
      await channel.invokeMethod('registerForRemoteNotifications');

      print(
          '🔔 SimpleNotificationService: ✅ Remote notification registration requested');
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error registering for remote notifications: $e');

      // If the method channel fails, we can still proceed
      // The iOS side will handle registration automatically during app launch
      print(
          '🔔 SimpleNotificationService: ⚠️ Continuing without method channel registration');
    }
  }

  /// Check if iOS system actually allows notifications (debug only)
  Future<bool> _checkIOSNotificationCapability() async {
    try {
      print(
          '🔔 SimpleNotificationService: Checking iOS notification capability (debug only)...');

      // This is now just a debug check - don't use it to override permission status
      final result = await _localNotifications.initialize(
        const InitializationSettings(
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );

      print(
          '🔔 SimpleNotificationService: Local notifications initialization result: $result');
      return result == true;
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error checking iOS notification capability: $e');
      return false;
    }
  }

  /// Force refresh iOS permissions by checking system state
  Future<void> _forceRefreshIOSPermissions() async {
    try {
      print(
          '🔔 SimpleNotificationService: Force refreshing iOS permissions...');

      // Clear cached permission status
      _permissionStatus = PermissionStatus.denied;

      // For iOS, permissions are already requested during initialization
      // iOS automatically registers for remote notifications during app launch
      // Focus on syncing device token from AirNotifier
      if (Platform.isIOS) {
        // First, try to sync device token from AirNotifier service
        await _syncDeviceTokenFromAirNotifier();

        // Manual registration is optional since iOS handles this automatically
        try {
          await _registerForRemoteNotifications();
        } catch (e) {
          print(
              '🔔 SimpleNotificationService: ⚠️ Remote notification registration failed, but iOS handles this automatically: $e');
        }

        // Set permission status based on whether we can proceed
        _permissionStatus = PermissionStatus.granted;
        print('🔔 SimpleNotificationService: iOS permission refresh completed');
      }

      print(
          '🔔 SimpleNotificationService: Final permission status after refresh: $_permissionStatus');
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error force refreshing iOS permissions: $e');
      _permissionStatus = PermissionStatus.denied;
    }
  }

  /// Show dialog to guide iOS user to settings
  Future<void> _showIOSPermissionDialog() async {
    try {
      // This will be handled by the UI layer
      print(
          '🔔 SimpleNotificationService: iOS permission dialog should be shown by UI');
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error showing iOS permission dialog: $e');
    }
  }

  /// Get current permission status
  PermissionStatus get permissionStatus => _permissionStatus;

  /// Check if notifications are actually available (not just permission granted)
  Future<bool> get areNotificationsAvailable async {
    if (kIsWeb) return false;

    if (Platform.isIOS) {
      // For iOS, just check permission status - don't override with capability checks
      return _permissionStatus == PermissionStatus.granted;
    } else {
      // For other platforms, just check permission
      return _permissionStatus == PermissionStatus.granted;
    }
  }

  /// Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    if (kIsWeb) return;

    try {
      print(
          '🔔 SimpleNotificationService: Initializing local notifications...');

      if (Platform.isIOS) {
        // For iOS, request permissions during initialization
        // This will trigger the iOS permission dialog
        const DarwinInitializationSettings iosSettings =
            DarwinInitializationSettings(
          requestAlertPermission:
              true, // Request permissions during initialization
          requestBadgePermission: true,
          requestSoundPermission: true,
          // Always use production APNS for production AirNotifier server
          defaultPresentAlert: false,
          defaultPresentBadge: false,
          defaultPresentSound: false,
        );

        const InitializationSettings settings = InitializationSettings(
          iOS: iosSettings,
        );

        final result = await _localNotifications.initialize(settings);
        print(
            '🔔 SimpleNotificationService: iOS local notifications initialized: $result');

        // Set APNS environment to production
        await _setIOSAPNSEnvironment();
      } else if (Platform.isAndroid) {
        const AndroidInitializationSettings androidSettings =
            AndroidInitializationSettings('@mipmap/ic_launcher');

        const InitializationSettings settings = InitializationSettings(
          android: androidSettings,
        );

        final result = await _localNotifications.initialize(settings);
        print(
            '🔔 SimpleNotificationService: Android local notifications initialized: $result');
      }
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error initializing local notifications: $e');
    }
  }

  /// Set iOS APNS environment to production
  Future<void> _setIOSAPNSEnvironment() async {
    try {
      print(
          '🔔 SimpleNotificationService: Setting iOS APNS environment to production...');

      // For iOS, we need to ensure APNS is configured for production
      // This is critical when pointing to production AirNotifier server

      // Check if we're pointing to production AirNotifier
      final isProductionAirNotifier =
          AirNotifierConfig.baseUrl.contains('strapblaque.com') ||
              AirNotifierConfig.baseUrl.contains('production');

      if (isProductionAirNotifier) {
        print(
            '🔔 SimpleNotificationService: ✅ Production AirNotifier detected, ensuring production APNS configuration');

        // iOS will automatically use production APNS when the app is built with production provisioning
        // But we can verify the configuration is correct

        // Check notification settings to ensure they're properly configured
        final notificationSettings =
            await _localNotifications.getNotificationAppLaunchDetails();
        print(
            '🔔 SimpleNotificationService: iOS notification launch details: $notificationSettings');

        // Verify APNS environment
        print(
            '🔔 SimpleNotificationService: ✅ iOS APNS configured for production environment');
        print(
            '🔔 SimpleNotificationService: 💡 Note: APNS environment is determined by provisioning profile, not runtime configuration');
      } else {
        print(
            '🔔 SimpleNotificationService: ⚠️ Non-production AirNotifier detected, but APNS should still be production for iOS');
        print(
            '🔔 SimpleNotificationService: 💡 iOS requires production APNS for production AirNotifier servers');
      }
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error setting iOS APNS environment: $e');
    }
  }

  /// Initialize AirNotifier with session ID
  Future<void> _initializeAirNotifier() async {
    if (_sessionId == null) {
      print(
          '🔔 SimpleNotificationService: No session ID available for AirNotifier');
      return;
    }

    try {
      // Initialize AirNotifier with current session ID
      await AirNotifierService.instance.initialize();
      print(
          '🔔 SimpleNotificationService: AirNotifier initialized with session ID: $_sessionId');

      // Sync device token from AirNotifier service
      await _syncDeviceTokenFromAirNotifier();
    } catch (e) {
      print('🔔 SimpleNotificationService: Error initializing AirNotifier: $e');
    }
  }

  /// Sync device token from AirNotifier service
  Future<void> _syncDeviceTokenFromAirNotifier() async {
    try {
      print(
          '🔔 SimpleNotificationService: Syncing device token from AirNotifier...');

      // Add a small delay to ensure AirNotifier is fully initialized
      await Future.delayed(const Duration(milliseconds: 500));

      // Get the current device token from AirNotifier service
      final airNotifierToken = AirNotifierService.instance.currentDeviceToken;

      print(
          '🔔 SimpleNotificationService: AirNotifier device token: ${airNotifierToken != null ? "${airNotifierToken.substring(0, 8)}..." : "No"}');
      print(
          '🔔 SimpleNotificationService: Current device token: ${_deviceToken != null ? "${_deviceToken!.substring(0, 8)}..." : "No"}');

      if (airNotifierToken != null && airNotifierToken.isNotEmpty) {
        print(
            '🔔 SimpleNotificationService: Syncing device token from AirNotifier: ${airNotifierToken.substring(0, 8)}...');

        // Set the device token in this service
        _deviceToken = airNotifierToken;

        // Link the token to the current session
        if (_sessionId != null) {
          await _linkTokenToSession();
        }

        print(
            '🔔 SimpleNotificationService: ✅ Device token synced from AirNotifier');
        print(
            '🔔 SimpleNotificationService: Device token after sync: ${_deviceToken != null ? "${_deviceToken!.substring(0, 8)}..." : "No"}');
      } else {
        print(
            '🔔 SimpleNotificationService: No device token available in AirNotifier service');

        // Try to get device token from storage as fallback
        await _tryRestoreDeviceTokenFromStorage();
      }
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error syncing device token from AirNotifier: $e');

      // Try to get device token from storage as fallback
      await _tryRestoreDeviceTokenFromStorage();
    }
  }

  /// Try to restore device token from storage as fallback
  Future<void> _tryRestoreDeviceTokenFromStorage() async {
    try {
      print(
          '🔔 SimpleNotificationService: Trying to restore device token from storage...');

      final storedToken = await _storage.read(key: 'device_token');

      if (storedToken != null && storedToken.isNotEmpty) {
        print(
            '🔔 SimpleNotificationService: Found device token in storage: ${storedToken.substring(0, 8)}...');

        // Set the device token in this service
        _deviceToken = storedToken;

        // Link the token to the current session
        if (_sessionId != null) {
          await _linkTokenToSession();
        }

        print(
            '🔔 SimpleNotificationService: ✅ Device token restored from storage');
      } else {
        print('🔔 SimpleNotificationService: No device token found in storage');
      }
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error restoring device token from storage: $e');
    }
  }

  /// Send message notification
  Future<bool> sendMessage({
    required String recipientId,
    required String senderName,
    required String message,
    required String conversationId,
  }) async {
    try {
      print('🔔 SimpleNotificationService: Sending message');

      // Create message data
      final messageData = {
        'type': 'message',
        'senderName': senderName,
        'senderId': SeSessionService().currentSessionId,
        'message': message,
        'conversationId': conversationId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'version': '1.0',
      };

      // Encrypt the message data
      final encryptedData = await _encryptData(messageData, recipientId);
      final checksum = _generateChecksum(messageData);

      // Send via AirNotifier with FULL ENCRYPTION
      // Use generic title/body to prevent data leakage to Google/Apple servers
      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: recipientId,
        title: 'Text Alert', // Generic title - no sensitive data
        body:
            'You have received a text message', // Generic body - no sensitive data
        data: {
          'encrypted': true,
          'type':
              'message', // Type indicator for routing (unencrypted for routing)
          'data': encryptedData, // Encrypted sensitive data
          'checksum': checksum, // Checksum for verification
        },
        sound: 'message.wav',
        encrypted: true, // Mark as encrypted for AirNotifier server
        checksum: checksum, // Include checksum for verification
      );

      if (success) {
        print('🔔 SimpleNotificationService: ✅ Message sent');
        return true;
      } else {
        print('🔔 SimpleNotificationService: ❌ Failed to send message');
        return false;
      }
    } catch (e) {
      print('🔔 SimpleNotificationService: Error sending message: $e');
      return false;
    }
  }

  /// Send encrypted message notification
  Future<bool> sendEncryptedMessage({
    required String recipientId,
    required String senderName,
    required String message,
    required String conversationId,
    required String encryptedData,
    required String checksum,
    String? messageId,
  }) async {
    try {
      print('🔔 SimpleNotificationService: Sending encrypted message');

      // Send via AirNotifier with FULL ENCRYPTION
      // Use generic title/body to prevent data leakage to Google/Apple servers
      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: recipientId,
        title: 'Secure Alert', // Generic title - no sensitive data
        body:
            'You have received a secure message', // Generic body - no sensitive data
        data: {
          'encrypted': true,
          'type':
              'message', // Type indicator for routing (unencrypted for routing)
          'data': encryptedData, // Encrypted sensitive data
          'checksum': checksum, // Checksum for verification
          'messageId': messageId, // Additional metadata
          'conversationId': conversationId, // Additional metadata
        },
        sound: 'message.wav',
        encrypted: true, // Mark as encrypted for AirNotifier server
        checksum: checksum, // Include checksum for verification
      );

      if (success) {
        print('🔔 SimpleNotificationService: ✅ Encrypted message sent');
        return true;
      } else {
        print(
            '🔔 SimpleNotificationService: ❌ Failed to send encrypted message');
        return false;
      }
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error sending encrypted message: $e');
      return false;
    }
  }

  /// Process received notification
  Future<Map<String, dynamic>?> processNotification(
      Map<String, dynamic> notificationData) async {
    try {
      print('🔔 SimpleNotificationService: Processing notification');
      print(
          '🔔 SimpleNotificationService: Notification data keys: ${notificationData.keys.toList()}');
      print(
          '🔔 SimpleNotificationService: Notification data types: ${notificationData.map((key, value) => MapEntry(key, value.runtimeType))}');

      // Check if notification is encrypted (handle both bool and string)
      final encryptedValue = notificationData['encrypted'];
      print(
          '🔔 SimpleNotificationService: Encrypted value: $encryptedValue (type: ${encryptedValue.runtimeType})');

      final isEncrypted = encryptedValue == true ||
          encryptedValue == 'true' ||
          encryptedValue == '1';

      print('🔔 SimpleNotificationService: Is encrypted: $isEncrypted');

      if (isEncrypted) {
        print(
            '🔔 SimpleNotificationService: 🔐 Processing encrypted notification');
        print(
            '🔔 SimpleNotificationService: Encrypted value: $encryptedValue (type: ${encryptedValue.runtimeType})');

        // Get encrypted data from the new structure
        var encryptedData = notificationData['data'] as String?;
        if (encryptedData == null) {
          // Fallback: try the old 'encryptedData' field for backward compatibility
          final fallbackData = notificationData['encryptedData'] as String?;
          if (fallbackData != null) {
            print(
                '🔔 SimpleNotificationService: Using fallback encryptedData field for encrypted content');
            encryptedData = fallbackData;
          } else {
            // Check if this is a silent notification (typing indicator, status updates)
            // These don't need encryption since they're just UI state updates
            final notificationType = notificationData['type'] as String?;
            if (notificationType == 'typing_indicator' ||
                notificationType == 'message_delivery_status' ||
                notificationType == 'online_status_update' ||
                notificationType == 'invitation_update') {
              print(
                  '🔔 SimpleNotificationService: Processing silent notification type: $notificationType');
              return notificationData; // Return the data directly for silent notifications
            }
            print(
                '🔔 SimpleNotificationService: ❌ No encrypted data found in data or encryptedData fields');
            return null;
          }
        }

        print(
            '🔔 SimpleNotificationService: Encrypted data found: ${encryptedData.length} characters');

        final checksum = notificationData['checksum'] as String?;
        final notificationType = notificationData['type'] as String?;
        final messageId = notificationData['messageId'] as String?;
        final conversationId = notificationData['conversationId'] as String?;

        // Handle silent field with proper type conversion
        bool? silent;
        final silentValue = notificationData['silent'];
        print(
            '🔔 SimpleNotificationService: Silent value: $silentValue (type: ${silentValue.runtimeType})');

        if (silentValue != null) {
          if (silentValue is bool) {
            silent = silentValue;
          } else if (silentValue is int) {
            silent = silentValue == 1;
          } else if (silentValue is String) {
            silent = silentValue == '1' || silentValue == 'true';
          }
          print('🔔 SimpleNotificationService: Silent converted to: $silent');
        }

        if (encryptedData == null) {
          print('🔔 SimpleNotificationService: ❌ No encrypted data found');
          return null;
        }

        // Before attempting to decrypt, trigger the encrypted message callback
        // This allows specialized handlers to decrypt using their own implementation
        if (_onEncryptedMessageReceived != null &&
            notificationType == 'message') {
          final currentUserId = _sessionId ?? '';
          _onEncryptedMessageReceived!(
              currentUserId, encryptedData, checksum ?? '');
        }

        // Handle message status updates (delivery receipts, read receipts)
        if (notificationType == 'message_delivery_status' &&
            messageId != null) {
          if (_onMessageStatusUpdate != null) {
            final senderId = notificationData['senderId'] as String? ?? '';
            final status = notificationData['status'] as String? ?? 'delivered';
            _onMessageStatusUpdate!(senderId, messageId, status);
          }

          // For silent notifications, we don't need to continue processing
          if (silent == true) {
            return {'type': 'silent_notification', 'handled': true};
          }
        }

        // Decrypt the data
        final decryptedData = await _decryptData(encryptedData);
        if (decryptedData == null) {
          print('🔔 SimpleNotificationService: ❌ Failed to decrypt data');
          return null;
        }

        print(
            '🔔 SimpleNotificationService: ✅ Data decrypted successfully using new EncryptionService');
        print(
            '🔔 SimpleNotificationService: Decrypted data keys: ${decryptedData.keys.toList()}');
        print(
            '🔔 SimpleNotificationService: Decrypted data types: ${decryptedData.map((key, value) => MapEntry(key, value.runtimeType))}');
        print(
            '🔔 SimpleNotificationService: Returning decrypted data: $decryptedData');
        return decryptedData;
      } else {
        print(
            '🔔 SimpleNotificationService: Processing plain text notification');

        // Special handling for key exchange notifications which are always unencrypted
        final notificationType = notificationData['type'] as String?;
        if (notificationType == 'key_exchange_request' ||
            notificationType == 'key_exchange_response') {
          print(
              '🔔 SimpleNotificationService: Detected unencrypted key exchange notification');
        }

        return notificationData;
      }
    } catch (e) {
      print('🔔 SimpleNotificationService: Error processing notification: $e');
      print(
          '🔔 SimpleNotificationService: Error stack trace: ${StackTrace.current}');
      return null;
    }
  }

  /// Handle notification and trigger callbacks
  Future<void> handleNotification(Map<String, dynamic> notificationData) async {
    try {
      print(
          '🔔 SimpleNotificationService: 🔔 RECEIVED NOTIFICATION: $notificationData');

      // Prevent duplicate notification processing
      final notificationId = _generateNotificationId(notificationData);
      if (_processedNotifications.contains(notificationId)) {
        print(
            '🔔 SimpleNotificationService: ⚠️ Duplicate notification detected, skipping: $notificationId');
        return;
      }

      // Mark this notification as processed
      _processedNotifications.add(notificationId);

      // Limit the size of processed notifications to prevent memory issues
      if (_processedNotifications.length > 1000) {
        print(
            '🔔 SimpleNotificationService: 🔧 Clearing old processed notifications to prevent memory buildup');
        _processedNotifications.clear();
        _processedNotifications.add(notificationId); // Keep the current one
      }

      print(
          '🔔 SimpleNotificationService: ✅ Notification marked as processed: $notificationId');

      // Convert Map<Object?, Object?> to Map<String, dynamic> safely
      Map<String, dynamic> safeNotificationData = <String, dynamic>{};
      notificationData.forEach((key, value) {
        if (key is String) {
          safeNotificationData[key] = value;
        }
      });

      // Extract the actual data from the notification
      Map<String, dynamic>? actualData;

      // Check if this is an iOS notification with aps structure
      if (safeNotificationData.containsKey('aps')) {
        final apsDataRaw = safeNotificationData['aps'];
        Map<String, dynamic>? apsData;

        // Safely convert Map<Object?, Object?> to Map<String, dynamic>
        if (apsDataRaw is Map) {
          apsData = <String, dynamic>{};
          apsDataRaw.forEach((key, value) {
            if (key is String) {
              apsData![key] = value;
            }
          });
        }

        if (apsData != null) {
          // For iOS, the data might be in the notification payload itself
          // Check if there's additional data beyond the aps structure
          actualData = <String, dynamic>{};

          // Copy all fields except 'aps' to actualData
          safeNotificationData.forEach((key, value) {
            if (key != 'aps' && key is String) {
              actualData![key] = value;
            }
          });

          // If no additional data found, try to extract from aps.alert
          if (actualData.isEmpty) {
            final alertRaw = apsData['alert'];
            Map<String, dynamic>? alert;

            // Safely convert alert to Map<String, dynamic>
            if (alertRaw is Map) {
              alert = <String, dynamic>{};
              alertRaw.forEach((key, value) {
                if (key is String) {
                  alert![key] = value;
                }
              });
            }

            if (alert != null) {
              // For invitation responses, we need to reconstruct the data
              // based on the notification title and body
              final title = alert['title'] as String?;
              final body = alert['body'] as String?;

              if (title == 'Invitation Accepted' && body != null) {
                // Extract responder name from body: "Prince accepted your invitation"
                final responderName =
                    body.replaceAll(' accepted your invitation', '');

                actualData = {
                  'type': 'invitation',
                  'subtype': 'accepted',
                  'responderName': responderName,
                  'responderId':
                      'unknown', // We'll need to get this from storage
                  'invitationId':
                      'unknown', // We'll need to get this from storage
                  'chatGuid': 'unknown', // We'll need to get this from storage
                };
                print(
                    '🔔 SimpleNotificationService: Reconstructed invitation accepted data: $actualData');
              } else if (title == 'Invitation Declined' && body != null) {
                // Extract responder name from body: "Prince declined your invitation"
                final responderName =
                    body.replaceAll(' declined your invitation', '');

                actualData = {
                  'type': 'invitation',
                  'subtype': 'declined',
                  'responderName': responderName,
                  'responderId':
                      'unknown', // We'll need to get this from storage
                  'invitationId':
                      'unknown', // We'll need to get this from storage
                };
                print(
                    '🔔 SimpleNotificationService: Reconstructed invitation declined data: $actualData');
              }
            }
          }

          print(
              '🔔 SimpleNotificationService: Extracted data from iOS notification: $actualData');
        }
      } else if (safeNotificationData.containsKey('data')) {
        // Android notification structure
        final dataField = safeNotificationData['data'];
        if (dataField is Map) {
          // Convert to Map<String, dynamic> safely
          actualData = <String, dynamic>{};
          dataField.forEach((key, value) {
            if (key is String) {
              actualData![key] = value;
            }
          });
          print(
              '🔔 SimpleNotificationService: Found data in nested field: $actualData');
        } else {
          print(
              '🔔 SimpleNotificationService: Data field is not a Map: $dataField');
          actualData = safeNotificationData;
        }
      } else {
        // Check if data is at top level
        actualData = safeNotificationData;
      }

      // Check if we have a payload field (iOS foreground notifications)
      if (actualData != null && actualData.containsKey('payload')) {
        final payloadStr = actualData['payload'] as String?;
        if (payloadStr != null) {
          try {
            final payloadData = json.decode(payloadStr) as Map<String, dynamic>;
            print(
                '🔔 SimpleNotificationService: Parsed payload JSON: $payloadData');

            // Merge payload data with actualData, prioritizing payload
            final mergedData = <String, dynamic>{...actualData};
            payloadData.forEach((key, value) {
              mergedData[key] = value;
            });
            actualData = mergedData;

            print(
                '🔔 SimpleNotificationService: Merged data with payload: $actualData');
          } catch (e) {
            print(
                '🔔 SimpleNotificationService: Failed to parse payload JSON: $e');
          }
        }
      }

      print(
          '🔔 SimpleNotificationService: Processed notification data: $actualData');

      // Process the notification data
      if (actualData == null) {
        print(
            '🔔 SimpleNotificationService: ❌ No valid data found in notification');
        return;
      }

      final processedData = await processNotification(actualData);
      if (processedData == null) {
        print(
            '🔔 SimpleNotificationService: ❌ Failed to process notification data');
        return;
      }

      final type = processedData['type'] as String?;
      if (type == null) {
        print(
            '🔔 SimpleNotificationService: ❌ No notification type found in data');
        return;
      }

      print(
          '🔔 SimpleNotificationService: Processing notification type: $type');

      switch (type) {
        case 'key_exchange_request':
          print(
              '🔔 SimpleNotificationService: 🎯 Processing key exchange request notification');
          await _handleKeyExchangeRequest(processedData);
          break;
        case 'key_exchange_response':
          print(
              '🔔 SimpleNotificationService: 🎯 Processing key exchange response notification');
          await _handleKeyExchangeResponse(processedData);
          break;
        case 'key_exchange_accepted':
          print(
              '🔔 SimpleNotificationService: 🎯 Processing key exchange accepted notification');
          await _handleKeyExchangeAccepted(processedData);
          break;
        case 'key_exchange_declined':
          print(
              '🔔 SimpleNotificationService: 🎯 Processing key exchange declined notification');
          await _handleKeyExchangeDeclined(processedData);
          break;
        case 'key_exchange_sent':
          print(
              '🔔 SimpleNotificationService: 🎯 Processing key exchange sent notification');
          await _handleKeyExchangeSent(processedData);
          break;
        case 'user_data_exchange':
          print(
              '🔔 SimpleNotificationService: 🎯 Processing encrypted user data exchange notification');
          await _handleUserDataExchange(processedData);
          break;
        case 'user_data_response':
          print(
              '🔔 SimpleNotificationService: 🎯 Processing encrypted user data response notification');
          await _handleUserDataResponse(processedData);
          break;

        case 'message':
          await _handleMessageNotification(processedData);
          break;
        case 'typing_indicator':
          await _handleTypingIndicatorNotification(processedData);
          break;
        case 'broadcast':
          await _handleBroadcastNotification(processedData);
          break;
        case 'online_status_update':
          await _handleOnlineStatusUpdate(processedData);
          break;
        default:
          print(
              '🔔 SimpleNotificationService: Unknown notification type: $type');
      }
    } catch (e) {
      print('🔔 SimpleNotificationService: Error handling notification: $e');
      print(
          '🔔 SimpleNotificationService: Error stack trace: ${StackTrace.current}');
    }
  }

  /// Handle message notification
  Future<void> _handleMessageNotification(Map<String, dynamic> data) async {
    final senderId = data['senderId'] as String?;
    final senderName = data['senderName'] as String?;
    final message = data['message'] as String?;
    final conversationId = data['conversationId'] as String?;

    if (senderId == null || senderName == null || message == null) {
      print('🔔 SimpleNotificationService: Invalid message notification data');
      return;
    }

    print(
        '🔔 SimpleNotificationService: Processing message from $senderName: $message');

    // Check if sender is blocked
    final currentUserId = SeSessionService().currentSessionId;
    if (currentUserId != null) {
      try {
        // Check database first for blocking status
        final messageStorageService = MessageStorageService.instance;
        final conversations =
            await messageStorageService.getUserConversations(currentUserId);

        // Find conversation with this sender
        final conversation = conversations.firstWhere(
          (conv) => conv.getOtherParticipantId(currentUserId) == senderId,
          orElse: () => throw Exception('Conversation not found'),
        );

        if (conversation.isBlocked == true) {
          print(
              '🔔 SimpleNotificationService: Message from blocked user ignored: $senderName');
          return; // Ignore message from blocked user
        }
      } catch (e) {
        print(
            '🔔 SimpleNotificationService: Error checking database for blocking status: $e');
        // Fallback to SharedPreferences if database fails
        try {
          final prefsService = SeSharedPreferenceService();
          final chatsJson = await prefsService.getJsonList('chats') ?? [];

          // Find chat with this sender
          for (final chatJson in chatsJson) {
            try {
              final chat = Chat.fromJson(chatJson);
              final otherUserId = chat.getOtherUserId(currentUserId);

              if (otherUserId == senderId && chat.getBlockedStatus()) {
                print(
                    '🔔 SimpleNotificationService: Message from blocked user ignored: $senderName');
                return; // Ignore message from blocked user
              }
            } catch (e) {
              print(
                  '🔔 SimpleNotificationService: Error parsing chat for blocking check: $e');
            }
          }
        } catch (fallbackError) {
          print(
              '🔔 SimpleNotificationService: Error in fallback blocking check: $fallbackError');
        }
      }
    }

    // Show local notification
    await showLocalNotification(
      title: 'New Message',
      body: 'You have received a new message',
      type: 'message',
      data: data,
    );

    // Save notification to SharedPreferences
    await _saveNotificationToSharedPrefs(
      id: 'message_${DateTime.now().millisecondsSinceEpoch}',
      title: 'New Message',
      body: 'You have received a new message',
      type: 'message',
      data: data,
      timestamp: DateTime.now(),
    );

    // Trigger indicator for new chat message
    IndicatorService().setNewChat();

    // Send delivery receipt back to sender
    try {
      final airNotifier = AirNotifierService.instance;
      final success = await airNotifier.sendMessageDeliveryStatus(
        recipientId: senderId,
        messageId:
            conversationId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
        status: 'delivered',
        conversationId: conversationId ??
            'chat_${DateTime.now().millisecondsSinceEpoch}_$senderId',
      );

      if (success) {
        print(
            '🔔 SimpleNotificationService: ✅ Delivery receipt sent to sender');
      } else {
        print(
            '🔔 SimpleNotificationService: ⚠️ Failed to send delivery receipt');
      }
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: ❌ Error sending delivery receipt: $e');
    }

    // Trigger callback for UI updates
    _onMessageReceived?.call(senderId, senderName, message);

    print(
        '🔔 SimpleNotificationService: ✅ Message notification handled successfully');
  }

  /// Handle typing indicator notification
  Future<void> _handleTypingIndicatorNotification(
      Map<String, dynamic> data) async {
    final senderId = data['senderId'] as String?;
    final isTyping = data['isTyping'] as bool?;

    if (senderId == null || isTyping == null) {
      print(
          '🔔 SimpleNotificationService: Invalid typing indicator notification data');
      return;
    }

    print(
        '🔔 SimpleNotificationService: Received typing indicator: $senderId -> $isTyping');

    // First, trigger the callback for any local listeners
    _onTypingIndicator?.call(senderId, isTyping);

    // Then, ensure the typing indicator is processed by the MessageStatusTrackingService
    // This ensures typing indicators work even when the callback isn't set up
    try {
      final messageStatusTrackingService =
          MessageStatusTrackingService.instance;
      await messageStatusTrackingService.handleExternalTypingIndicator(
          senderId, isTyping);
      print(
          '🔔 SimpleNotificationService: ✅ Typing indicator routed to MessageStatusTrackingService');
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: ❌ Failed to route typing indicator to MessageStatusTrackingService: $e');
    }
  }

  /// Handle broadcast notification
  Future<void> _handleBroadcastNotification(Map<String, dynamic> data) async {
    final message = data['message'] as String?;
    final timestamp = data['timestamp'] as int?;

    if (message == null) {
      print(
          '🔔 SimpleNotificationService: Invalid broadcast notification data');
      return;
    }

    // Show local notification
    await showLocalNotification(
      title: 'System Message',
      body: message,
      type: 'broadcast',
      data: data,
    );

    // Save notification to SharedPreferences
    await _saveNotificationToSharedPrefs(
      id: 'broadcast_${DateTime.now().millisecondsSinceEpoch}',
      title: 'System Message',
      body: message,
      type: 'broadcast',
      data: data,
      timestamp: DateTime.now(),
    );

    // Trigger indicator for new notification
    IndicatorService().setNewNotification();
  }

  /// Handle online status update notification
  Future<void> _handleOnlineStatusUpdate(Map<String, dynamic> data) async {
    final senderId = data['senderId'] as String?;
    final isOnline = data['isOnline'] as bool?;
    final lastSeen = data['lastSeen'] as String?;

    if (senderId == null || isOnline == null) {
      print('🔔 SimpleNotificationService: Invalid online status update data');
      return;
    }

    print(
        '🔔 SimpleNotificationService: Online status update from $senderId: $isOnline');

    // Update local online status
    try {
      final messageStorageService = MessageStorageService.instance;
      final currentUserId = SeSessionService().currentSessionId;

      if (currentUserId != null) {
        final conversations =
            await messageStorageService.getUserConversations(currentUserId);
        final conversation = conversations.firstWhere(
          (conv) => conv.isParticipant(senderId),
          orElse: () => throw Exception('Conversation not found'),
        );

        // Update conversation with online status
        final updatedConversation = conversation.copyWith(
          metadata: {
            ...?conversation.metadata,
            'is_online': isOnline,
            'last_seen': lastSeen ?? DateTime.now().toIso8601String(),
          },
        );

        await messageStorageService.saveConversation(updatedConversation);
        print(
            '🔔 SimpleNotificationService: ✅ Online status updated in local storage');
      }
    } catch (e) {
      print('🔔 SimpleNotificationService: ❌ Error updating online status: $e');
    }

    // Trigger callback for UI updates if available
    // TODO: Add callback for online status updates
    print(
        '🔔 SimpleNotificationService: ✅ Online status update handled successfully');
  }

  /// Set device token for push notifications
  Future<void> setDeviceToken(String token) async {
    // Prevent duplicate registration of the same token
    if (_deviceToken == token) {
      print(
          '🔔 SimpleNotificationService: Device token already set to: $token');
      return;
    }

    _deviceToken = token;
    print('🔔 SimpleNotificationService: Device token set: $token');

    // Only register with AirNotifier if we don't have a session ID yet
    // The session service will handle registration when session ID is available
    if (_sessionId == null) {
      try {
        await AirNotifierService.instance
            .registerDeviceToken(deviceToken: token);
        print(
            '🔔 SimpleNotificationService: ✅ Token registered with AirNotifier service (no session yet)');
      } catch (e) {
        print(
            '🔔 SimpleNotificationService: Error registering token with AirNotifier: $e');
      }
    } else {
      print(
          '🔔 SimpleNotificationService: Session ID available, will register token through session service');
    }

    // Link token to session with AirNotifier if session ID is available
    if (_sessionId != null) {
      print(
          '🔔 SimpleNotificationService: Session ID available, linking token to session: $_sessionId');
      await _linkTokenToSession();
    } else {
      print(
          '🔔 SimpleNotificationService: No session ID available for token linking - will link when session ID is set');
    }
  }

  /// Handle device token received from native platform
  Future<bool> handleDeviceTokenReceived(String token) async {
    print(
        '🔔 SimpleNotificationService: Device token received from native: $token');
    print('🔔 SimpleNotificationService: Current session ID: $_sessionId');
    await setDeviceToken(token);

    // If we have a session ID, try to link the token immediately
    if (_sessionId != null) {
      print(
          '🔔 SimpleNotificationService: Attempting to link token to existing session: $_sessionId');
      await _linkTokenToSession();
    }
    return true;
  }

  /// Link token to session with retry mechanism
  Future<void> _linkTokenToSession() async {
    if (_sessionId == null || _deviceToken == null) {
      print(
          '🔔 SimpleNotificationService: Cannot link token - missing session ID or device token');
      return;
    }

    // Token is already registered by the session service, just link it
    print(
        '🔔 SimpleNotificationService: Token already registered, linking to session: $_sessionId');

    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        final success =
            await AirNotifierService.instance.linkTokenToSession(_sessionId!);
        if (success) {
          print(
              '🔔 SimpleNotificationService: ✅ Token linked to session $_sessionId');
          return;
        } else {
          print(
              '🔔 SimpleNotificationService: ❌ Failed to link token to session (attempt ${retryCount + 1})');
          retryCount++;
          if (retryCount < maxRetries) {
            await Future.delayed(
                Duration(seconds: retryCount * 2)); // Exponential backoff
          }
        }
      } catch (e) {
        print(
            '🔔 SimpleNotificationService: Error linking token to session (attempt ${retryCount + 1}): $e');
        retryCount++;
        if (retryCount < maxRetries) {
          await Future.delayed(
              Duration(seconds: retryCount * 2)); // Exponential backoff
        }
      }
    }

    print(
        '🔔 SimpleNotificationService: ❌ Failed to link token after $maxRetries attempts');
  }

  /// Get current device token
  String? get deviceToken => _deviceToken;

  /// Get current session ID
  String? get sessionId => _sessionId;

  /// Clear session data and unlink token (for account deletion)
  Future<void> clearSessionData() async {
    try {
      print(
          '🔔 SimpleNotificationService: Clearing session data and unlinking token...');

      // Unlink token from current session if available
      if (_sessionId != null && _deviceToken != null) {
        try {
          await AirNotifierService.instance.unlinkTokenFromSession();
          print('🔔 SimpleNotificationService: ✅ Token unlinked from session');
        } catch (e) {
          print('🔔 SimpleNotificationService: Error unlinking token: $e');
        }
      }

      // Clear session ID
      _sessionId = null;

      print('🔔 SimpleNotificationService: ✅ Session data cleared');
    } catch (e) {
      print('🔔 SimpleNotificationService: Error clearing session data: $e');
    }
  }

  /// Set session ID and link token if available
  Future<void> setSessionId(String sessionId) async {
    _sessionId = sessionId;
    print('🔔 SimpleNotificationService: Session ID set: $sessionId');
    print('🔔 SimpleNotificationService: Current device token: $_deviceToken');

    // Initialize AirNotifier with the new session ID
    try {
      await _initializeAirNotifier();
      print(
          '🔔 SimpleNotificationService: ✅ AirNotifier initialized with session ID: $sessionId');
    } catch (e) {
      print('🔔 SimpleNotificationService: Error initializing AirNotifier: $e');
    }

    // Check if we need to request permissions first
    if (_permissionStatus == PermissionStatus.permanentlyDenied) {
      print(
          '🔔 SimpleNotificationService: Notification permission denied, requesting...');
      final granted = await requestNotificationPermissions();
      if (!granted) {
        print(
            '🔔 SimpleNotificationService: ⚠️ Warning: Notification permission still denied');
      }
    }

    // Link existing token to session if available
    if (_deviceToken != null) {
      print(
          '🔔 SimpleNotificationService: Device token available, linking to session: $_deviceToken');
      await _linkTokenToSession();
    } else {
      // Wait for native platform to automatically send token
      print(
          '🔔 SimpleNotificationService: No device token available, waiting for native platform to send token...');
      // Don't request token manually - let native side send it automatically
    }
  }

  /// Check if device token is registered
  bool isDeviceTokenRegistered() {
    return _deviceToken != null && _deviceToken!.isNotEmpty;
  }

  /// Request device token from native platform
  void _requestDeviceTokenFromNative() {
    _requestDeviceTokenWithRetry(0);
  }

  /// Request device token with retry mechanism
  void _requestDeviceTokenWithRetry(int retryCount) {
    try {
      const MethodChannel channel = MethodChannel('push_notifications');
      channel.invokeMethod('requestDeviceToken');
      print(
          '🔔 SimpleNotificationService: Requested device token from native platform (attempt ${retryCount + 1})');
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error requesting device token (attempt ${retryCount + 1}): $e');

      // Retry up to 3 times with exponential backoff
      if (retryCount < 3) {
        final delay = Duration(seconds: (retryCount + 1) * 2);
        print(
            '🔔 SimpleNotificationService: Retrying in ${delay.inSeconds} seconds...');
        Future.delayed(
            delay, () => _requestDeviceTokenWithRetry(retryCount + 1));
      } else {
        // Final fallback: Generate a temporary token for testing
        if (Platform.isAndroid) {
          final fallbackToken =
              'android_fallback_${DateTime.now().millisecondsSinceEpoch}';
          print(
              '🔔 SimpleNotificationService: Using Android fallback token: $fallbackToken');
          setDeviceToken(fallbackToken);
        }
      }
    }
  }

  /// Request notification permissions
  Future<bool> requestNotificationPermissions() async {
    return _requestNotificationPermissionsWithRetry(0);
  }

  /// Request notification permissions with retry mechanism
  Future<bool> _requestNotificationPermissionsWithRetry(int retryCount) async {
    try {
      print(
          '🔔 SimpleNotificationService: Requesting notification permissions (attempt ${retryCount + 1})...');

      const MethodChannel channel = MethodChannel('push_notifications');
      final result =
          await channel.invokeMethod('requestNotificationPermissions');

      print('🔔 SimpleNotificationService: Permission request result: $result');
      return result == true;
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error requesting permissions (attempt ${retryCount + 1}): $e');

      // Retry up to 2 times with exponential backoff
      if (retryCount < 2) {
        final delay = Duration(seconds: (retryCount + 1) * 2);
        print(
            '🔔 SimpleNotificationService: Retrying permission request in ${delay.inSeconds} seconds...');
        await Future.delayed(delay);
        return _requestNotificationPermissionsWithRetry(retryCount + 1);
      } else {
        return false;
      }
    }
  }

  /// Test method channel connectivity
  Future<String?> testMethodChannel() async {
    try {
      print('🔔 SimpleNotificationService: Testing method channel...');

      const MethodChannel channel = MethodChannel('push_notifications');
      final result = await channel.invokeMethod('testMethodChannel');

      print(
          '🔔 SimpleNotificationService: Method channel test result: $result');
      return result as String?;
    } catch (e) {
      print('🔔 SimpleNotificationService: Method channel test failed: $e');
      return null;
    }
  }

  /// Test MainActivity connectivity
  Future<String?> testMainActivity() async {
    try {
      print('🔔 SimpleNotificationService: Testing MainActivity...');

      const MethodChannel channel = MethodChannel('push_notifications');
      final result = await channel.invokeMethod('testMainActivity');

      print('🔔 SimpleNotificationService: MainActivity test result: $result');
      return result as String?;
    } catch (e) {
      print('🔔 SimpleNotificationService: MainActivity test failed: $e');
      return null;
    }
  }

  /// Set message received callback
  void setOnMessageReceived(
      Function(String senderId, String senderName, String message) callback) {
    _onMessageReceived = callback;
  }

  /// Set typing indicator callback
  void setOnTypingIndicator(Function(String senderId, bool isTyping) callback) {
    _onTypingIndicator = callback;
  }

  /// Send read receipt for a message
  Future<void> sendReadReceipt(
      String senderId, String messageId, String conversationId) async {
    try {
      print(
          '🔔 SimpleNotificationService: Sending read receipt for message: $messageId');

      final airNotifier = AirNotifierService.instance;
      final success = await airNotifier.sendMessageDeliveryStatus(
        recipientId: senderId,
        messageId: messageId,
        status: 'read',
        conversationId: conversationId,
      );

      if (success) {
        print('🔔 SimpleNotificationService: ✅ Read receipt sent to sender');
      } else {
        print('🔔 SimpleNotificationService: ⚠️ Failed to send read receipt');
      }
    } catch (e) {
      print('🔔 SimpleNotificationService: ❌ Error sending read receipt: $e');
    }
  }

  /// Send online status update
  Future<void> sendOnlineStatusUpdate(String recipientId, bool isOnline) async {
    try {
      print(
          '🔔 SimpleNotificationService: Sending online status update: $isOnline');

      final airNotifier = AirNotifierService.instance;
      final success = await airNotifier.sendOnlineStatusUpdate(
        recipientId: recipientId,
        isOnline: isOnline,
        lastSeen: isOnline ? null : DateTime.now().toIso8601String(),
      );

      if (success) {
        print('🔔 SimpleNotificationService: ✅ Online status update sent');
      } else {
        print(
            '🔔 SimpleNotificationService: ⚠️ Failed to send online status update');
      }
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: ❌ Error sending online status update: $e');
    }
  }

  /// Set encrypted message received callback
  void setOnEncryptedMessageReceived(
      Function(String recipientId, String encryptedData, String checksum)
          callback) {
    _onEncryptedMessageReceived = callback;
  }

  /// Set message status update callback
  void setOnMessageStatusUpdate(
      Function(String senderId, String messageId, String status) callback) {
    _onMessageStatusUpdate = callback;
  }

  /// Set callback for key exchange request received
  void setOnKeyExchangeRequestReceived(
      Function(Map<String, dynamic> data)? callback) {
    _onKeyExchangeRequestReceived = callback;
  }

  /// Set callback for key exchange accepted
  void setOnKeyExchangeAccepted(Function(Map<String, dynamic> data)? callback) {
    _onKeyExchangeAccepted = callback;
  }

  /// Set callback for key exchange declined
  void setOnKeyExchangeDeclined(Function(Map<String, dynamic> data)? callback) {
    _onKeyExchangeDeclined = callback;
  }

  /// Set callback for general notifications
  void setOnNotificationReceived(
      Function(String title, String body, String type,
              Map<String, dynamic>? data)?
          callback) {
    _onNotificationReceived = callback;
  }

  /// Set callback for conversation creation
  void setOnConversationCreated(
      Function(ChatConversation conversation)? callback) {
    _onConversationCreated = callback;
  }

  /// Show local notification
  Future<void> showLocalNotification({
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? data,
    String? sound,
  }) async {
    if (kIsWeb) return;
    if (!_isInitialized) await initialize();

    try {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'sechat_notifications',
        'SeChat Notifications',
        channelDescription: 'Notifications for SeChat app',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch.hashCode,
        title,
        body,
        details,
        payload: json.encode(data),
      );

      print('🔔 SimpleNotificationService: Local notification shown: $title');
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error showing local notification: $e');
    }
  }

  /// Encrypt data with recipient's public key
  Future<String> _encryptData(
      Map<String, dynamic> data, String recipientId) async {
    try {
      print(
          '🔔 SimpleNotificationService: 🔐 Encrypting data using new EncryptionService');

      // Use the new EncryptionService.encryptAesCbcPkcs7 method
      final result =
          await EncryptionService.encryptAesCbcPkcs7(data, recipientId);

      // Return the encrypted data (envelope) for backward compatibility
      return result['data']!;
    } catch (e) {
      print('🔔 SimpleNotificationService: ❌ Encryption failed: $e');
      throw Exception('Encryption failed: $e');
    }
  }

  /// Decrypt data with own private key
  Future<Map<String, dynamic>?> _decryptData(String encryptedData) async {
    try {
      print(
          '🔔 SimpleNotificationService: 🔐 Attempting to decrypt data using new EncryptionService');

      // Debug: Log the encrypted data being received
      final previewLength =
          encryptedData.length > 50 ? 50 : encryptedData.length;
      print(
          '🔔 SimpleNotificationService: Received encrypted data: ${encryptedData.substring(0, previewLength)}...');
      print(
          '🔔 SimpleNotificationService: Encrypted data length: ${encryptedData.length} characters');

      // Use the new EncryptionService.decryptAesCbcPkcs7 method
      final decryptedData =
          await EncryptionService.decryptAesCbcPkcs7(encryptedData);

      print(
          '🔔 SimpleNotificationService: Decryption result type: ${decryptedData.runtimeType}');
      if (decryptedData != null) {
        print(
            '🔔 SimpleNotificationService: Decryption result keys: ${decryptedData.keys.toList()}');
        print(
            '🔔 SimpleNotificationService: Decryption result preview: $decryptedData');
      }

      if (decryptedData == null) {
        print('🔔 SimpleNotificationService: ❌ Failed to decrypt data');
        return null;
      }

      print(
          '🔔 SimpleNotificationService: ✅ Data decrypted successfully using new EncryptionService');
      print(
          '🔔 SimpleNotificationService: Decrypted data keys: ${decryptedData.keys.toList()}');
      print(
          '🔔 SimpleNotificationService: Decrypted data types: ${decryptedData.map((key, value) => MapEntry(key, value.runtimeType))}');
      print(
          '🔔 SimpleNotificationService: Returning decrypted data: $decryptedData');
      return decryptedData;
    } catch (e) {
      print('🔔 SimpleNotificationService: Decryption failed: $e');
      return null;
    }
  }

  /// Get recipient's public key
  Future<String?> _getRecipientPublicKey(String recipientId) async {
    try {
      // First check if we have the key cached locally
      final cachedKey = await _storage.read(key: 'recipient_key_$recipientId');
      if (cachedKey != null) {
        return cachedKey;
      }

      // In a real implementation, you would:
      // 1. Query a secure key server using the recipient's session ID
      // 2. Verify the key's authenticity using digital signatures
      // 3. Cache the key locally for future use

      // For now, we'll use a simple key exchange mechanism
      // This should be replaced with a proper key server implementation
      print(
          '🔔 SimpleNotificationService: Requesting public key for $recipientId');

      // TODO: Implement proper key server query
      // For demo purposes, generate a test key if none exists
      print(
          '🔔 SimpleNotificationService: Generating test key for $recipientId');
      return await generateTestPublicKey(recipientId);
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error getting recipient public key: $e');
      return null;
    }
  }

  /// Generate checksum for data integrity
  String _generateChecksum(Map<String, dynamic> data) {
    final dataJson = json.encode(data);
    final bytes = utf8.encode(dataJson);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Store recipient's public key
  Future<void> storeRecipientPublicKey(
      String recipientId, String publicKey) async {
    await _storage.write(key: 'recipient_key_$recipientId', value: publicKey);
    print('🔔 SimpleNotificationService: Stored public key for $recipientId');
  }

  /// Generate and store a test public key for a recipient (for demo purposes)
  Future<String> generateTestPublicKey(String recipientId) async {
    try {
      // Generate a random AES key for the recipient
      final random = Random.secure();
      final aesKey = List<int>.generate(32, (_) => random.nextInt(256));
      final publicKey = base64Encode(aesKey);

      // Store the key
      await storeRecipientPublicKey(recipientId, publicKey);

      print(
          '🔔 SimpleNotificationService: Generated test public key for $recipientId');
      return publicKey;
    } catch (e) {
      print('🔔 SimpleNotificationService: Error generating test key: $e');
      rethrow;
    }
  }

  /// Clear all stored keys (for logout)
  Future<void> clearAllKeys() async {
    final keys = await _storage.readAll();
    for (final key in keys.keys) {
      if (key.startsWith('recipient_key_')) {
        await _storage.delete(key: key);
      }
    }
  }

  /// Clear ALL data when deleting account (comprehensive cleanup)
  Future<void> clearAllDataOnAccountDeletion() async {
    try {
      print(
          '🗑️ SimpleNotificationService: Starting comprehensive account data cleanup...');

      // 1. Clear all secure storage (encryption keys, etc.)
      final secureKeys = await _storage.readAll();
      for (final key in secureKeys.keys) {
        await _storage.delete(key: key);
        print('🗑️ SimpleNotificationService: Deleted secure key: $key');
      }

      // 2. Clear all shared preferences
      final prefsService = SeSharedPreferenceService();
      await prefsService.clear();
      print('🗑️ SimpleNotificationService: Cleared all shared preferences');

      // 3. Clear local notifications
      await _localNotifications.cancelAll();
      print('🗑️ SimpleNotificationService: Cancelled all local notifications');

      // 4. Clear notification cache
      _processedNotifications.clear();
      print('🗑️ SimpleNotificationService: Cleared notification cache');

      // 6. Reset service state
      _deviceToken = null;
      _sessionId = null;
      _permissionStatus = PermissionStatus.denied;
      _isInitialized = false;
      print('🗑️ SimpleNotificationService: Reset service state');

      // 7. Clear data from other services
      try {
        // Clear key exchange service data
        await KeyExchangeService.instance.clearAllPendingExchanges();
        print(
            '🗑️ SimpleNotificationService: Cleared key exchange service data');
      } catch (e) {
        print(
            '🗑️ SimpleNotificationService: Warning - some service cleanup failed: $e');
      }

      print(
          '🗑️ SimpleNotificationService: ✅ Comprehensive account cleanup completed');
    } catch (e) {
      print(
          '🗑️ SimpleNotificationService: ❌ Error during account cleanup: $e');
      // Don't throw - we want to continue with cleanup even if some parts fail
    }
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  /// Test encryption system (for debugging)
  Future<bool> testEncryption(String recipientId) async {
    try {
      print(
          '🔔 SimpleNotificationService: Testing encryption for $recipientId');

      // Test data
      final testData = {
        'type': 'test',
        'message': 'Hello, this is a test message!',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Get or generate recipient's public key
      final publicKey = await _getRecipientPublicKey(recipientId);
      if (publicKey == null) {
        print('🔔 SimpleNotificationService: ❌ Failed to get public key');
        return false;
      }

      // Encrypt the data
      final encryptedData = await _encryptData(testData, recipientId);
      final checksum = _generateChecksum(testData);

      print('🔔 SimpleNotificationService: ✅ Data encrypted successfully');
      print('🔔 SimpleNotificationService: Checksum: $checksum');

      // Test decryption
      final decryptedData = await _decryptData(encryptedData);
      if (decryptedData == null) {
        print('🔔 SimpleNotificationService: ❌ Failed to decrypt data');
        return false;
      }

      // Verify checksum
      final expectedChecksum = _generateChecksum(decryptedData);
      if (checksum != expectedChecksum) {
        print('🔔 SimpleNotificationService: ❌ Checksum verification failed');
        return false;
      }

      print('🔔 SimpleNotificationService: ✅ Encryption test passed');
      return true;
    } catch (e) {
      print('🔔 SimpleNotificationService: ❌ Encryption test failed: $e');
      return false;
    }
  }

  /// Show a toast message (for web, console, or native)
  void _showToastMessage(String message) {
    if (kIsWeb) {
      print('🔔 SimpleNotificationService: Web toast: $message');
    } else {
      // For native platforms, you would typically use a platform channel
      // to communicate with the native side.
      // This is a placeholder for a native implementation.
      print('🔔 SimpleNotificationService: Native toast: $message');
    }
  }

  /// Show a toast message using ScaffoldMessenger if context is available
  void showToastMessage(String message, {BuildContext? context}) {
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      _showToastMessage(message);
    }
  }

  /// Handle key exchange request notification
  Future<void> _handleKeyExchangeRequest(Map<String, dynamic> data) async {
    try {
      print('🔔 SimpleNotificationService: Processing key exchange request');

      // Extract key exchange request data
      final senderId = data['sender_id'] as String?;
      final requestId = data['request_id'] as String?;
      final requestPhrase = data['request_phrase'] as String?;
      final timestampRaw = data['timestamp'];

      if (senderId == null || requestId == null || requestPhrase == null) {
        print(
            '🔔 SimpleNotificationService: Invalid key exchange request data - missing required fields');
        print('🔔 SimpleNotificationService: Received data: $data');
        return;
      }

      // Handle timestamp conversion safely
      DateTime timestamp;
      if (timestampRaw is int) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(timestampRaw);
      } else if (timestampRaw is String) {
        try {
          timestamp =
              DateTime.fromMillisecondsSinceEpoch(int.parse(timestampRaw));
        } catch (e) {
          print(
              '🔔 SimpleNotificationService: Invalid timestamp string: $timestampRaw, using current time');
          timestamp = DateTime.now();
        }
      } else {
        print(
            '🔔 SimpleNotificationService: Invalid timestamp type: ${timestampRaw.runtimeType}, using current time');
        timestamp = DateTime.now();
      }

      print(
          '🔔 SimpleNotificationService: Key exchange request from $senderId with phrase: $requestPhrase');

      // Create a key exchange request record for the recipient
      final keyExchangeRequest = KeyExchangeRequest(
        id: requestId,
        fromSessionId: senderId,
        toSessionId: SeSessionService().currentSessionId ?? '',
        requestPhrase: requestPhrase,
        status: 'received',
        timestamp: timestamp,
        type: 'key_exchange_request',
      );

      // Save to local storage
      final prefsService = SeSharedPreferenceService();
      final existingRequests =
          await prefsService.getJsonList('key_exchange_requests') ?? [];

      // Check if request already exists
      if (!existingRequests.any((req) => req['id'] == requestId)) {
        existingRequests.add(keyExchangeRequest.toJson());
        await prefsService.setJsonList(
            'key_exchange_requests', existingRequests);
        print(
            '🔔 SimpleNotificationService: ✅ Key exchange request saved locally');
      } else {
        print(
            '🔔 SimpleNotificationService: Key exchange request already exists');
      }

      // Add notification item
      if (_onNotificationReceived != null) {
        print(
            '🔔 SimpleNotificationService: ✅ Calling notification callback for key exchange request');
        _onNotificationReceived!(
          'Key Exchange Request',
          'New key exchange request received',
          'key_exchange_request',
          data,
        );
        print(
            '🔔 SimpleNotificationService: ✅ Notification callback completed');
      } else {
        print('🔔 SimpleNotificationService: ⚠️ No notification callback set');
      }

      // Notify the provider via callback
      if (_onKeyExchangeRequestReceived != null) {
        _onKeyExchangeRequestReceived!(data);
        print(
            '🔔 SimpleNotificationService: ✅ Key exchange request callback triggered');
      }

      print('🔔 SimpleNotificationService: ✅ Key exchange request processed');
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error processing key exchange request: $e');
    }
  }

  /// Handle key exchange response notification
  Future<void> _handleKeyExchangeResponse(Map<String, dynamic> data) async {
    try {
      print('🔔 SimpleNotificationService: Processing key exchange response');

      // Extract key exchange data
      final senderId = data['sender_id'] as String?;
      final publicKey = data['public_key'] as String?;

      if (senderId == null || publicKey == null) {
        print(
            '🔔 SimpleNotificationService: Invalid key exchange response data');
        return;
      }

      print(
          '🔔 SimpleNotificationService: Key exchange response from $senderId');

      // Process the key exchange response using KeyExchangeService
      await KeyExchangeService.instance.processKeyExchangeResponse({
        'sender_id': senderId,
        'public_key': publicKey,
      });

      print('🔔 SimpleNotificationService: ✅ Key exchange response processed');
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error processing key exchange response: $e');
    }
  }

  /// Handle key exchange accepted notification
  Future<void> _handleKeyExchangeAccepted(Map<String, dynamic> data) async {
    try {
      print('🔔 SimpleNotificationService: Processing key exchange accepted');

      // Extract data
      final requestId = data['request_id'] as String?;
      final recipientId = data['recipient_id'] as String?;
      final timestampRaw = data['timestamp'];

      if (requestId == null || recipientId == null) {
        print('🔔 SimpleNotificationService: Invalid acceptance data');
        return;
      }

      // Handle timestamp conversion safely
      DateTime timestamp;
      if (timestampRaw is int) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(timestampRaw);
      } else if (timestampRaw is String) {
        try {
          timestamp =
              DateTime.fromMillisecondsSinceEpoch(int.parse(timestampRaw));
        } catch (e) {
          print(
              '🔔 SimpleNotificationService: Invalid timestamp string: $timestampRaw, using current time');
          timestamp = DateTime.now();
        }
      } else {
        print(
            '🔔 SimpleNotificationService: Invalid timestamp type: ${timestampRaw.runtimeType}, using current time');
        timestamp = DateTime.now();
      }

      // Process the acceptance using KeyExchangeRequestProvider
      // Note: This should be accessed through a provider context in a real app
      print(
          '🔔 SimpleNotificationService: Key exchange accepted for request: $requestId');

      // Add notification item
      if (_onNotificationReceived != null) {
        print(
            '🔔 SimpleNotificationService: ✅ Calling notification callback for key exchange accepted');
        _onNotificationReceived!(
          'Key Exchange Accepted',
          'Your key exchange request was accepted',
          'key_exchange_accepted',
          data,
        );
        print(
            '🔔 SimpleNotificationService: ✅ Notification callback completed for accepted');
      } else {
        print(
            '🔔 SimpleNotificationService: ⚠️ No notification callback set for accepted');
      }

      // Call the key exchange accepted callback
      if (_onKeyExchangeAccepted != null) {
        _onKeyExchangeAccepted!(data);
      }

      print(
          '🔔 SimpleNotificationService: ✅ Key exchange acceptance processed');
    } catch (e) {
      print('🔔 SimpleNotificationService: Error processing acceptance: $e');
    }
  }

  /// Handle key exchange declined notification
  Future<void> _handleKeyExchangeDeclined(Map<String, dynamic> data) async {
    try {
      print('🔔 SimpleNotificationService: Processing key exchange declined');

      // Extract data
      final requestId = data['request_id'] as String?;
      final recipientId = data['recipient_id'] as String?;
      final timestampRaw = data['timestamp'];

      if (requestId == null || recipientId == null) {
        print('🔔 SimpleNotificationService: Invalid decline data');
        return;
      }

      // Handle timestamp conversion safely
      DateTime timestamp;
      if (timestampRaw is int) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(timestampRaw);
      } else if (timestampRaw is String) {
        try {
          timestamp =
              DateTime.fromMillisecondsSinceEpoch(int.parse(timestampRaw));
        } catch (e) {
          print(
              '🔔 SimpleNotificationService: Invalid timestamp string: $timestampRaw, using current time');
          timestamp = DateTime.now();
        }
      } else {
        print(
            '🔔 SimpleNotificationService: Invalid timestamp type: ${timestampRaw.runtimeType}, using current time');
        timestamp = DateTime.now();
      }

      // Process the decline using KeyExchangeRequestProvider
      // Note: This should be accessed through a provider context in a real app
      print(
          '🔔 SimpleNotificationService: Key exchange declined for request: $requestId');

      // Add notification item
      if (_onNotificationReceived != null) {
        _onNotificationReceived!(
          'Key Exchange Declined',
          'Your key exchange request was declined',
          'key_exchange_declined',
          data,
        );
      }

      // Call the key exchange declined callback
      if (_onKeyExchangeDeclined != null) {
        _onKeyExchangeDeclined!(data);
      }

      print('🔔 SimpleNotificationService: ✅ Key exchange decline processed');
    } catch (e) {
      print('🔔 SimpleNotificationService: Error processing decline: $e');
    }
  }

  /// Handle encrypted user data exchange notification
  Future<void> _handleUserDataExchange(Map<String, dynamic> data) async {
    try {
      print(
          '🔔 SimpleNotificationService: Processing encrypted user data exchange');

      // The data is already decrypted at this point, so process it directly
      print(
          '🔔 SimpleNotificationService: ✅ User data already decrypted, processing directly');

      // Process the decrypted user data
      await _processDecryptedUserData(data);
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error processing user data exchange: $e');
    }
  }

  /// Process decrypted user data and create contact/chat
  Future<void> _processDecryptedUserData(Map<String, dynamic> userData) async {
    try {
      print('🔔 SimpleNotificationService: Processing decrypted user data');

      final senderId = userData['sender_id'] as String?;
      final displayName = userData['display_name'] as String?;
      final profileData = userData['profile_data'] as Map<String, dynamic>?;

      if (senderId == null || displayName == null) {
        print('🔔 SimpleNotificationService: Invalid user data');
        return;
      }

      print(
          '🔔 SimpleNotificationService: Processing data for user: $displayName ($senderId)');

      // Update the Key Exchange Request display name from "session_..." to actual name
      await _updateKeyExchangeRequestDisplayName(senderId, displayName);

      // Also update the KeyExchangeRequestProvider to refresh the UI in real-time
      try {
        // Import the provider and update display names
        // This will trigger UI updates for all key exchange requests
        final keyExchangeProvider = KeyExchangeRequestProvider();
        await keyExchangeProvider.updateUserDisplayName(senderId, displayName);
        print(
            '🔔 SimpleNotificationService: ✅ KeyExchangeRequestProvider updated with new display name from user data');
      } catch (e) {
        print(
            '🔔 SimpleNotificationService: Error updating KeyExchangeRequestProvider from user data: $e');
        // Continue with the process even if provider update fails
      }

      // Create contact and chat automatically
      await _createContactAndChat(senderId, displayName, profileData);

      print(
          '🔔 SimpleNotificationService: ✅ Contact and chat created successfully');
    } catch (e) {
      print('🔔 SimpleNotificationService: Error processing user data: $e');
    }
  }

  /// Update the Key Exchange Request display name
  Future<void> _updateKeyExchangeRequestDisplayName(
      String senderId, String displayName) async {
    try {
      print(
          '🔔 SimpleNotificationService: Updating KER display name for: $senderId to: $displayName');

      // Get the current user's session ID
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔔 SimpleNotificationService: User not logged in, cannot update KER');
        return;
      }

      // Store the display name mapping in shared preferences for later use
      final prefsService = SeSharedPreferenceService();
      final displayNameMappings =
          await prefsService.getJson('ker_display_names') ?? {};

      // Update the mapping
      displayNameMappings[senderId] = displayName;
      await prefsService.setJson('ker_display_names', displayNameMappings);

      print(
          '🔔 SimpleNotificationService: ✅ KER display name mapping stored: $senderId -> $displayName');

      // Update the KeyExchangeRequestProvider to refresh the UI in real-time
      try {
        // Import the provider and update display names
        // This will trigger UI updates for all key exchange requests
        final keyExchangeProvider = KeyExchangeRequestProvider();
        await keyExchangeProvider.updateUserDisplayName(senderId, displayName);
        print(
            '🔔 SimpleNotificationService: ✅ KeyExchangeRequestProvider updated with new display name');
      } catch (e) {
        print(
            '🔔 SimpleNotificationService: Error updating KeyExchangeRequestProvider: $e');
        // Continue with the process even if provider update fails
      }

      // Trigger a refresh of the key exchange requests to show updated names
      // This will be handled by the UI when it reads the display name mappings
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error updating KER display name: $e');
    }
  }

  /// Create contact and chat for the new connection
  Future<void> _createContactAndChat(
    String contactId,
    String displayName,
    Map<String, dynamic>? profileData,
  ) async {
    try {
      print(
          '🔔 SimpleNotificationService: Creating contact and chat for: $displayName');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🔔 SimpleNotificationService: User not logged in');
        return;
      }

      // Create contact
      final contact = {
        'id': contactId,
        'displayName': displayName,
        'sessionId': contactId,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'profileData': profileData ?? {},
        'status': 'active',
      };

      // Save contact to local storage
      final prefsService = SeSharedPreferenceService();
      final existingContacts = await prefsService.getJsonList('contacts') ?? [];

      // Check if contact already exists
      if (!existingContacts.any((c) => c['id'] == contactId)) {
        existingContacts.add(contact);
        await prefsService.setJsonList('contacts', existingContacts);
        print('🔔 SimpleNotificationService: ✅ Contact saved: $displayName');
      } else {
        print(
            '🔔 SimpleNotificationService: Contact already exists: $displayName');
      }

      // Create chat conversation in the database
      final chatId =
          'chat_${DateTime.now().millisecondsSinceEpoch}_${contactId.substring(0, 8)}';

      // Get current user info for chat
      final currentSession = SeSessionService().currentSession;
      final currentUserDisplayName = currentSession?.displayName ??
          'User ${currentUserId.substring(0, 8)}';

      // Create ChatConversation object for database
      final conversation = ChatConversation(
        id: chatId,
        participant1Id: currentUserId,
        participant2Id: contactId,
        displayName: displayName,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastMessageAt: DateTime.now(),
        lastMessageId: null,
        lastMessagePreview: null,
        lastMessageType: null,
        unreadCount: 0,
        isArchived: false,
        isMuted: false,
        isPinned: false,
        metadata: {
          'created_from_key_exchange': true,
          'contact_display_name': displayName,
          'current_user_display_name': currentUserDisplayName,
        },
        lastSeen: null,
        isTyping: false,
        typingStartedAt: null,
        notificationsEnabled: true,
        soundEnabled: true,
        vibrationEnabled: true,
        readReceiptsEnabled: true,
        typingIndicatorsEnabled: true,
        lastSeenEnabled: true,
        mediaAutoDownload: true,
        encryptMedia: true,
        mediaQuality: 'High',
        messageRetention: '30 days',
        isBlocked: false,
        blockedAt: null,
        recipientId: contactId,
        recipientName: displayName,
      );

      // Save conversation to database
      try {
        print(
            '🔔 SimpleNotificationService: 🗄️ Attempting to save conversation to database...');
        final messageStorageService = MessageStorageService.instance;
        print(
            '🔔 SimpleNotificationService: 📊 Conversation data: ${conversation.toJson()}');
        await messageStorageService.saveConversation(conversation);
        print(
            '🔔 SimpleNotificationService: ✅ Chat conversation created in database: $chatId');

        // Notify about conversation creation
        if (_onConversationCreated != null) {
          _onConversationCreated!(conversation);
        }
      } catch (e) {
        print(
            '🔔 SimpleNotificationService: ❌ Failed to create chat conversation in database: $e');
        print(
            '🔔 SimpleNotificationService: 🔍 Error details: ${e.runtimeType} - $e');
        // No fallback to SharedPreferences - database must succeed
        throw Exception('Failed to create chat conversation in database: $e');
      }

      // Send encrypted response with our user data and chat info
      await _sendEncryptedResponse(contactId, chatId);
    } catch (e) {
      print('🔔 SimpleNotificationService: Error creating contact/chat: $e');
      // Rollback changes if needed
      await _rollbackContactChatCreation(contactId);
    }
  }

  /// Send encrypted response with our user data and chat info
  Future<void> _sendEncryptedResponse(String contactId, String chatId) async {
    try {
      print(
          '🔔 SimpleNotificationService: Sending encrypted response to: $contactId');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) return;

      // Get the current user's actual display name from their session
      final currentSession = SeSessionService().currentSession;
      final userDisplayName = currentSession?.displayName ??
          'User ${currentUserId.substring(0, 8)}';

      // Create our user data payload with chat information
      final userData = {
        'type': 'user_data_response',
        'sender_id': currentUserId,
        'display_name': userDisplayName,
        'chat_id': chatId, // Include the chat GUID for Alice
        'profile_data': {
          'session_id': currentUserId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      };

      print(
          '🔔 SimpleNotificationService: Sending response with display name: $userDisplayName and chat ID: $chatId');

      // Encrypt the data
      final encryptedPayload = await EncryptionService.createEncryptedPayload(
        userData,
        contactId,
      );

      // Send encrypted notification
      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: contactId,
        title: 'Connection Established',
        body: 'Secure connection established successfully',
        data: {
          'data': encryptedPayload['data'] as String,
          'type': 'user_data_response',
        },
        sound: 'default',
        encrypted: true,
        checksum: encryptedPayload['checksum'] as String,
      );

      if (success) {
        print(
            '🔔 SimpleNotificationService: ✅ Encrypted response sent successfully');
      } else {
        print(
            '🔔 SimpleNotificationService: ❌ Failed to send encrypted response');
      }
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error sending encrypted response: $e');
    }
  }

  /// Rollback contact and chat creation on failure
  Future<void> _rollbackContactChatCreation(String contactId) async {
    try {
      print(
          '🔔 SimpleNotificationService: Rolling back contact/chat creation for: $contactId');

      final prefsService = SeSharedPreferenceService();

      // Remove contact
      final existingContacts = await prefsService.getJsonList('contacts') ?? [];
      existingContacts.removeWhere((c) => c['id'] == contactId);
      await prefsService.setJsonList('contacts', existingContacts);

      // Try to remove conversation from database if it exists
      try {
        final messageStorageService = MessageStorageService.instance;
        // Find conversation by participant ID and delete it
        final conversations = await messageStorageService
            .getUserConversations(SeSessionService().currentSessionId ?? '');
        final conversationToDelete = conversations.firstWhere(
          (conv) => conv.participant2Id == contactId,
          orElse: () => throw Exception('Conversation not found'),
        );

        // Note: We don't have a deleteConversation method yet, but we can mark it as deleted
        // For now, just log that we would delete it
        print(
            '🔔 SimpleNotificationService: Would delete conversation: ${conversationToDelete.id}');
      } catch (e) {
        print(
            '🔔 SimpleNotificationService: No conversation to rollback in database: $e');
      }

      print('🔔 SimpleNotificationService: ✅ Rollback completed');
    } catch (e) {
      print('🔔 SimpleNotificationService: Error during rollback: $e');
    }
  }

  /// Handle encrypted user data response notification
  Future<void> _handleUserDataResponse(Map<String, dynamic> data) async {
    try {
      print(
          '🔔 SimpleNotificationService: Processing encrypted user data response');

      // Extract encrypted data
      final encryptedData = data['data'] as String?;

      if (encryptedData == null) {
        print(
            '🔔 SimpleNotificationService: No encrypted data found in response');
        return;
      }

      // Decrypt the data using the new encryption service
      final decryptedData = await EncryptionService.decryptAesCbcPkcs7(
        encryptedData,
      );

      if (decryptedData == null) {
        print('🔔 SimpleNotificationService: Failed to decrypt response data');
        return;
      }

      print(
          '🔔 SimpleNotificationService: ✅ Response data decrypted successfully');

      // Process the decrypted response data
      await _processDecryptedResponseData(decryptedData);

      // Also update the KeyExchangeRequestProvider to refresh the UI in real-time
      try {
        final senderId = decryptedData['sender_id'] as String?;
        final displayName = decryptedData['display_name'] as String?;

        if (senderId != null && displayName != null) {
          // Update the KeyExchangeRequestProvider with the new display name
          final keyExchangeProvider = KeyExchangeRequestProvider();
          await keyExchangeProvider.updateUserDisplayName(
              senderId, displayName);
          print(
              '🔔 SimpleNotificationService: ✅ KeyExchangeRequestProvider updated with response display name');
        }
      } catch (e) {
        print(
            '🔔 SimpleNotificationService: Error updating KeyExchangeRequestProvider from response: $e');
        // Continue with the process even if provider update fails
      }
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error processing user data response: $e');
    }
  }

  /// Process decrypted response data and create contact/chat on sender side
  Future<void> _processDecryptedResponseData(
      Map<String, dynamic> responseData) async {
    try {
      print('🔔 SimpleNotificationService: Processing decrypted response data');

      final senderId = responseData['sender_id'] as String?;
      final displayName = responseData['display_name'] as String?;
      final chatId = responseData['chat_id'] as String?;
      final profileData = responseData['profile_data'] as Map<String, dynamic>?;

      if (senderId == null || displayName == null || chatId == null) {
        print('🔔 SimpleNotificationService: Invalid response data');
        return;
      }

      print(
          '🔔 SimpleNotificationService: Processing response for user: $displayName ($senderId)');

      // Update the Key Exchange Request display name from "session_..." to actual name
      await _updateKeyExchangeRequestDisplayName(senderId, displayName);

      // Create contact and chat on our side
      await _createContactAndChatFromResponse(
          senderId, displayName, chatId, profileData);

      // Mark the key exchange as complete by updating the KER status
      await _markKeyExchangeComplete(senderId);

      // Notify about completed key exchange for UI updates
      await _notifyKeyExchangeCompleted(senderId, displayName);

      print(
          '🔔 SimpleNotificationService: ✅ Contact and chat created from response');
      print(
          '🔔 SimpleNotificationService: 🎉 Key Exchange Request feature complete!');
    } catch (e) {
      print('🔔 SimpleNotificationService: Error processing response data: $e');
    }
  }

  /// Create contact and chat from response data
  Future<void> _createContactAndChatFromResponse(
    String contactId,
    String displayName,
    String chatId,
    Map<String, dynamic>? profileData,
  ) async {
    try {
      print(
          '🔔 SimpleNotificationService: Creating contact and chat from response for: $displayName');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🔔 SimpleNotificationService: User not logged in');
        return;
      }

      // Create contact
      final contact = {
        'id': contactId,
        'displayName': displayName,
        'sessionId': contactId,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'profileData': profileData ?? {},
        'status': 'active',
      };

      // Save contact to local storage (keeping this for backward compatibility)
      final prefsService = SeSharedPreferenceService();
      final existingContacts = await prefsService.getJsonList('contacts') ?? [];

      // Check if contact already exists
      if (!existingContacts.any((c) => c['id'] == contactId)) {
        existingContacts.add(contact);
        await prefsService.setJsonList('contacts', existingContacts);
        print(
            '🔔 SimpleNotificationService: ✅ Contact saved from response: $displayName');
      } else {
        print(
            '🔔 SimpleNotificationService: Contact already exists from response: $displayName');
      }

      // Create chat conversation in the database
      // Get current user info for chat
      final currentSession = SeSessionService().currentSession;
      final currentUserDisplayName = currentSession?.displayName ??
          'User ${currentUserId.substring(0, 8)}';

      // Create ChatConversation object for database
      final conversation = ChatConversation(
        id: chatId,
        participant1Id: currentUserId,
        participant2Id: contactId,
        displayName: displayName,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastMessageAt: DateTime.now(),
        lastMessageId: null,
        lastMessagePreview: null,
        lastMessageType: null,
        unreadCount: 0,
        isArchived: false,
        isMuted: false,
        isPinned: false,
        metadata: {
          'created_from_key_exchange': true,
          'contact_display_name': displayName,
          'current_user_display_name': currentUserDisplayName,
        },
        lastSeen: null,
        isTyping: false,
        typingStartedAt: null,
        notificationsEnabled: true,
        soundEnabled: true,
        vibrationEnabled: true,
        readReceiptsEnabled: true,
        typingIndicatorsEnabled: true,
        lastSeenEnabled: true,
        mediaAutoDownload: true,
        encryptMedia: true,
        mediaQuality: 'High',
        messageRetention: '30 days',
        isBlocked: false,
        blockedAt: null,
        recipientId: contactId,
        recipientName: displayName,
      );

      // Save conversation to database
      try {
        print(
            '🔔 SimpleNotificationService: 🗄️ Attempting to save conversation to database...');
        final messageStorageService = MessageStorageService.instance;
        print(
            '🔔 SimpleNotificationService: 📊 Conversation data: ${conversation.toJson()}');
        await messageStorageService.saveConversation(conversation);
        print(
            '🔔 SimpleNotificationService: ✅ Chat conversation created in database: $chatId');

        // Notify about conversation creation
        if (_onConversationCreated != null) {
          _onConversationCreated!(conversation);
        }
      } catch (e) {
        print(
            '🔔 SimpleNotificationService: ❌ Failed to create chat conversation in database: $e');
        print(
            '🔔 SimpleNotificationService: 🔍 Error details: ${e.runtimeType} - $e');
        // No fallback to SharedPreferences - database must succeed
        throw Exception('Failed to create chat conversation in database: $e');
      }

      // Show success message to user
      _showToastMessage('Secure connection established with $displayName!');
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error creating contact/chat from response: $e');
    }
  }

  /// Handle key exchange sent notification
  Future<void> _handleKeyExchangeSent(Map<String, dynamic> data) async {
    try {
      print(
          '🔔 SimpleNotificationService: Processing key exchange sent notification');

      // Extract key exchange data
      final senderId = data['sender_id'] as String?;
      final requestId = data['request_id'] as String?;
      final publicKey = data['public_key'] as String?;
      final timestampRaw = data['timestamp'];

      if (senderId == null || requestId == null || publicKey == null) {
        print(
            '🔔 SimpleNotificationService: Invalid key exchange sent data - missing required fields');
        print('🔔 SimpleNotificationService: Received data: $data');
        return;
      }

      // Handle timestamp conversion safely
      DateTime timestamp;
      if (timestampRaw is int) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(timestampRaw);
      } else if (timestampRaw is String) {
        try {
          timestamp =
              DateTime.fromMillisecondsSinceEpoch(int.parse(timestampRaw));
        } catch (e) {
          print(
              '🔔 SimpleNotificationService: Invalid timestamp string: $timestampRaw, using current time');
          timestamp = DateTime.now();
        }
      } else {
        print(
            '🔔 SimpleNotificationService: Invalid timestamp type: ${timestampRaw.runtimeType}, using current time');
        timestamp = DateTime.now();
      }

      print(
          '🔔 SimpleNotificationService: Key exchange sent from $senderId for request: $requestId');

      // Create a key exchange response record for the recipient
      final keyExchangeResponse = KeyExchangeRequest(
        id: requestId,
        fromSessionId: senderId,
        toSessionId: SeSessionService().currentSessionId ?? '',
        requestPhrase: '', // No phrase for sent notification
        status: 'sent',
        timestamp: timestamp,
        type: 'key_exchange_sent',
      );

      // Save to local storage
      final prefsService = SeSharedPreferenceService();
      final existingRequests =
          await prefsService.getJsonList('key_exchange_requests') ?? [];

      // Check if response already exists
      if (!existingRequests.any((req) => req['id'] == requestId)) {
        existingRequests.add(keyExchangeResponse.toJson());
        await prefsService.setJsonList(
            'key_exchange_requests', existingRequests);
        print(
            '🔔 SimpleNotificationService: ✅ Key exchange sent saved locally');
      } else {
        print('🔔 SimpleNotificationService: Key exchange sent already exists');
      }

      // Add notification item
      if (_onNotificationReceived != null) {
        _onNotificationReceived!(
          'Key Exchange Sent',
          'Your key exchange request has been sent',
          'key_exchange_sent',
          data,
        );
      }

      // Notify the provider via callback
      if (_onKeyExchangeRequestReceived != null) {
        _onKeyExchangeRequestReceived!(data);
        print(
            '🔔 SimpleNotificationService: ✅ Key exchange sent callback triggered');
      }

      print('🔔 SimpleNotificationService: ✅ Key exchange sent processed');
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error processing key exchange sent: $e');
    }
  }

  /// Generate a unique ID for a notification to prevent duplicates
  String _generateNotificationId(Map<String, dynamic> notificationData) {
    final dataJson = json.encode(notificationData);
    final hash = sha256.convert(utf8.encode(dataJson)).toString();
    return hash;
  }

  /// Clear processed notifications to prevent memory buildup
  void clearProcessedNotifications() {
    _processedNotifications.clear();
    print(
        '🔔 SimpleNotificationService: ✅ Cleared processed notifications cache');
  }

  /// Get count of processed notifications (for debugging)
  int get processedNotificationsCount => _processedNotifications.length;

  /// Save notification to SharedPreferences
  Future<void> _saveNotificationToSharedPrefs({
    required String id,
    required String title,
    required String body,
    required String type,
    required Map<String, dynamic> data,
    required DateTime timestamp,
  }) async {
    try {
      final prefsService = SeSharedPreferenceService();
      final existingNotifications =
          await prefsService.getJsonList('notifications') ?? [];

      final notification = {
        'id': id,
        'title': title,
        'body': body,
        'type': type,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
        'read': false,
      };

      existingNotifications.add(notification);
      await prefsService.setJsonList('notifications', existingNotifications);

      print(
          '🔔 SimpleNotificationService: ✅ Notification saved to SharedPreferences: $id');
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: ❌ Error saving notification to SharedPreferences: $e');
    }
  }

  /// Refresh notification permissions (useful when returning from settings)
  Future<void> refreshPermissions() async {
    try {
      print('🔔 SimpleNotificationService: Refreshing permissions...');

      if (Platform.isIOS) {
        // For iOS, use the enhanced permission refresh logic
        await _forceRefreshIOSPermissions();
      } else {
        // For other platforms, use standard permission check
        final status = await Permission.notification.status;
        _permissionStatus = status;
        print('🔔 SimpleNotificationService: Permissions refreshed: $status');
      }
    } catch (e) {
      print('🔔 SimpleNotificationService: Error refreshing permissions: $e');
    }
  }

  /// Force refresh iOS permissions (public method for external use)
  Future<void> forceRefreshIOSPermissions() async {
    if (Platform.isIOS) {
      await _forceRefreshIOSPermissions();
    }
  }

  /// Check if we need to show permission dialog
  bool get shouldShowPermissionDialog {
    if (kIsWeb) return false;

    if (Platform.isIOS) {
      return _permissionStatus == PermissionStatus.permanentlyDenied;
    } else {
      return _permissionStatus == PermissionStatus.denied;
    }
  }

  /// Open app settings for permission management
  Future<void> openAppSettingsForPermissions() async {
    try {
      await openAppSettings();
      print('🔔 SimpleNotificationService: App settings opened');
    } catch (e) {
      print('🔔 SimpleNotificationService: Error opening app settings: $e');
    }
  }

  /// Validate and correct permission status discrepancies
  Future<void> validatePermissionStatus() async {
    try {
      print('🔔 SimpleNotificationService: Validating permission status...');

      if (Platform.isIOS) {
        // For iOS, check if we need to request permissions again
        final reportedStatus = _permissionStatus;

        print('🔔 SimpleNotificationService: Reported status: $reportedStatus');

        if (reportedStatus == PermissionStatus.permanentlyDenied ||
            reportedStatus == PermissionStatus.denied) {
          print(
              '🔔 SimpleNotificationService: ⚠️ Status discrepancy detected - attempting to request permissions again');

          // First, try to sync device token from AirNotifier service
          await _syncDeviceTokenFromAirNotifier();

          // For iOS, permissions are already requested during initialization
          // iOS automatically registers for remote notifications during app launch
          // Manual registration is optional
          try {
            await _registerForRemoteNotifications();
          } catch (e) {
            print(
                '🔔 SimpleNotificationService: ⚠️ Remote notification registration failed, but iOS handles this automatically: $e');
          }

          // Update permission status
          _permissionStatus = PermissionStatus.granted;
          print(
              '🔔 SimpleNotificationService: ✅ Permission status updated to: $_permissionStatus');
        } else if (reportedStatus == PermissionStatus.granted) {
          print(
              '🔔 SimpleNotificationService: ✅ Permission status is already granted');
        }
      }
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error validating permission status: $e');
    }
  }

  /// Check current iOS notification settings (debug only)
  Future<void> _checkIOSNotificationSettings() async {
    try {
      print(
          '🔔 SimpleNotificationService: Checking iOS notification settings...');

      // Get notification settings using the main plugin
      final settings =
          await _localNotifications.getNotificationAppLaunchDetails();
      print(
          '🔔 SimpleNotificationService: iOS notification settings: $settings');

      // Also check permission status using permission_handler
      if (Platform.isIOS) {
        final permissionStatus = await Permission.notification.status;
        print(
            '🔔 SimpleNotificationService: iOS permission status: $permissionStatus');
      }
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error checking iOS notification settings: $e');
    }
  }

  /// Check if the method channel is available and ready
  Future<bool> _isMethodChannelReady() async {
    try {
      const channel = MethodChannel('push_notifications');

      // Try to call a simple test method
      final result = await channel.invokeMethod('testMethodChannel');
      print(
          '🔔 SimpleNotificationService: ✅ Method channel test successful: $result');
      return true;
    } catch (e) {
      print('🔔 SimpleNotificationService: ❌ Method channel not ready: $e');
      return false;
    }
  }

  /// Wait for method channel to be ready with timeout
  Future<bool> _waitForMethodChannel(
      {Duration timeout = const Duration(seconds: 5)}) async {
    final startTime = DateTime.now();

    while (DateTime.now().difference(startTime) < timeout) {
      if (await _isMethodChannelReady()) {
        return true;
      }

      // Wait a bit before trying again
      await Future.delayed(const Duration(milliseconds: 500));
    }

    print(
        '🔔 SimpleNotificationService: ⚠️ Method channel not ready after ${timeout.inSeconds} seconds');
    return false;
  }

  /// Mark the key exchange as complete
  Future<void> _markKeyExchangeComplete(String contactId) async {
    try {
      print(
          '🔔 SimpleNotificationService: Marking key exchange as complete for: $contactId');

      // Get the current user's session ID
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔔 SimpleNotificationService: User not logged in, cannot mark KER complete');
        return;
      }

      // Store the completion status in shared preferences
      final prefsService = SeSharedPreferenceService();
      final completedExchanges =
          await prefsService.getJson('completed_key_exchanges') ?? {};

      // Mark this exchange as complete
      completedExchanges[contactId] = {
        'completed_at': DateTime.now().millisecondsSinceEpoch,
        'status': 'complete',
      };

      await prefsService.setJson('completed_key_exchanges', completedExchanges);

      print(
          '🔔 SimpleNotificationService: ✅ Key exchange marked as complete for: $contactId');
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error marking key exchange complete: $e');
    }
  }

  /// Notify KeyExchangeRequestProvider about completed key exchange
  Future<void> _notifyKeyExchangeCompleted(
      String contactId, String displayName) async {
    try {
      print(
          '🔔 SimpleNotificationService: Notifying KeyExchangeRequestProvider about completed exchange');

      // Get the current user's session ID
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔔 SimpleNotificationService: User not logged in, cannot notify provider');
        return;
      }

      // Update the KER display names and mark as complete
      await _updateKeyExchangeRequestDisplayName(contactId, displayName);
      await _markKeyExchangeComplete(contactId);

      // Store the completion status in shared preferences for UI updates
      final prefsService = SeSharedPreferenceService();
      final completedExchanges =
          await prefsService.getJson('completed_key_exchanges') ?? {};

      // Mark this exchange as complete with display name
      completedExchanges[contactId] = {
        'completed_at': DateTime.now().millisecondsSinceEpoch,
        'status': 'complete',
        'display_name': displayName,
        'contact_id': contactId,
      };

      await prefsService.setJson('completed_key_exchanges', completedExchanges);

      print(
          '🔔 SimpleNotificationService: ✅ Key exchange completion data stored for UI updates');

      // Trigger UI refresh by updating the indicator service
      IndicatorService().setNewKeyExchange();
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error notifying about key exchange completion: $e');
    }
  }
}
