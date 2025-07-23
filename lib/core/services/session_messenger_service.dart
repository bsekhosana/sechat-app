import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

// Session Messenger Models
class SessionInvitation {
  final String id;
  final String senderId;
  final String senderName;
  final String recipientId;
  final String message;
  final String status; // pending, accepted, declined, expired
  final DateTime createdAt;
  final DateTime? expiresAt;
  final Map<String, dynamic>? metadata;

  SessionInvitation({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.recipientId,
    required this.message,
    required this.status,
    required this.createdAt,
    this.expiresAt,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'recipientId': recipientId,
        'message': message,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'metadata': metadata,
      };

  factory SessionInvitation.fromJson(Map<String, dynamic> json) =>
      SessionInvitation(
        id: json['id'],
        senderId: json['senderId'],
        senderName: json['senderName'],
        recipientId: json['recipientId'],
        message: json['message'],
        status: json['status'],
        createdAt: DateTime.parse(json['createdAt']),
        expiresAt: json['expiresAt'] != null
            ? DateTime.parse(json['expiresAt'])
            : null,
        metadata: json['metadata'],
      );
}

class SessionMessage {
  final String id;
  final String senderId;
  final String recipientId;
  final String content;
  final String messageType; // text, image, file, system
  final DateTime timestamp;
  final String status; // sent, delivered, read
  final bool isOutgoing;
  final Map<String, dynamic>? metadata;
  final String? replyToId;
  final List<String>? mentions;

  SessionMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.content,
    this.messageType = 'text',
    required this.timestamp,
    this.status = 'sent',
    required this.isOutgoing,
    this.metadata,
    this.replyToId,
    this.mentions,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'recipientId': recipientId,
        'content': content,
        'messageType': messageType,
        'timestamp': timestamp.toIso8601String(),
        'status': status,
        'isOutgoing': isOutgoing,
        'metadata': metadata,
        'replyToId': replyToId,
        'mentions': mentions,
      };

  factory SessionMessage.fromJson(Map<String, dynamic> json) => SessionMessage(
        id: json['id'],
        senderId: json['senderId'],
        recipientId: json['recipientId'],
        content: json['content'],
        messageType: json['messageType'] ?? 'text',
        timestamp: DateTime.parse(json['timestamp']),
        status: json['status'] ?? 'sent',
        isOutgoing: json['isOutgoing'] ?? false,
        metadata: json['metadata'],
        replyToId: json['replyToId'],
        mentions: json['mentions'] != null
            ? List<String>.from(json['mentions'])
            : null,
      );
}

class SessionContact {
  final String sessionId;
  final String? name;
  final String? profilePicture;
  final bool isBlocked;
  final DateTime lastSeen;
  final bool isOnline;
  final bool isTyping;
  final DateTime? lastMessageAt;
  final String? lastMessageContent;

  SessionContact({
    required this.sessionId,
    this.name,
    this.profilePicture,
    this.isBlocked = false,
    required this.lastSeen,
    this.isOnline = false,
    this.isTyping = false,
    this.lastMessageAt,
    this.lastMessageContent,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'name': name,
        'profilePicture': profilePicture,
        'isBlocked': isBlocked,
        'lastSeen': lastSeen.toIso8601String(),
        'isOnline': isOnline,
        'isTyping': isTyping,
        'lastMessageAt': lastMessageAt?.toIso8601String(),
        'lastMessageContent': lastMessageContent,
      };

  factory SessionContact.fromJson(Map<String, dynamic> json) => SessionContact(
        sessionId: json['sessionId'],
        name: json['name'],
        profilePicture: json['profilePicture'],
        isBlocked: json['isBlocked'] ?? false,
        lastSeen: DateTime.parse(json['lastSeen']),
        isOnline: json['isOnline'] ?? false,
        isTyping: json['isTyping'] ?? false,
        lastMessageAt: json['lastMessageAt'] != null
            ? DateTime.parse(json['lastMessageAt'])
            : null,
        lastMessageContent: json['lastMessageContent'],
      );
}

class SessionMessengerService {
  static final SessionMessengerService _instance =
      SessionMessengerService._internal();
  factory SessionMessengerService() => _instance;
  SessionMessengerService._internal();

  static SessionMessengerService get instance => _instance;

  // Core properties
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Uuid _uuid = Uuid();
  final Random _random = Random.secure();

  // Identity management
  String? _currentSessionId;
  String? _currentName;
  String? _currentProfilePicture;

  // Real-time communication
  WebSocketChannel? _webSocketChannel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  bool _isConnecting = false;

  // Data storage
  final Map<String, SessionContact> _contacts = {};
  final Map<String, List<SessionMessage>> _conversations = {};
  final Map<String, SessionInvitation> _invitations = {};

  // Event callbacks
  Function(SessionMessage)? onMessageReceived;
  Function(SessionInvitation)? onInvitationReceived;
  Function(SessionInvitation)? onInvitationResponse;
  Function(String)? onContactOnline;
  Function(String)? onContactOffline;
  Function(String)? onContactTyping;
  Function(String)? onContactTypingStopped;
  Function(String)? onMessageStatusUpdated;
  Function()? onConnected;
  Function()? onDisconnected;
  Function(String)? onError;

  // Configuration
  static const String _wsUrl = 'wss://askless.strapblaque.com/ws';
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  static const Duration _reconnectDelay = Duration(seconds: 5);
  static const Duration _invitationExpiry = Duration(hours: 24);

  // Initialize the service
  Future<void> initialize({
    required String sessionId,
    String? name,
    String? profilePicture,
  }) async {
    try {
      _currentSessionId = sessionId;
      _currentName = name;
      _currentProfilePicture = profilePicture;

      // Load existing data
      await _loadContacts();
      await _loadConversations();
      await _loadInvitations();

      print('🔐 SessionMessenger: Initialized for session: $sessionId');
    } catch (e) {
      print('🔐 SessionMessenger: Error initializing: $e');
      rethrow;
    }
  }

  // Connect to real-time service
  Future<void> connect() async {
    if (_isConnected || _isConnecting) return;

    try {
      _isConnecting = true;
      print('🔐 SessionMessenger: Connecting to real-time service...');

      _webSocketChannel = WebSocketChannel.connect(Uri.parse(_wsUrl));

      // Send authentication
      await _sendAuthMessage();

      // Set up message handling
      _webSocketChannel!.stream.listen(
        _handleWebSocketMessage,
        onError: _handleWebSocketError,
        onDone: _handleWebSocketDone,
      );

      _isConnected = true;
      _isConnecting = false;

      // Start heartbeat
      _startHeartbeat();

      onConnected?.call();
      print('🔐 SessionMessenger: Connected successfully');
    } catch (e) {
      _isConnecting = false;
      print('🔐 SessionMessenger: Connection failed: $e');
      onError?.call('Connection failed: $e');
      _scheduleReconnect();
    }
  }

  // Disconnect from real-time service
  Future<void> disconnect() async {
    try {
      _isConnected = false;
      _heartbeatTimer?.cancel();
      _reconnectTimer?.cancel();
      await _webSocketChannel?.sink.close();
      _webSocketChannel = null;
      onDisconnected?.call();
      print('🔐 SessionMessenger: Disconnected');
    } catch (e) {
      print('🔐 SessionMessenger: Error disconnecting: $e');
    }
  }

  // Send invitation
  Future<SessionInvitation> sendInvitation({
    required String recipientId,
    required String message,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final invitation = SessionInvitation(
        id: _uuid.v4(),
        senderId: _currentSessionId!,
        senderName: _currentName ?? 'Anonymous',
        recipientId: recipientId,
        message: message,
        status: 'pending',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(_invitationExpiry),
        metadata: metadata,
      );

      // Send via WebSocket
      await _sendWebSocketMessage({
        'type': 'invitation_send',
        'data': invitation.toJson(),
      });

      // Store locally
      _invitations[invitation.id] = invitation;
      await _saveInvitations();

      print('🔐 SessionMessenger: Invitation sent: ${invitation.id}');
      return invitation;
    } catch (e) {
      print('🔐 SessionMessenger: Error sending invitation: $e');
      rethrow;
    }
  }

  // Accept invitation
  Future<void> acceptInvitation(String invitationId) async {
    try {
      final invitation = _invitations[invitationId];
      if (invitation == null) {
        throw Exception('Invitation not found');
      }

      // Update invitation status
      final updatedInvitation = SessionInvitation(
        id: invitation.id,
        senderId: invitation.senderId,
        senderName: invitation.senderName,
        recipientId: invitation.recipientId,
        message: invitation.message,
        status: 'accepted',
        createdAt: invitation.createdAt,
        expiresAt: invitation.expiresAt,
        metadata: invitation.metadata,
      );

      // Send acceptance via WebSocket
      await _sendWebSocketMessage({
        'type': 'invitation_accept',
        'data': {'invitationId': invitationId},
      });

      // Add contact
      await _addContact(
        sessionId: invitation.senderId,
        name: invitation.senderName,
      );

      // Update local storage
      _invitations[invitationId] = updatedInvitation;
      await _saveInvitations();

      onInvitationResponse?.call(updatedInvitation);
      print('🔐 SessionMessenger: Invitation accepted: $invitationId');
    } catch (e) {
      print('🔐 SessionMessenger: Error accepting invitation: $e');
      rethrow;
    }
  }

  // Decline invitation
  Future<void> declineInvitation(String invitationId) async {
    try {
      final invitation = _invitations[invitationId];
      if (invitation == null) {
        throw Exception('Invitation not found');
      }

      // Update invitation status
      final updatedInvitation = SessionInvitation(
        id: invitation.id,
        senderId: invitation.senderId,
        senderName: invitation.senderName,
        recipientId: invitation.recipientId,
        message: invitation.message,
        status: 'declined',
        createdAt: invitation.createdAt,
        expiresAt: invitation.expiresAt,
        metadata: invitation.metadata,
      );

      // Send decline via WebSocket
      await _sendWebSocketMessage({
        'type': 'invitation_decline',
        'data': {'invitationId': invitationId},
      });

      // Update local storage
      _invitations[invitationId] = updatedInvitation;
      await _saveInvitations();

      onInvitationResponse?.call(updatedInvitation);
      print('🔐 SessionMessenger: Invitation declined: $invitationId');
    } catch (e) {
      print('🔐 SessionMessenger: Error declining invitation: $e');
      rethrow;
    }
  }

  // Send message
  Future<String> sendMessage({
    required String recipientId,
    required String content,
    String messageType = 'text',
    Map<String, dynamic>? metadata,
    String? replyToId,
    List<String>? mentions,
  }) async {
    try {
      final messageId = _uuid.v4();
      final message = SessionMessage(
        id: messageId,
        senderId: _currentSessionId!,
        recipientId: recipientId,
        content: content,
        messageType: messageType,
        timestamp: DateTime.now(),
        status: 'sent',
        isOutgoing: true,
        metadata: metadata,
        replyToId: replyToId,
        mentions: mentions,
      );

      // Send via WebSocket
      await _sendWebSocketMessage({
        'type': 'message_send',
        'data': message.toJson(),
      });

      // Add to local conversation
      _addMessageToConversation(recipientId, message);
      await _saveConversations();

      // Update contact's last message
      _updateContactLastMessage(recipientId, message);

      print('🔐 SessionMessenger: Message sent: $messageId');
      return messageId;
    } catch (e) {
      print('🔐 SessionMessenger: Error sending message: $e');
      rethrow;
    }
  }

  // Send typing indicator
  Future<void> sendTypingIndicator(String recipientId, bool isTyping) async {
    try {
      await _sendWebSocketMessage({
        'type': 'typing_indicator',
        'data': {
          'recipientId': recipientId,
          'isTyping': isTyping,
        },
      });
    } catch (e) {
      print('🔐 SessionMessenger: Error sending typing indicator: $e');
    }
  }

  // Mark message as read
  Future<void> markMessageAsRead(String messageId) async {
    try {
      await _sendWebSocketMessage({
        'type': 'message_read',
        'data': {'messageId': messageId},
      });

      // Update local message status
      _updateMessageStatus(messageId, 'read');
    } catch (e) {
      print('🔐 SessionMessenger: Error marking message as read: $e');
    }
  }

  // Private methods
  Future<void> _sendAuthMessage() async {
    await _sendWebSocketMessage({
      'type': 'auth',
      'data': {
        'sessionId': _currentSessionId,
        'name': _currentName,
        'profilePicture': _currentProfilePicture,
      },
    });
  }

  Future<void> _sendWebSocketMessage(Map<String, dynamic> message) async {
    if (!_isConnected) {
      throw Exception('Not connected to real-time service');
    }

    _webSocketChannel?.sink.add(json.encode(message));
  }

  void _handleWebSocketMessage(dynamic data) {
    try {
      final message = json.decode(data);
      final type = message['type'];
      final messageData = message['data'];

      switch (type) {
        case 'message_received':
          _handleMessageReceived(messageData);
          break;
        case 'invitation_received':
          _handleInvitationReceived(messageData);
          break;
        case 'invitation_response':
          _handleInvitationResponse(messageData);
          break;
        case 'contact_online':
          _handleContactOnline(messageData);
          break;
        case 'contact_offline':
          _handleContactOffline(messageData);
          break;
        case 'typing_indicator':
          _handleTypingIndicator(messageData);
          break;
        case 'message_status':
          _handleMessageStatus(messageData);
          break;
        case 'pong':
          // Heartbeat response
          break;
        default:
          print('🔐 SessionMessenger: Unknown message type: $type');
      }
    } catch (e) {
      print('🔐 SessionMessenger: Error handling WebSocket message: $e');
    }
  }

  void _handleMessageReceived(Map<String, dynamic> data) {
    try {
      final message = SessionMessage.fromJson(data);
      _addMessageToConversation(message.senderId, message);
      _updateContactLastMessage(message.senderId, message);
      onMessageReceived?.call(message);
    } catch (e) {
      print('🔐 SessionMessenger: Error handling received message: $e');
    }
  }

  void _handleInvitationReceived(Map<String, dynamic> data) {
    try {
      final invitation = SessionInvitation.fromJson(data);
      _invitations[invitation.id] = invitation;
      _saveInvitations();
      onInvitationReceived?.call(invitation);
    } catch (e) {
      print('🔐 SessionMessenger: Error handling received invitation: $e');
    }
  }

  void _handleInvitationResponse(Map<String, dynamic> data) {
    try {
      final invitation = SessionInvitation.fromJson(data);
      _invitations[invitation.id] = invitation;
      _saveInvitations();
      onInvitationResponse?.call(invitation);
    } catch (e) {
      print('🔐 SessionMessenger: Error handling invitation response: $e');
    }
  }

  void _handleContactOnline(Map<String, dynamic> data) {
    final sessionId = data['sessionId'];
    final contact = _contacts[sessionId];
    if (contact != null) {
      _contacts[sessionId] = SessionContact(
        sessionId: contact.sessionId,
        name: contact.name,
        profilePicture: contact.profilePicture,
        isBlocked: contact.isBlocked,
        lastSeen: contact.lastSeen,
        isOnline: true,
        isTyping: contact.isTyping,
        lastMessageAt: contact.lastMessageAt,
        lastMessageContent: contact.lastMessageContent,
      );
      onContactOnline?.call(sessionId);
    }
  }

  void _handleContactOffline(Map<String, dynamic> data) {
    final sessionId = data['sessionId'];
    final contact = _contacts[sessionId];
    if (contact != null) {
      _contacts[sessionId] = SessionContact(
        sessionId: contact.sessionId,
        name: contact.name,
        profilePicture: contact.profilePicture,
        isBlocked: contact.isBlocked,
        lastSeen: DateTime.now(),
        isOnline: false,
        isTyping: false,
        lastMessageAt: contact.lastMessageAt,
        lastMessageContent: contact.lastMessageContent,
      );
      onContactOffline?.call(sessionId);
    }
  }

  void _handleTypingIndicator(Map<String, dynamic> data) {
    final sessionId = data['sessionId'];
    final isTyping = data['isTyping'];
    final contact = _contacts[sessionId];

    if (contact != null) {
      _contacts[sessionId] = SessionContact(
        sessionId: contact.sessionId,
        name: contact.name,
        profilePicture: contact.profilePicture,
        isBlocked: contact.isBlocked,
        lastSeen: contact.lastSeen,
        isOnline: contact.isOnline,
        isTyping: isTyping,
        lastMessageAt: contact.lastMessageAt,
        lastMessageContent: contact.lastMessageContent,
      );

      if (isTyping) {
        onContactTyping?.call(sessionId);
      } else {
        onContactTypingStopped?.call(sessionId);
      }
    }
  }

  void _handleMessageStatus(Map<String, dynamic> data) {
    final messageId = data['messageId'];
    final status = data['status'];
    _updateMessageStatus(messageId, status);
    onMessageStatusUpdated?.call(messageId);
  }

  void _handleWebSocketError(error) {
    print('🔐 SessionMessenger: WebSocket error: $error');
    _isConnected = false;
    onError?.call('WebSocket error: $error');
    _scheduleReconnect();
  }

  void _handleWebSocketDone() {
    print('🔐 SessionMessenger: WebSocket connection closed');
    _isConnected = false;
    onDisconnected?.call();
    _scheduleReconnect();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      if (_isConnected) {
        _sendWebSocketMessage({'type': 'ping'});
      }
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (!_isConnected && !_isConnecting) {
        connect();
      }
    });
  }

  Future<void> _addContact({
    required String sessionId,
    String? name,
    String? profilePicture,
  }) async {
    _contacts[sessionId] = SessionContact(
      sessionId: sessionId,
      name: name,
      profilePicture: profilePicture,
      lastSeen: DateTime.now(),
    );
    await _saveContacts();
  }

  void _addMessageToConversation(String contactId, SessionMessage message) {
    if (!_conversations.containsKey(contactId)) {
      _conversations[contactId] = [];
    }
    _conversations[contactId]!.add(message);
  }

  void _updateContactLastMessage(String contactId, SessionMessage message) {
    final contact = _contacts[contactId];
    if (contact != null) {
      _contacts[contactId] = SessionContact(
        sessionId: contact.sessionId,
        name: contact.name,
        profilePicture: contact.profilePicture,
        isBlocked: contact.isBlocked,
        lastSeen: contact.lastSeen,
        isOnline: contact.isOnline,
        isTyping: contact.isTyping,
        lastMessageAt: message.timestamp,
        lastMessageContent: message.content,
      );
    }
  }

  void _updateMessageStatus(String messageId, String status) {
    for (final conversation in _conversations.values) {
      final messageIndex =
          conversation.indexWhere((msg) => msg.id == messageId);
      if (messageIndex != -1) {
        final message = conversation[messageIndex];
        conversation[messageIndex] = SessionMessage(
          id: message.id,
          senderId: message.senderId,
          recipientId: message.recipientId,
          content: message.content,
          messageType: message.messageType,
          timestamp: message.timestamp,
          status: status,
          isOutgoing: message.isOutgoing,
          metadata: message.metadata,
          replyToId: message.replyToId,
          mentions: message.mentions,
        );
        break;
      }
    }
  }

  // Data persistence
  Future<void> _loadContacts() async {
    try {
      final contactsJson =
          await _storage.read(key: 'session_messenger_contacts');
      if (contactsJson != null) {
        final contactsList = json.decode(contactsJson) as List;
        for (final contactJson in contactsList) {
          final contact = SessionContact.fromJson(contactJson);
          _contacts[contact.sessionId] = contact;
        }
      }
    } catch (e) {
      print('🔐 SessionMessenger: Error loading contacts: $e');
    }
  }

  Future<void> _saveContacts() async {
    try {
      final contactsList = _contacts.values.map((c) => c.toJson()).toList();
      await _storage.write(
        key: 'session_messenger_contacts',
        value: json.encode(contactsList),
      );
    } catch (e) {
      print('🔐 SessionMessenger: Error saving contacts: $e');
    }
  }

  Future<void> _loadConversations() async {
    try {
      final conversationsJson =
          await _storage.read(key: 'session_messenger_conversations');
      if (conversationsJson != null) {
        final conversationsMap =
            json.decode(conversationsJson) as Map<String, dynamic>;
        for (final entry in conversationsMap.entries) {
          final messagesList = entry.value as List;
          _conversations[entry.key] =
              messagesList.map((msg) => SessionMessage.fromJson(msg)).toList();
        }
      }
    } catch (e) {
      print('🔐 SessionMessenger: Error loading conversations: $e');
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
        key: 'session_messenger_conversations',
        value: json.encode(conversationsMap),
      );
    } catch (e) {
      print('🔐 SessionMessenger: Error saving conversations: $e');
    }
  }

  Future<void> _loadInvitations() async {
    try {
      final invitationsJson =
          await _storage.read(key: 'session_messenger_invitations');
      if (invitationsJson != null) {
        final invitationsMap =
            json.decode(invitationsJson) as Map<String, dynamic>;
        for (final entry in invitationsMap.entries) {
          _invitations[entry.key] = SessionInvitation.fromJson(entry.value);
        }
      }
    } catch (e) {
      print('🔐 SessionMessenger: Error loading invitations: $e');
    }
  }

  Future<void> _saveInvitations() async {
    try {
      final invitationsMap = <String, Map<String, dynamic>>{};
      for (final entry in _invitations.entries) {
        invitationsMap[entry.key] = entry.value.toJson();
      }
      await _storage.write(
        key: 'session_messenger_invitations',
        value: json.encode(invitationsMap),
      );
    } catch (e) {
      print('🔐 SessionMessenger: Error saving invitations: $e');
    }
  }

  // Getters
  String? get currentSessionId => _currentSessionId;
  String? get currentName => _currentName;
  bool get isConnected => _isConnected;
  Map<String, SessionContact> get contacts => Map.unmodifiable(_contacts);
  Map<String, List<SessionMessage>> get conversations =>
      Map.unmodifiable(_conversations);
  Map<String, SessionInvitation> get invitations =>
      Map.unmodifiable(_invitations);

  // Get messages for a conversation
  List<SessionMessage> getMessagesForContact(String contactId) {
    return _conversations[contactId] ?? [];
  }

  // Get contact by session ID
  SessionContact? getContact(String sessionId) {
    return _contacts[sessionId];
  }

  // Get pending invitations
  List<SessionInvitation> getPendingInvitations() {
    return _invitations.values
        .where((inv) =>
            inv.status == 'pending' && inv.recipientId == _currentSessionId)
        .toList();
  }

  // Get sent invitations
  List<SessionInvitation> getSentInvitations() {
    return _invitations.values
        .where((inv) => inv.senderId == _currentSessionId)
        .toList();
  }

  // Dispose
  void dispose() {
    disconnect();
  }
}
