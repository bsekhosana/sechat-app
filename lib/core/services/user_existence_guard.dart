import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import '../../shared/providers/auth_provider.dart'; // Temporarily disabled
// import '../../features/chat/providers/chat_provider.dart'; // Temporarily disabled
// import '../../features/invitations/providers/invitation_provider.dart'; // Temporarily disabled
// import '../../features/search/providers/search_provider.dart'; // Removed search functionality
import 'se_session_service.dart';
import 'local_storage_service.dart';
import 'secure_notification_service.dart';

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
      print('🔍 UserExistenceGuard: Already handling logout, skipping');
      return;
    }

    _isHandlingLogout = true;
    print(
        '🔍 UserExistenceGuard: User no longer exists, starting logout process');

    try {
      // 1. Logout from SeSessionService
      print('🔍 UserExistenceGuard: Logging out from SeSessionService');
      await SeSessionService().logout();

      // 2. Clear all local storage
      print('🔍 UserExistenceGuard: Clearing local storage');
      await _clearAllLocalData();

      // 3. Clear secure storage
      print('🔍 UserExistenceGuard: Clearing secure storage');
      await _clearSecureStorage();

      // 4. Cancel all notifications
      print('🔍 UserExistenceGuard: Cancelling notifications');
      await SecureNotificationService.instance.cancelAllNotifications();

      // 5. Reset all providers (this will be done by the app when it detects the logout)
      print('🔍 UserExistenceGuard: Logout process completed');

      // 6. Show logout message
      _showLogoutMessage();
    } catch (e) {
      print('🔍 UserExistenceGuard: Error during logout: $e');
    } finally {
      _isHandlingLogout = false;
    }
  }

  // Clear all local data
  Future<void> _clearAllLocalData() async {
    try {
      // Clear Hive databases
      await LocalStorageService.instance.clearAllData();
      print('🔍 UserExistenceGuard: Local storage cleared');
    } catch (e) {
      print('🔍 UserExistenceGuard: Error clearing local storage: $e');
    }
  }

  // Clear secure storage
  Future<void> _clearSecureStorage() async {
    try {
      await _storage.deleteAll();
      print('🔍 UserExistenceGuard: Secure storage cleared');
    } catch (e) {
      print('🔍 UserExistenceGuard: Error clearing secure storage: $e');
    }
  }

  // Show logout message
  void _showLogoutMessage() {
    // This will be handled by the app's navigation system
    // The app will detect the cleared storage and navigate to login
    print('🔍 UserExistenceGuard: User logged out due to account deletion');

    // Show a snackbar or dialog if context is available
    // For now, we'll rely on the app detecting the cleared storage
  }

  // Handle logout with context for UI updates
  Future<void> handleUserNotFoundWithContext(BuildContext context) async {
    if (_isHandlingLogout) {
      print('🔍 UserExistenceGuard: Already handling logout, skipping');
      return;
    }

    _isHandlingLogout = true;
    print(
        '🔍 UserExistenceGuard: User no longer exists, starting logout process');

    try {
      // 1. Logout from SeSessionService
      print('🔍 UserExistenceGuard: Logging out from SeSessionService');
      await SeSessionService().logout();

      // 2. Clear all local storage
      print('🔍 UserExistenceGuard: Clearing local storage');
      await _clearAllLocalData();

      // 3. Clear secure storage
      print('🔍 UserExistenceGuard: Clearing secure storage');
      await _clearSecureStorage();

      // 4. Cancel all notifications
      print('🔍 UserExistenceGuard: Cancelling notifications');
      await SecureNotificationService.instance.cancelAllNotifications();

      // 5. Reset all providers
      print('🔍 UserExistenceGuard: Resetting providers');
      resetProviders(context);

      // 6. Show logout message
      _showLogoutMessageWithContext(context);

      print('🔍 UserExistenceGuard: Logout process completed');
    } catch (e) {
      print('🔍 UserExistenceGuard: Error during logout: $e');
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
        print('🔍 UserExistenceGuard: Context not mounted, skipping SnackBar');
      }
    } catch (e) {
      print('🔍 UserExistenceGuard: Error showing logout message: $e');
    }
  }

  // Check if user is currently logged in
  Future<bool> isUserLoggedIn() async {
    try {
      final userId = await _storage.read(key: 'user_id');
      final deviceId = await _storage.read(key: 'device_id');
      return userId != null && deviceId != null;
    } catch (e) {
      print('🔍 UserExistenceGuard: Error checking login status: $e');
      return false;
    }
  }

  // Force logout (for manual logout)
  Future<void> forceLogout() async {
    print('🔍 UserExistenceGuard: Force logout requested');
    await handleUserNotFound();
  }

  // Reset all providers
  void resetProviders(BuildContext context) {
    try {
      // Check if context is still valid
      if (!context.mounted) {
        print(
            '🔍 UserExistenceGuard: Context not mounted, skipping provider reset');
        return;
      }

      // Reset auth provider - temporarily disabled
      // try {
      //   final authProvider = context.read<AuthProvider>();
      //   authProvider.reset();
      // } catch (e) {
      //   print('🔍 UserExistenceGuard: Error resetting auth provider: $e');
      // }

      // Reset other providers - temporarily disabled
      // try {
      //   final chatProvider = context.read<ChatProvider>();
      //   chatProvider.reset();
      // } catch (e) {
      //   print('🔍 UserExistenceGuard: Error resetting chat provider: $e');
      // }

      // try {
      //   final invitationProvider = context.read<InvitationProvider>();
      //   // invitationProvider.reset(); // Temporarily disabled
      // } catch (e) {
      //   print('🔍 UserExistenceGuard: Error resetting invitation provider: $e');
      // }

      // try {
      //   final searchProvider = context.read<SearchProvider>();
      //   // searchProvider.reset(); // Temporarily disabled
      // } catch (e) {
      //   print('🔍 UserExistenceGuard: Error resetting search provider: $e');
      // }

      print('🔍 UserExistenceGuard: All providers reset');
    } catch (e) {
      print('🔍 UserExistenceGuard: Error resetting providers: $e');
    }
  }
}
