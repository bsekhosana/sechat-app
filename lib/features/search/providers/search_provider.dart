import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/models/user.dart';

class SearchProvider extends ChangeNotifier {
  List<User> _searchResults = [];
  bool _isLoading = false;
  String _error = '';
  String _query = '';
  Timer? _debounceTimer;
  bool _showResults = false;

  List<User> get searchResults => _searchResults;
  bool get isLoading => _isLoading;
  String get error => _error;
  String get query => _query;
  bool get showResults => _showResults;

  void searchUsers(String query) {
    _query = query.trim();

    // Cancel previous timer
    _debounceTimer?.cancel();

    // Clear results and hide dropdown if query is too short
    if (_query.length < 3) {
      _searchResults.clear();
      _showResults = false;
      _isLoading = false;
      notifyListeners();
      return;
    }

    // DON'T set loading immediately - wait for timer
    // Reset previous results but don't show loading yet
    _searchResults.clear();
    _showResults = false;
    _isLoading = false;
    notifyListeners();

    // Start debounce timer (3 seconds) - only then start loading
    _debounceTimer = Timer(const Duration(seconds: 3), () {
      // NOW start loading
      _isLoading = true;
      _showResults = false; // Hide until we have results
      notifyListeners();
      _performSearch();
    });
  }

  Future<void> _performSearch() async {
    try {
      _error = '';

      // Make search case insensitive by converting to lowercase
      final searchQuery = _query.toLowerCase();

      print('🔍 Search Provider - Starting search for: $searchQuery');

      // Simulate API call - replace with actual API endpoint
      final response = await ApiService.searchUsers(searchQuery);

      print('🔍 Search Provider - API Response: $response');

      if (response['success']) {
        print('🔍 Search Provider - Users from API: ${response['users']}');

        _searchResults = (response['users'] as List).map((userData) {
          final user = User.fromJson(userData);
          // Set default online status to true until WebSocket provides real data
          return user.copyWith(isOnline: true);
        }).toList();

        print(
            '🔍 Search Provider - Parsed users count: ${_searchResults.length}');
        print('🔍 Search Provider - Parsed users: $_searchResults');
      } else {
        print('🔍 Search Provider - API Error: ${response['message']}');
        _error = response['message'] ?? 'Search failed';
        _searchResults.clear();
      }

      // Don't auto-close for no results - let user see the "no results" message
      // Only auto-close on actual errors
    } catch (e) {
      print('🔍 Search Provider - Exception: $e');
      _error = 'Search error: $e';
      _searchResults.clear();

      // Auto-close on error after 3 seconds
      Timer(const Duration(seconds: 3), () {
        if (mounted) hideResults();
      });
    } finally {
      _isLoading = false;
      _showResults = true; // NOW show results (including no results)
      print(
          '🔍 Search Provider - Final state - loading: $_isLoading, showResults: $_showResults, results count: ${_searchResults.length}');
      notifyListeners();
    }
  }

  Future<bool> sendInvitation(String userId) async {
    try {
      print('🔍 Search Provider - Sending invitation to user: $userId');

      final response = await ApiService.sendInvitation({
        'recipient_id': userId, // Changed from 'user_id' to 'recipient_id'
        'message': 'Hi! Let\'s chat on SeChat!',
      });

      print('🔍 Search Provider - Invitation response: $response');

      if (response['success']) {
        // Remove user from search results since they've been invited
        _searchResults.removeWhere((user) => user.id == userId);
        notifyListeners();
        return true;
      } else {
        _error = response['message'] ?? 'Failed to send invitation';
        notifyListeners();
        return false;
      }
    } catch (e) {
      print('🔍 Search Provider - Invitation error: $e');
      _error = 'Invitation error: $e';
      notifyListeners();
      return false;
    }
  }

  void hideResults() {
    _showResults = false;
    _searchResults.clear();
    _isLoading = false;
    notifyListeners();
  }

  void clearSearch() {
    _query = '';
    _searchResults.clear();
    _isLoading = false;
    _showResults = false;
    _error = '';
    _debounceTimer?.cancel();
    notifyListeners();
  }

  void clearError() {
    _error = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  // Helper to check if provider is still mounted
  bool get mounted => hasListeners;
}
