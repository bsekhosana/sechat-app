import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_conversation.dart';
import '../providers/chat_list_provider.dart';
import '../widgets/chat_list_item.dart';
import '../widgets/chat_search_bar.dart';
import '../../../shared/widgets/connection_status_widget.dart';
import '../../../shared/widgets/key_exchange_request_dialog.dart';
import '../screens/chat_screen.dart';

/// Main screen for displaying the list of chat conversations
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeChatList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatListProvider>().onScreenVisible();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh conversations when dependencies change (e.g., when returning to screen)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ChatListProvider>().onScreenVisible();
      }
    });
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

  void _initializeChatList() {
    // Initialize the chat list provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatListProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Header with connection status
            _buildHeader(),

            // Search bar
            _buildSearchBar(),

            // Chat list
            Expanded(
              child: _buildChatList(),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  /// Build the header section
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Consumer<ChatListProvider>(
                  builder: (context, provider, child) {
                    final totalConversations = provider.conversations.length;
                    final unreadCount = provider.totalUnreadCount;

                    if (totalConversations == 0) {
                      return Text(
                        'Send key exchange to start chatting',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      );
                    }

                    return Text(
                      '$totalConversations conversation${totalConversations == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Connection status
          const ConnectionStatusWidget(),
        ],
      ),
    );
  }

  /// Build the search bar
  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ChatSearchBar(
        onSearchChanged: (query) {
          context.read<ChatListProvider>().searchConversations(query);
        },
        onSearchCleared: () {
          context.read<ChatListProvider>().clearSearch();
        },
      ),
    );
  }

  /// Build the chat list
  Widget _buildChatList() {
    return Consumer<ChatListProvider>(
      builder: (context, provider, child) {
        if (provider.hasError) {
          return _buildErrorState(provider);
        }

        if (provider.isLoading) {
          return _buildLoadingState();
        }

        if (provider.conversations.isEmpty) {
          return _buildEmptyState();
        }

        return _buildConversationList(provider);
      },
    );
  }

  /// Build loading state
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            color: Color(0xFFFF6B35),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading conversations...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This should only take a few seconds',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 16),
          // Debug button to force reset loading state
          OutlinedButton(
            onPressed: () {
              context.read<ChatListProvider>().forceResetLoading();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[600],
              side: BorderSide(color: Colors.grey[400]!),
            ),
            child: const Text('Debug: Reset Loading'),
          ),
          const SizedBox(height: 8),
          // Debug button to force database recreation
          OutlinedButton(
            onPressed: () {
              context.read<ChatListProvider>().forceDatabaseRecreation();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red[600],
              side: BorderSide(color: Colors.red[400]!),
            ),
            child: const Text('Debug: Recreate Database'),
          ),
        ],
      ),
    );
  }

  /// Build error state
  Widget _buildErrorState(ChatListProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load conversations',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            provider.errorMessage ??
                'An error occurred while loading conversations',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => provider.retry(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B35),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Retry'),
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
            color: Colors.grey[600],
          ),
          const SizedBox(height: 16),
          Text(
            'No conversations yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Send a key exchange request to start a new conversation',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          // const SizedBox(height: 34),
        ],
      ),
    );
  }

  /// Build conversation list
  Widget _buildConversationList(ChatListProvider provider) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: RefreshIndicator(
          onRefresh: () async {
            await provider.refreshConversations();
          },
          child: ListView.builder(
            padding:
                const EdgeInsets.only(bottom: 24, left: 24, right: 24, top: 24),
            itemCount: provider.filteredConversations.length,
            itemBuilder: (context, index) {
              final conversation = provider.filteredConversations[index];
              final isLast = index == provider.filteredConversations.length - 1;

              return ChatListItem(
                conversation: conversation,
                onTap: () => _openChat(conversation),
                onLongPress: () => _showConversationOptions(conversation),
                onDelete: () => _deleteConversation(conversation),
                isLast: isLast,
              );
            },
          ),
        ),
      ),
    );
  }

  /// Build floating action button
  Widget _buildFloatingActionButton() {
    return FloatingActionButton(
      onPressed: _startNewChat,
      backgroundColor: const Color(0xFFFF6B35),
      foregroundColor: Colors.white,
      elevation: 4,
      tooltip: 'Send key exchange request',
      child: const Icon(Icons.chat_bubble_outline),
    );
  }

  /// Open chat conversation
  void _openChat(ChatConversation conversation) {
    // Use recipientId if available, otherwise fall back to participant2Id
    // This handles cases where older conversations might not have recipientId populated
    final effectiveRecipientId =
        conversation.recipientId ?? conversation.participant2Id ?? 'unknown';

    // Use recipientName if available, otherwise fall back to displayName
    final effectiveRecipientName = conversation.recipientName ??
        conversation.displayName ??
        'Unknown User';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          conversationId: conversation.id,
          recipientId: effectiveRecipientId,
          recipientName: effectiveRecipientName,
        ),
      ),
    );
  }

  /// Start new chat
  void _startNewChat() {
    // Open key exchange request dialog to start a new conversation
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const KeyExchangeRequestDialog(),
    );
  }

  /// Show conversation options
  void _showConversationOptions(ChatConversation conversation) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _buildConversationOptions(conversation),
    );
  }

  /// Build conversation options bottom sheet
  Widget _buildConversationOptions(ChatConversation conversation) {
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

          // Conversation info
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                (conversation.recipientName?.isNotEmpty ?? false)
                    ? conversation.recipientName![0].toUpperCase()
                    : '?',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              conversation.recipientName ?? 'Unknown User',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            subtitle: Text(
              'Messages',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),

          const Divider(),

          // Options
          ListTile(
            leading: Icon(
              Icons.notifications,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: Text(
              conversation.isMuted
                  ? 'Unmute notifications'
                  : 'Mute notifications',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            onTap: () {
              Navigator.pop(context);
              _toggleMuteNotifications(conversation);
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
              _blockUser(conversation);
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
              _deleteConversation(conversation);
            },
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Toggle mute notifications for conversation
  void _toggleMuteNotifications(ChatConversation conversation) {
    context.read<ChatListProvider>().toggleMuteNotifications(conversation.id);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          conversation.isMuted
              ? 'Notifications unmuted for ${conversation.recipientName}'
              : 'Notifications muted for ${conversation.recipientName}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Block user
  void _blockUser(ChatConversation conversation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content: Text(
          'Are you sure you want to block ${conversation.recipientName}? '
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
              context.read<ChatListProvider>().blockUser(conversation.id);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text('${conversation.recipientName} has been blocked'),
                  duration: const Duration(seconds: 2),
                ),
              );
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
  void _deleteConversation(ChatConversation conversation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: Text(
          'Are you sure you want to delete the conversation with ${conversation.recipientName}? '
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
              context
                  .read<ChatListProvider>()
                  .deleteConversation(conversation.id);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Conversation with ${conversation.recipientName} deleted'),
                  duration: const Duration(seconds: 2),
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
}
