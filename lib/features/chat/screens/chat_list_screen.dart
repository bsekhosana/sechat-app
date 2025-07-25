import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:share_plus/share_plus.dart';
import '../../../shared/providers/auth_provider.dart';
import '../providers/session_chat_provider.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/profile_icon_widget.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/network_service.dart';
import 'chat_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:sechat_app/features/chat/providers/chat_provider.dart';
import 'package:sechat_app/features/chat/screens/chat_screen.dart';
import 'package:sechat_app/shared/widgets/profile_icon_widget.dart';
import 'package:sechat_app/shared/widgets/invite_user_widget.dart';
import 'package:sechat_app/core/services/session_service.dart';
import 'package:sechat_app/shared/models/user.dart';
import 'package:sechat_app/core/services/notification_service.dart';
import 'package:sechat_app/shared/widgets/connection_status_widget.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = context.read<ChatProvider>();
      chatProvider.loadChats();
      // Refresh online status after loading chats
      chatProvider.refreshOnlineStatus();
    });
  }

  void _openChat(Chat chat) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
  }

  void _shareApp() {
    const String shareText = '''
🔒 Join me on SeChat - Private & Secure Messaging! 

✨ Features:
• End-to-end encrypted conversations
• Anonymous messaging
• No personal data required
• Clean, modern interface

Download now and let's chat securely!

#SeChat #PrivateMessaging #Encrypted
    ''';

    Share.share(
      shareText,
      subject: 'Join me on SeChat - Secure Messaging App',
    );
  }

  void _showChatOptions(BuildContext context, Chat chat, User? otherUser,
      String displayUsername) {
    final otherUserId =
        otherUser?.id ?? chat.getOtherUserId('current_user_placeholder');

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2C2C2C),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Options for $displayUsername',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.orange),
              title: const Text(
                'Remove Chats',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Delete all chats and messages',
                style: TextStyle(color: Colors.white70),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _removeUserChats(otherUserId, displayUsername);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: const Text(
                'Block User',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Block and remove all communication',
                style: TextStyle(color: Colors.white70),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _blockUser(otherUserId, displayUsername);
              },
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _blockUser(String userId, String username) async {
    final confirmed = await _showBlockUserActionSheet(context, username);

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
          // Refresh chat list
          context.read<ChatProvider>().loadChats();
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

  Future<bool?> _showBlockUserActionSheet(
      BuildContext context, String username) async {
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
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Are you sure you want to block $username? This will remove all chats and messages between you and prevent future communication.',
                  style: const TextStyle(
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

  Future<void> _removeUserChats(String userId, String username) async {
    final confirmed = await _showRemoveChatsActionSheet(context, username);

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
          // Refresh chat list
          context.read<ChatProvider>().loadChats();
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

  Future<bool?> _showRemoveChatsActionSheet(
      BuildContext context, String username) async {
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
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Are you sure you want to remove all chats and messages with $username? This action cannot be undone.',
                  style: const TextStyle(
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
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // Header matching the designs
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _shareApp,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.share,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: InviteUserWidget(),
                  ),
                  const SizedBox(width: 12),
                  const ProfileIconWidget(),
                ],
              ),
            ),

            // Tab selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // Container(
                  //   padding: const EdgeInsets.symmetric(
                  //       horizontal: 24, vertical: 12),
                  //   decoration: BoxDecoration(
                  //     color: const Color(0xFFFF6B35),
                  //     borderRadius: BorderRadius.circular(20),
                  //   ),
                  //   child: const Text(
                  //     'Messages',
                  //     style: TextStyle(
                  //       color: Colors.white,
                  //       fontSize: 16,
                  //       fontWeight: FontWeight.w600,
                  //     ),
                  //   ),
                  // ),
                  // const SizedBox(width: 16),
                  // Container(
                  //   padding: const EdgeInsets.symmetric(
                  //       horizontal: 24, vertical: 12),
                  //   child: Text(
                  //     'People',
                  //     style: TextStyle(
                  //       color: Colors.white.withOpacity(0.5),
                  //       fontSize: 16,
                  //       fontWeight: FontWeight.w400,
                  //     ),
                  //   ),
                  // ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Chat list
            Expanded(
              child: Consumer<ChatProvider>(
                builder: (context, chatProvider, child) {
                  if (chatProvider.isLoading) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF6B35),
                      ),
                    );
                  }

                  if (chatProvider.error != null) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Color(0xFFFF6B35),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Error Loading Chats',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            NetworkService.instance.getUserFriendlyErrorMessage(
                                chatProvider.error),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              chatProvider.clearError();
                              chatProvider.loadChats();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6B35),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }

                  if (chatProvider.chats.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline,
                            size: 64,
                            color: Color(0xFFFF6B35),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No Chats Yet',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start a conversation by searching for users',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 24),
                          // ElevatedButton.icon(
                          //   onPressed: () {
                          //     Navigator.of(context).pop();
                          //   },
                          //   icon: const Icon(Icons.search),
                          //   label: const Text('Search Users'),
                          //   style: ElevatedButton.styleFrom(
                          //     backgroundColor: const Color(0xFFFF6B35),
                          //     foregroundColor: Colors.white,
                          //   ),
                          // ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      await chatProvider.manualRefreshOnlineStatus();
                    },
                    color: const Color(0xFFFF6B35),
                    backgroundColor: const Color(0xFF121212),
                    child: AnimationLimiter(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: chatProvider.chats.length,
                        itemBuilder: (context, index) {
                          final chat = chatProvider.chats[index];
                          final otherUserId = chat.getOtherUserId(
                            context.read<AuthProvider>().currentUser?.id ?? '',
                          );
                          final otherUser =
                              chatProvider.getChatUser(otherUserId);

                          // Get username from chat data if user not found
                          String displayUsername = 'Unknown User';
                          if (otherUser != null) {
                            displayUsername = otherUser.username;
                          } else if (chat.otherUser != null &&
                              chat.otherUser!.containsKey('username')) {
                            displayUsername = chat.otherUser!['username'];
                          }

                          // Get online status
                          bool isOnline = false;
                          if (otherUser != null) {
                            // Use effective online status that considers typing state
                            isOnline = chatProvider
                                .getEffectiveOnlineStatus(otherUserId);
                          } else if (chat.otherUser != null &&
                              chat.otherUser!.containsKey('is_online')) {
                            isOnline = chat.otherUser!['is_online'] ?? false;
                          }

                          return AnimationConfiguration.staggeredList(
                            position: index,
                            duration: const Duration(milliseconds: 375),
                            child: SlideAnimation(
                              verticalOffset: 50.0,
                              child: FadeInAnimation(
                                child: GestureDetector(
                                  onLongPress: () => _showChatOptions(context,
                                      chat, otherUser, displayUsername),
                                  child: _ChatCard(
                                    chat: chat,
                                    otherUser: otherUser,
                                    displayUsername: displayUsername,
                                    isOnline: isOnline,
                                    onTap: () => _openChat(chat),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatCard extends StatelessWidget {
  final Chat chat;
  final User? otherUser;
  final String displayUsername;
  final bool isOnline;
  final VoidCallback onTap;

  const _ChatCard(
      {required this.chat,
      this.otherUser,
      required this.displayUsername,
      required this.isOnline,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFFFF6B35),
              child: Text(
                displayUsername.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            if (isOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: const Color(0xFF121212), width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          displayUsername,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        subtitle: Consumer<ChatProvider>(
          builder: (context, chatProvider, child) {
            // Check if the other user is typing
            final otherUserId = chat.getOtherUserId(
              context.read<AuthProvider>().currentUser?.id ?? '',
            );
            final isTyping = chatProvider.isUserTyping(otherUserId);

            if (isTyping) {
              return Text(
                'typing...',
                style: TextStyle(
                  color: const Color(0xFFFF6B35),
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              );
            } else {
              // Get last message content
              final lastMessageContent = _getLastMessageContent(chat);
              final currentUserId =
                  context.read<AuthProvider>().currentUser?.id ?? '';
              final lastMessageSenderId =
                  chat.lastMessage?['sender_id']?.toString();
              final isLastMessageFromMe = lastMessageSenderId == currentUserId;

              return Row(
                children: [
                  // Show tick status only for messages from other users
                  if (!isLastMessageFromMe && lastMessageContent.isNotEmpty)
                    _buildMessageStatus(
                        chat.lastMessage?['status']?.toString() ?? 'sent'),
                  Expanded(
                    child: Text(
                      lastMessageContent.isNotEmpty
                          ? lastMessageContent
                          : 'No messages yet',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            }
          },
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatTime(chat.lastMessageAt ?? chat.updatedAt),
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 4),
            // Unread count badge
            Consumer<ChatProvider>(
              builder: (context, chatProvider, child) {
                final unreadCount = chatProvider.getUnreadCount(chat.id);
                if (unreadCount > 0) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);

    if (messageDate == today) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return '${time.day}/${time.month}/${time.year}';
    }
  }

  String _getLastMessageContent(Chat chat) {
    if (chat.lastMessage != null && chat.lastMessage!.containsKey('content')) {
      return chat.lastMessage!['content'] as String;
    }
    return '';
  }

  Widget _buildMessageStatus(String status) {
    IconData icon;
    Color color;

    switch (status) {
      case 'sent':
        icon = Icons.check;
        color = Colors.grey;
        break;
      case 'delivered':
        icon = Icons.done_all;
        color = Colors.grey;
        break;
      case 'read':
        icon = Icons.done_all;
        color = const Color(0xFF2196F3);
        break;
      default:
        icon = Icons.check;
        color = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Icon(
        icon,
        size: 14,
        color: color,
      ),
    );
  }
}
