import 'package:flutter/foundation.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/features/chat/services/message_storage_service.dart';
import 'package:sechat_app/features/chat/models/chat_conversation.dart';

/// Optimized Chat List Provider
/// Manages the list of chat conversations with real-time updates
class OptimizedChatListProvider extends ChangeNotifier {
  // Static callback for conversation creation notifications
  static Function()? _onConversationCreatedCallback;

  // Database service
  final _databaseService = MessageStorageService.instance;

  // Session service
  final _sessionService = SeSessionService();

  // State
  List<ChatConversation> _conversations = [];
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';
  bool _isInitialized = false;
  final String _instanceId = DateTime.now().millisecondsSinceEpoch.toString();

  // Getters
  List<ChatConversation> get conversations => _conversations;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  bool get isInitialized => _isInitialized;

  /// Initialize the provider
  Future<void> initialize() async {
    // Prevent re-initialization
    if (_isInitialized) {
      print(
          '📱 OptimizedChatListProvider[$_instanceId]: ℹ️ Already initialized, skipping');
      return;
    }

    try {
      print(
          '📱 OptimizedChatListProvider[$_instanceId]: 🚀 Starting initialization');
      _setLoading(true);
      _clearError();

      await _loadConversations();

      _isInitialized = true;
      print(
          '📱 OptimizedChatListProvider[$_instanceId]: ✅ Initialized successfully');
    } catch (e) {
      _setError('Failed to initialize: $e');
      print(
          '📱 OptimizedChatListProvider[$_instanceId]: ❌ Initialization failed: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Load conversations from database
  Future<void> _loadConversations() async {
    try {
      final currentUserId = _sessionService.currentSessionId;
      if (currentUserId == null) {
        throw Exception('No current user session found');
      }

      final conversationsData =
          await _databaseService.getUserConversations(currentUserId);
      _conversations = conversationsData;

      print(
          '📱 OptimizedChatListProvider[$_instanceId]: ✅ Loaded ${_conversations.length} conversations');
    } catch (e) {
      throw Exception('Failed to load conversations: $e');
    }
  }

  /// Refresh conversations
  Future<void> refresh() async {
    try {
      _setLoading(true);
      _clearError();

      await _loadConversations();
      notifyListeners();

      print('📱 OptimizedChatListProvider: ✅ Conversations refreshed');
    } catch (e) {
      _setError('Failed to refresh: $e');
      print('📱 OptimizedChatListProvider: ❌ Refresh failed: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Set the static callback for conversation creation notifications
  static void setConversationCreatedCallback(Function() callback) {
    _onConversationCreatedCallback = callback;
    print('📱 OptimizedChatListProvider: ✅ Conversation created callback set');
  }

  /// Trigger conversation creation notification (called by notification service)
  static void notifyConversationCreated() {
    if (_onConversationCreatedCallback != null) {
      _onConversationCreatedCallback!();
      print(
          '📱 OptimizedChatListProvider: ✅ Conversation created notification triggered');
    } else {
      print(
          '📱 OptimizedChatListProvider: ⚠️ No conversation created callback set');
    }
  }

  /// Handle incoming message (called by notification service)
  Future<void> handleIncomingMessage({
    required String senderId,
    required String senderName,
    required String message,
    required String conversationId,
    required String messageId,
  }) async {
    try {
      print(
          '📱 OptimizedChatListProvider: 📨 Handling incoming message from $senderName');

      // Find existing conversation
      final conversationIndex =
          _conversations.indexWhere((c) => c.id == conversationId);

      if (conversationIndex != -1) {
        // Update existing conversation
        final existingConversation = _conversations[conversationIndex];
        final updatedConversation = existingConversation.copyWith(
          lastMessageAt: DateTime.now(),
          lastMessagePreview: message,
          unreadCount: existingConversation.unreadCount + 1,
          updatedAt: DateTime.now(),
        );

        _conversations[conversationIndex] = updatedConversation;

        // Move conversation to top
        _moveConversationToTop(conversationIndex);

        print(
            '📱 OptimizedChatListProvider: ✅ Updated existing conversation: $conversationId');
      } else {
        // Create new conversation if it doesn't exist
        await _createConversationForMessage(
            senderId, senderName, message, conversationId);
      }

      notifyListeners();
    } catch (e) {
      print(
          '📱 OptimizedChatListProvider: ❌ Error handling incoming message: $e');
    }
  }

  /// Create conversation for incoming message
  Future<void> _createConversationForMessage(
    String senderId,
    String senderName,
    String message,
    String conversationId,
  ) async {
    try {
      final currentUserId = _sessionService.currentSessionId;
      if (currentUserId == null) {
        throw Exception('No current user session found');
      }

      // Create new conversation
      final newConversation = ChatConversation(
        id: conversationId,
        participant1Id: senderId,
        participant2Id: currentUserId,
        displayName: senderName,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastMessageAt: DateTime.now(),
        lastMessagePreview: message,
        unreadCount: 1,
      );

      // Save to database
      await _databaseService.saveConversation(newConversation);

      // Add to local state
      _conversations.insert(0, newConversation);

      print(
          '📱 OptimizedChatListProvider: ✅ Created new conversation: $conversationId');
    } catch (e) {
      print('📱 OptimizedChatListProvider: ❌ Error creating conversation: $e');
    }
  }

  /// Handle typing indicator update
  void handleTypingIndicator(String senderId, bool isTyping) {
    try {
      print(
          '📱 OptimizedChatListProvider: ⌨️ Handling typing indicator: $senderId -> $isTyping');

      // Find conversation with this sender
      final conversationIndex =
          _conversations.indexWhere((c) => c.isParticipant(senderId));

      if (conversationIndex != -1) {
        final existingConversation = _conversations[conversationIndex];
        final updatedConversation = existingConversation.copyWith(
          isTyping: isTyping,
          typingStartedAt: isTyping ? DateTime.now() : null,
          updatedAt: DateTime.now(),
        );

        _conversations[conversationIndex] = updatedConversation;

        // Move conversation to top if typing started
        if (isTyping) {
          _moveConversationToTop(conversationIndex);
        }

        notifyListeners();
        print(
            '📱 OptimizedChatListProvider: ✅ Updated typing indicator for conversation: ${existingConversation.id}');
      }
    } catch (e) {
      print(
          '📱 OptimizedChatListProvider: ❌ Error handling typing indicator: $e');
    }
  }

  /// Handle online status update
  void handleOnlineStatusUpdate(
      String senderId, bool isOnline, String? lastSeen) {
    try {
      print(
          '📱 OptimizedChatListProvider: 🌐 Handling online status: $senderId -> $isOnline');

      // Find conversation with this sender
      final conversationIndex =
          _conversations.indexWhere((c) => c.isParticipant(senderId));

      if (conversationIndex != -1) {
        final existingConversation = _conversations[conversationIndex];
        final updatedConversation = existingConversation.copyWith(
          lastSeen: lastSeen != null ? DateTime.parse(lastSeen) : null,
          updatedAt: DateTime.now(),
        );

        _conversations[conversationIndex] = updatedConversation;
        notifyListeners();

        print(
            '📱 OptimizedChatListProvider: ✅ Updated online status for conversation: ${existingConversation.id}');
      }
    } catch (e) {
      print('📱 OptimizedChatListProvider: ❌ Error handling online status: $e');
    }
  }

  /// Handle outgoing message (message sent by current user)
  Future<void> handleOutgoingMessage({
    required String recipientId,
    required String message,
    required String conversationId,
    String? messageId,
  }) async {
    try {
      print(
          '📱 OptimizedChatListProvider: 📤 Handling outgoing message to $recipientId');

      // Find existing conversation
      final conversationIndex =
          _conversations.indexWhere((c) => c.id == conversationId);

      if (conversationIndex != -1) {
        // Update existing conversation
        final existingConversation = _conversations[conversationIndex];
        final updatedConversation = existingConversation.copyWith(
          lastMessageAt: DateTime.now(),
          lastMessagePreview: message,
          unreadCount: 0, // No unread count for outgoing messages
          updatedAt: DateTime.now(),
        );

        _conversations[conversationIndex] = updatedConversation;

        // Move conversation to top
        _moveConversationToTop(conversationIndex);

        print(
            '📱 OptimizedChatListProvider: ✅ Updated existing conversation with outgoing message');
      } else {
        // Create new conversation for outgoing message
        await _createConversationForOutgoingMessage(
            recipientId, message, conversationId);
      }

      notifyListeners();
    } catch (e) {
      print(
          '📱 OptimizedChatListProvider: ❌ Error handling outgoing message: $e');
    }
  }

  /// Create conversation for outgoing message
  Future<void> _createConversationForOutgoingMessage(
    String recipientId,
    String message,
    String conversationId,
  ) async {
    try {
      final currentUserId = _sessionService.currentSessionId;
      if (currentUserId == null) {
        throw Exception('No current user session found');
      }

      // Create new conversation
      final newConversation = ChatConversation(
        id: conversationId,
        participant1Id: currentUserId,
        participant2Id: recipientId,
        displayName: recipientId, // Will be updated when user data is loaded
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastMessageAt: DateTime.now(),
        lastMessagePreview: message,
        unreadCount: 0,
      );

      // Save to database
      await _databaseService.saveConversation(newConversation);

      // Add to local state
      _conversations.insert(0, newConversation);

      print(
          '📱 OptimizedChatListProvider: ✅ Created new conversation for outgoing message: $conversationId');
    } catch (e) {
      print(
          '📱 OptimizedChatListProvider: ❌ Error creating conversation for outgoing message: $e');
    }
  }

  /// Mark conversation as read
  Future<void> markConversationAsRead(String conversationId) async {
    try {
      final conversationIndex =
          _conversations.indexWhere((c) => c.id == conversationId);

      if (conversationIndex != -1) {
        final existingConversation = _conversations[conversationIndex];
        final updatedConversation = existingConversation.copyWith(
          unreadCount: 0,
          updatedAt: DateTime.now(),
        );

        _conversations[conversationIndex] = updatedConversation;

        // Update database by saving the updated conversation
        await _databaseService.saveConversation(updatedConversation);

        notifyListeners();
        print(
            '📱 OptimizedChatListProvider: ✅ Marked conversation as read: $conversationId');
      }
    } catch (e) {
      print(
          '📱 OptimizedChatListProvider: ❌ Error marking conversation as read: $e');
    }
  }

  /// Search conversations
  void searchConversations(String query) {
    _searchQuery = query.toLowerCase();
    _applySearchFilter();
    notifyListeners();
  }

  /// Apply search filter
  void _applySearchFilter() {
    if (_searchQuery.isEmpty) {
      // No search query, show all conversations
      return;
    }

    // Filter conversations based on search query
    _conversations = _conversations.where((conversation) {
      return (conversation.displayName?.toLowerCase().contains(_searchQuery) ??
              false) ||
          (conversation.lastMessagePreview
                  ?.toLowerCase()
                  .contains(_searchQuery) ??
              false);
    }).toList();
  }

  /// Clear search
  void clearSearch() {
    _searchQuery = '';
    _applySearchFilter();
    notifyListeners();
  }

  /// Move conversation to top of list
  void _moveConversationToTop(int index) {
    if (index > 0) {
      final conversation = _conversations.removeAt(index);
      _conversations.insert(0, conversation);
    }
  }

  /// Get conversation by ID
  ChatConversation? getConversation(String conversationId) {
    try {
      return _conversations.firstWhere((c) => c.id == conversationId);
    } catch (e) {
      return null;
    }
  }

  /// Get conversation with specific user
  ChatConversation? getConversationWithUser(String userId) {
    try {
      return _conversations.firstWhere((c) => c.isParticipant(userId));
    } catch (e) {
      return null;
    }
  }

  /// Delete conversation
  Future<void> deleteConversation(String conversationId) async {
    try {
      final conversationIndex =
          _conversations.indexWhere((c) => c.id == conversationId);

      if (conversationIndex != -1) {
        _conversations.removeAt(conversationIndex);

        // Delete from database (this will cascade delete messages)
        // Note: We'll need to implement this in the database service

        notifyListeners();
        print(
            '📱 OptimizedChatListProvider: ✅ Deleted conversation: $conversationId');
      }
    } catch (e) {
      print('📱 OptimizedChatListProvider: ❌ Error deleting conversation: $e');
    }
  }

  /// Clear all data (for testing/reset)
  Future<void> clearAllData() async {
    try {
      // Clear local state
      _conversations.clear();
      _clearError();
      _isInitialized = false;
      notifyListeners();

      print(
          '📱 OptimizedChatListProvider: ✅ All data cleared (local state only)');
      print(
          '📱 OptimizedChatListProvider: ℹ️ Note: Database data not cleared - use MessageStorageService.forceRecreateDatabase() if needed');
    } catch (e) {
      _setError('Failed to clear data: $e');
      print('📱 OptimizedChatListProvider: ❌ Error clearing data: $e');
    }
  }

  // ===== PRIVATE HELPER METHODS =====

  /// Set loading state
  void _setLoading(bool loading) {
    print(
        '📱 OptimizedChatListProvider[$_instanceId]: 🔄 Loading state changed: $_isLoading -> $loading');
    _isLoading = loading;
    notifyListeners();
  }

  /// Set error state
  void _setError(String error) {
    _error = error;
  }

  /// Clear error state
  void _clearError() {
    _error = null;
  }

  @override
  void dispose() {
    print('📱 OptimizedChatListProvider[$_instanceId]: 🗑️ Disposed');
    super.dispose();
  }
}
