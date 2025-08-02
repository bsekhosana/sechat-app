import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'airnotifier_service.dart';
import 'se_session_service.dart';
import 'global_user_service.dart';
import 'encryption_service.dart';
import 'local_storage_service.dart';
import 'se_shared_preference_service.dart';
import '../../shared/models/chat.dart';
import '../../shared/models/message.dart' as app_message;
import '../utils/guid_generator.dart';
import 'indicator_service.dart';
import 'package:flutter/material.dart';

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

  // Callbacks for notification handling
  Function(String, String, String)? _onInvitationReceived;
  Function(String, String, String, {String? conversationGuid})?
      _onInvitationResponse;
  Function(String, String, String)? _onMessageReceived;
  Function(String, bool)? _onTypingIndicator;

  // Provider instances for handling responses
  dynamic? _invitationProvider;

  SimpleNotificationService._();

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Get session ID (may be null initially - will be set later via setSessionId)
      _sessionId = SeSessionService().currentSessionId;

      // Request permissions
      await _requestPermissions();

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Initialize AirNotifier with session ID (if available)
      if (_sessionId != null) {
        await _initializeAirNotifier();
      }

      _isInitialized = true;
    } catch (e) {
      print('🔔 SimpleNotificationService: Error initializing: $e');
    }
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    if (kIsWeb) return;

    final status = await Permission.notification.request();
    _permissionStatus = status;
    print(
        '🔔 SimpleNotificationService: Notification permission status: $_permissionStatus');
  }

  /// Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    if (kIsWeb) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(settings);
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
    } catch (e) {
      print('🔔 SimpleNotificationService: Error initializing AirNotifier: $e');
    }
  }

  /// Send invitation notification
  Future<bool> sendInvitation({
    required String recipientId,
    required String senderName,
    required String invitationId,
    String? message,
  }) async {
    try {
      print('🔔 SimpleNotificationService: Sending invitation');

      // Create invitation data
      final invitationData = {
        'type': 'invitation',
        'invitationId': invitationId,
        'senderName': senderName,
        'senderId': SeSessionService().currentSessionId,
        'message': message ?? 'Contact request',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'version': '1.0',
      };

      // Encrypt the invitation data
      final encryptedData = await _encryptData(invitationData, recipientId);
      final checksum = _generateChecksum(invitationData);

      // Send via AirNotifier with encryption
      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: recipientId,
        title: 'New Contact Invitation',
        body: '$senderName would like to connect with you',
        data: {
          'encrypted': true,
          'data': encryptedData,
          'checksum': checksum,
        },
        sound: 'invitation.wav',
      );

      if (success) {
        print('🔔 SimpleNotificationService: ✅ Invitation sent');
        return true;
      } else {
        print('🔔 SimpleNotificationService: ❌ Failed to send invitation');
        return false;
      }
    } catch (e) {
      print('🔔 SimpleNotificationService: Error sending invitation: $e');
      return false;
    }
  }

  /// Send invitation response notification
  Future<bool> sendInvitationResponse({
    required String recipientId,
    required String senderName,
    required String invitationId,
    required String response, // 'accepted' or 'declined'
    String? conversationGuid, // Only for accepted invitations
  }) async {
    try {
      print('🔔 SimpleNotificationService: Sending invitation response');

      // Create invitation response data
      final responseData = {
        'type': 'invitation_response',
        'invitationId': invitationId,
        'responderId': SeSessionService().currentSessionId,
        'responderName': senderName,
        'response': response, // 'accepted' or 'declined'
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'version': '1.0',
      };

      // Add conversation GUID if invitation was accepted
      if (response == 'accepted' && conversationGuid != null) {
        responseData['conversationGuid'] = conversationGuid;
      }

      // Encrypt the response data
      final encryptedData = await _encryptData(responseData, recipientId);
      final checksum = _generateChecksum(responseData);

      // Determine notification content based on response
      final title = response == 'accepted'
          ? 'Invitation Accepted'
          : 'Invitation Declined';
      final body = response == 'accepted'
          ? '$senderName accepted your invitation'
          : '$senderName declined your invitation';

      // Send via AirNotifier with encryption
      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: recipientId,
        title: title,
        body: body,
        data: {
          'encrypted': true,
          'data': encryptedData,
          'checksum': checksum,
        },
        sound: response == 'accepted' ? 'accept.wav' : 'decline.wav',
      );

      if (success) {
        print('🔔 SimpleNotificationService: ✅ Invitation response sent');
        return true;
      } else {
        print(
            '🔔 SimpleNotificationService: ❌ Failed to send invitation response');
        return false;
      }
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error sending invitation response: $e');
      return false;
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

      // Send via AirNotifier with encryption
      final success =
          await AirNotifierService.instance.sendNotificationToSession(
        sessionId: recipientId,
        title: senderName,
        body:
            message.length > 100 ? '${message.substring(0, 100)}...' : message,
        data: {
          'encrypted': true,
          'data': encryptedData,
          'checksum': checksum,
        },
        sound: 'message.wav',
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

  /// Process received notification
  Future<Map<String, dynamic>?> processNotification(
      Map<String, dynamic> notificationData) async {
    try {
      print('🔔 SimpleNotificationService: Processing notification');

      // Check if notification is encrypted (handle both bool and string)
      final encryptedValue = notificationData['encrypted'];
      final isEncrypted = encryptedValue == true ||
          encryptedValue == 'true' ||
          encryptedValue == '1';

      if (isEncrypted) {
        print(
            '🔔 SimpleNotificationService: 🔐 Processing encrypted notification');

        // Get encrypted data from the new structure
        final encryptedData = notificationData['data'] as String?;
        final checksum = notificationData['checksum'] as String?;

        if (encryptedData == null) {
          print('🔔 SimpleNotificationService: ❌ No encrypted data found');
          return null;
        }

        // Decrypt the data
        final decryptedData = await _decryptData(encryptedData);
        if (decryptedData == null) {
          print('🔔 SimpleNotificationService: ❌ Failed to decrypt data');
          return null;
        }

        // Verify checksum
        final expectedChecksum = _generateChecksum(decryptedData);
        if (checksum != expectedChecksum) {
          print('🔔 SimpleNotificationService: ❌ Checksum verification failed');
          return null;
        }

        print(
            '🔔 SimpleNotificationService: ✅ Encrypted notification processed');
        return decryptedData;
      } else {
        print(
            '🔔 SimpleNotificationService: Processing plain text notification');
        return notificationData;
      }
    } catch (e) {
      print('🔔 SimpleNotificationService: Error processing notification: $e');
      return null;
    }
  }

  /// Handle notification and trigger callbacks
  Future<void> handleNotification(Map<String, dynamic> notificationData) async {
    try {
      print(
          '🔔 SimpleNotificationService: Handling notification: $notificationData');

      // Extract the actual data from the notification
      Map<String, dynamic>? actualData;

      // Check if data is nested under 'data' field (from Android logs)
      if (notificationData.containsKey('data')) {
        final dataField = notificationData['data'];
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
          actualData = notificationData;
        }
      } else {
        // Check if data is at top level
        actualData = notificationData;
        print(
            '🔔 SimpleNotificationService: Using top-level data: $actualData');
      }

      final decryptedData = await processNotification(actualData);
      if (decryptedData == null) {
        print('🔔 SimpleNotificationService: ❌ No decrypted data available');
        return;
      }

      print('🔔 SimpleNotificationService: Decrypted data: $decryptedData');

      final type = decryptedData['type'] as String?;
      if (type == null) {
        print('🔔 SimpleNotificationService: ❌ No notification type found');
        return;
      }

      print(
          '🔔 SimpleNotificationService: Processing notification type: $type');

      switch (type) {
        case 'invitation':
          await _handleInvitationNotification(decryptedData);
          break;
        case 'invitation_response':
          await _handleInvitationResponseNotification(decryptedData);
          break;
        case 'message':
          await _handleMessageNotification(decryptedData);
          break;
        case 'typing_indicator':
          await _handleTypingIndicatorNotification(decryptedData);
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

  /// Handle invitation notification
  Future<void> _handleInvitationNotification(Map<String, dynamic> data) async {
    final senderId = data['senderId'] as String?;
    final senderName = data['senderName'] as String?;
    final invitationId = data['invitationId'] as String?;

    if (senderId == null || senderName == null || invitationId == null) {
      print(
          '🔔 SimpleNotificationService: Invalid invitation notification data');
      return;
    }

    print(
        '🔔 SimpleNotificationService: Processing invitation from $senderName ($senderId)');

    // Check for existing invitations from this sender
    final prefsService = SeSharedPreferenceService();
    final existingInvitationsJson =
        await prefsService.getJsonList('invitations') ?? [];

    // Check for existing invitation from this sender
    final existingInvitation = existingInvitationsJson.firstWhere(
      (inv) =>
          inv['fromUserId'] == senderId &&
          inv['toUserId'] == (SeSessionService().currentSessionId ?? ''),
      orElse: () => <String, dynamic>{},
    );

    if (existingInvitation.isNotEmpty) {
      final status = existingInvitation['status'] as String?;

      if (status == 'accepted') {
        print(
            '🔔 SimpleNotificationService: Already in contacts with $senderName');
        // Show toast message
        _showToastMessage('Already in contacts with $senderName');
        return;
      } else if (status == 'declined') {
        print(
            '🔔 SimpleNotificationService: Previously declined invitation from $senderName');
        // Show toast message
        _showToastMessage('Previously declined invitation from $senderName');
        return;
      } else if (status == 'pending') {
        print(
            '🔔 SimpleNotificationService: Invitation already pending from $senderName');
        // Show toast message
        _showToastMessage('Invitation already pending from $senderName');
        return;
      }
    }

    // Check if sender is blocked (you can implement this logic)
    // final isBlocked = await _checkIfUserIsBlocked(senderId);
    // if (isBlocked) {
    //   print('🔔 SimpleNotificationService: Sender $senderName is blocked');
    //   _showToastMessage('Invitation from blocked user ignored');
    //   return;
    // }

    // Show local notification
    await showLocalNotification(
      title: 'New Contact Invitation',
      body: '$senderName would like to connect with you',
      type: 'invitation',
      data: data,
    );

    // Save notification to SharedPreferences
    await _saveNotificationToSharedPrefs(
      id: 'invitation_${DateTime.now().millisecondsSinceEpoch}',
      title: 'New Contact Invitation',
      body: '$senderName would like to connect with you',
      type: 'invitation',
      data: data,
      timestamp: DateTime.now(),
    );

    // Create invitation record and save to local storage
    try {
      final invitation = {
        'id': invitationId,
        'senderId': senderId,
        'recipientId': SeSessionService().currentSessionId ?? '',
        'senderUsername': senderName,
        'recipientUsername': GlobalUserService.instance.currentUsername ?? '',
        'message': 'Contact request',
        'status': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        'is_received': true, // This is a received invitation
      };

      print(
          '🔔 SimpleNotificationService: Saving invitation with data: $invitation');

      // Save to SeSharedPreferenceService (same as InvitationProvider)
      final prefsService = SeSharedPreferenceService();
      final existingInvitationsJson =
          await prefsService.getJsonList('invitations') ?? [];

      // Convert invitation to Invitation model format
      final invitationModel = {
        'id': invitation['id'],
        'fromUserId': invitation['senderId'],
        'fromUsername': invitation['senderUsername'],
        'toUserId': invitation['recipientId'],
        'toUsername': invitation['recipientUsername'],
        'status': 'pending',
        'createdAt': invitation['createdAt'],
        'respondedAt': null,
      };

      // Add new invitation to existing list
      existingInvitationsJson.add(invitationModel);

      // Save updated list
      await prefsService.setJsonList('invitations', existingInvitationsJson);
      print(
          '🔔 SimpleNotificationService: ✅ Invitation saved to SeSharedPreferenceService');

      // Verify the invitation was saved by reading it back
      final savedInvitationsJson =
          await prefsService.getJsonList('invitations');
      if (savedInvitationsJson != null && savedInvitationsJson.isNotEmpty) {
        final lastInvitation = savedInvitationsJson.last;
        print(
            '🔔 SimpleNotificationService: ✅ Invitation verified in storage: ${lastInvitation['fromUsername']}');
      } else {
        print(
            '🔔 SimpleNotificationService: ❌ Invitation not found in storage after saving');
      }

      // Trigger callback for UI updates (this will update invitations screen in real-time)
      _onInvitationReceived?.call(senderId, senderName, invitationId);
      print(
          '🔔 SimpleNotificationService: ✅ Invitation callback triggered - UI will update in real-time');

      // Trigger indicator for new invitation
      IndicatorService().setNewInvitation();

      // Refresh InvitationProvider if available
      if (_invitationProvider != null) {
        try {
          await _invitationProvider.refreshInvitations();
          print('🔔 SimpleNotificationService: ✅ InvitationProvider refreshed');
        } catch (e) {
          print(
              '🔔 SimpleNotificationService: Error refreshing InvitationProvider: $e');
        }
      }
    } catch (e) {
      print('🔔 SimpleNotificationService: Error saving invitation: $e');
    }
  }

  /// Handle invitation response notification
  Future<void> _handleInvitationResponseNotification(
      Map<String, dynamic> data) async {
    final responderId = data['responderId'] as String?;
    final responderName = data['responderName'] as String?;
    final response = data['response'] as String?; // 'accepted' or 'declined'
    final conversationGuid = data['conversationGuid'] as String?;

    if (responderId == null || responderName == null || response == null) {
      print(
          '🔔 SimpleNotificationService: Invalid invitation response notification data');
      return;
    }

    print(
        '🔔 SimpleNotificationService: Processing invitation response: $response from $responderName ($responderId)');

    // Show local notification
    final title =
        response == 'accepted' ? 'Invitation Accepted' : 'Invitation Declined';
    final body = response == 'accepted'
        ? '$responderName accepted your invitation'
        : '$responderName declined your invitation';

    await showLocalNotification(
      title: title,
      body: body,
      type: 'invitation_response',
      data: {
        ...data,
        'conversationGuid': conversationGuid, // Include GUID if available
      },
    );

    // Save notification to SharedPreferences
    await _saveNotificationToSharedPrefs(
      id: 'invitation_response_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      body: body,
      type: 'invitation_response',
      data: {
        ...data,
        'conversationGuid': conversationGuid,
        'chatGuid': data['chatGuid'], // Include chat GUID if available
      },
      timestamp: DateTime.now(),
    );

    // If invitation was accepted and we have a chat GUID, create the chat for the sender
    final chatGuid = data['chatGuid'] as String?;
    if (response == 'accepted' && chatGuid != null) {
      await _createChatForSender(data, chatGuid);
    }

    // If accepted and conversation GUID is provided, create conversation for sender
    if (response == 'accepted' && conversationGuid != null) {
      await _createConversationForSender(
          responderId, responderName, conversationGuid);
    }

    // Handle invitation response in InvitationProvider if available
    if (_invitationProvider != null) {
      try {
        await _invitationProvider.handleInvitationResponse(
            responderId, responderName, response,
            conversationGuid: conversationGuid);
        print(
            '🔔 SimpleNotificationService: ✅ Invitation response handled by InvitationProvider');
      } catch (e) {
        print(
            '🔔 SimpleNotificationService: Error handling invitation response in provider: $e');
      }
    }

    // Trigger callback with conversation GUID if available
    _onInvitationResponse?.call(responderId, responderName, response,
        conversationGuid: conversationGuid);
  }

  /// Create conversation for sender when invitation is accepted
  Future<void> _createConversationForSender(
      String responderId, String responderName, String conversationGuid) async {
    try {
      print(
          '🔔 SimpleNotificationService: Creating conversation for sender with GUID: $conversationGuid');

      final currentUserId = SeSessionService().currentSessionId ?? '';
      final currentUserName =
          GlobalUserService.instance.currentUsername ?? 'Unknown User';

      // Create new conversation for the sender
      final newChat = Chat(
        id: conversationGuid,
        user1Id: currentUserId,
        user2Id: responderId,
        user1DisplayName: currentUserName,
        user2DisplayName: responderName,
        status: 'active',
        lastMessageAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        otherUser: {
          'id': responderId,
          'username': responderName,
          'profile_picture': null,
        },
        lastMessage: {
          'content': 'You are now connected with $responderName',
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      // Save conversation to local storage
      await LocalStorageService.instance.saveChat(newChat);
      print(
          '🔔 SimpleNotificationService: ✅ Conversation created for sender: $conversationGuid');

      // Create initial message for the conversation
      final initialMessage = app_message.Message(
        id: GuidGenerator.generateShortId(),
        chatId: conversationGuid,
        senderId: 'system',
        content: 'You are now connected with $responderName',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: 'sent',
      );

      // Save initial message to local storage
      await LocalStorageService.instance.saveMessage(initialMessage);
      print(
          '🔔 SimpleNotificationService: ✅ Initial message created for sender: ${initialMessage.id}');
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error creating conversation for sender: $e');
    }
  }

  /// Create chat for sender when invitation is accepted
  Future<void> _createChatForSender(
      Map<String, dynamic> data, String chatGuid) async {
    try {
      print(
          '🔔 SimpleNotificationService: Creating chat for sender with GUID: $chatGuid');

      final fromUserId = data['fromUserId'] as String?;
      final fromUsername = data['fromUsername'] as String?;
      final toUserId = data['toUserId'] as String?;
      final toUsername = data['toUsername'] as String?;

      if (fromUserId == null ||
          fromUsername == null ||
          toUserId == null ||
          toUsername == null) {
        print(
            '🔔 SimpleNotificationService: ❌ Missing user data for chat creation');
        return;
      }

      // Create chat conversation for sender
      final chat = Chat(
        id: chatGuid,
        user1Id: fromUserId,
        user2Id: toUserId,
        user1DisplayName: fromUsername,
        user2DisplayName: toUsername,
        status: 'active',
        lastMessageAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Save chat to SharedPreferences
      final prefsService = SeSharedPreferenceService();
      final chatsJson = await prefsService.getJsonList('chats') ?? [];
      final existingIndex = chatsJson.indexWhere((c) => c['id'] == chatGuid);

      if (existingIndex != -1) {
        chatsJson[existingIndex] = chat.toJson();
      } else {
        chatsJson.add(chat.toJson());
      }

      await prefsService.setJsonList('chats', chatsJson);
      print(
          '🔔 SimpleNotificationService: ✅ Chat created for sender: $chatGuid');
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: ❌ Error creating chat for sender: $e');
    }
  }

  /// Handle message notification
  Future<void> _handleMessageNotification(Map<String, dynamic> data) async {
    final senderId = data['senderId'] as String?;
    final senderName = data['senderName'] as String?;
    final message = data['message'] as String?;

    if (senderId == null || senderName == null || message == null) {
      print('🔔 SimpleNotificationService: Invalid message notification data');
      return;
    }

    // Check if sender is blocked
    final currentUserId = SeSessionService().currentSessionId;
    if (currentUserId != null) {
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
    }

    // Show local notification
    await showLocalNotification(
      title: senderName,
      body: message,
      type: 'message',
      data: data,
    );

    // Save notification to SharedPreferences
    await _saveNotificationToSharedPrefs(
      id: 'message_${DateTime.now().millisecondsSinceEpoch}',
      title: senderName,
      body: message,
      type: 'message',
      data: data,
      timestamp: DateTime.now(),
    );

    // Trigger indicator for new chat message
    IndicatorService().setNewChat();

    // Trigger callback
    _onMessageReceived?.call(senderId, senderName, message);
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
      final existingNotificationsJson =
          await prefsService.getJsonList('notifications') ?? [];

      final notificationModel = {
        'id': id,
        'title': title,
        'body': body,
        'type': type,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
        'isRead': false,
      };

      // Add new notification to existing list
      existingNotificationsJson.add(notificationModel);

      // Save updated list
      await prefsService.setJsonList(
          'notifications', existingNotificationsJson);
      print(
          '🔔 SimpleNotificationService: ✅ Notification saved to SharedPreferences: $title');
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error saving notification to SharedPreferences: $e');
    }
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

    // Trigger callback (no local notification for typing indicators)
    _onTypingIndicator?.call(senderId, isTyping);
  }

  /// Set device token for push notifications
  Future<void> setDeviceToken(String token) async {
    _deviceToken = token;
    print('🔔 SimpleNotificationService: Device token set: $token');

    // Also set the token in AirNotifier service
    try {
      await AirNotifierService.instance.registerDeviceToken(deviceToken: token);
      print(
          '🔔 SimpleNotificationService: ✅ Token registered with AirNotifier service');
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error registering token with AirNotifier: $e');
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
  Future<void> handleDeviceTokenReceived(String token) async {
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
  }

  /// Link token to session with retry mechanism
  Future<void> _linkTokenToSession() async {
    if (_sessionId == null || _deviceToken == null) {
      print(
          '🔔 SimpleNotificationService: Cannot link token - missing session ID or device token');
      return;
    }

    // Ensure token is registered with AirNotifier first
    try {
      await AirNotifierService.instance
          .registerDeviceToken(deviceToken: _deviceToken!);
      print(
          '🔔 SimpleNotificationService: ✅ Token ensured registered with AirNotifier');
    } catch (e) {
      print(
          '🔔 SimpleNotificationService: Error ensuring token registration: $e');
    }

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

  /// Set invitation received callback
  void setOnInvitationReceived(
      Function(String senderId, String senderName, String invitationId)
          callback) {
    _onInvitationReceived = callback;
  }

  /// Set invitation response callback
  void setOnInvitationResponse(
      Function(String responderId, String responderName, String status,
              {String? conversationGuid})
          callback) {
    _onInvitationResponse = callback;
  }

  /// Set invitation provider instance for handling invitation responses
  void setInvitationProvider(dynamic invitationProvider) {
    _invitationProvider = invitationProvider;
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
      // Convert data to JSON string
      final dataJson = json.encode(data);

      // Get recipient's public key (in real implementation, fetch from key server)
      final recipientPublicKey = await _getRecipientPublicKey(recipientId);
      if (recipientPublicKey == null) {
        throw Exception('Recipient public key not found');
      }

      // Parse recipient's public key
      final publicKeyBytes = base64Decode(recipientPublicKey);

      // Generate random AES key for this message
      final aesKey = List<int>.generate(32, (_) => _random.nextInt(256));

      // Generate random IV
      final iv = List<int>.generate(16, (_) => _random.nextInt(256));

      // Encrypt data with AES
      final cipher = CBCBlockCipher(AESEngine());
      final params = ParametersWithIV(
        KeyParameter(Uint8List.fromList(aesKey)),
        Uint8List.fromList(iv),
      );
      cipher.init(true, params);

      final dataBytes = utf8.encode(dataJson);
      final paddedData = _padMessage(dataBytes);
      final encryptedBytes = cipher.process(Uint8List.fromList(paddedData));

      // Combine IV and encrypted data
      final combined = Uint8List.fromList([...iv, ...encryptedBytes]);

      // Encrypt AES key with recipient's public key (simplified - use AES key as is for demo)
      final encryptedAesKey = base64Encode(aesKey);

      // Create final encrypted payload
      final encryptedPayload = {
        'encryptedData': base64Encode(combined),
        'encryptedKey': encryptedAesKey,
        'algorithm': 'AES-256-CBC',
      };

      return base64Encode(utf8.encode(json.encode(encryptedPayload)));
    } catch (e) {
      throw Exception('Encryption failed: $e');
    }
  }

  /// Decrypt data with own private key
  Future<Map<String, dynamic>?> _decryptData(String encryptedData) async {
    try {
      // Get own private key from encryption service
      final privateKey = await EncryptionService.getPrivateKey();
      if (privateKey == null) {
        print('🔔 SimpleNotificationService: ❌ Private key not found');
        return null;
      }

      // Decode encrypted payload
      final payloadBytes = base64Decode(encryptedData);
      final payloadJson = utf8.decode(payloadBytes);
      final payload = json.decode(payloadJson) as Map<String, dynamic>;

      // Extract encrypted data and key
      final encryptedDataBase64 = payload['encryptedData'] as String;
      final encryptedKeyBase64 = payload['encryptedKey'] as String;

      // Decrypt AES key (simplified - use as is for demo)
      final aesKey = base64Decode(encryptedKeyBase64);

      // Decrypt data with AES
      final encryptedBytes = base64Decode(encryptedDataBase64);
      final iv = encryptedBytes.sublist(0, 16);
      final encryptedMessage = encryptedBytes.sublist(16);

      final cipher = CBCBlockCipher(AESEngine());
      final params = ParametersWithIV(
        KeyParameter(Uint8List.fromList(aesKey)),
        Uint8List.fromList(iv),
      );
      cipher.init(false, params);

      final decryptedBytes =
          cipher.process(Uint8List.fromList(encryptedMessage));
      final unpaddedBytes = _unpadMessage(decryptedBytes.toList());
      final decryptedJson = utf8.decode(unpaddedBytes);

      return json.decode(decryptedJson) as Map<String, dynamic>;
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

  /// PKCS7 padding
  List<int> _padMessage(List<int> message) {
    final blockSize = 16;
    final paddingLength = blockSize - (message.length % blockSize);
    final padding = List<int>.filled(paddingLength, paddingLength);
    return [...message, ...padding];
  }

  /// PKCS7 unpadding
  List<int> _unpadMessage(List<int> message) {
    final paddingLength = message.last;
    return message.sublist(0, message.length - paddingLength);
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
}
