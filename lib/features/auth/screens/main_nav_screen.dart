import 'package:flutter/material.dart';
import '../../chat/screens/chat_list_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../invitations/screens/invitations_screen.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../search/providers/search_provider.dart';
import 'package:provider/provider.dart';
import '../../invitations/providers/invitation_provider.dart';
import '../../../core/services/notification_service.dart';

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
  OverlayEntry? _searchOverlayEntry;
  TextEditingController? _searchController;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _handleNotificationDeepLink();
    _setupNotificationHandler();
  }

  void _handleNotificationDeepLink() {
    if (widget.notificationPayload != null) {
      final payload = NotificationService.instance
          .parseNotificationPayload(widget.notificationPayload);
      if (payload != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _navigateToInvitationsTab(payload);
        });
      }
    }
  }

  void _setupNotificationHandler() {
    NotificationService.instance.setOnNotificationTap((payload) {
      if (payload != null) {
        final parsedPayload =
            NotificationService.instance.parseNotificationPayload(payload);
        if (parsedPayload != null) {
          _navigateToInvitationsTab(parsedPayload);
        }
      }
    });
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
    SettingsScreen(), // Settings
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void showSearchOverlay(TextEditingController controller) {
    if (_searchOverlayEntry != null) return;
    _searchController = controller;
    _searchOverlayEntry = OverlayEntry(
      builder: (context) {
        final searchProvider = context.read<SearchProvider>();
        final invitationProvider = context.read<InvitationProvider>();
        final showResults = controller.text.isNotEmpty &&
            searchProvider.searchResults.isNotEmpty;
        final query = controller.text;
        if (!showResults) return const SizedBox.shrink();
        return GestureDetector(
          onTap: hideSearchOverlay,
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(color: Colors.transparent),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: const EdgeInsets.only(top: 90),
                    width: MediaQuery.of(context).size.width * 0.8,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 8),
                      itemCount: searchProvider.searchResults.length,
                      itemBuilder: (context, index) {
                        final user = searchProvider.searchResults[index];
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF232323),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFFF6B35),
                              child: Text(
                                user.username.isNotEmpty
                                    ? user.username[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: _buildHighlightedText(user.username, query),
                            subtitle: Text(
                              'Joined ${_formatJoined(user.createdAt)}',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 13),
                            ),
                            trailing: user.alreadyInvited
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'Invited',
                                      style: TextStyle(
                                        color: Color(0xFFFF6B35),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF6B35),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: IconButton(
                                      icon: const Icon(Icons.person_add,
                                          color: Colors.white, size: 20),
                                      onPressed: () async {
                                        final confirmed =
                                            await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            backgroundColor:
                                                const Color(0xFF2C2C2C),
                                            title: Text('Send Invitation',
                                                style: TextStyle(
                                                    color: Colors.white)),
                                            content: Text(
                                                'Are you sure you want to send an invitation to ${user.username}?',
                                                style: TextStyle(
                                                    color: Colors.white70)),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context)
                                                        .pop(false),
                                                child: Text('Cancel',
                                                    style: TextStyle(
                                                        color: Colors.white70)),
                                              ),
                                              ElevatedButton(
                                                onPressed: () =>
                                                    Navigator.of(context)
                                                        .pop(true),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      const Color(0xFFFF6B35),
                                                  foregroundColor: Colors.white,
                                                ),
                                                child: const Text('Send'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmed == true) {
                                          final success =
                                              await invitationProvider
                                                  .sendInvitation(
                                            recipientId: user.id,
                                            message:
                                                'Hi! I\'d like to chat with you on SeChat.',
                                          );
                                          if (success) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    'Invitation sent to ${user.username}!'),
                                                backgroundColor:
                                                    const Color(0xFF4CAF50),
                                              ),
                                            );
                                          } else {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(invitationProvider
                                                        .error ??
                                                    'Failed to send invitation'),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                          hideSearchOverlay();
                                        }
                                      },
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_searchOverlayEntry!);
  }

  void hideSearchOverlay() {
    _searchOverlayEntry?.remove();
    _searchOverlayEntry = null;
    _searchController?.clear();
    _searchController = null;
    FocusScope.of(context).unfocus();
    context.read<SearchProvider>().clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: Container(
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, FontAwesomeIcons.comments, 'Chats'),
                _buildNavItem(1, FontAwesomeIcons.envelope, 'Invitations'),
                _buildNavItem(2, FontAwesomeIcons.gear, 'Settings'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;

    return Consumer<InvitationProvider>(
      builder: (context, invitationProvider, child) {
        final showBadge = index == 1 && invitationProvider.totalBadgeCount > 0;

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
                if (showBadge)
                  Positioned(
                    top: -2,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF1E1E1E), width: 1),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      child: Text(
                        invitationProvider.totalBadgeCount > 99
                            ? '99+'
                            : invitationProvider.totalBadgeCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
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
}
