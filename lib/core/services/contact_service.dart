import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../shared/models/contact.dart';
import 'se_socket_service.dart';
import '../../features/chat/services/message_storage_service.dart';
import 'package:sechat_app//../core/utils/logger.dart';

/// Service for managing user contacts and their presence status
class ContactService extends ChangeNotifier {
  static ContactService? _instance;
  static ContactService get instance => _instance ??= ContactService._();

  ContactService._();

  final List<Contact> _contacts = [];
  final SeSocketService _socketService = SeSocketService.instance;

  // Storage key for contacts
  static const String _storageKey = 'user_contacts';

  List<Contact> get contacts => List.unmodifiable(_contacts);

  /// Get a specific contact by session ID
  Contact? getContact(String sessionId) {
    try {
      Logger.info(
          '📱 ContactService:  Looking for contact: $sessionId in ${_contacts.length} contacts');
      Logger.debug(
          '📱 ContactService: 🔍 Available contacts: ${_contacts.map((c) => c.sessionId).join(', ')}');
      final contact =
          _contacts.firstWhere((contact) => contact.sessionId == sessionId);
      Logger.debug(
          '📱 ContactService: ✅ Found contact: ${contact.sessionId} (${contact.isOnline ? 'online' : 'offline'})');
      return contact;
    } catch (e) {
      Logger.warning('📱 ContactService:  Contact not found: $sessionId');
      return null;
    }
  }

  /// Check if a user is a contact
  bool isContact(String sessionId) {
    return _contacts.any((contact) => contact.sessionId == sessionId);
  }

  /// Add a new contact
  Future<void> addContact(String sessionId, String displayName) async {
    try {
      // Check if contact already exists
      if (_contacts.any((c) => c.sessionId == sessionId)) {
        Logger.debug(
            '📱 ContactService: ℹ️ Contact already exists: $displayName ($sessionId)');
        return;
      }

      // Create new contact
      final contact = Contact(
        sessionId: sessionId,
        displayName: displayName,
        lastSeen: DateTime.now(),
      );

      // Add to local list
      _contacts.add(contact);

      // Save to storage
      await _saveContacts();

      // Notify server about new contact
      _socketService.addContact(sessionId);

      // Broadcast presence to the new contact
      _socketService.broadcastPresenceToContacts();

      Logger.debug(
          '📱 ContactService: ✅ Contact added: $displayName ($sessionId)');
      notifyListeners();
    } catch (e) {
      Logger.error('📱 ContactService:  Error adding contact: $e');
      rethrow;
    }
  }

  /// Remove a contact
  Future<void> removeContact(String sessionId) async {
    try {
      // Remove from local list
      _contacts.removeWhere((c) => c.sessionId == sessionId);

      // Save to storage
      await _saveContacts();

      // Notify server about contact removal
      _socketService.removeContact(sessionId);

      Logger.success('📱 ContactService:  Contact removed: $sessionId');
      notifyListeners();
    } catch (e) {
      Logger.error('📱 ContactService:  Error removing contact: $e');
      rethrow;
    }
  }

  /// Update contact presence status
  void updateContactPresence(
      String sessionId, bool isOnline, DateTime lastSeen) {
    try {
      Logger.debug(
          '📱 ContactService: 🔍 Attempting to update presence for: $sessionId (${isOnline ? 'online' : 'offline'})');
      Logger.debug(
          '📱 ContactService: 🔍 Current contacts: ${_contacts.map((c) => '${c.sessionId}:${c.isOnline}').join(', ')}');

      final index = _contacts.indexWhere((c) => c.sessionId == sessionId);
      if (index != -1) {
        final oldContact = _contacts[index];
        _contacts[index] = oldContact.copyWith(
          isOnline: isOnline,
          lastSeen: lastSeen,
        );

        Logger.success(
            '📱 ContactService:  Presence updated for $sessionId: ${oldContact.isOnline} -> $isOnline');
        notifyListeners();
        Logger.debug(
            '📱 ContactService: 🔔 notifyListeners() called for presence update');
      } else {
        Logger.warning(
            '📱 ContactService:  Contact not found for presence update: $sessionId');
        Logger.debug(
            '📱 ContactService: 🔍 Available contacts: ${_contacts.map((c) => c.sessionId).join(', ')}');

        // Auto-add contact if it doesn't exist but we're receiving presence updates
        // This can happen when conversations exist but contacts weren't properly added
        Logger.debug(
            '📱 ContactService: 🔧 Auto-adding contact for presence update');
        final newContact = Contact(
          sessionId: sessionId,
          displayName:
              sessionId, // Will be updated later when we get proper display name
          isOnline: isOnline,
          lastSeen: lastSeen,
          createdAt: DateTime.now(),
        );
        _contacts.add(newContact);
        _saveContacts(); // Save to persistence

        Logger.success(
            '📱 ContactService:  Auto-added contact for presence: $sessionId');
        notifyListeners();
        Logger.debug(
            '📱 ContactService: 🔔 notifyListeners() called for auto-add');
      }
    } catch (e) {
      Logger.error('📱 ContactService:  Error updating contact presence: $e');
    }
  }

  /// Update contact display name
  Future<void> updateContactDisplayName(
      String sessionId, String newDisplayName) async {
    try {
      final index = _contacts.indexWhere((c) => c.sessionId == sessionId);
      if (index != -1) {
        final contact = _contacts[index];
        _contacts[index] = contact.copyWith(
          displayName: newDisplayName,
        );

        // Save to storage
        await _saveContacts();

        Logger.success(
            '📱 ContactService:  Display name updated for $sessionId: $newDisplayName');
        notifyListeners();
      } else {
        Logger.warning(
            '📱 ContactService:  Contact not found for name update: $sessionId');
      }
    } catch (e) {
      Logger.error(
          '📱 ContactService:  Error updating contact display name: $e');
      rethrow;
    }
  }

  /// Load contacts from storage
  Future<void> loadContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contactsJson = prefs.getStringList(_storageKey) ?? [];

      _contacts.clear();
      for (final contactJson in contactsJson) {
        try {
          final contactData = json.decode(contactJson) as Map<String, dynamic>;
          final contact = Contact.fromJson(contactData);
          _contacts.add(contact);
        } catch (e) {
          Logger.warning('📱 ContactService:  Error parsing contact: $e');
        }
      }

      Logger.success(
          '📱 ContactService:  Loaded ${_contacts.length} contacts from storage');
      notifyListeners();
    } catch (e) {
      Logger.error('📱 ContactService:  Error loading contacts: $e');
    }
  }

  /// Save contacts to storage
  Future<void> _saveContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contactsJson =
          _contacts.map((contact) => json.encode(contact.toJson())).toList();

      await prefs.setStringList(_storageKey, contactsJson);
      Logger.success(
          '📱 ContactService:  Saved ${_contacts.length} contacts to storage');
    } catch (e) {
      Logger.error('📱 ContactService:  Error saving contacts: $e');
    }
  }

  /// Clear all contacts (used when account is deleted)
  Future<void> clearAllContacts() async {
    try {
      _contacts.clear();
      await _saveContacts();
      Logger.success('📱 ContactService:  All contacts cleared');
      notifyListeners();
    } catch (e) {
      Logger.error('📱 ContactService:  Error clearing contacts: $e');
    }
  }

  /// Get online contacts count
  int get onlineContactsCount => _contacts.where((c) => c.isOnline).length;

  /// Get offline contacts count
  int get offlineContactsCount => _contacts.where((c) => !c.isOnline).length;

  /// Get contacts that were last seen recently (within last hour)
  List<Contact> get recentlyActiveContacts {
    final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
    return _contacts.where((c) => c.lastSeen.isAfter(oneHourAgo)).toList();
  }

  /// Initialize the service
  Future<void> initialize() async {
    try {
      Logger.debug('📱 ContactService: 🔧 Initializing...');

      // Load existing contacts from storage
      await loadContacts();

      // CRITICAL: Sync contacts from existing conversations
      // This ensures we have contacts for presence requests even on fresh login
      await _syncContactsFromConversations();

      Logger.success(
          '📱 ContactService:  Initialized successfully with ${_contacts.length} contacts');
    } catch (e) {
      Logger.error('📱 ContactService:  Failed to initialize: $e');
    }
  }

  /// Sync contacts from existing conversations to ensure presence works
  Future<void> _syncContactsFromConversations() async {
    try {
      Logger.info(
          '📱 ContactService:  Syncing contacts from existing conversations...');

      // Import MessageStorageService to get existing conversations
      // This ensures we have contacts even if they weren't properly added before
      try {
        // Get existing conversations from MessageStorageService
        // We'll create contacts for each conversation participant
        final messageStorageService = MessageStorageService.instance;
        final conversations = await messageStorageService.getConversations();

        Logger.info(
            '📱 ContactService:  Found ${conversations.length} existing conversations');

        for (final conversation in conversations) {
          final conversationId = conversation.id;

          // CRITICAL FIX: Create contacts for both participants, not the conversation ID
          final participant1Id = conversation.participant1Id;
          final participant2Id = conversation.participant2Id;

          // Create contact for participant1 if not exists
          if (participant1Id.isNotEmpty && !isContact(participant1Id)) {
            Logger.debug(
                '📱 ContactService: 🔧 Creating contact for participant1: $participant1Id');

            final contact1 = Contact(
              sessionId: participant1Id, // ✅ Use actual user ID
              displayName: conversation
                  .getDisplayName(participant1Id), // ✅ Use actual user ID
              lastSeen: DateTime.now().subtract(const Duration(minutes: 5)),
              createdAt: DateTime.now(),
            );

            _contacts.add(contact1);
            Logger.success(
                '📱 ContactService:  Contact created for participant1: ${contact1.displayName}');
          }

          // Create contact for participant2 if not exists
          if (participant2Id.isNotEmpty && !isContact(participant2Id)) {
            Logger.debug(
                '📱 ContactService: 🔧 Creating contact for participant2: $participant2Id');

            final contact2 = Contact(
              sessionId: participant2Id, // ✅ Use actual user ID
              displayName: conversation
                  .getDisplayName(participant2Id), // ✅ Use actual user ID
              lastSeen: DateTime.now().subtract(const Duration(minutes: 5)),
              createdAt: DateTime.now(),
            );

            _contacts.add(contact2);
            Logger.success(
                '📱 ContactService:  Contact created for participant2: ${contact2.displayName}');
          }
        }

        // Save the new contacts
        if (conversations.isNotEmpty) {
          await _saveContacts();
          Logger.success(
              '📱 ContactService:  Synced ${conversations.length} contacts from conversations');
        }
      } catch (e) {
        Logger.warning(
            '📱 ContactService:  Could not sync from conversations: $e');
        // This is not critical - we can still function without it
      }
    } catch (e) {
      Logger.error(
          '📱 ContactService:  Error syncing contacts from conversations: $e');
    }
  }

  /// Dispose the service
  @override
  void dispose() {
    Logger.info('📱 ContactService:  Disposing service...');
    super.dispose();
  }
}
