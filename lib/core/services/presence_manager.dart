import 'package:flutter/foundation.dart';
import 'se_socket_service.dart';
import 'contact_service.dart';
import '/..//../core/utils/logger.dart';

/// Manager for handling all presence-related functionality
class PresenceManager extends ChangeNotifier {
  static PresenceManager? _instance;
  static PresenceManager get instance => _instance ??= PresenceManager._();

  PresenceManager._();

  final SeSocketService _socketService = SeSocketService.instance;
  final ContactService _contactService = ContactService.instance;

  bool _isInitialized = false;
  bool _isOnline = false;
  DateTime? _lastOnlineTime;

  bool get isInitialized => _isInitialized;
  bool get isOnline => _isOnline;
  DateTime? get lastOnlineTime => _lastOnlineTime;

  /// Initialize the presence manager
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      Logger.debug('🟢 PresenceManager: 🔧 Initializing...');

      // Initialize contact service
      await _contactService.initialize();

      // Set up presence event listeners
      _setupPresenceListeners();

      // Set up contact event listeners
      _setupContactListeners();

      _isInitialized = true;
      Logger.success('🟢 PresenceManager:  Initialized successfully');
    } catch (e) {
      Logger.error('🟢 PresenceManager:  Failed to initialize: $e');
      rethrow;
    }
  }

  /// Set up presence event listeners - REMOVED DUPLICATE CALLBACK
  void _setupPresenceListeners() {
    try {
      // REMOVED: Direct callback to avoid conflict with main.dart
      // Presence updates now handled through main.dart -> ContactService
      Logger.debug(
          '🟢 PresenceManager: ℹ️ Presence updates handled via main.dart callback (no duplicate)');
      Logger.success('🟢 PresenceManager:  Presence event listeners set up');
    } catch (e) {
      Logger.error(
          '🟢 PresenceManager:  Error setting up presence listeners: $e');
    }
  }

  /// Set up contact event listeners
  void _setupContactListeners() {
    try {
      // Listen for contact added events
      _socketService.setOnContactAdded((data) {
        Logger.debug(
            '🟢 PresenceManager: 🔗 Contact added event received: $data');

        // The server has confirmed the contact was added
        // We can update our local contact list if needed
        notifyListeners();
      });

      // Listen for contact removed events
      _socketService.setOnContactRemoved((data) {
        Logger.debug(
            '🟢 PresenceManager: 🔗 Contact removed event received: $data');

        // The server has confirmed the contact was removed
        // We can update our local contact list if needed
        notifyListeners();
      });

      Logger.success('🟢 PresenceManager:  Contact event listeners set up');
    } catch (e) {
      Logger.error(
          '🟢 PresenceManager:  Error setting up contact listeners: $e');
    }
  }

  /// Called when user session is registered
  void onSessionRegistered() {
    try {
      Logger.info(
          '🟢 PresenceManager:  Session registered, setting up presence system...');

      // Step 1: Update local online status first
      _isOnline = true;
      _lastOnlineTime = DateTime.now();

      // Step 2: Broadcast online status to all existing contacts (only if we have contacts)
      if (_contactService.contacts.isNotEmpty) {
        _socketService.broadcastPresenceToContacts();
        Logger.success(
            '🟢 PresenceManager:  Online presence broadcasted to ${_contactService.contacts.length} contacts');

        // Step 3: Request current presence status for all contacts
        _requestContactsPresenceStatus();
      } else {
        Logger.info(
            '🟢 PresenceManager:  No contacts to broadcast presence to');
      }

      notifyListeners();
    } catch (e) {
      Logger.error('🟢 PresenceManager:  Error in onSessionRegistered: $e');
    }
  }

  /// Request presence status for all contacts - ENHANCED BIDIRECTIONAL
  void _requestContactsPresenceStatus() {
    try {
      Logger.info(
          '🟢 PresenceManager:  Requesting presence status for all contacts...');

      final contactIds =
          _contactService.contacts.map((c) => c.sessionId).toList();
      if (contactIds.isNotEmpty) {
        // Method 1: Send a presence request to get current status of all contacts
        _socketService.requestPresenceStatus(contactIds);

        // Method 2: Also send individual presence updates to trigger responses
        // This ensures bidirectional presence even if server doesn't handle presence:request
        for (final contactId in contactIds) {
          _socketService.updatePresence(true, specificUsers: [contactId]);
        }

        Logger.debug(
            '🟢 PresenceManager: ✅ Presence status requested for ${contactIds.length} contacts (bidirectional)');
      } else {
        Logger.info('🟢 PresenceManager:  No contacts to request presence for');
      }
    } catch (e) {
      Logger.error(
          '🟢 PresenceManager:  Error requesting contacts presence status: $e');
    }
  }

  /// Add a new contact (after successful key exchange)
  Future<void> addNewContact(
      String contactSessionId, String displayName) async {
    try {
      Logger.debug(
          '🟢 PresenceManager: 🔗 Adding new contact: $displayName ($contactSessionId)');

      // Add to local contact list
      await _contactService.addContact(contactSessionId, displayName);

      // Only broadcast presence if we're currently online
      if (_isOnline) {
        _socketService.updatePresence(true, specificUsers: [contactSessionId]);
        Logger.success(
            '🟢 PresenceManager:  Presence sent to new contact: $displayName');
      } else {
        Logger.info(
            '🟢 PresenceManager:  User offline, skipping presence broadcast to new contact');
      }

      Logger.success('🟢 PresenceManager:  New contact added successfully');
      notifyListeners();
    } catch (e) {
      Logger.error('🟢 PresenceManager:  Error adding new contact: $e');
      rethrow;
    }
  }

  /// Called when user is going offline
  void onUserGoingOffline() {
    try {
      Logger.debug(
          '🟢 PresenceManager: 📱 User going offline, broadcasting presence...');

      // Broadcast offline status to all contacts
      _socketService.broadcastPresenceToContacts();

      // Update local online status
      _isOnline = false;

      Logger.success(
          '🟢 PresenceManager:  Offline presence broadcasted to all contacts');
      notifyListeners();
    } catch (e) {
      Logger.error('🟢 PresenceManager:  Error in onUserGoingOffline: $e');
    }
  }

  /// Called when user is coming back online
  void onUserComingOnline() {
    try {
      Logger.debug(
          '🟢 PresenceManager: 📱 User coming online, broadcasting presence...');

      // Update local online status first
      _isOnline = true;
      _lastOnlineTime = DateTime.now();

      // Broadcast online status to all contacts
      _socketService.broadcastPresenceToContacts();

      // Also request current presence status of all contacts for bidirectional updates
      _requestContactsPresenceStatus();

      Logger.success(
          '🟢 PresenceManager:  Online presence broadcasted and requested from all contacts');
      notifyListeners();
    } catch (e) {
      Logger.error('🟢 PresenceManager:  Error in onUserComingOnline: $e');
    }
  }

  /// Manually refresh presence status for all contacts
  void refreshAllContactsPresence() {
    try {
      Logger.info(
          '🟢 PresenceManager:  Manually refreshing all contacts presence...');
      _requestContactsPresenceStatus();
    } catch (e) {
      Logger.error(
          '🟢 PresenceManager:  Error refreshing contacts presence: $e');
    }
  }

  /// Force presence broadcast and request (for testing/debugging)
  void forcePresenceSync() {
    try {
      Logger.info('🟢 PresenceManager:  Force presence sync initiated...');

      // Step 1: Broadcast our presence to all contacts
      _socketService.broadcastPresenceToContacts();

      // Step 2: Request presence from all contacts
      _requestContactsPresenceStatus();

      Logger.success('🟢 PresenceManager:  Force presence sync completed');
    } catch (e) {
      Logger.error('🟢 PresenceManager:  Error in force presence sync: $e');
    }
  }

  /// Update presence for specific users
  void updatePresenceForUsers(bool isOnline, List<String> userIds) {
    try {
      Logger.debug(
          '🟢 PresenceManager: 📡 Updating presence for ${userIds.length} users: ${isOnline ? 'online' : 'offline'}');

      _socketService.updatePresence(isOnline, specificUsers: userIds);

      Logger.success(
          '🟢 PresenceManager:  Presence updated for specific users');
    } catch (e) {
      Logger.error(
          '🟢 PresenceManager:  Error updating presence for specific users: $e');
    }
  }

  /// Get online contacts count
  int get onlineContactsCount => _contactService.onlineContactsCount;

  /// Get offline contacts count
  int get offlineContactsCount => _contactService.offlineContactsCount;

  /// Get all contacts
  List<dynamic> get contacts => _contactService.contacts;

  /// Get a specific contact
  dynamic getContact(String sessionId) => _contactService.getContact(sessionId);

  /// Check if a user is a contact
  bool isContact(String sessionId) => _contactService.isContact(sessionId);

  /// Get contacts that were recently active
  List<dynamic> get recentlyActiveContacts =>
      _contactService.recentlyActiveContacts;

  /// Dispose the manager
  @override
  void dispose() {
    Logger.info('🟢 PresenceManager:  Disposing manager...');
    super.dispose();
  }

  /// Sync presence with a newly added contact (2-way presence update)
  Future<void> syncPresenceWithNewContact(String contactSessionId) async {
    try {
      Logger.info(
          '🟢 PresenceManager:  Syncing presence with new contact: $contactSessionId');

      // Step 1: Broadcast our presence to the new contact
      _socketService.updatePresence(true, specificUsers: [contactSessionId]);
      Logger.success(
          '🟢 PresenceManager:  Our presence broadcasted to new contact: $contactSessionId');

      // Step 2: Request presence status from the new contact
      _socketService.requestPresenceStatus([contactSessionId]);
      Logger.success(
          '🟢 PresenceManager:  Presence status requested from new contact: $contactSessionId');

      // Step 3: Also send individual presence update to trigger response
      _socketService.updatePresence(true, specificUsers: [contactSessionId]);
      Logger.success(
          '🟢 PresenceManager:  Individual presence update sent to new contact: $contactSessionId');

      Logger.success(
          '🟢 PresenceManager:  2-way presence sync completed for new contact: $contactSessionId');
    } catch (e) {
      Logger.error(
          '🟢 PresenceManager:  Error syncing presence with new contact: $contactSessionId: $e');
      rethrow;
    }
  }
}
