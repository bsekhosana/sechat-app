import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../core/services/se_session_service.dart';
import '../../../core/services/simple_notification_service.dart';

import '../services/message_storage_service.dart';
import '../services/message_status_tracking_service.dart';
import '../models/message.dart';
import '../models/chat_conversation.dart';

/// Provider for managing chat list state and operations
class ChatListProvider extends ChangeNotifier {
  final MessageStorageService _storageService = MessageStorageService.instance;
  final MessageStatusTrackingService _statusTrackingService =
      MessageStatusTrackingService.instance;

  // State
  List<ChatConversation> _conversations = [];
  List<ChatConversation> _filteredConversations = [];
  String _searchQuery = '';
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;

  // Getters
  List<ChatConversation> get conversations => _conversations;
  List<ChatConversation> get filteredConversations => _filteredConversations;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;
  int get totalUnreadCount =>
      _conversations.fold(0, (sum, conv) => sum + conv.unreadCount);

  /// Initialize the chat list provider
  Future<void> initialize() async {
    try {
      print('📱 ChatListProvider: 🚀 Starting initialization...');
      _setLoading(true);

      // Load conversations with timeout protection
      try {
        await _loadConversations();
      } catch (e) {
        print('📱 ChatListProvider: ❌ _loadConversations failed: $e');
        // Ensure we have a result even if loading fails
        _conversations = [];
        _applySearchFilter();
      }

      print(
          '📱 ChatListProvider: ✅ Conversations loaded, setting up services...');
      _setupStatusTracking();
      _setupConversationCreationListener();
      print('📱 ChatListProvider: ✅ Initialization complete');
      _setLoading(false);
    } catch (e) {
      print('📱 ChatListProvider: ❌ Initialization failed: $e');
      if (e is TimeoutException) {
        _setError('Loading conversations timed out. Please try again.');
      } else {
        _setError('Failed to initialize chat list: $e');
      }
    } finally {
      // Ensure loading is always set to false, even if there's an error
      print(
          '📱 ChatListProvider: 🔄 Setting loading to false in finally block');
      _setLoading(false);
    }
  }

  /// Load conversations from storage
  Future<void> _loadConversations() async {
    try {
      final currentUserId = _getCurrentUserId();
      if (currentUserId == 'unknown_user') {
        print('📱 ChatListProvider: ❌ No current user session found');
        _conversations = [];
        _applySearchFilter();
        return;
      }

      // Ensure MessageStorageService database is initialized
      bool databaseReady = false;
      int retryCount = 0;
      const maxRetries = 5;

      while (!databaseReady && retryCount < maxRetries) {
        try {
          // Try to load conversations from the database
          final conversations =
              await _storageService.getUserConversations(currentUserId);

          // Sort conversations by last message time (newest first)
          conversations.sort((a, b) {
            final aTime = a.lastMessageAt ?? a.createdAt;
            final bTime = b.lastMessageAt ?? b.createdAt;
            return bTime.compareTo(aTime);
          });

          _conversations = conversations;
          _applySearchFilter();
          databaseReady = true;

          print(
              '📱 ChatListProvider: ✅ Loaded ${conversations.length} conversations from database');

          // If we have conversations but they're all empty, there might be a parsing issue
          if (conversations.isNotEmpty &&
              conversations.every((c) => c.id.isEmpty)) {
            print(
                '📱 ChatListProvider: ⚠️ All conversations have empty IDs, possible parsing issue');
            _setError(
                'Conversation data corrupted. Please try recreating the database.');
          }
        } catch (e) {
          retryCount++;
          if (e.toString().contains('Database not initialized')) {
            print(
                '📱 ChatListProvider: ⏳ MessageStorageService database not ready, retry $retryCount/$maxRetries...');
            if (retryCount < maxRetries) {
              // Wait a bit for the database to be ready
              await Future.delayed(const Duration(milliseconds: 500));
            } else {
              print(
                  '📱 ChatListProvider: ❌ Database still not ready after $maxRetries retries');
              _conversations = [];
              _applySearchFilter();
              databaseReady =
                  true; // Mark as ready even with empty conversations
            }
          } else {
            print('📱 ChatListProvider: ❌ Failed to load conversations: $e');
            _conversations = [];
            _applySearchFilter();
            databaseReady = true; // Mark as ready even with empty conversations
            break;
          }
        }
      }

      // Ensure we always have a result, even if it's empty
      if (!databaseReady) {
        print(
            '📱 ChatListProvider: ⚠️ Database not ready, using empty conversations');
        _conversations = [];
        _applySearchFilter();
      }
    } catch (e) {
      print('📱 ChatListProvider: ❌ Failed to load conversations: $e');
      // Don't rethrow, just log the error and continue with empty conversations
      _conversations = [];
      _applySearchFilter();
    }
  }

  /// Setup status tracking for real-time updates
  void _setupStatusTracking() {
    // Listen for typing indicator updates
    _statusTrackingService.typingIndicatorStream?.listen((update) {
      _updateTypingIndicator(update);
    });

    // Listen for last seen updates
    _statusTrackingService.lastSeenStream?.listen((update) {
      _updateLastSeen(update);
    });

    // Listen for message status updates
    _statusTrackingService.statusUpdateStream?.listen((update) {
      _updateMessageStatus(update);
    });
  }

  /// Setup conversation creation listener
  void _setupConversationCreationListener() {
    try {
      final notificationService = SimpleNotificationService.instance;
      notificationService.setOnConversationCreated((conversation) {
        print(
            '📱 ChatListProvider: 🆕 New conversation created: ${conversation.id}');
        addConversation(conversation);
      });
      print('📱 ChatListProvider: ✅ Conversation creation listener set up');
    } catch (e) {
      print(
          '📱 ChatListProvider: ❌ Failed to set up conversation creation listener: $e');
    }
  }

  /// Update typing indicator for a conversation
  void _updateTypingIndicator(TypingIndicatorUpdate update) {
    final index =
        _conversations.indexWhere((conv) => conv.id == update.conversationId);
    if (index != -1) {
      final conversation = _conversations[index];
      final updatedConversation = conversation.copyWith(
        isTyping: update.isTyping,
        typingStartedAt: update.isTyping ? update.timestamp : null,
      );

      _conversations[index] = updatedConversation;
      _applySearchFilter();
      notifyListeners();
    }
  }

  /// Update last seen for a conversation
  void _updateLastSeen(LastSeenUpdate update) {
    final index = _conversations.indexWhere((conv) =>
        conv.participant1Id == update.userId ||
        conv.participant2Id == update.userId);
    if (index != -1) {
      final conversation = _conversations[index];
      final updatedConversation = conversation.copyWith(
        lastSeen: update.timestamp,
      );

      _conversations[index] = updatedConversation;
      _applySearchFilter();
      notifyListeners();
    }
  }

  /// Update message status for a conversation
  void _updateMessageStatus(MessageStatusUpdate update) {
    // Find conversation by message ID (this will need to be implemented when we have message-conversation mapping)
    // For now, we'll skip this update
    print(
        '📱 ChatListProvider: Message status update received for message: ${update.messageId}');
  }

  /// Search conversations
  void searchConversations(String query) {
    _searchQuery = query.trim().toLowerCase();
    _applySearchFilter();
    notifyListeners();
  }

  /// Clear search
  void clearSearch() {
    _searchQuery = '';
    _applySearchFilter();
    notifyListeners();
  }

  /// Apply search filter to conversations
  void _applySearchFilter() {
    if (_searchQuery.isEmpty) {
      _filteredConversations = List.from(_conversations);
    } else {
      _filteredConversations = _conversations.where((conversation) {
        final displayName = conversation.getDisplayName(_getCurrentUserId());
        return displayName.toLowerCase().contains(_searchQuery) ||
            (conversation.lastMessagePreview
                    ?.toLowerCase()
                    .contains(_searchQuery) ??
                false);
      }).toList();
    }
  }

  /// Refresh conversations
  Future<void> refreshConversations() async {
    try {
      print('📱 ChatListProvider: 🔄 Refreshing conversations...');
      await _loadConversations();
      notifyListeners();
      print('📱 ChatListProvider: ✅ Conversations refreshed');
    } catch (e) {
      print('📱 ChatListProvider: ❌ Failed to refresh conversations: $e');
      _setError('Failed to refresh conversations: $e');
    }
  }

  /// Force refresh UI state
  void forceRefresh() {
    print('📱 ChatListProvider: 🔄 Forcing UI refresh');
    notifyListeners();
  }

  /// Force reset loading state (for debugging)
  void forceResetLoading() {
    print('📱 ChatListProvider: 🔄 Force resetting loading state');
    _isLoading = false;
    _hasError = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Force database recreation (for schema issues)
  Future<void> forceDatabaseRecreation() async {
    try {
      print('📱 ChatListProvider: 🔄 Force recreating database...');
      await _storageService.forceRecreateDatabase();
      await _loadConversations();
      notifyListeners();
      print(
          '📱 ChatListProvider: ✅ Database recreated and conversations reloaded');
    } catch (e) {
      print('📱 ChatListProvider: ❌ Failed to recreate database: $e');
      _setError('Failed to recreate database: $e');
    }
  }

  /// Refresh conversations when screen becomes visible
  Future<void> onScreenVisible() async {
    try {
      print(
          '📱 ChatListProvider: 👁️ Screen became visible, refreshing conversations...');
      // Only refresh if we don't have conversations or if there was an error
      if (_conversations.isEmpty || _hasError) {
        await _loadConversations();
        notifyListeners();
      }
    } catch (e) {
      print('📱 ChatListProvider: ❌ Failed to refresh on screen visible: $e');
    }
  }

  /// Handle database corruption by forcing recreation
  Future<void> handleDatabaseCorruption() async {
    try {
      print('📱 ChatListProvider: 🔧 Handling database corruption...');
      _setError('Database corrupted. Recreating...');
      await forceDatabaseRecreation();
      _clearError();
      print('📱 ChatListProvider: ✅ Database corruption handled successfully');
    } catch (e) {
      print('📱 ChatListProvider: ❌ Failed to handle database corruption: $e');
      _setError('Failed to recover from database corruption: $e');
    }
  }

  /// Clear error state
  void _clearError() {
    _hasError = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Add new conversation
  Future<void> addConversation(ChatConversation conversation) async {
    try {
      // Check if conversation already exists
      final existingIndex =
          _conversations.indexWhere((conv) => conv.id == conversation.id);

      if (existingIndex != -1) {
        // Update existing conversation
        _conversations[existingIndex] = conversation;
      } else {
        // Add new conversation at the top
        _conversations.insert(0, conversation);
      }

      // Sort conversations by last message time
      _conversations.sort((a, b) {
        final aTime = a.lastMessageAt ?? a.createdAt;
        final bTime = b.lastMessageAt ?? b.createdAt;
        return bTime.compareTo(aTime);
      });

      _applySearchFilter();
      notifyListeners();

      print(
          '📱 ChatListProvider: ✅ Conversation ${conversation.id} added/updated');
    } catch (e) {
      print('📱 ChatListProvider: ❌ Failed to add conversation: $e');
      rethrow;
    }
  }

  /// Update conversation with new message
  Future<void> updateConversationWithMessage(Message message) async {
    try {
      final conversation =
          await _storageService.getConversation(message.conversationId);
      if (conversation == null) return;

      // Update conversation with new message info
      final updatedConversation = conversation.updateWithNewMessage(
        messageId: message.id,
        messagePreview: message.previewText,
        messageType: _convertToConversationMessageType(message.type),
        isFromCurrentUser: message.senderId == _getCurrentUserId(),
      );

      // Update in local list
      final index =
          _conversations.indexWhere((conv) => conv.id == conversation.id);
      if (index != -1) {
        _conversations[index] = updatedConversation;
      } else {
        _conversations.insert(0, updatedConversation);
      }

      // Sort conversations by last message time
      _conversations.sort((a, b) {
        final aTime = a.lastMessageAt ?? a.createdAt;
        final bTime = b.lastMessageAt ?? b.createdAt;
        return bTime.compareTo(aTime);
      });

      _applySearchFilter();
      notifyListeners();

      print('📱 ChatListProvider: ✅ Conversation updated with new message');
    } catch (e) {
      print(
          '📱 ChatListProvider: ❌ Failed to update conversation with message: $e');
    }
  }

  /// Mark conversation as read
  Future<void> markConversationAsRead(String conversationId) async {
    try {
      final index =
          _conversations.indexWhere((conv) => conv.id == conversationId);
      if (index != -1) {
        final conversation = _conversations[index];
        final updatedConversation = conversation.markAsRead();

        _conversations[index] = updatedConversation;
        _applySearchFilter();
        notifyListeners();

        // Update in storage
        await _storageService.saveConversation(updatedConversation);

        print('📱 ChatListProvider: ✅ Conversation marked as read');
      }
    } catch (e) {
      print('📱 ChatListProvider: ❌ Failed to mark conversation as read: $e');
    }
  }

  /// Toggle mute notifications for conversation
  Future<void> toggleMuteNotifications(String conversationId) async {
    try {
      final index =
          _conversations.indexWhere((conv) => conv.id == conversationId);
      if (index != -1) {
        final conversation = _conversations[index];
        final updatedConversation = conversation.toggleMute();

        _conversations[index] = updatedConversation;
        _applySearchFilter();
        notifyListeners();

        // Update in storage
        await _storageService.saveConversation(updatedConversation);

        print(
            '📱 ChatListProvider: ✅ Notifications ${updatedConversation.isMuted ? 'muted' : 'unmuted'}');
      }
    } catch (e) {
      print('�� ChatListProvider: ❌ Failed to toggle mute notifications: $e');
    }
  }

  /// Block user
  Future<void> blockUser(String conversationId) async {
    try {
      final index =
          _conversations.indexWhere((conv) => conv.id == conversationId);
      if (index != -1) {
        final conversation = _conversations[index];
        // Note: ChatConversation doesn't have isBlocked property yet
        // This will be implemented when we add blocking functionality
        print('📱 ChatListProvider: Blocking not implemented yet');
      }
    } catch (e) {
      print('📱 ChatListProvider: ❌ Failed to block user: $e');
    }
  }

  /// Delete conversation
  Future<void> deleteConversation(String conversationId) async {
    try {
      // Remove from local list
      _conversations.removeWhere((conv) => conv.id == conversationId);
      _applySearchFilter();
      notifyListeners();

      // Delete from storage
      await _storageService.deleteConversation(conversationId);

      print('📱 ChatListProvider: ✅ Conversation deleted');
    } catch (e) {
      print('📱 ChatListProvider: ❌ Failed to delete conversation: $e');
    }
  }

  /// Convert MessageType to conversation MessageType
  MessageType _convertToConversationMessageType(MessageType type) {
    // Since we're using the same MessageType enum, just return the type directly
    return type;
  }

  /// Get current user ID
  String _getCurrentUserId() {
    // Get current user ID from session service
    final sessionService = SeSessionService();
    return sessionService.currentSessionId ?? 'unknown_user';
  }

  /// Set loading state
  void _setLoading(bool loading) {
    print('📱 ChatListProvider: 🔄 Setting loading to: $loading');
    _isLoading = loading;
    if (loading) {
      _hasError = false;
      _errorMessage = null;
    }
    notifyListeners(); // Ensure UI updates when loading state changes
  }

  /// Set error state
  void _setError(String message) {
    _hasError = true;
    _errorMessage = message;
    _isLoading = false;
    print('📱 ChatListProvider: ❌ Error: $message');
    notifyListeners(); // Ensure UI updates when error occurs
  }

  /// Retry initialization
  Future<void> retry() async {
    clearError();
    await initialize();
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
    print('📱 ChatListProvider: ✅ Provider disposed');
    super.dispose();
  }

  /// Handle incoming message notification
  Future<void> handleIncomingMessage({
    required String senderId,
    required String senderName,
    required String message,
    required String conversationId,
  }) async {
    try {
      print(
          '📱 ChatListProvider: Handling incoming message from $senderName: $message');

      // Create or update conversation
      final currentUserId = _getCurrentUserId();
      if (currentUserId == 'unknown_user') {
        print('📱 ChatListProvider: ❌ No current user session found');
        return;
      }

      // Check if conversation exists
      ChatConversation? existingConversation;
      try {
        existingConversation = _conversations.firstWhere(
          (conv) => conv.isParticipant(senderId),
        );
      } catch (e) {
        existingConversation = null;
      }

      if (existingConversation != null) {
        // Update existing conversation
        final updatedConversation = existingConversation.copyWith(
          lastMessageAt: DateTime.now(),
          lastMessageId: conversationId,
          lastMessagePreview: message,
          lastMessageType: MessageType.text,
          unreadCount: existingConversation.unreadCount + 1,
          updatedAt: DateTime.now(),
        );

        // Update in storage
        await _storageService.saveConversation(updatedConversation);

        // Update local state
        final index =
            _conversations.indexWhere((c) => c.id == existingConversation!.id);
        if (index != -1) {
          _conversations[index] = updatedConversation;
        }

        print('📱 ChatListProvider: ✅ Updated existing conversation');
      } else {
        // Create new conversation
        final newConversation = ChatConversation(
          id: conversationId,
          participant1Id: currentUserId,
          participant2Id: senderId,
          displayName: senderName,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          lastMessageAt: DateTime.now(),
          lastMessageId: conversationId,
          lastMessagePreview: message,
          lastMessageType: MessageType.text,
          unreadCount: 1,
          isArchived: false,
          isMuted: false,
          isPinned: false,
          metadata: null,
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
          recipientId: senderId,
        );

        // Save to storage
        await _storageService.saveConversation(newConversation);

        // Add to local state
        _conversations.add(newConversation);

        print('📱 ChatListProvider: ✅ Created new conversation');
      }

      // Sort conversations by last message time
      _conversations.sort((a, b) {
        final aTime = a.lastMessageAt ?? a.createdAt;
        final bTime = b.lastMessageAt ?? b.createdAt;
        return bTime.compareTo(aTime);
      });

      // Apply search filter
      _applySearchFilter();

      // Notify listeners
      notifyListeners();

      print('📱 ChatListProvider: ✅ Incoming message handled successfully');
    } catch (e) {
      print('📱 ChatListProvider: ❌ Error handling incoming message: $e');
    }
  }
}
