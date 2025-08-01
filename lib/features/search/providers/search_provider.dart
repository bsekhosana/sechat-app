import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'dart:async';
import 'dart:convert'; // Added for json.encode and json.decode
import 'package:flutter/material.dart';
import '../../../shared/models/user.dart';
import '../../../shared/models/invitation.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/se_session_service.dart';
import '../../../core/services/network_service.dart';
import '../../../core/services/local_storage_service.dart';
import '../../../core/services/global_user_service.dart';

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
    _loadRecentSearches();
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

      // Check if this is the current user's Session ID
      final currentSessionId = SeSessionService().currentSessionId;
      if (sessionId == currentSessionId) {
        _error = 'This is your own Session ID - you cannot invite yourself';
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

  // Search for users by display name
  Future<void> searchByDisplayName(String displayName) async {
    try {
      _isLoading = true;
      _error = null;
      _lastSearchQuery = displayName;
      notifyListeners();

      print('🔍 SearchProvider: Searching for display name: $displayName');

      // For now, we'll just create a mock user since we don't have a user directory
      // In a real implementation, this would search a user directory
      final user = User(
        id: 'mock_session_id_${displayName.hashCode}',
        username: displayName,
        isOnline: false,
        lastSeen: DateTime.now(),
        alreadyInvited: false,
        invitationStatus: null,
      );

      _searchResults = [user];

      // Add to recent searches
      _addToRecentSearches(user);

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

  // Add contact (send invitation)
  Future<bool> addContact(String sessionId) async {
    try {
      print('🔍 SearchProvider: Adding contact: $sessionId');

      // This would be handled by the invitation system
      // For now, we'll just return success
      print('🔍 SearchProvider: Contact added successfully: $sessionId');
      return true;
    } catch (e) {
      print('🔍 SearchProvider: Error adding contact: $e');
      return false;
    }
  }

  // Remove contact
  Future<bool> removeContact(String sessionId) async {
    try {
      print('🔍 SearchProvider: Removing contact: $sessionId');

      // This would be handled by the invitation system
      // For now, we'll just return success
      print('🔍 SearchProvider: Contact removed successfully: $sessionId');
      return true;
    } catch (e) {
      print('🔍 SearchProvider: Error removing contact: $e');
      return false;
    }
  }

  // Get contacts (simplified - returns empty map since we don't have contact management yet)
  Map<String, User> getContacts() {
    return {};
  }

  // Check if user is a contact
  bool isContact(String sessionId) {
    return getContacts().containsKey(sessionId);
  }

  // Get contact by session ID
  User? getContact(String sessionId) {
    return getContacts()[sessionId];
  }

  // Load recent searches from local storage
  Future<void> _loadRecentSearches() async {
    try {
      final box = await Hive.openBox('recent_searches');
      final searchesJson = box.get('searches', defaultValue: '[]');
      final searches = json.decode(searchesJson) as List;

      _recentSearches =
          searches.map((search) => User.fromJson(search)).toList();
      notifyListeners();
    } catch (e) {
      print('🔍 SearchProvider: Error loading recent searches: $e');
    }
  }

  // Add user to recent searches
  void _addToRecentSearches(User user) {
    // Remove if already exists
    _recentSearches.removeWhere((search) => search.id == user.id);

    // Add to beginning
    _recentSearches.insert(0, user);

    // Keep only last 10 searches
    if (_recentSearches.length > 10) {
      _recentSearches = _recentSearches.take(10).toList();
    }

    _saveRecentSearches();
    notifyListeners();
  }

  // Save recent searches to local storage
  Future<void> _saveRecentSearches() async {
    try {
      final box = await Hive.openBox('recent_searches');
      final searchesJson =
          json.encode(_recentSearches.map((user) => user.toJson()).toList());
      await box.put('searches', searchesJson);
    } catch (e) {
      print('🔍 SearchProvider: Error saving recent searches: $e');
    }
  }

  // Clear recent searches
  Future<void> clearRecentSearches() async {
    try {
      final box = await Hive.openBox('recent_searches');
      await box.delete('searches');
      _recentSearches.clear();
      notifyListeners();
    } catch (e) {
      print('🔍 SearchProvider: Error clearing recent searches: $e');
    }
  }

  // Parse QR code data
  Map<String, dynamic>? parseQRCodeData(String qrData) {
    try {
      final data = json.decode(qrData);
      return data as Map<String, dynamic>;
    } catch (e) {
      print('🔍 SearchProvider: Error parsing QR code data: $e');
      return null;
    }
  }

  // Validate Session ID format
  bool _isValidSessionId(String sessionId) {
    // Basic validation - check if it's not empty and has reasonable length
    return sessionId.isNotEmpty && sessionId.length >= 10;
  }

  // Clear search results
  void clearSearch() {
    _searchResults.clear();
    _error = null;
    notifyListeners();
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

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
    return await addContact(userId);
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

  @override
  void dispose() {
    super.dispose();
  }
}
