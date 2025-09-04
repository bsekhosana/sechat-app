import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import '../../../core/services/se_session_service.dart';
import '../../../core/services/contact_service.dart';
import '../../../core/services/encryption_service.dart';
import '../services/message_storage_service.dart';

import '../../../shared/models/user.dart';
import '../models/message.dart';
import '../../../realtime/realtime_service_manager.dart';
import '../../../realtime/typing_service.dart';
import '../../../core/services/unified_message_service.dart' as unified_msg;
import '../services/message_status_tracking_service.dart';
import '../models/message_status.dart' as msg_status;
import '../services/unified_chat_integration_service.dart';
import 'chat_list_provider.dart';
import '../../../core/utils/conversation_id_generator.dart';
import 'dart:async';

/// Modern, unified chat provider with improved state management and performance
class UnifiedChatProvider extends ChangeNotifier {
  final SeSocketService _socketService = SeSocketService.instance;
  final unified_msg.UnifiedMessageService _messageService =
      unified_msg.UnifiedMessageService.instance;
  final MessageStorageService _messageStorage = MessageStorageService.instance;

  // Realtime services
  TypingService? _typingService;
  final UnifiedChatIntegrationService _integrationService =
      UnifiedChatIntegrationService();
  
  // Stream subscriptions for proper cleanup
  StreamSubscription? _typingStreamSubscription;
  StreamSubscription? _connectionStateSubscription;

  // Core state
  final List<Message> _messages = [];
  bool _isLoading = false;
  String? _error;
  bool _isConnected = true;

  // Chat conversation state
  String? _currentConversationId;
  String? _currentRecipientId;
  String? _currentRecipientName;
  bool _isRecipientTyping = false;
  DateTime? _recipientLastSeen;
  bool _isRecipientOnline = false;

  // User state tracking
  bool _isUserOnChatScreen = false;
  bool _isMuted = false;
  
  // Initialization state
  bool _isInitialized = false;
  String? _lastInitializedConversationId;
  bool _socketCallbacksSetup = false;
  
  // Debounce mechanism
  Timer? _refreshDebounceTimer;
  Timer? _notifyDebounceTimer;

  // Performance optimization
  final int _initialLoadLimit = 50;
  final int _lazyLoadLimit = 20;
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;

  // Getters
  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isConnected => _isConnected;
  bool get isRecipientTyping => _isRecipientTyping;
  DateTime? get recipientLastSeen => _recipientLastSeen;
  bool get isRecipientOnline => _isRecipientOnline;
  String? get currentRecipientName => _currentRecipientName;
  String? get currentRecipientId => _currentRecipientId;
  bool get isMuted => _isMuted;
  bool get isUserOnChatScreen => _isUserOnChatScreen;
  bool get hasMoreMessages => _hasMoreMessages;
  bool get isLoadingMore => _isLoadingMore;

  /// Get the current conversation ID
  String? get conversationId {
    if (_currentConversationId == null && _currentRecipientId != null) {
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId != null) {
        _currentConversationId = _generateConsistentConversationId(
            currentUserId, _currentRecipientId!);
      }
    }
    return _currentConversationId;
  }

  /// Get current user ID
  String? get currentUserId => SeSessionService().currentSessionId;

  /// Debounced notification to prevent excessive rebuilds
  void _notifyListenersDebounced() {
    _notifyDebounceTimer?.cancel();
    _notifyDebounceTimer = Timer(const Duration(milliseconds: 16), () {
      notifyListeners();
    });
  }

  /// Generate consistent conversation ID - API Compliant
  /// According to API docs: conversationId should be sender's sessionId for bidirectional conversations
  String _generateConsistentConversationId(String user1Id, String user2Id) {
    // Use the standard conversation ID generator for consistent format
    return ConversationIdGenerator.generateConsistentConversationId(
        user1Id, user2Id);
  }

  /// Initialize the chat provider for a specific conversation
  Future<void> initialize({
    required String conversationId,
    required String recipientId,
    required String recipientName,
  }) async {
    try {
      // Generate consistent conversation ID first
      final currentUserId = SeSessionService().currentSessionId;
      String? generatedConversationId;
      if (currentUserId != null) {
        generatedConversationId =
            _generateConsistentConversationId(currentUserId, recipientId);
      } else {
        generatedConversationId = conversationId;
      }

      // Check if already initialized for the same conversation
      if (_isInitialized && 
          _lastInitializedConversationId == generatedConversationId &&
          _currentRecipientId == recipientId) {
        print('UnifiedChatProvider: ⚠️ Already initialized for conversation: $generatedConversationId, skipping...');
        return;
      }

      _isLoading = true;
      _error = null;
      notifyListeners();

      // Set recipient info
      _currentRecipientId = recipientId;
      _currentRecipientName = recipientName;
      _currentConversationId = generatedConversationId;

      // Load initial messages
      await _loadInitialMessages();

      // Load recipient user data
      await _loadRecipientUserData(recipientId);

      // Setup realtime services (only once)
      _setupTypingService();
      _setupMessageServiceListener();
      if (!_socketCallbacksSetup) {
        _setupSocketCallbacks();
        _setupConnectionMonitoring();
        _socketCallbacksSetup = true;
      }

      // Register with integration service
      if (_currentConversationId != null) {
        _integrationService.registerActiveProvider(
            _currentConversationId!, this);
      }

      _isLoading = false;
      _isInitialized = true;
      _lastInitializedConversationId = _currentConversationId;
      notifyListeners();

      print(
          'UnifiedChatProvider: ✅ Initialized for conversation: $_currentConversationId');
    } catch (e) {
      _error = 'Failed to initialize chat: $e';
      _isLoading = false;
      _isInitialized = false;
      _lastInitializedConversationId = null;
      notifyListeners();
      print('UnifiedChatProvider: ❌ Failed to initialize: $e');
    }
  }

  /// Load initial messages for the conversation
  Future<void> _loadInitialMessages() async {
    try {
      if (_currentConversationId == null) return;

      print('UnifiedChatProvider: 🔄 Loading initial messages...');

      final loadedMessages = await _messageStorage.getMessages(
        _currentConversationId!,
        limit: _initialLoadLimit,
      );

      // Clear existing messages and add new ones
      _messages.clear();
      _messages.addAll(loadedMessages);

      // Sort messages by timestamp (oldest first for natural chat flow)
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Check if there are more messages to load
      _hasMoreMessages = loadedMessages.length >= _initialLoadLimit;

      print(
          'UnifiedChatProvider: ✅ Loaded ${loadedMessages.length} initial messages');
    } catch (e) {
      print('UnifiedChatProvider: ❌ Error loading initial messages: $e');
    }
  }

  /// Load more messages (lazy loading)
  Future<void> loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages || _messages.isEmpty) return;

    try {
      _isLoadingMore = true;
      notifyListeners();

      // For now, use regular getMessages with offset for lazy loading
      // This will be enhanced when getMessagesBefore is implemented
      final loadedMessages = await _messageStorage.getMessages(
        _currentConversationId!,
        limit: _lazyLoadLimit,
      );

      if (loadedMessages.isNotEmpty) {
        // Insert older messages at the beginning
        _messages.insertAll(0, loadedMessages);

        // Check if there are more messages
        _hasMoreMessages = loadedMessages.length >= _lazyLoadLimit;

        print(
            'UnifiedChatProvider: ✅ Loaded ${loadedMessages.length} more messages');
      } else {
        _hasMoreMessages = false;
      }

      _isLoadingMore = false;
      notifyListeners();
    } catch (e) {
      _isLoadingMore = false;
      notifyListeners();
      print('UnifiedChatProvider: ❌ Error loading more messages: $e');
    }
  }

  /// Load recipient user data
  Future<void> _loadRecipientUserData(String recipientId) async {
    try {
      // Check if we already have user data
      if (_chatUsers.containsKey(recipientId)) {
        final user = _chatUsers[recipientId]!;
        _isRecipientOnline = user.isOnline;
        _recipientLastSeen = user.lastSeen;
      } else {
        // Create default user data
        _isRecipientOnline = false;
        _recipientLastSeen = DateTime.now().subtract(const Duration(hours: 1));
      }

      // Try to get latest status from ContactService
      try {
        final contactService = ContactService.instance;
        final contact = contactService.getContact(recipientId);
        if (contact != null) {
          _isRecipientOnline = contact.isOnline;
          _recipientLastSeen = contact.lastSeen;
        }
      } catch (e) {
        print('UnifiedChatProvider: ⚠️ ContactService not available: $e');
      }

      print('UnifiedChatProvider: ✅ Loaded recipient data for: $recipientId');
    } catch (e) {
      print('UnifiedChatProvider: ❌ Error loading recipient data: $e');
    }
  }

  /// Setup typing service
  void _setupTypingService() {
    try {
      if (_typingService != null && _typingStreamSubscription != null) return;

      print('UnifiedChatProvider: 🔧 Setting up typing service...');
      _typingService = RealtimeServiceManager().typing;

      // Cancel existing subscription if any
      _typingStreamSubscription?.cancel();

      // Listen for typing updates
      _typingStreamSubscription = _typingService!.typingStream.listen((update) {
        if (update.conversationId == _currentConversationId) {
          if (update.source == 'peer' || update.source == 'server') {
            _isRecipientTyping = update.isTyping;
            _notifyListenersDebounced();
          }
        }
      });

      print('UnifiedChatProvider: ✅ Typing service setup complete');
    } catch (e) {
      print('UnifiedChatProvider: ❌ Failed to setup typing service: $e');
    }
  }

  /// Setup message service listener
  void _setupMessageServiceListener() {
    // Remove existing listener first to prevent duplicates
    _messageService.removeListener(_onMessageServiceUpdate);
    _messageService.addListener(_onMessageServiceUpdate);
    print('UnifiedChatProvider: ✅ Message service listener setup');
  }

  /// Handle message service updates
  void _onMessageServiceUpdate() {
    if (_currentConversationId != null) {
      // Only refresh if we don't have many messages loaded yet
      // This prevents interference with real-time socket messages
      if (_messages.length < 5) {
        // Debounce the refresh to prevent continuous rebuilding
        _refreshDebounceTimer?.cancel();
        _refreshDebounceTimer = Timer(const Duration(milliseconds: 500), () {
          _refreshMessagesFromDatabase();
        });
      }
    }
  }

  /// Refresh messages from database
  Future<void> _refreshMessagesFromDatabase() async {
    try {
      if (_currentConversationId == null) return;

      final loadedMessages = await _messageStorage.getMessages(
        _currentConversationId!,
        limit: _initialLoadLimit,
      );

      // Check for new messages
      final currentMessageIds = _messages.map((m) => m.id).toSet();
      final newMessages = loadedMessages
          .where((m) => !currentMessageIds.contains(m.id))
          .toList();

      if (newMessages.isNotEmpty) {
        _messages.addAll(newMessages);
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        notifyListeners();
        print(
            'UnifiedChatProvider: ✅ Added ${newMessages.length} new messages');
      }
    } catch (e) {
      print('UnifiedChatProvider: ❌ Error refreshing messages: $e');
    }
  }

  /// Setup socket callbacks
  void _setupSocketCallbacks() {
    try {
      print('UnifiedChatProvider: 🔧 Setting up socket callbacks...');

      // Message acknowledgment callback
      _socketService.setOnMessageAcked((messageId) {
        print('UnifiedChatProvider: ✅ Message acknowledged: $messageId');
        _updateMessageStatus(messageId, MessageStatus.sent);
      });

      // Message received callback
      _socketService.setOnMessageReceived(
          (senderId, senderName, message, conversationId, messageId) {
        print(
            'UnifiedChatProvider: 📨 Message received: $messageId from $senderId');
        _handleIncomingMessage(messageId, senderId, conversationId, message);
      });

      // Presence update callback
      _socketService.setOnOnlineStatusUpdate((userId, isOnline, lastSeen) {
        if (userId == _currentRecipientId) {
          final lastSeenDateTime =
              lastSeen != null ? DateTime.parse(lastSeen) : null;
          updateRecipientPresence(isOnline, lastSeenDateTime);
        }
      });

      // Typing indicator callback
      _socketService.setOnTypingIndicator((senderId, isTyping) {
        if (senderId == _currentRecipientId) {
          _isRecipientTyping = isTyping;
          _notifyListenersDebounced();
          print('UnifiedChatProvider: ⌨️ Typing indicator: $isTyping');
        }
      });

      print('UnifiedChatProvider: ✅ Socket callbacks setup complete');
    } catch (e) {
      print('UnifiedChatProvider: ❌ Failed to setup socket callbacks: $e');
    }
  }

  /// Setup connection monitoring
  void _setupConnectionMonitoring() {
    // Cancel existing subscription if any
    _connectionStateSubscription?.cancel();
    
    // Monitor socket connection status
    _connectionStateSubscription = _socketService.connectionStateStream.listen((isConnected) {
      if (_isConnected != isConnected) {
        _isConnected = isConnected;
        notifyListeners();
        print(
            'UnifiedChatProvider: 🔌 Connection status changed: $isConnected');
      }
    });
  }

  /// Send text message - Compliant with SeChat Socket.IO API
  Future<void> sendTextMessage(String content) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      if (content.trim().isEmpty) {
        throw Exception('Message content cannot be empty');
      }

      final recipientId = _currentRecipientId!;
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) {
        throw Exception('No active session found');
      }

      // Generate message ID according to API standards
      final messageId =
          'msg_${DateTime.now().millisecondsSinceEpoch}_$currentUserId';

      // Create message object with proper conversation ID handling
      // According to API docs: conversationId should be sender's sessionId for bidirectional conversations
      final message = Message(
        id: messageId,
        conversationId:
            currentUserId, // Use sender's sessionId as conversationId per API
        senderId: currentUserId,
        recipientId: recipientId,
        type: MessageType.text,
        content: {'text': content},
        status: MessageStatus.sending,
        timestamp: DateTime.now(),
        metadata: {
          'isFromCurrentUser': true,
          'messageDirection': 'outgoing',
          'sentAt': DateTime.now().toIso8601String(),
          'recipientId': recipientId,
          'apiCompliant': true, // Mark as API compliant
        },
      );

      // Add message to local list for immediate UI feedback
      _messages.add(message);
      notifyListeners();

      // Send message via unified message service (handles encryption and socket per API)
      final sendResult = await _messageService.sendMessage(
        messageId: messageId,
        recipientId: recipientId,
        body: content,
        conversationId: _currentConversationId, // Use proper conversation ID
      );

      if (sendResult.success) {
        // Update message status to sent
        final messageIndex = _messages.indexWhere((msg) => msg.id == messageId);
        if (messageIndex != -1) {
          _messages[messageIndex] = _messages[messageIndex].copyWith(
            status: MessageStatus.sent,
          );
          notifyListeners();
        }

        print('UnifiedChatProvider: ✅ Message sent successfully');
      } else {
        throw Exception('Message send failed: ${sendResult.error}');
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to send message: $e';
      _isLoading = false;
      notifyListeners();
      print('UnifiedChatProvider: ❌ Failed to send message: $e');
      rethrow;
    }
  }

  /// Update typing indicator
  void updateTypingIndicator(bool isTyping) async {
    try {
      if (_currentRecipientId == null || _typingService == null) return;

      if (isTyping) {
        _typingService!
            .startTyping(_currentConversationId!, [_currentRecipientId!]);
      } else {
        _typingService!.stopTyping(_currentConversationId!);
      }

      print('UnifiedChatProvider: ✅ Typing indicator sent: $isTyping');
    } catch (e) {
      print('UnifiedChatProvider: ❌ Error updating typing indicator: $e');
    }
  }

  /// Update recipient presence
  void updateRecipientPresence(bool isOnline, DateTime? lastSeen) {
    _isRecipientOnline = isOnline;
    _recipientLastSeen = lastSeen;
    notifyListeners();
    print(
        'UnifiedChatProvider: ✅ Recipient presence updated: online=$isOnline');
  }

  /// Mark conversation as read
  Future<void> markAsRead() async {
    try {
      if (_currentRecipientId == null) return;

      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId != null) {
        // Mark messages as read in database
        await _messageStorage.markConversationMessagesAsRead(
          _currentConversationId ?? _currentRecipientId!,
          currentUserId,
        );

        // Send read receipts for unread messages from the recipient
        for (final message in _messages) {
          if (message.senderId != currentUserId &&
              message.recipientId == currentUserId &&
              message.status != MessageStatus.read) {
            await _sendReadReceipt(message.id, message.senderId);
          }
        }
      }

      print('UnifiedChatProvider: ✅ Conversation marked as read');
    } catch (e) {
      print('UnifiedChatProvider: ❌ Error marking conversation as read: $e');
    }
  }

  /// Refresh messages
  Future<void> refreshMessages() async {
    try {
      await _loadInitialMessages();
      notifyListeners();
      print('UnifiedChatProvider: ✅ Messages refreshed');
    } catch (e) {
      print('UnifiedChatProvider: ❌ Error refreshing messages: $e');
    }
  }

  /// Toggle mute notifications
  Future<void> toggleMuteNotifications() async {
    _isMuted = !_isMuted;
    notifyListeners();
    print('UnifiedChatProvider: ✅ Mute notifications toggled: $_isMuted');
  }

  /// Mark user entered chat screen
  void markUserEnteredChatScreen() {
    _isUserOnChatScreen = true;
    print('UnifiedChatProvider: ✅ User entered chat screen');
  }

  /// Mark user left chat screen
  void markUserLeftChatScreen() {
    _isUserOnChatScreen = false;
    print('UnifiedChatProvider: ❌ User left chat screen');
  }

  /// Reset initialization state (for testing or manual reset)
  void resetInitializationState() {
    _isInitialized = false;
    _lastInitializedConversationId = null;
    print('UnifiedChatProvider: 🔄 Initialization state reset');
  }

  /// Register with chat list provider
  void registerWithChatListProvider(ChatListProvider chatListProvider) {
    _integrationService.setChatListProvider(chatListProvider);
    print(
        'UnifiedChatProvider: ✅ Registered with ChatListProvider via integration service');
  }

  /// Unregister from chat list provider
  void unregisterFromChatListProvider(ChatListProvider chatListProvider) {
    _integrationService.setChatListProvider(null);
    print(
        'UnifiedChatProvider: ❌ Unregistered from ChatListProvider via integration service');
  }

  /// Handle incoming message from socket - API Compliant
  Future<void> _handleIncomingMessage(String messageId, String senderId,
      String conversationId, String body) async {
    try {
      final currentUserId = SeSessionService().currentSessionId;
      if (currentUserId == null) return;

      // Check if this message is for the current user
      // The message is for us if the sender is the current recipient
      if (senderId == _currentRecipientId) {
        // CRITICAL: Decrypt the incoming message before displaying
        String decryptedText = body;

        // Check if this looks like encrypted content
        if (body.length > 100 && body.contains('eyJ')) {
          print(
              'UnifiedChatProvider: 🔓 Detected encrypted message, attempting decryption...');
          try {
            // Use EncryptionService to decrypt the message (first layer)
            final decryptedData =
                await EncryptionService.decryptAesCbcPkcs7(body);

            if (decryptedData != null && decryptedData.containsKey('text')) {
              final firstLayerDecrypted = decryptedData['text'] as String;
              print(
                  'UnifiedChatProvider: ✅ First layer decrypted: $firstLayerDecrypted');

              // Check if the decrypted text is still encrypted (double encryption scenario)
              if (firstLayerDecrypted.length > 100 &&
                  firstLayerDecrypted.contains('eyJ')) {
                print(
                    'UnifiedChatProvider: 🔍 Detected double encryption, decrypting inner layer...');
                try {
                  // Decrypt the inner encrypted content
                  final innerDecryptedData =
                      await EncryptionService.decryptAesCbcPkcs7(
                          firstLayerDecrypted);

                  if (innerDecryptedData != null &&
                      innerDecryptedData.containsKey('text')) {
                    final finalDecryptedText =
                        innerDecryptedData['text'] as String;
                    print(
                        'UnifiedChatProvider: ✅ Inner layer decrypted successfully');
                    decryptedText = finalDecryptedText;
                  } else {
                    print(
                        'UnifiedChatProvider: ⚠️ Inner layer decryption failed, using first layer');
                    decryptedText = firstLayerDecrypted;
                  }
                } catch (e) {
                  print(
                      'UnifiedChatProvider: ❌ Inner layer decryption error: $e, using first layer');
                  decryptedText = firstLayerDecrypted;
                }
              } else {
                // Single layer encryption, use as is
                print(
                    'UnifiedChatProvider: ✅ Single layer decryption completed');
                decryptedText = firstLayerDecrypted;
              }
            } else {
              print(
                  'UnifiedChatProvider: ⚠️ Decryption failed - invalid format, using encrypted text');
              decryptedText = '[Encrypted Message]';
            }
          } catch (e) {
            print('UnifiedChatProvider: ❌ Decryption failed: $e');
            decryptedText = '[Encrypted Message]';
          }
        } else {
          print(
              'UnifiedChatProvider: ℹ️ Message appears to be plain text, using as-is');
        }

        // Create message object with proper API compliance and decrypted content
        final message = Message(
          id: messageId,
          conversationId: conversationId, // This is sender's sessionId per API
          senderId: senderId,
          recipientId: currentUserId,
          type: MessageType.text,
          content: {'text': decryptedText},
          status: MessageStatus.delivered,
          timestamp: DateTime.now(),
          metadata: {
            'isFromCurrentUser': false,
            'messageDirection': 'incoming',
            'receivedAt': DateTime.now().toIso8601String(),
            'apiCompliant': true, // Mark as API compliant
            'isEncrypted': body.length > 100 &&
                body.contains('eyJ'), // Mark if original was encrypted
          },
        );

        // Add message to local list
        _messages.add(message);
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        // Save to database
        await _messageStorage.saveMessage(message);

        // Send read receipt if user is on chat screen (per API)
        if (_isUserOnChatScreen) {
          _sendReadReceipt(messageId, senderId);
        }

        notifyListeners();
        print(
            'UnifiedChatProvider: ✅ Incoming message added (API compliant): $messageId');
      }
    } catch (e) {
      print('UnifiedChatProvider: ❌ Error handling incoming message: $e');
    }
  }

  /// Update message status
  void _updateMessageStatus(String messageId, MessageStatus status) {
    try {
      final messageIndex = _messages.indexWhere((msg) => msg.id == messageId);
      if (messageIndex != -1) {
        _messages[messageIndex] =
            _messages[messageIndex].copyWith(status: status);
        notifyListeners();
        print(
            'UnifiedChatProvider: ✅ Message status updated: $messageId -> $status');
      }
    } catch (e) {
      print('UnifiedChatProvider: ❌ Error updating message status: $e');
    }
  }

  /// Send read receipt
  Future<void> _sendReadReceipt(String messageId, String senderId) async {
    try {
      if (_isRecipientOnline) {
        await _socketService.sendReadReceipt(senderId, messageId);
        print('UnifiedChatProvider: ✅ Read receipt sent: $messageId');
      }
    } catch (e) {
      print('UnifiedChatProvider: ❌ Error sending read receipt: $e');
    }
  }

  /// Handle message status updates
  Future<void> handleMessageStatusUpdate(MessageStatusUpdate update) async {
    try {
      final messageIndex =
          _messages.indexWhere((msg) => msg.id == update.messageId);

      if (messageIndex != -1) {
        final newStatus = _convertDeliveryStatusToMessageStatus(update.status);
        _messages[messageIndex] =
            _messages[messageIndex].copyWith(status: newStatus);

        // Update in database
        await _messageStorage.updateMessageStatus(update.messageId, newStatus);

        notifyListeners();
        print(
            'UnifiedChatProvider: ✅ Message status updated: ${update.messageId} -> $newStatus');
      }
    } catch (e) {
      print('UnifiedChatProvider: ❌ Error handling message status update: $e');
    }
  }

  /// Convert delivery status to message status
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
        return MessageStatus.sending;
    }
  }

  @override
  void dispose() {
    _messageService.removeListener(_onMessageServiceUpdate);

    // Cancel all timers
    _refreshDebounceTimer?.cancel();
    _notifyDebounceTimer?.cancel();

    // Cancel all stream subscriptions
    _typingStreamSubscription?.cancel();
    _connectionStateSubscription?.cancel();

    // Unregister from integration service
    if (_currentConversationId != null) {
      _integrationService.unregisterActiveProvider(_currentConversationId!);
    }

    // Reset initialization state
    _isInitialized = false;
    _lastInitializedConversationId = null;
    _socketCallbacksSetup = false;

    super.dispose();
  }

  // Helper maps for user data (simplified for now)
  final Map<String, User> _chatUsers = {};
}
