import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sechat_app/features/chat/providers/chat_list_provider.dart';
import 'package:sechat_app/features/key_exchange/providers/key_exchange_request_provider.dart';
import 'package:sechat_app/core/services/indicator_service.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/network_service.dart';
import 'package:sechat_app/features/chat/services/message_storage_service.dart';
import 'package:sechat_app/core/services/se_shared_preference_service.dart';
import 'package:sechat_app/core/services/local_storage_service.dart';
import '../../core/utils/store_link_resolver.dart';
import '../../core/services/global_user_service.dart';
import 'package:sechat_app/features/auth/screens/welcome_screen.dart';
import 'package:sechat_app/shared/providers/socket_status_provider.dart';

class ProfileIconWidget extends StatefulWidget {
  const ProfileIconWidget({super.key});

  @override
  State<ProfileIconWidget> createState() => _ProfileIconWidgetState();
}

class _ProfileIconWidgetState extends State<ProfileIconWidget>
    with TickerProviderStateMixin {
  late Animation<double> _glowAnimation;
  late AnimationController _glowController;
  late Animation<double> _pulseAnimation;
  late AnimationController _pulseController;
  bool _showCopySuccess = false;

  @override
  void dispose() {
    _glowController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    // Glow animation for connected state
    _glowController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _glowAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeInOut,
    ));

    // Pulse animation for reconnecting state
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  void _updateAnimationStatus(bool isConnected, bool isReconnecting) {
    if (isConnected) {
      _glowController.repeat(reverse: true);
      _pulseController.stop();
    } else if (isReconnecting) {
      _glowController.stop();
      _pulseController.repeat(reverse: true);
    } else {
      _glowController.stop();
      _pulseController.stop();
    }
  }

  void _showProfileMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final screenHeight = MediaQuery.of(context).size.height;

        return Hero(
          tag: 'profile_icon_button',
          child: Container(
            height: screenHeight * 0.95,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Header
                Container(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Profile icon
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(40),
                          image: const DecorationImage(
                            image: AssetImage('assets/logo/seChat_Logo.png'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Username
                      Text(
                        GlobalUserService.instance.currentUsername ?? 'User',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Network status
                      Consumer<NetworkService>(
                        builder: (context, networkService, child) {
                          final seSessionService = SeSessionService();
                          final session = seSessionService.currentSession;
                          bool isConnected =
                              networkService.isConnected && session != null;
                          bool isReconnecting = networkService.isReconnecting;

                          // Determine status text and color
                          String statusText;
                          Color statusColor;

                          if (!networkService.isConnected) {
                            statusText = 'No Network';
                            statusColor = Colors.red;
                          } else if (!networkService.isInternetAvailable) {
                            statusText = 'No Internet';
                            statusColor = Colors.red;
                          } else if (isReconnecting) {
                            statusText = 'Reconnecting...';
                            statusColor = Colors.orange;
                          } else if (isConnected) {
                            statusText = 'Connected';
                            statusColor = const Color(0xFF4CAF50);
                          } else {
                            statusText = 'Session Disconnected';
                            statusColor = Colors.orange;
                          }

                          return Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Session Code Section
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      'Session Code',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      seSessionService.currentSessionId ??
                                          'Unknown',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                        color: Colors.grey,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        // Share Button
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () =>
                                                _shareSessionCode(context),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 8),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFF6B35)
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.share,
                                                    color:
                                                        const Color(0xFFFF6B35),
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  const Text(
                                                    'Share',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Color(0xFFFF6B35),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Copy Button
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => _copySessionCode(),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 8),
                                              decoration: BoxDecoration(
                                                color: Colors.grey
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.copy,
                                                    color: Colors.grey,
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  const Text(
                                                    'Copy',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // Content - Scrollable
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 0, left: 24, right: 24),
                    child: Column(
                      children: [
                        // Menu options container
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Column(
                            children: [
                              _buildMenuButton(
                                icon: Icons.delete_sweep,
                                title: 'Clear All Chats',
                                subtitle: 'Delete all your conversations',
                                onTap: () => _showClearChatsConfirmation(),
                                isDestructive: true,
                              ),
                              const SizedBox(height: 16),
                              _buildMenuButton(
                                icon: Icons.account_circle_outlined,
                                title: 'Delete Session',
                                subtitle: 'Permanently delete your session',
                                onTap: () => _showDeleteAccountConfirmation(),
                                isDestructive: true,
                              ),
                            ],
                          ),
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

  Widget _buildMenuButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDestructive
                      ? Colors.red.withValues(alpha: 0.1)
                      : const Color(0xFFFF6B35).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: isDestructive ? Colors.red : const Color(0xFFFF6B35),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isDestructive ? Colors.red : Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.grey[400],
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showClearChatsConfirmation() {
    Navigator.pop(context); // Close the bottom sheet first
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Clear All Chats',
          style: TextStyle(color: Colors.black),
        ),
        content: const Text(
          'Are you sure you want to delete all your conversations? This action cannot be reversed.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearAllChats();
            },
            child: const Text(
              'Delete All',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountConfirmation() {
    Navigator.pop(context); // Close the bottom sheet first
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Delete Session',
          style: TextStyle(color: Colors.black),
        ),
        content: const Text(
          'Are you sure you want to permanently delete your session? This action cannot be reversed and all your data will be lost.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAccount();
            },
            child: const Text(
              'Delete Session',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllChats() async {
    if (!mounted) return;

    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      // Show loading with informative message
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              const Expanded(
                child: Text(
                  'Deleting all chats and messages...',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      );

      // CRITICAL: Clear all chats and messages while preserving conversations
      try {
        print(
            '🗑️ ProfileIconWidget: 🗄️ Clearing all database chats and messages...');

        // Clear all database data (conversations and messages)
        final messageStorageService = MessageStorageService.instance;
        await messageStorageService.deleteAllChats();

        // Clean up any malformed conversation IDs
        await messageStorageService.cleanupMalformedConversationIds();

        print('🗑️ ProfileIconWidget: ✅ Database chats and messages cleared');
      } catch (e) {
        print(
            '🗑️ ProfileIconWidget: ⚠️ Warning - database cleanup failed: $e');
        // Continue with chat deletion even if database cleanup fails
      }

      // Clear chat-related shared preferences
      try {
        print(
            '🗑️ ProfileIconWidget: 🔍 Clearing chat-related shared preferences...');
        final prefsService = SeSharedPreferenceService();

        // Remove specific chat-related keys
        await prefsService.remove('chats');
        await prefsService.remove('messages');
        await prefsService.remove('conversations');
        await prefsService.remove('last_message_preview');
        await prefsService.remove('unread_count');
        await prefsService.remove('last_message_at');

        print(
            '🗑️ ProfileIconWidget: ✅ Chat-related shared preferences cleared');
      } catch (e) {
        print(
            '🗑️ ProfileIconWidget: ⚠️ Warning - shared preferences cleanup failed: $e');
        // Continue with chat deletion even if shared preferences cleanup fails
      }

      // Clear local storage service chat data
      try {
        print(
            '🗑️ ProfileIconWidget: 📱 Clearing local storage service chat data...');
        final localStorageService = LocalStorageService.instance;
        await localStorageService.clearAllData();
        print(
            '🗑️ ProfileIconWidget: ✅ Local storage service chat data cleared');
      } catch (e) {
        print(
            '🗑️ ProfileIconWidget: ⚠️ Warning - local storage service cleanup failed: $e');
        // Continue with chat deletion even if local storage service cleanup fails
      }

      // Clear all provider data to prevent old conversations from showing
      if (mounted) {
        try {
          print('🗑️ ProfileIconWidget: 🧹 Clearing all provider data...');

          // Clear ChatListProvider
          final chatListProvider =
              Provider.of<ChatListProvider>(context, listen: false);
          chatListProvider.clearAllData();
          print('🗑️ ProfileIconWidget: ✅ ChatListProvider cleared');

          // Clear KeyExchangeRequestProvider
          final keyExchangeProvider =
              Provider.of<KeyExchangeRequestProvider>(context, listen: false);
          keyExchangeProvider.clearAllData();
          print('🗑️ ProfileIconWidget: ✅ KeyExchangeRequestProvider cleared');

          // Clear IndicatorService
          final indicatorService =
              Provider.of<IndicatorService>(context, listen: false);
          indicatorService.clearAllIndicators();
          print('🗑️ ProfileIconWidget: ✅ IndicatorService cleared');

          // Clear SocketStatusProvider
          final socketStatusProvider =
              Provider.of<SocketStatusProvider>(context, listen: false);
          socketStatusProvider.resetState();
          print('🗑️ ProfileIconWidget: ✅ SocketStatusProvider reset');

          print('🗑️ ProfileIconWidget: ✅ All provider data cleared');
        } catch (e) {
          print(
              '🗑️ ProfileIconWidget: ⚠️ Warning - provider cleanup failed: $e');
          // Don't fail the chat deletion if provider cleanup fails
        }
      }

      // Use the comprehensive chat deletion method from SeSessionService as backup
      try {
        print(
            '🗑️ ProfileIconWidget: 🔄 Using SeSessionService.deleteAllChats as backup...');
        final seSessionService = SeSessionService();
        await seSessionService.deleteAllChats();
        print(
            '🗑️ ProfileIconWidget: ✅ SeSessionService.deleteAllChats completed');
      } catch (e) {
        print(
            '🗑️ ProfileIconWidget: ⚠️ Warning - SeSessionService.deleteAllChats failed: $e');
        // This is just a backup, so don't fail if it doesn't work
      }

      if (!mounted) return;
      navigator.pop(); // Close loading dialog

      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('All chats and messages cleared successfully'),
          backgroundColor: Color(0xFFFF6B35),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      navigator.pop(); // Close loading dialog
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error clearing chats: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteAccount() async {
    if (!mounted) return;

    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      // Show loading with informative message
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              const Expanded(
                child: Text(
                  'Deleting account and all data...',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      );

      // CRITICAL: Clear all data from database and shared preferences BEFORE calling SeSessionService
      try {
        print('🗑️ ProfileIconWidget: 🗄️ Clearing all database data...');

        // Clear all database data (conversations and messages)
        final messageStorageService = MessageStorageService.instance;
        await messageStorageService.deleteAllChats();

        // Clean up any malformed conversation IDs
        await messageStorageService.cleanupMalformedConversationIds();

        print('🗑️ ProfileIconWidget: ✅ Database cleared');

        // Force recreate database to ensure clean state
        await messageStorageService.forceRecreateDatabase();
        print('🗑️ ProfileIconWidget: ✅ Database recreated');
      } catch (e) {
        print(
            '🗑️ ProfileIconWidget: ⚠️ Warning - database cleanup failed: $e');
        // Continue with account deletion even if database cleanup fails
      }

      // Clear all shared preferences
      try {
        print('🗑️ ProfileIconWidget: 🔍 Clearing all shared preferences...');
        final prefsService = SeSharedPreferenceService();
        await prefsService.clear();
        print('🗑️ ProfileIconWidget: ✅ Shared preferences cleared');
      } catch (e) {
        print(
            '🗑️ ProfileIconWidget: ⚠️ Warning - shared preferences cleanup failed: $e');
        // Continue with account deletion even if shared preferences cleanup fails
      }

      // Clear all local storage service data
      try {
        print(
            '🗑️ ProfileIconWidget: 📱 Clearing all local storage service data...');
        final localStorageService = LocalStorageService.instance;
        await localStorageService.clearAllData();
        print('🗑️ ProfileIconWidget: ✅ Local storage service cleared');
      } catch (e) {
        print(
            '🗑️ ProfileIconWidget: ⚠️ Warning - local storage service cleanup failed: $e');
        // Continue with account deletion even if local storage service cleanup fails
      }

      // Clear all temporary files and directories
      try {
        print(
            '🗑️ ProfileIconWidget: 🗂️ Clearing all temporary files and directories...');
        final appDocumentsDir = await getApplicationDocumentsDirectory();

        // Clear image directory if it exists
        final imagesDir = Directory('${appDocumentsDir.path}/sechat_images');
        if (await imagesDir.exists()) {
          await imagesDir.delete(recursive: true);
          print('🗑️ ProfileIconWidget: ✅ Image directory cleared');
        }

        // Clear temp directory if it exists
        final tempDir = Directory('${appDocumentsDir.path}/sechat_temp');
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
          print('🗑️ ProfileIconWidget: ✅ Temp directory cleared');
        }

        print(
            '🗑️ ProfileIconWidget: ✅ All temporary files and directories cleared');
      } catch (e) {
        print('🗑️ ProfileIconWidget: ⚠️ Warning - file cleanup failed: $e');
        // Continue with account deletion even if file cleanup fails
      }

      // Use the comprehensive account deletion method from SeSessionService
      final seSessionService = SeSessionService();
      await seSessionService.deleteAccount();

      // CRITICAL: Clear all provider data to prevent old conversations from showing
      if (mounted) {
        try {
          print('🗑️ ProfileIconWidget: 🧹 Clearing all provider data...');

          // Clear ChatListProvider
          final chatListProvider =
              Provider.of<ChatListProvider>(context, listen: false);
          chatListProvider.clearAllData();
          print('🗑️ ProfileIconWidget: ✅ ChatListProvider cleared');

          // Clear KeyExchangeRequestProvider
          final keyExchangeProvider =
              Provider.of<KeyExchangeRequestProvider>(context, listen: false);
          keyExchangeProvider.clearAllData();
          print('🗑️ ProfileIconWidget: ✅ KeyExchangeRequestProvider cleared');

          // Clear IndicatorService
          final indicatorService =
              Provider.of<IndicatorService>(context, listen: false);
          indicatorService.clearAllIndicators();
          print('🗑️ ProfileIconWidget: ✅ IndicatorService cleared');

          // Clear SocketStatusProvider
          final socketStatusProvider =
              Provider.of<SocketStatusProvider>(context, listen: false);
          socketStatusProvider.resetState();
          print('🗑️ ProfileIconWidget: ✅ SocketStatusProvider reset');

          print('🗑️ ProfileIconWidget: ✅ All provider data cleared');
        } catch (e) {
          print(
              '🗑️ ProfileIconWidget: ⚠️ Warning - provider cleanup failed: $e');
          // Don't fail the account deletion if provider cleanup fails
        }
      }

      if (!mounted) return;
      navigator.pop(); // Close loading dialog

      // Navigate to welcome screen
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const WelcomeScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      navigator.pop(); // Close loading dialog
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error deleting account: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSessionCode() {
    Navigator.pop(context); // Close the bottom sheet first
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final sessionId =
            SeSessionService().currentSessionId ?? 'No session ID';
        final displayName =
            GlobalUserService.instance.currentUsername ?? 'SeChat User';

        return Container(
          height: MediaQuery.of(context).size.height * 0.95,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Icon
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          image: const DecorationImage(
                            image: AssetImage('assets/logo/seChat_Logo.png'),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Title
                    const Text(
                      'My Session Code',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Subtitle
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

              // QR Code Container
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      // App Icon with Session ID
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[300]!),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // App Logo
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                image: const DecorationImage(
                                  image:
                                      AssetImage('assets/logo/seChat_Logo.png'),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Session ID Text
                            Text(
                              sessionId,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                                fontFamily: 'monospace',
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Copy Success Message
                      if (_showCopySuccess)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Session ID copied to clipboard',
                                style: TextStyle(
                                  color: Colors.green[700],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Session ID with Copy Button
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Session ID',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border:
                                          Border.all(color: Colors.grey[300]!),
                                    ),
                                    child: SelectableText(
                                      sessionId,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _copySessionId(context),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF6B35)
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.copy,
                                      color: Color(0xFFFF6B35),
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Action Buttons
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _shareSessionCode(context),
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFFF6B35).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.share,
                                color: Color(0xFFFF6B35),
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Share Session Code',
                                style: TextStyle(
                                  color: Color(0xFFFF6B35),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _copySessionId(BuildContext context) {
    final sessionId = SeSessionService().currentSessionId;
    if (sessionId != null) {
      Clipboard.setData(ClipboardData(text: sessionId));
      // Show success message above the session ID container
      setState(() {
        _showCopySuccess = true;
      });

      // Hide the message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showCopySuccess = false;
          });
        }
      });
    }
  }

  void _shareSessionCode(BuildContext context) async {
    if (!mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final sessionId = SeSessionService().currentSessionId;
      final displayName =
          GlobalUserService.instance.currentUsername ?? 'SeChat User';

      if (sessionId != null) {
        // Detect platform for appropriate app store link
        final link = await StoreLinkResolver.resolve();

        // Create invitation message
        final invitationMessage = '🔐 Connect with me on SeChat!\n\n'
            '👤 My Name: $displayName\n'
            '🆔 My Session ID: $sessionId\n\n'
            '📱 Download SeChat to start chatting securely:\n'
            '$link\n\n'
            '💬 Use my Session ID to send me a secure connection request!';

        // Share the invitation message
        await Share.share(
          invitationMessage,
          subject: 'Connect on SeChat - Secure Messaging',
        );

        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Session code shared successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to share session code: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _copySessionCode() {
    final sessionId = SeSessionService().currentSessionId ?? 'Unknown';
    Clipboard.setData(ClipboardData(text: sessionId));

    setState(() {
      _showCopySuccess = true;
    });

    // Hide success message after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showCopySuccess = false;
        });
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Session code copied to clipboard!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NetworkService>(
      builder: (context, networkService, child) {
        // Determine connection status and color
        Color statusColor;
        bool isConnected = false;
        bool isReconnecting = networkService.isReconnecting;
        bool isInternetAvailable = networkService.isInternetAvailable;

        if (!networkService.isConnected || !isInternetAvailable) {
          // Network is disconnected or no internet
          statusColor = Colors.red;
          isConnected = false;
        } else if (networkService.isReconnecting) {
          // Network is reconnecting
          statusColor = Colors.orange;
          isConnected = false;
        } else {
          // Network is connected, check SeSession status
          final seSessionService = SeSessionService();
          final session = seSessionService.currentSession;
          if (session != null) {
            statusColor = Colors.green;
            isConnected = true;
          } else {
            statusColor = Colors.orange;
            isConnected = false;
          }
        }

        // Update animation status based on connection state
        _updateAnimationStatus(isConnected, isReconnecting);

        return GestureDetector(
          onTap: _showProfileMenu,
          child: Hero(
            tag: 'profile_icon_button',
            child: AnimatedBuilder(
              animation: Listenable.merge([_glowAnimation, _pulseAnimation]),
              builder: (context, child) {
                // Determine which animation to use
                double animationValue;
                if (isConnected) {
                  animationValue = _glowAnimation.value;
                } else if (isReconnecting) {
                  animationValue = _pulseAnimation.value;
                } else {
                  animationValue = 0.3; // Static low glow for disconnected
                }

                return Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color:
                            statusColor.withValues(alpha: animationValue * 0.6),
                        blurRadius: isReconnecting ? 8 : 12,
                        spreadRadius: isReconnecting ? 1 : 2,
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: statusColor.withValues(alpha: animationValue),
                        width: isReconnecting ? 1.5 : 2,
                      ),
                      image: const DecorationImage(
                        image: AssetImage('assets/logo/seChat_Logo.png'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
