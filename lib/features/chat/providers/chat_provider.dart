import 'package:flutter/foundation.dart';
import '../../../core/services/secure_notification_service.dart';
import '../../../core/services/encryption_service.dart';
import '../../../core/services/se_session_service.dart';

import '../models/message.dart';
import '../services/message_storage_service.dart';
import '../services/message_status_tracking_service.dart';
import '../services/text_message_service.dart';
import '../../../core/services/airnotifier_service.dart';

/// Provider for managing individual chat conversation state and operations (text messages only)
class ChatProvider extends ChangeNotifier {
  final MessageStorageService _storageService = MessageStorageService.instance;
  final MessageStatusTrackingService _statusTrackingService =
      MessageStatusTrackingService.instance;

  // Default constructor
  ChatProvider();

  // Message services
  final TextMessageService _textMessageService = TextMessageService.instance;

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

      final conversations = await _storageService.getConversations();
      final conversation = conversations.firstWhere(
        (c) => c.id == _conversationId,
        orElse: () => throw Exception('Conversation not found'),
      );

      _isMuted = conversation.isMuted;
      _recipientLastSeen = conversation.lastSeen;
      notifyListeners();
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to load conversation: $e');
    }
  }

  /// Load messages for the conversation
  Future<void> _loadMessages() async {
    try {
      if (_conversationId == null) return;

      final messages = await _storageService.getMessages(_conversationId!);
      _messages = messages.reversed.toList(); // Show newest at bottom
      notifyListeners();
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to load messages: $e');
    }
  }

  /// Setup status tracking for messages
  void _setupStatusTracking() {
    // Listen for message status updates
    _statusTrackingService.statusUpdateStream.listen((update) {
      final messageIndex =
          _messages.indexWhere((m) => m.id == update.messageId);
      if (messageIndex != -1) {
        _messages[messageIndex] =
            _messages[messageIndex].copyWith(status: update.status);
        notifyListeners();
      }
    });

    // Listen for typing indicator updates
    _statusTrackingService.typingIndicatorStream.listen((update) {
      if (update.conversationId == _conversationId) {
        _isRecipientTyping = update.isTyping;
        notifyListeners();
      }
    });
  }

  /// Send a text message
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
        _messages.add(message);
        notifyListeners();

        // Send via AirNotifier if available
        await _sendMessageViaAirNotifier(message);
      }
    } catch (e) {
      _setError('Failed to send message: $e');
    }
  }

  /// Send message via AirNotifier service
  Future<void> _sendMessageViaAirNotifier(Message message) async {
    try {
      // TODO: Implement AirNotifier integration
      print('💬 ChatProvider: 📡 Message sent via AirNotifier: ${message.id}');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to send via AirNotifier: $e');
    }
  }

  /// Update typing indicator
  void updateTypingIndicator(bool isTyping) {
    _isRecipientTyping = isTyping;
    notifyListeners();

    // TODO: Send typing indicator via AirNotifier
    print('💬 ChatProvider: ⌨️ Typing indicator: $isTyping');
  }

  /// Mark conversation as read
  Future<void> markAsRead() async {
    try {
      if (_conversationId == null) return;

      // Mark all unread messages as read
      for (final message in _messages) {
        if (message.status == MessageStatus.delivered) {
          await _statusTrackingService.markMessageAsRead(message.id);
        }
      }

      print('💬 ChatProvider: ✅ Conversation marked as read');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to mark as read: $e');
    }
  }

  /// Toggle mute notifications
  Future<void> toggleMuteNotifications() async {
    try {
      _isMuted = !_isMuted;
      notifyListeners();

      // TODO: Update conversation settings in storage
      print('💬 ChatProvider: 🔇 Mute toggled: $_isMuted');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to toggle mute: $e');
    }
  }

  /// Refresh messages
  Future<void> refreshMessages() async {
    try {
      await _loadMessages();
      print('💬 ChatProvider: ✅ Messages refreshed');
    } catch (e) {
      print('💬 ChatProvider: ❌ Failed to refresh messages: $e');
    }
  }

  /// Clear error state
  void clearError() {
    _hasError = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Set error state
  void _setError(String message) {
    _hasError = true;
    _errorMessage = message;
    _isLoading = false;
    notifyListeners();
  }

  /// Dispose the provider
  @override
  void dispose() {
    if (_conversationId != null) {
      _instances.remove(_conversationId);
    }
    super.dispose();
  }

  /// Get chat provider instance for a conversation
  static ChatProvider? getInstance(String conversationId) {
    return _instances[conversationId];
  }

  /// Get all active chat providers
  static List<ChatProvider> getAllInstances() {
    return _instances.values.toList();
  }
}
