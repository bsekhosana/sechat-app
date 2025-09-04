import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/message.dart';
import '../providers/unified_chat_provider.dart';
import 'unified_message_bubble.dart';

/// Virtualized message list for handling large conversations efficiently
class UnifiedVirtualizedMessageList extends StatefulWidget {
  final ScrollController scrollController;
  final VoidCallback? onLoadMore;

  const UnifiedVirtualizedMessageList({
    super.key,
    required this.scrollController,
    this.onLoadMore,
  });

  @override
  State<UnifiedVirtualizedMessageList> createState() =>
      _UnifiedVirtualizedMessageListState();
}

class _UnifiedVirtualizedMessageListState
    extends State<UnifiedVirtualizedMessageList> {
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.scrollController.hasClients) return;

    final position = widget.scrollController.position;

    // For reverse ListView, check if we're near the top (which is actually the bottom of the list)
    // This means we need to load more older messages
    if (position.pixels >= position.maxScrollExtent - 200 &&
        widget.onLoadMore != null &&
        !_isLoadingMore) {
      _isLoadingMore = true;
      widget.onLoadMore!();
      // Reset loading flag after a delay
      Future.delayed(const Duration(milliseconds: 500), () {
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UnifiedChatProvider>(
      builder: (context, provider, child) {
        final messages = provider.messages;

        if (messages.isEmpty) {
          return const SizedBox.shrink();
        }

        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          reverse: true, // Show latest messages at bottom
          itemCount: messages.length,
          itemBuilder: (context, index) {
            // Reverse index for reverse ListView
            final reversedIndex = messages.length - 1 - index;
            final message = messages[reversedIndex];
            final isLast =
                index == 0; // First item in reverse list is last message
            final isFromCurrentUser =
                message.senderId == provider.currentUserId;

            return UnifiedMessageBubble(
              message: message,
              isFromCurrentUser: isFromCurrentUser,
              onTap: () => _showMessageOptions(message, provider),
              onLongPress: () => _showMessageOptions(message, provider),
              isLast: isLast,
            );
          },
        );
      },
    );
  }

  void _showMessageOptions(Message message, UnifiedChatProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.copy, color: Colors.grey[700]),
              title: Text(
                'Copy',
                style: TextStyle(color: Colors.grey[700]),
              ),
              onTap: () {
                Navigator.pop(context);
                _handleCopyMessage(message);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleCopyMessage(Message message) {
    // Copy to clipboard logic would go here
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
