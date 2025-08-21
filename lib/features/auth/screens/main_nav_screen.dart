import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import '../../../core/services/network_service.dart';
import '../../../core/services/indicator_service.dart';
import '../../../core/services/se_socket_service.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/connection_status_widget.dart';
import '../../../shared/widgets/socket_connection_status_widget.dart';
import '../../../shared/widgets/socket_status_button.dart';
import '../../../shared/widgets/profile_icon_widget.dart';
import '../../../shared/widgets/key_exchange_request_dialog.dart';
import '../../../core/services/se_session_service.dart';
import '../../key_exchange/screens/key_exchange_screen.dart';
import '../../notifications/screens/socket_notifications_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../chat/screens/chat_list_screen.dart';
import '../../key_exchange/providers/key_exchange_request_provider.dart';
import '../../chat/providers/chat_list_provider.dart';
import '../../notifications/services/notification_manager_service.dart';
import 'package:sechat_app/main.dart' show updateCurrentScreenIndex;

class MainNavScreen extends StatefulWidget {
  final Map<String, dynamic>? notificationPayload;

  const MainNavScreen({
    super.key,
    this.notificationPayload,
  });

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
      _setupNotificationProviders();
    });
  }

  void _checkIndicators() async {
    await _indicatorService.checkForNewItems();
  }

  void _loadAllData() {
    // Load data for other providers
    // Notifications now handled by socket service
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

  void _setupNotificationProviders() async {
    // Connect KeyExchangeRequestProvider to socket service
    final keyExchangeProvider = context.read<KeyExchangeRequestProvider>();

    // Initialize the provider to load saved requests
    keyExchangeProvider.initialize();

    // CRITICAL FIX: Use the existing initialized SeSocketService instance
    // This ensures we're using the same service that was initialized in AuthChecker
    final socketService = SeSocketService.instance;

    // Debug: Check current session ID
    final currentSessionId = SeSessionService().currentSessionId;
    print('🔌 MainNavScreen: 🔍 Current session ID: $currentSessionId');
    print(
        '🔌 MainNavScreen: 🔍 SeSocketService connected: ${socketService.isConnected}');

    // Check if SeSocketService is already initialized
    if (socketService.isConnected) {
      print(
          '🔌 MainNavScreen: ✅ SeSocketService already connected, setting up KER callback');

      // Set up the callback immediately
      socketService.setOnKeyExchangeRequestReceived(
        (data) => keyExchangeProvider.processReceivedKeyExchangeRequest(data),
      );

      // Verify the callback is set
      print('🔌 MainNavScreen: ✅ KER callback set up successfully');

      // Test: Verify we can emit events (this tests the socket connection)
      try {
        socketService.emit('test:connection',
            {'test': true, 'timestamp': DateTime.now().toIso8601String()});
        print('🔌 MainNavScreen: ✅ Test emit successful - socket is working');
      } catch (e) {
        print('🔌 MainNavScreen: ❌ Test emit failed: $e');
      }
    } else {
      print(
          '🔌 MainNavScreen: 🔌 SeSocketService not connected, initializing...');

      // Initialize if not already connected
      try {
        final currentSessionId = SeSessionService().currentSessionId;
        if (currentSessionId != null) {
          await socketService.connect(currentSessionId);
          print(
              '🔌 MainNavScreen: ✅ SeSocketService connected and listening for incoming KER events');

          // Set up the callback after connection
          socketService.setOnKeyExchangeRequestReceived(
            (data) =>
                keyExchangeProvider.processReceivedKeyExchangeRequest(data),
          );

          // Verify the callback is set
          print(
              '🔌 MainNavScreen: ✅ KER callback set up successfully after connection');

          // Test: Verify we can emit events (this tests the socket connection)
          try {
            socketService.emit('test:connection',
                {'test': true, 'timestamp': DateTime.now().toIso8601String()});
            print(
                '🔌 MainNavScreen: ✅ Test emit successful after connection - socket is working');
          } catch (e) {
            print('🔌 MainNavScreen: ❌ Test emit failed after connection: $e');
          }
        } else {
          print(
              '🔌 MainNavScreen: ❌ No current session ID available for socket connection');
        }
      } catch (e) {
        print('🔌 MainNavScreen: ❌ Failed to connect SeSocketService: $e');
      }
    }

    // Set up badge count updates
    _setupBadgeCountUpdates();

    print(
        '🔌 MainNavScreen: ✅ KeyExchangeRequestProvider connected to socket service and initialized');
  }

  void _setupBadgeCountUpdates() {
    // Get the indicator service from provider
    final indicatorService = context.read<IndicatorService>();

    // Set up periodic badge count updates
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _updateBadgeCounts();
      } else {
        timer.cancel();
      }
    });

    // Initial update
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateBadgeCounts();
    });
  }

  void _updateBadgeCounts() async {
    try {
      final indicatorService = context.read<IndicatorService>();

      // Update chat count from ChatListProvider
      final chatListProvider = context.read<ChatListProvider>();
      final unreadChatsCount = chatListProvider.conversations
          .where((conv) => conv.unreadCount > 0)
          .length;

      // Update key exchange count from KeyExchangeRequestProvider
      final keyExchangeProvider = context.read<KeyExchangeRequestProvider>();
      final pendingKeyExchangeCount =
          keyExchangeProvider.receivedRequests.length;

      // Update notification count from NotificationManagerService
      final notificationManager = NotificationManagerService();
      final unreadNotificationsCount =
          await notificationManager.getUnreadCount();

      // Update indicator service
      indicatorService.updateCounts(
        unreadChats: unreadChatsCount,
        pendingKeyExchange: pendingKeyExchangeCount,
        unreadNotifications: unreadNotificationsCount,
      );
    } catch (e) {
      print('🔔 MainNavScreen: ❌ Error updating badge counts: $e');
    }
  }

  static final List<Widget> _screens = <Widget>[
    const ChatListScreen(), // Chats
    KeyExchangeScreen(), // Key Exchange
    const SocketNotificationsScreen(), // Notifications
    SettingsScreen(), // Settings
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    // Clear indicators based on selected tab
    if (index == 1) {
      // K.Exchange tab
      final indicatorService = context.read<IndicatorService>();
      indicatorService.clearKeyExchangeIndicator();
    }
    updateCurrentScreenIndex(_selectedIndex);
  }

  /// Get the title for the current screen based on selected index
  String _getScreenTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Chats';
      case 1:
        return 'K.Exchange';
      case 2:
        return 'Notifications';
      case 3:
        return 'Settings';
      default:
        return 'Chats';
    }
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
                        const SocketStatusButton(), // Socket status button
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 50,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  _getScreenTitle(),
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
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
                // Socket connection status banner
                SocketConnectionStatusWidget(),
                // Network connection status banner
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
                              indicatorService.unreadChatsCount),
                          _buildNavItem(1, FontAwesomeIcons.key, 'K.Exchange',
                              indicatorService.pendingKeyExchangeCount),
                          _buildNavItem(
                              2,
                              FontAwesomeIcons.bell,
                              'Notifications',
                              indicatorService.unreadNotificationsCount),
                          _buildNavItem(
                              3, FontAwesomeIcons.gear, 'Settings', 0),
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

  Widget _buildNavItem(int index, IconData icon, String label, int count) {
    final isSelected = _selectedIndex == index;
    final hasBadge = count > 0;

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
                    if (hasBadge)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          constraints:
                              const BoxConstraints(minWidth: 16, minHeight: 16),
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF6B35),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            count > 99 ? '99+' : count.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
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
