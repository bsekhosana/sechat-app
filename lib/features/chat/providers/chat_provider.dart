import 'package:flutter/foundation.dart';
import '../../../core/services/simple_notification_service.dart';
import '../../../core/services/encryption_service.dart';
import '../../../core/services/se_session_service.dart';

import '../models/message.dart';
import '../services/message_storage_service.dart';
import '../services/message_status_tracking_service.dart';
import '../services/text_message_service.dart';
import '../services/voice_message_service.dart';
import '../services/image_message_service.dart';
import '../services/video_message_service.dart';
import '../services/document_message_service.dart';
import '../services/location_message_service.dart';
import '../services/contact_message_service.dart';
import '../services/contact_message_service.dart' show ContactData;
import '../../../core/services/airnotifier_service.dart';

/// Provider for managing individual chat conversation state and operations
class ChatProvider extends ChangeNotifier {
  final MessageStorageService _storageService = MessageStorageService.instance;
  final MessageStatusTrackingService _statusTrackingService =
      MessageStatusTrackingService.instance;

  // Default constructor
  ChatProvider();

  // Message services
  final TextMessageService _textMessageService = TextMessageService.instance;
  final VoiceMessageService _voiceMessageService = VoiceMessageService.instance;
  final ImageMessageService _imageMessageService = ImageMessageService.instance;
  final VideoMessageService _videoMessageService = VideoMessageService.instance;
  final DocumentMessageService _documentMessageService =
      DocumentMessageService.instance;
  final LocationMessageService _locationMessageService =
      LocationMessageService.instance;
  final ContactMessageService _contactMessageService =
      ContactMessageService.instance;

  // State
  String? _conversationId;
  String? _recipientId;
  List<Message> _messages = [];
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _isMuted = false;
  bool _isRecipientTyping = false;

  // Static registry of active chat providers
  static final Map<String, ChatProvider> _instances = <String, ChatProvider>{};
  DateTime? _recipientLastSeen;
  bool _isRecipientOnline = false;

  // Getters
  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;
  bool get isMuted => _isMuted;
  bool get isRecipientTyping => _isRecipientTyping;
  DateTime? get recipientLastSeen => _recipientLastSeen;
  bool get isRecipientOnline => _isRecipientOnline;

  /// Initialize the chat provider
  Future<void> initialize({
    required String conversationId,
    required String recipientId,
    required String recipientName,
  }) async {
    // Register this instance for incoming messages
    _instances[conversationId] = this;
    try {
      _setLoading(true);

      _conversationId = conversationId;
      _recipientId = recipientId;

      await _loadConversation();
      await _loadMessages();
      _setupStatusTracking();

      _setLoading(false);

      print('💬 ChatProvider: ✅ Initialized for conversation: $conversationId');
    } catch (e) {
      _setError('Failed to initialize chat: $e');
    }
  }

  /// Load conversation details
  Future<void> _loadConversation() async {
    try {
      if (_conversationId == null) return;

      final conversation =
          await _storageService.getConversation(_conversationId!);
      if (conversation != null) {
        _isMuted = conversation.isMuted;
        _recipientLastSeen = conversation.lastSeen;
        _isRecipientOnline = _isUserOnline(_recipientLastSeen);
      }
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to load conversation: $e');
    }
  }

  /// Load messages for the conversation
  Future<void> _loadMessages() async {
    try {
      if (_conversationId == null) return;

      final messages = await _storageService.getConversationMessages(
        _conversationId!,
        limit: 100,
      );

      // Sort messages by creation time (newest first for display)
      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      _messages = messages;

      print('💬 ChatProvider: ✅ Loaded ${messages.length} messages');

      // Notify listeners to update UI
      notifyListeners();
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to load messages: $e');
    }
  }

  /// Setup status tracking for real-time updates
  void _setupStatusTracking() {
    // Listen for typing indicator updates
    _statusTrackingService.typingIndicatorStream.listen((update) {
      if (update.conversationId == _conversationId) {
        _isRecipientTyping = update.isTyping;
        notifyListeners();
      }
    });

    // Listen for last seen updates
    _statusTrackingService.lastSeenStream.listen((update) {
      if (update.userId == _recipientId) {
        _recipientLastSeen = update.timestamp;
        _isRecipientOnline = _isUserOnline(_recipientLastSeen);
        notifyListeners();
      }
    });

    // Listen for message status updates
    _statusTrackingService.statusUpdateStream.listen((update) {
      _updateMessageStatus(update);
    });
  }

  /// Check if user is online (within last 5 minutes)
  bool _isUserOnline(DateTime? lastSeen) {
    if (lastSeen == null) return false;

    final now = DateTime.now();
    final difference = now.difference(lastSeen);
    return difference.inMinutes < 5;
  }

  /// Update message status
  void _updateMessageStatus(MessageStatusUpdate update) {
    // If the status is "read", mark all sent and delivered messages as read
    if (update.status == MessageStatus.read) {
      bool updated = false;

      // Update all messages sent by the current user that are not yet read
      for (int i = 0; i < _messages.length; i++) {
        final message = _messages[i];

        // Only update messages sent by current user and not yet read
        if (message.senderId == _getCurrentUserId() &&
            (message.status == MessageStatus.sent ||
                message.status == MessageStatus.delivered)) {
          _messages[i] = message.copyWith(
            status: MessageStatus.read,
            readAt: DateTime.now(),
          );
          updated = true;

          // Also update in storage
          _storageService.saveMessage(_messages[i]);
        }
      }

      if (updated) {
        notifyListeners();
      }
    } else {
      // For other statuses, just update the specific message
      final index = _messages.indexWhere((msg) => msg.id == update.messageId);
      if (index != -1) {
        final message = _messages[index];
        final updatedMessage = message.copyWith(
          status: update.status,
          deliveredAt: update.status == MessageStatus.delivered
              ? DateTime.now()
              : message.deliveredAt,
          readAt: update.status == MessageStatus.read
              ? DateTime.now()
              : message.readAt,
        );

        _messages[index] = updatedMessage;

        // Also update in storage
        _storageService.saveMessage(updatedMessage);

        notifyListeners();
      }
    }
  }

  /// Update message status from notification (internal method)
  void _updateMessageStatusFromNotification(
      String messageId, MessageStatus status) {
    final index = _messages.indexWhere((msg) => msg.id == messageId);
    if (index != -1) {
      final message = _messages[index];
      final updatedMessage = message.copyWith(
        status: status,
        deliveredAt: status == MessageStatus.delivered
            ? DateTime.now()
            : message.deliveredAt,
        readAt: status == MessageStatus.read ? DateTime.now() : message.readAt,
      );

      _messages[index] = updatedMessage;

      // Also update in storage
      _storageService.saveMessage(updatedMessage);

      // Notify listeners to update UI
      notifyListeners();

      print(
          '💬 ChatProvider: ✅ Message status updated in UI: $messageId -> $status');
    } else {
      print(
          '💬 ChatProvider: ⚠️ Message not found for status update: $messageId');
    }
  }

  /// Send text message
  Future<void> sendTextMessage(String text) async {
    try {
      if (_conversationId == null || _recipientId == null) {
        throw Exception('Chat not initialized');
      }

      // Send message via local service first
      final message = await _textMessageService.sendTextMessage(
        conversationId: _conversationId!,
        recipientId: _recipientId!,
        text: text,
      );

      if (message != null) {
        _addMessage(message);
        await _updateConversationWithMessage(message);
      }

      // Send encrypted push notification to recipient
      try {
        // Create message data for encryption
        final messageData = {
          'type': 'message',
          'message_id':
              message?.id ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
          'sender_id': _getCurrentUserId(),
          'sender_name': _getCurrentUserId(),
          'message': text,
          'conversation_id': _conversationId!,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };

        // Create properly encrypted payload using EncryptionService
        final encryptedPayload = await EncryptionService.createEncryptedPayload(
            messageData, _recipientId!);

        // Send using the encrypted payload
        final success =
            await SimpleNotificationService.instance.sendEncryptedMessage(
          recipientId: _recipientId!,
          senderName: _getCurrentUserId(),
          message: text,
          conversationId: _conversationId!,
          encryptedData: encryptedPayload['data'] as String,
          checksum: encryptedPayload['checksum'] as String,
          messageId:
              message?.id ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
        );

        if (success) {
          print('💬 ChatProvider: ✅ Encrypted push notification sent');
        } else {
          print(
              '💬 ChatProvider: ⚠️ Failed to send encrypted push notification');
        }
      } catch (notificationError) {
        print(
            '💬 ChatProvider: ⚠️ Error sending encrypted push notification: $notificationError');
        // Don't rethrow - local message was sent successfully
      }

      print('💬 ChatProvider: ✅ Text message sent');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to send text message: $e');
      rethrow;
    }
  }

  /// Send voice message
  Future<void> sendVoiceMessage(int duration, String filePath) async {
    try {
      if (_conversationId == null || _recipientId == null) {
        throw Exception('Chat not initialized');
      }

      final message = await _voiceMessageService.sendVoiceMessage(
        conversationId: _conversationId!,
        recipientId: _recipientId!,
        audioFilePath: filePath,
        duration: duration,
      );

      if (message != null) {
        _addMessage(message);
        await _updateConversationWithMessage(message);
      }

      print('💬 ChatProvider: ✅ Voice message sent');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to send voice message: $e');
      rethrow;
    }
  }

  /// Send image message
  Future<void> sendImageMessage(String filePath) async {
    try {
      if (_conversationId == null || _recipientId == null) {
        throw Exception('Chat not initialized');
      }

      final message = await _imageMessageService.sendImageMessage(
        conversationId: _conversationId!,
        recipientId: _recipientId!,
        imageFilePath: filePath,
      );

      if (message != null) {
        _addMessage(message);
        await _updateConversationWithMessage(message);
      }

      print('💬 ChatProvider: ✅ Image message sent');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to send image message: $e');
      rethrow;
    }
  }

  /// Send video message
  Future<void> sendVideoMessage(String filePath) async {
    try {
      if (_conversationId == null || _recipientId == null) {
        throw Exception('Chat not initialized');
      }

      final message = await _videoMessageService.sendVideoMessage(
        conversationId: _conversationId!,
        recipientId: _recipientId!,
        videoFilePath: filePath,
        duration: 0, // This should be calculated from the actual video file
      );

      if (message != null) {
        _addMessage(message);
        await _updateConversationWithMessage(message);
      }

      print('💬 ChatProvider: ✅ Video message sent');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to send video message: $e');
      rethrow;
    }
  }

  /// Send document message
  Future<void> sendDocumentMessage(String filePath) async {
    try {
      if (_conversationId == null || _recipientId == null) {
        throw Exception('Chat not initialized');
      }

      final message = await _documentMessageService.sendDocumentMessage(
        conversationId: _conversationId!,
        recipientId: _recipientId!,
        documentFilePath: filePath,
      );

      if (message != null) {
        _addMessage(message);
        await _updateConversationWithMessage(message);
      }

      print('💬 ChatProvider: ✅ Document message sent');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to send document message: $e');
      rethrow;
    }
  }

  /// Send location message
  Future<void> sendLocationMessage(double latitude, double longitude) async {
    try {
      if (_conversationId == null || _recipientId == null) {
        throw Exception('Chat not initialized');
      }

      final message = await _locationMessageService.sendLocationMessage(
        conversationId: _conversationId!,
        recipientId: _recipientId!,
        location: LocationData(
          latitude: latitude,
          longitude: longitude,
          accuracy: LocationAccuracy.high,
          timestamp: DateTime.now(),
          source: LocationSource.gps,
        ),
      );

      if (message != null) {
        _addMessage(message);
        await _updateConversationWithMessage(message);
      }

      print('💬 ChatProvider: ✅ Location message sent');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to send location message: $e');
      rethrow;
    }
  }

  /// Send contact message
  Future<void> sendContactMessage(ContactData contactData) async {
    try {
      if (_conversationId == null || _recipientId == null) {
        throw Exception('Chat not initialized');
      }

      final message = await _contactMessageService.sendContactMessage(
        conversationId: _conversationId!,
        recipientId: _recipientId!,
        contact: contactData,
      );

      if (message != null) {
        _addMessage(message);
        await _updateConversationWithMessage(message);
      }

      print('💬 ChatProvider: ✅ Contact message sent');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to send contact message: $e');
      rethrow;
    }
  }

  /// Send emoticon message
  Future<void> sendEmoticonMessage(String emoticon) async {
    try {
      if (_conversationId == null || _recipientId == null) {
        throw Exception('Chat not initialized');
      }

      final message = await _textMessageService.sendEmoticonMessage(
        conversationId: _conversationId!,
        recipientId: _recipientId!,
        emoticon: emoticon,
      );

      if (message != null) {
        _addMessage(message);
        await _updateConversationWithMessage(message);
      }

      print('💬 ChatProvider: ✅ Emoticon message sent');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to send emoticon message: $e');
      rethrow;
    }
  }

  /// Update typing indicator
  Future<void> updateTypingIndicator(bool isTyping) async {
    try {
      if (_conversationId == null || _recipientId == null) return;

      // DON'T update local typing indicator for current user
      // This prevents "You are typing..." from showing on sender's device
      // await _statusTrackingService.updateTypingIndicator(
      //   _conversationId!,
      //   _recipientId!,
      //   isTyping,
      // );

      // Send typing indicator to recipient via push notification
      try {
        // Send typing indicator via AirNotifier
        final airNotifier = AirNotifierService.instance;
        final success = await airNotifier.sendTypingIndicator(
          recipientId: _recipientId!,
          senderName: airNotifier.currentUserId ?? 'Anonymous User',
          isTyping: isTyping,
        );

        if (success) {
          print(
              '💬 ChatProvider: ✅ Typing indicator sent to recipient: $isTyping');
        } else {
          print(
              '💬 ChatProvider: ⚠️ Failed to send typing indicator to recipient');
        }
      } catch (e) {
        print(
            '💬 ChatProvider: ⚠️ Failed to send typing indicator to recipient: $e');
        // Don't rethrow - local typing indicator still works
      }

      print('💬 ChatProvider: ✅ Typing indicator sent to recipient: $isTyping');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to update typing indicator: $e');
    }
  }

  /// Add message to local list
  void _addMessage(Message message) {
    // Check if message already exists to avoid duplicates
    final existingIndex = _messages.indexWhere((m) => m.id == message.id);
    if (existingIndex != -1) {
      // Update existing message if needed
      _messages[existingIndex] = message;
    } else {
      // Add new message
      _messages.add(message);
    }

    // Sort messages by creation time (newest first for display)
    // This works with ListView.builder(reverse: true) to show newest at bottom
    _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    notifyListeners();

    // Scroll to bottom after adding a new message
    // This is handled by the ChatScreen
  }

  /// Update conversation with new message
  Future<void> _updateConversationWithMessage(Message message) async {
    try {
      if (_conversationId == null) return;

      final conversation =
          await _storageService.getConversation(_conversationId!);
      if (conversation != null) {
        final updatedConversation = conversation.updateWithNewMessage(
          messageId: message.id,
          messagePreview: message.previewText,
          messageType: _convertToConversationMessageType(message.type),
          isFromCurrentUser: message.senderId == _getCurrentUserId(),
        );

        await _storageService.saveConversation(updatedConversation);
      }
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to update conversation: $e');
    }
  }

  /// Convert MessageType to conversation MessageType
  MessageType _convertToConversationMessageType(MessageType type) {
    // Since we're using the same MessageType enum, just return the type directly
    return type;
  }

  /// Handle incoming message for this conversation
  /// This is called from SimpleNotificationService or ChatListProvider
  static Future<bool> handleIncomingMessage({
    required String conversationId,
    required Message message,
  }) async {
    // Find the provider instance for this conversation
    final provider = _instances[conversationId];
    if (provider != null) {
      // Add message to the conversation
      provider._addMessage(message);

      // Send delivery receipt
      try {
        final airNotifier = AirNotifierService.instance;
        final success = await airNotifier.sendMessageDeliveryStatus(
          recipientId: message.senderId,
          messageId: message.id,
          status: 'delivered',
          conversationId: conversationId,
        );

        if (success) {
          print(
              '💬 ChatProvider: ✅ Delivery receipt sent for message: ${message.id}');
        } else {
          print('💬 ChatProvider: ⚠️ Failed to send delivery receipt');
        }
      } catch (e) {
        print('💬 ChatProvider: ❌ Failed to send delivery receipt: $e');
      }

      return true;
    }
    return false;
  }

  /// Update message status from notification (called by SimpleNotificationService)
  static Future<bool> updateMessageStatusFromNotification({
    required String conversationId,
    required String messageId,
    required MessageStatus status,
  }) async {
    // Find the provider instance for this conversation
    final provider = _instances[conversationId];
    if (provider != null) {
      // Update the message status in the UI
      provider._updateMessageStatusFromNotification(messageId, status);
      return true;
    }
    return false;
  }

  /// Refresh messages
  Future<void> refreshMessages() async {
    try {
      await _loadMessages();
      notifyListeners();
    } catch (e) {
      _setError('Failed to refresh messages: $e');
    }
  }

  /// Mark conversation as read and send read receipts
  Future<void> markAsRead() async {
    try {
      if (_conversationId == null || _recipientId == null) return;

      // Update conversation in database
      final conversation =
          await _storageService.getConversation(_conversationId!);
      if (conversation != null) {
        // Mark as read locally
        final updatedConversation = conversation.markAsRead();
        await _storageService.saveConversation(updatedConversation);

        // Send read receipts for all unread messages
        final unreadMessages = _messages
            .where((msg) =>
                msg.senderId == _recipientId &&
                (msg.status == MessageStatus.sent ||
                    msg.status == MessageStatus.delivered))
            .toList();

        if (unreadMessages.isNotEmpty) {
          print(
              '💬 ChatProvider: Sending read receipts for ${unreadMessages.length} messages');

          // Send read receipts for each message
          for (final message in unreadMessages) {
            try {
              final airNotifier = AirNotifierService.instance;
              final success = await airNotifier.sendMessageDeliveryStatus(
                recipientId: _recipientId!,
                messageId: message.id,
                status: 'read',
                conversationId: _conversationId!,
              );

              if (success) {
                // Update message status locally
                final updatedMessage =
                    message.copyWith(status: MessageStatus.read);
                final index = _messages.indexWhere((m) => m.id == message.id);
                if (index != -1) {
                  _messages[index] = updatedMessage;
                }

                // Update message in database
                await _storageService.saveMessage(updatedMessage);

                print(
                    '💬 ChatProvider: ✅ Read receipt sent for message: ${message.id}');
              }
            } catch (e) {
              print('💬 ChatProvider: ❌ Failed to send read receipt: $e');
            }
          }

          // Notify listeners to update UI
          notifyListeners();
        }
      }
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to mark conversation as read: $e');
    }
  }

  /// Toggle mute notifications
  Future<void> toggleMuteNotifications() async {
    try {
      if (_conversationId == null) return;

      _isMuted = !_isMuted;

      final conversation =
          await _storageService.getConversation(_conversationId!);
      if (conversation != null) {
        final updatedConversation = conversation.toggleMute();
        await _storageService.saveConversation(updatedConversation);
      }

      notifyListeners();

      print(
          '💬 ChatProvider: ✅ Notifications ${_isMuted ? 'muted' : 'unmuted'}');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to toggle mute notifications: $e');
    }
  }

  /// Delete conversation
  Future<void> deleteConversation() async {
    try {
      if (_conversationId == null) return;

      await _storageService.deleteConversation(_conversationId!);

      print('💬 ChatProvider: ✅ Conversation deleted');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to delete conversation: $e');
    }
  }

  /// Update conversation settings
  Future<void> updateConversationSettings(
    String conversationId, {
    bool? notificationsEnabled,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? readReceiptsEnabled,
    bool? typingIndicatorsEnabled,
    bool? lastSeenEnabled,
    bool? mediaAutoDownload,
    bool? encryptMedia,
    String? mediaQuality,
    String? messageRetention,
  }) async {
    try {
      final conversation =
          await _storageService.getConversation(conversationId);
      if (conversation == null) return;

      final updatedConversation = conversation.copyWith(
        notificationsEnabled:
            notificationsEnabled ?? conversation.notificationsEnabled,
        soundEnabled: soundEnabled ?? conversation.soundEnabled,
        vibrationEnabled: vibrationEnabled ?? conversation.vibrationEnabled,
        readReceiptsEnabled:
            readReceiptsEnabled ?? conversation.readReceiptsEnabled,
        typingIndicatorsEnabled:
            typingIndicatorsEnabled ?? conversation.typingIndicatorsEnabled,
        lastSeenEnabled: lastSeenEnabled ?? conversation.lastSeenEnabled,
        mediaAutoDownload: mediaAutoDownload ?? conversation.mediaAutoDownload,
        encryptMedia: encryptMedia ?? conversation.encryptMedia,
        mediaQuality: mediaQuality ?? conversation.mediaQuality,
        messageRetention: messageRetention ?? conversation.messageRetention,
        updatedAt: DateTime.now(),
      );

      await _storageService.saveConversation(updatedConversation);

      print('💬 ChatProvider: ✅ Conversation settings updated');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to update conversation settings: $e');
    }
  }

  /// Clear conversation media cache
  Future<void> clearConversationMedia(String conversationId) async {
    try {
      await _storageService.clearConversationMedia(conversationId);
      print('💬 ChatProvider: ✅ Conversation media cache cleared');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to clear conversation media: $e');
    }
  }

  /// Export conversation
  Future<void> exportConversation(String conversationId, String format) async {
    try {
      await _storageService.exportConversation(conversationId, format);
      print('💬 ChatProvider: ✅ Conversation exported as $format');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to export conversation: $e');
    }
  }

  /// Block user
  Future<void> blockUser(String userId) async {
    try {
      // This will integrate with the API service to block the user
      // For now, we'll just mark the conversation as blocked locally
      if (_conversationId == null) return;

      final conversation =
          await _storageService.getConversation(_conversationId!);
      if (conversation == null) return;

      final updatedConversation = conversation.copyWith(
        isBlocked: true,
        blockedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _storageService.saveConversation(updatedConversation);

      print('💬 ChatProvider: ✅ User blocked');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to block user: $e');
    }
  }

  /// Delete message
  Future<void> deleteMessage(String messageId) async {
    try {
      // Remove from local list
      _messages.removeWhere((msg) => msg.id == messageId);
      notifyListeners();

      // Mark as deleted in storage
      final message = await _getMessageById(messageId);
      if (message != null) {
        final deletedMessage = message.copyWith(
          status: MessageStatus.deleted,
          deletedAt: DateTime.now(),
        );
        await _storageService.saveMessage(deletedMessage);
      }

      print('💬 ChatProvider: ✅ Message deleted');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to delete message: $e');
    }
  }

  /// Get message by ID
  Future<Message?> _getMessageById(String messageId) async {
    try {
      // This will be implemented when we add message retrieval to the storage service
      // For now, return null
      return null;
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to get message: $e');
      return null;
    }
  }

  /// Get current user ID
  String _getCurrentUserId() {
    try {
      // Get the current user ID from the session service
      final sessionId = SeSessionService().currentSessionId;
      if (sessionId != null && sessionId.isNotEmpty) {
        return sessionId;
      }

      // Fallback: try to get from conversation participants
      if (_conversationId != null) {
        // This is a temporary fallback - in a real app, we'd get this from auth service
        print('💬 ChatProvider: ⚠️ Using fallback user ID from conversation');
        return _conversationId!;
      }

      // Last resort fallback
      print(
          '💬 ChatProvider: ⚠️ No user ID available, using timestamp fallback');
      return 'user_${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      print('💬 ChatProvider: ❌ Error getting current user ID: $e');
      return 'user_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    if (loading) {
      _hasError = false;
      _errorMessage = null;
    }
  }

  /// Set error state
  void _setError(String message) {
    _hasError = true;
    _errorMessage = message;
    _isLoading = false;
    print('💬 ChatProvider: ❌ Error: $message');
  }

  /// Clear error state
  void clearError() {
    _hasError = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Dispose of resources
  @override
  void dispose() {
    // Unregister this instance when disposed
    if (_conversationId != null) {
      _instances.remove(_conversationId);
    }
    print('💬 ChatProvider: ✅ Provider disposed');
    super.dispose();
  }
}
