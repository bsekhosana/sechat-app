import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../core/services/se_session_service.dart';
import '../../../core/services/se_socket_service.dart';
import '../../../core/services/contact_service.dart';
import '../../../core/services/encryption_service.dart';
import '../../../realtime/realtime_service_manager.dart';
import '../../../realtime/presence_service.dart';

import '../services/message_storage_service.dart';
import '../services/message_status_tracking_service.dart';
import '../models/message.dart';
import '../models/message_status.dart' as msg_status;
import '../models/chat_conversation.dart';
import 'package:sechat_app/core/utils/conversation_id_generator.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import 'session_chat_provider.dart';
import '/../core/utils/logger.dart';

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

  // Reference to active SessionChatProvider for real-time updates
  SessionChatProvider? _activeSessionChatProvider;

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

  /// Set the active SessionChatProvider for real-time updates
  void setActiveSessionChatProvider(SessionChatProvider? provider) {
    _activeSessionChatProvider = provider;
    Logger.success(
        '📱 ChatListProvider: ${provider != null ? ' Set' : '❌ Cleared'} active SessionChatProvider');
  }

  /// Get real-time online status for a specific recipient
  bool getRecipientOnlineStatus(String recipientId) {
    // 🆕 FIXED: Use ContactService as primary source of truth for presence
    // This ensures consistent presence data across the app
    try {
      final contactService = ContactService.instance;
      final contact = contactService.getContact(recipientId);
      if (contact != null) {
        Logger.success(
            '📱 ChatListProvider:  Using ContactService presence for $recipientId: ${contact.isOnline}');
        return contact.isOnline;
      }
    } catch (e) {
      Logger.warning(
          '📱 ChatListProvider:  ContactService not available, falling back: $e');
    }

    // Fallback to conversation data if ContactService not available
    try {
      final conversation = _conversations.firstWhere(
        (conv) =>
            conv.participant1Id == recipientId ||
            conv.participant2Id == recipientId,
      );
      Logger.success(
          '📱 ChatListProvider:  Using conversation presence for $recipientId: ${conversation.isOnline}');
      return conversation.isOnline ?? false;
    } catch (e) {
      // No conversation found, default to offline
      Logger.warning(
          '📱 ChatListProvider:  No presence data found for $recipientId, defaulting to offline');
      return false;
    }
  }

  /// Process message status update from external source
  void processMessageStatusUpdate(MessageStatusUpdate update) {
    _updateMessageStatus(update);
  }

  /// Process message status update with additional context for better conversation lookup
  Future<void> processMessageStatusUpdateWithContext(
    MessageStatusUpdate update, {
    String? conversationId,
    String? recipientId,
  }) async {
    // 🆕 FIXED: Process ALL status updates including delivered/read for chat list items
    // The chat list needs to show the latest message status for proper UI updates
    Logger.info(
        '📱 ChatListProvider:  Processing status update: ${update.messageId} -> ${update.status}');

    // First, update the chat list (conversation metadata)
    await _updateMessageStatusWithContext(update,
        conversationId: conversationId, recipientId: recipientId);

    // Then, forward the update to the active SessionChatProvider for real-time UI updates
    if (_activeSessionChatProvider != null) {
      try {
        Logger.info(
            '📱 ChatListProvider:  Forwarding status update to SessionChatProvider: ${update.messageId} -> ${update.status}');
        await _activeSessionChatProvider!.handleMessageStatusUpdate(update);
        Logger.success(
            '📱 ChatListProvider:  Forwarded message status update to active SessionChatProvider');
      } catch (e) {
        Logger.warning(
            '📱 ChatListProvider:  Failed to forward status update to SessionChatProvider: $e');
      }
    } else {
      Logger.info(
          '📱 ChatListProvider:  No active SessionChatProvider to forward status update to');
      Logger.info(
          '📱 ChatListProvider:  Active provider: $_activeSessionChatProvider');
    }
  }

  /// Handle new message arrival and update chat list in real-time
  Future<void> handleNewMessageArrival({
    required String messageId,
    required String senderId,
    required String content,
    required String conversationId,
    required DateTime timestamp,
    required MessageType messageType,
  }) async {
    try {
      Logger.info(
          '📱 ChatListProvider:  Handling new message arrival: $messageId');

      // Find the conversation
      final conversationIndex = _conversations.indexWhere(
        (conv) => conv.id == conversationId,
      );

      if (conversationIndex != -1) {
        // CRITICAL: Decrypt the message content for preview
        String decryptedPreview = content;

        // Debug: Log the content being processed
        Logger.debug(
            '📱 ChatListProvider: 🔍 Processing message content for preview: ${content.length} chars, starts with: ${content.length > 50 ? content.substring(0, 50) : content}');

        // Check if this looks like encrypted content (base64 encoded JSON)
        // Look for common patterns in encrypted messages
        bool isEncryptedContent = content.length > 100 &&
            (content.contains('eyJ') ||
                content.contains('eyJ2') ||
                content.startsWith('eyJ') ||
                content.contains('{"v":') ||
                content.contains('"alg":') ||
                content.contains('"iv":') ||
                content.contains('"ct":') ||
                // Additional patterns for encrypted content
                content.contains('AES-256-CBC') ||
                content.contains('PKCS7') ||
                // Check if it's a long base64 string (typical of encrypted content)
                (content.length > 200 &&
                    RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(content)));

        if (isEncryptedContent) {
          Logger.debug(
              '📱 ChatListProvider:  Attempting to decrypt message preview for chat list');
          try {
            // Use EncryptionService to decrypt the message (first layer)
            final decryptedData =
                await EncryptionService.decryptAesCbcPkcs7(content);

            if (decryptedData != null && decryptedData.containsKey('text')) {
              final firstLayerDecrypted = decryptedData['text'] as String;
              Logger.success(
                  '📱 ChatListProvider:  First layer decrypted for preview: $firstLayerDecrypted');

              // Check if the decrypted text is still encrypted (double encryption scenario)
              if (firstLayerDecrypted.length > 100 &&
                  firstLayerDecrypted.contains('eyJ')) {
                Logger.info(
                    '📱 ChatListProvider:  Detected double encryption in preview, decrypting inner layer...');
                try {
                  // Decrypt the inner encrypted content
                  final innerDecryptedData =
                      await EncryptionService.decryptAesCbcPkcs7(
                          firstLayerDecrypted);

                  if (innerDecryptedData != null &&
                      innerDecryptedData.containsKey('text')) {
                    final finalDecryptedText =
                        innerDecryptedData['text'] as String;
                    Logger.success(
                        '📱 ChatListProvider:  Inner layer decrypted for preview successfully');
                    decryptedPreview = finalDecryptedText;
                  } else {
                    Logger.warning(
                        '📱 ChatListProvider:  Inner layer decryption failed for preview, using first layer');
                    decryptedPreview = firstLayerDecrypted;
                  }
                } catch (e) {
                  Logger.error(
                      '📱 ChatListProvider:  Inner layer decryption error for preview: $e, using first layer');
                  decryptedPreview = firstLayerDecrypted;
                }
              } else {
                // Single layer encryption, use as is
                Logger.success(
                    '📱 ChatListProvider:  Single layer decryption completed for preview');
                decryptedPreview = firstLayerDecrypted;
              }
            } else {
              Logger.warning(
                  '📱 ChatListProvider:  Decryption failed for preview - invalid format, using encrypted text');
              decryptedPreview = '[Encrypted Message]';
            }
          } catch (e) {
            Logger.error(
                '📱 ChatListProvider:  Decryption failed for preview: $e');
            decryptedPreview = '[Encrypted Message]';
          }
        } else {
          Logger.info(
              '📱 ChatListProvider:  Message appears to be plain text for preview, using as-is');
        }

        // Update the conversation with new message info
        final oldConversation = _conversations[conversationIndex];
        final updatedConversation = oldConversation.copyWith(
          lastMessageId: messageId,
          lastMessagePreview: _truncateMessagePreview(decryptedPreview),
          lastMessageAt: timestamp,
          lastMessageType: messageType,
          updatedAt: DateTime.now(),
        );

        _conversations[conversationIndex] = updatedConversation;

        // Move this conversation to the top (most recent)
        _moveConversationToTop(conversationIndex);

        // Apply search filter and notify listeners
        _applySearchFilter();
        notifyListeners();

        Logger.success(
            '📱 ChatListProvider:  Chat list updated with decrypted message preview: $messageId');
      } else {
        Logger.warning(
            '📱 ChatListProvider:  Conversation not found for new message: $conversationId');
      }
    } catch (e) {
      Logger.error(
          '📱 ChatListProvider:  Error handling new message arrival: $e');
    }
  }

  /// Move conversation to top of list (most recent)
  void _moveConversationToTop(int conversationIndex) {
    if (conversationIndex > 0) {
      final conversation = _conversations.removeAt(conversationIndex);
      _conversations.insert(0, conversation);
      Logger.success(
          '📱 ChatListProvider:  Moved conversation to top: ${conversation.id}');
    }
  }

  /// Truncate message preview to reasonable length
  String _truncateMessagePreview(String content) {
    const maxLength = 50;
    if (content.length <= maxLength) return content;
    return '${content.substring(0, maxLength)}...';
  }

  /// Convert MessageDeliveryStatus to MessageStatus
  MessageStatus _convertDeliveryStatusToMessageStatus(
      msg_status.MessageDeliveryStatus deliveryStatus) {
    switch (deliveryStatus) {
      case msg_status.MessageDeliveryStatus.pending:
        return MessageStatus.pending;
      case msg_status.MessageDeliveryStatus.sent:
        return MessageStatus.sent;
      case msg_status.MessageDeliveryStatus.delivered:
        return MessageStatus.delivered;
      case msg_status.MessageDeliveryStatus.read:
        return MessageStatus.read;
      case msg_status.MessageDeliveryStatus.failed:
        return MessageStatus.failed;
      case msg_status.MessageDeliveryStatus.retrying:
        return MessageStatus.sending; // Map retrying to sending
    }
  }

  /// Update conversation online status from external source
  void updateConversationOnlineStatus(
      String userId, bool isOnline, String? lastSeen) {
    try {
      Logger.info(
          '📱 ChatListProvider:  Updating online status for user: $userId -> ${isOnline ? 'online' : 'offline'}');
      Logger.debug(
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

        Logger.debug(
            '📱 ChatListProvider: ✅ Online status updated for conversation: ${oldConversation.id} (${oldConversation.displayName}) -> ${oldConversation.isOnline} -> $isOnline');
        Logger.debug(
            '📱 ChatListProvider: 🔔 notifyListeners() called for presence update');
      } else {
        Logger.warning(
            '📱 ChatListProvider:  No conversation found for user: $userId');
        Logger.debug(
            '📱 ChatListProvider: 🔍 Available conversations: ${_conversations.map((c) => '${c.id} (${c.displayName})').join(', ')}');
      }
    } catch (e) {
      Logger.error('📱 ChatListProvider:  Error updating online status: $e');
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
      Logger.info(
          '📱 ChatListProvider:  Clearing all data and resetting state...');

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

      Logger.success('📱 ChatListProvider:  All data cleared and state reset');
    } catch (e) {
      Logger.error('📱 ChatListProvider:  Error clearing data: $e');
    }
  }

  /// Initialize the provider
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      Logger.debug('📱 ChatListProvider: Initializing...');

      // Initialize the channel-based socket service
      await _socketService.initialize();

      // Load existing conversations
      await _loadConversations();

      // Set up socket callbacks
      _setupSocketCallbacks();

      _isInitialized = true;
      Logger.success('📱 ChatListProvider:  Initialized successfully');
    } catch (e) {
      Logger.error('📱 ChatListProvider:  Failed to initialize: $e');
      rethrow;
    }
  }

  /// Load conversations from storage
  Future<void> _loadConversations() async {
    try {
      final currentUserId = _getCurrentUserId();
      if (currentUserId == 'unknown_user') {
        Logger.error('📱 ChatListProvider:  No current user session found');
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

          // Clear all typing indicators to remove stale data
          clearAllTypingIndicators();

          _applySearchFilter();
          databaseReady = true;

          Logger.success(
              '📱 ChatListProvider:  Loaded ${conversations.length} conversations from database');

          // If we have conversations but they're all empty, there might be a parsing issue
          if (conversations.isNotEmpty &&
              conversations.every((c) => c.id.isEmpty)) {
            Logger.warning(
                '📱 ChatListProvider:  All conversations have empty IDs, possible parsing issue');
            _setError(
                'Conversation data corrupted. Please try recreating the database.');
          }
        } catch (e) {
          retryCount++;
          if (e.toString().contains('Database not initialized')) {
            Logger.debug(
                '📱 ChatListProvider: ⏳ MessageStorageService database not ready, retry $retryCount/$maxRetries...');
            if (retryCount < maxRetries) {
              // Wait a bit for the database to be ready
              await Future.delayed(const Duration(milliseconds: 500));
            } else {
              Logger.error(
                  '📱 ChatListProvider:  Database still not ready after $maxRetries retries');
              _conversations = [];
              _applySearchFilter();
              databaseReady =
                  true; // Mark as ready even with empty conversations
            }
          } else {
            Logger.error(
                '📱 ChatListProvider:  Failed to load conversations: $e');
            _conversations = [];
            _applySearchFilter();
            databaseReady = true; // Mark as ready even with empty conversations
            break;
          }
        }
      }

      // Ensure we always have a result, even if it's empty
      if (!databaseReady) {
        Logger.warning(
            '📱 ChatListProvider:  Database not ready, using empty conversations');
        _conversations = [];
        _applySearchFilter();
      }
    } catch (e) {
      Logger.error('📱 ChatListProvider:  Failed to load conversations: $e');
      // Don't rethrow, just log the error and continue with empty conversations
      _conversations = [];
      _applySearchFilter();
    }
  }

  /// Load last messages for all conversations to populate previews
  Future<void> _loadLastMessagesForAllConversations() async {
    try {
      Logger.info(
          '📱 ChatListProvider:  Loading last messages for all conversations...');

      for (int i = 0; i < _conversations.length; i++) {
        final conversation = _conversations[i];

        // Only load if we don't already have last message data
        if (conversation.lastMessagePreview == null ||
            conversation.lastMessageId == null) {
          final latestMessage = await getLatestMessage(conversation.id);
          if (latestMessage != null) {
            // CRITICAL: Use async decryption for message preview
            final messagePreview = await _getMessagePreviewAsync(latestMessage);

            final updatedConversation = conversation.copyWith(
              lastMessageAt: latestMessage.timestamp,
              lastMessageId: latestMessage.id,
              lastMessagePreview: messagePreview,
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

      Logger.success(
          '📱 ChatListProvider:  Last messages loaded for all conversations');
    } catch (e) {
      Logger.error('📱 ChatListProvider:  Error loading last messages: $e');
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
      Logger.success(
          ' ChatListProvider:  Socket service typing indicator callback set');
    } catch (e) {
      Logger.error(
          ' ChatListProvider:  Failed to set up socket service typing indicator callback: $e');
    }

    // Listen for online status updates from socket service
    try {
      final socketService = SeSocketService.instance;
      // Note: Online status updates are handled through lastSeen updates
      Logger.success(' ChatListProvider:  Status tracking services set up');
    } catch (e) {
      Logger.error(' ChatListProvider:  Failed to set up status tracking: $e');
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

        Logger.success(
            '📱 ChatListProvider:  Online status updated for conversation: $conversationId');
        notifyListeners();
      }
    } catch (e) {
      Logger.error('📱 ChatListProvider:  Error updating online status: $e');
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

        Logger.success(
            ' ChatListProvider:  Updated conversation display name: $senderId -> $displayName');
      } else {
        Logger.warning(
            ' ChatListProvider:  No conversation found for user data exchange: $senderId');
      }
    } catch (e) {
      Logger.error(' ChatListProvider:  Error handling user data exchange: $e');
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

        Logger.success(
            ' ChatListProvider:  Updated display name for conversation: $conversationId -> $displayName');
      } else {
        Logger.warning(
            ' ChatListProvider:  No conversation found to update display name: $conversationId');
      }
    } catch (e) {
      Logger.error(
          ' ChatListProvider:  Error updating conversation display name: $e');
    }
  }

  /// Setup conversation creation listener
  void _setupConversationCreationListener() {
    try {
      final socketService = SeSocketService.instance;
      socketService.setOnConversationCreated((conversationData) async {
        Logger.info(
            ' ChatListProvider:  New conversation created: ${conversationData['conversation_id_local'] ?? 'unknown'}');

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
              Logger.success(
                  ' ChatListProvider:  Conversation saved to database: $conversationId');
            } catch (e) {
              Logger.error(
                  ' ChatListProvider:  Failed to save conversation to database: $e');
            }

            _addNewConversation(conversation);
            Logger.success(
                ' ChatListProvider:  Conversation created and added: ${conversation.id}');
          }
        } catch (e) {
          Logger.error(
              ' ChatListProvider:  Error creating conversation from socket data: $e');
        }

        Logger.debug(' ChatListProvider: Conversation data: $conversationData');
      });
      Logger.success(
          ' ChatListProvider:  Conversation creation listener set up');
    } catch (e) {
      Logger.error(
          ' ChatListProvider:  Failed to set up conversation creation listener: $e');
    }
  }

  /// Setup realtime services for presence and typing
  void _setupRealtimeServices() {
    try {
      // Check if already initialized
      if (_presenceService != null) {
        Logger.info(
            '📱 ChatListProvider:  Presence service already initialized');
        return;
      }

      // Initialize presence service
      _presenceService = RealtimeServiceManager().presence;

      // Note: Presence updates are handled through the existing socket service
      // The realtime presence service will be used for local presence management
      // and peer presence updates will come through the socket service callbacks

      Logger.success(
          '📱 ChatListProvider:  Realtime services set up successfully');
    } catch (e) {
      Logger.error(
          '📱 ChatListProvider:  Failed to set up realtime services: $e');
    }
  }

  /// Handle typing indicator from socket service
  void _handleTypingIndicatorFromSocket(String senderId, bool isTyping) {
    try {
      Logger.debug(
          '📱 ChatListProvider:  Typing indicator from socket: $senderId -> $isTyping');

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

        Logger.success(
            '📱 ChatListProvider:  Updated typing indicator for conversation: ${conversation.id}');
      } else {
        Logger.warning(
            '📱 ChatListProvider:  No conversation found for typing indicator from: $senderId');
      }
    } catch (e) {
      Logger.error(
          '📱 ChatListProvider:  Error handling typing indicator from socket: $e');
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

  /// Clear all typing indicators (call this when app loads to clear stale data)
  void clearAllTypingIndicators() {
    try {
      Logger.info('📱 ChatListProvider:  Clearing all typing indicators');

      bool hasChanges = false;
      for (int i = 0; i < _conversations.length; i++) {
        if (_conversations[i].isTyping == true) {
          _conversations[i] = _conversations[i].copyWith(
            isTyping: false,
            typingStartedAt: null,
          );
          hasChanges = true;
        }
      }

      if (hasChanges) {
        _applySearchFilter();
        notifyListeners();
        Logger.success('📱 ChatListProvider:  All typing indicators cleared');
      }
    } catch (e) {
      Logger.error(
          '📱 ChatListProvider:  Error clearing typing indicators: $e');
    }
  }

  /// Update typing indicator by participant ID (for socket events)
  void updateTypingIndicatorByParticipant(String participantId, bool isTyping) {
    try {
      Logger.debug(
          '📱 ChatListProvider:  Updating typing indicator for participant: $participantId -> $isTyping');

      // CRITICAL: Prevent sender from processing their own typing indicator
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId != null && participantId == currentUserId) {
        Logger.warning(
            '📱 ChatListProvider:  Ignoring own typing indicator from: $participantId');
        return; // Don't process own typing indicator
      }

      // Find conversation by participant ID
      final index = _conversations.indexWhere((conv) =>
          conv.participant1Id == participantId ||
          conv.participant2Id == participantId);

      if (index != -1) {
        final conversation = _conversations[index];

        // CRITICAL: Only show typing indicator if the participant is NOT the current user
        // This ensures typing indicators are shown on the recipient's side, not the sender's side
        final currentUserId = SeSessionService().currentSessionId;
        if (currentUserId != null && participantId == currentUserId) {
          Logger.warning(
              '📱 ChatListProvider:  Not showing typing indicator for own conversation');
          return; // Don't show typing indicator for own conversation
        }

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
              Logger.success(
                  '📱 ChatListProvider:  Auto-cleared typing indicator for conversation: ${conversation.id}');
            }
          });
        }

        Logger.success(
            '📱 ChatListProvider:  Updated typing indicator for conversation: ${conversation.id}');
      } else {
        Logger.warning(
            '📱 ChatListProvider:  No conversation found for typing indicator from: $participantId');
      }
    } catch (e) {
      Logger.error(
          '📱 ChatListProvider:  Error updating typing indicator by participant: $e');
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

      Logger.success(
          '📱 ChatListProvider:  Last seen updated for conversation: ${conversation.id}');
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
        Logger.success(
            '📱 ChatListProvider:  New conversation added to list: ${conversation.id}');
      } else {
        Logger.info(
            '📱 ChatListProvider:  Conversation already exists: ${conversation.id}');
      }
    } catch (e) {
      Logger.error('📱 ChatListProvider:  Error adding new conversation: $e');
    }
  }

  /// Update message status for a conversation - FIXED conversation lookup
  Future<void> _updateMessageStatus(MessageStatusUpdate update) async {
    try {
      Logger.debug(
          '📱 ChatListProvider: Message status update received for message: ${update.messageId}');

      // CRITICAL FIX: Find conversation by multiple methods
      ChatConversation? conversation;

      // Method 1: Try to find by lastMessageId (original method)
      try {
        conversation = _conversations.firstWhere(
          (conv) => conv.lastMessageId == update.messageId,
        );
        Logger.success(
            '📱 ChatListProvider:  Found conversation by lastMessageId: ${conversation.id}');
      } catch (e) {
        conversation = null;
        Logger.warning(
            '📱 ChatListProvider:  No conversation found by lastMessageId');
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
          Logger.success(
              '📱 ChatListProvider:  Found conversation by senderId: ${conversation.id}');
        } catch (e) {
          Logger.warning(
              '📱 ChatListProvider:  No conversation found by senderId: ${update.senderId}');
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

        // CRITICAL FIX: Update the actual message status in the database
        try {
          // Convert MessageDeliveryStatus to MessageStatus
          final messageStatus =
              _convertDeliveryStatusToMessageStatus(update.status);
          await _storageService.updateMessageStatus(
              update.messageId, messageStatus);
          Logger.success(
              '📱 ChatListProvider:  Message status updated in database: ${update.messageId} -> ${messageStatus}');
        } catch (e) {
          Logger.warning(
              '📱 ChatListProvider:  Failed to update message status in database: $e');
        }

        // Update local state
        final index =
            _conversations.indexWhere((c) => c.id == conversation!.id);
        if (index != -1) {
          _conversations[index] = updatedConversation;
        }

        // Apply search filter and notify listeners
        _applySearchFilter();
        notifyListeners();

        Logger.success(
            '📱 ChatListProvider:  Message status updated for conversation: ${conversation.id}');
      } else {
        Logger.warning(
            '📱 ChatListProvider:  No conversation found for message: ${update.messageId}');
        Logger.debug(
            '📱 ChatListProvider: 🔍 Available conversations: ${_conversations.map((c) => '${c.id} (lastMsg: ${c.lastMessageId})').join(', ')}');
        Logger.info(
            '📱 ChatListProvider:  Update details: senderId=${update.senderId}');
      }
    } catch (e) {
      Logger.error('📱 ChatListProvider:  Error updating message status: $e');
    }
  }

  /// Update message status with additional context for better conversation lookup
  Future<void> _updateMessageStatusWithContext(
    MessageStatusUpdate update, {
    String? conversationId,
    String? recipientId,
  }) async {
    try {
      Logger.debug(
          '📱 ChatListProvider: Message status update with context for message: ${update.messageId}');
      Logger.info(
          '📱 ChatListProvider:  Context: conversationId=$conversationId, recipientId=$recipientId');

      // ENHANCED LOOKUP: Use the additional context for better conversation finding
      ChatConversation? conversation;

      // Method 1: Try to find by conversationId from context (actual conversation ID)
      if (conversation == null && conversationId != null) {
        try {
          // CRITICAL: conversationId is the actual conversation ID (chat_session1_session2)
          // Find conversation by its ID directly
          conversation = _conversations.firstWhere(
            (conv) => conv.id == conversationId,
          );
          Logger.success(
              '📱 ChatListProvider:  Found conversation by context conversationId: ${conversation.id}');
        } catch (e) {
          Logger.warning(
              '📱 ChatListProvider:  No conversation found by context conversationId: $conversationId');
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
          Logger.success(
              '📱 ChatListProvider:  Found conversation by context recipientId: ${conversation.id}');
        } catch (e) {
          Logger.warning(
              '📱 ChatListProvider:  No conversation found by context recipientId: $recipientId');
        }
      }

      // Method 3: Fall back to lastMessageId (original method)
      if (conversation == null) {
        try {
          conversation = _conversations.firstWhere(
            (conv) => conv.lastMessageId == update.messageId,
          );
          Logger.success(
              '📱 ChatListProvider:  Found conversation by lastMessageId: ${conversation.id}');
        } catch (e) {
          Logger.warning(
              '📱 ChatListProvider:  No conversation found by lastMessageId');
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
          Logger.success(
              '📱 ChatListProvider:  Found conversation by update senderId: ${conversation.id}');
        } catch (e) {
          Logger.warning(
              '📱 ChatListProvider:  No conversation found by update senderId: ${update.senderId}');
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

        // CRITICAL FIX: Update the actual message status in the database
        try {
          // Convert MessageDeliveryStatus to MessageStatus
          final messageStatus =
              _convertDeliveryStatusToMessageStatus(update.status);
          await _storageService.updateMessageStatus(
              update.messageId, messageStatus);
          Logger.success(
              '📱 ChatListProvider:  Message status updated in database: ${update.messageId} -> ${messageStatus}');
        } catch (e) {
          Logger.warning(
              '📱 ChatListProvider:  Failed to update message status in database: $e');
        }

        // Update local state
        final index =
            _conversations.indexWhere((c) => c.id == conversation!.id);
        if (index != -1) {
          _conversations[index] = updatedConversation;
        }

        // Apply search filter and notify listeners
        _applySearchFilter();
        notifyListeners();

        Logger.success(
            '📱 ChatListProvider:  Message status updated with context for conversation: ${conversation.id}');
      } else {
        Logger.warning(
            '📱 ChatListProvider:  No conversation found for message with context: ${update.messageId}');
        Logger.debug(
            '📱 ChatListProvider: 🔍 Available conversations: ${_conversations.map((c) => '${c.id} (lastMsg: ${c.lastMessageId})').join(', ')}');
        Logger.info(
            '📱 ChatListProvider:  Context details: conversationId=$conversationId, recipientId=$recipientId, senderId=${update.senderId}');
      }
    } catch (e) {
      Logger.error(
          '📱 ChatListProvider:  Error updating message status with context: $e');
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
      Logger.info('📱 ChatListProvider:  Refreshing conversations...');
      await _loadConversations();
      notifyListeners();
      Logger.success('📱 ChatListProvider:  Conversations refreshed');
    } catch (e) {
      Logger.error('📱 ChatListProvider:  Failed to refresh conversations: $e');
      _setError('Failed to refresh conversations: $e');
    }
  }

  /// Force refresh UI state
  void forceRefresh() {
    Logger.info('📱 ChatListProvider:  Forcing UI refresh');
    notifyListeners();
  }

  /// Force reset loading state (for debugging)
  void forceResetLoading() {
    Logger.info('📱 ChatListProvider:  Force resetting loading state');
    _isLoading = false;
    _hasError = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Force database recreation (for schema issues)
  Future<void> forceDatabaseRecreation() async {
    try {
      Logger.info('📱 ChatListProvider:  Force recreating database...');
      await _storageService.forceRecreateDatabase();
      await _loadConversations();
      notifyListeners();
      Logger.success(
          '📱 ChatListProvider:  Database recreated and conversations reloaded');
    } catch (e) {
      Logger.error('📱 ChatListProvider:  Failed to recreate database: $e');
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
      Logger.error('📱 ChatListProvider:  Error getting latest message: $e');
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

          // CRITICAL: Use async decryption for message preview
          final messagePreview = await _getMessagePreviewAsync(latestMessage);

          final updatedConversation = conversation.copyWith(
            lastMessageAt: latestMessage.timestamp,
            lastMessageId: latestMessage.id,
            lastMessagePreview: messagePreview,
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

          Logger.success(
              '📱 ChatListProvider:  Conversation updated with latest message: $conversationId');
        }
      }
    } catch (e) {
      Logger.error(
          '📱 ChatListProvider:  Error updating conversation with latest message: $e');
    }
  }

  /// Get message preview text with async decryption support
  Future<String> _getMessagePreviewAsync(Message message) async {
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
              // CRITICAL: Try to decrypt incoming encrypted messages for chat list preview
              return await _decryptMessageForPreviewAsync(message);
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

  /// Decrypt message content for chat list preview (async version)
  Future<String> _decryptMessageForPreviewAsync(Message message) async {
    try {
      // Check if we have the text content to decrypt
      if (!message.content.containsKey('text')) {
        return '[Encrypted Message]';
      }

      final encryptedText = message.content['text'] as String?;
      if (encryptedText == null || encryptedText.isEmpty) {
        return '[Encrypted Message]';
      }

      // CRITICAL: For chat list preview, we need to decrypt the message content
      // This is the same logic used in TextMessageBubble
      if (encryptedText.length > 100 && encryptedText.contains('eyJ')) {
        // This looks like encrypted data, try to decrypt it
        Logger.debug(
            '📱 ChatListProvider:  Attempting to decrypt message for preview: ${message.id}');

        try {
          // Use EncryptionService to decrypt the message
          final decryptedData =
              await EncryptionService.decryptAesCbcPkcs7(encryptedText);

          if (decryptedData != null && decryptedData.containsKey('text')) {
            final decryptedText = decryptedData['text'] as String;
            Logger.success(
                '📱 ChatListProvider:  First layer decrypted: $decryptedText');

            // CRITICAL: Check if the decrypted text is still encrypted (double encryption scenario)
            if (decryptedText.length > 100 && decryptedText.contains('eyJ')) {
              Logger.info(
                  '📱 ChatListProvider:  Detected double encryption, decrypting inner layer...');
              Logger.debug(
                  '📱 ChatListProvider: 🔍 First layer decrypted text preview: ${decryptedText.substring(0, decryptedText.length > 100 ? 100 : decryptedText.length)}...');

              try {
                // Decrypt the inner encrypted content
                final innerDecryptedData =
                    await EncryptionService.decryptAesCbcPkcs7(decryptedText);

                if (innerDecryptedData != null &&
                    innerDecryptedData.containsKey('text')) {
                  final finalDecryptedText =
                      innerDecryptedData['text'] as String;
                  Logger.success(
                      '📱 ChatListProvider:  Inner layer decrypted successfully');
                  Logger.info(
                      '📱 ChatListProvider:  Final decrypted text: $finalDecryptedText');
                  return finalDecryptedText;
                } else {
                  Logger.warning(
                      '📱 ChatListProvider:  Inner layer decryption failed');
                  return decryptedText; // Return the first layer decrypted text as fallback
                }
              } catch (e) {
                Logger.error(
                    '📱 ChatListProvider:  Inner layer decryption error: $e');
                return decryptedText; // Return the first layer decrypted text as fallback
              }
            } else {
              // Single layer encryption, return as is
              Logger.success(
                  '📱 ChatListProvider:  Single layer decryption completed');
              return decryptedText;
            }
          } else {
            Logger.warning(
                '📱 ChatListProvider:  Decryption failed - invalid format');
            return '[Encrypted Message]';
          }
        } catch (e) {
          Logger.error(
              '📱 ChatListProvider:  Decryption failed for preview: $e');
          return '[Encrypted Message]';
        }
      } else {
        // This might be plain text or already decrypted
        return encryptedText;
      }
    } catch (e) {
      Logger.error(
          '📱 ChatListProvider:  Error decrypting message preview: $e');
      return '[Encrypted Message]';
    }
  }

  /// Refresh conversations when screen becomes visible
  Future<void> onScreenVisible() async {
    try {
      Logger.debug(
          '📱 ChatListProvider: 👁️ Screen became visible, refreshing conversations...');
      // Only refresh if we don't have conversations or if there was an error
      if (_conversations.isEmpty || _hasError) {
        await _loadConversations();
        notifyListeners();
      }
    } catch (e) {
      Logger.error(
          '📱 ChatListProvider:  Failed to refresh on screen visible: $e');
    }
  }

  /// Handle database corruption by forcing recreation
  Future<void> handleDatabaseCorruption() async {
    try {
      Logger.debug('📱 ChatListProvider: 🔧 Handling database corruption...');
      _setError('Database corrupted. Recreating...');
      await forceDatabaseRecreation();
      _clearError();
      Logger.success(
          '📱 ChatListProvider:  Database corruption handled successfully');
    } catch (e) {
      Logger.error(
          '📱 ChatListProvider:  Failed to handle database corruption: $e');
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

      Logger.success(
          '📱 ChatListProvider:  Conversation ${conversation.id} added/updated');
    } catch (e) {
      Logger.error('📱 ChatListProvider:  Failed to add conversation: $e');
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

      Logger.success(
          '📱 ChatListProvider:  Conversation updated with new message');
    } catch (e) {
      Logger.error(
          '📱 ChatListProvider:  Failed to update conversation with message: $e');
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

        Logger.success('📱 ChatListProvider:  Conversation marked as read');
      }
    } catch (e) {
      Logger.error(
          '📱 ChatListProvider:  Failed to mark conversation as read: $e');
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

        Logger.success(
            '📱 ChatListProvider:  Notifications ${updatedConversation.isMuted ? 'muted' : 'unmuted'}');
      }
    } catch (e) {
      Logger.error(
          '📱 ChatListProvider:  Failed to toggle mute notifications: $e');
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
        Logger.debug('📱 ChatListProvider: Blocking not implemented yet');
      }
    } catch (e) {
      Logger.error('📱 ChatListProvider:  Failed to block user: $e');
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

      Logger.success('📱 ChatListProvider:  Conversation deleted');
    } catch (e) {
      Logger.error('📱 ChatListProvider:  Failed to delete conversation: $e');
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
    Logger.info('📱 ChatListProvider:  Setting loading to: $loading');
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
    Logger.error('📱 ChatListProvider:  Error: $message');
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
    Logger.success('📱 ChatListProvider:  Provider disposed');
    super.dispose();
  }

  /// Refresh chat list order based on latest message times
  void refreshChatListOrder() {
    try {
      // Clear all typing indicators to remove stale data
      clearAllTypingIndicators();

      // Sort conversations by last message time (newest first)
      _conversations.sort((a, b) {
        final aTime = a.lastMessageAt ?? a.createdAt;
        final bTime = b.lastMessageAt ?? b.createdAt;
        return bTime.compareTo(aTime);
      });

      // Apply search filter
      _applySearchFilter();

      // Notify listeners to update UI
      notifyListeners();

      Logger.success('📱 ChatListProvider:  Chat list order refreshed');
    } catch (e) {
      Logger.error(
          '📱 ChatListProvider:  Error refreshing chat list order: $e');
    }
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
      Logger.debug(
          '📱 ChatListProvider: Handling incoming message from $senderName: $message');

      // CRITICAL: Decrypt the message content for chat list preview
      String decryptedMessagePreview = message;

      // Check if this looks like encrypted content
      if (message.length > 100 && message.contains('eyJ')) {
        Logger.debug(
            '📱 ChatListProvider:  Detected encrypted message, attempting decryption...');
        try {
          // Use EncryptionService to decrypt the message (first layer)
          final decryptedData =
              await EncryptionService.decryptAesCbcPkcs7(message);

          if (decryptedData != null && decryptedData.containsKey('text')) {
            final firstLayerDecrypted = decryptedData['text'] as String;
            Logger.success(
                '📱 ChatListProvider:  First layer decrypted: $firstLayerDecrypted');
            Logger.info(
                '📱 ChatListProvider:  First layer length: ${firstLayerDecrypted.length}');
            Logger.debug(
                '📱 ChatListProvider: 🔍 First layer contains eyJ: ${firstLayerDecrypted.contains('eyJ')}');

            // CRITICAL: Check if the decrypted text is still encrypted (double encryption scenario)
            if (firstLayerDecrypted.length > 100 &&
                firstLayerDecrypted.contains('eyJ')) {
              Logger.info(
                  '📱 ChatListProvider:  Detected double encryption, decrypting inner layer...');
              Logger.debug(
                  '📱 ChatListProvider: 🔍 First layer preview: ${firstLayerDecrypted.substring(0, firstLayerDecrypted.length > 100 ? 100 : firstLayerDecrypted.length)}...');

              try {
                // Decrypt the inner encrypted content
                final innerDecryptedData =
                    await EncryptionService.decryptAesCbcPkcs7(
                        firstLayerDecrypted);

                if (innerDecryptedData != null &&
                    innerDecryptedData.containsKey('text')) {
                  final finalDecryptedText =
                      innerDecryptedData['text'] as String;
                  Logger.success(
                      '📱 ChatListProvider:  Inner layer decrypted successfully');
                  Logger.info(
                      '📱 ChatListProvider:  Final decrypted text: $finalDecryptedText');
                  decryptedMessagePreview = finalDecryptedText;
                } else {
                  Logger.warning(
                      '📱 ChatListProvider:  Inner layer decryption failed, using first layer');
                  decryptedMessagePreview = firstLayerDecrypted;
                }
              } catch (e) {
                Logger.error(
                    '📱 ChatListProvider:  Inner layer decryption error: $e, using first layer');
                decryptedMessagePreview = firstLayerDecrypted;
              }
            } else {
              // Single layer encryption, use as is
              Logger.success(
                  '📱 ChatListProvider:  Single layer decryption completed');
              decryptedMessagePreview = firstLayerDecrypted;
            }
          } else {
            Logger.warning(
                '📱 ChatListProvider:  Decryption failed - invalid format, using encrypted preview');
            decryptedMessagePreview = '[Encrypted Message]';
          }
        } catch (e) {
          Logger.error(
              '📱 ChatListProvider:  Decryption failed for preview: $e');
          decryptedMessagePreview = '[Encrypted Message]';
        }
      } else {
        Logger.info(
            '📱 ChatListProvider:  Message appears to be plain text, using as-is');
      }

      // Create or update conversation
      final currentUserId = _getCurrentUserId();
      if (currentUserId == 'unknown_user') {
        Logger.error('📱 ChatListProvider:  No current user session found');
        return;
      }

      // CRITICAL: Only find conversation by consistent ID
      ChatConversation? existingConversation;

      try {
        existingConversation = _conversations.firstWhere(
          (conv) => conv.id == conversationId,
        );
        Logger.success(
            '📱 ChatListProvider:  Found conversation by consistent ID: $conversationId');
      } catch (e) {
        existingConversation = null;
        Logger.warning(
            '📱 ChatListProvider:  No existing conversation found for ID: $conversationId');
      }

      if (existingConversation != null) {
        // Update existing conversation with DECRYPTED preview
        final updatedConversation = existingConversation.copyWith(
          lastMessageAt: DateTime.now(),
          lastMessageId: messageId ??
              'msg_${DateTime.now().millisecondsSinceEpoch}', // Use provided messageId or generate one
          lastMessagePreview: decryptedMessagePreview, // Use decrypted content
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

        Logger.success(
            '📱 ChatListProvider:  Updated existing conversation with decrypted preview');
      } else {
        // Create new conversation with DECRYPTED preview
        final newConversation = ChatConversation(
          id: conversationId,
          participant1Id: currentUserId,
          participant2Id: senderId,
          displayName: senderName,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          lastMessageAt: DateTime.now(),
          lastMessageId: messageId ?? conversationId,
          lastMessagePreview: decryptedMessagePreview, // Use decrypted content
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

        Logger.success(
            '📱 ChatListProvider:  Created new conversation with decrypted preview');
      }

      // Sort conversations by last message time (newest first)
      _conversations.sort((a, b) {
        final aTime = a.lastMessageAt ?? a.createdAt;
        final bTime = b.lastMessageAt ?? b.createdAt;
        return bTime.compareTo(aTime);
      });

      // Apply search filter
      _applySearchFilter();

      // Notify listeners to update UI
      notifyListeners();

      Logger.success(
          '📱 ChatListProvider:  Chat list reordered - conversation moved to top');

      Logger.success(
          '📱 ChatListProvider:  Incoming message handled successfully with decryption');
    } catch (e) {
      Logger.error('📱 ChatListProvider:  Error handling incoming message: $e');
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
        Logger.info(
            '📱 ChatListProvider:  Conversation already exists: $conversationId');
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

      Logger.success(
          '📱 ChatListProvider:  Added new conversation: $conversationId');
    } catch (e) {
      Logger.error('📱 ChatListProvider:  Failed to add new conversation: $e');
    }
  }

  /// Generate consistent conversation ID that both users will have
  /// This ensures messages appear in the same conversation for both users
  /// Updated to match server's new consistent ID format
  String _generateConsistentConversationId(String user1Id, String user2Id) {
    return ConversationIdGenerator.generateConsistentConversationId(
        user1Id, user2Id);
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

        Logger.success(
            '📱 ChatListProvider:  Created conversation: $conversationId');
      } else {
        Logger.info(
            '📱 ChatListProvider:  Conversation already exists: $conversationId');
      }
    } catch (e) {
      Logger.error('📱 ChatListProvider:  Failed to ensure conversation: $e');
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

      Logger.success(
          '📱 ChatListProvider:  Updated conversation with outgoing message: $conversationId');
    } catch (e) {
      Logger.error(
          '📱 ChatListProvider:  Failed to handle outgoing message: $e');
    }
  }

  /// Refresh a specific conversation with latest data
  Future<void> refreshConversation(String conversationId) async {
    try {
      Logger.info(
          '📱 ChatListProvider:  Refreshing conversation: $conversationId');

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

        Logger.success(
            '📱 ChatListProvider:  Conversation refreshed: $conversationId');
      }
    } catch (e) {
      Logger.error('📱 ChatListProvider:  Error refreshing conversation: $e');
    }
  }

  /// Setup online status callback - REMOVED DUPLICATE
  void _setupOnlineStatusCallback() {
    try {
      // REMOVED: Direct callback to SeSocketService to avoid duplication
      // Online status updates now come through main.dart -> updateConversationOnlineStatus
      Logger.debug(
          '🔌 ChatListProvider: ℹ️ Online status updates handled via main.dart callback (no duplicate)');
      Logger.success(
          ' ChatListProvider:  Online status callback setup complete');
    } catch (e) {
      Logger.error(
          ' ChatListProvider:  Error setting up online status callback: $e');
    }
  }

  /// Handle online status update
  void _handleOnlineStatusUpdate(
      String senderId, bool isOnline, String? lastSeen) {
    try {
      Logger.debug(
          '📱 ChatListProvider:  Online status update: $senderId -> $isOnline');

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

        Logger.success(
            '📱 ChatListProvider:  Online status updated for conversation: ${conversation.id}');
      } else {
        Logger.warning(
            '📱 ChatListProvider:  No conversation found for sender: $senderId');
      }
    } catch (e) {
      Logger.error(
          '📱 ChatListProvider:  Error handling online status update: $e');
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
