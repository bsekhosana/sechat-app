import 'package:flutter/foundation.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/models/user.dart';

class SearchProvider extends ChangeNotifier {
  List<User> _searchResults = [];
  bool _isLoading = false;
  String? _error;
  String _lastQuery = '';

  List<User> get searchResults => _searchResults;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get lastQuery => _lastQuery;

  Future<void> searchUsers(String query) async {
    if (query.trim().isEmpty) {
      _searchResults = [];
      _lastQuery = '';
      notifyListeners();
      return;
    }

    if (query == _lastQuery) return; // Avoid duplicate searches

    _isLoading = true;
    _error = null;
    _lastQuery = query;
    notifyListeners();

    try {
      final response = await ApiService.searchUsers(query);

      if (response['success']) {
        _searchResults =
            (response['users'] as List)
                .map((userData) => User.fromJson(userData))
                .toList();
      } else {
        _error = response['message'] ?? 'Search failed';
      }
    } catch (e) {
      _error = e.toString();
      _searchResults = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    _searchResults = [];
    _lastQuery = '';
    _error = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  bool isUserInResults(String userId) {
    return _searchResults.any((user) => user.id == userId);
  }
}
