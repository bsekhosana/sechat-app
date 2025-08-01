import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../notifications/providers/notification_provider.dart';
import '../../../core/services/simple_notification_service.dart';
import '../../../core/services/network_service.dart';
import '../../../core/services/indicator_service.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/connection_status_widget.dart';
import '../../../shared/widgets/invite_user_widget.dart';
import '../../../shared/widgets/profile_icon_widget.dart';
import '../../../shared/widgets/invite_contact_dialog.dart';
import '../../../core/services/se_session_service.dart';
import '../../invitations/screens/invitations_screen.dart';
import '../../notifications/screens/notifications_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../chat/screens/chat_list_screen.dart';

class MainNavScreen extends StatefulWidget {
  final Map<String, dynamic>? notificationPayload;

  const MainNavScreen({
    Key? key,
    this.notificationPayload,
  }) : super(key: key);

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _selectedIndex = 0;
  final IndicatorService _indicatorService = IndicatorService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllData();
      _checkIndicators();
    });
  }

  void _checkIndicators() async {
    await _indicatorService.checkForNewItems();
  }

  void _loadAllData() {
    // Load notifications only (other providers temporarily disabled)
    context.read<NotificationProvider>().loadNotifications();
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

  void _handleNotificationDeepLink() {
    if (widget.notificationPayload != null) {
      // Handle notification payload for deep linking
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _selectedIndex = 2; // Notifications tab
        });
      });
    }
  }

  void _setupNotificationHandler() {
    // Set up notification handling for deep linking
  }

  static final List<Widget> _screens = <Widget>[
    const ChatListScreen(), // Chats
    InvitationsScreen(), // Invitations
    NotificationsScreen(), // Notifications
    SettingsScreen(), // Settings
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _indicatorService,
      child: Consumer<IndicatorService>(
        builder: (context, indicatorService, child) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: Column(
              children: [
                // Header
                SafeArea(
                  child: Padding(
                    padding:
                        const EdgeInsets.only(left: 20, right: 20, top: 20),
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
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (context) =>
                                    const InviteContactDialog(),
                              );
                            },
                            child: Container(
                              height: 50,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6B35)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.person_add,
                                    size: 22,
                                    color: const Color(0xFFFF6B35),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const ProfileIconWidget(),
                      ],
                    ),
                  ),
                ),
                // Main content
                Expanded(
                  child: _screens[_selectedIndex],
                ),
              ],
            ),
            bottomNavigationBar: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Connection status banner
                ConnectionStatusWidget(),
                // Bottom navigation bar
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: Colors.grey,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildNavItem(0, FontAwesomeIcons.comments, 'Chats',
                              indicatorService.hasNewChats),
                          _buildNavItem(
                              1,
                              FontAwesomeIcons.userPlus,
                              'Invitations',
                              indicatorService.hasNewInvitations),
                          _buildNavItem(
                              2,
                              FontAwesomeIcons.bell,
                              'Notifications',
                              indicatorService.hasNewNotifications),
                          _buildNavItem(
                              3, FontAwesomeIcons.gear, 'Settings', false),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildNavItem(
      int index, IconData icon, String label, bool hasIndicator) {
    final isSelected = _selectedIndex == index;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onItemTapped(index),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    FaIcon(
                      icon,
                      color: isSelected ? const Color(0xFFFF6B35) : Colors.grey,
                      size: 18,
                    ),
                    if (hasIndicator)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF6B35),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFFFF6B35) : Colors.grey,
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
