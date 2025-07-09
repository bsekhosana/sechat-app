import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/services/api_service.dart';
import '../../core/services/encryption_service.dart';
import '../../core/services/websocket_service.dart';
import '../models/user.dart';
import '../models/security_question.dart';

class AuthProvider extends ChangeNotifier {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  User? _currentUser;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _error;
  List<SecurityQuestion> _securityQuestions = [];

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String? get error => _error;
  List<SecurityQuestion> get securityQuestions => _securityQuestions;

  AuthProvider() {
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    _isLoading = true;
    notifyListeners();

    try {
      final deviceId = await _storage.read(key: 'device_id');
      final username = await _storage.read(key: 'username');
      final userId = await _storage.read(key: 'user_id');
      final loggedIn = await _storage.read(key: 'loggedin');

      print(
          '🔐 Auth Init - Device ID: $deviceId, Username: $username, Logged in: $loggedIn');

      if (deviceId != null && username != null && userId != null) {
        _currentUser = User(id: userId, deviceId: deviceId, username: username);

        // If user is marked as logged in, auto-authenticate
        if (loggedIn == 'true') {
          _isAuthenticated = true;
          print('🔐 Auto-login successful');

          // Connect to WebSocket (optional - don't fail if WebSocket is unavailable)
          if (!kIsWeb) {
            try {
              await WebSocketService.instance.connect();
            } catch (e) {
              print('WebSocket connection failed: $e');
              // Continue without WebSocket - basic functionality should still work
            }
          }
        } else {
          // User data exists but not logged in - this means we should show login screen
          print('🔐 User data found but not logged in - show login screen');
        }
      } else {
        // No user data - show welcome screen
        print('🔐 No user data found - show welcome screen');
      }
    } catch (e) {
      _error = e.toString();
      print('🔐 Auth initialization error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String username,
    required String password,
    required int securityQuestionId,
    required String securityAnswer,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Generate device ID if not exists
      String? deviceId = await _storage.read(key: 'device_id');
      if (deviceId == null) {
        deviceId = await EncryptionService.getDeviceId();
        await _storage.write(key: 'device_id', value: deviceId);
      }

      // Generate encryption keys
      await EncryptionService.generateKeyPair();

      final response = await ApiService.register({
        'device_id': deviceId,
        'username': username,
        'password': password,
        'security_question_id': securityQuestionId,
        'security_answer': securityAnswer,
      });

      if (response['success']) {
        await _storeUserData(
          userId: response['user_id'].toString(),
          username: username,
          deviceId: deviceId,
          isLoggedIn: true,
        );

        _currentUser = User(
          id: response['user_id'].toString(),
          deviceId: deviceId,
          username: username,
        );
        _isAuthenticated = true;

        // Connect to WebSocket after successful registration (optional)
        if (!kIsWeb) {
          try {
            await WebSocketService.instance.connect();
          } catch (e) {
            print('WebSocket connection failed: $e');
            // Continue without WebSocket - basic functionality should still work
          }
        }

        return true;
      } else {
        _error = response['message'] ?? 'Registration failed';
        return false;
      }
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> login({
    required String deviceId,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      print(
          '🔑 Attempting login with deviceId: $deviceId, password: $password');
      final response = await ApiService.login({
        'device_id': deviceId,
        'password': password,
      });

      if (response['success']) {
        // Save all user data locally for easier future logins
        await _storeUserData(
          userId: response['user_id'].toString(),
          username: response['username'],
          deviceId: deviceId,
          isLoggedIn: true,
        );

        _currentUser = User(
          id: response['user_id'].toString(),
          deviceId: deviceId,
          username: response['username'],
        );
        _isAuthenticated = true;

        // Connect to WebSocket after successful login (optional)
        if (!kIsWeb) {
          try {
            await WebSocketService.instance.connect();
          } catch (e) {
            print('WebSocket connection failed: $e');
            // Continue without WebSocket - basic functionality should still work
          }
        }

        return true;
      } else {
        _error = response['message'] ?? 'Login failed';
        return false;
      }
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    // Disconnect WebSocket
    WebSocketService.instance.disconnect();

    // Update loggedin status to false (keep user data for future login)
    await _storage.write(key: 'loggedin', value: 'false');

    _currentUser = null;
    _isAuthenticated = false;
    _error = null;
    notifyListeners();
  }

  // Store user data and loggedin status
  Future<void> _storeUserData({
    required String userId,
    required String username,
    required String deviceId,
    required bool isLoggedIn,
  }) async {
    await _storage.write(key: 'user_id', value: userId);
    await _storage.write(key: 'username', value: username);
    await _storage.write(key: 'device_id', value: deviceId);
    await _storage.write(key: 'loggedin', value: isLoggedIn ? 'true' : 'false');
  }

  // Check if user exists for this device (for login screen logic)
  Future<bool> userExistsForDevice() async {
    final deviceId = await _storage.read(key: 'device_id');
    final username = await _storage.read(key: 'username');
    return deviceId != null && username != null;
  }

  // Get stored username for login screen
  Future<String?> getStoredUsername() async {
    return await _storage.read(key: 'username');
  }

  // Fetch username from database using device ID
  Future<String?> fetchUsernameFromDeviceId() async {
    try {
      final deviceId = await _storage.read(key: 'device_id');
      if (deviceId == null) return null;

      // Call API to get user profile by device ID
      final response = await ApiService.getUserProfile();
      if (response['success'] && response['user'] != null) {
        final username = response['user']['username'];

        // Save username locally for future use
        await _storage.write(key: 'username', value: username);

        return username;
      }
    } catch (e) {
      print('🔐 Error fetching username from device ID: $e');
    }
    return null;
  }

  // Check if we have device ID but missing username
  Future<bool> hasDeviceIdButNoUsername() async {
    final deviceId = await _storage.read(key: 'device_id');
    final username = await _storage.read(key: 'username');
    return deviceId != null && username == null;
  }

  // Load security questions for registration
  Future<void> loadSecurityQuestions() async {
    try {
      final response = await ApiService.getSecurityQuestions();
      if (response['success']) {
        _securityQuestions = (response['questions'] as List)
            .map((q) => SecurityQuestion.fromJson(q))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      print('Error loading security questions: $e');
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  FlutterSecureStorage get storage => _storage;

  Future<String?> getUserSecurityQuestion() async {
    try {
      print('🔐 AuthProvider - Fetching security question');
      final response = await ApiService.getUserSecurityQuestion();
      print('🔐 AuthProvider - Security question response: $response');
      if (response['success'] == true && response['question'] != null) {
        final questionText = response['question']['question_text'];
        print('🔐 AuthProvider - Extracted question: $questionText');
        return questionText;
      } else {
        print('🔐 AuthProvider - No question found in response');
      }
    } catch (e) {
      print('Error fetching security question: $e');
    }
    return null;
  }

  Future<bool> verifySecurityAnswer(String answer) async {
    try {
      final response = await ApiService.verifySecurityAnswer(answer);
      return response['success'] == true;
    } catch (e) {
      print('Error verifying security answer: $e');
      return false;
    }
  }

  Future<bool> resetPassword(String newPassword) async {
    try {
      final response = await ApiService.resetPassword(newPassword);
      return response['success'] == true;
    } catch (e) {
      print('Error resetting password: $e');
      return false;
    }
  }

  Future<bool> deleteAccount() async {
    try {
      final response = await ApiService.deleteAccount();
      if (response['success'] == true) {
        // Clear all local storage
        await _storage.deleteAll();
        _currentUser = null;
        _isAuthenticated = false;
        _error = null;
        notifyListeners();
        return true;
      }
    } catch (e) {
      print('Error deleting account: $e');
    }
    return false;
  }
}
