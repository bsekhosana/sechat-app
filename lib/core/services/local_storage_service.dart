import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import '../../shared/models/chat.dart';
import '../../shared/models/message.dart';
import '../../shared/models/user.dart';
import 'se_shared_preference_service.dart';

class LocalStorageService extends ChangeNotifier {
  static LocalStorageService? _instance;
  static LocalStorageService get instance =>
      _instance ??= LocalStorageService._();

  final SeSharedPreferenceService _prefsService = SeSharedPreferenceService();
  final Uuid _uuid = const Uuid();
  Directory? _appDocumentsDir;
  Directory? _imagesDir;
  Directory? _tempDir;
  bool _isInitialized = false;

  LocalStorageService._();

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Create directories for file storage
      await _createDirectories();
      _isInitialized = true;
    } catch (e) {
      print('📱 LocalStorageService: Error initializing: $e');
    }
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
  // Note: Chat operations are now handled by MessageStorageService
  // These methods are kept for backward compatibility but are deprecated

  @Deprecated('Use MessageStorageService.saveConversation instead')
  Future<void> saveChat(Chat chat) async {
    print(
        '📱 LocalStorageService: ⚠️ saveChat is deprecated, use MessageStorageService.saveConversation instead');
    // No-op - chats are now stored in database
  }

  @Deprecated('Use MessageStorageService instead')
  Future<void> saveChats(List<Chat> chats) async {
    print(
        '📱 LocalStorageService: ⚠️ saveChats is deprecated, use MessageStorageService instead');
    // No-op - chats are now stored in database
  }

  @Deprecated('Use MessageStorageService.getUserConversations instead')
  Future<List<Chat>> getAllChats() async {
    print(
        '📱 LocalStorageService: ⚠️ getAllChats is deprecated, use MessageStorageService.getUserConversations instead');
    return []; // No-op - chats are now stored in database
  }

  @Deprecated('Use MessageStorageService instead')
  Future<void> deleteChat(String chatId) async {
    print(
        '📱 LocalStorageService: ⚠️ deleteChat is deprecated, use MessageStorageService instead');
    // No-op - chats are now stored in database
  }

  // ==================== MESSAGE MANAGEMENT ====================
  // Note: Message operations are now handled by MessageStorageService
  // These methods are kept for backward compatibility but are deprecated

  @Deprecated('Use MessageStorageService.saveMessage instead')
  Future<void> saveMessage(Message message) async {
    print(
        '📱 LocalStorageService: ⚠️ saveMessage is deprecated, use MessageStorageService.saveMessage instead');
    // No-op - messages are now stored in database
  }

  @Deprecated('Use MessageStorageService instead')
  Future<void> saveMessages(List<Message> messages) async {
    print(
        '📱 LocalStorageService: ⚠️ saveMessages is deprecated, use MessageStorageService instead');
    // No-op - messages are now stored in database
  }

  @Deprecated('Use MessageStorageService.getConversationMessages instead')
  Future<List<Message>> getMessagesForChat(String chatId) async {
    print(
        '📱 LocalStorageService: ⚠️ getMessagesForChat is deprecated, use MessageStorageService.getConversationMessages instead');
    return []; // No-op - messages are now stored in database
  }

  @Deprecated('Use MessageStorageService instead')
  Future<void> deleteMessage(String messageId) async {
    print(
        '📱 LocalStorageService: ⚠️ deleteMessage is deprecated, use MessageStorageService instead');
    // No-op - messages are now stored in database
  }

  // ==================== USER MANAGEMENT ====================

  Future<void> saveUser(User user) async {
    final usersJson = await _prefsService.getJsonList('users') ?? [];
    final existingIndex = usersJson.indexWhere((u) => u['id'] == user.id);

    if (existingIndex != -1) {
      usersJson[existingIndex] = user.toJson();
    } else {
      usersJson.add(user.toJson());
    }

    await _prefsService.setJsonList('users', usersJson);
    notifyListeners();
  }

  Future<List<User>> getAllUsers() async {
    final users = <User>[];
    try {
      final usersJson = await _prefsService.getJsonList('users') ?? [];
      for (final userJson in usersJson) {
        try {
          users.add(User.fromJson(userJson));
        } catch (e) {
          print('📱 LocalStorageService: Error parsing user: $e');
        }
      }
    } catch (e) {
      print('📱 LocalStorageService: Error loading users: $e');
    }
    return users;
  }

  // ==================== INVITATION MANAGEMENT ====================

  Future<void> saveInvitation(Map<String, dynamic> invitation) async {
    final invitationsJson =
        await _prefsService.getJsonList('invitations') ?? [];
    final existingIndex =
        invitationsJson.indexWhere((inv) => inv['id'] == invitation['id']);

    if (existingIndex != -1) {
      invitationsJson[existingIndex] = invitation;
    } else {
      invitationsJson.add(invitation);
    }

    await _prefsService.setJsonList('invitations', invitationsJson);
    notifyListeners();
  }

  Future<Map<String, dynamic>?> getInvitation(String invitationId) async {
    try {
      final invitationsJson =
          await _prefsService.getJsonList('invitations') ?? [];
      for (final invitationJson in invitationsJson) {
        if (invitationJson['id'] == invitationId) {
          return invitationJson;
        }
      }
    } catch (e) {
      print('📱 LocalStorageService: Error loading invitation: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getAllInvitations() async {
    try {
      final invitationsJson =
          await _prefsService.getJsonList('invitations') ?? [];
      return invitationsJson;
    } catch (e) {
      print('📱 LocalStorageService: Error loading invitations: $e');
      return [];
    }
  }

  // ==================== NOTIFICATION MANAGEMENT ====================

  Future<void> saveNotification(Map<String, dynamic> notification) async {
    final notificationsJson =
        await _prefsService.getJsonList('notifications') ?? [];
    final existingIndex = notificationsJson
        .indexWhere((notif) => notif['id'] == notification['id']);

    if (existingIndex != -1) {
      notificationsJson[existingIndex] = notification;
    } else {
      notificationsJson.add(notification);
    }

    await _prefsService.setJsonList('notifications', notificationsJson);
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getAllNotifications() async {
    try {
      final notificationsJson =
          await _prefsService.getJsonList('notifications') ?? [];
      return notificationsJson;
    } catch (e) {
      print('📱 LocalStorageService: Error loading notifications: $e');
      return [];
    }
  }

  // ==================== STORAGE MANAGEMENT ====================

  Future<Map<String, dynamic>> getStorageStats() async {
    try {
      final stats = <String, dynamic>{};

      // Count chats
      final chatsJson = await _prefsService.getJsonList('chats') ?? [];
      stats['totalChats'] = chatsJson.length;

      // Count messages
      final messagesJson = await _prefsService.getJsonList('messages') ?? [];
      stats['totalMessages'] = messagesJson.length;

      // Count users
      final usersJson = await _prefsService.getJsonList('users') ?? [];
      stats['totalUsers'] = usersJson.length;

      // Count invitations
      final invitationsJson =
          await _prefsService.getJsonList('invitations') ?? [];
      stats['totalInvitations'] = invitationsJson.length;

      // Count notifications
      final notificationsJson =
          await _prefsService.getJsonList('notifications') ?? [];
      stats['totalNotifications'] = notificationsJson.length;

      return stats;
    } catch (e) {
      print('📱 LocalStorageService: Error getting storage stats: $e');
      return {};
    }
  }

  Future<void> clearOldMessages({int daysToKeep = 30}) async {
    try {
      print(
          '📱 LocalStorageService: Clearing old messages (keeping last $daysToKeep days)...');

      final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
      final messagesJson = await _prefsService.getJsonList('messages') ?? [];
      final updatedMessages = <Map<String, dynamic>>[];

      for (final messageJson in messagesJson) {
        try {
          final createdAt = DateTime.parse(
              messageJson['createdAt'] ?? DateTime.now().toIso8601String());
          if (createdAt.isAfter(cutoffDate)) {
            updatedMessages.add(messageJson);
          }
        } catch (e) {
          print('📱 LocalStorageService: Error parsing message date: $e');
          // Keep message if we can't parse the date
          updatedMessages.add(messageJson);
        }
      }

      await _prefsService.setJsonList('messages', updatedMessages);
      notifyListeners();
      print(
          '📱 LocalStorageService: ✅ Old messages cleared (${messagesJson.length - updatedMessages.length} messages removed)');
    } catch (e) {
      print('📱 LocalStorageService: Error clearing old messages: $e');
    }
  }

  Future<void> clearAllData() async {
    try {
      print('📱 LocalStorageService: Clearing all data...');

      await _prefsService.remove('chats');
      await _prefsService.remove('messages');
      await _prefsService.remove('users');
      await _prefsService.remove('invitations');
      await _prefsService.remove('notifications');

      notifyListeners();
      print('📱 LocalStorageService: ✅ All data cleared');
    } catch (e) {
      print('📱 LocalStorageService: Error clearing all data: $e');
    }
  }

  // ==================== FILE STORAGE ====================

  Future<String> saveImage(Uint8List imageData, String fileName) async {
    if (kIsWeb) {
      throw UnsupportedError('File storage not supported on web');
    }

    final file = File('${_imagesDir!.path}/$fileName');
    await file.writeAsBytes(imageData);
    return file.path;
  }

  Future<Uint8List?> loadImage(String filePath) async {
    if (kIsWeb) {
      throw UnsupportedError('File storage not supported on web');
    }

    final file = File(filePath);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  Future<void> deleteImage(String filePath) async {
    if (kIsWeb) {
      throw UnsupportedError('File storage not supported on web');
    }

    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<String> getTempFilePath(String fileName) async {
    if (kIsWeb) {
      throw UnsupportedError('File storage not supported on web');
    }

    return '${_tempDir!.path}/$fileName';
  }

  Future<void> cleanupTempFiles() async {
    if (kIsWeb) {
      return;
    }

    try {
      final tempDir = _tempDir!;
      if (await tempDir.exists()) {
        await for (final file in tempDir.list()) {
          if (file is File) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      print('📱 LocalStorageService: Error cleaning up temp files: $e');
    }
  }
}
