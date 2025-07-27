import 'package:flutter/material.dart';
import '../../chat/screens/chat_list_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../invitations/screens/invitations_screen.dart';
import '../../notifications/screens/notifications_screen.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../search/providers/search_provider.dart';
import 'package:provider/provider.dart';
import '../../invitations/providers/invitation_provider.dart';
import '../../notifications/providers/notification_provider.dart';
import '../../../core/services/simple_notification_service.dart';
import '../../chat/providers/chat_provider.dart';
import '../../../core/services/network_service.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/connection_status_widget.dart';
import '../../../core/services/session_service.dart';

class MainNavScreen extends StatefulWidget {
  final int initialIndex;
  final String? notificationPayload;

  static final GlobalKey<_MainNavScreenState> globalKey =
      GlobalKey<_MainNavScreenState>();

  MainNavScreen({
    Key? key,
    this.initialIndex = 0,
    this.notificationPayload,
  }) : super(key: globalKey);

  static _MainNavScreenState? of(BuildContext context) =>
      globalKey.currentState;

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _handleNotificationDeepLink();
    _setupNotificationHandler();
    _loadAllData();
  }

  void _loadAllData() {
    print('📱 MainNavScreen: Loading all local data on app startup...');

    // Load all data - these methods handle their own async operations
    context.read<InvitationProvider>().loadInvitations();
    context.read<NotificationProvider>().loadNotifications();
    context.read<ChatProvider>().loadChats();

    print('📱 MainNavScreen: ✅ All local data loading initiated');
  }

  void _handleNotificationDeepLink() {
    if (widget.notificationPayload != null) {
      // Handle notification payload for deep linking
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToInvitationsTab({'tab': 'received'});
      });
    }
  }

  void _setupNotificationHandler() {
    // Set up notification handling for deep linking
    print('🔔 MainNavScreen: Notification handler setup complete');
  }

  void _navigateToInvitationsTab(Map<String, dynamic> payload) {
    setState(() {
      _selectedIndex = 1; // Invitations tab
    });

    // Mark appropriate invitations as read based on the payload
    final invitationProvider = context.read<InvitationProvider>();
    if (payload['tab'] == 'received') {
      invitationProvider.markReceivedInvitationsAsRead();
    } else if (payload['tab'] == 'sent') {
      invitationProvider.markSentInvitationsAsRead();
    }
  }

  static final List<Widget> _screens = <Widget>[
    ChatListScreen(), // Home - shows chat feed
    InvitationsScreen(), // Invitations
    NotificationsScreen(), // Notifications
    SettingsScreen(), // Settings
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    // Track when user enters/exits invitations screen
    final invitationProvider = context.read<InvitationProvider>();
    if (index == 1) {
      // User entered invitations tab
      invitationProvider.setOnInvitationsScreen(true);
    } else {
      // User left invitations tab
      invitationProvider.setOnInvitationsScreen(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Connection status banner
          ConnectionStatusWidget(),
          // Bottom navigation bar
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              border: Border(
                top: BorderSide(
                  color: Color(0xFF404040),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              child: Container(
                height: 65,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(0, FontAwesomeIcons.comments, 'Chats'),
                    _buildNavItem(1, FontAwesomeIcons.envelope, 'Invitations'),
                    _buildNavItem(2, FontAwesomeIcons.bell, 'Notifications'),
                    _buildNavItem(3, FontAwesomeIcons.gear, 'Settings'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;

    return Consumer3<InvitationProvider, ChatProvider, NotificationProvider>(
      builder: (context, invitationProvider, chatProvider, notificationProvider,
          child) {
        final showInvitationBadge =
            index == 1 && invitationProvider.hasUnreadInvitations;
        final showChatBadge = index == 0 && chatProvider.hasUnreadMessages;
        final showNotificationBadge =
            index == 2 && notificationProvider.unreadCount > 0;

        return GestureDetector(
          onTap: () => _onItemTapped(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFFF6B35) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FaIcon(
                      icon,
                      color:
                          isSelected ? Colors.white : const Color(0xFF666666),
                      size: 18,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(
                        color:
                            isSelected ? Colors.white : const Color(0xFF666666),
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                if (showInvitationBadge ||
                    showChatBadge ||
                    showNotificationBadge)
                  Positioned(
                    top: -2,
                    right: 4,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2196F3), // Blue color
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFF1E1E1E), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2196F3).withOpacity(0.6),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) {
      return Text(text,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600));
    }
    final String lowerText = text.toLowerCase();
    final String lowerQuery = query.toLowerCase();
    if (!lowerText.contains(lowerQuery)) {
      return Text(text,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600));
    }
    final List<TextSpan> spans = [];
    int start = 0;
    while (start < text.length) {
      final int index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(
            text: text.substring(start),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(
            text: text.substring(start, index),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: const TextStyle(
          backgroundColor: Color(0xFFFF6B35),
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ));
      start = index + query.length;
    }
    return RichText(text: TextSpan(children: spans));
  }

  String _formatJoined(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays >= 1) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    } else if (diff.inHours >= 1) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    } else if (diff.inMinutes >= 1) {
      return '${diff.inMinutes} min${diff.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'just now';
    }
  }

  Future<bool?> _showInvitationActionSheet(
    BuildContext context,
    User user,
    String actionText,
  ) async {
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
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  actionText,
                  style: const TextStyle(
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
                  user.hasDeclinedInvitation || user.hasDeletedInvitation
                      ? 'Send a new invitation to ${user.username}?'
                      : 'Send an invitation to ${user.username}?',
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
                          backgroundColor: user.hasDeclinedInvitation ||
                                  user.hasDeletedInvitation
                              ? const Color(0xFF2196F3)
                              : const Color(0xFFFF6B35),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(user.hasDeclinedInvitation ||
                                user.hasDeletedInvitation
                            ? 'Reinvite'
                            : 'Send'),
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
}
