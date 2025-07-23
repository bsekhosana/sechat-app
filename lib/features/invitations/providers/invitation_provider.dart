import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../../shared/models/invitation.dart';
import '../../../shared/models/user.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/network_service.dart';
import '../../../core/services/local_storage_service.dart';
import '../../../core/services/notification_service.dart';
import 'dart:async';

class InvitationProvider extends ChangeNotifier {
  List<Invitation> _invitations = [];
  final Map<String, User> _invitationUsers = {};
  bool _isLoading = false;
  String? _error;
  bool _isSyncingPendingInvitations = false;

  List<Invitation> get invitations => _invitations;
  bool get isLoading => _isLoading;
  String? get error => _error;

  User? getInvitationUser(String userId) {
    return _invitationUsers[userId];
  }

  InvitationProvider() {
    _setupSession();
    _setupNetworkListener();
    _loadInvitationsFromLocal();
    _setupLocalStorageListener();
  }

  void _setupSession() {
    // Set up Session Protocol event handlers for contact management
    SessionService.instance.onContactAdded = _handleContactAdded;
    SessionService.instance.onContactUpdated = _handleContactUpdated;
    SessionService.instance.onContactRemoved = _handleContactRemoved;
    SessionService.instance.onConnected = _handleSessionConnected;
    SessionService.instance.onDisconnected = _handleSessionDisconnected;
    SessionService.instance.onError = _handleSessionError;
  }

  void _setupNetworkListener() {
    NetworkService.instance.addListener(_handleNetworkChange);
  }

  void _setupLocalStorageListener() {
    LocalStorageService.instance.addListener(_handleLocalStorageChange);
  }

  void _handleLocalStorageChange() {
    _loadInvitationsFromLocal();
    notifyListeners();
  }

  bool _isHandlingNetworkChange = false;

  void _handleNetworkChange() {
    if (_isHandlingNetworkChange) {
      print(
          '📱 InvitationProvider: Network change handler already in progress, skipping...');
      return;
    }

    _isHandlingNetworkChange = true;
    final networkService = NetworkService.instance;

    if (networkService.isConnected && !networkService.isReconnecting) {
      print('📱 InvitationProvider: Network reconnected, refreshing services');

      if (!SessionService.instance.isConnected) {
        print(
            '📱 InvitationProvider: Session not connected - attempting to connect');
        SessionService.instance.connect();
      } else {
        NetworkService.instance.handleSuccessfulReconnection();
      }

      _syncPendingInvitations();
    } else if (!networkService.isConnected) {
      print('📱 InvitationProvider: Network disconnected');
    }

    Timer(const Duration(seconds: 2), () {
      _isHandlingNetworkChange = false;
    });
  }

  void _syncPendingInvitations() {
    if (_isSyncingPendingInvitations) {
      print(
          '📱 InvitationProvider: Already syncing pending invitations, skipping...');
      return;
    }

    _isSyncingPendingInvitations = true;
    print('📱 InvitationProvider: Syncing pending invitations...');

    // In Session Protocol, we don't have traditional invitations
    // Instead, we sync contacts and their status
    _isSyncingPendingInvitations = false;
  }

  // Load invitations from local storage
  Future<void> _loadInvitationsFromLocal() async {
    try {
      final invitationData =
          await LocalStorageService.instance.getInvitations();
      _invitations =
          invitationData.map((data) => Invitation.fromJson(data)).toList();
      notifyListeners();
    } catch (e) {
      print(
          '📱 InvitationProvider: Error loading invitations from local storage: $e');
    }
  }

  // Add contact using Session Protocol
  Future<void> addContact({
    required String sessionId,
    String? displayName,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Add contact via Session Protocol
      await SessionService.instance.addContact(
        sessionId: sessionId,
        name: displayName,
      );

      // Create invitation record for local tracking
      final invitation = Invitation(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: SessionService.instance.currentSessionId ?? '',
        recipientId: sessionId,
        message: 'Contact request',
        status: 'accepted', // In Session, adding contact is immediate
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      _invitations.add(invitation);

      // Create user object for the contact
      final user = User(
        id: sessionId,
        username: displayName ?? 'Anonymous User',
        profilePicture: null, // No profile picture in Session Protocol
        isOnline: false,
        lastSeen: DateTime.now(),
        alreadyInvited: true,
        invitationStatus: 'accepted',
      );

      _invitationUsers[sessionId] = user;

      // Save to local storage
      await LocalStorageService.instance
          .saveInvitations(_invitations.map((inv) => inv.toJson()).toList());

      // Show instant notification for successful invitation
      await NotificationService.instance.showInvitationReceivedNotification(
        senderUsername: displayName ?? 'Anonymous',
        message: 'Contact request sent successfully',
        invitationId: invitation.id,
      );

      print('📱 InvitationProvider: Contact added: $sessionId');
    } catch (e) {
      _error = 'Failed to add contact: $e';
      notifyListeners();
      print('📱 InvitationProvider: Error adding contact: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Remove contact using Session Protocol
  Future<void> removeContact(String sessionId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Remove contact via Session Protocol
      await SessionService.instance.removeContact(sessionId);

      // Remove from local invitations
      _invitations.removeWhere((inv) => inv.recipientId == sessionId);
      _invitationUsers.remove(sessionId);

      // Save to local storage
      await LocalStorageService.instance
          .saveInvitations(_invitations.map((inv) => inv.toJson()).toList());

      print('📱 InvitationProvider: Contact removed: $sessionId');
    } catch (e) {
      _error = 'Failed to remove contact: $e';
      notifyListeners();
      print('📱 InvitationProvider: Error removing contact: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Get all contacts
  Map<String, LocalSessionContact> getContacts() {
    return SessionService.instance.contacts;
  }

  // Check if user is a contact
  bool isContact(String sessionId) {
    return SessionService.instance.contacts.containsKey(sessionId);
  }

  // Get contact by session ID
  LocalSessionContact? getContact(String sessionId) {
    return SessionService.instance.contacts[sessionId];
  }

  // Update contact profile
  Future<bool> updateContactProfile({
    required String sessionId,
    String? displayName,
    String? profilePicture,
  }) async {
    try {
      // Update contact via Session Protocol
      // Note: This would need to be implemented in SessionService
      print('📱 InvitationProvider: Updating contact profile: $sessionId');

      // Update local user object
      final user = _invitationUsers[sessionId];
      if (user != null) {
        _invitationUsers[sessionId] = user.copyWith(
          username: displayName ?? user.username,
          profilePicture: profilePicture ?? user.profilePicture,
        );
      }

      notifyListeners();
      return true;
    } catch (e) {
      print('📱 InvitationProvider: Error updating contact profile: $e');
      _error = 'Failed to update contact profile: $e';
      notifyListeners();
      return false;
    }
  }

  // Block contact
  Future<bool> blockContact(String sessionId) async {
    try {
      print('📱 InvitationProvider: Blocking contact: $sessionId');

      // Block contact via Session Protocol
      // Note: This would need to be implemented in SessionService

      // Update local user object
      final user = _invitationUsers[sessionId];
      if (user != null) {
        _invitationUsers[sessionId] = user.copyWith(
            // Add blocked status to User model if needed
            );
      }

      notifyListeners();
      return true;
    } catch (e) {
      print('📱 InvitationProvider: Error blocking contact: $e');
      _error = 'Failed to block contact: $e';
      notifyListeners();
      return false;
    }
  }

  // Unblock contact
  Future<bool> unblockContact(String sessionId) async {
    try {
      print('📱 InvitationProvider: Unblocking contact: $sessionId');

      // Unblock contact via Session Protocol
      // Note: This would need to be implemented in SessionService

      notifyListeners();
      return true;
    } catch (e) {
      print('📱 InvitationProvider: Error unblocking contact: $e');
      _error = 'Failed to unblock contact: $e';
      notifyListeners();
      return false;
    }
  }

  // Get blocked contacts
  List<LocalSessionContact> getBlockedContacts() {
    return SessionService.instance.contacts.values
        .where((contact) => contact.isBlocked)
        .toList();
  }

  // Refresh contacts from Session Protocol
  Future<void> refreshContacts() async {
    try {
      print('📱 InvitationProvider: Refreshing contacts...');

      // Contacts are automatically managed by Session Protocol
      // This method can be used to trigger UI updates
      notifyListeners();
    } catch (e) {
      print('📱 InvitationProvider: Error refreshing contacts: $e');
      _error = 'Failed to refresh contacts: $e';
      notifyListeners();
    }
  }

  // Session Protocol Event Handlers
  void _handleContactAdded(LocalSessionContact contact) async {
    try {
      print(
          '📱 InvitationProvider: Contact added via Session: ${contact.sessionId}');

      // Create user object for the contact
      final user = User(
        id: contact.sessionId,
        username: contact.name ?? 'Anonymous User',
        profilePicture: contact.profilePicture,
        isOnline: contact.isOnline,
        lastSeen: contact.lastSeen,
        alreadyInvited: true,
        invitationStatus: 'accepted',
      );

      _invitationUsers[contact.sessionId] = user;

      // Create invitation record
      final invitation = Invitation(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: SessionService.instance.currentSessionId ?? '',
        recipientId: contact.sessionId,
        message: 'Contact added',
        status: 'accepted',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      _invitations.add(invitation);

      // Show notification for contact added (invitation accepted)
      await NotificationService.instance.showInvitationResponseNotification(
        username: contact.name ?? 'Anonymous User',
        status: 'accepted',
        invitationId: invitation.id,
      );

      notifyListeners();
    } catch (e) {
      print('📱 InvitationProvider: Error handling contact added: $e');
    }
  }

  void _handleContactUpdated(LocalSessionContact contact) {
    try {
      print(
          '📱 InvitationProvider: Contact updated via Session: ${contact.sessionId}');

      // Update local user object
      final user = User(
        id: contact.sessionId,
        username: contact.name ?? 'Anonymous User',
        profilePicture: contact.profilePicture,
        isOnline: contact.isOnline,
        lastSeen: contact.lastSeen,
        alreadyInvited: true,
        invitationStatus: 'accepted',
      );

      _invitationUsers[contact.sessionId] = user;

      notifyListeners();
    } catch (e) {
      print('📱 InvitationProvider: Error handling contact updated: $e');
    }
  }

  void _handleContactRemoved(String sessionId) {
    try {
      print('📱 InvitationProvider: Contact removed via Session: $sessionId');

      // Remove from local data
      _invitationUsers.remove(sessionId);
      _invitations.removeWhere((inv) => inv.recipientId == sessionId);

      notifyListeners();
    } catch (e) {
      print('📱 InvitationProvider: Error handling contact removed: $e');
    }
  }

  void _handleSessionConnected() {
    print('📱 InvitationProvider: Session connected');
    // Refresh contacts when Session connects
    refreshContacts();
  }

  void _handleSessionDisconnected() {
    print('📱 InvitationProvider: Session disconnected');
  }

  void _handleSessionError(String error) {
    print('📱 InvitationProvider: Session error: $error');
    _error = error;
    notifyListeners();
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Reset provider state
  void reset() {
    _invitations.clear();
    _invitationUsers.clear();
    _isLoading = false;
    _error = null;
    _isSyncingPendingInvitations = false;
    notifyListeners();
  }

  // Public methods for UI compatibility

  // Load invitations (Session contacts)
  Future<void> loadInvitations() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      print('📱 InvitationProvider: Loading invitations (Session contacts)...');

      // Get contacts from Session Service
      final contacts = SessionService.instance.contacts;

      // Convert contacts to invitations
      _invitations = contacts.values.map((contact) {
        return Invitation(
          id: contact.sessionId,
          senderId: SessionService.instance.currentIdentity?.sessionId ?? '',
          recipientId: contact.sessionId,
          message: 'Contact added',
          status: 'accepted',
          createdAt: contact.lastSeen,
          updatedAt: contact.lastSeen,
        );
      }).toList();

      // Create user objects for contacts
      for (final contact in contacts.values) {
        _invitationUsers[contact.sessionId] = User(
          id: contact.sessionId,
          username: contact.name ?? 'Anonymous User',
          profilePicture: contact.profilePicture,
          isOnline: contact.isOnline,
          lastSeen: contact.lastSeen,
          alreadyInvited: true,
          invitationStatus: 'accepted',
        );
      }

      print('📱 InvitationProvider: Loaded ${_invitations.length} invitations');
    } catch (e) {
      print('📱 InvitationProvider: Error loading invitations: $e');
      _error = 'Failed to load invitations: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Mark received invitations as read
  void markReceivedInvitationsAsRead() {
    // In Session Protocol, all contacts are considered "read"
    notifyListeners();
  }

  // Mark sent invitations as read
  void markSentInvitationsAsRead() {
    // In Session Protocol, all contacts are considered "read"
    notifyListeners();
  }

  // Set on invitations screen (for tracking UI state)
  void setOnInvitationsScreen(bool isOnScreen) {
    // This method is for UI state tracking
    notifyListeners();
  }

  // Check if there are unread invitations
  bool get hasUnreadInvitations {
    // In Session Protocol, all contacts are considered "read"
    return false;
  }

  // Accept invitation (Session Protocol equivalent)
  Future<bool> acceptInvitation(String invitationId) async {
    try {
      final invitation =
          _invitations.firstWhere((inv) => inv.id == invitationId);

      // Update invitation status
      final updatedInvitation = invitation.copyWith(
        status: 'accepted',
        updatedAt: DateTime.now(),
      );

      final index = _invitations.indexWhere((inv) => inv.id == invitationId);
      if (index != -1) {
        _invitations[index] = updatedInvitation;
      }

      // Add as contact in Session Protocol
      await SessionService.instance.addContact(
        sessionId: invitation.recipientId,
        name: _invitationUsers[invitation.recipientId]?.username,
        profilePicture:
            _invitationUsers[invitation.recipientId]?.profilePicture,
      );

      notifyListeners();
      return true;
    } catch (e) {
      print('📱 InvitationProvider: Error accepting invitation: $e');
      return false;
    }
  }

  // Decline invitation
  Future<bool> declineInvitation(String invitationId) async {
    try {
      final invitation =
          _invitations.firstWhere((inv) => inv.id == invitationId);

      // Update invitation status
      final updatedInvitation = invitation.copyWith(
        status: 'declined',
        updatedAt: DateTime.now(),
      );

      final index = _invitations.indexWhere((inv) => inv.id == invitationId);
      if (index != -1) {
        _invitations[index] = updatedInvitation;
      }

      notifyListeners();
      return true;
    } catch (e) {
      print('📱 InvitationProvider: Error declining invitation: $e');
      return false;
    }
  }

  // Delete invitation
  Future<bool> deleteInvitation(String invitationId) async {
    try {
      _invitations.removeWhere((inv) => inv.id == invitationId);
      notifyListeners();
      return true;
    } catch (e) {
      print('📱 InvitationProvider: Error deleting invitation: $e');
      return false;
    }
  }

  // Send invitation (Session Protocol equivalent)
  Future<bool> sendInvitation(String recipientId) async {
    try {
      await addContact(
        sessionId: recipientId,
        displayName: null, // Will be fetched from Session network
      );
      return true;
    } catch (e) {
      print('📱 InvitationProvider: Error sending invitation: $e');
      return false;
    }
  }

  // Check if user is invited
  bool isUserInvited(String userId) {
    return _invitations
        .any((inv) => inv.recipientId == userId && inv.status == 'accepted');
  }

  // Check if user is queued (pending invitation)
  bool isUserQueued(String userId) {
    return _invitations
        .any((inv) => inv.recipientId == userId && inv.status == 'pending');
  }

  @override
  void dispose() {
    // Remove network listener
    NetworkService.instance.removeListener(_handleNetworkChange);
    super.dispose();
  }
}
