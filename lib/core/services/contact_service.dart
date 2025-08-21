import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../shared/models/contact.dart';
import 'se_socket_service.dart';

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
      return _contacts.firstWhere((contact) => contact.sessionId == sessionId);
    } catch (e) {
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
        print(
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

      print('📱 ContactService: ✅ Contact added: $displayName ($sessionId)');
      notifyListeners();
    } catch (e) {
      print('📱 ContactService: ❌ Error adding contact: $e');
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

      print('📱 ContactService: ✅ Contact removed: $sessionId');
      notifyListeners();
    } catch (e) {
      print('📱 ContactService: ❌ Error removing contact: $e');
      rethrow;
    }
  }

  /// Update contact presence status
  void updateContactPresence(
      String sessionId, bool isOnline, DateTime lastSeen) {
    try {
      final index = _contacts.indexWhere((c) => c.sessionId == sessionId);
      if (index != -1) {
        final contact = _contacts[index];
        _contacts[index] = contact.copyWith(
          isOnline: isOnline,
          lastSeen: lastSeen,
        );

        print(
            '📱 ContactService: ✅ Presence updated for $sessionId: ${isOnline ? 'online' : 'offline'}');
        notifyListeners();
      } else {
        print(
            '📱 ContactService: ⚠️ Contact not found for presence update: $sessionId');
      }
    } catch (e) {
      print('📱 ContactService: ❌ Error updating contact presence: $e');
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

        print(
            '📱 ContactService: ✅ Display name updated for $sessionId: $newDisplayName');
        notifyListeners();
      } else {
        print(
            '📱 ContactService: ⚠️ Contact not found for name update: $sessionId');
      }
    } catch (e) {
      print('📱 ContactService: ❌ Error updating contact display name: $e');
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
          print('📱 ContactService: ⚠️ Error parsing contact: $e');
        }
      }

      print(
          '📱 ContactService: ✅ Loaded ${_contacts.length} contacts from storage');
      notifyListeners();
    } catch (e) {
      print('📱 ContactService: ❌ Error loading contacts: $e');
    }
  }

  /// Save contacts to storage
  Future<void> _saveContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contactsJson =
          _contacts.map((contact) => json.encode(contact.toJson())).toList();

      await prefs.setStringList(_storageKey, contactsJson);
      print(
          '📱 ContactService: ✅ Saved ${_contacts.length} contacts to storage');
    } catch (e) {
      print('📱 ContactService: ❌ Error saving contacts: $e');
    }
  }

  /// Clear all contacts (used when account is deleted)
  Future<void> clearAllContacts() async {
    try {
      _contacts.clear();
      await _saveContacts();
      print('📱 ContactService: ✅ All contacts cleared');
      notifyListeners();
    } catch (e) {
      print('📱 ContactService: ❌ Error clearing contacts: $e');
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
      print('📱 ContactService: 🔧 Initializing...');

      // Load existing contacts from storage
      await loadContacts();

      print(
          '📱 ContactService: ✅ Initialized successfully with ${_contacts.length} contacts');
    } catch (e) {
      print('📱 ContactService: ❌ Failed to initialize: $e');
    }
  }

  /// Dispose the service
  @override
  void dispose() {
    print('📱 ContactService: 🗑️ Disposing service...');
    super.dispose();
  }
}
