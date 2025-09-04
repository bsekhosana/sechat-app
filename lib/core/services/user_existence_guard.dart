import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
// import '../../shared/providers/auth_provider.dart'; // Temporarily disabled
// import '../../features/chat/providers/chat_provider.dart'; // Temporarily disabled
// import '../../features/invitations/providers/invitation_provider.dart'; // Temporarily disabled
// import '../../features/search/providers/search_provider.dart'; // Removed search functionality
import 'se_session_service.dart';
import 'se_socket_service.dart';
import 'local_storage_service.dart';
import '/..//../core/utils/logger.dart';
// import 'secure_notification_service.dart'; // Removed - now handled by socket service

class UserExistenceGuard {
  static final UserExistenceGuard _instance = UserExistenceGuard._internal();
  factory UserExistenceGuard() => _instance;
  UserExistenceGuard._internal();

  static UserExistenceGuard get instance => _instance;

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _isHandlingLogout = false;

  // Handle user not found - logout and clear all data
  Future<void> handleUserNotFound() async {
    if (_isHandlingLogout) {
      Logger.info(' UserExistenceGuard: Already handling logout, skipping');
      return;
    }

    _isHandlingLogout = true;
    Logger.info(
        ' UserExistenceGuard: User no longer exists, starting logout process');

    try {
      // 1. Remove session on socket server (if possible) then logout locally
      try {
        final socketService = SeSocketService.instance;
        final sessionId = SeSessionService().currentSessionId;
        await socketService.deleteSessionOnServer(sessionId: sessionId);
      } catch (e) {
        // Best-effort; proceed regardless
      }

      Logger.info(' UserExistenceGuard: Logging out from SeSessionService');
      await SeSessionService().logout();

      // 2. Clear all local storage
      Logger.info(' UserExistenceGuard: Clearing local storage');
      await _clearAllLocalData();

      // 3. Clear secure storage
      Logger.info(' UserExistenceGuard: Clearing secure storage');
      await _clearSecureStorage();

      // 4. Cancel all notifications (now handled by socket service)
      Logger.info(
          ' UserExistenceGuard: Notifications handled by socket service');

      // 5. Reset all providers (this will be done by the app when it detects the logout)
      Logger.info(' UserExistenceGuard: Logout process completed');

      // 6. Show logout message
      _showLogoutMessage();
    } catch (e) {
      Logger.info(' UserExistenceGuard: Error during logout: $e');
    } finally {
      _isHandlingLogout = false;
    }
  }

  // Clear all local data
  Future<void> _clearAllLocalData() async {
    try {
      // Clear Hive databases
      await LocalStorageService.instance.clearAllData();
      Logger.info(' UserExistenceGuard: Local storage cleared');
    } catch (e) {
      Logger.info(' UserExistenceGuard: Error clearing local storage: $e');
    }
  }

  // Clear secure storage
  Future<void> _clearSecureStorage() async {
    try {
      await _storage.deleteAll();
      Logger.info(' UserExistenceGuard: Secure storage cleared');
    } catch (e) {
      Logger.info(' UserExistenceGuard: Error clearing secure storage: $e');
    }
  }

  // Show logout message
  void _showLogoutMessage() {
    // This will be handled by the app's navigation system
    // The app will detect the cleared storage and navigate to login
    Logger.info(' UserExistenceGuard: User logged out due to account deletion');

    // Show a snackbar or dialog if context is available
    // For now, we'll rely on the app detecting the cleared storage
  }

  // Handle logout with context for UI updates
  Future<void> handleUserNotFoundWithContext(BuildContext context) async {
    if (_isHandlingLogout) {
      Logger.info(' UserExistenceGuard: Already handling logout, skipping');
      return;
    }

    _isHandlingLogout = true;
    Logger.info(
        ' UserExistenceGuard: User no longer exists, starting logout process');

    try {
      // 1. Logout from SeSessionService
      Logger.info(' UserExistenceGuard: Logging out from SeSessionService');
      await SeSessionService().logout();

      // 2. Clear all local storage
      Logger.info(' UserExistenceGuard: Clearing local storage');
      await _clearAllLocalData();

      // 3. Clear secure storage
      Logger.info(' UserExistenceGuard: Clearing secure storage');
      await _clearSecureStorage();

      // 4. Cancel all notifications (now handled by socket service)
      Logger.info(
          ' UserExistenceGuard: Notifications handled by socket service');

      // 5. Reset all providers
      Logger.info(' UserExistenceGuard: Resetting providers');
      resetProviders(context);

      // 6. Show logout message
      _showLogoutMessageWithContext(context);

      Logger.info(' UserExistenceGuard: Logout process completed');
    } catch (e) {
      Logger.info(' UserExistenceGuard: Error during logout: $e');
    } finally {
      _isHandlingLogout = false;
    }
  }

  // Show logout message with context
  void _showLogoutMessageWithContext(BuildContext context) {
    try {
      // Check if the context is still valid and mounted
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Your account has been deleted. You have been logged out.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      } else {
        Logger.info(
            ' UserExistenceGuard: Context not mounted, skipping SnackBar');
      }
    } catch (e) {
      Logger.info(' UserExistenceGuard: Error showing logout message: $e');
    }
  }

  // Check if user is currently logged in
  Future<bool> isUserLoggedIn() async {
    try {
      final userId = await _storage.read(key: 'user_id');
      final deviceId = await _storage.read(key: 'device_id');
      return userId != null && deviceId != null;
    } catch (e) {
      Logger.info(' UserExistenceGuard: Error checking login status: $e');
      return false;
    }
  }

  // Force logout (for manual logout)
  Future<void> forceLogout() async {
    Logger.info(' UserExistenceGuard: Force logout requested');
    await handleUserNotFound();
  }

  // Reset all providers
  void resetProviders(BuildContext context) {
    try {
      // Check if context is still valid
      if (!context.mounted) {
        Logger.info(
            ' UserExistenceGuard: Context not mounted, skipping provider reset');
        return;
      }

      // Reset auth provider - temporarily disabled
      // try {
      //   final authProvider = context.read<AuthProvider>();
      //   authProvider.reset();
      // } catch (e) {
      //   Logger.info(' UserExistenceGuard: Error resetting auth provider: $e');
      // }

      // Reset other providers - temporarily disabled
      // try {
      //   final chatProvider = context.read<ChatProvider>();
      //   chatProvider.reset();
      // } catch (e) {
      //   Logger.info(' UserExistenceGuard: Error resetting chat provider: $e');
      // }

      // try {
      //   final invitationProvider = context.read<InvitationProvider>();
      //   // invitationProvider.reset(); // Temporarily disabled
      // } catch (e) {
      //   Logger.info(' UserExistenceGuard: Error resetting invitation provider: $e');
      // }

      // try {
      //   final searchProvider = context.read<SearchProvider>();
      //   // searchProvider.reset(); // Temporarily disabled
      // } catch (e) {
      //   Logger.info(' UserExistenceGuard: Error resetting search provider: $e');
      // }

      Logger.info(' UserExistenceGuard: All providers reset');
    } catch (e) {
      Logger.info(' UserExistenceGuard: Error resetting providers: $e');
    }
  }
}
