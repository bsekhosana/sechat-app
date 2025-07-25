import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'local_storage_service.dart';
import 'encryption_service.dart';
import '../../shared/models/chat.dart';
import '../../shared/models/message.dart';
import '../../shared/models/user.dart';
import '../../shared/models/invitation.dart';

class NotificationDataSyncService {
  static final NotificationDataSyncService _instance =
      NotificationDataSyncService._internal();
  factory NotificationDataSyncService() => _instance;
  NotificationDataSyncService._internal();

  static NotificationDataSyncService get instance => _instance;

  final LocalStorageService _storage = LocalStorageService.instance;
  final Uuid _uuid = const Uuid();

  // Process notification and update local database
  Future<void> processNotification(
      Map<String, dynamic> notificationData) async {
    try {
      final type = notificationData['type'] as String?;
      final action = notificationData['action'] as String?;
      final timestamp = notificationData['timestamp'] as int?;

      if (type == null || action == null) {
        print(
            '📱 NotificationDataSync: Invalid notification data - missing type or action');
        return;
      }

      print(
          '📱 NotificationDataSync: Processing notification - type: $type, action: $action');

      switch (type) {
        case 'invitation':
          await _handleInvitationNotification(notificationData);
          break;
        case 'invitation_response':
          await _handleInvitationResponseNotification(notificationData);
          break;
        case 'invitation_update':
          await _handleInvitationUpdateNotification(notificationData);
          break;
        case 'message':
          await _handleMessageNotification(notificationData);
          break;
        case 'message_delivery_status':
          await _handleMessageDeliveryStatusNotification(notificationData);
          break;
        case 'typing_indicator':
          await _handleTypingIndicatorNotification(notificationData);
          break;
        case 'online_status_update':
          await _handleOnlineStatusUpdateNotification(notificationData);
          break;
        default:
          print('📱 NotificationDataSync: Unknown notification type: $type');
      }

      // Save notification to local database
      await _saveNotificationToLocalDB(notificationData);
    } catch (e) {
      print('📱 NotificationDataSync: Error processing notification: $e');
    }
  }

  // Handle invitation notification
  Future<void> _handleInvitationNotification(Map<String, dynamic> data) async {
    try {
      final invitationId = data['invitationId'] as String?;
      final senderId = data['senderId'] as String?;
      final senderName = data['senderName'] as String?;
      final message = data['message'] as String?;

      if (invitationId == null || senderId == null || senderName == null) {
        print('📱 NotificationDataSync: Invalid invitation notification data');
        return;
      }

      // Create invitation object
      final invitation = Invitation(
        id: invitationId,
        senderId: senderId,
        recipientId: _getCurrentUserId(),
        message: message ?? 'Would you like to connect?',
        status: 'pending',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isReceived: true,
        senderUsername: senderName,
      );

      // Save to local database
      await _storage.saveInvitation(invitation.toJson());

      // Create user object for sender
      final user = User(
        id: senderId,
        username: senderName,
        profilePicture: null,
        isOnline: false,
        lastSeen: DateTime.now(),
        alreadyInvited: true,
        invitationStatus: 'pending',
      );

      await _storage.saveUser(user);

      print(
          '📱 NotificationDataSync: Invitation saved to local DB: $invitationId');
    } catch (e) {
      print(
          '📱 NotificationDataSync: Error handling invitation notification: $e');
    }
  }

  // Handle invitation response notification
  Future<void> _handleInvitationResponseNotification(
      Map<String, dynamic> data) async {
    try {
      final invitationId = data['invitationId'] as String?;
      final status = data['status'] as String?;
      final responderId = data['responderId'] as String?;
      final responderName = data['responderName'] as String?;
      final chatId = data['chatId'] as String?;

      if (invitationId == null ||
          status == null ||
          responderId == null ||
          responderName == null) {
        print(
            '📱 NotificationDataSync: Invalid invitation response notification data');
        return;
      }

      // Update invitation status
      final existingInvitation = _storage.getInvitation(invitationId);
      if (existingInvitation != null) {
        final updatedInvitation =
            Invitation.fromJson(existingInvitation).copyWith(
          status: status,
          updatedAt: DateTime.now(),
          acceptedAt: status == 'accepted' ? DateTime.now() : null,
          declinedAt: status == 'declined' ? DateTime.now() : null,
        );

        await _storage.saveInvitation(updatedInvitation.toJson());
      }

      // If accepted, create chat object
      if (status == 'accepted' && chatId != null) {
        await _createChatFromInvitation(
            invitationId, chatId, responderId, responderName);
      }

      print(
          '📱 NotificationDataSync: Invitation response processed: $invitationId - $status');
    } catch (e) {
      print(
          '📱 NotificationDataSync: Error handling invitation response notification: $e');
    }
  }

  // Handle invitation update (silent notification)
  Future<void> _handleInvitationUpdateNotification(
      Map<String, dynamic> data) async {
    try {
      final invitationId = data['invitationId'] as String?;
      final action = data['action'] as String?;
      final senderId = data['senderId'] as String?;
      final senderName = data['senderName'] as String?;

      if (invitationId == null || action == null || senderId == null) {
        print(
            '📱 NotificationDataSync: Invalid invitation update notification data');
        return;
      }

      // Update invitation based on action
      final existingInvitation = _storage.getInvitation(invitationId);
      if (existingInvitation != null) {
        final invitation = Invitation.fromJson(existingInvitation);

        Invitation updatedInvitation;
        switch (action) {
          case 'received':
            // Already handled by invitation notification
            return;
          case 'accepted':
            updatedInvitation = invitation.copyWith(
              status: 'accepted',
              updatedAt: DateTime.now(),
              acceptedAt: DateTime.now(),
            );
            break;
          case 'declined':
            updatedInvitation = invitation.copyWith(
              status: 'declined',
              updatedAt: DateTime.now(),
              declinedAt: DateTime.now(),
            );
            break;
          default:
            print(
                '📱 NotificationDataSync: Unknown invitation action: $action');
            return;
        }

        await _storage.saveInvitation(updatedInvitation.toJson());
        print(
            '📱 NotificationDataSync: Invitation updated via silent notification: $invitationId - $action');
      }
    } catch (e) {
      print(
          '📱 NotificationDataSync: Error handling invitation update notification: $e');
    }
  }

  // Handle message notification
  Future<void> _handleMessageNotification(Map<String, dynamic> data) async {
    try {
      final senderId = data['senderId'] as String?;
      final senderName = data['senderName'] as String?;
      final message = data['message'] as String?;
      final conversationId = data['conversationId'] as String?;

      if (senderId == null ||
          senderName == null ||
          message == null ||
          conversationId == null) {
        print('📱 NotificationDataSync: Invalid message notification data');
        return;
      }

      // Create message object
      final messageObj = Message(
        id: _uuid.v4(),
        chatId: conversationId,
        senderId: senderId,
        content: message,
        type: MessageType.text,
        status: 'received',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Save message to local database
      await _storage.saveMessage(messageObj);

      // Update or create chat
      await _updateOrCreateChat(
          conversationId, senderId, senderName, messageObj);

      // Send delivery confirmation
      await _sendDeliveryConfirmation(senderId, messageObj.id, conversationId);

      print(
          '📱 NotificationDataSync: Message saved to local DB: ${messageObj.id}');
    } catch (e) {
      print('📱 NotificationDataSync: Error handling message notification: $e');
    }
  }

  // Handle message delivery status notification
  Future<void> _handleMessageDeliveryStatusNotification(
      Map<String, dynamic> data) async {
    try {
      final messageId = data['messageId'] as String?;
      final status = data['status'] as String?;
      final conversationId = data['conversationId'] as String?;

      if (messageId == null || status == null || conversationId == null) {
        print(
            '📱 NotificationDataSync: Invalid message delivery status notification data');
        return;
      }

      // Update message status in local database
      await _storage.updateMessageStatus(conversationId, messageId, status);

      print(
          '📱 NotificationDataSync: Message status updated: $messageId - $status');
    } catch (e) {
      print(
          '📱 NotificationDataSync: Error handling message delivery status notification: $e');
    }
  }

  // Handle typing indicator notification
  Future<void> _handleTypingIndicatorNotification(
      Map<String, dynamic> data) async {
    try {
      final senderId = data['senderId'] as String?;
      final isTyping = data['isTyping'] as bool?;

      if (senderId == null || isTyping == null) {
        print(
            '📱 NotificationDataSync: Invalid typing indicator notification data');
        return;
      }

      // Update typing status (this would typically be handled by the UI)
      print(
          '📱 NotificationDataSync: Typing indicator received: $senderId - $isTyping');
    } catch (e) {
      print(
          '📱 NotificationDataSync: Error handling typing indicator notification: $e');
    }
  }

  // Handle online status update notification
  Future<void> _handleOnlineStatusUpdateNotification(
      Map<String, dynamic> data) async {
    try {
      final senderId = data['senderId'] as String?;
      final isOnline = data['isOnline'] as bool?;
      final lastSeen = data['lastSeen'] as String?;

      if (senderId == null || isOnline == null) {
        print(
            '📱 NotificationDataSync: Invalid online status update notification data');
        return;
      }

      // Update user's online status
      final existingUser = _storage.getUser(senderId);
      if (existingUser != null) {
        final user = User.fromJson(existingUser);
        final updatedUser = user.copyWith(
          isOnline: isOnline,
          lastSeen:
              lastSeen != null ? DateTime.parse(lastSeen) : DateTime.now(),
        );

        await _storage.saveUser(updatedUser);
        print(
            '📱 NotificationDataSync: User online status updated: $senderId - $isOnline');
      }
    } catch (e) {
      print(
          '📱 NotificationDataSync: Error handling online status update notification: $e');
    }
  }

  // Create chat from accepted invitation
  Future<void> _createChatFromInvitation(String invitationId, String chatId,
      String otherUserId, String otherUsername) async {
    try {
      // Create chat object
      final chat = Chat(
        id: chatId,
        user1Id: _getCurrentUserId(),
        user2Id: otherUserId,
        lastMessageAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        otherUser: {
          'id': otherUserId,
          'username': otherUsername,
          'is_online': false,
          'last_seen': DateTime.now().toIso8601String(),
        },
        lastMessage: null,
      );

      // Save chat to local database
      await _storage.saveChat(chat);

      // Create user object for the other user
      final user = User(
        id: otherUserId,
        username: otherUsername,
        profilePicture: null,
        isOnline: false,
        lastSeen: DateTime.now(),
        alreadyInvited: true,
        invitationStatus: 'accepted',
      );

      await _storage.saveUser(user);

      print('📱 NotificationDataSync: Chat created from invitation: $chatId');
    } catch (e) {
      print('📱 NotificationDataSync: Error creating chat from invitation: $e');
    }
  }

  // Update or create chat
  Future<void> _updateOrCreateChat(String chatId, String senderId,
      String senderName, Message message) async {
    try {
      final existingChat = _storage.getChat(chatId);

      if (existingChat != null) {
        // Update existing chat
        final updatedChat = existingChat.copyWith(
          lastMessageAt: message.createdAt,
          lastMessage: message.toJson(),
          updatedAt: message.createdAt,
        );
        await _storage.saveChat(updatedChat);
      } else {
        // Create new chat
        final chat = Chat(
          id: chatId,
          user1Id: _getCurrentUserId(),
          user2Id: senderId,
          lastMessageAt: message.createdAt,
          createdAt: message.createdAt,
          updatedAt: message.createdAt,
          otherUser: {
            'id': senderId,
            'username': senderName,
            'is_online': false,
            'last_seen': DateTime.now().toIso8601String(),
          },
          lastMessage: message.toJson(),
        );
        await _storage.saveChat(chat);
      }
    } catch (e) {
      print('📱 NotificationDataSync: Error updating/creating chat: $e');
    }
  }

  // Send delivery confirmation
  Future<void> _sendDeliveryConfirmation(
      String senderId, String messageId, String conversationId) async {
    try {
      // This would send a silent notification back to confirm delivery
      // Implementation depends on your notification service
      print(
          '📱 NotificationDataSync: Sending delivery confirmation for message: $messageId');
    } catch (e) {
      print('📱 NotificationDataSync: Error sending delivery confirmation: $e');
    }
  }

  // Save notification to local database
  Future<void> _saveNotificationToLocalDB(
      Map<String, dynamic> notificationData) async {
    try {
      final notificationId = notificationData['id'] ?? _uuid.v4();
      final timestamp = notificationData['timestamp'] ??
          DateTime.now().millisecondsSinceEpoch;

      final notificationRecord = {
        'id': notificationId,
        'type': notificationData['type'],
        'action': notificationData['action'],
        'timestamp':
            DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String(),
        'isRead': false,
        'data': notificationData,
      };

      await _storage.saveNotification(notificationRecord);
    } catch (e) {
      print(
          '📱 NotificationDataSync: Error saving notification to local DB: $e');
    }
  }

  // Get current user ID (this should be implemented based on your auth system)
  String _getCurrentUserId() {
    // This should return the current user's Session ID
    // Implementation depends on your auth provider
    return 'current_user_id'; // Placeholder
  }

  // Get invitation from local database
  Map<String, dynamic>? _getInvitation(String invitationId) {
    return _storage.getInvitation(invitationId);
  }

  // Get user from local database
  User? _getUser(String userId) {
    return _storage.getUser(userId);
  }
}
