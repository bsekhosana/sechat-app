import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../core/services/se_session_service.dart';
import '../../../core/services/se_socket_service.dart';
import '../../../realtime/realtime_service_manager.dart';
import '../../../realtime/presence_service.dart';

import '../services/message_storage_service.dart';
import '../services/message_status_tracking_service.dart';
import '../models/message.dart';
import '../models/chat_conversation.dart';
import 'package:sechat_app/core/utils/conversation_id_generator.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';

/// Provider for managing chat list state and operations
class ChatListProvider extends ChangeNotifier {
  final MessageStorageService _storageService = MessageStorageService.instance;
  final MessageStatusTrackingService _statusTrackingService =
      MessageStatusTrackingService.instance;
  final SeSocketService _socketService = SeSocketService.instance;

  // Realtime services
  PresenceService? _presenceService;

  // Callback for online status updates to notify other providers
  Function(String, bool, DateTime?)? _onOnlineStatusChanged;

  // State
  List<ChatConversation> _conversations = [];
  List<ChatConversation> _filteredConversations = [];
  String _searchQuery = '';
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _isInitialized = false;

  /// Set callback for online status changes
  void setOnOnlineStatusChanged(Function(String, bool, DateTime?) callback) {
    _onOnlineStatusChanged = callback;
  }

  /// Process message status update from external source
  void processMessageStatusUpdate(MessageStatusUpdate update) {
    _updateMessageStatus(update);
  }

  /// Process message status update with additional context for better conversation lookup
  void processMessageStatusUpdateWithContext(
    MessageStatusUpdate update, {
    String? conversationId,
    String? recipientId,
  }) {
    _updateMessageStatusWithContext(update,
        conversationId: conversationId, recipientId: recipientId);
  }

  /// Update conversation online status from external source
  void updateConversationOnlineStatus(
      String userId, bool isOnline, String? lastSeen) {
    try {
      print(
          '📱 ChatListProvider: 🔍 Updating online status for user: $userId -> ${isOnline ? 'online' : 'offline'}');
      print(
          '📱 ChatListProvider: 🔍 Current conversations: ${_conversations.map((c) => '${c.id}:${c.isOnline}').join(', ')}');

      // Find conversation with this user and update online status
      final conversationIndex = _conversations.indexWhere(
        (conv) =>
            conv.participant1Id == userId || conv.participant2Id == userId,
      );

      if (conversationIndex != -1) {
        final oldConversation = _conversations[conversationIndex];
        final updatedConversation = oldConversation.copyWith(
          isOnline: isOnline,
          lastSeen: lastSeen != null ? DateTime.tryParse(lastSeen) : null,
        );

        _conversations[conversationIndex] = updatedConversation;
        _applySearchFilter();
        notifyListeners();

        print(
            '📱 ChatListProvider: ✅ Online status updated for conversation: ${oldConversation.id} (${oldConversation.displayName}) -> ${oldConversation.isOnline} -> $isOnline');
        print(
            '📱 ChatListProvider: 🔔 notifyListeners() called for presence update');
      } else {
        print(
            '📱 ChatListProvider: ⚠️ No conversation found for user: $userId');
        print(
            '📱 ChatListProvider: 🔍 Available conversations: ${_conversations.map((c) => '${c.id} (${c.displayName})').join(', ')}');
      }
    } catch (e) {
      print('📱 ChatListProvider: ❌ Error updating online status: $e');
    }
  }

  // Getters
  List<ChatConversation> get conversations => _conversations;
  List<ChatConversation> get filteredConversations => _filteredConversations;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;
  int get totalUnreadCount =>
      _conversations.fold(0, (sum, conv) => sum + conv.unreadCount);

  /// Clear all data and reset provider state (used when account is deleted)
  void clearAllData() {
    try {
      print(
          '📱 ChatListProvider: 🗑️ Clearing all data and resetting state...');

      // Clear all conversations
      _conversations.clear();
      _filteredConversations.clear();

      // Reset search and state
      _searchQuery = '';
      _isLoading = false;
      _hasError = false;
      _errorMessage = null;
      _isInitialized = false;

      // Clear realtime services
      _presenceService = null;
      _onOnlineStatusChanged = null;

      // Notify listeners
      notifyListeners();

      print('📱 ChatListProvider: ✅ All data cleared and state reset');
    } catch (e) {
      print('📱 ChatListProvider: ❌ Error clearing data: $e');
    }
  }

  /// Initialize the provider
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('📱 ChatListProvider: Initializing...');

      // Initialize the channel-based socket service
      await _socketService.initialize();

      // Load existing conversations
      await _loadConversations();

      // Set up socket callbacks
      _setupSocketCallbacks();

      _isInitialized = true;
      print('📱 ChatListProvider: ✅ Initialized successfully');
    } catch (e) {
      print('📱 ChatListProvider: ❌ Failed to initialize: $e');
      rethrow;
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
          final conversations = await _storageService.getMyLocalConversations();

          // Sort conversations by last message time (newest first)
          conversations.sort((a, b) {
            final aTime = a.lastMessageAt ?? a.createdAt;
            final bTime = b.lastMessageAt ?? b.createdAt;
            return bTime.compareTo(aTime);
          });

          _conversations = conversations;

          // Load last messages for all conversations to populate previews
          await _loadLastMessagesForAllConversations();

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

  /// Load last messages for all conversations to populate previews
  Future<void> _loadLastMessagesForAllConversations() async {
    try {
      print(
          '📱 ChatListProvider: 🔄 Loading last messages for all conversations...');

      for (int i = 0; i < _conversations.length; i++) {
        final conversation = _conversations[i];

        // Only load if we don't already have last message data
        if (conversation.lastMessagePreview == null ||
            conversation.lastMessageId == null) {
          final latestMessage = await getLatestMessage(conversation.id);
          if (latestMessage != null) {
            final updatedConversation = conversation.copyWith(
              lastMessageAt: latestMessage.timestamp,
              lastMessageId: latestMessage.id,
              lastMessagePreview: _getMessagePreview(latestMessage),
              lastMessageType: latestMessage.type,
              updatedAt: DateTime.now(),
            );

            _conversations[i] = updatedConversation;

            // Save the updated conversation to storage
            await _storageService.saveConversation(updatedConversation);
          }
        }
      }

      // Re-sort conversations after loading last messages
      _conversations.sort((a, b) {
        final aTime = a.lastMessageAt ?? a.createdAt;
        final bTime = b.lastMessageAt ?? b.createdAt;
        return bTime.compareTo(aTime);
      });

      print(
          '📱 ChatListProvider: ✅ Last messages loaded for all conversations');
    } catch (e) {
      print('📱 ChatListProvider: ❌ Error loading last messages: $e');
    }
  }

  /// Setup status tracking for real-time updates
  void _setupStatusTracking() {
    // Listen for typing indicator updates
    _statusTrackingService.typingIndicatorStream.listen((update) {
      _updateTypingIndicator(update);
    });

    // Listen for last seen updates
    _statusTrackingService.lastSeenStream.listen((update) {
      _updateLastSeen(update);
    });

    // Listen for message status updates
    _statusTrackingService.statusUpdateStream.listen((update) {
      _updateMessageStatus(update);
    });

    // Listen for typing indicators from socket service
    try {
      final socketService = SeSocketService.instance;
      socketService.setOnTypingIndicator((senderId, isTyping) {
        _handleTypingIndicatorFromSocket(senderId, isTyping);
      });
      print(
          '🔌 ChatListProvider: ✅ Socket service typing indicator callback set');
    } catch (e) {
      print(
          '🔌 ChatListProvider: ❌ Failed to set up socket service typing indicator callback: $e');
    }

    // Listen for online status updates from socket service
    try {
      final socketService = SeSocketService.instance;
      // Note: Online status updates are handled through lastSeen updates
      print('🔌 ChatListProvider: ✅ Status tracking services set up');
    } catch (e) {
      print('🔌 ChatListProvider: ❌ Failed to set up status tracking: $e');
    }
  }

  /// Update online status for a conversation
  Future<void> _updateOnlineStatus(
      String conversationId, bool isOnline, DateTime? lastSeen) async {
    try {
      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index != -1) {
        final conversation = _conversations[index];
        final updatedConversation = conversation.copyWith(
          lastSeen: lastSeen,
          updatedAt: DateTime.now(),
        );

        _conversations[index] = updatedConversation;
        await _storageService.saveConversation(updatedConversation);

        print(
            '📱 ChatListProvider: ✅ Online status updated for conversation: $conversationId');
        notifyListeners();
      }
    } catch (e) {
      print('📱 ChatListProvider: ❌ Error updating online status: $e');
    }
  }

  /// Handle user data exchange to update conversation display names
  void handleUserDataExchange(String senderId, String displayName) {
    try {
      // Find conversation by participant ID
      final index = _conversations.indexWhere((conv) =>
          conv.participant1Id == senderId || conv.participant2Id == senderId);

      if (index != -1) {
        final conversation = _conversations[index];
        final updatedConversation = conversation.copyWith(
          displayName: displayName,
          updatedAt: DateTime.now(),
        );

        _conversations[index] = updatedConversation;

        // Update in storage
        _storageService.saveConversation(updatedConversation);

        _applySearchFilter();
        notifyListeners();

        print(
            '🔌 ChatListProvider: ✅ Updated conversation display name: $senderId -> $displayName');
      } else {
        print(
            '🔌 ChatListProvider: ⚠️ No conversation found for user data exchange: $senderId');
      }
    } catch (e) {
      print('🔌 ChatListProvider: ❌ Error handling user data exchange: $e');
    }
  }

  /// Update conversation display name when user data becomes available
  void updateConversationDisplayName(
      String conversationId, String displayName) {
    try {
      final index =
          _conversations.indexWhere((conv) => conv.id == conversationId);
      if (index != -1) {
        final conversation = _conversations[index];
        final updatedConversation = conversation.copyWith(
          displayName: displayName,
          updatedAt: DateTime.now(),
        );

        _conversations[index] = updatedConversation;
        _applySearchFilter();
        notifyListeners();

        print(
            '🔌 ChatListProvider: ✅ Updated display name for conversation: $conversationId -> $displayName');
      } else {
        print(
            '🔌 ChatListProvider: ⚠️ No conversation found to update display name: $conversationId');
      }
    } catch (e) {
      print(
          '🔌 ChatListProvider: ❌ Error updating conversation display name: $e');
    }
  }

  /// Setup conversation creation listener
  void _setupConversationCreationListener() {
    try {
      final socketService = SeSocketService.instance;
      socketService.setOnConversationCreated((conversationData) async {
        print(
            '🔌 ChatListProvider: 🆕 New conversation created: ${conversationData['conversation_id_local'] ?? 'unknown'}');

        // Create a ChatConversation from the socket data
        try {
          final currentUserId = SeSessionService().currentSessionId;
          if (currentUserId != null) {
            // CRITICAL: Use consistent conversation ID for both users
            final senderId = conversationData['senderId'] ?? '';
            final conversationId =
                _generateConsistentConversationId(currentUserId, senderId);

            // Create a basic conversation - the display name will be updated when user data is available
            final conversation = ChatConversation(
              id: conversationId,
              participant1Id: currentUserId,
              participant2Id: senderId,
              displayName:
                  'User ${senderId.substring(0, 8)}...', // Temporary readable name
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              lastMessageAt: null,
              lastMessageId: null,
              lastMessagePreview: null,
              lastMessageType: null,
              unreadCount: 0,
              isArchived: false,
              isMuted: false,
              isPinned: false,
              metadata: null,
              lastSeen: null,
              isOnline: false,
              isTyping: false,
              typingStartedAt: null,
              notificationsEnabled: true,
              soundEnabled: true,
              vibrationEnabled: true,
              readReceiptsEnabled: true,
              typingIndicatorsEnabled: true,
              lastSeenEnabled: true,
            );

            // CRITICAL: Save conversation to database so it persists after refresh
            try {
              await MessageStorageService.instance
                  .saveConversation(conversation);
              print(
                  '🔌 ChatListProvider: ✅ Conversation saved to database: $conversationId');
            } catch (e) {
              print(
                  '🔌 ChatListProvider: ❌ Failed to save conversation to database: $e');
            }

            _addNewConversation(conversation);
            print(
                '🔌 ChatListProvider: ✅ Conversation created and added: ${conversation.id}');
          }
        } catch (e) {
          print(
              '🔌 ChatListProvider: ❌ Error creating conversation from socket data: $e');
        }

        print('🔌 ChatListProvider: Conversation data: $conversationData');
      });
      print('🔌 ChatListProvider: ✅ Conversation creation listener set up');
    } catch (e) {
      print(
          '🔌 ChatListProvider: ❌ Failed to set up conversation creation listener: $e');
    }
  }

  /// Setup realtime services for presence and typing
  void _setupRealtimeServices() {
    try {
      // Check if already initialized
      if (_presenceService != null) {
        print('📱 ChatListProvider: ℹ️ Presence service already initialized');
        return;
      }

      // Initialize presence service
      _presenceService = RealtimeServiceManager().presence;

      // Note: Presence updates are handled through the existing socket service
      // The realtime presence service will be used for local presence management
      // and peer presence updates will come through the socket service callbacks

      print('📱 ChatListProvider: ✅ Realtime services set up successfully');
    } catch (e) {
      print('📱 ChatListProvider: ❌ Failed to set up realtime services: $e');
    }
  }

  /// Handle typing indicator from socket service
  void _handleTypingIndicatorFromSocket(String senderId, bool isTyping) {
    try {
      print(
          '📱 ChatListProvider: 🔔 Typing indicator from socket: $senderId -> $isTyping');

      // Find conversation with this sender and update typing status
      final conversationIndex = _conversations.indexWhere(
        (conv) =>
            conv.participant1Id == senderId || conv.participant2Id == senderId,
      );

      if (conversationIndex != -1) {
        final conversation = _conversations[conversationIndex];
        final updatedConversation = conversation.copyWith(
          isTyping: isTyping,
          typingStartedAt: isTyping ? DateTime.now() : null,
        );

        _conversations[conversationIndex] = updatedConversation;
        _applySearchFilter();
        notifyListeners();

        print(
            '📱 ChatListProvider: ✅ Updated typing indicator for conversation: ${conversation.id}');
      } else {
        print(
            '📱 ChatListProvider: ⚠️ No conversation found for typing indicator from: $senderId');
      }
    } catch (e) {
      print(
          '📱 ChatListProvider: ❌ Error handling typing indicator from socket: $e');
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

  /// Update typing indicator by participant ID (for socket events)
  void updateTypingIndicatorByParticipant(String participantId, bool isTyping) {
    try {
      print(
          '📱 ChatListProvider: 🔔 Updating typing indicator for participant: $participantId -> $isTyping');

      // CRITICAL: Prevent sender from processing their own typing indicator
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId != null && participantId == currentUserId) {
        print(
            '📱 ChatListProvider: ⚠️ Ignoring own typing indicator from: $participantId');
        return; // Don't process own typing indicator
      }

      // Find conversation by participant ID
      final index = _conversations.indexWhere((conv) =>
          conv.participant1Id == participantId ||
          conv.participant2Id == participantId);

      if (index != -1) {
        final conversation = _conversations[index];
        final updatedConversation = conversation.copyWith(
          isTyping: isTyping,
          typingStartedAt: isTyping ? DateTime.now() : null,
        );

        _conversations[index] = updatedConversation;
        _applySearchFilter();
        notifyListeners();

        // Auto-clear typing indicator after 7 seconds (as per server behavior)
        if (isTyping) {
          Timer(const Duration(seconds: 7), () {
            // Only clear if it's still the same typing state
            if (_conversations[index].isTyping == true) {
              final conversation = _conversations[index];
              final clearedConversation = conversation.copyWith(
                isTyping: false,
                typingStartedAt: null,
              );
              _conversations[index] = clearedConversation;
              _applySearchFilter();
              notifyListeners();
              print(
                  '📱 ChatListProvider: ✅ Auto-cleared typing indicator for conversation: ${conversation.id}');
            }
          });
        }

        print(
            '📱 ChatListProvider: ✅ Updated typing indicator for conversation: ${conversation.id}');
      } else {
        print(
            '📱 ChatListProvider: ⚠️ No conversation found for typing indicator from: $participantId');
      }
    } catch (e) {
      print(
          '📱 ChatListProvider: ❌ Error updating typing indicator by participant: $e');
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

      print(
          '📱 ChatListProvider: ✅ Last seen updated for conversation: ${conversation.id}');
    }
  }

  /// Add a new conversation to the list
  void _addNewConversation(ChatConversation conversation) {
    try {
      // Check if conversation already exists
      if (!_conversations.any((conv) => conv.id == conversation.id)) {
        _conversations.add(conversation);

        // Note: Conversation is already saved to database in the callback
        // No need to save again here to avoid duplicate operations

        _applySearchFilter();
        notifyListeners();
        print(
            '📱 ChatListProvider: ✅ New conversation added to list: ${conversation.id}');
      } else {
        print(
            '📱 ChatListProvider: ℹ️ Conversation already exists: ${conversation.id}');
      }
    } catch (e) {
      print('📱 ChatListProvider: ❌ Error adding new conversation: $e');
    }
  }

  /// Update message status for a conversation - FIXED conversation lookup
  void _updateMessageStatus(MessageStatusUpdate update) {
    try {
      print(
          '📱 ChatListProvider: Message status update received for message: ${update.messageId}');

      // CRITICAL FIX: Find conversation by multiple methods
      ChatConversation? conversation;

      // Method 1: Try to find by lastMessageId (original method)
      try {
        conversation = _conversations.firstWhere(
          (conv) => conv.lastMessageId == update.messageId,
        );
        print(
            '📱 ChatListProvider: ✅ Found conversation by lastMessageId: ${conversation.id}');
      } catch (e) {
        conversation = null;
        print('📱 ChatListProvider: ⚠️ No conversation found by lastMessageId');
      }

      // Method 2: If not found by lastMessageId, try to find by sender ID
      if (conversation == null && update.senderId != null) {
        try {
          conversation = _conversations.firstWhere(
            (conv) =>
                conv.participant1Id == update.senderId ||
                conv.participant2Id == update.senderId ||
                conv.id ==
                    update.senderId, // Conversation ID might be participant ID
          );
          print(
              '📱 ChatListProvider: ✅ Found conversation by senderId: ${conversation.id}');
        } catch (e) {
          print(
              '📱 ChatListProvider: ⚠️ No conversation found by senderId: ${update.senderId}');
        }
      }

      if (conversation != null) {
        // Update the conversation's last message status
        final updatedConversation = conversation.copyWith(
          updatedAt: DateTime.now(),
          metadata: {
            ...?conversation.metadata,
            'last_message_status': update.status.toString().split('.').last,
            'last_message_status_updated': update.timestamp.toIso8601String(),
          },
        );

        // Update in storage
        _storageService.saveConversation(updatedConversation);

        // Update local state
        final index =
            _conversations.indexWhere((c) => c.id == conversation!.id);
        if (index != -1) {
          _conversations[index] = updatedConversation;
        }

        // Apply search filter and notify listeners
        _applySearchFilter();
        notifyListeners();

        print(
            '📱 ChatListProvider: ✅ Message status updated for conversation: ${conversation.id}');
      } else {
        print(
            '📱 ChatListProvider: ⚠️ No conversation found for message: ${update.messageId}');
        print(
            '📱 ChatListProvider: 🔍 Available conversations: ${_conversations.map((c) => '${c.id} (lastMsg: ${c.lastMessageId})').join(', ')}');
        print(
            '📱 ChatListProvider: 🔍 Update details: senderId=${update.senderId}');
      }
    } catch (e) {
      print('📱 ChatListProvider: ❌ Error updating message status: $e');
    }
  }

  /// Update message status with additional context for better conversation lookup
  void _updateMessageStatusWithContext(
    MessageStatusUpdate update, {
    String? conversationId,
    String? recipientId,
  }) {
    try {
      print(
          '📱 ChatListProvider: Message status update with context for message: ${update.messageId}');
      print(
          '📱 ChatListProvider: 🔍 Context: conversationId=$conversationId, recipientId=$recipientId');

      // ENHANCED LOOKUP: Use the additional context for better conversation finding
      ChatConversation? conversation;

      // Method 1: Try to find by conversationId from context (sender's ID per updated API docs)
      if (conversation == null && conversationId != null) {
        try {
          // CRITICAL: conversationId is now the consistent conversation ID for both users
          // We need to find the conversation where this sender is a participant
          conversation = _conversations.firstWhere(
            (conv) =>
                conv.participant1Id == conversationId ||
                conv.participant2Id == conversationId,
          );
          print(
              '📱 ChatListProvider: ✅ Found conversation by context conversationId (sender): ${conversation.id}');
        } catch (e) {
          print(
              '📱 ChatListProvider: ⚠️ No conversation found by context conversationId (sender): $conversationId');
        }
      }

      // Method 2: Try to find by recipientId from context
      if (conversation == null && recipientId != null) {
        try {
          conversation = _conversations.firstWhere(
            (conv) =>
                conv.participant1Id == recipientId ||
                conv.participant2Id == recipientId ||
                conv.id ==
                    recipientId, // Conversation ID might be participant ID
          );
          print(
              '📱 ChatListProvider: ✅ Found conversation by context recipientId: ${conversation.id}');
        } catch (e) {
          print(
              '📱 ChatListProvider: ⚠️ No conversation found by context recipientId: $recipientId');
        }
      }

      // Method 3: Fall back to lastMessageId (original method)
      if (conversation == null) {
        try {
          conversation = _conversations.firstWhere(
            (conv) => conv.lastMessageId == update.messageId,
          );
          print(
              '📱 ChatListProvider: ✅ Found conversation by lastMessageId: ${conversation.id}');
        } catch (e) {
          print(
              '📱 ChatListProvider: ⚠️ No conversation found by lastMessageId');
        }
      }

      // Method 4: Try to find by senderId from update
      if (conversation == null && update.senderId != null) {
        try {
          conversation = _conversations.firstWhere(
            (conv) =>
                conv.participant1Id == update.senderId ||
                conv.participant2Id == update.senderId ||
                conv.id ==
                    update.senderId, // Conversation ID might be participant ID
          );
          print(
              '📱 ChatListProvider: ✅ Found conversation by update senderId: ${conversation.id}');
        } catch (e) {
          print(
              '📱 ChatListProvider: ⚠️ No conversation found by update senderId: ${update.senderId}');
        }
      }

      if (conversation != null) {
        // Update the conversation's last message status
        final updatedConversation = conversation.copyWith(
          updatedAt: DateTime.now(),
          metadata: {
            ...?conversation.metadata,
            'last_message_status': update.status.toString().split('.').last,
            'last_message_status_updated': update.timestamp.toIso8601String(),
          },
        );

        // Update in storage
        _storageService.saveConversation(updatedConversation);

        // Update local state
        final index =
            _conversations.indexWhere((c) => c.id == conversation!.id);
        if (index != -1) {
          _conversations[index] = updatedConversation;
        }

        // Apply search filter and notify listeners
        _applySearchFilter();
        notifyListeners();

        print(
            '📱 ChatListProvider: ✅ Message status updated with context for conversation: ${conversation.id}');
      } else {
        print(
            '📱 ChatListProvider: ⚠️ No conversation found for message with context: ${update.messageId}');
        print(
            '📱 ChatListProvider: 🔍 Available conversations: ${_conversations.map((c) => '${c.id} (lastMsg: ${c.lastMessageId})').join(', ')}');
        print(
            '📱 ChatListProvider: 🔍 Context details: conversationId=$conversationId, recipientId=$recipientId, senderId=${update.senderId}');
      }
    } catch (e) {
      print(
          '📱 ChatListProvider: ❌ Error updating message status with context: $e');
    }
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

  /// Get the latest message for a conversation to show tick status
  Future<Message?> getLatestMessage(String conversationId) async {
    try {
      final messages = await _storageService.getMessages(
        conversationId,
        limit: 1,
      );

      if (messages.isNotEmpty) {
        return messages.first;
      }
      return null;
    } catch (e) {
      print('📱 ChatListProvider: ❌ Error getting latest message: $e');
      return null;
    }
  }

  /// Update conversation with latest message and status
  Future<void> updateConversationWithLatestMessage(
      String conversationId) async {
    try {
      final latestMessage = await getLatestMessage(conversationId);
      if (latestMessage != null) {
        final index = _conversations.indexWhere((c) => c.id == conversationId);
        if (index != -1) {
          final conversation = _conversations[index];
          final updatedConversation = conversation.copyWith(
            lastMessageAt: latestMessage.timestamp,
            lastMessageId: latestMessage.id,
            lastMessagePreview: _getMessagePreview(latestMessage),
            lastMessageType: latestMessage.type,
            updatedAt: DateTime.now(),
          );

          _conversations[index] = updatedConversation;
          await _storageService.saveConversation(updatedConversation);

          // Sort conversations by last message time
          _conversations.sort((a, b) {
            final aTime = a.lastMessageAt ?? a.createdAt;
            final bTime = b.lastMessageAt ?? b.createdAt;
            return bTime.compareTo(aTime);
          });

          _applySearchFilter();
          notifyListeners();

          print(
              '📱 ChatListProvider: ✅ Conversation updated with latest message: $conversationId');
        }
      }
    } catch (e) {
      print(
          '📱 ChatListProvider: ❌ Error updating conversation with latest message: $e');
    }
  }

  /// Get message preview text with smart decryption
  String _getMessagePreview(Message message) {
    switch (message.type) {
      case MessageType.text:
        // Check if this is an encrypted message that needs decryption
        if (message.isEncrypted) {
          // Check if it's from current user (show without decryption)
          final currentUserId = _getCurrentUserId();
          if (message.senderId == currentUserId) {
            // Your own message - show original text
            final text = message.content['text'] as String?;
            if (text != null && text.isNotEmpty) {
              return text;
            } else {
              return '[Your message]';
            }
          } else {
            // Other user's message - check if it's incoming encrypted
            if (message.content.containsKey('isIncomingEncrypted') &&
                (message.content['isIncomingEncrypted'] == true ||
                    message.content['isIncomingEncrypted'] == 'true')) {
              return '[Encrypted Message]';
            } else {
              // Regular message from other user
              return message.content['text'] as String? ?? '[Message]';
            }
          }
        }
        return message.content['text'] as String? ?? '';
      case MessageType.reply:
        final replyText = message.content['reply_text'] as String? ?? '';
        return '↩️ Reply: $replyText';
      case MessageType.system:
        return message.content['system_text'] as String? ?? 'System message';
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
      print('📱 ChatListProvider: ❌ Failed to toggle mute notifications: $e');
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
    String? messageId, // Add messageId parameter
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

      // CRITICAL: Only find conversation by consistent ID
      ChatConversation? existingConversation;

      try {
        existingConversation = _conversations.firstWhere(
          (conv) => conv.id == conversationId,
        );
        print(
            '📱 ChatListProvider: ✅ Found conversation by consistent ID: $conversationId');
      } catch (e) {
        existingConversation = null;
        print(
            '📱 ChatListProvider: ⚠️ No existing conversation found for ID: $conversationId');
      }

      if (existingConversation != null) {
        // Update existing conversation
        final updatedConversation = existingConversation.copyWith(
          lastMessageAt: DateTime.now(),
          lastMessageId: messageId ??
              'msg_${DateTime.now().millisecondsSinceEpoch}', // Use provided messageId or generate one
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
          lastMessageId: messageId ?? conversationId,
          lastMessagePreview: message,
          lastMessageType: MessageType.text,
          unreadCount: 1,
          isArchived: false,
          isMuted: false,
          isPinned: false,
          metadata: null,
          lastSeen: null,
          isOnline: false,
          isTyping: false,
          typingStartedAt: null,
          notificationsEnabled: true,
          soundEnabled: true,
          vibrationEnabled: true,
          readReceiptsEnabled: true,
          typingIndicatorsEnabled: true,
          lastSeenEnabled: true,
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

  /// Add a new conversation by recipient ID
  void _addNewConversationByRecipient(
      String recipientId, String recipientName) {
    try {
      // CRITICAL: Use consistent conversation ID for both users
      final senderUserId = _getCurrentUserId();
      final conversationId =
          _generateConsistentConversationId(senderUserId, recipientId);

      // Check if conversation already exists
      if (_conversations.any((conv) => conv.id == conversationId)) {
        print(
            '📱 ChatListProvider: ℹ️ Conversation already exists: $conversationId');
        return;
      }

      final currentUserId = _getCurrentUserId();

      // Create new conversation
      final newConversation = ChatConversation(
        id: conversationId,
        participant1Id: currentUserId,
        participant2Id: recipientId,
        displayName: recipientName,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastMessageAt: null,
        lastMessageId: null,
        lastMessagePreview: null,
        lastMessageType: null,
        unreadCount: 0,
        isArchived: false,
        isMuted: false,
        isPinned: false,
        metadata: null,
        lastSeen: null,
        isOnline: false,
        isTyping: false,
        typingStartedAt: null,
        notificationsEnabled: true,
        soundEnabled: true,
        vibrationEnabled: true,
        readReceiptsEnabled: true,
        typingIndicatorsEnabled: true,
        lastSeenEnabled: true,
      );

      _conversations.add(newConversation);
      _applySearchFilter();
      notifyListeners();

      print('📱 ChatListProvider: ✅ Added new conversation: $conversationId');
    } catch (e) {
      print('📱 ChatListProvider: ❌ Failed to add new conversation: $e');
    }
  }

  /// Generate consistent conversation ID that both users will have
  /// This ensures messages appear in the same conversation for both users
  /// Updated to match server's new consistent ID format
  String _generateConsistentConversationId(String user1Id, String user2Id) {
    // Sort user IDs alphabetically to ensure consistency
    final sortedIds = [user1Id, user2Id]..sort();
    // Server expects conversation IDs to start with 'chat_' prefix
    return 'chat_${sortedIds[0]}_${sortedIds[1]}';
  }

  /// Ensure conversation exists, create if it doesn't
  Future<void> ensureConversationExists(
      String conversationId, String senderId, String senderName) async {
    try {
      // Check if conversation already exists
      ChatConversation? existingConversation;
      try {
        existingConversation = _conversations.firstWhere(
          (conv) => conv.id == conversationId,
        );
      } catch (e) {
        existingConversation = null;
      }

      if (existingConversation == null) {
        // Create new conversation
        final currentUserId = _getCurrentUserId();
        final newConversation = ChatConversation(
          id: conversationId,
          participant1Id: currentUserId,
          participant2Id: senderId,
          displayName: senderName,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          lastMessageAt: null,
          lastMessageId: null,
          lastMessagePreview: null,
          lastMessageType: null,
          unreadCount: 0,
          isArchived: false,
          isMuted: false,
          isPinned: false,
          metadata: null,
          lastSeen: null,
          isOnline: false,
          isTyping: false,
          typingStartedAt: null,
          notificationsEnabled: true,
          soundEnabled: true,
          vibrationEnabled: true,
          readReceiptsEnabled: true,
          typingIndicatorsEnabled: true,
          lastSeenEnabled: true,
        );

        // Save to storage
        await _storageService.saveConversation(newConversation);

        // Add to local state
        _conversations.add(newConversation);
        _applySearchFilter();
        notifyListeners();

        print('📱 ChatListProvider: ✅ Created conversation: $conversationId');
      } else {
        print(
            '📱 ChatListProvider: ℹ️ Conversation already exists: $conversationId');
      }
    } catch (e) {
      print('📱 ChatListProvider: ❌ Failed to ensure conversation: $e');
    }
  }

  /// Handle outgoing message
  void handleOutgoingMessage(
      String recipientId, String content, String messageId) {
    try {
      // CRITICAL: Use consistent conversation ID for both users
      final currentUserId = _getCurrentUserId();
      final conversationId =
          _generateConsistentConversationId(currentUserId, recipientId);

      // Find existing conversation
      final conversationIndex =
          _conversations.indexWhere((conv) => conv.id == conversationId);

      if (conversationIndex != -1) {
        // Update existing conversation
        final conversation = _conversations[conversationIndex];
        _conversations[conversationIndex] = conversation.copyWith(
          lastMessagePreview: content,
          lastMessageId: messageId,
          lastMessageAt: DateTime.now(),
          lastMessageType: MessageType.text,
          updatedAt: DateTime.now(),
        );
      } else {
        // Create new conversation if it doesn't exist
        _addNewConversationByRecipient(
            recipientId, 'User ${recipientId.substring(0, 8)}...');

        // Update the newly created conversation
        final newConversationIndex =
            _conversations.indexWhere((conv) => conv.id == conversationId);
        if (newConversationIndex != -1) {
          final conversation = _conversations[newConversationIndex];
          _conversations[newConversationIndex] = conversation.copyWith(
            lastMessagePreview: content,
            lastMessageId: messageId,
            lastMessageAt: DateTime.now(),
            lastMessageType: MessageType.text,
            updatedAt: DateTime.now(),
          );
        }
      }

      _applySearchFilter();
      notifyListeners();

      print(
          '📱 ChatListProvider: ✅ Updated conversation with outgoing message: $conversationId');
    } catch (e) {
      print('📱 ChatListProvider: ❌ Failed to handle outgoing message: $e');
    }
  }

  /// Refresh a specific conversation with latest data
  Future<void> refreshConversation(String conversationId) async {
    try {
      print('📱 ChatListProvider: 🔄 Refreshing conversation: $conversationId');

      // Get the latest conversation data from storage
      final currentUserId = _getCurrentUserId();
      final conversations =
          await _storageService.getUserConversations(currentUserId);

      // Find and update the specific conversation
      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index != -1) {
        final updatedConversation = conversations.firstWhere(
          (c) => c.id == conversationId,
          orElse: () => _conversations[index],
        );

        _conversations[index] = updatedConversation;

        // Sort conversations by last message time
        _conversations.sort((a, b) {
          final aTime = a.lastMessageAt ?? a.createdAt;
          final bTime = b.lastMessageAt ?? b.createdAt;
          return bTime.compareTo(aTime);
        });

        _applySearchFilter();
        notifyListeners();

        print('📱 ChatListProvider: ✅ Conversation refreshed: $conversationId');
      }
    } catch (e) {
      print('📱 ChatListProvider: ❌ Error refreshing conversation: $e');
    }
  }

  /// Setup online status callback - REMOVED DUPLICATE
  void _setupOnlineStatusCallback() {
    try {
      // REMOVED: Direct callback to SeSocketService to avoid duplication
      // Online status updates now come through main.dart -> updateConversationOnlineStatus
      print(
          '🔌 ChatListProvider: ℹ️ Online status updates handled via main.dart callback (no duplicate)');
      print('🔌 ChatListProvider: ✅ Online status callback setup complete');
    } catch (e) {
      print(
          '🔌 ChatListProvider: ❌ Error setting up online status callback: $e');
    }
  }

  /// Handle online status update
  void _handleOnlineStatusUpdate(
      String senderId, bool isOnline, String? lastSeen) {
    try {
      print(
          '📱 ChatListProvider: 🔔 Online status update: $senderId -> $isOnline');

      // Find conversation with this sender and update online status
      final conversationIndex = _conversations.indexWhere(
        (conv) =>
            conv.participant1Id == senderId || conv.participant2Id == senderId,
      );

      if (conversationIndex != -1) {
        final conversation = _conversations[conversationIndex];
        final updatedConversation = conversation.copyWith(
          lastSeen: lastSeen != null ? DateTime.tryParse(lastSeen) : null,
          isOnline: isOnline,
        );

        _conversations[conversationIndex] = updatedConversation;
        _applySearchFilter();
        notifyListeners();

        // Notify other providers about online status change
        if (_onOnlineStatusChanged != null) {
          _onOnlineStatusChanged!(
              senderId, isOnline, updatedConversation.lastSeen);
        }

        print(
            '📱 ChatListProvider: ✅ Online status updated for conversation: ${conversation.id}');
      } else {
        print(
            '📱 ChatListProvider: ⚠️ No conversation found for sender: $senderId');
      }
    } catch (e) {
      print('📱 ChatListProvider: ❌ Error handling online status update: $e');
    }
  }

  /// Setup socket callbacks
  void _setupSocketCallbacks() {
    _setupConversationCreationListener();
    _setupStatusTracking();
    _setupRealtimeServices();
    _setupOnlineStatusCallback();
  }
}
