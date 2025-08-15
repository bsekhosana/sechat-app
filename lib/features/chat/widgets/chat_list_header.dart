import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_list_provider.dart';
import '../../../shared/widgets/app_icon.dart';
import '../../../shared/widgets/connection_status_widget.dart';

/// Header widget for the chat list screen
class ChatListHeader extends StatelessWidget {
  final VoidCallback onSettingsPressed;
  final VoidCallback? onSearchPressed;
  final String? title;
  final bool showSearchButton;

  const ChatListHeader({
    super.key,
    required this.onSettingsPressed,
    this.onSearchPressed,
    this.title,
    this.showSearchButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // App icon and title
          Expanded(
            child: Row(
              children: [
                const AppIcon(widthPerc: 0.08), // 8% of screen width
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title ?? 'Chats',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                    ),
                    const SizedBox(height: 2),
                    Consumer<ChatListProvider>(
                      builder: (context, provider, child) {
                        final totalConversations =
                            provider.conversations.length;
                        final unreadCount = provider.totalUnreadCount;

                        if (totalConversations == 0) {
                          return Text(
                            'No conversations yet',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          );
                        }

                        return Text(
                          '$totalConversations conversation${totalConversations == 1 ? '' : 's'}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Connection status
          const ConnectionStatusWidget(),

          // Search button
          if (showSearchButton)
            IconButton(
              onPressed: onSearchPressed,
              icon: Icon(
                Icons.search,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              tooltip: 'Search conversations',
            ),

          // Settings button
          IconButton(
            onPressed: onSettingsPressed,
            icon: Icon(
              Icons.settings,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}
