import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/services/session_service.dart';
import '../../core/services/airnotifier_service.dart';
import '../../core/services/native_push_service.dart';
import '../models/user.dart';
import 'dart:convert';

class AuthProvider extends ChangeNotifier {
  static AuthProvider? _instance;
  static AuthProvider get instance => _instance ??= AuthProvider._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  User? _currentUser;
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;

  // Session Protocol specific
  String? _sessionId;
  String? _displayName;
  String? _profilePicture;
  bool _isFirstTime = true;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isInitialized => _isInitialized;
  String? get sessionId => _sessionId;
  String? get displayName => _displayName;
  String? get profilePicture => _profilePicture;
  bool get isFirstTime => _isFirstTime;

  AuthProvider._() {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _isLoading = true;
      notifyListeners();

      // Check if Session identity exists
      final sessionIdentity = await _storage.read(key: 'session_identity');

      if (sessionIdentity != null) {
        // User has existing Session identity
        final identity = json.decode(sessionIdentity);
        _sessionId = identity['sessionId'];
        _displayName = await _storage.read(key: 'display_name');
        _profilePicture = await _storage.read(key: 'profile_picture');
        _isFirstTime = false;

        // Initialize Session Protocol
        await SessionService.instance.initialize();

        // Initialize AirNotifier service for push notifications
        await AirNotifierService.instance.initialize(sessionId: _sessionId!);
        print('🔐 Auth: AirNotifier service initialized');

        // Register device token with Session ID if available
        try {
          await NativePushService.instance
              .registerStoredDeviceToken(_sessionId!);
          print('🔐 Auth: Device token registered with Session ID');
        } catch (e) {
          print('🔐 Auth: Error registering device token: $e');
        }

        // Create user object from Session identity
        _currentUser = User(
          id: _sessionId!,
          username: _displayName ?? 'Anonymous User',
          profilePicture: _profilePicture,
          isOnline: true,
          lastSeen: DateTime.now(),
        );

        _isAuthenticated = true;
        print('🔐 Auth: Session identity restored: $_sessionId');
      } else {
        // First time user - will need to create Session identity
        _isFirstTime = true;
        print('🔐 Auth: First time user - no Session identity found');
      }

      _isInitialized = true;
    } catch (e) {
      print('🔐 Auth: Error during initialization: $e');
      _error = 'Failed to initialize: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Create new Session identity (first time setup)
  Future<bool> createSessionIdentity({
    required String displayName,
    String? profilePicture,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      print('🔐 Auth: Creating new Session identity...');

      // Initialize Session Protocol
      await SessionService.instance.initialize();

      // Get the generated Session identity
      final identity = SessionService.instance.currentIdentity;
      if (identity == null) {
        throw Exception('Failed to create Session identity');
      }

      _sessionId = identity.sessionId;
      _displayName = displayName;
      _profilePicture = profilePicture;
      _isFirstTime = false;

      // Save identity and user preferences
      await _storage.write(
          key: 'session_identity', value: json.encode(identity.toJson()));
      await _storage.write(key: 'display_name', value: displayName);
      if (profilePicture != null) {
        await _storage.write(key: 'profile_picture', value: profilePicture);
      }
      await _storage.write(key: 'is_first_time', value: 'false');

      // Create user object
      _currentUser = User(
        id: _sessionId!,
        username: displayName,
        profilePicture: profilePicture,
        isOnline: true,
        lastSeen: DateTime.now(),
      );

      _isAuthenticated = true;

      // Connect to Session network
      await SessionService.instance.connect();

      // Initialize AirNotifier service for push notifications
      await AirNotifierService.instance.initialize(sessionId: _sessionId!);
      print('🔐 Auth: AirNotifier service initialized');

      // Register device token with Session ID if available
      try {
        await NativePushService.instance.registerStoredDeviceToken(_sessionId!);
        print('🔐 Auth: Device token registered with Session ID');
      } catch (e) {
        print('🔐 Auth: Error registering device token: $e');
      }

      print('🔐 Auth: Session identity created successfully: $_sessionId');
      return true;
    } catch (e) {
      print('🔐 Auth: Error creating Session identity: $e');
      _error = 'Failed to create account. Please try again.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Import existing Session identity
  Future<bool> importSessionIdentity({
    required String sessionId,
    required String privateKey,
    String? displayName,
    String? profilePicture,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      print('🔐 Auth: Importing Session identity: $sessionId');

      // Validate Session ID format
      if (!_isValidSessionId(sessionId)) {
        throw Exception('Invalid account ID format');
      }

      // Create Session identity object
      final identity = LocalSessionIdentity(
        publicKey: '', // Will be derived from private key
        privateKey: privateKey,
        sessionId: sessionId,
        createdAt: DateTime.now(),
      );

      // Save identity
      await _storage.write(
          key: 'session_identity', value: json.encode(identity.toJson()));

      _sessionId = sessionId;
      _displayName = displayName ?? 'Anonymous User';
      _profilePicture = profilePicture;
      _isFirstTime = false;

      // Save user preferences
      await _storage.write(key: 'display_name', value: _displayName);
      if (profilePicture != null) {
        await _storage.write(key: 'profile_picture', value: profilePicture);
      }
      await _storage.write(key: 'is_first_time', value: 'false');

      // Initialize Session Protocol with imported identity
      await SessionService.instance.initialize();

      // Create user object
      _currentUser = User(
        id: _sessionId!,
        username: _displayName!,
        profilePicture: _profilePicture,
        isOnline: true,
        lastSeen: DateTime.now(),
      );

      _isAuthenticated = true;

      // Connect to Session network
      await SessionService.instance.connect();

      // Initialize AirNotifier service for push notifications
      await AirNotifierService.instance.initialize(sessionId: _sessionId!);
      print('🔐 Auth: AirNotifier service initialized');

      // Register device token with Session ID if available
      try {
        await NativePushService.instance.registerStoredDeviceToken(_sessionId!);
        print('🔐 Auth: Device token registered with Session ID');
      } catch (e) {
        print('🔐 Auth: Error registering device token: $e');
      }

      print('🔐 Auth: Session identity imported successfully: $sessionId');
      return true;
    } catch (e) {
      print('🔐 Auth: Error importing Session identity: $e');
      _error = 'Failed to sign in. Please check your account details.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update user profile
  Future<bool> updateProfile({
    String? displayName,
    String? profilePicture,
  }) async {
    try {
      if (!_isAuthenticated) {
        throw Exception('User not authenticated');
      }

      if (displayName != null) {
        _displayName = displayName;
        await _storage.write(key: 'display_name', value: displayName);
      }

      if (profilePicture != null) {
        _profilePicture = profilePicture;
        await _storage.write(key: 'profile_picture', value: profilePicture);
      }

      // Update current user object
      if (_currentUser != null) {
        _currentUser = _currentUser!.copyWith(
          username: _displayName ?? _currentUser!.username,
          profilePicture: _profilePicture ?? _currentUser!.profilePicture,
        );
      }

      print('🔐 Auth: Profile updated successfully');
      notifyListeners();
      return true;
    } catch (e) {
      print('🔐 Auth: Error updating profile: $e');
      _error = 'Failed to update profile: $e';
      notifyListeners();
      return false;
    }
  }

  // Export Session identity for backup
  Future<Map<String, String>> exportSessionIdentity() async {
    try {
      if (!_isAuthenticated || _sessionId == null) {
        throw Exception('No account to export');
      }

      final identity = SessionService.instance.currentIdentity;
      if (identity == null) {
        throw Exception('Account not found');
      }

      return {
        'sessionId': identity.sessionId,
        'privateKey': identity.privateKey,
        'displayName': _displayName ?? 'Anonymous User',
        'profilePicture': _profilePicture ?? '',
      };
    } catch (e) {
      print('🔐 Auth: Error exporting Session identity: $e');
      _error = 'Failed to export account details.';
      notifyListeners();
      rethrow;
    }
  }

  // Logout
  Future<void> logout() async {
    try {
      print('🔐 Auth: Logging out...');

      // Disconnect from Session network
      await SessionService.instance.disconnect();

      // Clear user data
      _currentUser = null;
      _isAuthenticated = false;
      _sessionId = null;
      _displayName = null;
      _profilePicture = null;
      _error = null;

      // Unlink token from session
      if (_sessionId != null) {
        try {
          await AirNotifierService.instance.unlinkTokenFromSession();
          print('🔐 Auth: Unlinked token from session for logout');
        } catch (e) {
          print('🔐 Auth: Error unlinking token from session: $e');
        }
      }

      // Clear secure storage
      await _storage.delete(key: 'session_identity');
      await _storage.delete(key: 'display_name');
      await _storage.delete(key: 'profile_picture');
      await _storage.delete(key: 'is_first_time');

      print('🔐 Auth: Logout completed');
      notifyListeners();
    } catch (e) {
      print('🔐 Auth: Error during logout: $e');
      _error = 'Logout failed: $e';
      notifyListeners();
    }
  }

  // Delete Session identity (permanent)
  Future<bool> deleteSessionIdentity() async {
    try {
      if (!_isAuthenticated) {
        throw Exception('You must be signed in to delete your account');
      }

      print('🔐 Auth: Deleting Session identity...');

      // Disconnect from Session network
      await SessionService.instance.disconnect();

      // Unlink token from session
      if (_sessionId != null) {
        try {
          await AirNotifierService.instance.unlinkTokenFromSession();
          print('🔐 Auth: Unlinked token from session for account deletion');
        } catch (e) {
          print('🔐 Auth: Error unlinking token from session: $e');
        }
      }

      // Clear all data
      await _storage.deleteAll();

      // Reset state
      _currentUser = null;
      _isAuthenticated = false;
      _sessionId = null;
      _displayName = null;
      _profilePicture = null;
      _error = null;
      _isFirstTime = true;

      print('🔐 Auth: Session identity deleted permanently');
      notifyListeners();
      return true;
    } catch (e) {
      print('🔐 Auth: Error deleting Session identity: $e');
      _error = 'Failed to delete account. Please try again.';
      notifyListeners();
      return false;
    }
  }

  // Validate Session ID format
  bool _isValidSessionId(String sessionId) {
    // Session IDs are typically 66 characters long and contain alphanumeric characters
    return sessionId.length == 66 &&
        RegExp(r'^[A-Za-z0-9]+$').hasMatch(sessionId);
  }

  // Get Session QR code data for sharing
  String? getSessionQRCodeData() {
    if (_sessionId == null) return null;

    // Create QR code data with Session ID and optional display name
    final qrData = {
      'sessionId': _sessionId,
      'displayName': _displayName ?? 'Anonymous User',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    return json.encode(qrData);
  }

  // Parse Session QR code data
  Map<String, dynamic>? parseSessionQRCodeData(String qrData) {
    try {
      final data = json.decode(qrData) as Map<String, dynamic>;

      // Validate required fields
      if (!data.containsKey('sessionId')) {
        throw Exception('Invalid contact code: missing account ID');
      }

      return data;
    } catch (e) {
      print('🔐 Auth: Error parsing QR code data: $e');
      return null;
    }
  }

  // Check if user has contacts
  Future<bool> hasContacts() async {
    try {
      final contacts = SessionService.instance.contacts;
      return contacts.isNotEmpty;
    } catch (e) {
      print('🔐 Auth: Error checking contacts: $e');
      return false;
    }
  }

  // Get user's Session contacts
  Map<String, LocalSessionContact> getContacts() {
    return SessionService.instance.contacts;
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Reset provider state
  void reset() {
    _currentUser = null;
    _isAuthenticated = false;
    _sessionId = null;
    _displayName = null;
    _profilePicture = null;
    _error = null;
    _isFirstTime = true;
    _isLoading = false;
    notifyListeners();
  }

  // Storage getter for backward compatibility
  FlutterSecureStorage get storage => _storage;

  // Remove all password-related legacy methods since Session Protocol doesn't use passwords
  // The following methods are kept for UI compatibility but are deprecated:

  // Login method (for backward compatibility - now uses Session identity)
  Future<bool> login(
      {required String deviceId, required String password}) async {
    try {
      // For Session Protocol, we don't use username/password
      // Instead, we check if a Session identity exists
      final sessionIdentity = await _storage.read(key: 'session_identity');

      if (sessionIdentity != null) {
        // User has existing Session identity - restore it
        final identity = json.decode(sessionIdentity);
        _sessionId = identity['sessionId'];
        _displayName = await _storage.read(key: 'display_name');
        _profilePicture = await _storage.read(key: 'profile_picture');

        // Initialize Session Protocol
        await SessionService.instance.initialize();

        // Create user object
        _currentUser = User(
          id: _sessionId!,
          username: _displayName ?? 'Anonymous User',
          profilePicture: _profilePicture,
          isOnline: true,
          lastSeen: DateTime.now(),
        );

        _isAuthenticated = true;
        await SessionService.instance.connect();

        print('🔐 Auth: Session identity restored via legacy login');
        return true;
      } else {
        // No Session identity exists - user needs to create one
        _error = 'No account found. Please create a new SeChat account.';
        return false;
      }
    } catch (e) {
      print('🔐 Auth: Error in legacy login: $e');
      _error = 'Sign in failed. Please check your account details.';
      return false;
    }
  }

  // Register method (for backward compatibility - now creates Session identity)
  Future<bool> register({
    required String username,
    required String password,
    required String securityQuestion,
    required String securityAnswer,
  }) async {
    try {
      // Create new Session identity with the username as display name
      return await createSessionIdentity(displayName: username);
    } catch (e) {
      print('🔐 Auth: Error in legacy register: $e');
      _error = 'Registration failed: $e';
      return false;
    }
  }

  // Get stored username (for backward compatibility)
  Future<String?> getStoredUsername() async {
    return await _storage.read(key: 'display_name');
  }

  // Reset app method (for backward compatibility)
  Future<void> resetApp() async {
    await logout();
  }

  // Delete account method (for backward compatibility)
  Future<bool> deleteAccount() async {
    return await deleteSessionIdentity();
  }

  // Device ID methods (for backward compatibility)
  Future<bool> userExistsForDevice(String deviceId) async {
    // Check if Session identity exists
    final sessionIdentity = await _storage.read(key: 'session_identity');
    return sessionIdentity != null;
  }

  Future<bool> hasDeviceIdButNoUsername() async {
    final sessionIdentity = await _storage.read(key: 'session_identity');
    final displayName = await _storage.read(key: 'display_name');
    return sessionIdentity != null && displayName == null;
  }

  Future<String?> fetchUsernameFromDeviceId(String deviceId) async {
    return await _storage.read(key: 'display_name');
  }
}
