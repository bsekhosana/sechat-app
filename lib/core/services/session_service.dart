import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:uuid/uuid.dart';
import 'simple_notification_service.dart';

// Session Protocol Models
class LocalSessionIdentity {
  final String publicKey;
  final String privateKey;
  final String sessionId;
  final DateTime createdAt;

  LocalSessionIdentity({
    required this.publicKey,
    required this.privateKey,
    required this.sessionId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'publicKey': publicKey,
        'privateKey': privateKey,
        'sessionId': sessionId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory LocalSessionIdentity.fromJson(Map<String, dynamic> json) =>
      LocalSessionIdentity(
        publicKey: json['publicKey'],
        privateKey: json['privateKey'],
        sessionId: json['sessionId'],
        createdAt: DateTime.parse(json['createdAt']),
      );
}

class LocalSessionContact {
  final String sessionId;
  final String? name;
  final String? profilePicture;
  final bool isBlocked;
  final DateTime lastSeen;
  final bool isOnline;

  LocalSessionContact({
    required this.sessionId,
    this.name,
    this.profilePicture,
    this.isBlocked = false,
    required this.lastSeen,
    this.isOnline = false,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'name': name,
        'profilePicture': profilePicture,
        'isBlocked': isBlocked,
        'lastSeen': lastSeen.toIso8601String(),
        'isOnline': isOnline,
      };

  factory LocalSessionContact.fromJson(Map<String, dynamic> json) =>
      LocalSessionContact(
        sessionId: json['sessionId'],
        name: json['name'],
        profilePicture: json['profilePicture'],
        isBlocked: json['isBlocked'] ?? false,
        lastSeen: DateTime.parse(json['lastSeen']),
        isOnline: json['isOnline'] ?? false,
      );
}

class LocalSessionMessage {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final String messageType; // text, image, file, etc.
  final DateTime timestamp;
  final String status; // sent, delivered, read
  final bool isOutgoing;
  final Map<String, dynamic>? metadata;

  LocalSessionMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.messageType = 'text',
    required this.timestamp,
    this.status = 'sent',
    required this.isOutgoing,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'receiverId': receiverId,
        'content': content,
        'messageType': messageType,
        'timestamp': timestamp.toIso8601String(),
        'status': status,
        'isOutgoing': isOutgoing,
        'metadata': metadata,
      };

  factory LocalSessionMessage.fromJson(Map<String, dynamic> json) =>
      LocalSessionMessage(
        id: json['id'],
        senderId: json['senderId'],
        receiverId: json['receiverId'],
        content: json['content'],
        messageType: json['messageType'] ?? 'text',
        timestamp: DateTime.parse(json['timestamp']),
        status: json['status'] ?? 'sent',
        isOutgoing: json['isOutgoing'],
        metadata: json['metadata'],
      );
}

class SessionService {
  static SessionService? _instance;
  static SessionService get instance => _instance ??= SessionService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const MethodChannel _channel = MethodChannel('session_protocol');

  LocalSessionIdentity? _currentIdentity;
  final Map<String, LocalSessionContact> _contacts = {};
  final Map<String, List<LocalSessionMessage>> _conversations = {};
  bool _isInitialized = false;
  bool _isConnected = false;

  // Callbacks for real-time events
  Function()? onConnected;
  Function()? onDisconnected;
  Function(String)? onError;
  Function(LocalSessionMessage)? onMessageReceived;
  Function(LocalSessionContact)? onContactAdded;
  Function(LocalSessionContact)? onContactUpdated;
  Function(String)? onContactRemoved;
  Function(String)? onTypingReceived;
  Function(String)? onTypingStopped;
  Function(String)? onMessageStatusUpdated;

  SessionService._();

  // Initialize Session Protocol
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('🔐 Session: Initializing Session Protocol...');

      // Load existing identity or create new one
      await _loadOrCreateIdentity();

      // Initialize native Session SDK
      await _initializeNativeSDK();

      // Load contacts and conversations
      await _loadContacts();
      await _loadConversations();

      _isInitialized = true;
      print('🔐 Session: Initialization complete');
    } catch (e) {
      print('🔐 Session: Initialization failed: $e');
      rethrow;
    }
  }

  // Restore session from persistent storage
  Future<void> restoreSession() async {
    try {
      print('🔐 Session: Restoring session from persistent storage...');

      // Check if session data exists
      final hasIdentity = await _storage.containsKey(key: 'session_identity');
      if (!hasIdentity) {
        print('🔐 Session: No existing session found, will create new one');
        return;
      }

      // Load existing identity
      await _loadOrCreateIdentity();

      // Load contacts and conversations
      await _loadContacts();
      await _loadConversations();

      // Initialize native SDK with restored data
      await _initializeNativeSDK();

      _isInitialized = true;
      print('🔐 Session: Session restored successfully');
      print('🔐 Session: Identity: ${_currentIdentity?.sessionId}');
      print('🔐 Session: Contacts: ${_contacts.length}');
      print('🔐 Session: Conversations: ${_conversations.length}');
    } catch (e) {
      print('🔐 Session: Error restoring session: $e');
      // If restoration fails, clear corrupted data and start fresh
      await _clearCorruptedData();
      rethrow;
    }
  }

  // Save current session state to persistent storage
  Future<void> persistSession() async {
    try {
      print('🔐 Session: Persisting session data...');

      if (_currentIdentity != null) {
        await _storage.write(
          key: 'session_identity',
          value: json.encode(_currentIdentity!.toJson()),
        );
        print('🔐 Session: ✅ Identity persisted');
      }

      await _saveContacts();
      await _saveConversations();

      // Save session state
      await _storage.write(
        key: 'session_state',
        value: json.encode({
          'isInitialized': _isInitialized,
          'isConnected': _isConnected,
          'lastSaved': DateTime.now().toIso8601String(),
        }),
      );

      print('🔐 Session: ✅ Session data persisted successfully');
    } catch (e) {
      print('🔐 Session: Error persisting session: $e');
      rethrow;
    }
  }

  // Clear corrupted data and start fresh
  Future<void> _clearCorruptedData() async {
    try {
      print('🔐 Session: Clearing corrupted session data...');
      await _storage.deleteAll();
      _currentIdentity = null;
      _contacts.clear();
      _conversations.clear();
      _isInitialized = false;
      _isConnected = false;
      print('🔐 Session: ✅ Corrupted data cleared');
    } catch (e) {
      print('🔐 Session: Error clearing corrupted data: $e');
    }
  }

  Future<void> _loadOrCreateIdentity() async {
    try {
      final identityJson = await _storage.read(key: 'session_identity');

      if (identityJson != null) {
        _currentIdentity =
            LocalSessionIdentity.fromJson(json.decode(identityJson));
        print(
            '🔐 Session: Loaded existing identity: ${_currentIdentity!.sessionId}');
      } else {
        await _createNewIdentity();
      }
    } catch (e) {
      print('🔐 Session: Error loading identity: $e');
      await _createNewIdentity();
    }
  }

  Future<void> _createNewIdentity() async {
    try {
      print('🔐 Session: Creating new identity...');

      // Generate Ed25519 key pair for Session Protocol
      final keyPair = await _generateEd25519KeyPair();

      final publicKey = keyPair['publicKey'];
      final privateKey = keyPair['privateKey'];

      if (publicKey == null || privateKey == null) {
        throw Exception('Failed to generate key pair');
      }

      _currentIdentity = LocalSessionIdentity(
        publicKey: publicKey,
        privateKey: privateKey,
        sessionId: _generateSessionId(publicKey),
        createdAt: DateTime.now(),
      );

      // Save identity securely
      await _storage.write(
        key: 'session_identity',
        value: json.encode(_currentIdentity!.toJson()),
      );

      print('🔐 Session: New identity created: ${_currentIdentity!.sessionId}');
    } catch (e) {
      print('🔐 Session: Error creating identity: $e');
      rethrow;
    }
  }

  Future<Map<String, String>> _generateEd25519KeyPair() async {
    try {
      final result = await _channel.invokeMethod('generateEd25519KeyPair');
      return Map<String, String>.from(result);
    } catch (e) {
      print('🔐 Session: Error generating key pair: $e');
      // Fallback to Dart implementation
      return _generateEd25519KeyPairFallback();
    }
  }

  Map<String, String> _generateEd25519KeyPairFallback() {
    // Simplified fallback implementation
    // Generate random keys for development/testing
    final random = Random.secure();
    final publicKeyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final privateKeyBytes = List<int>.generate(32, (_) => random.nextInt(256));

    return {
      'publicKey': base64.encode(publicKeyBytes),
      'privateKey': base64.encode(privateKeyBytes),
    };
  }

  String _generateSessionId(String publicKey) {
    // Session Protocol uses a specific format for Session IDs
    final hash = sha256.convert(utf8.encode(publicKey));
    return base64.encode(hash.bytes).replaceAll(RegExp(r'[+/=]'), '');
  }

  Future<void> _initializeNativeSDK() async {
    try {
      if (_currentIdentity == null) {
        throw Exception('Identity not available');
      }

      final sessionIdentity = {
        'publicKey': _currentIdentity!.publicKey,
        'privateKey': _currentIdentity!.privateKey,
        'sessionId': _currentIdentity!.sessionId,
        'createdAt': _currentIdentity!.createdAt.toIso8601String(),
      };

      await _channel.invokeMethod('initializeSession', sessionIdentity);

      print('🔐 Session: Native SDK initialized successfully');
    } catch (e) {
      print('🔐 Session: Error initializing native SDK: $e');
      rethrow;
    }
  }

  Future<void> _loadContacts() async {
    try {
      final contactsJson = await _storage.read(key: 'session_contacts');
      if (contactsJson != null) {
        final contactsList = json.decode(contactsJson) as List;
        for (final contactJson in contactsList) {
          final contact = LocalSessionContact.fromJson(contactJson);
          _contacts[contact.sessionId] = contact;
        }
      }
      print('🔐 Session: Loaded ${_contacts.length} contacts');
    } catch (e) {
      print('🔐 Session: Error loading contacts: $e');
    }
  }

  Future<void> _loadConversations() async {
    try {
      final conversationsJson =
          await _storage.read(key: 'session_conversations');
      if (conversationsJson != null) {
        final conversationsMap =
            json.decode(conversationsJson) as Map<String, dynamic>;
        for (final entry in conversationsMap.entries) {
          final messagesList = entry.value as List;
          _conversations[entry.key] = messagesList
              .map((msg) => LocalSessionMessage.fromJson(msg))
              .toList();
        }
      }
      print('🔐 Session: Loaded ${_conversations.length} conversations');
    } catch (e) {
      print('🔐 Session: Error loading conversations: $e');
    }
  }

  // Connect to Session network
  Future<void> connect() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      print('🔐 Session: Connecting to Session network...');
      await _channel.invokeMethod('connect');
      _isConnected = true;
      print('🔐 Session: Connected to Session network');
    } catch (e) {
      print('🔐 Session: Connection failed: $e');
      rethrow;
    }
  }

  // Disconnect from Session network
  Future<void> disconnect() async {
    try {
      print('🔐 Session: Disconnecting from Session network...');
      await _channel.invokeMethod('disconnect');
      _isConnected = false;
      print('🔐 Session: Disconnected from Session network');
    } catch (e) {
      print('🔐 Session: Disconnect error: $e');
    }
  }

  // Clear all conversations
  Future<void> clearAllConversations() async {
    try {
      _conversations.clear();
      await _storage.delete(key: 'session_conversations');
      print('🔐 Session: All conversations cleared');
    } catch (e) {
      print('🔐 Session: Error clearing conversations: $e');
      rethrow;
    }
  }

  // Clear all data (for account deletion)
  Future<void> clearAllData() async {
    try {
      print('🔐 Session: Clearing all session data (account deletion)...');

      // Disconnect from network first
      if (_isConnected) {
        await disconnect();
      }

      // Clear notification service session data and unlink token
      try {
        await SimpleNotificationService.instance.clearSessionData();
        print('🔐 Session: ✅ Notification service session data cleared');
      } catch (e) {
        print('🔐 Session: Error clearing notification service data: $e');
      }

      // Clear in-memory data
      _currentIdentity = null;
      _contacts.clear();
      _conversations.clear();
      _isInitialized = false;
      _isConnected = false;

      // Clear all stored data
      await _storage.deleteAll();

      print('🔐 Session: ✅ All session data cleared');
    } catch (e) {
      print('🔐 Session: Error clearing all data: $e');
      rethrow;
    }
  }

  // Handle app lifecycle events
  Future<void> onAppPaused() async {
    try {
      print('🔐 Session: App paused - persisting session data...');
      await persistSession();
    } catch (e) {
      print('🔐 Session: Error persisting session on app pause: $e');
    }
  }

  Future<void> onAppResumed() async {
    try {
      print('🔐 Session: App resumed - checking session state...');
      // Session data is already loaded, just verify state
      if (_isInitialized && _currentIdentity != null) {
        print('🔐 Session: Session state verified on resume');
      }
    } catch (e) {
      print('🔐 Session: Error checking session state on resume: $e');
    }
  }

  Future<void> onAppDetached() async {
    try {
      print('🔐 Session: App detached - final session persistence...');
      await persistSession();
    } catch (e) {
      print('🔐 Session: Error persisting session on app detach: $e');
    }
  }

  // Check if session data exists
  Future<bool> hasExistingSession() async {
    try {
      return await _storage.containsKey(key: 'session_identity');
    } catch (e) {
      print('🔐 Session: Error checking for existing session: $e');
      return false;
    }
  }

  // Get session info for debugging
  Map<String, dynamic> getSessionInfo() {
    return {
      'isInitialized': _isInitialized,
      'isConnected': _isConnected,
      'hasIdentity': _currentIdentity != null,
      'identitySessionId': _currentIdentity?.sessionId,
      'contactsCount': _contacts.length,
      'conversationsCount': _conversations.length,
    };
  }

  // Send message
  Future<String> sendMessage({
    required String receiverId,
    required String content,
    String messageType = 'text',
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isConnected) {
      throw Exception('Not connected to Session network');
    }

    try {
      final messageId = const Uuid().v4();
      // Send via native SDK
      final sessionMessage = {
        'id': messageId,
        'senderId': _currentIdentity!.sessionId,
        'receiverId': receiverId,
        'content': content,
        'messageType': messageType,
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'sent',
        'isOutgoing': true,
      };

      // Add to local conversation
      _addMessageToConversation(
          receiverId,
          LocalSessionMessage(
            id: messageId,
            senderId: _currentIdentity!.sessionId,
            receiverId: receiverId,
            content: content,
            messageType: messageType,
            timestamp: DateTime.now(),
            status: 'sent',
            isOutgoing: true,
          ));

      await _channel.invokeMethod('sendMessage', sessionMessage);

      print('🔐 Session: Message sent: $messageId');
      return messageId;
    } catch (e) {
      print('🔐 Session: Error sending message: $e');
      rethrow;
    }
  }

  // Add contact
  Future<void> addContact({
    required String sessionId,
    String? name,
    String? profilePicture,
  }) async {
    try {
      // Add via native SDK
      final sessionContact = {
        'sessionId': sessionId,
        'name': name,
        'profilePicture': profilePicture,
        'lastSeen': DateTime.now().toIso8601String(),
        'isOnline': false,
        'isBlocked': false,
      };

      await _channel.invokeMethod('addContact', sessionContact);

      // Add to local contacts
      _contacts[sessionId] = LocalSessionContact(
        sessionId: sessionId,
        name: name,
        profilePicture: profilePicture,
        lastSeen: DateTime.now(),
      );
      await _saveContacts();

      onContactAdded?.call(_contacts[sessionId]!);
      print('🔐 Session: Contact added: $sessionId');
    } catch (e) {
      print('🔐 Session: Error adding contact: $e');
      rethrow;
    }
  }

  // Send typing indicator
  Future<void> sendTypingIndicator(String receiverId, bool isTyping) async {
    if (!_isConnected) {
      print(
          '🔐 Session: Error sending typing indicator: Not connected to Session network');
      return;
    }

    try {
      // Send typing indicator via native SDK
      await _channel.invokeMethod('sendTypingIndicator', {
        'receiverId': receiverId,
        'isTyping': isTyping,
      });
    } catch (e) {
      print('🔐 Session: Error sending typing indicator: $e');
      // Don't rethrow - typing indicators are not critical
    }
  }

  // Remove contact
  Future<void> removeContact(String sessionId) async {
    try {
      _contacts.remove(sessionId);
      await _saveContacts();

      // Remove via native SDK
      await _channel.invokeMethod('removeContact', sessionId);

      onContactRemoved?.call(sessionId);
      print('🔐 Session: Contact removed: $sessionId');
    } catch (e) {
      print('🔐 Session: Error removing contact: $e');
      rethrow;
    }
  }

  // Update message status
  Future<void> updateMessageStatus(String messageId, String status) async {
    try {
      // Find and update message in conversations
      for (final conversation in _conversations.values) {
        final messageIndex =
            conversation.indexWhere((msg) => msg.id == messageId);
        if (messageIndex != -1) {
          final updatedMessage = LocalSessionMessage(
            id: conversation[messageIndex].id,
            senderId: conversation[messageIndex].senderId,
            receiverId: conversation[messageIndex].receiverId,
            content: conversation[messageIndex].content,
            messageType: conversation[messageIndex].messageType,
            timestamp: conversation[messageIndex].timestamp,
            status: status,
            isOutgoing: conversation[messageIndex].isOutgoing,
            metadata: conversation[messageIndex].metadata,
          );

          conversation[messageIndex] = updatedMessage;
          await _saveConversations();

          onMessageStatusUpdated?.call(messageId);
          break;
        }
      }
    } catch (e) {
      print('🔐 Session: Error updating message status: $e');
    }
  }

  // Helper methods
  void _addMessageToConversation(
      String contactId, LocalSessionMessage message) {
    if (!_conversations.containsKey(contactId)) {
      _conversations[contactId] = [];
    }
    _conversations[contactId]!.add(message);
    _saveConversations();
  }

  Future<void> _saveContacts() async {
    try {
      final contactsList = _contacts.values.map((c) => c.toJson()).toList();
      await _storage.write(
        key: 'session_contacts',
        value: json.encode(contactsList),
      );
    } catch (e) {
      print('🔐 Session: Error saving contacts: $e');
    }
  }

  Future<void> _saveConversations() async {
    try {
      final conversationsMap = <String, List<Map<String, dynamic>>>{};
      for (final entry in _conversations.entries) {
        conversationsMap[entry.key] =
            entry.value.map((m) => m.toJson()).toList();
      }
      await _storage.write(
        key: 'session_conversations',
        value: json.encode(conversationsMap),
      );
    } catch (e) {
      print('🔐 Session: Error saving conversations: $e');
    }
  }

  // Event handlers
  void _handleMessageReceived(dynamic arguments) {
    try {
      final message =
          LocalSessionMessage.fromJson(Map<String, dynamic>.from(arguments));
      _addMessageToConversation(message.senderId, message);
      onMessageReceived?.call(message);
    } catch (e) {
      print('🔐 Session: Error handling received message: $e');
    }
  }

  void _handleContactAdded(dynamic arguments) {
    try {
      final contact =
          LocalSessionContact.fromJson(Map<String, dynamic>.from(arguments));
      _contacts[contact.sessionId] = contact;
      _saveContacts();
      onContactAdded?.call(contact);
    } catch (e) {
      print('🔐 Session: Error handling contact added: $e');
    }
  }

  void _handleContactUpdated(dynamic arguments) {
    try {
      final contact =
          LocalSessionContact.fromJson(Map<String, dynamic>.from(arguments));
      _contacts[contact.sessionId] = contact;
      _saveContacts();
      onContactUpdated?.call(contact);
    } catch (e) {
      print('🔐 Session: Error handling contact updated: $e');
    }
  }

  void _handleContactRemoved(dynamic arguments) {
    try {
      final sessionId = arguments as String;
      _contacts.remove(sessionId);
      _saveContacts();
      onContactRemoved?.call(sessionId);
    } catch (e) {
      print('🔐 Session: Error handling contact removed: $e');
    }
  }

  void _handleTypingReceived(dynamic arguments) {
    try {
      final sessionId = arguments as String;
      onTypingReceived?.call(sessionId);
    } catch (e) {
      print('🔐 Session: Error handling typing received: $e');
    }
  }

  void _handleTypingStopped(dynamic arguments) {
    try {
      final sessionId = arguments as String;
      onTypingStopped?.call(sessionId);
    } catch (e) {
      print('🔐 Session: Error handling typing stopped: $e');
    }
  }

  void _handleMessageStatusUpdated(dynamic arguments) {
    try {
      final messageId = arguments as String;
      onMessageStatusUpdated?.call(messageId);
    } catch (e) {
      print('🔐 Session: Error handling message status updated: $e');
    }
  }

  void _handleConnected() {
    _isConnected = true;
    onConnected?.call();
  }

  void _handleDisconnected() {
    _isConnected = false;
    onDisconnected?.call();
  }

  void _handleError(dynamic arguments) {
    final error = arguments as String;
    onError?.call(error);
  }

  // Getters
  LocalSessionIdentity? get currentIdentity => _currentIdentity;
  Map<String, LocalSessionContact> get contacts => Map.unmodifiable(_contacts);
  Map<String, List<LocalSessionMessage>> get conversations =>
      Map.unmodifiable(_conversations);
  bool get isInitialized => _isInitialized;
  bool get isConnected => _isConnected;

  // Get messages for a conversation
  List<LocalSessionMessage> getMessagesForContact(String contactId) {
    return _conversations[contactId] ?? [];
  }

  // Get contact by session ID
  LocalSessionContact? getContact(String sessionId) {
    return _contacts[sessionId];
  }

  // Get current user's session ID
  String? get currentSessionId => _currentIdentity?.sessionId;
}
