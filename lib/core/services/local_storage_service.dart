import 'dart:io';
import 'dart:typed_data';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import '../../shared/models/chat.dart';
import '../../shared/models/message.dart';
import '../../shared/models/user.dart';

class LocalStorageService extends ChangeNotifier {
  static LocalStorageService? _instance;
  static LocalStorageService get instance =>
      _instance ??= LocalStorageService._();

  late Box<dynamic> _chatsBox;
  late Box<dynamic> _messagesBox;
  late Box<dynamic> _usersBox;
  late Box<dynamic> _pendingMessagesBox;
  late Box<dynamic> _deletedMessagesBox;
  late Box<dynamic> _storageStatsBox;
  late Box<dynamic> _invitationsBox;

  final Uuid _uuid = const Uuid();
  Directory? _appDocumentsDir;
  Directory? _imagesDir;
  Directory? _tempDir;

  LocalStorageService._();

  Future<void> initialize() async {
    print('📱 LocalStorageService: Initializing...');

    // Initialize Hive boxes
    _chatsBox = await Hive.openBox('chats');
    _messagesBox = await Hive.openBox('messages');
    _usersBox = await Hive.openBox('users');
    _pendingMessagesBox = await Hive.openBox('pending_messages');
    _deletedMessagesBox = await Hive.openBox('deleted_messages');
    _storageStatsBox = await Hive.openBox('storage_stats');
    _invitationsBox = await Hive.openBox('invitations');

    // Create directories for file storage
    await _createDirectories();

    print('📱 LocalStorageService: Initialized successfully');
  }

  Future<void> _createDirectories() async {
    if (kIsWeb) {
      // Web platform - use temporary directories or skip file storage
      print(
          '📱 LocalStorageService: Running on web, skipping file directories');
      return;
    }

    // Mobile/Desktop platforms
    _appDocumentsDir = await getApplicationDocumentsDirectory();
    _imagesDir = Directory('${_appDocumentsDir!.path}/sechat_images');
    _tempDir = Directory('${_appDocumentsDir!.path}/sechat_temp');

    // Create directories if they don't exist
    if (!await _imagesDir!.exists()) {
      await _imagesDir!.create(recursive: true);
    }
    if (!await _tempDir!.exists()) {
      await _tempDir!.create(recursive: true);
    }
  }

  // ==================== CHAT MANAGEMENT ====================

  Future<void> saveChat(Chat chat) async {
    await _chatsBox.put(chat.id, chat.toJson());
    notifyListeners();
  }

  Future<void> saveChats(List<Chat> chats) async {
    final batch = _chatsBox.toMap();
    for (final chat in chats) {
      batch[chat.id] = chat.toJson();
    }
    await _chatsBox.putAll(batch);
    notifyListeners();
  }

  List<Chat> getAllChats() {
    final chats = <Chat>[];
    for (final value in _chatsBox.values) {
      try {
        chats.add(Chat.fromJson(value));
      } catch (e) {
        print('📱 LocalStorageService: Error parsing chat: $e');
      }
    }
    return chats;
  }

  Chat? getChat(String chatId) {
    final data = _chatsBox.get(chatId);
    if (data != null) {
      try {
        return Chat.fromJson(data);
      } catch (e) {
        print('📱 LocalStorageService: Error parsing chat $chatId: $e');
      }
    }
    return null;
  }

  Future<void> deleteChat(String chatId) async {
    await _chatsBox.delete(chatId);
    // Also delete all messages for this chat
    await deleteMessagesForChat(chatId);
    notifyListeners();
  }

  Future<void> updateChatLastMessage(String chatId, Message message) async {
    final chat = getChat(chatId);
    if (chat != null) {
      final updatedChat = chat.copyWith(
        lastMessageAt: message.createdAt,
        lastMessage: message.toJson(),
      );
      await saveChat(updatedChat);
    }
  }

  // ==================== MESSAGE MANAGEMENT ====================

  Future<void> saveMessage(Message message) async {
    await _messagesBox.put('${message.chatId}_${message.id}', message.toJson());

    // Update chat's last message
    await updateChatLastMessage(message.chatId, message);

    notifyListeners();
  }

  Future<void> saveMessages(List<Message> messages) async {
    final batch = <String, dynamic>{};
    for (final message in messages) {
      batch['${message.chatId}_${message.id}'] = message.toJson();
    }
    await _messagesBox.putAll(batch);
    notifyListeners();
  }

  List<Message> getMessagesForChat(String chatId) {
    final messages = <Message>[];
    final prefix = '${chatId}_';

    for (final key in _messagesBox.keys) {
      if (key.toString().startsWith(prefix)) {
        try {
          final data = _messagesBox.get(key);
          if (data != null) {
            messages.add(Message.fromJson(data));
          }
        } catch (e) {
          print('📱 LocalStorageService: Error parsing message: $e');
        }
      }
    }

    // Sort by creation time (oldest first)
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  Message? getMessage(String chatId, String messageId) {
    final data = _messagesBox.get('${chatId}_$messageId');
    if (data != null) {
      try {
        return Message.fromJson(data);
      } catch (e) {
        print('📱 LocalStorageService: Error parsing message $messageId: $e');
      }
    }
    return null;
  }

  Future<void> updateMessageStatus(
      String chatId, String messageId, String status) async {
    final message = getMessage(chatId, messageId);
    if (message != null) {
      final updatedMessage = message.copyWith(
        status: status,
        updatedAt: DateTime.now(),
      );
      await saveMessage(updatedMessage);
    }
  }

  Future<void> deleteMessage(String chatId, String messageId,
      {bool deleteForEveryone = false}) async {
    if (deleteForEveryone) {
      // Mark for deletion on all devices
      await _deletedMessagesBox.put('${chatId}_$messageId', {
        'chatId': chatId,
        'messageId': messageId,
        'deletedAt': DateTime.now().toIso8601String(),
        'deleteForEveryone': true,
      });
    }

    // Delete locally
    await _messagesBox.delete('${chatId}_$messageId');
    notifyListeners();
  }

  Future<void> deleteMessagesForChat(String chatId) async {
    final prefix = '${chatId}_';
    final keysToDelete = <String>[];

    for (final key in _messagesBox.keys) {
      if (key.toString().startsWith(prefix)) {
        keysToDelete.add(key.toString());
      }
    }

    await _messagesBox.deleteAll(keysToDelete);
    notifyListeners();
  }

  // ==================== PENDING MESSAGES (OFFLINE QUEUE) ====================

  Future<void> addPendingMessage(Message message) async {
    await _pendingMessagesBox.put('${message.chatId}_${message.id}', {
      ...message.toJson(),
      'pending': true,
      'queuedAt': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  List<Map<String, dynamic>> getPendingMessages() {
    final pending = <Map<String, dynamic>>[];
    for (final value in _pendingMessagesBox.values) {
      pending.add(Map<String, dynamic>.from(value));
    }
    return pending;
  }

  Future<void> removePendingMessage(String chatId, String messageId) async {
    await _pendingMessagesBox.delete('${chatId}_$messageId');
    notifyListeners();
  }

  Future<void> clearPendingMessages() async {
    await _pendingMessagesBox.clear();
    notifyListeners();
  }

  Future<void> markMessageAsDeleted(
      String chatId, String messageId, String deleteType) async {
    try {
      // Get the message from local storage
      final messages = getMessagesForChat(chatId);
      final messageIndex = messages.indexWhere((m) => m.id == messageId);

      if (messageIndex != -1) {
        final message = messages[messageIndex];
        final updatedMessage = message.copyWith(
          isDeleted: true,
          deleteType: deleteType,
        );

        // Update in local storage
        await _messagesBox.put(messageId, updatedMessage.toJson());

        print(
            '📱 LocalStorageService: Marked message $messageId as deleted ($deleteType)');
      }
    } catch (e) {
      print('📱 LocalStorageService: Error marking message as deleted: $e');
      throw e;
    }
  }

  // ==================== USER MANAGEMENT ====================

  Future<void> saveUser(User user) async {
    await _usersBox.put(user.id, user.toJson());
    notifyListeners();
  }

  User? getUser(String userId) {
    final data = _usersBox.get(userId);
    if (data != null) {
      try {
        return User.fromJson(data);
      } catch (e) {
        print('📱 LocalStorageService: Error parsing user $userId: $e');
      }
    }
    return null;
  }

  List<User> getAllUsers() {
    final users = <User>[];
    for (final value in _usersBox.values) {
      try {
        users.add(User.fromJson(value));
      } catch (e) {
        print('📱 LocalStorageService: Error parsing user: $e');
      }
    }
    return users;
  }

  Future<void> saveUsers(List<Map<String, dynamic>> usersData) async {
    final batch = <String, dynamic>{};
    for (final userData in usersData) {
      batch[userData['id']] = userData;
    }
    await _usersBox.putAll(batch);
    notifyListeners();
  }

  // ==================== IMAGE STORAGE ====================

  Future<String> saveImage(Uint8List imageData, String fileName) async {
    if (kIsWeb) {
      // Web platform - store in memory or use alternative storage
      print(
          '📱 LocalStorageService: Web platform - image storage not implemented');
      return 'web://$fileName';
    }

    final file = File('${_imagesDir!.path}/$fileName');
    await file.writeAsBytes(imageData);
    return file.path;
  }

  Future<String> saveImageFromFile(File imageFile) async {
    if (kIsWeb) {
      // Web platform - store in memory or use alternative storage
      print(
          '📱 LocalStorageService: Web platform - image storage not implemented');
      return 'web://${_uuid.v4()}.jpg';
    }

    final fileName = '${_uuid.v4()}.jpg';
    final destinationFile = File('${_imagesDir!.path}/$fileName');
    await imageFile.copy(destinationFile.path);
    return destinationFile.path;
  }

  Future<File?> getImageFile(String fileName) async {
    if (kIsWeb) {
      // Web platform - return null for now
      print(
          '📱 LocalStorageService: Web platform - image retrieval not implemented');
      return null;
    }

    final file = File('${_imagesDir!.path}/$fileName');
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  Future<void> deleteImage(String fileName) async {
    if (kIsWeb) {
      // Web platform - no-op for now
      print(
          '📱 LocalStorageService: Web platform - image deletion not implemented');
      return;
    }

    final file = File('${_imagesDir!.path}/$fileName');
    if (await file.exists()) {
      await file.delete();
    }
  }

  // ==================== STORAGE STATISTICS ====================

  Future<Map<String, dynamic>> getStorageStats() async {
    final stats = <String, dynamic>{};

    // Calculate message statistics
    final allMessages = <Message>[];
    for (final value in _messagesBox.values) {
      try {
        allMessages.add(Message.fromJson(value));
      } catch (e) {
        // Skip invalid messages
      }
    }

    final textMessages =
        allMessages.where((m) => m.type == MessageType.text).length;
    final imageMessages =
        allMessages.where((m) => m.type == MessageType.image).length;
    final voiceMessages =
        allMessages.where((m) => m.type == MessageType.voice).length;
    final fileMessages =
        allMessages.where((m) => m.type == MessageType.file).length;

    // Calculate file sizes
    int totalImageSize = 0;
    int totalVoiceSize = 0;
    int totalFileSize = 0;

    if (!kIsWeb && _imagesDir != null && await _imagesDir!.exists()) {
      await for (final file in _imagesDir!.list(recursive: true)) {
        if (file is File) {
          totalImageSize += await file.length();
        }
      }
    }

    stats['totalMessages'] = allMessages.length;
    stats['textMessages'] = textMessages;
    stats['imageMessages'] = imageMessages;
    stats['voiceMessages'] = voiceMessages;
    stats['fileMessages'] = fileMessages;
    stats['totalImageSize'] = totalImageSize;
    stats['totalVoiceSize'] = totalVoiceSize;
    stats['totalFileSize'] = totalFileSize;
    stats['totalStorageSize'] = totalImageSize + totalVoiceSize + totalFileSize;
    stats['chatsCount'] = _chatsBox.length;
    stats['usersCount'] = _usersBox.length;
    stats['pendingMessagesCount'] = _pendingMessagesBox.length;

    return stats;
  }

  // Clear all data
  Future<void> clearAllData() async {
    await _chatsBox.clear();
    await _messagesBox.clear();
    await _usersBox.clear();
    await _pendingMessagesBox.clear();
    await _deletedMessagesBox.clear();
    await _storageStatsBox.clear();
    await _invitationsBox.clear();
    notifyListeners();
  }

  // Public methods for provider compatibility

  // Get all chats
  List<Chat> getChats() {
    return getAllChats();
  }

  // Get messages for a chat
  List<Message> getMessages(String chatId) {
    return getMessagesForChat(chatId);
  }

  // Get invitations (Session contacts)
  List<Map<String, dynamic>> getInvitations() {
    final invitations = <Map<String, dynamic>>[];
    for (final value in _invitationsBox.values) {
      try {
        if (value is Map<String, dynamic>) {
          invitations.add(value);
        }
      } catch (e) {
        print('📱 LocalStorageService: Error parsing invitation: $e');
      }
    }
    return invitations;
  }

  // Save invitations (Session contacts)
  Future<void> saveInvitations(List<Map<String, dynamic>> invitations) async {
    final batch = <String, dynamic>{};
    for (int i = 0; i < invitations.length; i++) {
      batch['invitation_$i'] = invitations[i];
    }
    await _invitationsBox.putAll(batch);
    notifyListeners();
  }

  // Session Protocol specific methods

  // Save Session identity
  Future<void> saveSessionIdentity(Map<String, dynamic> identity) async {
    await _storageStatsBox.put('session_identity', identity);
    notifyListeners();
  }

  // Get Session identity
  Map<String, dynamic>? getSessionIdentity() {
    final data = _storageStatsBox.get('session_identity');
    if (data is Map<String, dynamic>) {
      return data;
    }
    return null;
  }

  // Save Session contacts
  Future<void> saveSessionContacts(List<Map<String, dynamic>> contacts) async {
    final batch = <String, dynamic>{};
    for (int i = 0; i < contacts.length; i++) {
      batch['contact_$i'] = contacts[i];
    }
    await _usersBox.putAll(batch);
    notifyListeners();
  }

  // Get Session contacts
  List<Map<String, dynamic>> getSessionContacts() {
    final contacts = <Map<String, dynamic>>[];
    for (final value in _usersBox.values) {
      try {
        if (value is Map<String, dynamic>) {
          contacts.add(value);
        }
      } catch (e) {
        print('📱 LocalStorageService: Error parsing contact: $e');
      }
    }
    return contacts;
  }

  Future<void> clearOldMessages({int daysToKeep = 30}) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
    final keysToDelete = <String>[];

    for (final key in _messagesBox.keys) {
      try {
        final data = _messagesBox.get(key);
        if (data != null) {
          final message = Message.fromJson(data);
          if (message.createdAt.isBefore(cutoffDate)) {
            keysToDelete.add(key.toString());
          }
        }
      } catch (e) {
        // Skip invalid messages
      }
    }

    await _messagesBox.deleteAll(keysToDelete);
    notifyListeners();
  }

  // ==================== INVITATION MANAGEMENT ====================

  Future<void> saveInvitation(Map<String, dynamic> invitationData) async {
    await _invitationsBox.put(invitationData['id'], invitationData);
    notifyListeners();
  }

  Future<void> deleteInvitation(String invitationId) async {
    await _invitationsBox.delete(invitationId);
    notifyListeners();
  }

  Future<void> clearAllInvitations() async {
    await _invitationsBox.clear();
    notifyListeners();
  }

  // ==================== RECENT SEARCHES ====================

  Future<void> saveRecentSearches(List<User> recentSearches) async {
    final searchesData = recentSearches.map((user) => user.toJson()).toList();
    await _usersBox.put('recent_searches', searchesData);
    notifyListeners();
  }

  List<User> getRecentSearches() {
    final data = _usersBox.get('recent_searches');
    if (data != null && data is List) {
      try {
        return data.map((userData) => User.fromJson(userData)).toList();
      } catch (e) {
        print('📱 LocalStorageService: Error parsing recent searches: $e');
      }
    }
    return [];
  }

  Future<void> clearRecentSearches() async {
    await _usersBox.delete('recent_searches');
    notifyListeners();
  }

  // ==================== UTILITY METHODS ====================

  String generateMessageId() {
    return _uuid.v4();
  }

  String generateChatId() {
    return _uuid.v4();
  }

  Future<void> close() async {
    await _chatsBox.close();
    await _messagesBox.close();
    await _usersBox.close();
    await _pendingMessagesBox.close();
    await _deletedMessagesBox.close();
    await _storageStatsBox.close();
    await _invitationsBox.close();
  }
}
