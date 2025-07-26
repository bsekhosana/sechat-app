import 'global_user_service.dart';

/// Example usage of the GlobalUserService
/// This demonstrates how to access user data without needing context
class GlobalUserExample {
  /// Example: Get current user info without context
  static void printCurrentUserInfo() {
    final userService = GlobalUserService.instance;

    if (userService.isAuthenticated) {
      print('Current User: ${userService.currentUsername}');
      print('User ID: ${userService.currentUserId}');
      print('Session ID: ${userService.sessionId}');
      print('Display Name: ${userService.displayNameOrUsername}');
      print('Has Profile Picture: ${userService.hasProfilePicture}');
      print('Is Online: ${userService.isOnline}');
      print('Is New User: ${userService.isNewUser}');
    } else {
      print('No user is currently authenticated');
    }
  }

  /// Example: Check authentication status
  static bool isUserLoggedIn() {
    return GlobalUserService.instance.isAuthenticated;
  }

  /// Example: Get user display name for UI
  static String getUserDisplayName() {
    return GlobalUserService.instance.displayNameOrUsername;
  }

  /// Example: Check if user has profile picture
  static bool userHasProfilePicture() {
    return GlobalUserService.instance.hasProfilePicture;
  }

  /// Example: Get user session ID for API calls
  static String? getUserSessionId() {
    return GlobalUserService.instance.sessionId;
  }

  /// Example: Update user profile
  static Future<bool> updateUserProfile({
    String? displayName,
    String? profilePicture,
  }) async {
    return await GlobalUserService.instance.updateProfile(
      displayName: displayName,
      profilePicture: profilePicture,
    );
  }

  /// Example: Logout user
  static Future<void> logoutUser() async {
    await GlobalUserService.instance.logout();
  }

  /// Example: Check if user is loading
  static bool isUserLoading() {
    return GlobalUserService.instance.isLoading;
  }

  /// Example: Get any auth errors
  static String? getAuthError() {
    return GlobalUserService.instance.error;
  }

  /// Example: Clear auth errors
  static void clearAuthError() {
    GlobalUserService.instance.clearError();
  }
}

/// Usage examples in your code:
/// 
/// // In any widget or service, without needing context:
/// 
/// // Check if user is logged in
/// if (GlobalUserService.instance.isAuthenticated) {
///   // User is logged in
/// }
/// 
/// // Get current user info
/// final currentUser = GlobalUserService.instance.currentUser;
/// final username = GlobalUserService.instance.currentUsername;
/// final sessionId = GlobalUserService.instance.sessionId;
/// 
/// // Update profile
/// await GlobalUserService.instance.updateProfile(
///   displayName: 'New Name',
///   profilePicture: 'new_picture_url',
/// );
/// 
/// // Logout
/// await GlobalUserService.instance.logout();
/// 
/// // Check loading state
/// if (GlobalUserService.instance.isLoading) {
///   // Show loading indicator
/// }
/// 
/// // Handle errors
/// final error = GlobalUserService.instance.error;
/// if (error != null) {
///   // Show error message
///   GlobalUserService.instance.clearError();
/// } 