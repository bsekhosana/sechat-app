import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sechat_app/features/chat/providers/optimized_chat_list_provider.dart';
import 'package:sechat_app/features/chat/models/chat_conversation.dart';
import 'package:sechat_app/features/chat/widgets/optimized_chat_list_item.dart';
import 'package:sechat_app/features/chat/screens/optimized_chat_screen.dart';
import 'package:sechat_app/shared/widgets/key_exchange_request_dialog.dart';

/// Optimized Chat List Screen
/// Clean, focused chat list with real-time updates
class OptimizedChatListScreen extends StatefulWidget {
  const OptimizedChatListScreen({super.key});

  @override
  State<OptimizedChatListScreen> createState() =>
      _OptimizedChatListScreenState();
}

class _OptimizedChatListScreenState extends State<OptimizedChatListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Initialize the provider when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OptimizedChatListProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: _buildAppBar(),
      body: _buildBody(),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  /// Build app bar with search functionality
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Chats'),
      elevation: 2,
      backgroundColor: Colors.white,
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: _showSearchBar,
        ),
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: _showMoreOptions,
        ),
      ],
    );
  }

  /// Build main body content
  Widget _buildBody() {
    return Consumer<OptimizedChatListProvider>(
      builder: (context, provider, child) {
        print(
            '📱 OptimizedChatListScreen: 🔄 Rebuilding UI - Loading: ${provider.isLoading}, Conversations: ${provider.conversations.length}, Error: ${provider.error}');

        if (provider.isLoading) {
          print('📱 OptimizedChatListScreen: 🔄 Showing loading indicator');
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (provider.error != null) {
          print('📱 OptimizedChatListScreen: 🔄 Showing error widget');
          return _buildErrorWidget(provider.error!);
        }

        if (provider.conversations.isEmpty) {
          print('📱 OptimizedChatListScreen: 🔄 Showing empty state');
          return _buildEmptyState();
        }

        print('📱 OptimizedChatListScreen: 🔄 Showing conversations list');
        return RefreshIndicator(
          onRefresh: provider.refresh,
          child: _buildConversationsList(provider),
        );
      },
    );
  }

  /// Build conversations list
  Widget _buildConversationsList(OptimizedChatListProvider provider) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8.0),
      itemCount: provider.conversations.length,
      itemBuilder: (context, index) {
        final conversation = provider.conversations[index];
        return OptimizedChatListItem(
          conversation: conversation,
          onTap: () => _openChat(conversation),
          onLongPress: () => _showConversationOptions(conversation),
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
            'Error loading chats',
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
              context.read<OptimizedChatListProvider>().refresh();
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
            'No conversations yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a conversation to begin chatting',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[500],
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Build floating action button
  Widget _buildFloatingActionButton() {
    return FloatingActionButton(
      onPressed: _startNewConversation,
      backgroundColor: const Color(0xFFFF6B35),
      foregroundColor: Colors.white,
      elevation: 4,
      tooltip: 'Send key exchange request',
      child: const Icon(Icons.chat_bubble_outline),
    );
  }

  /// Show search bar
  void _showSearchBar() {
    showSearch(
      context: context,
      delegate: _ChatSearchDelegate(
        context.read<OptimizedChatListProvider>(),
      ),
    );
  }

  /// Show more options menu
  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _buildMoreOptionsSheet(),
    );
  }

  /// Build more options bottom sheet
  Widget _buildMoreOptionsSheet() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Refresh'),
            onTap: () {
              Navigator.pop(context);
              context.read<OptimizedChatListProvider>().refresh();
            },
          ),
          ListTile(
            leading: const Icon(Icons.clear_all),
            title: const Text('Clear All'),
            onTap: () {
              Navigator.pop(context);
              _showClearAllConfirmation();
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Chat Settings'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Navigate to chat settings
            },
          ),
        ],
      ),
    );
  }

  /// Show clear all confirmation dialog
  void _showClearAllConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Chats'),
        content: const Text(
          'This will delete all conversations and messages. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<OptimizedChatListProvider>().clearAllData();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  /// Open chat conversation
  void _openChat(ChatConversation conversation) {
    // Mark conversation as read
    context
        .read<OptimizedChatListProvider>()
        .markConversationAsRead(conversation.id);

    // Navigate to chat screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OptimizedChatScreen(
          conversationId: conversation.id,
          recipientName: conversation.displayName ?? 'Unknown',
        ),
      ),
    );
  }

  /// Show conversation options
  void _showConversationOptions(ChatConversation conversation) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _buildConversationOptionsSheet(conversation),
    );
  }

  /// Build conversation options bottom sheet
  Widget _buildConversationOptionsSheet(ChatConversation conversation) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.pin),
            title: Text(conversation.isPinned ? 'Unpin' : 'Pin'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement pin/unpin functionality
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_off),
            title: const Text('Mute Notifications'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement mute functionality
            },
          ),
          ListTile(
            leading: const Icon(Icons.archive),
            title: const Text('Archive'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement archive functionality
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _showDeleteConfirmation(conversation);
            },
          ),
        ],
      ),
    );
  }

  /// Show delete confirmation dialog
  void _showDeleteConfirmation(ChatConversation conversation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: Text(
          'Are you sure you want to delete the conversation with ${conversation.displayName}? This action cannot be undone.',
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
                  .read<OptimizedChatListProvider>()
                  .deleteConversation(conversation.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Start new conversation
  void _startNewConversation() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const KeyExchangeRequestDialog(),
    );
  }
}

/// Chat search delegate for search functionality
class _ChatSearchDelegate extends SearchDelegate<String> {
  final OptimizedChatListProvider _provider;

  _ChatSearchDelegate(this._provider);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, '');
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    if (query.isEmpty) {
      return const Center(
        child: Text('Start typing to search conversations'),
      );
    }

    // Filter conversations based on search query
    final filteredConversations = _provider.conversations.where((conversation) {
      return (conversation.displayName
                  ?.toLowerCase()
                  .contains(query.toLowerCase()) ??
              false) ||
          (conversation.lastMessagePreview
                  ?.toLowerCase()
                  .contains(query.toLowerCase()) ??
              false);
    }).toList();

    if (filteredConversations.isEmpty) {
      return Center(
        child: Text('No conversations found for "$query"'),
      );
    }

    return ListView.builder(
      itemCount: filteredConversations.length,
      itemBuilder: (context, index) {
        final conversation = filteredConversations[index];
        return ListTile(
          title: Text(conversation.displayName ?? 'Unknown'),
          subtitle: conversation.lastMessagePreview != null
              ? Text(
                  conversation.lastMessagePreview!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          trailing: conversation.unreadCount > 0
              ? Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    conversation.unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                )
              : null,
          onTap: () {
            // Navigate to chat screen
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => OptimizedChatScreen(
                  conversationId: conversation.id,
                  recipientName: conversation.displayName ?? 'Unknown',
                ),
              ),
            );
          },
        );
      },
    );
  }
}
