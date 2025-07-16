import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/user.dart';
import '../../../shared/models/message.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import 'dart:async';

class ChatProvider extends ChangeNotifier {
  List<Chat> _chats = [];
  final Map<String, List<Message>> _messages = {};
  final Map<String, User> _chatUsers = {};
  final Map<String, int> _unreadCounts = {}; // Track unread message counts
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

  int getUnreadCount(String chatId) {
    return _unreadCounts[chatId] ?? 0;
  }

  int get totalUnreadCount {
    return _unreadCounts.values.fold(0, (sum, count) => sum + count);
  }

  bool get hasUnreadMessages => totalUnreadCount > 0;

  ChatProvider() {
    _setupSocket();
    _loadChatsFromLocal();
    _startOnlineStatusRefreshTimer();
  }

  void _setupSocket() {
    SocketService.instance.onMessageReceived = _handleSocketMessage;
    SocketService.instance.onChatMessageReceived = _handleChatMessageReceived;
    SocketService.instance.onTypingReceived = _handleTypingReceived;
    SocketService.instance.onUserOnline = _handleUserOnline;
    SocketService.instance.onUserOffline = _handleUserOffline;
    SocketService.instance.onUserStatusUpdated = _handleUserStatusUpdated;
    SocketService.instance.onConnected = _handleSocketConnected;
    SocketService.instance.onDisconnected = _handleSocketDisconnected;
    SocketService.instance.onError = _handleSocketError;
    SocketService.instance.onInvitationResponse = _handleInvitationResponse;
    SocketService.instance.onMessageStatusUpdated = _handleMessageStatusUpdated;
  }

  void _handleSocketMessage(Map<String, dynamic> data) {
    // General message handling
    print('📱 ChatProvider: Socket message received: $data');
  }

  void _handleUserOnline(Map<String, dynamic> data) {
    final userId = data['userId'].toString();
    print('📱 ChatProvider: User $userId came online');
    _updateUserOnlineStatus(userId, true, null);
  }

  void _handleUserOffline(Map<String, dynamic> data) {
    final userId = data['userId'].toString();
    print('📱 ChatProvider: User $userId went offline');
    _updateUserOnlineStatus(userId, false, DateTime.now());
  }

  void _handleUserStatusUpdated(Map<String, dynamic> data) {
    final userId = data['userId'].toString();
    final status = data['status'] as String;
    // Update user status if needed
    print('📱 ChatProvider: User status updated: $userId - $status');
  }

  void _handleChatMessageReceived(Map<String, dynamic> data) {
    // Handle Socket.IO message format
    print('📱 ChatProvider: Received Socket.IO message: $data');

    try {
      // Extract message content - handle both 'message' and 'content' fields
      String content;
      if (data.containsKey('message')) {
        content = data['message'] as String;
      } else if (data.containsKey('content')) {
        content = data['content'] as String;
      } else {
        print('📱 ChatProvider: No message content found in data: $data');
        return;
      }

      // Extract sender information
      String senderId;
      if (data.containsKey('sender_id')) {
        senderId = data['sender_id'].toString();
      } else if (data.containsKey('sender') && data['sender'] is Map) {
        final sender = data['sender'] as Map<String, dynamic>;
        senderId = sender['id'].toString();
      } else {
        print('📱 ChatProvider: No sender information found in data: $data');
        return;
      }

      // Extract chat ID
      String chatId;
      if (data.containsKey('chat_id')) {
        chatId = data['chat_id'].toString();
      } else if (data.containsKey('receiver_id')) {
        chatId = data['receiver_id'].toString();
      } else {
        print('📱 ChatProvider: No chat ID found in data: $data');
        return;
      }

      // Create message
      final newMessage = Message(
        id: data['id'].toString(),
        chatId: chatId,
        senderId: senderId,
        content: content,
        type: MessageType.values.firstWhere(
          (e) => e.toString().split('.').last == (data['type'] ?? 'text'),
          orElse: () => MessageType.text,
        ),
        status: data['status'] ?? 'received',
        createdAt: DateTime.parse(data['created_at']),
        updatedAt: DateTime.parse(data['updated_at'] ?? data['created_at']),
      );

      // Store sender user information if available
      if (data.containsKey('sender') && data['sender'] is Map) {
        final senderData = data['sender'] as Map<String, dynamic>;
        try {
          final sender = User.fromJson(senderData);
          _chatUsers[sender.id] = sender;
          print('📱 ChatProvider: Stored sender user: ${sender.username}');
        } catch (e) {
          print('📱 ChatProvider: Error parsing sender data: $e');
        }
      }

      // Add message to local storage
      if (!_messages.containsKey(chatId)) {
        _messages[chatId] = [];
      }
      _messages[chatId]!.add(newMessage);
      _saveMessagesToLocal(chatId, _messages[chatId]!);

      // Update chat's last message timestamp
      updateChatLastMessage(chatId, newMessage.createdAt);

      // Update message status to delivered and send WebSocket update
      _updateMessageStatus(chatId, newMessage.id, 'delivered');

      // Send WebSocket status update for delivered status
      if (SocketService.instance.isAuthenticated) {
        SocketService.instance.updateMessageStatus(
          messageId: newMessage.id,
          status: 'delivered',
        );
      }

      // Increment unread count if message is from another user
      final currentUserId = SocketService.instance.currentUserId;
      if (newMessage.senderId != currentUserId) {
        _unreadCounts[chatId] = (_unreadCounts[chatId] ?? 0) + 1;
      }

      print(
          '📱 ChatProvider: Successfully processed message: ${newMessage.id}');
      notifyListeners();
    } catch (e) {
      print('📱 ChatProvider: Error processing Socket.IO message: $e');
      print('📱 ChatProvider: Message data: $data');
    }
  }

  void _handleTypingReceived(Map<String, dynamic> data) {
    // Handle typing indicators
    print('📱 ChatProvider: Received typing indicator: $data');

    try {
      // Extract sender ID - handle both 'sender_id' and 'userId' fields
      String senderId;
      if (data.containsKey('sender_id')) {
        senderId = data['sender_id'].toString();
      } else if (data.containsKey('userId')) {
        senderId = data['userId'].toString();
      } else {
        print('📱 ChatProvider: No sender ID found in typing data: $data');
        return;
      }

      // Extract typing status
      bool isTyping;
      if (data.containsKey('is_typing')) {
        isTyping = data['is_typing'] == true;
      } else if (data.containsKey('isTyping')) {
        isTyping = data['isTyping'] == true;
      } else {
        print('📱 ChatProvider: No typing status found in data: $data');
        return;
      }

      print('📱 ChatProvider: User $senderId typing: $isTyping');

      // Update typing status for the user
      if (_chatUsers.containsKey(senderId)) {
        _chatUsers[senderId] = _chatUsers[senderId]!.copyWith(
          isTyping: isTyping,
        );
        notifyListeners();
      } else {
        print('📱 ChatProvider: User $senderId not found in chat users');
      }
    } catch (e) {
      print('📱 ChatProvider: Error processing typing indicator: $e');
      print('📱 ChatProvider: Typing data: $data');
    }
  }

  void _handleInvitationResponse(Map<String, dynamic> data) {
    final status = data['status'] as String;

    // If invitation was accepted, refresh chats to show the new chat
    if (status == 'accepted') {
      print('📱 ChatProvider: Invitation accepted, refreshing chats...');
      loadChats();
    }
  }

  void _handleSocketConnected() {
    print('🔌 ChatProvider: Socket.IO connected');
  }

  void _handleSocketDisconnected() {
    print('🔌 ChatProvider: Socket.IO disconnected');
  }

  void _handleSocketError(String error) {
    print('🔌 ChatProvider: Socket.IO error: $error');
    // Don't set this as a blocking error - Socket.IO is optional
    // _error = 'Socket.IO error: $error';
    // notifyListeners();
  }

  void _handleMessageStatusUpdated(Map<String, dynamic> data) {
    print('📱 ChatProvider: Message status updated: $data');

    try {
      final messageId = data['messageId'].toString();
      final status = data['status'] as String;

      // Find the message in all chats and update its status
      for (final chatId in _messages.keys) {
        final messages = _messages[chatId];
        if (messages != null) {
          for (int i = 0; i < messages.length; i++) {
            if (messages[i].id == messageId) {
              messages[i] = messages[i].copyWith(status: status);
              _saveMessagesToLocal(chatId, messages);
              print(
                  '📱 ChatProvider: Updated message $messageId status to $status in chat $chatId');
              break;
            }
          }
        }
      }

      notifyListeners();
    } catch (e) {
      print('📱 ChatProvider: Error processing message status update: $e');
      print('📱 ChatProvider: Status data: $data');
    }
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
    final localChats = box.values.map((e) => Chat.fromJson(e)).toList();
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
          print('📱 ChatProvider: Chat data: $chatData');

          bool userStored = false;

          // Check for other_user field (primary structure from API)
          if (chatData.containsKey('other_user') &&
              chatData['other_user'] != null) {
            final otherUserData =
                chatData['other_user'] as Map<String, dynamic>;
            print('📱 ChatProvider: other_user data: $otherUserData');
            final otherUser = User.fromJson(otherUserData);
            // Use the actual online status from the API
            _chatUsers[otherUser.id] = otherUser;
            userStored = true;
            print(
                '📱 ChatProvider: Stored user ${otherUser.username} with ID ${otherUser.id} (online: ${otherUser.isOnline})');
          }

          // Also check for participants field (alternative structure)
          if (!userStored &&
              chatData.containsKey('participants') &&
              chatData['participants'] != null) {
            final participants = chatData['participants'] as List;
            for (final participantData in participants) {
              final participant =
                  User.fromJson(participantData as Map<String, dynamic>);
              // Use the actual online status from the API
              _chatUsers[participant.id] = participant;
              userStored = true;
              print(
                  '📱 ChatProvider: Stored participant ${participant.username} with ID ${participant.id} (online: ${participant.isOnline})');
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
                isOnline: false, // Default to offline for unknown users
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
      _messages[chatId] =
          (localMessages as List).map((e) => Message.fromJson(e)).toList();
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

  Future<void> loadMessages(String chatId, [String? currentUserId]) async {
    // Check if chat exists first
    final chatExists = _chats.any((chat) => chat.id == chatId);
    if (!chatExists) {
      print('📱 ChatProvider: Chat $chatId not found, skipping message load');
      return;
    }

    // Load from local storage first
    await _loadMessagesFromLocal(chatId);

    try {
      print('📱 ChatProvider: Loading messages for chat $chatId');
      final response = await ApiService.getMessages(chatId);
      if (response['success'] == true) {
        final messagesData = response['messages'] as List;
        final newMessages = messagesData
            .map((messageData) => Message.fromJson(messageData))
            .toList();

        _messages[chatId] = newMessages;
        await _saveMessagesToLocal(chatId, _messages[chatId]!);

        // Send WebSocket status updates for messages that are now read
        if (SocketService.instance.isAuthenticated) {
          for (final message in newMessages) {
            if (message.status == 'read' && message.senderId != currentUserId) {
              SocketService.instance.updateMessageStatus(
                messageId: message.id,
                status: 'read',
              );
            }
          }
        }

        notifyListeners();
      } else {
        throw Exception(response['message'] ?? 'Failed to load messages');
      }
    } catch (e) {
      print('📱 ChatProvider: Error loading messages for chat $chatId: $e');
      // Don't set this as a blocking error - messages can be loaded later
      // _error = e.toString();
      // notifyListeners();
    }
  }

  Future<void> markMessagesAsRead(String chatId,
      [String? currentUserId]) async {
    // Check if chat exists first
    final chatExists = _chats.any((chat) => chat.id == chatId);
    if (!chatExists) {
      print('📱 ChatProvider: Chat $chatId not found, skipping mark as read');
      return;
    }

    try {
      await ApiService.markMessagesAsRead(chatId);

      // Update local messages status and send WebSocket updates
      final messages = _messages[chatId];
      if (messages != null) {
        for (int i = 0; i < messages.length; i++) {
          if (messages[i].status != 'read') {
            final updatedMessage = messages[i].copyWith(status: 'read');
            messages[i] = updatedMessage;

            // Send WebSocket status update for real-time feedback
            if (SocketService.instance.isAuthenticated) {
              SocketService.instance.updateMessageStatus(
                messageId: updatedMessage.id,
                status: 'read',
              );
              print(
                  '📱 ChatProvider: Sent read status update for message ${updatedMessage.id}');
            }
          }
        }
        await _saveMessagesToLocal(chatId, messages);
      }

      // Clear unread count for this chat
      _unreadCounts[chatId] = 0;

      notifyListeners();
    } catch (e) {
      // Silently fail for read status updates
      print(
          '📱 ChatProvider: Failed to mark messages as read for chat $chatId: $e');
    }
  }

  Future<void> sendMessage(String chatId, String content,
      [String? currentUserId]) async {
    // Check if chat exists first
    final chatExists = _chats.any((chat) => chat.id == chatId);
    if (!chatExists) {
      print('📱 ChatProvider: Chat $chatId not found, cannot send message');
      _error = 'Chat not found';
      notifyListeners();
      return;
    }

    try {
      // Get current user ID from parameter or SocketService
      String? userId = currentUserId;
      if (userId == null) {
        userId = SocketService.instance.currentUserId;
      }

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Try Socket.IO first for real-time messaging
      if (SocketService.instance.isAuthenticated) {
        // Get recipient's user ID
        final otherUserId = _getOtherUserId(chatId);
        if (otherUserId.isEmpty) {
          throw Exception('Recipient not found');
        }

        // Send message via Socket.IO
        SocketService.instance.sendMessage(
          receiverId: otherUserId,
          message: content,
        );

        // Create temporary message for immediate UI feedback
        final tempMessage = Message(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          chatId: chatId,
          senderId: userId,
          content: content,
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
      print('📱 ChatProvider: Error sending message: $e');
      _error = e.toString();
      notifyListeners();
    }
  }

  // Send typing indicator
  void sendTypingIndicator(String chatId, bool isTyping,
      [String? currentUserId]) {
    try {
      if (SocketService.instance.isAuthenticated) {
        final otherUserId = _getOtherUserId(chatId);
        if (otherUserId.isNotEmpty) {
          SocketService.instance.sendTypingIndicator(
            receiverId: otherUserId,
            isTyping: isTyping,
          );
        } else {
          print(
              '📱 ChatProvider: Cannot send typing indicator - other user ID not found for chat $chatId');
        }
      }
    } catch (e) {
      print(
          '📱 ChatProvider: Error sending typing indicator for chat $chatId: $e');
    }
  }

  // Get typing status for a user
  bool isUserTyping(String userId) {
    return _chatUsers[userId]?.isTyping ?? false;
  }

  String _getOtherUserId(String chatId) {
    try {
      final chat = _chats.firstWhere((c) => c.id == chatId);

      // Get current user ID from SocketService or AuthProvider
      String currentUserId = SocketService.instance.currentUserId ?? '';

      // If SocketService doesn't have it, try to get from storage
      if (currentUserId.isEmpty) {
        // We'll need to get this from AuthProvider, but for now use a placeholder
        // This should be passed in from the UI layer
        currentUserId = 'current_user_placeholder';
      }

      return chat.getOtherUserId(currentUserId);
    } catch (e) {
      print('📱 ChatProvider: Chat $chatId not found in _getOtherUserId');
      return '';
    }
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
    print(
        '📱 ChatProvider: Attempting to update online status for user $userId - Online: $isOnline');
    print(
        '📱 ChatProvider: User exists in _chatUsers: ${_chatUsers.containsKey(userId)}');
    print('📱 ChatProvider: Available users: ${_chatUsers.keys.toList()}');

    if (_chatUsers.containsKey(userId)) {
      _chatUsers[userId] = _chatUsers[userId]!.copyWith(
        isOnline: isOnline,
        lastSeen: lastSeen,
      );
      print(
          '📱 ChatProvider: Successfully updated online status for user $userId - Online: $isOnline');
      notifyListeners();
    } else {
      print(
          '📱 ChatProvider: User $userId not found in _chatUsers, cannot update online status');
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
