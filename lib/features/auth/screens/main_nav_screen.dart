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

import '../../notifications/services/local_notification_badge_service.dart';
import '../../notifications/services/local_notification_database_service.dart';
import 'package:sechat_app/main.dart' show updateCurrentScreenIndex;
import 'package:sechat_app/shared/widgets/global_socket_status_banner.dart';

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

      // Set initial screen context
      _indicatorService.setScreenContext(
        isOnKeyExchangeScreen: false,
        isOnNotificationsScreen: false,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Update badge counts when dependencies change (e.g., providers update)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateBadgeCountsSync();
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
          '🔌 MainNavScreen: ✅ SeSocketService already connected, setting up providers');

      // The provider already handles socket connection in its initialize method
      // Just ensure it's initialized
      await keyExchangeProvider.initialize();

      // Set up badge count updates
      _setupBadgeCountUpdates();

      print(
          '🔌 MainNavScreen: ✅ KeyExchangeRequestProvider connected to socket service and initialized');
    } else {
      print(
          '🔌 MainNavScreen: ⚠️ SeSocketService not connected yet, will retry in setupBadgeCountUpdates');

      // Set up badge count updates anyway (will retry connection)
      _setupBadgeCountUpdates();
    }
  }

  /// Force refresh badge counts (can be called from external sources)
  void forceRefreshBadgeCounts() {
    print('🔔 MainNavScreen: 🔄 Force refreshing badge counts');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateBadgeCountsSync(); // Instant update
      _updateBadgeCounts(); // Full update
    });
  }

  /// Refresh notification badge count immediately (for when notifications are marked as read)
  void refreshNotificationBadgeCount() async {
    print(
        '🔔 MainNavScreen: 🔄 Refreshing notification badge count immediately');
    try {
      final localNotificationBadgeService = LocalNotificationBadgeService();
      final unreadCount = await localNotificationBadgeService.getUnreadCount();

      // Update the indicator service immediately
      _indicatorService.updateCountsWithContext(
          unreadNotifications: unreadCount);

      print(
          '🔔 MainNavScreen: ✅ Notification badge count refreshed: $unreadCount');
    } catch (e) {
      print(
          '🔔 MainNavScreen: ❌ Error refreshing notification badge count: $e');
    }
  }

  /// Update badge counts when providers change (for real-time updates)
  void _onProviderChanged() {
    print('🔔 MainNavScreen: 🔄 Provider changed, updating badge counts');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateBadgeCountsSync(); // Instant update for immediate response
    });
  }

  void _setupBadgeCountUpdates() {
    // Get the indicator service from provider
    final indicatorService = context.read<IndicatorService>();

    // Initial update - no more periodic delays
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateBadgeCounts();
    });

    // Also update immediately for instant response
    _updateBadgeCountsSync();

    // Ensure badge counts are displayed even if screen context is set
    // This prevents the context-aware logic from hiding the initial counts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_indicatorService.pendingKeyExchangeCount > 0 ||
          _indicatorService.unreadNotificationsCount > 0) {
        print(
            '🔔 MainNavScreen: 🔍 Ensuring badge counts are visible after setup');
        // Force a refresh to ensure counts are displayed
        _updateBadgeCountsSync();
      }
    });
  }

  void _updateBadgeCounts() async {
    try {
      final indicatorService = context.read<IndicatorService>();

      // Update chat count from ChatListProvider (synchronous)
      final chatListProvider = context.read<ChatListProvider>();
      final unreadChatsCount = chatListProvider.conversations
          .where((conv) => conv.unreadCount > 0)
          .length;

      // Update key exchange count from KeyExchangeRequestProvider (synchronous)
      final keyExchangeProvider = context.read<KeyExchangeRequestProvider>();
      // Count both pending/received requests AND pending/sent requests
      final pendingReceivedCount = keyExchangeProvider.receivedRequests
          .where((req) => req.status == 'received' || req.status == 'pending')
          .length;
      final pendingSentCount = keyExchangeProvider.sentRequests
          .where((req) => req.status == 'pending' || req.status == 'sent')
          .length;
      final pendingKeyExchangeCount = pendingReceivedCount + pendingSentCount;

      // Update notification count from LocalNotificationBadgeService (asynchronous but cached)
      final localNotificationBadgeService = LocalNotificationBadgeService();
      final unreadNotificationsCount =
          await localNotificationBadgeService.getUnreadCount();

      print(
          '🔔 MainNavScreen: 📱 Local notification count: $unreadNotificationsCount');

      // Additional debugging: Check if there are any notifications in the database
      try {
        final databaseService = LocalNotificationDatabaseService();
        final allNotifications = await databaseService.getAllNotifications();
        final unreadNotifications =
            allNotifications.where((n) => n.status == 'unread').toList();
        final readNotifications =
            allNotifications.where((n) => n.status == 'read').toList();

        print('🔔 MainNavScreen: 🔍 Database notification details:');
        print('  - Total notifications: ${allNotifications.length}');
        print('  - Unread notifications: ${unreadNotifications.length}');
        print('  - Read notifications: ${readNotifications.length}');

        if (unreadNotifications.isNotEmpty) {
          print(
              '  - Unread notification types: ${unreadNotifications.map((n) => n.type).toList()}');
        }
      } catch (e) {
        print(
            '🔔 MainNavScreen: ⚠️ Could not get detailed notification info: $e');
      }

      // Update indicator service using context-aware method
      indicatorService.updateCountsWithContext(
        unreadChats: unreadChatsCount,
        pendingKeyExchange: pendingKeyExchangeCount,
        unreadNotifications: unreadNotificationsCount,
      );
    } catch (e) {
      print('🔔 MainNavScreen: ❌ Error updating badge counts: $e');
    }
  }

  /// Update badge counts synchronously for instant response (chat and key exchange only)
  void _updateBadgeCountsSync() {
    try {
      final indicatorService = context.read<IndicatorService>();

      // Update chat count from ChatListProvider (synchronous)
      final chatListProvider = context.read<ChatListProvider>();
      final unreadChatsCount = chatListProvider.conversations
          .where((conv) => conv.unreadCount > 0)
          .length;

      // Update key exchange count from KeyExchangeRequestProvider (synchronous)
      final keyExchangeProvider = context.read<KeyExchangeRequestProvider>();
      // Count both pending/received requests AND pending/sent requests
      final pendingReceivedCount = keyExchangeProvider.receivedRequests
          .where((req) => req.status == 'received' || req.status == 'pending')
          .length;
      final pendingSentCount = keyExchangeProvider.sentRequests
          .where((req) => req.status == 'pending' || req.status == 'sent')
          .length;
      final pendingKeyExchangeCount = pendingReceivedCount + pendingSentCount;

      // Update indicator service using context-aware method (synchronous counts only)
      indicatorService.updateCountsWithContext(
        unreadChats: unreadChatsCount,
        pendingKeyExchange: pendingKeyExchangeCount,
        unreadNotifications: null, // Don't update notifications in sync method
      );

      print(
          '🔔 MainNavScreen: ⚡ Sync badge update - Chats: $unreadChatsCount, KER: $pendingKeyExchangeCount');
    } catch (e) {
      print('🔔 MainNavScreen: ❌ Error updating sync badge counts: $e');
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

    // Set screen context based on selected tab (don't clear indicators yet)
    if (index == 1) {
      // K.Exchange tab - just set context, don't clear indicator
      _indicatorService.setScreenContext(
        isOnKeyExchangeScreen: true,
        isOnNotificationsScreen: false,
      );
    } else if (index == 2) {
      // Notifications tab - just set context, don't clear indicator
      _indicatorService.setScreenContext(
        isOnKeyExchangeScreen: false,
        isOnNotificationsScreen: true,
      );
    } else {
      // Other tabs - reset screen context
      _indicatorService.setScreenContext(
        isOnKeyExchangeScreen: false,
        isOnNotificationsScreen: false,
      );
    }

    // Update badge counts immediately after navigation to ensure they're displayed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Always update badge counts when navigating to show current values
      _updateBadgeCountsSync(); // Instant update for chat and KER
      _updateBadgeCounts(); // Full update including notifications

      // Force display current badge counts to ensure they're visible
      _indicatorService.forceDisplayCurrentCounts();
    });

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
                GlobalSocketStatusBanner(),
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
            padding: const EdgeInsets.symmetric(
                vertical: 8, horizontal: 4), // Increased padding for badges
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior:
                      Clip.none, // Allow badges to extend beyond bounds
                  children: [
                    FaIcon(
                      icon,
                      color: isSelected ? const Color(0xFFFF6B35) : Colors.grey,
                      size: 18,
                    ),
                    if (hasBadge)
                      Positioned(
                        right: -4, // Move further right to avoid cutoff
                        top: -4, // Move further up to avoid cutoff
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
