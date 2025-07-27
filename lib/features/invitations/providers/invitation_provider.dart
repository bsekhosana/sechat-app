import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import '../../../shared/models/invitation.dart';
import '../../../shared/models/user.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/network_service.dart';
import '../../../core/services/local_storage_service.dart';
import '../../../core/services/simple_notification_service.dart';
import '../../../core/services/global_user_service.dart';
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
    _setupNotificationHandlers();
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

  void _setupNotificationHandlers() {
    // Set up notification service callbacks for real-time updates
    SimpleNotificationService.instance
        .setOnInvitationReceived(handleIncomingInvitation);
    SimpleNotificationService.instance
        .setOnInvitationResponse(handleInvitationResponse);

    print(
        '📱 InvitationProvider: ✅ Notification handlers set up for real-time updates');
  }

  // Handle incoming invitation notification
  Future<void> handleIncomingInvitation(
      String senderId, String senderName, String invitationId) async {
    print(
        '📱 InvitationProvider: Received invitation from $senderName ($senderId) with ID: $invitationId');

    // Create invitation record
    final invitation = Invitation(
      id: invitationId,
      senderId: senderId,
      recipientId: SessionService.instance.currentSessionId ?? '',
      senderUsername: senderName,
      recipientUsername: GlobalUserService.instance.currentUsername ?? '',
      message: 'Contact request',
      status: 'pending',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isReceived: true, // This is a received invitation
    );

    print(
        '📱 InvitationProvider: Created invitation object: ${invitation.toJson()}');

    // Check if invitation already exists
    final existingInvitation =
        _invitations.any((inv) => inv.id == invitationId);
    print(
        '📱 InvitationProvider: Invitation already exists: $existingInvitation');

    // Add to list if not already present
    if (!existingInvitation) {
      // Add new invitation at the top (index 0) for real-time updates
      _invitations.insert(0, invitation);

      // Sort by creation time (newest first) to ensure proper ordering
      _invitations.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      print(
          '📱 InvitationProvider: Added invitation to list. Total invitations: ${_invitations.length}');

      // Save to local storage
      await LocalStorageService.instance
          .saveInvitations(_invitations.map((inv) => inv.toJson()).toList());

      notifyListeners();
      print(
          '📱 InvitationProvider: ✅ Added incoming invitation: $invitationId and notified listeners');
    } else {
      // TODO: show a message that the invitation already exists

      print(
          '📱 InvitationProvider: Invitation already exists, skipping: $invitationId');
    }
  }

  // Handle invitation response notification
  Future<void> handleInvitationResponse(
      String responderId, String responderName, String status) async {
    print(
        '📱 InvitationProvider: Received invitation response from $responderName ($responderId): $status');

    // Find and update the invitation
    final invitationIndex = _invitations.indexWhere(
        (inv) => inv.recipientId == responderId && inv.status == 'pending');

    if (invitationIndex != -1) {
      final oldInvitation = _invitations[invitationIndex];
      final updatedInvitation = Invitation(
        id: oldInvitation.id,
        senderId: oldInvitation.senderId,
        recipientId: oldInvitation.recipientId,
        senderUsername: oldInvitation.senderUsername,
        recipientUsername: oldInvitation.recipientUsername,
        message: oldInvitation.message,
        status: status,
        createdAt: oldInvitation.createdAt,
        updatedAt: DateTime.now(),
      );

      _invitations[invitationIndex] = updatedInvitation;

      // Save to local storage
      await LocalStorageService.instance
          .saveInvitations(_invitations.map((inv) => inv.toJson()).toList());

      notifyListeners();
      print('📱 InvitationProvider: Updated invitation status to: $status');
    }
  }

  void _handleLocalStorageChange() {
    print(
        '📱 InvitationProvider: Local storage changed, reloading invitations...');
    _loadInvitationsFromLocal();
    _scheduleNotifyListeners();
  }

  void _scheduleNotifyListeners() {
    // Schedule notification to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        notifyListeners();
      } catch (e) {
        print('📱 InvitationProvider: Error notifying listeners: $e');
      }
    });
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
      print('📱 InvitationProvider: Loading invitations from local storage...');
      final invitationData =
          await LocalStorageService.instance.getInvitations();
      print(
          '📱 InvitationProvider: Found ${invitationData.length} invitations in storage');

      // Debug: Print each invitation data
      for (int i = 0; i < invitationData.length; i++) {
        print('📱 InvitationProvider: Invitation $i: ${invitationData[i]}');
      }

      _invitations =
          invitationData.map((data) => Invitation.fromJson(data)).toList();
      print('📱 InvitationProvider: Loaded ${_invitations.length} invitations');

      // Debug: Print each loaded invitation
      for (int i = 0; i < _invitations.length; i++) {
        print(
            '📱 InvitationProvider: Loaded invitation $i: ${_invitations[i].toJson()}');
      }

      notifyListeners();
      print('📱 InvitationProvider: ✅ Notified listeners of invitation update');
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
        senderUsername: GlobalUserService.instance.currentUsername ?? '',
        recipientUsername: displayName ?? 'Anonymous User',
        message: 'Contact request',
        status: 'accepted', // In Session, adding contact is immediate
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isReceived: false, // This is a sent invitation (user initiated contact)
      );

      // Add new invitation at the top (index 0) for real-time updates
      _invitations.insert(0, invitation);

      // Sort by creation time (newest first) to ensure proper ordering
      _invitations.sort((a, b) => b.createdAt.compareTo(a.createdAt));

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

      // Show instant notification for successful contact addition
      await SimpleNotificationService.instance.showLocalNotification(
        title: 'Contact Added',
        body: 'Contact $displayName added successfully',
        type: 'contact_added',
        data: {
          'contactName': displayName ?? 'Anonymous',
          'invitationId': invitation.id,
        },
      );

      print('📱 InvitationProvider: Contact added: $sessionId');
    } catch (e) {
      _error = 'Failed to add contact: $e';
      _scheduleNotifyListeners();
      print('📱 InvitationProvider: Error adding contact: $e');
    } finally {
      _isLoading = false;
      _scheduleNotifyListeners();
    }
  }

  // Remove contact using Session Protocol
  Future<void> removeContact(String sessionId) async {
    try {
      _isLoading = true;
      _error = null;
      _scheduleNotifyListeners();

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
      _scheduleNotifyListeners();
      print('📱 InvitationProvider: Error removing contact: $e');
    } finally {
      _isLoading = false;
      _scheduleNotifyListeners();
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
        isReceived: false, // This is a sent invitation (contact was added)
      );

      // Add new invitation at the top (index 0) for real-time updates
      _invitations.insert(0, invitation);

      // Sort by creation time (newest first) to ensure proper ordering
      _invitations.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Show notification for contact added (invitation accepted)
      await SimpleNotificationService.instance.showLocalNotification(
        title: 'Contact Added',
        body: '${contact.name ?? 'Anonymous User'} is now your contact',
        type: 'contact_added',
        data: {
          'contactName': contact.name ?? 'Anonymous User',
          'status': 'accepted',
          'invitationId': invitation.id,
        },
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

  // Load invitations (merge local storage with Session contacts)
  Future<void> loadInvitations({bool forceRefresh = false}) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      print(
          '📱 InvitationProvider: Loading invitations (merge local storage with Session contacts)... forceRefresh: $forceRefresh');

      // First, load invitations from local storage
      await _loadInvitationsFromLocal();
      print(
          '📱 InvitationProvider: Loaded ${_invitations.length} invitations from local storage');

      // Get contacts from Session Service
      final contacts = SessionService.instance.contacts;
      print('📱 InvitationProvider: Found ${contacts.length} Session contacts');

      // Create a map of existing invitation IDs to avoid duplicates
      final existingInvitationIds = _invitations.map((inv) => inv.id).toSet();
      print(
          '📱 InvitationProvider: Existing invitation IDs: $existingInvitationIds');

      // Check if we already have Session contacts in our invitations
      final hasSessionContacts = _invitations
          .any((inv) => inv.status == 'accepted' && inv.isReceived == false);

      print(
          '📱 InvitationProvider: Already has Session contacts: $hasSessionContacts');

      // Only add Session contacts if we don't have them already or if force refresh is requested
      int addedCount = 0;
      if (!hasSessionContacts || forceRefresh) {
        // Add Session contacts as invitations (if not already present)
        for (final contact in contacts.values) {
          if (!existingInvitationIds.contains(contact.sessionId)) {
            final sessionInvitation = Invitation(
              id: contact.sessionId,
              senderId:
                  SessionService.instance.currentIdentity?.sessionId ?? '',
              recipientId: contact.sessionId,
              message: 'Contact added',
              status: 'accepted',
              createdAt: contact.lastSeen,
              updatedAt: contact.lastSeen,
              isReceived:
                  false, // These are sent invitations (user initiated contact)
            );

            _invitations.add(sessionInvitation);
            addedCount++;
            print(
                '📱 InvitationProvider: Added Session contact as invitation: ${contact.sessionId}');
          } else {
            print(
                '📱 InvitationProvider: Skipped duplicate Session contact: ${contact.sessionId}');
          }

          // Create user objects for contacts (always update user data)
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

        // Only save to local storage if we actually added new invitations
        if (addedCount > 0) {
          await LocalStorageService.instance.saveInvitations(
              _invitations.map((inv) => inv.toJson()).toList());
          print(
              '📱 InvitationProvider: Saved ${_invitations.length} invitations to local storage (added $addedCount new)');
        } else {
          print(
              '📱 InvitationProvider: No new invitations added, skipping local storage save');
        }
      } else {
        print(
            '📱 InvitationProvider: Session contacts already exist, skipping addition');

        // Still update user objects for contacts
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
      }

      // Sort by creation time (newest first)
      _invitations.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Only save to local storage if we actually added new invitations
      if (addedCount > 0) {
        await LocalStorageService.instance
            .saveInvitations(_invitations.map((inv) => inv.toJson()).toList());
        print(
            '📱 InvitationProvider: Saved ${_invitations.length} invitations to local storage (added $addedCount new)');
      } else {
        print(
            '📱 InvitationProvider: No new invitations added, skipping local storage save');
      }

      print(
          '📱 InvitationProvider: Loaded ${_invitations.length} total invitations (local + Session contacts)');
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
    // No state change needed, so no notifyListeners() call
  }

  // Check if there are unread invitations
  bool get hasUnreadInvitations {
    // In Session Protocol, all contacts are considered "read"
    return false;
  }

  // Block user via Session ID and update invitation status
  Future<bool> blockUser(String sessionId) async {
    try {
      print('📱 InvitationProvider: Blocking user via Session ID: $sessionId');

      // Find the invitation for this user
      final invitation = _invitations.firstWhere(
        (inv) => inv.senderId == sessionId || inv.recipientId == sessionId,
        orElse: () =>
            throw Exception('Invitation not found for user: $sessionId'),
      );

      // Update invitation status to blocked (but keep it for reference)
      final updatedInvitation = invitation.copyWith(
        status: 'blocked',
        updatedAt: DateTime.now(),
      );

      // Update in memory
      final index = _invitations.indexWhere((inv) => inv.id == invitation.id);
      if (index != -1) {
        _invitations[index] = updatedInvitation;
      }

      // Save to local storage for persistence
      await LocalStorageService.instance
          .saveInvitations(_invitations.map((inv) => inv.toJson()).toList());

      // Update user status to blocked
      if (_invitationUsers.containsKey(sessionId)) {
        final user = _invitationUsers[sessionId]!;
        final updatedUser = user.copyWith(
          invitationStatus: 'blocked',
        );
        _invitationUsers[sessionId] = updatedUser;
      }

      // Remove contact via Session Protocol (this effectively blocks them)
      try {
        await SessionService.instance.removeContact(sessionId);
        print(
            '📱 InvitationProvider: ✅ User removed via Session Protocol: $sessionId');
      } catch (e) {
        print('📱 InvitationProvider: ⚠️ Session Protocol removal failed: $e');
        // Continue anyway - we've already blocked locally
      }

      notifyListeners();
      print('📱 InvitationProvider: ✅ User blocked successfully: $sessionId');
      return true;
    } catch (e) {
      print('📱 InvitationProvider: Error blocking user: $e');
      _error = 'Failed to block user: $e';
      notifyListeners();
      return false;
    }
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

  // Delete invitation (does NOT delete notifications - they persist independently)
  Future<bool> deleteInvitation(String invitationId) async {
    try {
      _invitations.removeWhere((inv) => inv.id == invitationId);

      // Save updated invitations to local storage for persistence
      await LocalStorageService.instance
          .saveInvitations(_invitations.map((inv) => inv.toJson()).toList());

      notifyListeners();
      print(
          '📱 InvitationProvider: ✅ Deleted invitation $invitationId and saved to local storage (notifications preserved)');
      return true;
    } catch (e) {
      print('📱 InvitationProvider: Error deleting invitation: $e');
      return false;
    }
  }

  // [STEP 1] Send invitation using AirNotifier
  Future<bool> sendInvitation(String recipientId,
      {required String displayName}) async {
    // The display name is required and will be the name saved for this contact on the local device

    try {
      // [STEP 2] Validate invitation request
      // Check if trying to invite yourself
      final currentSessionId = SessionService.instance.currentSessionId;
      if (recipientId == currentSessionId) {
        print(
            '📱 InvitationProvider: Cannot send invitation to yourself: $recipientId');
        return false;
      }

      if (isUserInvited(recipientId)) {
        print(
            '📱 InvitationProvider: User $recipientId is already in contacts');
        return false;
      }

      if (isUserQueued(recipientId)) {
        print(
            '📱 InvitationProvider: Invitation to $recipientId is already pending');
        return false;
      }

      // [STEP 3] Generate unique invitation ID and prepare data
      final invitationId =
          'inv_${DateTime.now().millisecondsSinceEpoch}_${recipientId}';

      final recipientName = displayName; // Display name is now required

      // Get current user info from global user service
      final senderName =
          GlobalUserService.instance.currentUsername ?? 'Unknown User';

      // [STEP 4] Send push notification via SimpleNotificationService
      final success = await SimpleNotificationService.instance.sendInvitation(
        recipientId: recipientId,
        senderName: senderName,
        invitationId: invitationId,
        message: 'Contact request',
      );

      if (success) {
        print(
            '📱 InvitationProvider: Invitation sent via AirNotifier to: $recipientId');

        // [STEP 5] Create invitation record for local tracking
        final invitation = Invitation(
          id: invitationId,
          senderId: SessionService.instance.currentSessionId ?? '',
          recipientId: recipientId,
          senderUsername: senderName,
          recipientUsername: recipientName,
          message: 'Contact request',
          status: 'pending', // Set as pending until recipient responds
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          isReceived: false, // This is a sent invitation
        );

        // Add new invitation at the top (index 0) for real-time updates
        _invitations.insert(0, invitation);

        // Sort by creation time (newest first) to ensure proper ordering
        _invitations.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        // [STEP 6] Create local notification for sender's notifications screen
        // Show recipient's name in the notification (not sender's name)
        await SimpleNotificationService.instance.showLocalNotification(
          title: 'Invitation Sent',
          body: 'Invitation sent to $recipientName',
          type: 'invitation_sent',
          data: {
            'recipientName': recipientName,
            'invitationId': invitationId,
          },
        );

        notifyListeners();

        // No local notification for sender - only recipient should get notification

        return true;
      } else {
        print(
            '📱 InvitationProvider: Failed to send invitation via AirNotifier to: $recipientId');

        // Set error message for UI display
        _error =
            'Failed to send invitation. Recipient may be offline or not registered.';
        _scheduleNotifyListeners();

        return false;
      }
    } catch (e) {
      print('📱 InvitationProvider: Error sending invitation: $e');

      // Set error message for UI display
      _error = 'Failed to send invitation: ${e.toString()}';
      _scheduleNotifyListeners();

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
