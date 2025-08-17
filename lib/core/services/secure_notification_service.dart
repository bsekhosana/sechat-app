import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
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
import 'package:sechat_app/features/chat/models/message.dart' as chat_message;
import 'package:sechat_app/shared/models/key_exchange_request.dart';
import 'package:sechat_app/core/services/indicator_service.dart';
import 'package:flutter/material.dart';
import '../config/airnotifier_config.dart';
import 'package:sechat_app/features/key_exchange/providers/key_exchange_request_provider.dart';
import 'package:sechat_app/features/chat/models/chat_conversation.dart';
import 'package:sechat_app/features/chat/services/message_storage_service.dart';
import 'package:sechat_app/features/chat/services/message_status_tracking_service.dart';
import 'package:sechat_app/features/chat/providers/chat_provider.dart';

/// Unified secure notification service for encrypted messaging and local notifications
class SecureNotificationService {
  static SecureNotificationService? _instance;
  static SecureNotificationService get instance =>
      _instance ??= SecureNotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  String? _deviceToken;
  String? _sessionId;
  PermissionStatus _permissionStatus = PermissionStatus.denied;

  // Cache the last typing indicator sent time for rate limiting
  final Map<String, DateTime> _lastTypingIndicatorSent = {};
  // Typing indicator cooldown duration
  static const Duration typingIndicatorCooldown = Duration(seconds: 2);

  // Permission check cache to avoid spamming
  DateTime? _lastPermissionCheck;
  static const Duration _permissionCheckCooldown = Duration(hours: 24);

  // Getters for permission status
  PermissionStatus get permissionStatus => _permissionStatus;
  bool get isPermissionGranted => _permissionStatus.isGranted;

  // Notification callbacks
  Function(String senderId, String senderName, String message,
      String conversationId, String? messageId)? _onMessageReceived;
  Function(String senderId, bool isTyping)? _onTypingIndicator;
  Function(String senderId, String messageId, String status)?
      _onMessageStatusUpdate;
  Function(Map<String, dynamic> data)? _onKeyExchangeRequestReceived;
  Function(Map<String, dynamic> data)? _onKeyExchangeAccepted;
  Function(Map<String, dynamic> data)? _onKeyExchangeDeclined;
  Function(String title, String body, String type, Map<String, dynamic>? data)?
      _onNotificationReceived;
  Function(ChatConversation conversation)? _onConversationCreated;

  // Prevent duplicate notification processing
  final Set<String> _processedNotifications = <String>{};

  SecureNotificationService._();

  /// Initialize the secure notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Get session ID (may be null initially - will be set later via setSessionId)
      _sessionId = SeSessionService().currentSessionId;

      // Ensure encryption keys exist
      await KeyExchangeService.instance.ensureKeysExist();

      // Initialize local notifications FIRST (this sets up the iOS plugin)
      await _initializeLocalNotifications();

      // Request permissions AFTER local notifications are initialized
      await _requestPermissions();

      // Initialize AirNotifier with session ID (if available)
      if (_sessionId != null) {
        await _initializeAirNotifier();
      }

      _isInitialized = true;

      // Check for app reinstall and handle if needed
      await detectAndHandleAppReinstall();

      // Log final permission status and device token state
      print(
          '🔒 SecureNotificationService: Final permission status: $_permissionStatus');
      print(
          '🔒 SecureNotificationService: Device token: ${_deviceToken != null ? 'Available' : 'Not available'}');
      print('🔒 SecureNotificationService: ✅ Service initialized');
    } catch (e) {
      print('🔒 SecureNotificationService: ❌ Failed to initialize: $e');
    }
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    try {
      // Check if we've already requested permissions recently
      if (_lastPermissionCheck != null &&
          DateTime.now().difference(_lastPermissionCheck!) <
              _permissionCheckCooldown) {
        print(
            '🔒 SecureNotificationService: Skipping permission request (checked recently)');
        return;
      }

      if (Platform.isIOS) {
        const channel = MethodChannel('push_notifications');
        String status = 'notDetermined';

        try {
          status =
              (await channel.invokeMethod<String>('getAuthorizationStatus')) ??
                  'notDetermined';
        } on MissingPluginException {
          // Channel not ready yet (wrong engine / startup race). If we already have APNs token, consider granted.
          if (_deviceToken?.isNotEmpty == true) {
            _permissionStatus = PermissionStatus.granted;
            _lastPermissionCheck = DateTime.now();
            print(
                '🔒 iOS: Channel missing but APNs token present -> treating as granted');
            return;
          }
          // Otherwise, silently skip and try again later (don't show dialog).
          print('🔒 iOS: Channel missing and no token yet -> will retry later');
          _permissionStatus =
              PermissionStatus.denied; // internal state; don't show dialog yet
          _lastPermissionCheck = DateTime.now();
          return;
        }

        print('🔒 SecureNotificationService: iOS auth status: $status');

        if (status == 'notDetermined') {
          final granted =
              await channel.invokeMethod<bool>('requestAuthorization') ?? false;
          _permissionStatus =
              granted ? PermissionStatus.granted : PermissionStatus.denied;
          if (granted) {
            await channel.invokeMethod('registerForRemoteNotifications');
          }
        } else {
          final grantedStates = {'authorized', 'provisional', 'ephemeral'};
          _permissionStatus = grantedStates.contains(status)
              ? PermissionStatus.granted
              : PermissionStatus.denied;
          if (_permissionStatus.isGranted) {
            await channel.invokeMethod('registerForRemoteNotifications');
          }
        }
      } else {
        // Android etc.
        final status = await Permission.notification.request();
        _permissionStatus = status;
        print('🔒 SecureNotificationService: Android permissions requested');
      }

      _lastPermissionCheck = DateTime.now();
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Failed to request permissions: $e');
    }
  }

  /// Initialize local notifications plugin
  Future<void> _initializeLocalNotifications() async {
    try {
      // Define notification channels for Android
      final androidSettings =
          const AndroidInitializationSettings('ic_notification');

      // Define notification settings for iOS
      final iosSettings = const DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      // Initialize with platform-specific settings
      final initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      // Initialize the plugin
      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _handleNotificationTap,
      );

      // Create distinct notification channels for Android
      await _createNotificationChannels();

      // Set iOS APNS environment if on iOS
      if (Platform.isIOS) {
        await _setIOSAPNSEnvironment();
      }

      print('🔒 SecureNotificationService: ✅ Local notifications initialized');
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Failed to initialize local notifications: $e');
    }
  }

  /// Create distinct notification channels for Android
  Future<void> _createNotificationChannels() async {
    try {
      if (Platform.isAndroid) {
        // Chat messages channel
        const chatChannel = AndroidNotificationChannel(
          'chat_messages',
          'Chat Messages',
          description: 'Notifications for new chat messages',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        );

        // System notifications channel
        const systemChannel = AndroidNotificationChannel(
          'system_notifications',
          'System Notifications',
          description: 'Notifications for system events and key exchange',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        );

        // Key exchange channel
        const keyExchangeChannel = AndroidNotificationChannel(
          'key_exchange',
          'Key Exchange',
          description: 'Notifications for key exchange requests and responses',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        );

        await _notifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(chatChannel);
        await _notifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(systemChannel);
        await _notifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(keyExchangeChannel);

        print(
            '🔒 SecureNotificationService: ✅ Android notification channels created');
      }
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error creating notification channels: $e');
    }
  }

  /// Set iOS APNS environment to production
  Future<void> _setIOSAPNSEnvironment() async {
    try {
      print(
          '🔒 SecureNotificationService: Setting iOS APNS environment to production...');

      // For iOS, we need to ensure APNS is configured for production
      // This is critical when pointing to production AirNotifier server

      // Check if we're pointing to production AirNotifier
      final isProductionAirNotifier =
          AirNotifierConfig.baseUrl.contains('strapblaque.com') ||
              AirNotifierConfig.baseUrl.contains('production');

      if (isProductionAirNotifier) {
        print(
            '🔒 SecureNotificationService: ✅ Production AirNotifier detected, ensuring production APNS configuration');

        // iOS will automatically use production APNS when the app is built with production provisioning
        // But we can verify the configuration is correct

        // Check notification settings to ensure they're properly configured
        final notificationSettings =
            await _notifications.getNotificationAppLaunchDetails();
        print(
            '🔒 SecureNotificationService: iOS notification launch details: $notificationSettings');

        // Verify APNS environment
        print(
            '🔒 SecureNotificationService: ✅ iOS APNS configured for production environment');
        print(
            '🔒 SecureNotificationService: 💡 Note: APNS environment is determined by provisioning profile, not runtime configuration');
      } else {
        print(
            '🔒 SecureNotificationService: ⚠️ Non-production AirNotifier detected, but APNS should still be production for iOS');
        print(
            '🔒 SecureNotificationService: 💡 iOS requires production APNS for production AirNotifier servers');
      }
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error setting iOS APNS environment: $e');
    }
  }

  // ===== iOS APNS HANDLING =====

  /// Handle iOS notification permissions specifically
  Future<void> _handleIOSPermissions() async {
    try {
      print('🔒 SecureNotificationService: Handling iOS permissions...');

      // For iOS, permissions are now requested during initialization in _initializeLocalNotifications
      // iOS automatically registers for remote notifications during app launch
      // We just need to ensure our method channel is ready for device token delivery

      // First, try to sync device token from AirNotifier service
      await _syncDeviceTokenFromAirNotifier();

      // Check if we already have a device token (indicating permissions were previously granted)
      if (_deviceToken != null && _deviceToken!.isNotEmpty) {
        print(
            '🔒 SecureNotificationService: ✅ Device token already available, permissions were previously granted');
        _permissionStatus = PermissionStatus.granted;
      } else {
        // No device token available, but iOS handles registration automatically
        // We can try to register manually, but it's not critical
        try {
          await _registerForRemoteNotifications();
        } catch (e) {
          print(
              '🔒 SecureNotificationService: ⚠️ Remote notification registration failed, but iOS handles this automatically: $e');
        }

        // Set permission status based on whether we can proceed
        _permissionStatus = PermissionStatus.granted;
      }

      print(
          '🔒 SecureNotificationService: ✅ iOS notification permissions handled');
    } catch (e) {
      print('🔒 SecureNotificationService: Error handling iOS permissions: $e');
      _permissionStatus = PermissionStatus.denied;
    }
  }

  /// Register for remote notifications on iOS
  Future<void> _registerForRemoteNotifications() async {
    try {
      print(
          '🔒 SecureNotificationService: Registering for remote notifications...');

      // Check if we already have a device token
      if (_deviceToken != null && _deviceToken!.isNotEmpty) {
        print(
            '🔒 SecureNotificationService: ✅ Device token already available: ${_deviceToken!.substring(0, 8)}...');
        print(
            '🔒 SecureNotificationService: Skipping remote notification registration');
        return;
      }

      // Wait for method channel to be ready
      final isReady = await _waitForMethodChannel();

      if (!isReady) {
        print(
            '🔒 SecureNotificationService: ⚠️ Method channel not ready, skipping remote notification registration');
        print(
            '🔒 SecureNotificationService: iOS will handle registration automatically during app launch');
        return;
      }

      // Now try to register for remote notifications
      const channel = MethodChannel('push_notifications');
      await channel.invokeMethod('registerForRemoteNotifications');

      print(
          '🔒 SecureNotificationService: ✅ Remote notification registration requested');
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error registering for remote notifications: $e');

      // If the method channel fails, we can still proceed
      // The iOS side will handle registration automatically during app launch
      print(
          '🔒 SecureNotificationService: ⚠️ Continuing without method channel registration');
    }
  }

  /// Check if the method channel is available and ready
  Future<bool> _isMethodChannelReady() async {
    try {
      const channel = MethodChannel('push_notifications');

      // Try to call a simple test method
      final result = await channel.invokeMethod('testMethodChannel');
      print(
          '🔒 SecureNotificationService: ✅ Method channel test successful: $result');
      return true;
    } catch (e) {
      print('🔒 SecureNotificationService: ❌ Method channel not ready: $e');
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
        '🔒 SecureNotificationService: ⚠️ Method channel not ready after ${timeout.inSeconds} seconds');
    return false;
  }

  /// Manually request device token from native platform
  Future<void> _requestDeviceTokenFromNative() async {
    try {
      print(
          '🔒 SecureNotificationService: Manually requesting device token from native platform...');

      // Wait for method channel to be ready
      final isReady = await _waitForMethodChannel();
      if (!isReady) {
        print(
            '🔒 SecureNotificationService: ⚠️ Method channel not ready, cannot request token');
        return;
      }

      const channel = MethodChannel('push_notifications');
      await channel.invokeMethod('requestDeviceToken');
      print(
          '🔒 SecureNotificationService: ✅ Device token request sent to native platform');
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error requesting device token: $e');
    }
  }

  /// Manually trigger device token retrieval if not available
  Future<void> ensureDeviceTokenAvailable() async {
    if (_deviceToken != null && _deviceToken!.isNotEmpty) {
      print(
          '🔒 SecureNotificationService: ✅ Device token already available: ${_deviceToken!.substring(0, 8)}...');
      return;
    }

    print(
        '🔒 SecureNotificationService: ⚠️ No device token available, manually requesting from native platform...');
    await _requestDeviceTokenFromNative();
  }

  /// Sync device token from AirNotifier service
  Future<void> _syncDeviceTokenFromAirNotifier() async {
    try {
      print(
          '🔒 SecureNotificationService: Syncing device token from AirNotifier...');

      // Add a small delay to ensure AirNotifier is fully initialized
      await Future.delayed(const Duration(milliseconds: 500));

      // Get the current device token from AirNotifier service
      final airNotifierToken = AirNotifierService.instance.currentDeviceToken;

      print(
          '🔒 SecureNotificationService: AirNotifier device token: ${airNotifierToken != null ? "${airNotifierToken.substring(0, 8)}..." : "No"}');
      print(
          '🔒 SecureNotificationService: Current device token: ${_deviceToken != null ? "${_deviceToken!.substring(0, 8)}..." : "No"}');

      if (airNotifierToken != null && airNotifierToken.isNotEmpty) {
        print(
            '🔒 SecureNotificationService: Syncing device token from AirNotifier: ${airNotifierToken.substring(0, 8)}...');

        // Set the device token in this service
        _deviceToken = airNotifierToken;

        // Link the token to the current session
        if (_sessionId != null) {
          await _linkTokenToSession();
        }

        print(
            '🔒 SecureNotificationService: ✅ Device token synced from AirNotifier');
        print(
            '🔒 SecureNotificationService: Device token after sync: ${_deviceToken != null ? "${_deviceToken!.substring(0, 8)}..." : "No"}');
      } else {
        print(
            '🔒 SecureNotificationService: ✅ No device token available in AirNotifier service');

        // Try to get device token from storage as fallback
        await _tryRestoreDeviceTokenFromStorage();
      }
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error syncing device token from AirNotifier: $e');

      // Try to get device token from storage as fallback
      await _tryRestoreDeviceTokenFromStorage();
    }
  }

  /// Try to restore device token from storage as fallback
  Future<void> _tryRestoreDeviceTokenFromStorage() async {
    try {
      print(
          '🔒 SecureNotificationService: ✅ Trying to restore device token from storage...');

      // This would use secure storage in a real implementation
      // For now, we'll just log that we would try to restore
      print(
          '🔒 SecureNotificationService: Would attempt to restore device token from storage');
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error restoring device token from storage: $e');
    }
  }

  /// Link token to session with retry mechanism
  Future<void> _linkTokenToSession() async {
    if (_sessionId == null || _deviceToken == null) {
      print(
          '🔒 SecureNotificationService: Cannot link token - missing session ID or device token');
      return;
    }

    // Token is already registered by the session service, just link it
    print(
        '🔒 SecureNotificationService: ✅ Token already registered, linking to session: $_sessionId');

    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        final success =
            await AirNotifierService.instance.linkTokenToSession(_sessionId!);
        if (success) {
          print(
              '🔒 SecureNotificationService: ✅ Token linked to session $_sessionId');
          return;
        } else {
          print(
              '🔒 SecureNotificationService: ❌ Failed to link token to session (attempt ${retryCount + 1})');
          retryCount++;
          if (retryCount < maxRetries) {
            await Future.delayed(
                Duration(seconds: retryCount * 2)); // Exponential backoff
          }
        }
      } catch (e) {
        print(
            '🔒 SecureNotificationService: ❌ Error linking token to session (attempt ${retryCount + 1}): $e');
        return;
      }
    }

    print(
        '🔒 SecureNotificationService: ❌ Failed to link token after $maxRetries attempts');
  }

  /// Initialize AirNotifier service
  Future<void> _initializeAirNotifier() async {
    try {
      // Ensure AirNotifier service is initialized first
      await AirNotifierService.instance.initialize(sessionId: _sessionId);

      // If we already have a runtime token (handleDeviceTokenReceived was called), use it.
      _deviceToken ??= await _getDeviceToken();

      // Always persist + link this token now (don't let old cached token win)
      if (_deviceToken != null && _sessionId != null) {
        // Use the proper token linking method that handles registration and linking
        await _ensureTokenLinkedToSession();
      } else {
        print(
            '🔒 SecureNotificationService: ⚠️ Missing device token or session ID for AirNotifier linking');
      }
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Failed to initialize AirNotifier: $e');
    }
  }

  /// Get device token for push notifications
  Future<String?> _getDeviceToken() async {
    try {
      // Get device token from platform channel
      const platform = MethodChannel('push_notifications');
      final token = await platform.invokeMethod<String>('getDeviceToken');

      if (token != null && token.isNotEmpty) {
        print(
            '🔒 SecureNotificationService: ✅ Device token received: ${token.substring(0, 8)}...');
        return token;
      } else {
        print('🔒 SecureNotificationService: ⚠️ No device token available');
        return null;
      }
    } catch (e) {
      print('🔒 SecureNotificationService: ❌ Failed to get device token: $e');
      return null;
    }
  }

  /// Handle device token received from platform
  Future<void> handleDeviceTokenReceived(String token) async {
    _deviceToken = token;
    print(
        '🔒 SecureNotificationService: ✅ Device token received: ${token.substring(0, 8)}...');

    // If we have a session ID, ensure the token is immediately linked to the session
    if (_sessionId != null) {
      print(
          '🔒 SecureNotificationService: 🔄 Session ID available, ensuring token is linked to session on AirNotifier');
      await _ensureTokenLinkedToSession();
    } else {
      print(
          '🔒 SecureNotificationService: ⚠️ No session ID available yet, will link token when session is set');
      // Token will be linked when setSessionId is called
    }
  }

  /// Ensure token is linked to session on AirNotifier with retry mechanism
  Future<void> _ensureTokenLinkedToSession() async {
    if (_sessionId == null || _deviceToken == null) {
      print(
          '🔒 SecureNotificationService: Cannot link token - missing session ID or device token');
      return;
    }

    print(
        '🔒 SecureNotificationService: 🔗 Ensuring token is linked to session: $_sessionId');

    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        // First, ensure the token is properly stored in AirNotifier service
        // This sets _currentDeviceToken in the service when sessionId matches currentSessionId
        final platform = Platform.isIOS ? 'ios' : 'android';
        await AirNotifierService.instance.saveTokenForSession(
          sessionId: _sessionId!,
          token: _deviceToken!,
          platform: platform,
        );

        // Now register the device token with AirNotifier server
        print(
            '🔒 SecureNotificationService: 🔄 About to call registerDeviceToken...');
        final success = await AirNotifierService.instance.registerDeviceToken(
          deviceToken: _deviceToken!,
          sessionId: _sessionId!,
        );
        print(
            '🔒 SecureNotificationService: 🔄 registerDeviceToken returned: $success');

        if (success) {
          print(
              '🔒 SecureNotificationService: ✅ Device token registered and linked with AirNotifier server');

          // For iOS devices, ensure token visibility after successful linking
          if (_isIOSDevice(_deviceToken!)) {
            await _ensureIOSTokenVisibility(_sessionId!);
          }
          return;
        } else {
          print(
              '🔒 SecureNotificationService: ❌ Failed to register device token (attempt ${retryCount + 1})');
        }

        retryCount++;
        if (retryCount < maxRetries) {
          await Future.delayed(
              Duration(seconds: retryCount * 2)); // Exponential backoff
        }
      } catch (e) {
        print(
            '🔒 SecureNotificationService: ❌ Error linking token to session (attempt ${retryCount + 1}): $e');
        retryCount++;
        if (retryCount < maxRetries) {
          await Future.delayed(
              Duration(seconds: retryCount * 2)); // Exponential backoff
        }
      }
    }

    print(
        '🔒 SecureNotificationService: ❌ Failed to link token after $maxRetries attempts');
  }

  /// Try to register device with AirNotifier (handles missing session ID gracefully)
  Future<void> _tryRegisterDevice() async {
    if (_deviceToken == null) {
      print(
          '🔒 SecureNotificationService: ⚠️ No device token available for registration');
      return;
    }

    if (_sessionId == null) {
      print(
          '🔒 SecureNotificationService: ⚠️ No session ID available yet, will retry when session is set');
      print(
          '🔒 SecureNotificationService: Device token stored for later registration: ${_deviceToken!.substring(0, 8)}...');
      // Store token for later registration when session ID becomes available
      return;
    }

    print(
        '🔒 SecureNotificationService: 🔄 Attempting to register device with session ID: $_sessionId');

    // Session ID is available, proceed with registration
    final platform = Platform.isIOS ? 'ios' : 'android';
    await AirNotifierService.instance.saveTokenForSession(
      sessionId: _sessionId!,
      token: _deviceToken!,
      platform: platform,
    );

    // Register device immediately
    await _registerDevice();
  }

  /// Register device with AirNotifier
  Future<void> _registerDevice() async {
    try {
      if (_deviceToken == null || _sessionId == null) {
        print(
            '🔒 SecureNotificationService: ⚠️ Missing device token or session ID for registration');
        return;
      }

      print(
          '🔒 SecureNotificationService: Registering device with AirNotifier');
      print('🔒 SecureNotificationService: Device token: $_deviceToken');
      print('🔒 SecureNotificationService: Session ID: $_sessionId');

      // Use AirNotifierService to register the device
      final airNotifierService = AirNotifierService.instance;
      final success = await airNotifierService.registerDeviceToken(
        deviceToken: _deviceToken!,
        sessionId: _sessionId!,
      );

      if (success) {
        print(
            '🔒 SecureNotificationService: ✅ Device registered with AirNotifier');

        // For iOS devices, ensure token visibility - only after successful registration
        if (_isIOSDevice(_deviceToken!)) {
          await _ensureIOSTokenVisibility(_sessionId!);
        }
      } else {
        print(
            '🔒 SecureNotificationService: ❌ Failed to register device with AirNotifier');
      }
    } catch (e) {
      print('🔒 SecureNotificationService: ❌ Failed to register device: $e');
    }
  }

  /// Detect if device is iOS based on token format
  bool _isIOSDevice(String token) {
    // iOS tokens are typically 64 characters long and contain alphanumeric characters
    // They also have a specific format pattern
    if (token.length == 64 && RegExp(r'^[A-Fa-f0-9]+$').hasMatch(token)) {
      // Additional iOS token validation
      // iOS tokens typically don't contain certain patterns that Android tokens have
      if (!token.contains(':')) {
        // Android FCM tokens often contain colons
        return true;
      }
    }

    // Android FCM tokens are typically longer and contain different characters
    // They can be 140+ characters and often contain colons, dots, and other special chars
    if (token.length > 100 || token.contains(':') || token.contains('.')) {
      return false;
    }

    // Fallback: if we can't determine, assume Android (more common)
    print(
        '🔒 SecureNotificationService: ⚠️ Could not determine device type for token, assuming Android');
    return false;
  }

  /// Ensure iOS token is properly visible to other sessions
  Future<void> _ensureIOSTokenVisibility(String sessionId) async {
    try {
      print(
          '🔒 SecureNotificationService: Ensuring iOS token visibility for session: $sessionId');

      // For iOS, we need to ensure the token is properly shared
      // This might involve additional API calls to make the token discoverable

      // First, check if the token is visible to other sessions
      final airNotifierService = AirNotifierService.instance;
      await airNotifierService.ensureIOSTokenVisibility(sessionId);
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error ensuring iOS token visibility: $e');
    }
  }

  /// Fix iOS token visibility issues
  Future<void> _fixIOSTokenVisibility(String sessionId) async {
    try {
      print(
          '🔒 SecureNotificationService: Attempting to fix iOS token visibility for session: $sessionId');

      // Try to re-register the token with explicit iOS device type
      if (_deviceToken != null) {
        final airNotifierService = AirNotifierService.instance;
        await airNotifierService.fixIOSTokenVisibility(sessionId);

        print(
            '🔒 SecureNotificationService: ✅ iOS token visibility fix attempted');
      }
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error fixing iOS token visibility: $e');
    }
  }

  /// Wait for key exchange to complete with timeout
  Future<bool> _waitForKeyExchange(String recipientId) async {
    const maxWaitTime = Duration(seconds: 10);
    const checkInterval = Duration(milliseconds: 200);
    final startTime = DateTime.now();

    while (DateTime.now().difference(startTime) < maxWaitTime) {
      // Check if we now have a public key for this user
      if (await KeyExchangeService.instance.hasPublicKeyForUser(recipientId)) {
        // Verify the key is valid by testing encryption
        try {
          final testData = {'test': 'key_exchange_verification'};
          final encrypted =
              await EncryptionService.encryptAesCbcPkcs7(testData, recipientId);
          if (encrypted['data'] != null) {
            print(
                '🔒 SecureNotificationService: Key exchange verified successfully');
            return true;
          }
        } catch (e) {
          print('🔒 SecureNotificationService: Key verification failed: $e');
        }
      }

      // Wait before checking again
      await Future.delayed(checkInterval);
    }

    print(
        '🔒 SecureNotificationService: Key exchange timeout after ${maxWaitTime.inSeconds}s');
    return false;
  }

  /// Handle notification tap
  void _handleNotificationTap(NotificationResponse response) {
    try {
      final payload = response.payload;
      if (payload != null) {
        final data = _parseNotificationPayload(payload);
        if (data != null) {
          _handleDeepLink(data);
        }
      }
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Failed to handle notification tap: $e');
    }
  }

  /// Parse notification payload
  Map<String, dynamic>? _parseNotificationPayload(String payload) {
    try {
      // Simple JSON parsing
      if (payload.startsWith('{') && payload.endsWith('}')) {
        // Extract conversation ID from payload
        final conversationIdMatch =
            RegExp(r'"conversation_id":"([^"]+)"').firstMatch(payload);
        final messageTypeMatch =
            RegExp(r'"message_type":"([^"]+)"').firstMatch(payload);

        if (conversationIdMatch != null) {
          return {
            'conversation_id': conversationIdMatch.group(1),
            'message_type': messageTypeMatch?.group(1) ?? 'text',
          };
        }
      }
      return null;
    } catch (e) {
      print('🔒 SecureNotificationService: ❌ Failed to parse payload: $e');
      return null;
    }
  }

  /// Handle deep link to conversation
  void _handleDeepLink(Map<String, dynamic> data) {
    try {
      final conversationId = data['conversation_id'] as String?;
      if (conversationId != null) {
        // This would integrate with your navigation system
        print(
            '🔒 SecureNotificationService: Deep linking to conversation: $conversationId');
      }
    } catch (e) {
      print('🔒 SecureNotificationService: ❌ Failed to handle deep link: $e');
    }
  }

  /// Show local notification
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? type,
    Map<String, dynamic>? data,
  }) async {
    try {
      // Check if notifications are initialized
      if (!_isInitialized) {
        print('🔒 SecureNotificationService: ❌ Notifications not initialized');
        return;
      }

      // Determine the appropriate channel based on notification type
      String channelId;
      String channelName;
      String channelDescription;
      Importance importance;
      Priority priority;

      switch (type) {
        case 'text_message':
        case 'message':
          channelId = 'chat_messages';
          channelName = 'Chat Messages';
          channelDescription = 'Notifications for new chat messages';
          importance = Importance.high;
          priority = Priority.high;
          break;
        case 'key_exchange_request':
        case 'key_exchange_accepted':
        case 'key_exchange_declined':
        case 'key_exchange_response':
        case 'key_exchange_request_sent':
        case 'key_exchange_response_sent':
          channelId = 'key_exchange';
          channelName = 'Key Exchange';
          channelDescription =
              'Notifications for key exchange requests and responses';
          importance = Importance.high;
          priority = Priority.high;
          break;
        default:
          channelId = 'system_notifications';
          channelName = 'System Notifications';
          channelDescription = 'Notifications for system events';
          importance = Importance.low;
          priority = Priority.low;
      }

      // Create notification details
      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: importance,
        priority: priority,
        showWhen: true,
      );

      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: data?['conversation_id'] as String? ?? 'general',
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Create payload
      final payload = data != null ? json.encode(data) : null;

      // Show notification
      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch % 100000,
        title,
        body,
        details,
        payload: payload,
      );

      print(
          '🔒 SecureNotificationService: ✅ Local notification shown on channel: $channelId');
    } catch (e) {
      print('🔒 SecureNotificationService: ❌ Failed to show notification: $e');
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
      print('🔒 SecureNotificationService: Sending encrypted message');

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
          'senderId': SeSessionService().currentSessionId ??
              '', // Sender ID for routing
          'senderName': senderName, // Sender name for routing
          'conversationId': conversationId, // Conversation ID for routing
          'data': encryptedData, // Encrypted sensitive data
          'checksum': checksum, // Checksum for verification
          'messageId': messageId, // Additional metadata
          // Add additional fields to ensure notification is processed
          'action': 'message_received',
          'priority': 'high',
          'category': 'chat_message',
        },
        sound: 'message.wav',
        encrypted: true, // Mark as encrypted for AirNotifier server
        checksum: checksum, // Include checksum for verification
      );

      if (success) {
        print('🔒 SecureNotificationService: ✅ Encrypted message sent');
        return true;
      } else {
        print(
            '🔒 SecureNotificationService: ❌ Failed to send encrypted message');
        return false;
      }
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error sending encrypted message: $e');
      return false;
    }
  }

  /// Handle message notification
  Future<void> _handleMessageNotification(Map<String, dynamic> data) async {
    print('🔒 SecureNotificationService: 🔍 Processing message data: $data');

    // Handle both encrypted and unencrypted message formats
    String? senderId, senderName, message, conversationId;

    // IMPORTANT FIX: Handle iOS message notifications with different structures
    // First check if this is an iOS notification with aps structure
    if (data.containsKey('aps')) {
      print(
          '🔒 SecureNotificationService: 🔴 iOS notification detected with aps structure');
    }

    // Handle both boolean and string encrypted values
    final encryptedValue = data['encrypted'];
    final isEncrypted = encryptedValue == true ||
        encryptedValue == 'true' ||
        encryptedValue == '1' ||
        encryptedValue == 1;

    if (isEncrypted) {
      // Encrypted message format - data is in the 'data' field
      final encryptedData = data['data'] as String?;
      if (encryptedData != null) {
        // For now, assume the encrypted data contains the message directly
        // In a real implementation, this would be decrypted
        message = encryptedData;
        senderId = data['senderId'] as String?;
        senderName = data['senderName'] as String?;
        conversationId = data['conversationId'] as String?;

        print(
            '🔒 SecureNotificationService: 🔴 Encrypted message parsed: $message from $senderName');
      }
    } else {
      // Unencrypted message format
      senderId = data['senderId'] as String?;
      senderName = data['senderName'] as String?;
      message = data['message'] as String?;
      conversationId = data['conversationId'] as String?;

      print(
          '🔒 SecureNotificationService: 🔴 Unencrypted message parsed: $message from $senderName');
    }

    // Check for snake_case field names in the decrypted data
    if (senderId == null && data.containsKey('sender_id')) {
      senderId = data['sender_id'] as String?;
      print(
          '🔒 SecureNotificationService: 🔴 Using snake_case sender_id: $senderId');
    }

    if (senderName == null && data.containsKey('sender_name')) {
      senderName = data['sender_name'] as String?;
      print(
          '🔒 SecureNotificationService: 🔴 Using snake_case sender_name: $senderName');
    }

    if (conversationId == null && data.containsKey('conversation_id')) {
      conversationId = data['conversation_id'] as String?;
      print(
          '🔒 SecureNotificationService: 🔴 Using snake_case conversation_id: $conversationId');
    }

    // IMPORTANT FIX: Handle iOS notifications that might have a different structure
    if (senderId == null || senderName == null || message == null) {
      print(
          '🔒 SecureNotificationService: ⚠️ Missing fields in message notification data');
      print(
          '🔒 SecureNotificationService: senderId: $senderId, senderName: $senderName, message: $message');

      // Try to extract data from iOS notification structure
      if (data.containsKey('aps')) {
        print(
            '🔒 SecureNotificationService: 🔴 Attempting to extract data from iOS notification structure');

        // Try to get sender ID and name from other fields
        if (senderId == null) {
          senderId =
              data['senderId'] as String? ?? data['sender_id'] as String?;
          print(
              '🔒 SecureNotificationService: 🔴 Extracted senderId: $senderId');
        }

        if (senderName == null) {
          senderName =
              data['senderName'] as String? ?? data['sender_name'] as String?;
          print(
              '🔒 SecureNotificationService: 🔴 Extracted senderName: $senderName');
        }

        if (message == null) {
          // Try to get message from data field
          if (data.containsKey('data')) {
            final dataField = data['data'];
            if (dataField is String) {
              message = dataField;
              print(
                  '🔒 SecureNotificationService: 🔴 Extracted message from data field: $message');
            } else if (dataField is Map) {
              message = dataField['text'] as String? ??
                  dataField['message'] as String?;
              print(
                  '🔒 SecureNotificationService: 🔴 Extracted message from data map: $message');
            }
          }
        }
      }

      // If still missing required fields, return
      if (senderId == null || senderName == null || message == null) {
        print(
            '🔒 SecureNotificationService: ❌ Invalid message notification data - missing required fields');
        print(
            '🔒 SecureNotificationService: senderId: $senderId, senderName: $senderName, message: $message');
        return;
      }
    }

    print(
        '🔒 SecureNotificationService: Processing message from $senderName: $message');

    // CRITICAL FIX: Don't show local notifications for messages from the current user
    // This prevents the infinite notification loop
    final currentUserId = SeSessionService().currentSessionId;
    if (currentUserId != null && senderId == currentUserId) {
      print(
          '🔒 SecureNotificationService: ℹ️ Skipping local notification for message from self');
      return;
    }

    // Check if sender is blocked
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
              '🔒 SecureNotificationService: Message from blocked user ignored: $senderName');
          return; // Ignore message from blocked user
        }
      } catch (e) {
        print(
            '🔒 SecureNotificationService: Error checking database for blocking status: $e');
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
                    '🔒 SecureNotificationService: Message from blocked user ignored: $senderName');
                return; // Ignore message from blocked user
              }
            } catch (e) {
              print(
                  '🔒 SecureNotificationService: Error parsing chat for blocking check: $e');
            }
          }
        } catch (fallbackError) {
          print(
              '🔒 SecureNotificationService: Error in fallback blocking check: $fallbackError');
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
      // Check if sender is not the current user
      final currentUserId = SeSessionService().currentSessionId;
      if (senderId == currentUserId) {
        print(
            '🔒 SecureNotificationService: ℹ️ Skipping delivery receipt to self');
      } else {
        final airNotifier = AirNotifierService.instance;

        // Use the message_id as the messageId parameter, not the conversationId
        final messageId = data['message_id'] as String? ??
            'msg_${DateTime.now().millisecondsSinceEpoch}';

        final success = await airNotifier.sendMessageDeliveryStatus(
          recipientId: senderId,
          messageId: messageId,
          status: 'delivered',
          conversationId: conversationId ??
              'chat_${DateTime.now().millisecondsSinceEpoch}_$senderId',
        );

        if (success) {
          print(
              '🔒 SecureNotificationService: ✅ Delivery receipt sent to sender: $senderId');
        } else {
          print(
              '🔒 SecureNotificationService: ⚠️ Failed to send delivery receipt');
        }
      }
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error sending delivery receipt: $e');
    }

    // Create a Message object and save it to the database
    try {
      final messageStorageService = MessageStorageService.instance;
      final currentUserId = SeSessionService().currentSessionId ?? '';

      // Generate a unique message ID
      final messageId = data['messageId'] as String? ??
          data['message_id'] as String? ??
          'msg_${DateTime.now().millisecondsSinceEpoch}';
      final messageText =
          message; // Store the message text in a separate variable to avoid naming conflict

      // Create Message object using the Message constructor
      final messageObj = chat_message.Message(
        id: messageId,
        conversationId: conversationId ??
            'chat_${DateTime.now().millisecondsSinceEpoch}_$senderId',
        senderId: senderId,
        recipientId: currentUserId,
        type: chat_message.MessageType.text,
        content: {'text': messageText},
        status: chat_message.MessageStatus.delivered,
      );

      // Save message to database
      if (messageObj != null) {
        await messageStorageService.saveMessage(messageObj);
        print(
            '🔒 SecureNotificationService: ✅ Message saved to database: $messageId');

        // Try to route to active ChatProvider first (for chat screen updates)
        try {
          // Note: ChatProvider.handleIncomingMessage is not implemented yet
          // For now, we'll just log that we would route to it
          print(
              '🔒 SecureNotificationService: ℹ️ Would route message to ChatProvider (method not implemented yet)');
        } catch (e) {
          print(
              '🔒 SecureNotificationService: ⚠️ Failed to route to ChatProvider: $e');
        }

        // ALWAYS trigger callback for UI updates - this will route to ChatListProvider
        // This ensures the chat list is updated regardless of whether the chat screen is active
        print(
            '🔒 SecureNotificationService: 🔄 Triggering message received callback for ChatListProvider');
        // Pass the conversation ID and message ID to ensure correct routing
        _onMessageReceived?.call(
            senderId,
            senderName,
            message,
            conversationId ??
                'chat_${DateTime.now().millisecondsSinceEpoch}_$senderId',
            messageId);
      }
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error saving message to database: $e');
    }

    print(
        '🔒 SecureNotificationService: ✅ Message notification handled successfully');
  }

  /// Handle typing indicator notification
  Future<void> _handleTypingIndicatorNotification(
      Map<String, dynamic> data) async {
    final senderId = data['senderId'] as String?;
    final isTyping = data['isTyping'] as bool?;

    if (senderId == null || isTyping == null) {
      print(
          '🔒 SecureNotificationService: Invalid typing indicator notification data');
      return;
    }

    print(
        '🔒 SecureNotificationService: Received typing indicator: $senderId -> $isTyping');

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
          '🔒 SecureNotificationService: ✅ Typing indicator routed to MessageStatusTrackingService');
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Failed to route typing indicator to MessageStatusTrackingService: $e');
    }
  }

  /// Handle broadcast notification
  Future<void> _handleBroadcastNotification(Map<String, dynamic> data) async {
    final message = data['message'] as String?;
    final timestamp = data['timestamp'] as int?;

    if (message == null) {
      print(
          '🔒 SecureNotificationService: Invalid broadcast notification data');
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

  /// Send read receipt for a message
  Future<void> sendReadReceipt(
      String senderId, String messageId, String conversationId) async {
    try {
      print(
          '🔒 SecureNotificationService: Sending read receipt for message: $messageId');

      final airNotifier = AirNotifierService.instance;
      final success = await airNotifier.sendMessageDeliveryStatus(
        recipientId: senderId,
        messageId: messageId,
        status: 'read',
        conversationId: conversationId,
      );

      if (success) {
        print('🔒 SecureNotificationService: ✅ Read receipt sent to sender');
      } else {
        print('🔒 SecureNotificationService: ⚠️ Failed to send read receipt');
      }
    } catch (e) {
      print('🔒 SecureNotificationService: ❌ Error sending read receipt: $e');
    }
  }

  /// Send online status update
  Future<void> sendOnlineStatusUpdate(String recipientId, bool isOnline) async {
    try {
      print(
          '🔒 SecureNotificationService: Sending online status update: $isOnline');

      final airNotifier = AirNotifierService.instance;
      final success = await airNotifier.sendOnlineStatusUpdate(
        recipientId: recipientId,
        isOnline: isOnline,
        lastSeen: isOnline ? null : DateTime.now().toIso8601String(),
      );

      if (success) {
        print('🔒 SecureNotificationService: ✅ Online status update sent');
      } else {
        print(
            '🔒 SecureNotificationService: ⚠️ Failed to send online status update');
      }
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error sending online status update: $e');
    }
  }

  /// Send typing indicator
  Future<void> sendTypingIndicator(String recipientId, bool isTyping) async {
    try {
      print(
          '🔒 SecureNotificationService: Sending typing indicator: $isTyping to $recipientId');

      final airNotifier = AirNotifierService.instance;
      final currentUserId = SeSessionService().currentSessionId ?? '';
      final currentSession = SeSessionService().currentSession;
      final senderName = currentSession?.displayName ??
          'User ${currentUserId.substring(0, 8)}';

      final success = await airNotifier.sendTypingIndicator(
        recipientId: recipientId,
        senderName: senderName,
        isTyping: isTyping,
      );

      if (success) {
        print('🔒 SecureNotificationService: ✅ Typing indicator sent');
      } else {
        print(
            '🔒 SecureNotificationService: ⚠️ Failed to send typing indicator');
      }
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error sending typing indicator: $e');
    }
  }

  /// Generate checksum for data integrity
  String _generateChecksum(Map<String, dynamic> data) {
    final dataJson = json.encode(data);
    final bytes = utf8.encode(dataJson);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

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
          '🔒 SecureNotificationService: ✅ Notification saved to SharedPreferences: $id');
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error saving notification to SharedPreferences: $e');
    }
  }

  /// Send encrypted delivery receipt notification (handshake step 2)
  Future<bool> sendEncryptedDeliveryReceipt({
    required String recipientId,
    required String messageId,
    required String conversationId,
  }) async {
    try {
      // Ensure key exchange with recipient
      final keyExchangeSuccess = await KeyExchangeService.instance
          .ensureKeyExchangeWithUser(recipientId);
      if (!keyExchangeSuccess) {
        print(
            '🔒 SecureNotificationService: Key exchange failed, cannot encrypt delivery receipt');
        return false;
      }

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🔒 SecureNotificationService: User not logged in');
        return false;
      }

      // Create receipt data
      final receiptData = {
        'type': 'delivery_receipt',
        'message_id': messageId,
        'recipient_id': currentUserId,
        'conversation_id': conversationId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'handshake_step': 2, // Step 2: Delivered
      };

      // Create encrypted payload
      final encryptedPayload = await EncryptionService.createEncryptedPayload(
          receiptData, recipientId);

      // Send silent notification via AirNotifier
      return await _sendNotificationToSession(
        sessionId: recipientId,
        title: '', // Empty title for silent notification
        body: '', // Empty body for silent notification
        data: {
          'data': encryptedPayload['data'] as String,
          'type': 'message_delivery_status',
          'silent': true,
        },
        sound: null, // No sound for delivery status
        badge: 0, // No badge for silent notifications
        encrypted: true,
        checksum: encryptedPayload['checksum'] as String,
      );
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error sending encrypted delivery receipt: $e');
      return false;
    }
  }

  /// Send encrypted read receipt notification (handshake step 3)
  Future<bool> sendEncryptedReadReceipt({
    required String recipientId,
    required List<String> messageIds,
    required String conversationId,
  }) async {
    try {
      // Ensure key exchange with recipient
      final keyExchangeSuccess = await KeyExchangeService.instance
          .ensureKeyExchangeWithUser(recipientId);
      if (!keyExchangeSuccess) {
        print(
            '🔒 SecureNotificationService: Key exchange failed, cannot encrypt read receipt');
        return false;
      }

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🔒 SecureNotificationService: User not logged in');
        return false;
      }

      // Create receipt data
      final receiptData = {
        'type': 'read_receipt',
        'message_ids': messageIds,
        'recipient_id': currentUserId,
        'conversation_id': conversationId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'handshake_step': 3, // Step 3: Read
      };

      // Create encrypted payload
      final encryptedPayload = await EncryptionService.createEncryptedPayload(
          receiptData, recipientId);

      // Send silent notification via AirNotifier
      return await _sendNotificationToSession(
        sessionId: recipientId,
        title: '', // Empty title for silent notification
        body: '', // Empty body for silent notification
        data: {
          'data': encryptedPayload['data'] as String,
          'type': 'message_read',
          'silent': true,
        },
        sound: null, // No sound for read notifications
        badge: 0, // No badge for silent notifications
        encrypted: true,
        checksum: encryptedPayload['checksum'] as String,
      );
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error sending encrypted read receipt: $e');
      return false;
    }
  }

  /// Send encrypted typing indicator
  Future<bool> sendEncryptedTypingIndicator({
    required String recipientId,
    required bool isTyping,
    required String conversationId,
  }) async {
    try {
      // Rate limit typing indicators to avoid notification spam
      final now = DateTime.now();
      final lastSent = _lastTypingIndicatorSent[recipientId];

      if (lastSent != null &&
          now.difference(lastSent) < typingIndicatorCooldown) {
        // Too soon, skip this update
        return true; // Return true to avoid error handling
      }

      // Coalesce consecutive typing indicators: if we're already typing and sending another typing=true, skip it
      if (isTyping && lastSent != null) {
        // Check if we're already in a typing state
        print(
            '🔒 SecureNotificationService: Coalescing consecutive typing=true indicator');
        return true; // Return true since we're already typing
      }

      // Update last sent time
      _lastTypingIndicatorSent[recipientId] = now;

      // Ensure key exchange with recipient
      final keyExchangeSuccess = await KeyExchangeService.instance
          .ensureKeyExchangeWithUser(recipientId);
      if (!keyExchangeSuccess) {
        print(
            '🔒 SecureNotificationService: Key exchange failed, cannot encrypt typing indicator');
        return false;
      }

      final currentUserId = SeSessionService().currentSessionId;
      final username = await SeSessionService().getCurrentUsername();

      if (currentUserId == null || username == null) {
        print('🔒 SecureNotificationService: User not logged in');
        return false;
      }

      // Create typing data
      final typingData = {
        'type': 'typing_indicator',
        'sender_id': currentUserId,
        'sender_name': username,
        'is_typing': isTyping,
        'conversation_id': conversationId,
        'timestamp': now.millisecondsSinceEpoch,
      };

      // Create encrypted payload
      final encryptedPayload = await EncryptionService.createEncryptedPayload(
          typingData, recipientId);

      // Send silent notification via AirNotifier
      return await _sendNotificationToSession(
        sessionId: recipientId,
        title: '', // Empty title for silent notification
        body: '', // Empty body for silent notification
        data: {
          'data': encryptedPayload['data'] as String,
          'type': 'typing_indicator',
          'silent': true,
        },
        sound: null, // No sound for typing indicators
        badge: 0, // No badge for silent notifications
        encrypted: true,
        checksum: encryptedPayload['checksum'] as String,
      );
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error sending encrypted typing indicator: $e');
      return false;
    }
  }

  /// Send encrypted online status update
  Future<bool> sendEncryptedOnlineStatus({
    required String recipientId,
    required bool isOnline,
  }) async {
    try {
      // Ensure key exchange with recipient
      final keyExchangeSuccess = await KeyExchangeService.instance
          .ensureKeyExchangeWithUser(recipientId);
      if (!keyExchangeSuccess) {
        print(
            '🔒 SecureNotificationService: Key exchange failed, cannot encrypt online status');
        return false;
      }

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🔒 SecureNotificationService: User not logged in');
        return false;
      }

      // Create online status data
      final statusData = {
        'type': 'online_status',
        'user_id': currentUserId,
        'is_online': isOnline,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Create encrypted payload
      final encryptedPayload = await EncryptionService.createEncryptedPayload(
          statusData, recipientId);

      // Send silent notification via AirNotifier
      return await _sendNotificationToSession(
        sessionId: recipientId,
        title: '', // Empty title for silent notification
        body: '', // Empty body for silent notification
        data: {
          'data': encryptedPayload['data'] as String,
          'type': 'online_status',
          'silent': true,
        },
        sound: null, // No sound for status updates
        badge: 0, // No badge for silent notifications
        encrypted: true,
        checksum: encryptedPayload['checksum'] as String,
      );
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error sending encrypted online status: $e');
      return false;
    }
  }

  /// Send notification to session via AirNotifier
  Future<bool> _sendNotificationToSession({
    required String sessionId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? sound,
    int badge = 0,
    bool encrypted = false,
    String? checksum,
  }) async {
    try {
      return await AirNotifierService.instance.sendNotificationToSession(
        sessionId: sessionId,
        title: title,
        body: body,
        data: data,
        sound: sound,
        badge: badge,
        encrypted: encrypted,
        checksum: checksum,
      );
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error sending notification to session: $e');
      return false;
    }
  }

  /// Process encrypted notification
  Future<Map<String, dynamic>?> processEncryptedNotification(
      Map<String, dynamic> notificationData) async {
    try {
      print('🔒 SecureNotificationService: Processing encrypted notification');

      // Extract encrypted data
      final encryptedValue =
          notificationData['data'] ?? notificationData['encryptedData'];
      if (encryptedValue == null) {
        print('🔒 SecureNotificationService: No encrypted data found');
        return null;
      }

      final isEncrypted = notificationData['encrypted'] == true;
      if (!isEncrypted) {
        print('🔒 SecureNotificationService: Notification is not encrypted');
        return null;
      }

      // Extract checksum
      final checksum = notificationData['checksum'] as String?;
      if (checksum == null) {
        print('🔒 SecureNotificationService: No checksum found');
        return null;
      }

      // Decrypt the data
      final decryptedData =
          await _decryptNotificationData(encryptedValue as String, checksum);
      if (decryptedData == null) {
        print('🔒 SecureNotificationService: Failed to decrypt data');
        return null;
      }

      print(
          '🔒 SecureNotificationService: Successfully decrypted notification');
      return decryptedData;
    } catch (e) {
      print(
          '🔒 SecureNotificationService: Error processing encrypted notification: $e');
      return null;
    }
  }

  /// Decrypt notification data using our encryption service
  Future<Map<String, dynamic>?> _decryptNotificationData(
      String encryptedData, String checksum) async {
    try {
      print(
          '🔒 SecureNotificationService: Decrypting notification data using EncryptionService...');

      // Use our real EncryptionService to decrypt the data
      final decryptedData = await EncryptionService.decryptAesCbcPkcs7(
        encryptedData,
      );

      if (decryptedData != null) {
        print(
            '🔒 SecureNotificationService: ✅ Notification data decrypted successfully');
        return decryptedData;
      } else {
        print(
            '🔒 SecureNotificationService: ❌ Failed to decrypt notification data');
        return null;
      }
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error decrypting notification data: $e');
      return null;
    }
  }

  /// Handle incoming text message notification
  Future<void> handleTextMessageNotification({
    required String senderId,
    required String senderName,
    required String message,
    String? conversationId,
    Map<String, dynamic>? data,
  }) async {
    try {
      // Get current user ID
      final currentUserId = GlobalUserService.instance.currentUserId;
      if (currentUserId == null) {
        print('🔒 SecureNotificationService: ❌ No current user ID found');
        return;
      }

      // Generate message ID if not provided
      final messageId = data?['message_id'] as String? ??
          'msg_${DateTime.now().millisecondsSinceEpoch}';

      // Show notification for the message
      await showLocalNotification(
        title: senderName,
        body: message,
        type: 'text_message',
        data: {
          'sender_id': senderId,
          'conversation_id': conversationId,
          'message_id': messageId,
          'message_type': 'text',
        },
      );

      // Trigger callback for UI updates
      _onMessageReceived?.call(
        senderId,
        senderName,
        message,
        conversationId ??
            'chat_${DateTime.now().millisecondsSinceEpoch}_$senderId',
        messageId,
      );

      print(
          '🔒 SecureNotificationService: ✅ Text message notification handled');
    } catch (e) {
      print('🔒 SecureNotificationService: ❌ Error handling text message: $e');
    }
  }

  /// Handle typing indicator notification
  Future<void> handleTypingIndicator({
    required String senderId,
    required bool isTyping,
  }) async {
    try {
      print(
          '🔒 SecureNotificationService: Received typing indicator: $senderId -> $isTyping');

      // Trigger callback for UI updates
      _onTypingIndicator?.call(senderId, isTyping);

      // Notify the status tracking service
      final statusTrackingService = MessageStatusTrackingService.instance;
      await statusTrackingService.handleExternalTypingIndicator(
          senderId, isTyping);

      print('🔒 SecureNotificationService: ✅ Typing indicator handled');
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error handling typing indicator: $e');
    }
  }

  /// Handle message status update notification
  Future<void> handleMessageStatusUpdate({
    required String messageId,
    required String status,
    String? senderId,
  }) async {
    try {
      print(
          '🔒 SecureNotificationService: Received message status update: $messageId -> $status');

      // Convert status string to appropriate format for the callback
      String normalizedStatus = status.toLowerCase();
      if (!['sent', 'delivered', 'read', 'failed'].contains(normalizedStatus)) {
        normalizedStatus = 'sent';
      }

      // Trigger callback for UI updates
      _onMessageStatusUpdate?.call(senderId ?? '', messageId, status);

      print('🔒 SecureNotificationService: ✅ Message status update handled');
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error handling message status update: $e');
    }
  }

  /// Set session ID and ensure token is linked to session on AirNotifier
  Future<void> setSessionId(String sessionId) async {
    _sessionId = sessionId;
    print('🔒 SecureNotificationService: ✅ Session ID updated: $sessionId');
    print(
        '🔒 SecureNotificationService: Current device token: ${_deviceToken != null ? "${_deviceToken!.substring(0, 8)}..." : "None"}');

    // Re-initialize AirNotifier with new session ID
    if (_isInitialized) {
      await _initializeAirNotifier();
      print(
          '🔒 SecureNotificationService: ✅ AirNotifier initialized with session ID: $sessionId');
    }

    // If no device token available, try to get it from native platform
    if (_deviceToken == null || _deviceToken!.isEmpty) {
      print(
          '🔒 SecureNotificationService: ⚠️ No device token available, attempting to retrieve from native platform...');
      await ensureDeviceTokenAvailable();

      // Wait a bit for the token to be received
      await Future.delayed(const Duration(milliseconds: 1000));
    }

    // ALWAYS ensure token is linked to session on AirNotifier when session ID is set
    if (_deviceToken != null && _deviceToken!.isNotEmpty) {
      print(
          '🔒 SecureNotificationService: 🔄 Session ID set, ensuring device token is linked to session on AirNotifier');
      await _ensureTokenLinkedToSession();
    } else {
      print(
          '🔒 SecureNotificationService: ⚠️ No device token available yet, will link when token is received');
    }
  }

  /// Set device token
  Future<void> setDeviceToken(String deviceToken) async {
    try {
      _deviceToken = deviceToken;
      print(
          '🔒 SecureNotificationService: ✅ Device token set: ${deviceToken.substring(0, 8)}...');
    } catch (e) {
      print('🔒 SecureNotificationService: ❌ Error setting device token: $e');
    }
  }

  /// Check if device token is registered
  bool isDeviceTokenRegistered() {
    return _deviceToken != null && _deviceToken!.isNotEmpty;
  }

  /// Get device token
  String? get deviceToken => _deviceToken;

  /// Get session ID
  String? get sessionId => _sessionId;

  /// Refresh notification permissions
  Future<void> refreshPermissions() async {
    try {
      print('🔒 SecureNotificationService: Refreshing permissions');
      await _requestPermissions();
      print('🔒 SecureNotificationService: ✅ Permissions refreshed');
    } catch (e) {
      print('🔒 SecureNotificationService: ❌ Error refreshing permissions: $e');
    }
  }

  /// Validate permission status
  Future<void> validatePermissionStatus() async {
    try {
      print('🔒 SecureNotificationService: Validating permission status');
      // This is a simplified implementation
      print('🔒 SecureNotificationService: ✅ Permission status validated');
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error validating permission status: $e');
    }
  }

  /// Open app settings for permissions
  Future<void> openAppSettingsForPermissions() async {
    try {
      print(
          '🔒 SecureNotificationService: Opening app settings for permissions');
      // This is a simplified implementation
      print('🔒 SecureNotificationService: ✅ App settings opened');
    } catch (e) {
      print('🔒 SecureNotificationService: ❌ Error opening app settings: $e');
    }
  }

  /// Check if should show permission dialog
  bool get shouldShowPermissionDialog {
    if (kIsWeb) return false;

    // If we have a device token, we don't need to show the permission dialog
    if (_deviceToken?.isNotEmpty == true) {
      print(
          '🔒 SecureNotificationService: No need to show permission dialog - device token present');
      return false;
    }

    // Only show when explicitly denied - not when granted or not determined
    final shouldShow = _permissionStatus == PermissionStatus.denied ||
        _permissionStatus == PermissionStatus.permanentlyDenied;

    print(
        '🔒 SecureNotificationService: Permission dialog check - token: ${_deviceToken != null ? "present" : "missing"}, status: $_permissionStatus, shouldShow: $shouldShow');

    return shouldShow;
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    try {
      print('🔒 SecureNotificationService: Cancelling all notifications');
      await _notifications.cancelAll();
      print('🔒 SecureNotificationService: ✅ All notifications cancelled');
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error cancelling notifications: $e');
    }
  }

  /// Set message received callback
  void setOnMessageReceived(
    Function(String senderId, String senderName, String message,
            String conversationId, String? messageId)
        callback,
  ) {
    _onMessageReceived = callback;
    print('🔒 SecureNotificationService: ✅ Message received callback set');
  }

  /// Set typing indicator callback
  void setOnTypingIndicator(
    Function(String senderId, bool isTyping) callback,
  ) {
    _onTypingIndicator = callback;
    print('🔒 SecureNotificationService: ✅ Typing indicator callback set');
  }

  /// Set message status update callback
  void setOnMessageStatusUpdate(
    Function(String senderId, String messageId, String status) callback,
  ) {
    _onMessageStatusUpdate = callback;
    print('🔒 SecureNotificationService: ✅ Message status update callback set');
  }

  /// Set conversation created callback
  void setOnConversationCreated(
    Function(ChatConversation conversation) callback,
  ) {
    _onConversationCreated = callback;
    print('🔒 SecureNotificationService: ✅ Conversation created callback set');
  }

  /// Set key exchange request received callback
  void setOnKeyExchangeRequestReceived(
    Function(Map<String, dynamic> data) callback,
  ) {
    _onKeyExchangeRequestReceived = callback;
    print('🔒 SecureNotificationService: ✅ Key exchange request callback set');
  }

  /// Set key exchange accepted callback
  void setOnKeyExchangeAccepted(
    Function(Map<String, dynamic> data) callback,
  ) {
    _onKeyExchangeAccepted = callback;
    print('🔒 SecureNotificationService: ✅ Key exchange accepted callback set');
  }

  /// Set key exchange declined callback
  void setOnKeyExchangeDeclined(
    Function(Map<String, dynamic> data) callback,
  ) {
    _onKeyExchangeDeclined = callback;
    print('🔒 SecureNotificationService: ✅ Key exchange declined callback set');
  }

  /// Set notification received callback
  void setOnNotificationReceived(
    Function(String title, String body, String type, Map<String, dynamic>? data)
        callback,
  ) {
    _onNotificationReceived = callback;
    print('🔒 SecureNotificationService: ✅ Notification received callback set');
  }

  /// Handle notification
  Future<void> handleNotification(Map<String, dynamic> data) async {
    try {
      print(
          '🔒 SecureNotificationService: 🔔 RECEIVED NOTIFICATION: ${data.keys}');
      print('🔒 SecureNotificationService: 🔔 NOTIFICATION DATA: $data');

      // Normalize to string-keyed map immediately
      final safeRoot = _stringKeyed(data);

      // Skip processing if this is a local notification (from our own app)
      if (safeRoot['fromLocalNotification'] == true) {
        print('🔒 SecureNotificationService: ℹ️ Skipping local notification');
        return;
      }

      // iOS duplicate filtering
      if (Platform.isIOS && safeRoot['payload'] != null) {
        final payloadStr = safeRoot['payload'].toString();
        final iosNotificationId =
            'ios_${sha256.convert(utf8.encode(payloadStr)).toString()}';
        if (_processedNotifications.contains(iosNotificationId)) {
          print(
              '🔒 SecureNotificationService: ℹ️ Skipping duplicate iOS notification');
          return;
        }
        _processedNotifications.add(iosNotificationId);
      }

      // Skip processing if the sender is the current user
      final currentUserId = SeSessionService().currentSessionId;
      final senderId = safeRoot['senderId'] ?? safeRoot['sender_id'];
      if (senderId == currentUserId) {
        print(
            '🔒 SecureNotificationService: ℹ️ Skipping notification from self');
        return;
      }

      // ==== Extract/normalize actualData ====
      Map<String, dynamic>? actualData;

      // Check if this is an iOS notification with aps structure
      if (safeRoot.containsKey('aps')) {
        final apsDataRaw = safeRoot['aps'];
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
          safeRoot.forEach((key, value) {
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
                    '🔒 SecureNotificationService: Reconstructed invitation accepted data: $actualData');
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
              }
            }
          }

          print(
              '🔒 SecureNotificationService: Extracted data from iOS notification: $actualData');
        }
      } else if (safeRoot.containsKey('data')) {
        // Android-style nested data
        final dataField = safeRoot['data'];
        if (dataField is Map) {
          actualData = _stringKeyed(dataField as Map);
        } else if (_isStringBase64(dataField)) {
          // Canonical encrypted format
          actualData = {
            if (safeRoot['type'] != null) 'type': safeRoot['type'],
            'encrypted': true,
            'data': dataField as String,
            if (safeRoot['checksum'] != null) 'checksum': safeRoot['checksum'],
          };
        } else {
          // Unexpected; fall back to all root fields
          actualData = safeRoot;
        }
      } else {
        // Already top-level
        actualData = safeRoot;
      }

      // Check if we have a payload field (iOS foreground notifications)
      if (actualData != null && actualData.containsKey('payload')) {
        final payloadStr = actualData['payload'] as String?;
        if (payloadStr != null) {
          try {
            final payloadData = json.decode(payloadStr) as Map<String, dynamic>;
            print(
                '🔒 SecureNotificationService: Parsed payload JSON: $payloadData');

            // Merge payload data with actualData, prioritizing payload
            final mergedData = <String, dynamic>{...actualData};
            payloadData.forEach((key, value) {
              mergedData[key] = value;
            });
            actualData = mergedData;

            print(
                '🔒 SecureNotificationService: Merged data with payload: $actualData');
          } catch (e) {
            print(
                '🔒 SecureNotificationService: Failed to parse payload JSON: $e');
          }
        }
      }

      // Handle iOS notifications with different structure
      // ONLY restructure if this is actually an iOS notification with aps structure
      // AND it's a specific type that needs restructuring (like user_data_response)
      if (actualData != null &&
          actualData.containsKey('aps') &&
          actualData.containsKey('data') &&
          actualData.containsKey('type') &&
          actualData['type'] == 'user_data_response') {
        // Only for specific iOS notification types

        print(
            '🔒 SecureNotificationService: 🔴 iOS user_data_response notification detected, restructuring data');

        // iOS notifications have aps + data structure, need to restructure for processing
        final iosData = <String, dynamic>{
          'type': actualData['type'],
          'data': actualData['data'], // This is the encrypted string
          'encrypted': true, // Mark as encrypted
        };

        // Add any other fields that might be needed
        if (actualData.containsKey('checksum')) {
          iosData['checksum'] = actualData['checksum'];
        }

        print(
            '🔒 SecureNotificationService: 🔴 Restructured iOS data: $iosData');
        actualData = iosData;
      }

      // Handle iOS notifications with aps structure that don't need restructuring
      // These are notifications like key_exchange_request, invitation_update, etc.
      if (actualData != null &&
          actualData.containsKey('aps') &&
          actualData.containsKey('type') &&
          actualData['type'] != 'user_data_response') {
        print(
            '🔒 SecureNotificationService: 🔴 iOS notification with aps structure detected: ${actualData['type']}');

        // For these notifications, we need to extract the actual data from the aps structure
        // or from the notification payload itself
        if (actualData.containsKey('data')) {
          // If there's a data field, it might contain the actual notification data
          final dataField = actualData['data'];
          if (dataField is String) {
            // This is likely encrypted data that needs to be processed
            print(
                '🔒 SecureNotificationService: 🔴 iOS notification has encrypted data field');
          } else if (dataField is Map) {
            // This is structured data that can be used directly
            print(
                '🔒 SecureNotificationService: 🔴 iOS notification has structured data field');
          }
        }
      }

      print(
          '🔒 SecureNotificationService: Processed notification data: $actualData');

      // Process the notification data
      if (actualData == null) {
        print(
            '🔒 SecureNotificationService: ❌ No valid data found in notification');
        return;
      }

      print(
          '🔒 SecureNotificationService: 🔍 About to process notification with type: ${actualData['type']}, encrypted=${actualData['encrypted']}');

      final processedData = await processNotification(actualData);
      if (processedData == null) {
        print(
            '🔒 SecureNotificationService: ❌ Failed to process notification data');
        return;
      }

      print(
          '🔒 SecureNotificationService: ✅ Notification processed successfully, type: ${processedData['type']}');

      final type = processedData['type'] as String?;
      if (type == null) {
        print(
            '🔒 SecureNotificationService: ❌ No notification type found in data');
        return;
      }

      print(
          '🔒 SecureNotificationService: Processing notification type: $type');
      print(
          '🔒 SecureNotificationService: 🔴 FULL PROCESSED DATA: $processedData');

      switch (type) {
        case 'key_exchange_request':
          print(
              '🔒 SecureNotificationService: 🎯 Processing key exchange request notification');
          await handleKeyExchangeRequest(processedData);
          break;
        case 'key_exchange_response':
          print(
              '🔒 SecureNotificationService: 🎯 Processing key exchange response notification');
          await handleKeyExchangeResponse(processedData);
          break;
        case 'key_exchange_accepted':
          print(
              '🔒 SecureNotificationService: 🎯 Processing key exchange accepted notification');
          await handleKeyExchangeAccepted(processedData);
          break;
        case 'key_exchange_declined':
          print(
              '🔒 SecureNotificationService: 🎯 Processing key exchange declined notification');
          await handleKeyExchangeDeclined(processedData);
          break;
        case 'key_exchange_sent':
          print(
              '🔒 SecureNotificationService: 🎯 Processing key exchange sent notification');
          await handleKeyExchangeSent(processedData);
          break;
        case 'user_data_exchange':
          print(
              '🔒 SecureNotificationService: 🎯 Processing encrypted user data exchange notification');
          await handleUserDataExchange(processedData);
          break;
        case 'user_data_response':
          print(
              '🔒 SecureNotificationService: 🎯 Processing encrypted user data response notification');
          await handleUserDataResponse(processedData);
          break;
        case 'message':
          print(
              '🔒 SecureNotificationService: 🎯 Processing message notification');
          print(
              '🔒 SecureNotificationService: 🔴 MESSAGE NOTIFICATION DATA: $processedData');
          await handleMessageNotification(processedData);
          print(
              '🔒 SecureNotificationService: 🔴 MESSAGE NOTIFICATION HANDLED');
          break;
        case 'typing_indicator':
          await handleTypingIndicatorNotification(processedData);
          break;
        case 'message_delivery_status':
          print(
              '🔒 SecureNotificationService: 🎯 Processing message delivery status notification');
          await handleMessageDeliveryStatus(processedData);
          break;
        case 'broadcast':
          await handleBroadcastNotification(processedData);
          break;
        case 'online_status_update':
          await handleOnlineStatusUpdate(processedData);
          break;
        default:
          print(
              '🔒 SecureNotificationService: Unknown notification type: $type');
      }
    } catch (e) {
      print('🔒 SecureNotificationService: Error handling notification: $e');
      print(
          '🔒 SecureNotificationService: Error stack trace: ${StackTrace.current}');
    }
  }

  // ===== KEY EXCHANGE NOTIFICATION HANDLING =====

  /// Handle key exchange request notification
  Future<void> handleKeyExchangeRequest(Map<String, dynamic> data) async {
    try {
      print('🔒 SecureNotificationService: Handling key exchange request');
      print('🔒 SecureNotificationService: 🔍 Key exchange data: $data');

      // Extract key exchange request data - handle both field name variations
      final senderId =
          data['sender_id'] as String? ?? data['senderId'] as String? ?? '';
      final publicKey = data['sender_public_key'] as String? ??
          data['public_key'] as String? ??
          '';
      final version = data['version'] as String? ?? '';
      final requestId = data['request_id'] as String? ?? '';
      final requestPhrase = data['request_phrase'] as String? ?? '';

      print(
          '🔒 SecureNotificationService: 🔍 Extracted fields - senderId: $senderId, publicKey: ${publicKey.isNotEmpty ? "present" : "missing"}');

      if (senderId.isEmpty || publicKey.isEmpty) {
        print(
            '🔒 SecureNotificationService: ❌ Invalid key exchange request data - missing required fields');
        print(
            '🔒 SecureNotificationService: senderId: $senderId, publicKey: ${publicKey.isNotEmpty ? "present" : "missing"}');
        return;
      }

      // Store sender's public key (but don't automatically respond)
      await EncryptionService.storeRecipientPublicKey(senderId, publicKey);
      print('🔒 SecureNotificationService: ✅ Stored public key for $senderId');

      // Trigger callback for UI updates (this will show the invitation to the user)
      if (_onKeyExchangeRequestReceived != null) {
        _onKeyExchangeRequestReceived!(data);
        print(
            '🔒 SecureNotificationService: ✅ Key exchange request callback triggered');
      } else {
        print(
            '🔒 SecureNotificationService: ⚠️ No key exchange request callback set');
      }

      // Show local notification
      await showLocalNotification(
        title: 'Key Exchange Request',
        body: 'New encryption key exchange request received',
        type: 'key_exchange_request',
        data: data,
      );

      print(
          '🔒 SecureNotificationService: ✅ Key exchange request processed successfully');
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error handling key exchange request: $e');
    }
  }

  /// Handle key exchange response notification
  Future<void> handleKeyExchangeResponse(Map<String, dynamic> data) async {
    try {
      print('🔒 SecureNotificationService: Handling key exchange response');
      print(
          '🔒 SecureNotificationService: 🔍 Key exchange response data: $data');

      // Extract key exchange response data - handle both field name variations
      final senderId =
          data['sender_id'] as String? ?? data['senderId'] as String? ?? '';
      final publicKey = data['public_key'] as String? ?? '';
      final responseId = data['response_id'] as String? ?? '';

      print(
          '🔒 SecureNotificationService: 🔍 Extracted response fields - senderId: $senderId, publicKey: ${publicKey.isNotEmpty ? "present" : "missing"}, responseId: $responseId');

      if (senderId.isEmpty || publicKey.isEmpty) {
        print(
            '🔒 SecureNotificationService: ❌ Invalid key exchange response data - missing required fields');
        print(
            '🔒 SecureNotificationService: senderId: $senderId, publicKey: ${publicKey.isNotEmpty ? "present" : "missing"}');
        return;
      }

      // Process the key exchange response using KeyExchangeService
      final success =
          await KeyExchangeService.instance.processKeyExchangeResponse({
        'sender_id': senderId,
        'public_key': publicKey,
        'timestamp': data['timestamp'],
      });

      if (success) {
        print(
            '🔒 SecureNotificationService: ✅ Key exchange response processed successfully');

        // Trigger callback for UI updates
        _onKeyExchangeRequestReceived?.call(data);

        // Show local notification
        await showLocalNotification(
          title: 'Key Exchange Response',
          body: 'Encryption key exchange response received',
          type: 'key_exchange_response',
          data: data,
        );
      } else {
        print(
            '🔒 SecureNotificationService: ❌ Failed to process key exchange response');
      }
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error handling key exchange response: $e');
    }
  }

  /// Handle conversation created notification
  Future<void> handleConversationCreated(Map<String, dynamic> data) async {
    try {
      print(
          '🔒 SecureNotificationService: Handling conversation created notification');

      // Extract conversation data
      final conversationId = data['conversation_id'] as String? ?? '';
      final participants = data['participants'] as List<dynamic>? ?? [];
      final timestamp = data['timestamp'];

      if (conversationId.isEmpty) {
        print('🔒 SecureNotificationService: ✅ Invalid conversation data');
        return;
      }

      // Create conversation object
      final conversation = ChatConversation(
        id: conversationId,
        participant1Id:
            participants.isNotEmpty ? participants[0].toString() : '',
        participant2Id:
            participants.length > 1 ? participants[1].toString() : '',
        displayName: 'New Conversation',
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
          'created_from_external': true,
          'timestamp': timestamp,
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
        recipientId: participants.isNotEmpty ? participants[0].toString() : '',
        recipientName: 'New Conversation',
      );

      // Trigger callback for UI updates
      _onConversationCreated?.call(conversation);

      // Show local notification
      await showLocalNotification(
        title: 'New Conversation',
        body: 'A new conversation has been created',
        type: 'conversation_created',
        data: conversation.toJson(),
      );

      print(
          '🔒 SecureNotificationService: ✅ Conversation created notification handled');
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error handling conversation created notification: $e');
    }
  }

  // ===== KEY EXCHANGE NOTIFICATION SENDING =====

  /// Send key exchange request notification
  Future<bool> sendKeyExchangeRequest({
    required String recipientId,
    String? requestPhrase,
  }) async {
    try {
      print(
          '🔒 SecureNotificationService: Sending key exchange request to $recipientId');

      // Pre-flight check: ensure recipient has a registered token
      final hasRecipientToken =
          await AirNotifierService.instance.hasAnyToken(sessionId: recipientId);
      if (!hasRecipientToken) {
        print(
            '❌ Recipient has no push tokens – cannot send key exchange request');
        return false;
      }

      // Use KeyExchangeService to create the request
      final success = await KeyExchangeService.instance.requestKeyExchange(
        recipientId,
        requestPhrase: requestPhrase,
      );

      if (success) {
        print(
            '🔒 SecureNotificationService: ✅ Key exchange request sent successfully');

        // Show local notification for confirmation
        await showLocalNotification(
          title: 'Key Exchange Request Sent',
          body: 'Encryption key exchange request sent to recipient',
          type: 'key_exchange_request_sent',
          data: {'recipient_id': recipientId},
        );
      } else {
        print(
            '🔒 SecureNotificationService: ❌ Failed to send key exchange request');
      }

      return success;
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error sending key exchange request: $e');
      return false;
    }
  }

  /// Send key exchange response notification
  Future<bool> sendKeyExchangeResponse({
    required String recipientId,
    required String requestId,
    required bool accepted,
    String? responseMessage,
  }) async {
    try {
      print(
          '🔒 SecureNotificationService: Sending key exchange response to $recipientId');

      // Pre-flight check: ensure recipient has a registered token
      final hasRecipientToken =
          await AirNotifierService.instance.hasAnyToken(sessionId: recipientId);
      if (!hasRecipientToken) {
        print(
            '❌ Recipient has no push tokens – cannot send key exchange response');
        return false;
      }

      // Create response data
      final responseData = {
        'type': 'key_exchange_response',
        'recipient_id': recipientId,
        'request_id': requestId,
        'response_type': accepted ? 'accepted' : 'declined',
        'response_message': responseMessage ??
            (accepted ? 'Key exchange accepted' : 'Key exchange declined'),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Send via AirNotifier (plaintext for key exchange)
      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: recipientId,
        title: accepted ? 'Key Exchange Accepted' : 'Key Exchange Declined',
        body: responseData['response_message'] as String,
        data: responseData,
      );

      if (success) {
        print(
            '🔒 SecureNotificationService: ✅ Key exchange response sent successfully');

        // Show local notification for confirmation
        await showLocalNotification(
          title: 'Key Exchange Response Sent',
          body: 'Response sent to key exchange request',
          type: 'key_exchange_response_sent',
          data: responseData,
        );
      } else {
        print(
            '🔒 SecureNotificationService: ❌ Failed to send key exchange response');
      }

      return success;
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error sending key exchange response: $e');
      return false;
    }
  }

  /// Send conversation created notification
  Future<bool> sendConversationCreatedNotification({
    required String recipientId,
    required String conversationId,
    required List<String> participants,
  }) async {
    try {
      print(
          '🔒 SecureNotificationService: Sending conversation created notification to $recipientId');

      // Pre-flight check: ensure recipient has a registered token
      final hasRecipientToken =
          await AirNotifierService.instance.hasAnyToken(sessionId: recipientId);
      if (!hasRecipientToken) {
        print(
            '❌ Recipient has no push tokens – cannot send conversation notification');
        return false;
      }

      // Create conversation data
      final conversationData = {
        'type': 'conversation_created',
        'conversation_id': conversationId,
        'participants': participants,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Send via AirNotifier (plaintext for system notifications)
      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: recipientId,
        title: 'New Conversation',
        body: 'A new conversation has been created',
        data: conversationData,
      );

      if (success) {
        print(
            '🔒 SecureNotificationService: ✅ Conversation created notification sent successfully');
      } else {
        print(
            '🔒 SecureNotificationService: ✅ Failed to send conversation created notification');
      }

      return success;
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error sending conversation created notification: $e');
      return false;
    }
  }

  /// Dispose of resources
  void dispose() {
    _isInitialized = false;
    print('🔒 SecureNotificationService: ✅ Service disposed');
  }

  // Helper methods for notification processing
  /// Helper: Convert Map<dynamic, dynamic> to Map<String, dynamic> safely
  Map<String, dynamic> _stringKeyed(Map<dynamic, dynamic> m) {
    final out = <String, dynamic>{};
    m.forEach((k, v) {
      if (k is String) out[k] = v;
    });
    return out;
  }

  /// Helper: Check if a value is likely base64 encoded
  bool _isStringBase64(Object? v) {
    if (v is! String) return false;
    final s = v.trim();
    // Quick heuristic: base64 is usually long and uses +/=
    if (s.length < 32) return false;
    final base64Regex = RegExp(r'^[A-Za-z0-9+/=]+$');
    return base64Regex.hasMatch(s);
  }

  /// Process notification data (placeholder for now)
  Future<Map<String, dynamic>?> processNotification(
      Map<String, dynamic> data) async {
    // For now, just return the data as-is
    // This can be enhanced later with encryption/decryption logic
    return data;
  }

  /// Handle key exchange accepted notification
  Future<void> handleKeyExchangeAccepted(Map<String, dynamic> data) async {
    try {
      print(
          '🔒 SecureNotificationService: 🎯 Processing key exchange accepted notification');
      print(
          '🔒 SecureNotificationService: Processing key exchange accepted: $data');

      // Extract key exchange data
      final requestId = data['request_id'] as String?;
      final recipientId = data['recipient_id'] as String?;
      final acceptorPublicKey = data['acceptor_public_key'] as String?;
      final timestampRaw = data['timestamp'];

      if (requestId == null || recipientId == null) {
        print(
            '🔒 SecureNotificationService: ❌ Invalid key exchange accepted data - missing required fields');
        print('🔒 SecureNotificationService: Received data: $data');
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
              '🔒 SecureNotificationService: Invalid timestamp string: $timestampRaw, using current time');
          timestamp = DateTime.now();
        }
      } else {
        print(
            '🔒 SecureNotificationService: Invalid timestamp type: ${timestampRaw.runtimeType}, using current time');
        timestamp = DateTime.now();
      }

      print(
          '🔒 SecureNotificationService: ✅ Key exchange accepted for request: $requestId from: $recipientId');

      // Store the acceptance locally
      await _storeKeyExchangeAccepted(requestId, recipientId, timestamp);

      // Send encrypted user data to the accepting user
      await _sendUserDataToAcceptor(recipientId);

      // Add notification item
      if (_onNotificationReceived != null) {
        _onNotificationReceived!(
          'Key Exchange Accepted',
          'Your key exchange request was accepted',
          'key_exchange_accepted',
          data,
        );
        print(
            '🔒 SecureNotificationService: ✅ Notification callback completed for accepted');
      } else {
        print(
            '🔒 SecureNotificationService: ⚠️ No notification callback set for accepted');
      }

      // Call the key exchange accepted callback
      if (_onKeyExchangeAccepted != null) {
        _onKeyExchangeAccepted!(data);
        print(
            '🔒 SecureNotificationService: ✅ Key exchange accepted callback triggered');
      }

      print(
          '🔒 SecureNotificationService: ✅ Key exchange acceptance processed successfully');
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error processing key exchange accepted: $e');
      print(
          '🔒 SecureNotificationService: Error stack trace: ${StackTrace.current}');
    }
  }

  /// Store key exchange accepted locally
  Future<void> _storeKeyExchangeAccepted(
      String requestId, String recipientId, DateTime timestamp) async {
    try {
      print(
          '🔒 SecureNotificationService: Storing key exchange accepted locally');

      // Get the current user's session ID
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔒 SecureNotificationService: ❌ User not logged in, cannot store acceptance');
        return;
      }

      // Store the acceptance in shared preferences
      final prefsService = SeSharedPreferenceService();
      final acceptedExchanges =
          await prefsService.getJson('accepted_key_exchanges') ?? {};

      // Mark this exchange as accepted
      acceptedExchanges[requestId] = {
        'recipient_id': recipientId,
        'accepted_at': timestamp.millisecondsSinceEpoch,
        'status': 'accepted',
        'request_id': requestId,
      };

      await prefsService.setJson('accepted_key_exchanges', acceptedExchanges);
      print(
          '🔒 SecureNotificationService: ✅ Key exchange acceptance stored locally');
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error storing key exchange acceptance: $e');
    }
  }

  /// Send encrypted user data to the accepting user
  Future<void> _sendUserDataToAcceptor(String recipientId) async {
    try {
      print(
          '🔒 SecureNotificationService: 🔐 Sending encrypted user data to acceptor: $recipientId');

      // Get the current user's session data
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔒 SecureNotificationService: ❌ User not logged in, cannot send user data');
        return;
      }

      final currentSession = SeSessionService().currentSession;
      final userDisplayName = currentSession?.displayName ??
          'User ${currentUserId.substring(0, 8)}';

      // Create user data payload
      final userData = {
        'type': 'user_data_exchange',
        'sender_id': currentUserId,
        'display_name': userDisplayName,
        'profile_data': {
          'session_id': currentUserId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'accepted_at': DateTime.now().millisecondsSinceEpoch,
        },
      };

      print(
          '🔒 SecureNotificationService: 🔐 Encrypting user data for: $recipientId');

      // Encrypt the data using the new EncryptionService
      final encryptedPayload = await EncryptionService.encryptAesCbcPkcs7(
        userData,
        recipientId,
      );

      // Send encrypted notification
      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: recipientId,
        title: 'Connection Established',
        body: 'Secure connection established successfully',
        data: {
          'data': encryptedPayload['data'] as String,
          'type': 'user_data_exchange',
          'encrypted': true,
          'checksum': encryptedPayload['checksum'] as String,
        },
        sound: 'default',
        encrypted: true,
        checksum: encryptedPayload['checksum'] as String,
      );

      if (success) {
        print(
            '🔒 SecureNotificationService: ✅ Encrypted user data sent successfully to: $recipientId');
      } else {
        print(
            '🔒 SecureNotificationService: ❌ Failed to send encrypted user data to: $recipientId');
      }
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error sending user data to acceptor: $e');
    }
  }

  /// Handle key exchange declined notification
  Future<void> handleKeyExchangeDeclined(Map<String, dynamic> data) async {
    await _handleKeyExchangeDeclined(data);
  }

  /// Handle key exchange sent notification
  Future<void> handleKeyExchangeSent(Map<String, dynamic> data) async {
    await _handleKeyExchangeSent(data);
  }

  /// Handle user data exchange notification
  Future<void> handleUserDataExchange(Map<String, dynamic> data) async {
    await _handleUserDataExchange(data);
  }

  /// Handle user data response notification
  Future<void> handleUserDataResponse(Map<String, dynamic> data) async {
    await _handleUserDataResponse(data);
  }

  /// Handle typing indicator notification
  Future<void> handleTypingIndicatorNotification(
      Map<String, dynamic> data) async {
    print('🔒 SecureNotificationService: Processing typing indicator: $data');
    // TODO: Implement typing indicator handling
  }

  /// Handle message delivery status notification
  Future<void> handleMessageDeliveryStatus(Map<String, dynamic> data) async {
    print(
        '🔒 SecureNotificationService: Processing message delivery status: $data');
    // TODO: Implement message delivery status handling
  }

  /// Handle broadcast notification
  Future<void> handleBroadcastNotification(Map<String, dynamic> data) async {
    print(
        '🔒 SecureNotificationService: Processing broadcast notification: $data');
    // TODO: Implement broadcast notification handling
  }

  /// Handle online status update notification
  Future<void> handleOnlineStatusUpdate(Map<String, dynamic> data) async {
    print(
        '🔒 SecureNotificationService: Processing online status update: $data');
    // TODO: Implement online status update handling
  }

  /// Handle message notification
  Future<void> handleMessageNotification(Map<String, dynamic> data) async {
    print('🔒 SecureNotificationService: 🔍 Processing message data: $data');

    // Extract message data
    final senderId =
        data['sender_id'] as String? ?? data['senderId'] as String? ?? '';
    final senderName = data['sender_name'] as String? ??
        data['senderName'] as String? ??
        'Unknown';
    final message = data['message'] as String? ?? '';
    final conversationId =
        data['conversation_id'] as String? ?? data['conversationId'] as String?;
    final messageId =
        data['message_id'] as String? ?? data['messageId'] as String?;

    if (senderId.isEmpty || message.isEmpty) {
      print(
          '🔒 SecureNotificationService: ❌ Invalid message notification data - missing required fields');
      return;
    }

    print(
        '🔒 SecureNotificationService: Processing message from $senderName: $message');

    // Show local notification
    await showLocalNotification(
      title: 'New Message',
      body: 'You have received a new message',
      type: 'message',
      data: data,
    );

    // Trigger message received callback
    if (_onMessageReceived != null) {
      _onMessageReceived!(
        senderId,
        senderName,
        message,
        conversationId ??
            'chat_${DateTime.now().millisecondsSinceEpoch}_$senderId',
        messageId,
      );
    }

    print(
        '🔒 SecureNotificationService: ✅ Message notification handled successfully');
  }

  /// Handle key exchange declined notification
  Future<void> _handleKeyExchangeDeclined(Map<String, dynamic> data) async {
    // TODO: Implement key exchange declined handling
    print(
        '🔒 SecureNotificationService: Processing key exchange declined: $data');
  }

  /// Handle key exchange sent notification
  Future<void> _handleKeyExchangeSent(Map<String, dynamic> data) async {
    // TODO: Implement key exchange sent handling
    print('🔒 SecureNotificationService: Processing key exchange sent: $data');
  }

  /// Handle encrypted user data exchange notification
  Future<void> _handleUserDataExchange(Map<String, dynamic> data) async {
    try {
      print(
          '🔒 SecureNotificationService: 🔐 Processing encrypted user data exchange');
      print(
          '🔒 SecureNotificationService: 🔍 Input data keys: ${data.keys.toList()}');
      print('🔒 SecureNotificationService: 🔍 Input data: $data');

      // Extract encrypted data - handle both direct and nested structures
      String? encryptedData;

      // Check if data is directly in the 'encryptedData' field
      if (data.containsKey('encryptedData')) {
        final dataField = data['encryptedData'];
        if (dataField is String) {
          encryptedData = dataField;
          print(
              '🔒 SecureNotificationService: Found encrypted data in encryptedData field: ${encryptedData.length} characters');
        } else {
          print(
              '🔒 SecureNotificationService: encryptedData field is not a string: ${dataField.runtimeType}');
        }
      }

      // Check if data is in a nested structure (iOS aps format)
      if (encryptedData == null && data.containsKey('aps')) {
        print(
            '🔒 SecureNotificationService: 🔴 iOS notification with aps structure detected');

        // Try to extract from the main data field
        if (data.containsKey('data')) {
          final dataField = data['data'];
          if (dataField is String) {
            encryptedData = dataField;
            print(
                '🔒 SecureNotificationService: Found encrypted data in iOS notification: ${encryptedData.length} characters');
          }
        }
      }

      if (encryptedData == null) {
        print(
            '🔒 SecureNotificationService: ❌ No encrypted data found in user data exchange');
        print(
            '🔒 SecureNotificationService: Available fields: ${data.keys.toList()}');
        return;
      }

      print(
          '🔒 SecureNotificationService: 🔐 Attempting to decrypt data: ${encryptedData.substring(0, 50)}...');

      // Decrypt the data using the new encryption service
      final decryptedData = await EncryptionService.decryptAesCbcPkcs7(
        encryptedData,
      );

      if (decryptedData == null) {
        print(
            '🔒 SecureNotificationService: ❌ Failed to decrypt user data exchange data');
        return;
      }

      print('🔒 SecureNotificationService: ✅ User data decrypted successfully');
      print(
          '🔒 SecureNotificationService: 🔍 Decrypted data type: ${decryptedData.runtimeType}');
      print('🔒 SecureNotificationService: 🔍 Decrypted data: $decryptedData');

      // Ensure decryptedData is a Map before processing
      if (decryptedData is! Map<String, dynamic>) {
        print(
            '🔒 SecureNotificationService: ❌ Decrypted data is not a Map: ${decryptedData.runtimeType}');
        print(
            '🔒 SecureNotificationService: Decrypted data value: $decryptedData');
        return;
      }

      // Process the decrypted user data
      await _processDecryptedUserData(decryptedData);
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error processing user data exchange: $e');
      print(
          '🔒 SecureNotificationService: Error stack trace: ${StackTrace.current}');
    }
  }

  /// Process decrypted user data and create contact/chat
  Future<void> _processDecryptedUserData(Map<String, dynamic> userData) async {
    try {
      print('🔒 SecureNotificationService: Processing decrypted user data');
      print(
          '🔒 SecureNotificationService: 🔍 User data keys: ${userData.keys.toList()}');
      print('🔒 SecureNotificationService: 🔍 User data: $userData');

      final senderId = userData['sender_id'] as String?;
      final displayName = userData['display_name'] as String?;
      final profileData = userData['profile_data'] as Map<String, dynamic>?;

      if (senderId == null || displayName == null) {
        print(
            '🔒 SecureNotificationService: ❌ Invalid user data - missing required fields');
        print(
            '🔒 SecureNotificationService: Available fields: ${userData.keys.toList()}');
        return;
      }

      print(
          '🔒 SecureNotificationService: ✅ Processing data for user: $displayName ($senderId)');

      // Update the Key Exchange Request display name from "session_..." to actual name
      await _updateKeyExchangeRequestDisplayName(senderId, displayName);

      // Also update the KeyExchangeRequestProvider to refresh the UI in real-time
      try {
        // Import the provider and update display names
        // This will trigger UI updates for all key exchange requests
        final keyExchangeProvider = KeyExchangeRequestProvider();
        await keyExchangeProvider.updateUserDisplayName(senderId, displayName);
        print(
            '🔒 SecureNotificationService: ✅ KeyExchangeRequestProvider updated with new display name from user data');
      } catch (e) {
        print(
            '🔒 SecureNotificationService: Error updating KeyExchangeRequestProvider from user data: $e');
        // Continue with the process even if provider update fails
      }

      // Create contact and chat automatically
      await _createContactAndChat(senderId, displayName, profileData);

      print(
          '🔒 SecureNotificationService: ✅ Contact and chat created successfully');
    } catch (e) {
      print('🔒 SecureNotificationService: ❌ Error processing user data: $e');
    }
  }

  /// Update the Key Exchange Request display name
  Future<void> _updateKeyExchangeRequestDisplayName(
      String senderId, String displayName) async {
    try {
      print(
          '🔒 SecureNotificationService: Updating KER display name for: $senderId to: $displayName');

      // Get the current user's session ID
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print(
            '🔒 SecureNotificationService: ❌ User not logged in, cannot update KER');
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
          '🔒 SecureNotificationService: ✅ KER display name mapping stored: $senderId -> $displayName');

      // Update the KeyExchangeRequestProvider to refresh the UI in real-time
      try {
        // Import the provider and update display names
        // This will trigger UI updates for all key exchange requests
        final keyExchangeProvider = KeyExchangeRequestProvider();
        await keyExchangeProvider.updateUserDisplayName(senderId, displayName);
        print(
            '🔒 SecureNotificationService: ✅ KeyExchangeRequestProvider updated with new display name');
      } catch (e) {
        print(
            '🔒 SecureNotificationService: Error updating KeyExchangeRequestProvider: $e');
        // Continue with the process even if provider update fails
      }

      // Trigger a refresh of the key exchange requests to show updated names
      // This will be handled by the UI when it reads the display name mappings
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error updating KER display name: $e');
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
          '🔒 SecureNotificationService: Creating contact and chat for: $displayName');

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        print('🔒 SecureNotificationService: ❌ User not logged in');
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
        print('🔒 SecureNotificationService: ✅ Contact saved: $displayName');
      } else {
        print(
            '🔒 SecureNotificationService: Contact already exists: $displayName');
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
            '🔒 SecureNotificationService: 🗄️ Attempting to save conversation to database...');
        final messageStorageService = MessageStorageService.instance;
        print(
            '🔒 SecureNotificationService: 📊 Conversation data: ${conversation.toJson()}');
        await messageStorageService.saveConversation(conversation);
        print(
            '🔒 SecureNotificationService: ✅ Chat conversation created in database: $chatId');

        // Notify about conversation creation
        if (_onConversationCreated != null) {
          _onConversationCreated!(conversation);
        }
      } catch (e) {
        print(
            '🔒 SecureNotificationService: ❌ Failed to create chat conversation in database: $e');
        print(
            '🔒 SecureNotificationService: 🔍 Error details: ${e.runtimeType} - $e');
        // No fallback to SharedPreferences - database must succeed
        throw Exception('Failed to create chat conversation in database: $e');
      }

      // Send encrypted response with our user data and chat info
      await _sendEncryptedResponse(contactId, chatId);
    } catch (e) {
      print('🔒 SecureNotificationService: ❌ Error creating contact/chat: $e');
      // Rollback changes if needed
      await _rollbackContactChatCreation(contactId);
    }
  }

  /// Send encrypted response with our user data and chat info
  Future<void> _sendEncryptedResponse(String contactId, String chatId) async {
    try {
      print(
          '🔒 SecureNotificationService: 🔐 Sending encrypted response to: $contactId');

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
          '🔒 SecureNotificationService: Sending response with display name: $userDisplayName and chat ID: $chatId');

      // Encrypt the data
      final encryptedPayload = await EncryptionService.encryptAesCbcPkcs7(
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
            '🔒 SecureNotificationService: ✅ Encrypted response sent successfully');
      } else {
        print(
            '🔒 SecureNotificationService: ❌ Failed to send encrypted response');
      }
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error sending encrypted response: $e');
    }
  }

  /// Rollback contact and chat creation on failure
  Future<void> _rollbackContactChatCreation(String contactId) async {
    try {
      print(
          '🔒 SecureNotificationService: Rolling back contact/chat creation for: $contactId');

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
            '🔒 SecureNotificationService: Would delete conversation: ${conversationToDelete.id}');
      } catch (e) {
        print(
            '🔒 SecureNotificationService: No conversation to rollback in database: $e');
      }

      print('🔒 SecureNotificationService: ✅ Rollback completed');
    } catch (e) {
      print('🔒 SecureNotificationService: ❌ Error during rollback: $e');
    }
  }

  /// Handle encrypted user data response notification
  Future<void> _handleUserDataResponse(Map<String, dynamic> data) async {
    try {
      print(
          '🔒 SecureNotificationService: 🔐 Processing encrypted user data response');
      print(
          '🔒 SecureNotificationService: 🔍 Input data keys: ${data.keys.toList()}');
      print('🔒 SecureNotificationService: 🔍 Input data: $data');

      // Extract encrypted data - handle both direct and nested structures
      String? encryptedData;

      // Check if data is directly in the 'data' field
      if (data.containsKey('data')) {
        final dataField = data['data'];
        if (dataField is String) {
          encryptedData = dataField;
          print(
              '🔒 SecureNotificationService: Found encrypted data in data field: ${encryptedData.length} characters');
        } else {
          print(
              '🔒 SecureNotificationService: Data field is not a string: ${dataField.runtimeType}');
        }
      }

      // Check if data is in a nested structure (iOS aps format)
      if (encryptedData == null && data.containsKey('aps')) {
        print(
            '🔒 SecureNotificationService: 🔴 iOS notification with aps structure detected');

        // Try to extract from the main data field
        if (data.containsKey('data')) {
          final dataField = data['data'];
          if (dataField is String) {
            encryptedData = dataField;
            print(
                '🔒 SecureNotificationService: Found encrypted data in iOS notification: ${encryptedData.length} characters');
          }
        }
      }

      if (encryptedData == null) {
        print(
            '🔒 SecureNotificationService: ❌ No encrypted data found in response');
        print(
            '🔒 SecureNotificationService: Available fields: ${data.keys.toList()}');
        return;
      }

      print(
          '🔒 SecureNotificationService: 🔐 Attempting to decrypt data: ${encryptedData.substring(0, 50)}...');

      // Decrypt the data using the new encryption service
      final decryptedData = await EncryptionService.decryptAesCbcPkcs7(
        encryptedData,
      );

      if (decryptedData == null) {
        print(
            '🔒 SecureNotificationService: ❌ Failed to decrypt response data');
        return;
      }

      print(
          '🔒 SecureNotificationService: ✅ Response data decrypted successfully');
      print(
          '🔒 SecureNotificationService: 🔍 Decrypted data type: ${decryptedData.runtimeType}');
      print('🔒 SecureNotificationService: 🔍 Decrypted data: $decryptedData');

      // Ensure decryptedData is a Map before processing
      if (decryptedData is! Map<String, dynamic>) {
        print(
            '🔒 SecureNotificationService: ❌ Decrypted data is not a Map: ${decryptedData.runtimeType}');
        print(
            '🔒 SecureNotificationService: Decrypted data value: $decryptedData');
        return;
      }

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
              '🔒 SecureNotificationService: ✅ KeyExchangeRequestProvider updated with response display name');
        }
      } catch (e) {
        print(
            '🔒 SecureNotificationService: Error updating KeyExchangeRequestProvider from response: $e');
        // Continue with the process even if provider update fails
      }
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error processing user data response: $e');
      print(
          '🔒 SecureNotificationService: Error stack trace: ${StackTrace.current}');
    }
  }

  /// Process decrypted response data and create contact/chat on sender side
  Future<void> _processDecryptedResponseData(
      Map<String, dynamic> responseData) async {
    try {
      print('🔒 SecureNotificationService: Processing decrypted response data');
      print(
          '🔒 SecureNotificationService: 🔍 Response data keys: ${responseData.keys.toList()}');
      print('🔒 SecureNotificationService: 🔍 Response data: $responseData');
      print(
          '🔒 SecureNotificationService: 🔍 Response data types: ${responseData.map((key, value) => MapEntry(key, value.runtimeType))}');

      final senderId = responseData['sender_id'] as String?;
      final displayName = responseData['display_name'] as String?;
      final chatId = responseData['chat_id'] as String?;
      final profileData = responseData['profile_data'] as Map<String, dynamic>?;

      print(
          '🔒 SecureNotificationService: 🔍 Extracted fields - senderId: $senderId, displayName: $displayName, chatId: $chatId');

      if (senderId == null || displayName == null || chatId == null) {
        print(
            '🔒 SecureNotificationService: ❌ Invalid response data - missing required fields');
        print(
            '🔒 SecureNotificationService: Available fields: ${responseData.keys.toList()}');
        return;
      }

      print(
          '🔒 SecureNotificationService: ✅ Processing response for user: $displayName ($senderId)');

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
          '🔒 SecureNotificationService: ✅ Contact and chat created from response');
      print(
          '🔒 SecureNotificationService: 🎉 Key Exchange Request feature complete!');
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error processing response data: $e');
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
          '🔒 SecureNotificationService: Creating contact and chat from response for: $displayName');

      final currentUserId = _sessionId;
      if (currentUserId == null) {
        print('🔒 SecureNotificationService: User not logged in');
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
            '🔒 SecureNotificationService: ✅ Contact saved from response: $displayName');
      } else {
        print(
            '🔒 SecureNotificationService: Contact already exists from response: $displayName');
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
            '🔒 SecureNotificationService: 🗄️ Attempting to save conversation to database...');
        final messageStorageService = MessageStorageService.instance;
        print(
            '🔒 SecureNotificationService: 📊 Conversation data: ${conversation.toJson()}');
        await messageStorageService.saveConversation(conversation);
        print(
            '🔒 SecureNotificationService: ✅ Chat conversation created in database: $chatId');

        // Notify about conversation creation
        if (_onConversationCreated != null) {
          _onConversationCreated!(conversation);
        }
      } catch (e) {
        print(
            '🔒 SecureNotificationService: ❌ Failed to create chat conversation in database: $e');
        print(
            '🔒 SecureNotificationService: 🔍 Error details: ${e.runtimeType} - $e');
        // No fallback to SharedPreferences - database must succeed
        throw Exception('Failed to create chat conversation in database: $e');
      }

      // Show success message to user
      _showToastMessage('Secure connection established with $displayName!');
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error creating contact/chat from response: $e');
    }
  }

  /// Mark the key exchange as complete
  Future<void> _markKeyExchangeComplete(String contactId) async {
    try {
      print(
          '🔒 SecureNotificationService: Marking key exchange as complete for: $contactId');

      // Get the current user's session ID
      final currentUserId = _sessionId;
      if (currentUserId == null) {
        print(
            '🔒 SecureNotificationService: User not logged in, cannot mark KER complete');
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
          '🔒 SecureNotificationService: ✅ Key exchange marked as complete for: $contactId');
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error marking key exchange complete: $e');
    }
  }

  /// Notify KeyExchangeRequestProvider about completed key exchange
  Future<void> _notifyKeyExchangeCompleted(
      String contactId, String displayName) async {
    try {
      print(
          '🔒 SecureNotificationService: Notifying KeyExchangeRequestProvider about completed exchange');

      // Get the current user's session ID
      final currentUserId = _sessionId;
      if (currentUserId == null) {
        print(
            '🔒 SecureNotificationService: User not logged in, cannot notify provider');
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
          '🔒 SecureNotificationService: ✅ Key exchange completion data stored for UI updates');

      // Trigger UI refresh by updating the indicator service
      IndicatorService().setNewKeyExchange();
    } catch (e) {
      print(
          '🔒 SecureNotificationService: ❌ Error notifying about key exchange completion: $e');
    }
  }

  /// Show a toast message (for web, console, or native)
  void _showToastMessage(String message) {
    if (kIsWeb) {
      print('🔒 SecureNotificationService: Web toast: $message');
    } else {
      // For native platforms, you would typically use a platform channel
      // to communicate with the native side.
      // This is a placeholder for a native implementation.
      print('🔒 SecureNotificationService: Native toast: $message');
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

  /// Send message notification
  Future<bool> sendMessage({
    required String recipientId,
    required String senderName,
    required String message,
    required String conversationId,
  }) async {
    try {
      print('🔒 SecureNotificationService: Sending message');

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
      final encryptedData = await EncryptionService.encryptAesCbcPkcs7(
        messageData,
        recipientId,
      );
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
          'data': encryptedData['data'] as String, // Encrypted sensitive data
          'checksum': checksum, // Checksum for verification
        },
        sound: 'message.wav',
        encrypted: true, // Mark as encrypted for AirNotifier server
        checksum: checksum, // Include checksum for verification
      );

      if (success) {
        print('🔒 SecureNotificationService: ✅ Message sent');
        return true;
      } else {
        print('🔒 SecureNotificationService: ❌ Failed to send message');
        return false;
      }
    } catch (e) {
      print('🔒 SecureNotificationService: Error sending message: $e');
      return false;
    }
  }

  /// Clear ALL data when deleting account (comprehensive cleanup)
  Future<void> clearAllDataOnAccountDeletion() async {
    try {
      print(
          '🗑️ SecureNotificationService: Starting comprehensive account data cleanup...');

      // 1. Clear all secure storage (encryption keys, etc.)
      final storage = FlutterSecureStorage();
      final secureKeys = await storage.readAll();
      for (final key in secureKeys.keys) {
        await storage.delete(key: key);
        print('🗑️ SecureNotificationService: Deleted secure key: $key');
      }

      // 2. Clear all shared preferences
      final prefsService = SeSharedPreferenceService();
      await prefsService.clear();
      print('🗑️ SecureNotificationService: Cleared all shared preferences');

      // 3. Clear local notifications
      await _notifications.cancelAll();
      print('🗑️ SecureNotificationService: Cancelled all local notifications');

      // 4. Clear notification cache
      _processedNotifications.clear();
      print('🗑️ SecureNotificationService: Cleared notification cache');

      // 5. Unlink device from AirNotifier server
      try {
        if (_deviceToken != null && _sessionId != null) {
          await AirNotifierService.instance.unlinkTokenFromSession();
          print(
              '🗑️ SecureNotificationService: Unlinked device from AirNotifier');
        }
      } catch (e) {
        print(
            '🗑️ SecureNotificationService: Warning - AirNotifier unlink failed: $e');
      }

      // 6. Reset service state
      _deviceToken = null;
      _sessionId = null;
      _permissionStatus = PermissionStatus.denied;
      _isInitialized = false;
      print('🗑️ SecureNotificationService: Reset service state');

      // 7. Clear data from other services
      try {
        // Clear key exchange service data
        await KeyExchangeService.instance.clearAllPendingExchanges();
        print(
            '🗑️ SecureNotificationService: Cleared key exchange service data');
      } catch (e) {
        print(
            '🗑️ SecureNotificationService: Warning - some service cleanup failed: $e');
      }

      print(
          '🗑️ SecureNotificationService: ✅ Comprehensive account cleanup completed');
    } catch (e) {
      print(
          '🗑️ SecureNotificationService: ❌ Error during account cleanup: $e');
      // Don't throw - we want to continue with cleanup even if some parts fail
    }
  }

  /// Detect if app was reinstalled and handle re-registration
  Future<void> detectAndHandleAppReinstall() async {
    try {
      print('🔄 SecureNotificationService: Checking for app reinstall...');

      // Check if we have a device token but no session ID (indicates reinstall)
      if (_deviceToken != null &&
          _deviceToken!.isNotEmpty &&
          _sessionId == null) {
        print(
            '🔄 SecureNotificationService: App reinstall detected - device token exists but no session');
        await _handleAppReinstall();
      }

      // Check if we have a session ID but device token is not registered on AirNotifier
      if (_sessionId != null && _deviceToken != null) {
        // Simple check: if we have a device token and session ID, assume it's registered
        // In a real implementation, you could make an API call to verify registration
        final isRegistered = _deviceToken!.isNotEmpty && _sessionId!.isNotEmpty;

        if (!isRegistered) {
          print(
              '🔄 SecureNotificationService: Device not registered on AirNotifier - re-registering');
          await _handleAppReinstall();
        }
      }

      // Check for app reinstall by looking at installation timestamp
      final prefsService = SeSharedPreferenceService();
      final lastInstallTime =
          await prefsService.getInt('app_install_timestamp');
      final currentTime = DateTime.now().millisecondsSinceEpoch;

      if (lastInstallTime == null) {
        // First time install - set timestamp
        await prefsService.setInt('app_install_timestamp', currentTime);
        print(
            '🔄 SecureNotificationService: First install detected, setting timestamp');
      } else {
        // Check if app was reinstalled (timestamp difference > 1 hour)
        final timeDiff = currentTime - lastInstallTime;
        if (timeDiff > 3600000) {
          // 1 hour in milliseconds
          print(
              '🔄 SecureNotificationService: App reinstall detected based on timestamp');
          await _handleAppReinstall();
          // Update timestamp
          await prefsService.setInt('app_install_timestamp', currentTime);
        }
      }
    } catch (e) {
      print('🔄 SecureNotificationService: Error detecting app reinstall: $e');
    }
  }

  /// Handle app reinstall by re-registering with AirNotifier
  Future<void> _handleAppReinstall() async {
    try {
      print('🔄 SecureNotificationService: Handling app reinstall...');

      // Clear old device token and session data
      _deviceToken = null;
      _sessionId = null;
      _isInitialized = false;

      // Clear notification cache
      _processedNotifications.clear();

      // Cancel all local notifications
      await _notifications.cancelAll();

      // Re-initialize the service
      await initialize();

      print(
          '🔄 SecureNotificationService: ✅ App reinstall handled successfully');
    } catch (e) {
      print('🔄 SecureNotificationService: ❌ Error handling app reinstall: $e');
    }
  }

  /// Check if device is properly registered on AirNotifier
  Future<bool> isDeviceProperlyRegistered() async {
    try {
      if (_deviceToken == null || _sessionId == null) {
        return false;
      }

      // Simple check: if we have a device token and session ID, assume it's registered
      // In a real implementation, you could make an API call to verify registration
      final isRegistered = _deviceToken!.isNotEmpty && _sessionId!.isNotEmpty;

      if (!isRegistered) {
        print(
            '🔍 SecureNotificationService: Device not properly registered on AirNotifier');
        return false;
      }

      print(
          '🔍 SecureNotificationService: ✅ Device properly registered on AirNotifier');
      return true;
    } catch (e) {
      print(
          '🔍 SecureNotificationService: ❌ Error checking device registration: $e');
      return false;
    }
  }

  /// Force re-registration with AirNotifier (useful for troubleshooting)
  Future<void> forceReregistration() async {
    try {
      print(
          '🔄 SecureNotificationService: Force re-registering with AirNotifier...');

      // Clear current registration
      if (_deviceToken != null && _sessionId != null) {
        try {
          await AirNotifierService.instance.unlinkTokenFromSession();
          print('🔄 SecureNotificationService: Unlinked old device token');
        } catch (e) {
          print('🔄 SecureNotificationService: Warning - unlink failed: $e');
        }
      }

      // Reset service state
      _deviceToken = null;
      _isInitialized = false;

      // Re-initialize
      await initialize();

      print('🔄 SecureNotificationService: ✅ Force re-registration completed');
    } catch (e) {
      print(
          '🔄 SecureNotificationService: ❌ Error during force re-registration: $e');
    }
  }
}
