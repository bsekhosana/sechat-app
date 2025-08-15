import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/message.dart';
import '../models/chat_conversation.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input_area.dart';
import '../widgets/chat_header.dart';
import '../widgets/typing_indicator.dart';
import '../../../shared/widgets/connection_status_widget.dart';
import '../services/contact_message_service.dart' show ContactData;

/// Main screen for individual chat conversations
class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String recipientId;
  final String recipientName;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.recipientId,
    required this.recipientName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeChat();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeController.forward();
    _slideController.forward();
  }

  void _initializeChat() {
    // Initialize the chat provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().initialize(
            conversationId: widget.conversationId,
            recipientId: widget.recipientId,
            recipientName: widget.recipientName,
          );
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Header with recipient info and actions
            _buildHeader(),

            // Messages list
            Expanded(
              child: _buildMessagesList(),
            ),

            // Input area
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  /// Build the header section
  Widget _buildHeader() {
    return Consumer<ChatProvider>(
      builder: (context, provider, child) {
        return ChatHeader(
          recipientName: widget.recipientName,
          isOnline: provider.isRecipientOnline,
          lastSeen: provider.recipientLastSeen,
          onBackPressed: () => Navigator.pop(context),
          onMorePressed: () => _showChatOptions(provider),
        );
      },
    );
  }

  /// Build the messages list
  Widget _buildMessagesList() {
    return Consumer<ChatProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return _buildLoadingState();
        }

        if (provider.messages.isEmpty) {
          return _buildEmptyState();
        }

        return _buildMessagesListContent(provider);
      },
    );
  }

  /// Build loading state
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Loading messages...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  /// Build empty state
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color:
                Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start the conversation by sending a message!',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withOpacity(0.7),
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Build messages list content
  Widget _buildMessagesListContent(ChatProvider provider) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          children: [
            // Messages list
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await provider.refreshMessages();
                },
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  reverse: true, // Show newest messages at the bottom
                  itemCount: provider.messages.length,
                  itemBuilder: (context, index) {
                    final message = provider.messages[index];
                    final isLast = index == provider.messages.length - 1;

                    return MessageBubble(
                      message: message,
                      isFromCurrentUser:
                          message.senderId == _getCurrentUserId(),
                      onTap: () => _showMessageOptions(message, provider),
                      onLongPress: () => _showMessageOptions(message, provider),
                      isLast: isLast,
                    );
                  },
                ),
              ),
            ),

            // Typing indicator
            if (provider.isRecipientTyping)
              TypingIndicator(
                recipientName: widget.recipientName,
              ),
          ],
        ),
      ),
    );
  }

  /// Build input area
  Widget _buildInputArea() {
    return Consumer<ChatProvider>(
      builder: (context, provider, child) {
        return ChatInputArea(
          onTextMessageSent: (text) => _sendTextMessage(text, provider),
          onVoiceMessageRecorded: (duration, filePath) =>
              _sendVoiceMessage(duration, filePath, provider),
          onImageSelected: (filePath) => _sendImageMessage(filePath, provider),
          onVideoSelected: (filePath) => _sendVideoMessage(filePath, provider),
          onDocumentSelected: (filePath) =>
              _sendDocumentMessage(filePath, provider),
          onLocationShared: (latitude, longitude) =>
              _sendLocationMessage(latitude, longitude, provider),
          onContactShared: (contactData) =>
              _sendContactMessage(contactData, provider),
          onEmoticonSelected: (emoticon) =>
              _sendEmoticonMessage(emoticon, provider),
          isTyping: (isTyping) => _updateTypingIndicator(isTyping, provider),
        );
      },
    );
  }

  /// Send text message
  Future<void> _sendTextMessage(String text, ChatProvider provider) async {
    if (text.trim().isEmpty) return;

    try {
      await provider.sendTextMessage(text.trim());
      _textController.clear();
      _scrollToBottom();
    } catch (e) {
      _showErrorSnackBar('Failed to send message: $e');
    }
  }

  /// Send voice message
  Future<void> _sendVoiceMessage(
      int duration, String filePath, ChatProvider provider) async {
    try {
      await provider.sendVoiceMessage(duration, filePath);
      _scrollToBottom();
    } catch (e) {
      _showErrorSnackBar('Failed to send voice message: $e');
    }
  }

  /// Send image message
  Future<void> _sendImageMessage(String filePath, ChatProvider provider) async {
    try {
      await provider.sendImageMessage(filePath);
      _scrollToBottom();
    } catch (e) {
      _showErrorSnackBar('Failed to send image: $e');
    }
  }

  /// Send video message
  Future<void> _sendVideoMessage(String filePath, ChatProvider provider) async {
    try {
      await provider.sendVideoMessage(filePath);
      _scrollToBottom();
    } catch (e) {
      _showErrorSnackBar('Failed to send video: $e');
    }
  }

  /// Send document message
  Future<void> _sendDocumentMessage(
      String filePath, ChatProvider provider) async {
    try {
      await provider.sendDocumentMessage(filePath);
      _scrollToBottom();
    } catch (e) {
      _showErrorSnackBar('Failed to send document: $e');
    }
  }

  /// Send location message
  Future<void> _sendLocationMessage(
      double latitude, double longitude, ChatProvider provider) async {
    try {
      await provider.sendLocationMessage(latitude, longitude);
      _scrollToBottom();
    } catch (e) {
      _showErrorSnackBar('Failed to send location: $e');
    }
  }

  /// Send contact message
  Future<void> _sendContactMessage(
      ContactData contactData, ChatProvider provider) async {
    try {
      await provider.sendContactMessage(contactData);
      _scrollToBottom();
    } catch (e) {
      _showErrorSnackBar('Failed to send contact: $e');
    }
  }

  /// Send emoticon message
  Future<void> _sendEmoticonMessage(
      String emoticon, ChatProvider provider) async {
    try {
      await provider.sendEmoticonMessage(emoticon);
      _scrollToBottom();
    } catch (e) {
      _showErrorSnackBar('Failed to send emoticon: $e');
    }
  }

  /// Update typing indicator
  Future<void> _updateTypingIndicator(
      bool isTyping, ChatProvider provider) async {
    try {
      await provider.updateTypingIndicator(isTyping);
    } catch (e) {
      print('Failed to update typing indicator: $e');
    }
  }

  /// Scroll to bottom of messages
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Show chat options
  void _showChatOptions(ChatProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _buildChatOptions(provider),
    );
  }

  /// Build chat options bottom sheet
  Widget _buildChatOptions(ChatProvider provider) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Recipient info
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                widget.recipientName.isNotEmpty
                    ? widget.recipientName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              widget.recipientName.isNotEmpty
                  ? widget.recipientName
                  : 'Unknown User',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            subtitle: Text(
              '${provider.messages.length} messages',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),

          const Divider(),

          // Options
          ListTile(
            leading: Icon(
              Icons.search,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: Text(
              'Search messages',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            onTap: () {
              Navigator.pop(context);
              _showMessageSearch(provider);
            },
          ),

          ListTile(
            leading: Icon(
              Icons.notifications,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: Text(
              provider.isMuted ? 'Unmute notifications' : 'Mute notifications',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            onTap: () {
              Navigator.pop(context);
              _toggleMuteNotifications(provider);
            },
          ),

          ListTile(
            leading: Icon(
              Icons.block,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Block user',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
            onTap: () {
              Navigator.pop(context);
              _blockUser(provider);
            },
          ),

          ListTile(
            leading: Icon(
              Icons.delete_forever,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Delete conversation',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
            onTap: () {
              Navigator.pop(context);
              _deleteConversation(provider);
            },
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Show message search
  void _showMessageSearch(ChatProvider provider) {
    // TODO: Implement message search functionality
    _showInfoSnackBar('Message search coming soon!');
  }

  /// Toggle mute notifications
  void _toggleMuteNotifications(ChatProvider provider) {
    provider.toggleMuteNotifications();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          provider.isMuted
              ? 'Notifications unmuted for ${widget.recipientName}'
              : 'Notifications muted for ${widget.recipientName}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Block user
  void _blockUser(ChatProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content: Text(
          'Are you sure you want to block ${widget.recipientName}? '
          'This will prevent them from sending you messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.blockUser(widget.recipientId);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${widget.recipientName} has been blocked'),
                  duration: const Duration(seconds: 2),
                ),
              );

              Navigator.pop(context); // Return to chat list
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  /// Delete conversation
  void _deleteConversation(ChatProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: Text(
          'Are you sure you want to delete the conversation with ${widget.recipientName}? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.deleteConversation();

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text('Conversation with ${widget.recipientName} deleted'),
                  duration: const Duration(seconds: 2),
                ),
              );

              Navigator.pop(context); // Return to chat list
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Show message options
  void _showMessageOptions(Message message, ChatProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _buildMessageOptions(message, provider),
    );
  }

  /// Build message options bottom sheet
  Widget _buildMessageOptions(Message message, ChatProvider provider) {
    final canEdit = message.senderId == _getCurrentUserId() &&
        message.status != MessageStatus.deleted;
    final canDelete = message.senderId == _getCurrentUserId();

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Message preview
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  _getMessageTypeIcon(message.type),
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message.previewText,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Options
          if (canEdit)
            ListTile(
              leading: Icon(
                Icons.edit,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                'Edit message',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              onTap: () {
                Navigator.pop(context);
                _editMessage(message, provider);
              },
            ),

          ListTile(
            leading: Icon(
              Icons.reply,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: Text(
              'Reply to message',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            onTap: () {
              Navigator.pop(context);
              _replyToMessage(message, provider);
            },
          ),

          ListTile(
            leading: Icon(
              Icons.forward,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: Text(
              'Forward message',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            onTap: () {
              Navigator.pop(context);
              _forwardMessage(message, provider);
            },
          ),

          if (canDelete)
            ListTile(
              leading: Icon(
                Icons.delete,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete message',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
              onTap: () {
                Navigator.pop(context);
                _deleteMessage(message, provider);
              },
            ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Get message type icon
  IconData _getMessageTypeIcon(MessageType type) {
    switch (type) {
      case MessageType.text:
        return Icons.text_fields;
      case MessageType.voice:
        return Icons.mic;
      case MessageType.video:
        return Icons.videocam;
      case MessageType.image:
        return Icons.image;
      case MessageType.document:
        return Icons.description;
      case MessageType.location:
        return Icons.location_on;
      case MessageType.contact:
        return Icons.person;
      case MessageType.emoticon:
        return Icons.emoji_emotions;
      case MessageType.reply:
        return Icons.reply;
      case MessageType.system:
        return Icons.info;
    }
  }

  /// Edit message
  void _editMessage(Message message, ChatProvider provider) {
    // TODO: Implement message editing
    _showInfoSnackBar('Message editing coming soon!');
  }

  /// Reply to message
  void _replyToMessage(Message message, ChatProvider provider) {
    // TODO: Implement message reply
    _showInfoSnackBar('Message reply coming soon!');
  }

  /// Forward message
  void _forwardMessage(Message message, ChatProvider provider) {
    // TODO: Implement message forwarding
    _showInfoSnackBar('Message forwarding coming soon!');
  }

  /// Delete message
  void _deleteMessage(Message message, ChatProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text(
          'Are you sure you want to delete this message? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.deleteMessage(message.id);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Message deleted'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Show error snackbar
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Show info snackbar
  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Get current user ID
  String _getCurrentUserId() {
    // This will be implemented when we integrate with the session service
    // For now, return a placeholder
    return 'current_user_id';
  }
}
