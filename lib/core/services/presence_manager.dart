import 'package:flutter/foundation.dart';
import 'se_socket_service.dart';
import 'contact_service.dart';

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
      print('🟢 PresenceManager: 🔧 Initializing...');

      // Initialize contact service
      await _contactService.initialize();

      // Set up presence event listeners
      _setupPresenceListeners();

      // Set up contact event listeners
      _setupContactListeners();

      _isInitialized = true;
      print('🟢 PresenceManager: ✅ Initialized successfully');
    } catch (e) {
      print('🟢 PresenceManager: ❌ Failed to initialize: $e');
      rethrow;
    }
  }

  /// Set up presence event listeners
  void _setupPresenceListeners() {
    try {
      // Listen for presence updates from other users
      _socketService.setOnOnlineStatusUpdate((senderId, isOnline, lastSeen) {
        print(
            '🟢 PresenceManager: 📡 Presence update received: $senderId -> ${isOnline ? 'online' : 'offline'}');

        // Update contact presence in ContactService
        if (lastSeen != null) {
          final lastSeenTime = DateTime.parse(lastSeen);
          _contactService.updateContactPresence(
              senderId, isOnline, lastSeenTime);
        } else {
          final now = DateTime.now();
          _contactService.updateContactPresence(senderId, isOnline, now);
        }
      });

      print('🟢 PresenceManager: ✅ Presence event listeners set up');
    } catch (e) {
      print('🟢 PresenceManager: ❌ Error setting up presence listeners: $e');
    }
  }

  /// Set up contact event listeners
  void _setupContactListeners() {
    try {
      // Listen for contact added events
      _socketService.setOnContactAdded((data) {
        print('🟢 PresenceManager: 🔗 Contact added event received: $data');

        // The server has confirmed the contact was added
        // We can update our local contact list if needed
        notifyListeners();
      });

      // Listen for contact removed events
      _socketService.setOnContactRemoved((data) {
        print('🟢 PresenceManager: 🔗 Contact removed event received: $data');

        // The server has confirmed the contact was removed
        // We can update our local contact list if needed
        notifyListeners();
      });

      print('🟢 PresenceManager: ✅ Contact event listeners set up');
    } catch (e) {
      print('🟢 PresenceManager: ❌ Error setting up contact listeners: $e');
    }
  }

  /// Called when user session is registered
  void onSessionRegistered() {
    try {
      print(
          '🟢 PresenceManager: 🚀 Session registered, setting up presence system...');

      // Step 1: Broadcast online status to all existing contacts
      _socketService.broadcastPresenceToContacts();

      // Step 2: Update local online status
      _isOnline = true;
      _lastOnlineTime = DateTime.now();

      print(
          '🟢 PresenceManager: ✅ Online presence broadcasted to all contacts');
      notifyListeners();
    } catch (e) {
      print('🟢 PresenceManager: ❌ Error in onSessionRegistered: $e');
    }
  }

  /// Add a new contact (after successful key exchange)
  Future<void> addNewContact(
      String contactSessionId, String displayName) async {
    try {
      print(
          '🟢 PresenceManager: 🔗 Adding new contact: $displayName ($contactSessionId)');

      // Add to local contact list
      await _contactService.addContact(contactSessionId, displayName);

      // Broadcast your presence to the new contact
      _socketService.updatePresence(true, specificUsers: [contactSessionId]);

      print('🟢 PresenceManager: ✅ New contact added and presence broadcasted');
      notifyListeners();
    } catch (e) {
      print('🟢 PresenceManager: ❌ Error adding new contact: $e');
      rethrow;
    }
  }

  /// Called when user is going offline
  void onUserGoingOffline() {
    try {
      print(
          '🟢 PresenceManager: 📱 User going offline, broadcasting presence...');

      // Broadcast offline status to all contacts
      _socketService.broadcastPresenceToContacts();

      // Update local online status
      _isOnline = false;

      print(
          '🟢 PresenceManager: ✅ Offline presence broadcasted to all contacts');
      notifyListeners();
    } catch (e) {
      print('🟢 PresenceManager: ❌ Error in onUserGoingOffline: $e');
    }
  }

  /// Called when user is coming back online
  void onUserComingOnline() {
    try {
      print(
          '🟢 PresenceManager: 📱 User coming online, broadcasting presence...');

      // Broadcast online status to all contacts
      _socketService.broadcastPresenceToContacts();

      // Update local online status
      _isOnline = true;
      _lastOnlineTime = DateTime.now();

      print(
          '🟢 PresenceManager: ✅ Online presence broadcasted to all contacts');
      notifyListeners();
    } catch (e) {
      print('🟢 PresenceManager: ❌ Error in onUserComingOnline: $e');
    }
  }

  /// Update presence for specific users
  void updatePresenceForUsers(bool isOnline, List<String> userIds) {
    try {
      print(
          '🟢 PresenceManager: 📡 Updating presence for ${userIds.length} users: ${isOnline ? 'online' : 'offline'}');

      _socketService.updatePresence(isOnline, specificUsers: userIds);

      print('🟢 PresenceManager: ✅ Presence updated for specific users');
    } catch (e) {
      print(
          '🟢 PresenceManager: ❌ Error updating presence for specific users: $e');
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
    print('🟢 PresenceManager: 🗑️ Disposing manager...');
    super.dispose();
  }
}
