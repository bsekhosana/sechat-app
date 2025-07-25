import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/message.dart';
import '../../../shared/providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/local_storage_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/network_service.dart';
import 'dart:async';

class ChatScreen extends StatefulWidget {
  final Chat chat;

  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();
  Timer? _typingTimer;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();

    // Add scroll listener to track position
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final chatProvider = context.read<ChatProvider>();
      final currentUser = context.read<AuthProvider>().currentUser;

      if (currentUser != null) {
        // Set current user as active in this chat
        chatProvider.setUserActiveInChat(widget.chat.id);

        chatProvider.loadMessages(widget.chat.id);
        // Mark all messages as read when entering chat
        chatProvider.markAllMessagesAsRead(widget.chat.id);

        // Refresh online status for the other user
        final otherUserId = widget.chat.getOtherUserId(currentUser.id);
        if (otherUserId.isNotEmpty) {
          print(
              '📱 ChatScreen: Refreshing online status for user $otherUserId');
          // Refresh online status via API
          await chatProvider.refreshUserOnlineStatus();
        }

        // Add listener to scroll to bottom when new messages arrive
        chatProvider.addListener(_onMessagesChanged);

        // No need to scroll to bottom initially since ListView is reversed
        // Messages will appear at the bottom by default
      } else {
        print('📱 ChatScreen: Current user not found');
      }
    });
  }

  void _onScroll() {
    // Trigger rebuild to update floating action button visibility
    setState(() {});
  }

  void _onMessagesChanged() {
    final chatProvider = context.read<ChatProvider>();
    final messages = chatProvider.getMessagesForChat(widget.chat.id);

    // Scroll to bottom if there are messages
    if (messages.isNotEmpty && _scrollController.hasClients) {
      try {
        // Check if this is the initial load (no previous scroll position)
        final isInitialLoad = _scrollController.position.pixels == 0;

        if (isInitialLoad) {
          // Always scroll to bottom on initial load
          _scrollToBottom();
        } else {
          // For subsequent updates, only scroll if user is near bottom (top of reversed list)
          final isAtBottom =
              _scrollController.position.pixels <= 100; // 100px threshold

          if (isAtBottom) {
            _scrollToBottom();
          }
        }
      } catch (e) {
        // Handle case where scroll position is not available yet
        print(
            '📱 ChatScreen: Scroll position not available in _onMessagesChanged: $e');
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();

    // Store references to providers before disposal to avoid unsafe access
    ChatProvider? chatProvider;
    AuthProvider? authProvider;

    try {
      chatProvider = context.read<ChatProvider>();
      authProvider = context.read<AuthProvider>();
    } catch (e) {
      print('📱 ChatScreen: Error accessing providers during disposal: $e');
    }

    // Remove listener to prevent memory leaks
    if (chatProvider != null) {
      try {
        chatProvider.removeListener(_onMessagesChanged);
      } catch (e) {
        print('📱 ChatScreen: Error removing listener: $e');
      }
    }

    // Set current user as inactive when leaving chat
    if (authProvider != null && chatProvider != null) {
      final currentUser = authProvider.currentUser;
      if (currentUser != null) {
        try {
          chatProvider.setUserInactiveInChat(currentUser.id);
        } catch (e) {
          print('📱 ChatScreen: Error setting user inactive: $e');
        }
      }
    }

    // Stop typing indicator when leaving chat
    if (_isTyping && chatProvider != null) {
      try {
        chatProvider.sendTypingIndicator(widget.chat.id, false);
      } catch (e) {
        print('📱 ChatScreen: Error stopping typing indicator: $e');
      }
    }

    super.dispose();
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    // Stop typing indicator
    _stopTypingIndicator();

    final chatProvider = context.read<ChatProvider>();
    final currentUser = context.read<AuthProvider>().currentUser;

    if (currentUser != null) {
      chatProvider.sendMessage(widget.chat.id, _messageController.text.trim());
    } else {
      print('📱 ChatScreen: Current user not found, cannot send message');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated')),
      );
      return;
    }

    _messageController.clear();

    // Scroll to bottom after sending message
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // Since ListView is reversed, scroll to 0 to show newest messages
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTextChanged(String text) {
    // Only start typing indicator if there's actual content (not just spaces)
    if (text.trim().isNotEmpty) {
      if (!_isTyping) {
        _startTypingIndicator();
      }

      // Reset typing timer
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(milliseconds: 1500), () {
        _stopTypingIndicator();
      });
    } else {
      // If text is empty or only spaces, stop typing indicator
      if (_isTyping) {
        _stopTypingIndicator();
      }
    }
  }

  void _startTypingIndicator() {
    if (!_isTyping) {
      _isTyping = true;
      final currentUser = context.read<AuthProvider>().currentUser;
      if (currentUser != null) {
        context.read<ChatProvider>().sendTypingIndicator(widget.chat.id, true);
      }
    }
  }

  void _stopTypingIndicator() {
    if (_isTyping) {
      _isTyping = false;
      final currentUser = context.read<AuthProvider>().currentUser;
      if (currentUser != null) {
        context.read<ChatProvider>().sendTypingIndicator(widget.chat.id, false);
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        await _sendImage(image);
      }
    } catch (e) {
      print('📱 ChatScreen: Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendImage(XFile imageFile) async {
    try {
      final currentUser = context.read<AuthProvider>().currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Read image data
      final Uint8List imageData = await imageFile.readAsBytes();
      final fileName =
          '${LocalStorageService.instance.generateMessageId()}.jpg';

      // Save image to local storage
      final localPath =
          await LocalStorageService.instance.saveImage(imageData, fileName);

      // Create message
      final messageId = LocalStorageService.instance.generateMessageId();
      final message = Message(
        id: messageId,
        chatId: widget.chat.id,
        senderId: currentUser.id,
        content: '📷 Image',
        type: MessageType.image,
        status: 'sent',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        localFilePath: localPath,
        fileName: imageFile.name,
        fileSize: imageData.length,
      );

      // Save message to local storage
      await LocalStorageService.instance.saveMessage(message);

      // Add to local messages for UI
      final chatProvider = context.read<ChatProvider>();
      chatProvider.addMessageToChat(widget.chat.id, message);

      // Try to send via Session if available
      if (SessionService.instance.isConnected &&
          NetworkService.instance.isConnected) {
        try {
          final otherUserId = chatProvider.getOtherUserId(widget.chat.id);
          if (otherUserId.isNotEmpty) {
            // For now, just send a text message indicating image was sent
            // In a full implementation, you'd upload the image to a server
            SessionService.instance.sendMessage(
              receiverId: otherUserId,
              content: '📷 Image sent',
            );

            // Keep status as 'sent' - will be updated when receiver confirms
          }
        } catch (e) {
          print('📱 ChatScreen: Session send failed, image saved locally: $e');
        }
      } else {
        // Add to pending messages for later sync
        await LocalStorageService.instance.addPendingMessage(message);
        print('📱 ChatScreen: Image queued for later sync');
      }
    } catch (e) {
      print('📱 ChatScreen: Error sending image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleDeleteMessage(Message message, String deleteType) async {
    try {
      final chatProvider = context.read<ChatProvider>();

      // Use the new ChatProvider method for message deletion
      chatProvider.deleteMessage(widget.chat.id, message.id,
          deleteType: deleteType);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(deleteType == 'for_me'
                ? 'Message deleted for you'
                : 'Message deleted for everyone'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      print('📱 ChatScreen: Error deleting message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF2C2C2C),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            const Text(
              'Send Image',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _pickImage(ImageSource.camera);
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B35),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _pickImage(ImageSource.gallery);
                    },
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B35),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _blockUser(String userId) async {
    final confirmed = await _showBlockUserActionSheet(context);

    if (confirmed == true) {
      try {
        final response = await ApiService.blockUser(userId);
        if (response['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'User blocked successfully'),
              backgroundColor: Colors.red,
            ),
          );
          // Navigate back to chat list
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Failed to block user'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error blocking user: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool?> _showBlockUserActionSheet(BuildContext context) async {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF2C2C2C),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Block User',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Description
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Are you sure you want to block this user? This will remove all chats and messages between you and prevent future communication.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 16),

              // Action buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Block'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Future<void> _removeUserChats(String userId) async {
    final confirmed = await _showRemoveChatsActionSheet(context);

    if (confirmed == true) {
      try {
        final response = await ApiService.removeUserChats(userId);
        if (response['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(response['message'] ?? 'Chats removed successfully'),
              backgroundColor: Colors.orange,
            ),
          );
          // Navigate back to chat list
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Failed to remove chats'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing chats: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<bool?> _showRemoveChatsActionSheet(BuildContext context) async {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF2C2C2C),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Remove Chats',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Description
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Are you sure you want to remove all chats and messages with this user? This action cannot be undone.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 16),

              // Action buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Remove'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.read<AuthProvider>().currentUser;
    final otherUserId = widget.chat.getOtherUserId(currentUser?.id ?? '');
    final otherUser = context.read<ChatProvider>().getChatUser(otherUserId);

    // Get username from chat data if user not found
    String displayUsername = 'Unknown User';
    if (otherUser != null) {
      displayUsername = otherUser.username;
      print('📱 ChatScreen: Using username from otherUser: $displayUsername');
    } else if (widget.chat.otherUser != null &&
        widget.chat.otherUser!.containsKey('username')) {
      displayUsername = widget.chat.otherUser!['username'];
      print(
          '📱 ChatScreen: Using username from chat.otherUser: $displayUsername');
    } else {
      print(
          '📱 ChatScreen: No username found, using fallback: $displayUsername');
      print('📱 ChatScreen: otherUser: $otherUser');
      print('📱 ChatScreen: chat.otherUser: ${widget.chat.otherUser}');
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80, // Increased height
        title: Row(
          children: [
            CircleAvatar(
              radius: 24, // Increased avatar size
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                displayUsername.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18, // Increased font size
                ),
              ),
            ),
            const SizedBox(width: 16), // Increased spacing
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    displayUsername,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 18, // Increased font size
                    ),
                  ),
                  const SizedBox(height: 4), // Added spacing
                  Consumer<ChatProvider>(
                    builder: (context, chatProvider, child) {
                      final isTyping = chatProvider.isUserTyping(otherUserId);

                      // Get effective online status that considers typing state
                      final effectiveOnlineStatus =
                          chatProvider.getEffectiveOnlineStatus(otherUserId);

                      if (isTyping) {
                        return Text(
                          'typing...',
                          style: TextStyle(
                            fontSize: 14, // Increased font size
                            color: Theme.of(context).colorScheme.primary,
                            fontStyle: FontStyle.italic,
                          ),
                        );
                      } else {
                        return Text(
                          effectiveOnlineStatus ? 'Online' : 'Offline',
                          style: TextStyle(
                            fontSize: 14, // Increased font size
                            color: effectiveOnlineStatus
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 28),
            onSelected: (value) async {
              switch (value) {
                case 'block':
                  await _blockUser(otherUserId);
                  break;
                case 'remove_chats':
                  await _removeUserChats(otherUserId);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                    Icon(Icons.block, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Block User'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'remove_chats',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Remove Chats'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.call, size: 28), // Increased icon size
            onPressed: () {
              // TODO: Implement voice calling
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Voice calling coming soon!')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, child) {
                final messages = chatProvider.getMessagesForChat(
                  widget.chat.id,
                );

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start the conversation!',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  reverse:
                      true, // Start from bottom, scroll up for older messages
                  itemBuilder: (context, index) {
                    // Use reversed index since we want newest messages at bottom
                    final message = messages[messages.length - 1 - index];
                    final currentUser =
                        context.read<AuthProvider>().currentUser;
                    final isOwnMessage = message.senderId == currentUser?.id;

                    return _MessageBubble(
                      message: message,
                      isOwnMessage: isOwnMessage,
                      onDeleteMessage: _handleDeleteMessage,
                    );
                  },
                );
              },
            ),
          ),
          // Message Input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                // Image picker button
                IconButton(
                  onPressed: _showImagePickerOptions,
                  icon: const Icon(Icons.image),
                  color: const Color(0xFFFF6B35),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: _onTextChanged,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _sendMessage,
                  mini: true,
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Consumer<ChatProvider>(
        builder: (context, chatProvider, child) {
          final messages = chatProvider.getMessagesForChat(widget.chat.id);

          // Show scroll to bottom button if there are messages and user is not at bottom
          if (messages.isNotEmpty && _scrollController.hasClients) {
            try {
              // Since ListView is reversed, check if user is near the top (which shows newest messages)
              final isAtBottom = _scrollController.position.pixels <= 100;

              if (!isAtBottom) {
                return FloatingActionButton(
                  onPressed: _scrollToBottom,
                  mini: true,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: const Icon(Icons.keyboard_arrow_down,
                      color: Colors.white),
                );
              }
            } catch (e) {
              // Handle case where scroll position is not available yet
              print('📱 ChatScreen: Scroll position not available yet: $e');
            }
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isOwnMessage;
  final Function(Message, String) onDeleteMessage;

  const _MessageBubble({
    required this.message,
    required this.isOwnMessage,
    required this.onDeleteMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isOwnMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showDeleteOptions(context),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isOwnMessage
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16).copyWith(
              bottomLeft: isOwnMessage
                  ? const Radius.circular(16)
                  : const Radius.circular(4),
              bottomRight: isOwnMessage
                  ? const Radius.circular(4)
                  : const Radius.circular(16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.type == MessageType.image) ...[
                // Image message
                if (message.localFilePath != null &&
                    message.localFilePath!.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(
                      maxWidth: 200,
                      maxHeight: 200,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(message.localFilePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 200,
                            height: 150,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.broken_image,
                              size: 50,
                              color: Colors.grey,
                            ),
                          );
                        },
                      ),
                    ),
                  )
                else
                  Container(
                    width: 200,
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.image,
                      size: 50,
                      color: Colors.grey,
                    ),
                  ),
              ] else ...[
                // Text message
                Text(
                  message.content,
                  style: TextStyle(
                    color: isOwnMessage
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                _formatTime(message.createdAt),
                style: TextStyle(
                  fontSize: 10,
                  color: isOwnMessage
                      ? Theme.of(
                          context,
                        ).colorScheme.onPrimary.withValues(alpha: 0.7)
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
              if (isOwnMessage) ...[
                const SizedBox(width: 4),
                Icon(
                  message.statusIcon,
                  size: 12,
                  color: message.getStatusColor(
                    Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF2C2C2C),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            const Text(
              'Delete Message',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                onDeleteMessage(message, 'for_me');
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete for me'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),

            if (isOwnMessage) ...[
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onDeleteMessage(message, 'for_everyone');
                },
                icon: const Icon(Icons.delete_forever),
                label: const Text('Delete for everyone'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
