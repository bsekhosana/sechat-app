import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/message.dart';
import '../models/chat_conversation.dart';
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
  String? _recipientName;
  List<Message> _messages = [];
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _isMuted = false;
  bool _isRecipientTyping = false;
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
    try {
      _setLoading(true);

      _conversationId = conversationId;
      _recipientId = recipientId;
      _recipientName = recipientName;

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

      // Sort messages by creation time (oldest first for display)
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      _messages = messages;

      print('💬 ChatProvider: ✅ Loaded ${messages.length} messages');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to load messages: $e');
    }
  }

  /// Setup status tracking for real-time updates
  void _setupStatusTracking() {
    // Listen for typing indicator updates
    _statusTrackingService.typingIndicatorStream?.listen((update) {
      if (update.conversationId == _conversationId) {
        _isRecipientTyping = update.isTyping;
        notifyListeners();
      }
    });

    // Listen for last seen updates
    _statusTrackingService.lastSeenStream?.listen((update) {
      if (update.userId == _recipientId) {
        _recipientLastSeen = update.timestamp;
        _isRecipientOnline = _isUserOnline(_recipientLastSeen);
        notifyListeners();
      }
    });

    // Listen for message status updates
    _statusTrackingService.statusUpdateStream?.listen((update) {
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
    final index = _messages.indexWhere((msg) => msg.id == update.messageId);
    if (index != -1) {
      final message = _messages[index];
      final updatedMessage = message.copyWith(
        status: update.status,
      );

      _messages[index] = updatedMessage;
      notifyListeners();
    }
  }

  /// Send text message
  Future<void> sendTextMessage(String text) async {
    try {
      if (_conversationId == null || _recipientId == null) {
        throw Exception('Chat not initialized');
      }

      final message = await _textMessageService.sendTextMessage(
        conversationId: _conversationId!,
        recipientId: _recipientId!,
        text: text,
      );

      if (message != null) {
        _addMessage(message);
        await _updateConversationWithMessage(message);
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

      await _statusTrackingService.updateTypingIndicator(
        _conversationId!,
        _recipientId!,
        isTyping,
      );

      print('💬 ChatProvider: ✅ Typing indicator updated: $isTyping');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to update typing indicator: $e');
    }
  }

  /// Add message to local list
  void _addMessage(Message message) {
    _messages.add(message);
    // Sort messages by creation time (oldest first for display)
    _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    notifyListeners();
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

  /// Refresh messages
  Future<void> refreshMessages() async {
    try {
      await _loadMessages();
      notifyListeners();
    } catch (e) {
      _setError('Failed to refresh messages: $e');
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
    // This will be implemented when we integrate with the session service
    // For now, return a placeholder
    return 'current_user_id';
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
    print('💬 ChatProvider: ✅ Provider disposed');
    super.dispose();
  }
}
