import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/message.dart';
import '../providers/session_chat_provider.dart';
import '../providers/chat_list_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input_area.dart';
import '../widgets/chat_header.dart';
import '../widgets/typing_indicator.dart';

/// Main screen for individual chat conversations
class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String recipientId;
  final String recipientName;
  final bool isOnline;
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.recipientId,
    required this.recipientName,
    required this.isOnline,
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
      final chatProvider = context.read<SessionChatProvider>();

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

        // CRITICAL: Scroll to bottom after messages are loaded
        // Use a delay to ensure messages are rendered first
        Future.delayed(const Duration(milliseconds: 300), () {
          _scrollToBottom();
        });
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
      backgroundColor: Colors.white, // White background
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

              // Typing indicator - positioned between messages and input
              _buildTypingIndicator(),

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
    return Consumer<SessionChatProvider>(
      builder: (context, provider, child) {
        return ChatHeader(
          recipientName: provider.currentRecipientName ?? widget.recipientName,
          isOnline: widget.isOnline || provider.isRecipientOnline,
          lastSeen: provider.recipientLastSeen,
          onBackPressed: () => Navigator.pop(context),
          onMorePressed: () => _showChatOptions(provider),
        );
      },
    );
  }

  /// Build the messages list
  Widget _buildMessagesList() {
    return Consumer<SessionChatProvider>(
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Loading messages...',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey[700], // Dark grey text
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build empty state
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No messages yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.grey[800], // Dark grey text
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Start the conversation by sending a message!',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600], // Light grey text
                    height: 1.4,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Build messages list content
  Widget _buildMessagesListContent(SessionChatProvider provider) {
    // CRITICAL: Check if we need to auto-scroll for incoming messages
    _checkAndAutoScrollForIncomingMessages(provider);

    // CRITICAL: Auto-scroll to bottom when messages are first loaded
    // This ensures the chat opens scrolled to the bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (provider.messages.isNotEmpty && _scrollController.hasClients) {
        final currentPosition = _scrollController.position.pixels;
        // Only auto-scroll if we're not already at the bottom
        if (currentPosition < _scrollController.position.maxScrollExtent - 10) {
          print(
              '📱 ChatScreen: 🔄 Auto-scrolling to bottom for initial message load');
          _scrollToBottom();
        }
      }
    });

    // Process messages for display (no decryption at this stage)
    for (var element in provider.messages) {
      try {
        print('🟢 ChatScreen: 🔍 Message: ${element.id}');
        print(
            '🟢 ChatScreen: 🔍 Content keys: ${element.content.keys.toList()}');
        print('🟢 ChatScreen: 🔍 Is encrypted: ${element.isEncrypted}');
        print('🟢 ChatScreen: 🔍 Timestamp: ${element.timestamp}');
        print('🟢 ChatScreen: 🔍 Sender: ${element.senderId}');
        print('🟢 ChatScreen: 🔍 Conversation: ${element.conversationId}');
      } catch (e) {
        print('🟢 ChatScreen: ❌ Error processing message ${element.id}: $e');
      }
    }

    // print('🟢 ChatScreen: 🔍 Messages: ${provider.messages}');
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
                  padding:
                      const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
                  reverse:
                      false, // Show messages in normal order (oldest to newest)
                  itemCount: provider.messages.length,
                  itemBuilder: (context, index) {
                    // Messages are now sorted ASCENDING (oldest first), so display naturally
                    final message = provider.messages[index];
                    final isLast = index ==
                        provider.messages.length -
                            1; // Last message is at the end

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
          ],
        ),
      ),
    );
  }

  /// Build typing indicator
  Widget _buildTypingIndicator() {
    return Consumer<SessionChatProvider>(
      builder: (context, provider, child) {
        if (!provider.isRecipientTyping) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TypingIndicator(
            typingUserName:
                provider.currentRecipientName ?? widget.recipientName,
          ),
        );
      },
    );
  }

  /// Build input area
  Widget _buildInputArea() {
    return Consumer<SessionChatProvider>(
      builder: (context, provider, child) {
        return ChatInputArea(
          onTextMessageSent: (text) => _sendTextMessage(text, provider),
          isTyping: (isTyping) => _updateTypingIndicator(isTyping, provider),
        );
      },
    );
  }

  /// Send text message
  Future<void> _sendTextMessage(
      String text, SessionChatProvider provider) async {
    print('📱 ChatScreen: 🔧 _sendTextMessage called with: "$text"');
    print('📱 ChatScreen: 🔍 provider: ${provider.hashCode}');
    print('📱 ChatScreen: 🔍 provider type: ${provider.runtimeType}');

    if (text.trim().isEmpty) {
      print('📱 ChatScreen: ❌ Text is empty, returning early');
      return;
    }

    try {
      print('📱 ChatScreen: 🔧 Calling provider.sendTextMessage...');
      await provider.sendTextMessage(text.trim());
      print('📱 ChatScreen: ✅ provider.sendTextMessage completed successfully');
      _textController.clear();

      // CRITICAL: Scroll to bottom after sending message
      // Use a small delay to ensure the message is added to the UI
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollToBottom();
      });
    } catch (e) {
      print('📱 ChatScreen: ❌ Error in _sendTextMessage: $e');
      _showErrorSnackBar('Failed to send message: $e');
    }
  }

  /// Update typing indicator
  void _updateTypingIndicator(bool isTyping, SessionChatProvider provider) {
    provider.updateTypingIndicator(isTyping);
  }

  /// CRITICAL: Check if we need to auto-scroll for incoming messages
  void _checkAndAutoScrollForIncomingMessages(SessionChatProvider provider) {
    // Only auto-scroll if we have messages and the user is near the bottom
    if (provider.messages.isNotEmpty && _scrollController.hasClients) {
      final currentPosition = _scrollController.position.pixels;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final isNearBottom =
          (maxScroll - currentPosition) < 150; // Within 150px of bottom

      // If user is near bottom, auto-scroll for incoming messages
      if (isNearBottom) {
        // Check if the latest message is from another user (incoming)
        final latestMessage =
            provider.messages.last; // Last because sorted ASCENDING
        final currentUserId = _getCurrentUserId();

        if (latestMessage.senderId != currentUserId) {
          // This is an incoming message, auto-scroll to bottom
          print(
              '📱 ChatScreen: 🔄 Auto-scrolling for incoming message from ${latestMessage.senderId}');
          Future.delayed(const Duration(milliseconds: 100), () {
            _scrollToBottom();
          });
        }
      }
    }
  }

  /// Scroll to bottom of messages
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentPosition = _scrollController.position.pixels;
      print(
          '📱 ChatScreen: 🔄 Scrolling to bottom: current=$currentPosition, max=$maxScroll');

      // Only scroll if we're not already at the bottom
      if (currentPosition < maxScroll - 10) {
        _scrollController
            .animateTo(
          maxScroll,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        )
            .then((_) {
          print('📱 ChatScreen: ✅ Scrolled to bottom successfully');
        }).catchError((e) {
          print('📱 ChatScreen: ❌ Error scrolling to bottom: $e');
        });
      } else {
        print('📱 ChatScreen: ℹ️ Already at bottom, no need to scroll');
      }
    } else {
      print('📱 ChatScreen: ⚠️ ScrollController has no clients yet');
    }
  }

  /// Show chat options
  void _showChatOptions(SessionChatProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white, // White background
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
                _showSearchDialog();
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
                _showDeleteChatConfirmation();
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
              color: Colors.grey[700], // Dark grey text
            ),
      ),
      onTap: onTap,
    );
  }

  /// Show search dialog
  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white, // White background
        title: Text(
          'Search Messages',
          style: TextStyle(
            color: Colors.grey[800], // Dark grey text
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'Enter search term...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) {
                // TODO: Implement actual search logic
                print('🔍 Searching for: $value');
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Search functionality will be implemented in future updates',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show delete chat confirmation
  void _showDeleteChatConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white, // White background
        title: Text(
          'Delete Chat?',
          style: TextStyle(
            color: Colors.grey[800], // Dark grey text
          ),
        ),
        content: Text(
          'This will permanently delete this chat conversation. This action cannot be undone.',
          style: TextStyle(
            color: Colors.grey[600], // Light grey text
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
              // TODO: Implement actual chat deletion logic
              print('🗑️ Delete chat confirmed');
              Navigator.pop(context); // Go back to previous screen
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

  /// Show delete conversation confirmation
  void _showDeleteConversationConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white, // White background
        title: Text(
          'Delete Conversation?',
          style: TextStyle(
            color: Colors.grey[800], // Dark grey text
          ),
        ),
        content: Text(
          'This will permanently delete this conversation and all its messages. This action cannot be undone.',
          style: TextStyle(
            color: Colors.grey[600], // Light grey text
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
              // TODO: Implement actual conversation deletion logic
              print('🗑️ Delete conversation confirmed');
              Navigator.pop(context); // Go back to previous screen
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

  /// Show delete confirmation
  void _showDeleteConfirmation(SessionChatProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white, // White background
        title: Text(
          'Delete chat?',
          style: TextStyle(
            color: Colors.grey[800], // Dark grey text
          ),
        ),
        content: Text(
          'This will permanently delete all messages in this conversation. This action cannot be undone.',
          style: TextStyle(
            color: Colors.grey[600], // Light grey text
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
              _showDeleteConversationConfirmation();
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
  void _showMessageOptions(Message message, SessionChatProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white, // White background
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
                _handleReplyMessage(message);
              },
            ),
            _buildMessageOption(
              icon: Icons.forward,
              title: 'Forward',
              onTap: () {
                Navigator.pop(context);
                _handleForwardMessage(message);
              },
            ),
            _buildMessageOption(
              icon: Icons.copy,
              title: 'Copy',
              onTap: () {
                Navigator.pop(context);
                _handleCopyMessage(message);
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
              color: Colors.grey[700], // Dark grey text
            ),
      ),
      onTap: onTap,
    );
  }

  /// Handle reply to message
  void _handleReplyMessage(Message message) {
    // Set the text controller to show reply context
    _textController.text =
        'Replying to: ${message.content['text'] ?? 'Message'}';
    _textController.selection = TextSelection.fromPosition(
      TextPosition(offset: _textController.text.length),
    );

    // Focus the text field
    FocusScope.of(context).requestFocus(FocusNode());

    // Show a snackbar to indicate reply mode
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reply mode activated'),
        duration: const Duration(seconds: 2),
      ),
    );

    print('💬 Reply to message: ${message.id}');
  }

  /// Handle forward message
  void _handleForwardMessage(Message message) {
    // Show forward dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white, // White background
        title: Text(
          'Forward Message',
          style: TextStyle(
            color: Colors.grey[800], // Dark grey text
          ),
        ),
        content: Text(
          'Forward functionality will be implemented in future updates',
          style: TextStyle(
            color: Colors.grey[600], // Light grey text
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );

    print('📤 Forward message: ${message.id}');
  }

  /// Handle copy message
  void _handleCopyMessage(Message message) {
    final messageText = message.content['text'] ?? 'Message content';

    // Copy to clipboard
    Clipboard.setData(ClipboardData(text: messageText));

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );

    print('📋 Copy message: ${message.id}');
  }

  /// Handle delete message
  void _handleDeleteMessage(Message message, SessionChatProvider provider) {
    // TODO: Implement actual message deletion logic
    // This would typically involve:
    // 1. Removing from local storage
    // 2. Sending delete request to server
    // 3. Updating UI

    print('🗑️ Delete message confirmed: ${message.id}');

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message deleted'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Show delete message confirmation
  void _showDeleteMessageConfirmation(
      Message message, SessionChatProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white, // White background
        title: Text(
          'Delete message?',
          style: TextStyle(
            color: Colors.grey[800], // Dark grey text
          ),
        ),
        content: Text(
          'This message will be permanently deleted. This action cannot be undone.',
          style: TextStyle(
            color: Colors.grey[600], // Light grey text
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
              _handleDeleteMessage(message, provider);
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
    // Get from the chat provider
    final provider = context.read<SessionChatProvider>();
    return provider.currentUserId ?? 'unknown';
  }
}
