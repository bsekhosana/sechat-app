import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/message.dart';
import '../providers/chat_provider.dart';
import '../providers/chat_list_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input_area.dart';
import '../widgets/chat_header.dart';
import '../widgets/typing_indicator.dart';
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
      final chatProvider = context.read<ChatProvider>();

      // Initialize the chat provider
      chatProvider
          .initialize(
        conversationId: widget.conversationId,
        recipientId: widget.recipientId,
        recipientName: widget.recipientName,
      )
          .then((_) {
        // Mark conversation as read when screen is opened
        chatProvider.markAsRead();

        // Also update the chat list counter
        final chatListProvider =
            Provider.of<ChatListProvider>(context, listen: false);
        chatListProvider.markConversationAsRead(widget.conversationId);
      });
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
      backgroundColor: Theme.of(context).colorScheme.background,
      body: GestureDetector(
        onTap: () {
          // Auto-close keyboard when tapping outside input field
          FocusScope.of(context).unfocus();
        },
        child: SafeArea(
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
                typingUserName: 'Bruno', // TODO: Get from typing indicator data
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
      _showErrorSnackBar('Failed to send image message: $e');
    }
  }

  /// Send video message
  Future<void> _sendVideoMessage(String filePath, ChatProvider provider) async {
    try {
      await provider.sendVideoMessage(filePath);
      _scrollToBottom();
    } catch (e) {
      _showErrorSnackBar('Failed to send video message: $e');
    }
  }

  /// Send document message
  Future<void> _sendDocumentMessage(
      String filePath, ChatProvider provider) async {
    try {
      await provider.sendDocumentMessage(filePath);
      _scrollToBottom();
    } catch (e) {
      _showErrorSnackBar('Failed to send document message: $e');
    }
  }

  /// Send location message
  Future<void> _sendLocationMessage(
      double latitude, double longitude, ChatProvider provider) async {
    try {
      await provider.sendLocationMessage(latitude, longitude);
      _scrollToBottom();
    } catch (e) {
      _showErrorSnackBar('Failed to send location message: $e');
    }
  }

  /// Send contact message
  Future<void> _sendContactMessage(
      ContactData contactData, ChatProvider provider) async {
    try {
      await provider.sendContactMessage(contactData);
      _scrollToBottom();
    } catch (e) {
      _showErrorSnackBar('Failed to send contact message: $e');
    }
  }

  /// Send emoticon message
  Future<void> _sendEmoticonMessage(
      String emoticon, ChatProvider provider) async {
    try {
      await provider.sendEmoticonMessage(emoticon);
      _scrollToBottom();
    } catch (e) {
      _showErrorSnackBar('Failed to send emoticon message: $e');
    }
  }

  /// Update typing indicator
  void _updateTypingIndicator(bool isTyping, ChatProvider provider) {
    provider.updateTypingIndicator(isTyping);
  }

  /// Scroll to bottom of messages
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Show chat options
  void _showChatOptions(ChatProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
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

            // Options
            _buildChatOption(
              icon: Icons.search,
              title: 'Search messages',
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement search functionality
              },
            ),
            _buildChatOption(
              icon: Icons.notifications_off,
              title: provider.isMuted
                  ? 'Unmute notifications'
                  : 'Mute notifications',
              onTap: () {
                Navigator.pop(context);
                provider.toggleMuteNotifications();
              },
            ),
            _buildChatOption(
              icon: Icons.delete_outline,
              title: 'Delete chat',
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmation(provider);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Build chat option
  Widget _buildChatOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
      ),
      onTap: onTap,
    );
  }

  /// Show delete confirmation
  void _showDeleteConfirmation(ChatProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(
          'Delete chat?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'This will permanently delete all messages in this conversation. This action cannot be undone.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.deleteConversation();
              Navigator.pop(context);
            },
            child: Text(
              'Delete',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
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
      builder: (context) => Container(
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

            // Options
            _buildMessageOption(
              icon: Icons.reply,
              title: 'Reply',
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement reply functionality
              },
            ),
            _buildMessageOption(
              icon: Icons.forward,
              title: 'Forward',
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement forward functionality
              },
            ),
            _buildMessageOption(
              icon: Icons.copy,
              title: 'Copy',
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement copy functionality
              },
            ),
            if (message.isFromCurrentUser(_getCurrentUserId()))
              _buildMessageOption(
                icon: Icons.delete_outline,
                title: 'Delete',
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteMessageConfirmation(message, provider);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Build message option
  Widget _buildMessageOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
      ),
      onTap: onTap,
    );
  }

  /// Show delete message confirmation
  void _showDeleteMessageConfirmation(Message message, ChatProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(
          'Delete message?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'This message will be permanently deleted. This action cannot be undone.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.deleteMessage(message.id);
            },
            child: Text(
              'Delete',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
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
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Get current user ID
  String _getCurrentUserId() {
    // TODO: Get from authentication service
    return 'current_user_id';
  }
}
