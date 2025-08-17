import '../../shared/models/user.dart';
import 'se_session_service.dart';

/// Global service for accessing the current user without needing context
class GlobalUserService {
  static GlobalUserService? _instance;
  static GlobalUserService get instance => _instance ??= GlobalUserService._();

  GlobalUserService._();

  /// Get the current authenticated user
  User? get currentUser {
    final session = SeSessionService().currentSession;
    if (session == null) return null;

    return User(
      id: session.sessionId,
      username: session.displayName,
      profilePicture: null, // SeSessionService doesn't store profile pictures
      isOnline: true,
      lastSeen: DateTime.now(),
      createdAt: session.createdAt,
    );
  }

  /// Check if user is authenticated
  bool get isAuthenticated {
    final session = SeSessionService().currentSession;
    return session != null && session.isLoggedIn;
  }

  /// Get the current user's ID
  String? get currentUserId => currentUser?.id;

  /// Get the current user's username
  String? get currentUsername => currentUser?.username;

  /// Get the current user's profile picture
  String? get currentUserProfilePicture => currentUser?.profilePicture;

  /// Get the current user's session ID
  String? get sessionId => SeSessionService().currentSessionId;

  /// Get the current user's display name
  String? get displayName => SeSessionService().currentSession?.displayName;

  /// Check if the user is online
  bool get isOnline => currentUser?.isOnline ?? false;

  /// Get the user's last seen timestamp
  DateTime? get lastSeen => currentUser?.lastSeen;

  /// Update the current user's online status
  void updateOnlineStatus(bool isOnline) {
    // SeSessionService doesn't track online status
    // This is handled by the notification system
  }

  /// Check if user has a profile picture
  bool get hasProfilePicture =>
      currentUserProfilePicture != null &&
      currentUserProfilePicture!.isNotEmpty;

  /// Get user's full name or username as fallback
  String get displayNameOrUsername =>
      displayName ?? currentUsername ?? 'Anonymous User';

  /// Check if this is the first time user
  bool get isFirstTime {
    final session = SeSessionService().currentSession;
    return session == null;
  }

  /// Get user's public key if available
  String? get publicKey => SeSessionService().currentSession?.publicKey;

  /// Check if user has been created recently (within last 24 hours)
  bool get isNewUser {
    final session = SeSessionService().currentSession;
    if (session == null) return false;
    return DateTime.now().difference(session.createdAt).inHours < 24;
  }

  /// Get user's creation date
  DateTime? get createdAt => SeSessionService().currentSession?.createdAt;

  /// Check if user data is available
  bool get hasUserData => SeSessionService().currentSession != null;

  /// Get user's device ID if available
  String? get deviceId =>
      null; // SeSessionService doesn't track device ID separately

  /// Check if user is typing
  bool get isTyping => currentUser?.isTyping ?? false;

  /// Update typing status
  void updateTypingStatus(bool isTyping) {
    // SeSessionService doesn't track typing status
    // This is handled by the chat system
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
  bool get isLoading => false; // SeSessionService operations are synchronous

  /// Check if auth is initialized
  bool get isInitialized => SeSessionService().currentSession != null;

  /// Get any auth error
  String? get error => null; // SeSessionService doesn't store errors

  /// Clear auth error
  void clearError() {
    // SeSessionService doesn't store errors
  }

  /// Logout the current user
  Future<void> logout() async {
    await SeSessionService().logout();
  }

  /// Update user profile
  Future<bool> updateProfile({
    String? displayName,
    String? profilePicture,
  }) async {
    // SeSessionService doesn't support profile updates yet
    // This would need to be implemented if needed
    return false;
  }

  /// Export session identity
  Future<Map<String, String>> exportSessionIdentity() async {
    final session = SeSessionService().currentSession;
    if (session == null) return {};

    return {
      'sessionId': session.sessionId,
      'displayName': session.displayName,
      'publicKey': session.publicKey,
      'createdAt': session.createdAt.toIso8601String(),
    };
  }

  /// Delete session identity
  Future<bool> deleteSessionIdentity() async {
    try {
      await SeSessionService().deleteSession();
      return true;
    } catch (e) {
      return false;
    }
  }



  /// Check if user has contacts
  Future<bool> hasContacts() async {
    // This would need to be implemented based on invitation system
    return false;
  }

  /// Get user's contacts
  Map<String, dynamic> getContacts() {
    // This would need to be implemented based on invitation system
    return {};
  }
}
