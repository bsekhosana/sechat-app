import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/message.dart';
import '../providers/unified_chat_provider.dart';
import '../providers/chat_list_provider.dart';

import '../widgets/unified_virtualized_message_list.dart';
import '../widgets/unified_chat_input_area.dart';
import '../widgets/unified_chat_header.dart';
import '../widgets/unified_typing_indicator.dart';
import '/../core/utils/logger.dart';

/// Modern, unified chat screen with WhatsApp-like design and improved performance
class UnifiedChatScreen extends StatefulWidget {
  final String conversationId;
  final String recipientId;
  final String recipientName;
  final bool isOnline;

  const UnifiedChatScreen({
    super.key,
    required this.conversationId,
    required this.recipientId,
    required this.recipientName,
    required this.isOnline,
  });

  @override
  State<UnifiedChatScreen> createState() => _UnifiedChatScreenState();
}

class _UnifiedChatScreenState extends State<UnifiedChatScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();

  bool _isNearBottom = true;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupScrollListener();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
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
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeController.forward();
    _slideController.forward();
  }

  void _initializeChat(BuildContext context) {
    final chatProvider = context.read<UnifiedChatProvider>();

    chatProvider
        .initialize(
      conversationId: widget.conversationId,
      recipientId: widget.recipientId,
      recipientName: widget.recipientName,
    )
        .then((_) {
      // Mark user as entered chat screen
      chatProvider.markUserEnteredChatScreen();

      // Mark conversation as read
      chatProvider.markAsRead();

      // Update chat list
      final chatListProvider =
          Provider.of<ChatListProvider>(context, listen: false);
      chatListProvider.markConversationAsRead(widget.conversationId);

      // Register for real-time updates
      chatProvider.registerWithChatListProvider(chatListProvider);

      // Auto-scroll to bottom after initial load
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _scrollToBottom(animated: false);
        }
      });
    });
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        final position = _scrollController.position;
        // For reverse ListView, "bottom" (newest messages) is at pixels = 0
        final isNearBottom = position.pixels <= 100;

        // Only update state if the value actually changed to prevent unnecessary rebuilds
        if (isNearBottom != _isNearBottom) {
          _isNearBottom = isNearBottom;
          // Use a debounced setState to prevent excessive rebuilds
          Future.microtask(() {
            if (mounted) {
              setState(() {});
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    try {
      final chatProvider = context.read<UnifiedChatProvider>();
      chatProvider.markUserLeftChatScreen();

      final chatListProvider = context.read<ChatListProvider>();
      chatProvider.unregisterFromChatListProvider(chatListProvider);
    } catch (e) {
      // Ignore errors during dispose
    }

    _isInitialized = false;
    _fadeController.dispose();
    _slideController.dispose();
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Initialize chat after provider is created (only once)
    if (!_isInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isInitialized) {
          _isInitialized = true;
          _initializeChat(context);
        }
      });
    }

    return Scaffold(
      backgroundColor: Colors.white, // Match main screen background
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            // Header with recipient info and actions (no SafeArea, fills to top)
            _buildHeader(),

            // Connection status banner (when disconnected)
            _buildConnectionStatus(),

            // Messages list
            Expanded(
              child: _buildMessagesList(),
            ),

            // Typing indicator
            _buildTypingIndicator(),

            // Input area (no SafeArea, fills to bottom)
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  /// Build the header section
  Widget _buildHeader() {
    return Consumer<UnifiedChatProvider>(
      builder: (context, provider, child) {
        return UnifiedChatHeader(
          recipientName: provider.currentRecipientName ?? widget.recipientName,
          isOnline: provider.isRecipientOnline,
          lastSeen: provider.recipientLastSeen,
          onBackPressed: () => Navigator.pop(context),
          onMorePressed: () => _showChatOptions(provider),
        );
      },
    );
  }

  /// Build connection status banner
  Widget _buildConnectionStatus() {
    return Consumer<UnifiedChatProvider>(
      builder: (context, provider, child) {
        if (provider.isConnected) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.orange,
          child: Row(
            children: [
              const Icon(Icons.wifi_off, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              const Text(
                'No internet connection',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build the messages list
  Widget _buildMessagesList() {
    return Consumer<UnifiedChatProvider>(
      builder: (context, provider, child) {
        // Auto-scroll to bottom when new messages arrive
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkAndAutoScrollForNewMessages(provider);
        });

        if (provider.isLoading && provider.messages.isEmpty) {
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const CircularProgressIndicator(
                color: Color(0xFF25D366), // WhatsApp green
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Loading messages...',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey[700],
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                size: 64,
                color: Color(0xFF25D366), // WhatsApp green
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No messages yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.grey[800],
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Start the conversation by sending a message!',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600],
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
  Widget _buildMessagesListContent(UnifiedChatProvider provider) {
    // Check if we need to auto-scroll for new messages
    _checkAndAutoScrollForNewMessages(provider);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: RefreshIndicator(
          onRefresh: () async {
            await provider.refreshMessages();
          },
          child: UnifiedVirtualizedMessageList(
            scrollController: _scrollController,
            onLoadMore: provider.hasMoreMessages
                ? () => provider.loadMoreMessages()
                : null,
          ),
        ),
      ),
    );
  }

  /// Build typing indicator
  Widget _buildTypingIndicator() {
    return Consumer<UnifiedChatProvider>(
      builder: (context, provider, child) {
        if (!provider.isRecipientTyping) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: UnifiedTypingIndicator(
            typingUserName:
                provider.currentRecipientName ?? widget.recipientName,
          ),
        );
      },
    );
  }

  /// Build input area
  Widget _buildInputArea() {
    return Consumer<UnifiedChatProvider>(
      builder: (context, provider, child) {
        return UnifiedChatInputArea(
          onTextMessageSent: (text) => _sendTextMessage(text, provider),
          isTyping: (isTyping) => _updateTypingIndicator(isTyping, provider),
          isConnected: provider.isConnected,
        );
      },
    );
  }

  /// Send text message
  Future<void> _sendTextMessage(
      String text, UnifiedChatProvider provider) async {
    if (text.trim().isEmpty) return;

    try {
      await provider.sendTextMessage(text.trim());
      _textController.clear();

      // Update chat list
      try {
        final chatListProvider =
            Provider.of<ChatListProvider>(context, listen: false);
        chatListProvider.handleNewMessageArrival(
          messageId: provider.messages.last.id,
          senderId: _getCurrentUserId(provider),
          content: text.trim(),
          conversationId: provider.conversationId ?? widget.conversationId,
          timestamp: DateTime.now(),
          messageType: MessageType.text,
        );
      } catch (e) {
        Logger.warning('UnifiedChatScreen:  Could not update chat list: $e');
      }

      // Auto-scroll to bottom
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollToBottom();
      });
    } catch (e) {
      _showErrorSnackBar('Failed to send message: $e');
    }
  }

  /// Update typing indicator
  void _updateTypingIndicator(bool isTyping, UnifiedChatProvider provider) {
    provider.updateTypingIndicator(isTyping);
  }

  /// Check if we need to auto-scroll for new messages
  void _checkAndAutoScrollForNewMessages(UnifiedChatProvider provider) {
    if (provider.messages.isNotEmpty && _scrollController.hasClients) {
      // Auto-scroll if user is near bottom (near newest messages)
      if (_isNearBottom) {
        Future.delayed(const Duration(milliseconds: 100), () {
          _scrollToBottom();
        });
      }
    }
  }

  /// Scroll to bottom of messages (newest messages)
  void _scrollToBottom({bool animated = true}) {
    if (_scrollController.hasClients) {
      // For reverse ListView, "bottom" (newest messages) is at pixels = 0
      final currentPosition = _scrollController.position.pixels;

      if (currentPosition > 10) {
        if (animated) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(0.0);
        }
      }
    }
  }

  /// Show chat options
  void _showChatOptions(UnifiedChatProvider provider) {
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
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
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
      leading: Icon(icon, color: Colors.grey[700]),
      title: Text(
        title,
        style: TextStyle(color: Colors.grey[700]),
      ),
      onTap: onTap,
    );
  }

  /// Show search dialog
  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          'Search Messages',
          style: TextStyle(color: Colors.grey[800]),
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
                Logger.info(' Searching for: $value');
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Search functionality will be implemented in future updates',
              style: TextStyle(
                color: Colors.grey[600],
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
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
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
        backgroundColor: Colors.white,
        title: Text(
          'Delete Chat?',
          style: TextStyle(color: Colors.grey[800]),
        ),
        content: Text(
          'This will permanently delete this chat conversation. This action cannot be undone.',
          style: TextStyle(color: Colors.grey[600]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Logger.info(' Delete chat confirmed');
              Navigator.pop(context);
            },
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
  String _getCurrentUserId(UnifiedChatProvider provider) {
    return provider.currentUserId ?? 'unknown';
  }
}
