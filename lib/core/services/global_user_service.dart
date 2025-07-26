import '../../shared/models/user.dart';
import '../../shared/providers/auth_provider.dart';

/// Global service for accessing the current user without needing context
class GlobalUserService {
  static GlobalUserService? _instance;
  static GlobalUserService get instance => _instance ??= GlobalUserService._();

  GlobalUserService._();

  /// Get the current authenticated user
  User? get currentUser => AuthProvider.instance.currentUser;

  /// Check if user is authenticated
  bool get isAuthenticated => AuthProvider.instance.isAuthenticated;

  /// Get the current user's ID
  String? get currentUserId => currentUser?.id;

  /// Get the current user's username
  String? get currentUsername => currentUser?.username;

  /// Get the current user's profile picture
  String? get currentUserProfilePicture => currentUser?.profilePicture;

  /// Get the current user's session ID
  String? get sessionId => AuthProvider.instance.sessionId;

  /// Get the current user's display name
  String? get displayName => AuthProvider.instance.displayName;

  /// Check if the user is online
  bool get isOnline => currentUser?.isOnline ?? false;

  /// Get the user's last seen timestamp
  DateTime? get lastSeen => currentUser?.lastSeen;

  /// Update the current user's online status
  void updateOnlineStatus(bool isOnline) {
    if (currentUser != null) {
      final updatedUser = currentUser!.copyWith(
        isOnline: isOnline,
        lastSeen: isOnline ? null : DateTime.now(),
      );
      // Note: This would need to be integrated with AuthProvider to actually update the user
      // For now, this is a placeholder for the concept
    }
  }

  /// Check if user has a profile picture
  bool get hasProfilePicture =>
      currentUserProfilePicture != null &&
      currentUserProfilePicture!.isNotEmpty;

  /// Get user's full name or username as fallback
  String get displayNameOrUsername =>
      displayName ?? currentUsername ?? 'Anonymous User';

  /// Check if this is the first time user
  bool get isFirstTime => AuthProvider.instance.isFirstTime;

  /// Get user's public key if available
  String? get publicKey => currentUser?.publicKey;

  /// Check if user has been created recently (within last 24 hours)
  bool get isNewUser {
    final user = currentUser;
    if (user == null) return false;
    return DateTime.now().difference(user.createdAt).inHours < 24;
  }

  /// Get user's creation date
  DateTime? get createdAt => currentUser?.createdAt;

  /// Check if user data is available
  bool get hasUserData => currentUser != null;

  /// Get user's device ID if available
  String? get deviceId => currentUser?.deviceId;

  /// Check if user is typing
  bool get isTyping => currentUser?.isTyping ?? false;

  /// Update typing status
  void updateTypingStatus(bool isTyping) {
    if (currentUser != null) {
      final updatedUser = currentUser!.copyWith(isTyping: isTyping);
      // Note: This would need to be integrated with AuthProvider to actually update the user
      // For now, this is a placeholder for the concept
    }
  }

  /// Get user's invitation status
  String? get invitationStatus => currentUser?.invitationStatus;

  /// Check if user has pending invitations
  bool get hasPendingInvitations => currentUser?.hasPendingInvitation ?? false;

  /// Check if user can be reinvited
  bool get canReinvite => currentUser?.canReinvite ?? false;

  /// Get user's invitation ID
  String? get invitationId => currentUser?.invitationId;

  /// Check if user has been invited before
  bool get alreadyInvited => currentUser?.alreadyInvited ?? false;

  /// Get user's previous online status
  bool? get previousOnlineStatus => currentUser?.previousOnlineStatus;

  /// Check if user is loading
  bool get isLoading => AuthProvider.instance.isLoading;

  /// Check if auth is initialized
  bool get isInitialized => AuthProvider.instance.isInitialized;

  /// Get any auth error
  String? get error => AuthProvider.instance.error;

  /// Clear auth error
  void clearError() => AuthProvider.instance.clearError();

  /// Logout the current user
  Future<void> logout() => AuthProvider.instance.logout();

  /// Update user profile
  Future<bool> updateProfile({
    String? displayName,
    String? profilePicture,
  }) =>
      AuthProvider.instance.updateProfile(
        displayName: displayName,
        profilePicture: profilePicture,
      );

  /// Export session identity
  Future<Map<String, String>> exportSessionIdentity() =>
      AuthProvider.instance.exportSessionIdentity();

  /// Delete session identity
  Future<bool> deleteSessionIdentity() =>
      AuthProvider.instance.deleteSessionIdentity();

  /// Get session QR code data
  String? getSessionQRCodeData() =>
      AuthProvider.instance.getSessionQRCodeData();

  /// Parse session QR code data
  Map<String, dynamic>? parseSessionQRCodeData(String qrData) =>
      AuthProvider.instance.parseSessionQRCodeData(qrData);

  /// Check if user has contacts
  Future<bool> hasContacts() => AuthProvider.instance.hasContacts();

  /// Get user's contacts
  Map<String, dynamic> getContacts() => AuthProvider.instance.getContacts();
}
