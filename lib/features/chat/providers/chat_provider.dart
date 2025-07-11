import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/user.dart';
import '../../../shared/models/message.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/websocket_service.dart';
import '../../../core/services/encryption_service.dart';
import 'dart:async';

class ChatProvider extends ChangeNotifier {
  List<Chat> _chats = [];
  final Map<String, List<Message>> _messages = {};
  final Map<String, User> _chatUsers = {};
  bool _isLoading = false;
  String? _error;

  List<Chat> get chats => _chats;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<Message> getMessagesForChat(String chatId) {
    return _messages[chatId] ?? [];
  }

  User? getChatUser(String userId) {
    return _chatUsers[userId];
  }

  ChatProvider() {
    _setupWebSocket();
    _loadChatsFromLocal();
    _startOnlineStatusRefreshTimer();
  }

  void _setupWebSocket() {
    WebSocketService.instance.onMessageReceived = _handleWebSocketMessage;
    WebSocketService.instance.onChatMessageReceived =
        _handleChatMessageReceived;
    WebSocketService.instance.onTypingReceived = _handleTypingReceived;
    WebSocketService.instance.onReadReceiptReceived =
        _handleReadReceiptReceived;
    WebSocketService.instance.onConnected = _handleWebSocketConnected;
    WebSocketService.instance.onDisconnected = _handleWebSocketDisconnected;
    WebSocketService.instance.onError = _handleWebSocketError;
  }

  void _handleWebSocketMessage(Map<String, dynamic> data) {
    // General message handling
    if (data['type'] == 'user_online_status') {
      final userId = data['user_id'] as String;
      final isOnline = data['is_online'] as bool;
      final lastSeen =
          data['last_seen'] != null ? DateTime.parse(data['last_seen']) : null;

      _updateUserOnlineStatus(userId, isOnline, lastSeen);
    }
  }

  void _handleChatMessageReceived(Map<String, dynamic> data) {
    final messageData = data['message'] as Map<String, dynamic>;
    final encryptedContent = messageData['content'] as String;

    // Decrypt the message
    String decryptedContent;
    try {
      decryptedContent =
          EncryptionService.decryptMessage(encryptedContent) as String;
    } catch (e) {
      decryptedContent = '[Encrypted message]'; // Fallback if decryption fails
    }

    // Create message with decrypted content
    final newMessage = Message(
      id: messageData['id'].toString(),
      chatId: messageData['chat_id'].toString(),
      senderId: messageData['sender_id'].toString(),
      content: decryptedContent,
      type: MessageType.values.firstWhere(
        (e) => e.toString().split('.').last == messageData['type'],
        orElse: () => MessageType.text,
      ),
      status: messageData['status'] ?? 'sent',
      createdAt: DateTime.parse(messageData['created_at']),
      updatedAt: DateTime.parse(messageData['updated_at']),
    );

    final chatId = newMessage.chatId;

    // Add message to local storage
    if (!_messages.containsKey(chatId)) {
      _messages[chatId] = [];
    }
    _messages[chatId]!.add(newMessage);
    _saveMessagesToLocal(chatId, _messages[chatId]!);

    // Update chat's last message timestamp
    updateChatLastMessage(chatId, newMessage.createdAt);

    // Update message status to delivered
    _updateMessageStatus(chatId, newMessage.id, 'delivered');

    notifyListeners();
  }

  void _handleTypingReceived(Map<String, dynamic> data) {
    // Handle typing indicators
    // This can be used to show "typing..." indicator in UI
  }

  void _handleReadReceiptReceived(Map<String, dynamic> data) {
    final chatId = data['chat_id'] as String;
    final userId = data['user_id'] as String;

    // Update message status to read for messages sent by current user
    final messages = _messages[chatId];
    if (messages != null) {
      bool updated = false;
      for (int i = 0; i < messages.length; i++) {
        if (messages[i].senderId == userId && messages[i].status != 'read') {
          messages[i] = messages[i].copyWith(status: 'read');
          updated = true;
        }
      }
      if (updated) {
        _saveMessagesToLocal(chatId, messages);
        notifyListeners();
      }
    }
  }

  void _handleWebSocketConnected() {
    print('🔌 ChatProvider: WebSocket connected');
  }

  void _handleWebSocketDisconnected() {
    print('🔌 ChatProvider: WebSocket disconnected');
  }

  void _handleWebSocketError(String error) {
    print('🔌 ChatProvider: WebSocket error: $error');
    // Don't set this as a blocking error - WebSocket is optional
    // _error = 'WebSocket error: $error';
    // notifyListeners();
  }

  void _updateMessageStatus(String chatId, String messageId, String status) {
    final messages = _messages[chatId];
    if (messages != null) {
      for (int i = 0; i < messages.length; i++) {
        if (messages[i].id == messageId) {
          messages[i] = messages[i].copyWith(status: status);
          _saveMessagesToLocal(chatId, messages);
          break;
        }
      }
    }
  }

  Future<void> _loadChatsFromLocal() async {
    final box = Hive.box('chats');
    final localChats = box.values
        .map((e) => Chat.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _chats = localChats;
    notifyListeners();
  }

  Future<void> _saveChatsToLocal(List<Chat> chats) async {
    final box = Hive.box('chats');
    await box.clear();
    for (var chat in chats) {
      await box.put(chat.id, chat.toJson());
    }
  }

  Future<void> loadChats() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Load from local storage first for instant UI
    await _loadChatsFromLocal();

    try {
      print('📱 ChatProvider: Loading chats from API...');
      final response = await ApiService.getChats();
      print('📱 ChatProvider: API response: $response');

      if (response['success'] == true) {
        final chatsData = response['chats'] as List;
        _chats = chatsData.map((chatData) => Chat.fromJson(chatData)).toList();

        // Extract and store user information from chat data
        for (int i = 0; i < chatsData.length; i++) {
          final chatData = chatsData[i] as Map<String, dynamic>;
          final chat = _chats[i];

          print('📱 ChatProvider: Processing chat ${chat.id}');
          print('📱 ChatProvider: Chat data keys: ${chatData.keys.toList()}');

          bool userStored = false;

          // Check for other_user field
          if (chatData.containsKey('other_user') &&
              chatData['other_user'] != null) {
            final otherUserData =
                chatData['other_user'] as Map<String, dynamic>;
            final otherUser = User.fromJson(otherUserData);
            // Set default online status to true until WebSocket provides real data
            final onlineUser = otherUser.copyWith(isOnline: true);
            _chatUsers[onlineUser.id] = onlineUser;
            userStored = true;
            print(
                '📱 ChatProvider: Stored user ${onlineUser.username} with ID ${onlineUser.id} (online: true)');
          }

          // Also check for participants field (alternative structure)
          if (chatData.containsKey('participants') &&
              chatData['participants'] != null) {
            final participants = chatData['participants'] as List;
            for (final participantData in participants) {
              final participant =
                  User.fromJson(participantData as Map<String, dynamic>);
              // Set default online status to true until WebSocket provides real data
              final onlineParticipant = participant.copyWith(isOnline: true);
              _chatUsers[onlineParticipant.id] = onlineParticipant;
              userStored = true;
              print(
                  '📱 ChatProvider: Stored participant ${onlineParticipant.username} with ID ${onlineParticipant.id} (online: true)');
            }
          }

          // If no user data found, create a temporary user for now
          if (!userStored) {
            final otherUserId = chat.getOtherUserId('current_user_placeholder');
            if (otherUserId.isNotEmpty &&
                otherUserId != 'current_user_placeholder') {
              final tempUser = User(
                id: otherUserId,
                deviceId: 'unknown',
                username: 'Chat User ${otherUserId.substring(0, 8)}',
                isOnline: true,
                createdAt: DateTime.now(),
              );
              _chatUsers[tempUser.id] = tempUser;
              print(
                  '📱 ChatProvider: Created temporary user ${tempUser.username} for ID ${tempUser.id}');
            }
          }
        }

        print('📱 ChatProvider: Total users stored: ${_chatUsers.length}');
        print('📱 ChatProvider: User IDs: ${_chatUsers.keys.toList()}');
        print('📱 ChatProvider: Loaded ${_chats.length} chats');
        await _saveChatsToLocal(_chats);
      } else {
        throw Exception(response['message'] ?? 'Failed to load chats');
      }
    } catch (e) {
      print('📱 ChatProvider: Error loading chats: $e');
      _error = 'Failed to load chats: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadMessagesFromLocal(String chatId) async {
    final box = Hive.box('messages');
    final localMessages = box.get(chatId);
    if (localMessages != null) {
      _messages[chatId] = (localMessages as List)
          .map((e) => Message.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      notifyListeners();
    }
  }

  Future<void> _saveMessagesToLocal(
    String chatId,
    List<Message> messages,
  ) async {
    final box = Hive.box('messages');
    await box.put(chatId, messages.map((m) => m.toJson()).toList());
  }

  Future<void> loadMessages(String chatId) async {
    // Load from local storage first
    await _loadMessagesFromLocal(chatId);

    try {
      final response = await ApiService.getMessages(chatId);
      if (response['success'] == true) {
        final messagesData = response['messages'] as List;
        _messages[chatId] = messagesData
            .map((messageData) => Message.fromJson(messageData))
            .toList();
        await _saveMessagesToLocal(chatId, _messages[chatId]!);
        notifyListeners();
      } else {
        throw Exception(response['message'] ?? 'Failed to load messages');
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> markMessagesAsRead(String chatId) async {
    try {
      await ApiService.markMessagesAsRead(chatId);

      // Update local messages status
      final messages = _messages[chatId];
      if (messages != null) {
        for (int i = 0; i < messages.length; i++) {
          if (messages[i].status != 'read') {
            messages[i] = messages[i].copyWith(status: 'read');
          }
        }
        await _saveMessagesToLocal(chatId, messages);
        notifyListeners();
      }
    } catch (e) {
      // Silently fail for read status updates
      print('Failed to mark messages as read: $e');
    }
  }

  Future<void> sendMessage(String chatId, String content) async {
    try {
      // Try WebSocket first for real-time messaging
      if (WebSocketService.instance.isAuthenticated) {
        // Get recipient's public key for encryption
        final recipientUser = _chatUsers[_getOtherUserId(chatId)];
        if (recipientUser == null) {
          throw Exception('Recipient not found');
        }

        // Encrypt the message
        final encryptedContent = EncryptionService.encryptMessage(
          content,
          recipientUser.publicKey ?? '', // This should be stored in user model
        );

        WebSocketService.instance.sendChatMessage(
          chatId: chatId,
          content: encryptedContent, // Send encrypted content
        );

        // Create temporary message for immediate UI feedback
        final tempMessage = Message(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          chatId: chatId,
          senderId: 'current_user', // Will be replaced with actual user ID
          content: content, // Store decrypted content locally
          type: MessageType.text,
          status: 'sent',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Add to local messages immediately
        _messages[chatId] = [...(_messages[chatId] ?? []), tempMessage];
        await _saveMessagesToLocal(chatId, _messages[chatId]!);
        updateChatLastMessage(chatId, tempMessage.createdAt);
        notifyListeners();

        return;
      }

      // Fallback to API if WebSocket is not available
      final response = await ApiService.sendMessage(chatId, {
        'content': content,
        'type': 'text',
      });

      if (response['success'] == true) {
        final messageData = response['message'] as Map<String, dynamic>;
        final newMessage = Message.fromJson(messageData);

        // Add to local messages
        _messages[chatId] = [...(_messages[chatId] ?? []), newMessage];
        await _saveMessagesToLocal(chatId, _messages[chatId]!);

        // Update chat's last message timestamp
        updateChatLastMessage(chatId, newMessage.createdAt);

        notifyListeners();
      } else {
        throw Exception(response['message'] ?? 'Failed to send message');
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  String _getOtherUserId(String chatId) {
    final chat = _chats.firstWhere((c) => c.id == chatId);
    return chat.getOtherUserId(
      'current_user_id',
    ); // TODO: Get from auth provider
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void addChat(Chat chat) {
    _chats.add(chat);
    notifyListeners();
  }

  void addChatUser(User user) {
    _chatUsers[user.id] = user;
    notifyListeners();
  }

  void updateChatLastMessage(String chatId, DateTime timestamp) {
    final index = _chats.indexWhere((c) => c.id == chatId);
    if (index != -1) {
      _chats[index] = _chats[index].copyWith(lastMessageAt: timestamp);
      notifyListeners();
    }
  }

  void _updateUserOnlineStatus(
      String userId, bool isOnline, DateTime? lastSeen) {
    if (_chatUsers.containsKey(userId)) {
      _chatUsers[userId] = _chatUsers[userId]!.copyWith(
        isOnline: isOnline,
        lastSeen: lastSeen,
      );
      print(
          '📱 ChatProvider: Updated online status for user $userId - Online: $isOnline');
      notifyListeners();
    }
  }

  void updateUserOnlineStatus(String userId, bool isOnline) {
    _updateUserOnlineStatus(userId, isOnline, isOnline ? null : DateTime.now());
  }

  Future<void> refreshOnlineStatus() async {
    try {
      // TODO: Implement getUsersOnlineStatus API endpoint
      // final response = await ApiService.getUsersOnlineStatus();
      // For now, we'll just mark all users as online if they have recent activity
      // This can be improved when the backend API is ready

      print(
          '📱 ChatProvider: Online status refresh - using WebSocket data only');
      // Online status will be updated via WebSocket events
    } catch (e) {
      print('📱 ChatProvider: Error refreshing online status: $e');
      // Don't throw error - online status is not critical
    }
  }

  void _startOnlineStatusRefreshTimer() {
    _refreshOnlineStatusTimer = Timer.periodic(
      const Duration(minutes: 2),
      (timer) async {
        await refreshOnlineStatus();
      },
    );
  }

  void _disposeOnlineStatusTimer() {
    _refreshOnlineStatusTimer?.cancel();
  }

  Timer? _refreshOnlineStatusTimer;

  @override
  void dispose() {
    _disposeOnlineStatusTimer();
    super.dispose();
  }
}
