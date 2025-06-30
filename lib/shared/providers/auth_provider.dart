import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/services/api_service.dart';
import '../../core/services/encryption_service.dart';
import '../../core/services/websocket_service.dart';
import '../models/user.dart';

class AuthProvider extends ChangeNotifier {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  User? _currentUser;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _error;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String? get error => _error;

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

      if (deviceId != null && username != null && userId != null) {
        _currentUser = User(id: userId, deviceId: deviceId, username: username);
        _isAuthenticated = true;

        // Connect to WebSocket
        await WebSocketService.instance.connect();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String username,
    required String password,
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
      });

      if (response['success']) {
        await _storage.write(
          key: 'user_id',
          value: response['user_id'].toString(),
        );
        await _storage.write(key: 'username', value: username);

        _currentUser = User(
          id: response['user_id'].toString(),
          deviceId: deviceId,
          username: username,
        );
        _isAuthenticated = true;

        // Connect to WebSocket after successful registration
        await WebSocketService.instance.connect();

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
      final response = await ApiService.login({
        'device_id': deviceId,
        'password': password,
      });

      if (response['success']) {
        await _storage.write(
          key: 'user_id',
          value: response['user_id'].toString(),
        );
        await _storage.write(key: 'username', value: response['username']);

        _currentUser = User(
          id: response['user_id'].toString(),
          deviceId: deviceId,
          username: response['username'],
        );
        _isAuthenticated = true;

        // Connect to WebSocket after successful login
        await WebSocketService.instance.connect();

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

    await _storage.deleteAll();
    _currentUser = null;
    _isAuthenticated = false;
    _error = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
