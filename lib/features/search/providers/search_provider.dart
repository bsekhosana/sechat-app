import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'dart:async';
import 'dart:convert'; // Added for json.encode and json.decode
import 'package:flutter/material.dart';
import '../../../shared/models/user.dart';
import '../../../shared/models/invitation.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/network_service.dart';
import '../../../core/services/local_storage_service.dart';

// Search state enum
enum SearchState { idle, loading, success, error, noResults }

class SearchProvider extends ChangeNotifier {
  List<User> _searchResults = [];
  List<User> _recentSearches = [];
  bool _isLoading = false;
  String? _error;
  String _lastSearchQuery = '';

  List<User> get searchResults => _searchResults;
  List<User> get recentSearches => _recentSearches;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get lastSearchQuery => _lastSearchQuery;

  SearchProvider() {
    _setupSession();
    _loadRecentSearches();
  }

  void _setupSession() {
    // Set up Session Protocol event handlers
    SessionService.instance.onContactAdded = _handleContactAdded;
    SessionService.instance.onContactUpdated = _handleContactUpdated;
    SessionService.instance.onContactRemoved = _handleContactRemoved;
    SessionService.instance.onError = _handleSessionError;
  }

  // Search for users by Session ID
  Future<void> searchBySessionId(String sessionId) async {
    try {
      _isLoading = true;
      _error = null;
      _lastSearchQuery = sessionId;
      notifyListeners();

      print('🔍 SearchProvider: Searching for Session ID: $sessionId');

      // Validate Session ID format
      if (!_isValidSessionId(sessionId)) {
        _error = 'Invalid Session ID format';
        _searchResults = [];
        return;
      }

      // Check if this Session ID is already a contact
      final contacts = SessionService.instance.contacts;
      if (contacts.containsKey(sessionId)) {
        _error = 'This user is already in your contacts';
        _searchResults = [];
        return;
      }

      // Check if this is the current user's Session ID
      final currentSessionId = SessionService.instance.currentSessionId;
      if (sessionId == currentSessionId) {
        _error = 'This is your own Session ID';
        _searchResults = [];
        return;
      }

      // Create a user object for the found Session ID
      final user = User(
        id: sessionId,
        username: 'Anonymous User',
        isOnline: false,
        lastSeen: DateTime.now(),
        alreadyInvited: false,
        invitationStatus: null,
      );

      _searchResults = [user];

      // Add to recent searches
      _addToRecentSearches(user);

      print('🔍 SearchProvider: Search completed for Session ID: $sessionId');
    } catch (e) {
      print('🔍 SearchProvider: Error searching by Session ID: $e');
      _error = 'Search failed: $e';
      _searchResults = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Search for users by display name (if available in Session Protocol)
  Future<void> searchByDisplayName(String displayName) async {
    try {
      _isLoading = true;
      _error = null;
      _lastSearchQuery = displayName;
      notifyListeners();

      print('🔍 SearchProvider: Searching for display name: $displayName');

      // In Session Protocol, searching by display name is limited
      // as it prioritizes privacy. We can only search within our contacts
      final contacts = SessionService.instance.contacts.values
          .where((contact) =>
              contact.name?.toLowerCase().contains(displayName.toLowerCase()) ==
              true)
          .toList();

      if (contacts.isEmpty) {
        _error = 'No users found with this display name';
        _searchResults = [];
        return;
      }

      // Convert SessionContact to User objects
      _searchResults = contacts
          .map((contact) => User(
                id: contact.sessionId,
                username: contact.name ?? 'Anonymous User',
                profilePicture: contact.profilePicture,
                isOnline: contact.isOnline,
                lastSeen: contact.lastSeen,
                alreadyInvited: true,
                invitationStatus: 'accepted',
              ))
          .toList();

      print(
          '🔍 SearchProvider: Found ${_searchResults.length} users with display name: $displayName');
    } catch (e) {
      print('🔍 SearchProvider: Error searching by display name: $e');
      _error = 'Search failed: $e';
      _searchResults = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Add contact (Session Protocol equivalent of sending invitation)
  Future<bool> addContact(String sessionId,
      {String? displayName, String? profilePicture}) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      print('🔍 SearchProvider: Adding contact: $sessionId');

      // Add contact via Session Protocol
      await SessionService.instance.addContact(
        sessionId: sessionId,
        name: displayName,
        profilePicture: profilePicture,
      );

      // Remove from search results
      _searchResults.removeWhere((user) => user.id == sessionId);

      print('🔍 SearchProvider: Contact added successfully: $sessionId');
      return true;
    } catch (e) {
      print('🔍 SearchProvider: Error adding contact: $e');
      _error = 'Failed to add contact: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Remove contact
  Future<bool> removeContact(String sessionId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      print('🔍 SearchProvider: Removing contact: $sessionId');

      // Remove contact via Session Protocol
      await SessionService.instance.removeContact(sessionId);

      print('🔍 SearchProvider: Contact removed successfully: $sessionId');
      return true;
    } catch (e) {
      print('🔍 SearchProvider: Error removing contact: $e');
      _error = 'Failed to remove contact: $e';
      return false;
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

  // Load recent searches from local storage
  Future<void> _loadRecentSearches() async {
    try {
      final recentSearchesData =
          await LocalStorageService.instance.getRecentSearches();
      _recentSearches = recentSearchesData;
      notifyListeners();
    } catch (e) {
      print('🔍 SearchProvider: Error loading recent searches: $e');
    }
  }

  // Add user to recent searches
  void _addToRecentSearches(User user) {
    // Remove if already exists
    _recentSearches.removeWhere((u) => u.id == user.id);

    // Add to beginning
    _recentSearches.insert(0, user);

    // Keep only last 10 searches
    if (_recentSearches.length > 10) {
      _recentSearches = _recentSearches.take(10).toList();
    }

    // Save to local storage
    LocalStorageService.instance.saveRecentSearches(_recentSearches);
  }

  // Clear recent searches
  Future<void> clearRecentSearches() async {
    try {
      _recentSearches.clear();
      await LocalStorageService.instance.clearRecentSearches();
      notifyListeners();
    } catch (e) {
      print('🔍 SearchProvider: Error clearing recent searches: $e');
    }
  }

  // Clear search results
  void clearSearchResults() {
    _searchResults.clear();
    _error = null;
    notifyListeners();
  }

  // Validate Session ID format
  bool _isValidSessionId(String sessionId) {
    // Session IDs are typically 66 characters long and contain alphanumeric characters
    return sessionId.length == 66 &&
        RegExp(r'^[A-Za-z0-9]+$').hasMatch(sessionId);
  }

  // Generate QR code data for sharing Session ID
  String? generateQRCodeData(String sessionId) {
    if (!_isValidSessionId(sessionId)) return null;

    final qrData = {
      'sessionId': sessionId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    return json.encode(qrData);
  }

  // Parse QR code data
  Map<String, dynamic>? parseQRCodeData(String qrData) {
    try {
      final data = json.decode(qrData) as Map<String, dynamic>;

      if (!data.containsKey('sessionId')) {
        throw Exception('Invalid QR code: missing sessionId');
      }

      return data;
    } catch (e) {
      print('🔍 SearchProvider: Error parsing QR code data: $e');
      return null;
    }
  }

  // Session Protocol Event Handlers
  void _handleContactAdded(LocalSessionContact contact) {
    try {
      print(
          '🔍 SearchProvider: Contact added via Session: ${contact.sessionId}');

      // Update search results if this contact was found in search
      final index =
          _searchResults.indexWhere((user) => user.id == contact.sessionId);
      if (index != -1) {
        _searchResults[index] = _searchResults[index].copyWith(
          alreadyInvited: true,
          invitationStatus: 'accepted',
        );
      }

      notifyListeners();
    } catch (e) {
      print('🔍 SearchProvider: Error handling contact added: $e');
    }
  }

  void _handleContactUpdated(LocalSessionContact contact) {
    try {
      print(
          '🔍 SearchProvider: Contact updated via Session: ${contact.sessionId}');

      // Update search results if this contact was found in search
      final index =
          _searchResults.indexWhere((user) => user.id == contact.sessionId);
      if (index != -1) {
        _searchResults[index] = _searchResults[index].copyWith(
          username: contact.name ?? 'Anonymous User',
          profilePicture: contact.profilePicture,
        );
      }

      notifyListeners();
    } catch (e) {
      print('🔍 SearchProvider: Error handling contact updated: $e');
    }
  }

  void _handleContactRemoved(String sessionId) {
    try {
      print('🔍 SearchProvider: Contact removed via Session: $sessionId');

      // Remove from search results
      _searchResults.removeWhere((user) => user.id == sessionId);

      notifyListeners();
    } catch (e) {
      print('🔍 SearchProvider: Error handling contact removed: $e');
    }
  }

  void _handleSessionError(String error) {
    print('🔍 SearchProvider: Session error: $error');
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
    _searchResults.clear();
    _recentSearches.clear();
    _isLoading = false;
    _error = null;
    _lastSearchQuery = '';
    notifyListeners();
  }

  // Public methods for UI compatibility

  // Search users (main search method)
  Future<void> searchUsers(String query) async {
    if (query.isEmpty) {
      _searchResults = [];
      _error = null;
      notifyListeners();
      return;
    }

    // Determine if query looks like a Session ID
    if (_isValidSessionId(query)) {
      await searchBySessionId(query);
    } else {
      await searchByDisplayName(query);
    }
  }

  // Clear search
  void clearSearch() {
    _searchResults.clear();
    _error = null;
    _lastSearchQuery = '';
    notifyListeners();
  }

  // Network error state
  bool get showNetworkError {
    return !NetworkService.instance.isConnected;
  }

  // Current search state
  SearchState get searchState {
    if (_isLoading) return SearchState.loading;
    if (_error != null) return SearchState.error;
    if (_searchResults.isEmpty && _lastSearchQuery.isNotEmpty)
      return SearchState.noResults;
    if (_searchResults.isNotEmpty) return SearchState.success;
    return SearchState.idle;
  }

  // Current query
  String get query => _lastSearchQuery;

  // Manual retry
  Future<void> manualRetry() async {
    if (_lastSearchQuery.isNotEmpty) {
      await searchUsers(_lastSearchQuery);
    }
  }

  // Show results
  bool get showResults => _searchResults.isNotEmpty;

  // Check if invitation is loading
  bool isInvitationLoading(String userId) {
    // This would need to be implemented with a loading state map
    // For now, return false
    return false;
  }

  // Remove invitation (remove contact)
  Future<bool> removeInvitation(String userId) async {
    return await removeContact(userId);
  }

  // Send invitation (add contact)
  Future<bool> sendInvitation(String userId) async {
    final user = _searchResults.firstWhere((u) => u.id == userId);
    return await addContact(
      userId,
      displayName: user.username,
      profilePicture: user.profilePicture,
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
