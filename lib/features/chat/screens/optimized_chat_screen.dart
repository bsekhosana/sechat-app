import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sechat_app/features/chat/providers/optimized_session_chat_provider.dart';

import 'package:sechat_app/features/chat/widgets/optimized_message_bubble.dart';
import 'package:sechat_app/features/chat/widgets/optimized_typing_indicator.dart';

/// Optimized Chat Screen
/// Clean, focused chat screen with real-time message updates
class OptimizedChatScreen extends StatefulWidget {
  final String conversationId;
  final String recipientName;

  const OptimizedChatScreen({
    super.key,
    required this.conversationId,
    required this.recipientName,
  });

  @override
  State<OptimizedChatScreen> createState() => _OptimizedChatScreenState();
}

class _OptimizedChatScreenState extends State<OptimizedChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Initialize the chat session when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<OptimizedSessionChatProvider>()
          .initialize(widget.conversationId);
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
      bottomNavigationBar: _buildMessageInput(),
    );
  }

  /// Build app bar with recipient info and online status
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: _buildAppBarTitle(),
      elevation: 2,
      backgroundColor: Theme.of(context).primaryColor,
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: _showChatOptions,
        ),
      ],
    );
  }

  /// Build app bar title with recipient info
  Widget _buildAppBarTitle() {
    return Consumer<OptimizedSessionChatProvider>(
      builder: (context, provider, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.recipientName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (provider.isRecipientOnline)
              const Text(
                'Online',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green,
                ),
              )
            else if (provider.recipientLastSeen != null)
              Text(
                'Last seen ${_formatLastSeen(provider.recipientLastSeen!)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
          ],
        );
      },
    );
  }

  /// Build main body content
  Widget _buildBody() {
    return Consumer<OptimizedSessionChatProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (provider.error != null) {
          return _buildErrorWidget(provider.error!);
        }

        if (provider.messages.isEmpty) {
          return _buildEmptyState();
        }

        return Column(
          children: [
            Expanded(
              child: _buildMessagesList(provider),
            ),
            if (provider.isRecipientTyping)
              OptimizedTypingIndicator(
                userName: widget.recipientName,
              ),
          ],
        );
      },
    );
  }

  /// Build messages list
  Widget _buildMessagesList(OptimizedSessionChatProvider provider) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16.0),
      reverse: true,
      itemCount: provider.messages.length,
      itemBuilder: (context, index) {
        final message = provider.messages[index];
        return OptimizedMessageBubble(
          message: message,
          isFromCurrentUser: provider.isMessageFromCurrentUser(message),
        );
      },
    );
  }

  /// Build error widget
  Widget _buildErrorWidget(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            'Error loading chat',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              context.read<OptimizedSessionChatProvider>().refreshMessages();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Build empty state widget
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start the conversation by sending a message',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[500],
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Build message input area
  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              onChanged: _onMessageChanged,
            ),
          ),
          const SizedBox(width: 8),
          _buildSendButton(),
        ],
      ),
    );
  }

  /// Build send button
  Widget _buildSendButton() {
    return Consumer<OptimizedSessionChatProvider>(
      builder: (context, provider, child) {
        final hasText = _messageController.text.trim().isNotEmpty;

        return Container(
          decoration: BoxDecoration(
            color: hasText ? Theme.of(context).primaryColor : Colors.grey[300],
            shape: BoxShape.circle,
          ),
          child: IconButton(
            onPressed: hasText ? _sendMessage : null,
            icon: Icon(
              Icons.send,
              color: hasText ? Colors.white : Colors.grey[600],
            ),
          ),
        );
      },
    );
  }

  /// Handle message text changes
  void _onMessageChanged(String text) {
    // TODO: Implement typing indicator
    setState(() {});
  }

  /// Send message
  void _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    try {
      // Clear input
      _messageController.clear();
      _focusNode.unfocus();

      // Send message via provider
      await context
          .read<OptimizedSessionChatProvider>()
          .sendTextMessage(message);

      // Scroll to bottom to show new message
      _scrollToBottom();
    } catch (e) {
      // Show error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
  void _showChatOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _buildChatOptionsSheet(),
    );
  }

  /// Build chat options bottom sheet
  Widget _buildChatOptionsSheet() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Search Messages'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement message search
            },
          ),
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: const Text('Attach File'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement file attachment
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Camera'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement camera
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Gallery'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement gallery
            },
          ),
          ListTile(
            leading: const Icon(Icons.mic),
            title: const Text('Voice Message'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement voice messages
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title:
                const Text('Clear Chat', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _showClearChatConfirmation();
            },
          ),
        ],
      ),
    );
  }

  /// Show clear chat confirmation dialog
  void _showClearChatConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat'),
        content: const Text(
          'This will delete all messages in this conversation. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement clear chat functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Clear chat feature coming soon!'),
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  /// Format last seen time
  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }
}
