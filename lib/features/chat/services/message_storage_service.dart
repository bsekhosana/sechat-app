import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/message.dart';
import '../models/media_message.dart';
import '../models/chat_conversation.dart';
import '../../../core/services/se_shared_preference_service.dart';
import '../../../core/services/se_session_service.dart';

/// Service for managing local storage of chat messages and conversations
class MessageStorageService {
  static MessageStorageService? _instance;
  static MessageStorageService get instance =>
      _instance ??= MessageStorageService._();

  Database? _database;
  final SeSharedPreferenceService _prefsService = SeSharedPreferenceService();
  Directory? _mediaDirectory;
  Directory? _thumbnailsDirectory;

  MessageStorageService._();

  /// Initialize the storage service
  Future<void> initialize() async {
    try {
      print('💾 MessageStorageService: Initializing storage service');

      // Initialize database
      await _initializeDatabase();

      // Initialize media directories
      await _initializeMediaDirectories();

      print(
          '💾 MessageStorageService: ✅ Storage service initialized successfully');
    } catch (e) {
      print(
          '💾 MessageStorageService: ❌ Failed to initialize storage service: $e');
      rethrow;
    }
  }

  /// Initialize SQLite database
  Future<void> _initializeDatabase() async {
    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final databasePath =
          path.join(documentsDirectory.path, 'chat_database.db');

      _database = await openDatabase(
        databasePath,
        version: 2,
        onCreate: _createDatabaseTables,
        onUpgrade: _upgradeDatabase,
      );

      print('💾 MessageStorageService: ✅ Database initialized');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to initialize database: $e');
      rethrow;
    }
  }

  /// Create database tables
  Future<void> _createDatabaseTables(Database db, int version) async {
    try {
      // Conversations table
      await db.execute('''
        CREATE TABLE conversations (
          id TEXT PRIMARY KEY,
          participant1_id TEXT NOT NULL,
          participant2_id TEXT NOT NULL,
          display_name TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          last_message_at TEXT,
          last_message_id TEXT,
          last_message_preview TEXT,
          last_message_type TEXT,
          unread_count INTEGER DEFAULT 0,
          is_archived INTEGER DEFAULT 0,
          is_muted INTEGER DEFAULT 0,
          is_pinned INTEGER DEFAULT 0,
          metadata TEXT,
          last_seen TEXT,
          is_typing INTEGER DEFAULT 0,
          typing_started_at TEXT,
          notifications_enabled INTEGER DEFAULT 1,
          sound_enabled INTEGER DEFAULT 1,
          vibration_enabled INTEGER DEFAULT 1,
          read_receipts_enabled INTEGER DEFAULT 1,
          typing_indicators_enabled INTEGER DEFAULT 1,
          last_seen_enabled INTEGER DEFAULT 1,
          media_auto_download INTEGER DEFAULT 1,
          encrypt_media INTEGER DEFAULT 1,
          media_quality TEXT DEFAULT 'High',
          message_retention TEXT DEFAULT '30 days',
          is_blocked INTEGER DEFAULT 0,
          blocked_at TEXT,
          recipient_id TEXT,
          recipient_name TEXT
        )
      ''');

      // Messages table
      await db.execute('''
        CREATE TABLE messages (
          id TEXT PRIMARY KEY,
          conversation_id TEXT NOT NULL,
          sender_id TEXT NOT NULL,
          recipient_id TEXT NOT NULL,
          type TEXT NOT NULL,
          content TEXT NOT NULL,
          status TEXT NOT NULL,
          timestamp TEXT NOT NULL,
          delivered_at TEXT,
          read_at TEXT,
          deleted_at TEXT,
          reply_to_message_id TEXT,
          metadata TEXT,
          is_encrypted INTEGER DEFAULT 1,
          checksum TEXT,
          file_size INTEGER,
          mime_type TEXT,
          FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE
        )
      ''');

      // Message status table
      await db.execute('''
        CREATE TABLE message_status (
          id TEXT PRIMARY KEY,
          message_id TEXT NOT NULL,
          conversation_id TEXT NOT NULL,
          recipient_id TEXT NOT NULL,
          delivery_status TEXT NOT NULL,
          timestamp TEXT NOT NULL,
          delivered_at TEXT,
          read_at TEXT,
          error_message TEXT,
          retry_count INTEGER DEFAULT 0,
          last_retry_at TEXT,
          FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE
        )
      ''');

      // Media messages table
      await db.execute('''
        CREATE TABLE media_messages (
          id TEXT PRIMARY KEY,
          message_id TEXT NOT NULL,
          type TEXT NOT NULL,
          file_path TEXT NOT NULL,
          file_name TEXT NOT NULL,
          mime_type TEXT NOT NULL,
          file_size INTEGER NOT NULL,
          duration INTEGER,
          width INTEGER,
          height INTEGER,
          is_compressed INTEGER DEFAULT 0,
          thumbnail_path TEXT,
          metadata TEXT,
          created_at TEXT NOT NULL,
          processed_at TEXT,
          FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE
        )
      ''');

      // Create indexes for better performance
      await db.execute(
          'CREATE INDEX idx_conversations_participants ON conversations (participant1_id, participant2_id)');
      await db.execute(
          'CREATE INDEX idx_messages_conversation ON messages (conversation_id)');
      await db
          .execute('CREATE INDEX idx_messages_sender ON messages (sender_id)');
      await db.execute(
          'CREATE INDEX idx_messages_recipient ON messages (recipient_id)');
      await db.execute(
          'CREATE INDEX idx_messages_timestamp ON messages (timestamp)');
      await db.execute(
          'CREATE INDEX idx_message_status_message ON message_status (message_id)');
      await db.execute(
          'CREATE INDEX idx_media_messages_message ON media_messages (message_id)');

      print('💾 MessageStorageService: ✅ Database tables created');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to create database tables: $e');
      rethrow;
    }
  }

  /// Upgrade database schema
  Future<void> _upgradeDatabase(
      Database db, int oldVersion, int newVersion) async {
    print(
        '💾 MessageStorageService: Upgrading database from v$oldVersion to v$newVersion');

    if (oldVersion < 2) {
      // Add new columns to conversations table
      try {
        print(
            '💾 MessageStorageService: 🔄 Starting database upgrade to v2...');

        // Check if columns already exist before adding them
        final existingColumns = await db.query('conversations', limit: 1);
        final columns = existingColumns.isNotEmpty
            ? existingColumns.first.keys.toList()
            : <String>[];

        if (!columns.contains('notifications_enabled')) {
          await db.execute(
              'ALTER TABLE conversations ADD COLUMN notifications_enabled INTEGER DEFAULT 1');
        }
        if (!columns.contains('sound_enabled')) {
          await db.execute(
              'ALTER TABLE conversations ADD COLUMN sound_enabled INTEGER DEFAULT 1');
        }
        if (!columns.contains('vibration_enabled')) {
          await db.execute(
              'ALTER TABLE conversations ADD COLUMN vibration_enabled INTEGER DEFAULT 1');
        }
        if (!columns.contains('read_receipts_enabled')) {
          await db.execute(
              'ALTER TABLE conversations ADD COLUMN read_receipts_enabled INTEGER DEFAULT 1');
        }
        if (!columns.contains('typing_indicators_enabled')) {
          await db.execute(
              'ALTER TABLE conversations ADD COLUMN typing_indicators_enabled INTEGER DEFAULT 1');
        }
        if (!columns.contains('last_seen_enabled')) {
          await db.execute(
              'ALTER TABLE conversations ADD COLUMN last_seen_enabled INTEGER DEFAULT 1');
        }
        if (!columns.contains('media_auto_download')) {
          await db.execute(
              'ALTER TABLE conversations ADD COLUMN media_auto_download INTEGER DEFAULT 1');
        }
        if (!columns.contains('encrypt_media')) {
          await db.execute(
              'ALTER TABLE conversations ADD COLUMN encrypt_media INTEGER DEFAULT 1');
        }
        if (!columns.contains('media_quality')) {
          await db.execute(
              'ALTER TABLE conversations ADD COLUMN media_quality TEXT DEFAULT "High"');
        }
        if (!columns.contains('message_retention')) {
          await db.execute(
              'ALTER TABLE conversations ADD COLUMN message_retention TEXT DEFAULT "30 days"');
        }
        if (!columns.contains('is_blocked')) {
          await db.execute(
              'ALTER TABLE conversations ADD COLUMN is_blocked INTEGER DEFAULT 0');
        }
        if (!columns.contains('blocked_at')) {
          await db
              .execute('ALTER TABLE conversations ADD COLUMN blocked_at TEXT');
        }
        if (!columns.contains('recipient_id')) {
          await db.execute(
              'ALTER TABLE conversations ADD COLUMN recipient_id TEXT');
        }
        if (!columns.contains('recipient_name')) {
          await db.execute(
              'ALTER TABLE conversations ADD COLUMN recipient_name TEXT');
        }

        print('💾 MessageStorageService: ✅ Database upgraded to v2');
      } catch (e) {
        print('💾 MessageStorageService: ❌ Failed to upgrade database: $e');
        // If upgrade fails, recreate the table
        print('💾 MessageStorageService: 🔄 Recreating conversations table...');
        await db.execute('DROP TABLE IF EXISTS conversations');
        await _createDatabaseTables(db, newVersion);
      }
    }
  }

  /// Initialize media storage directories
  Future<void> _initializeMediaDirectories() async {
    try {
      final appDocumentsDirectory = await getApplicationDocumentsDirectory();

      // Create media directory
      _mediaDirectory =
          Directory(path.join(appDocumentsDirectory.path, 'chat_media'));
      if (!await _mediaDirectory!.exists()) {
        await _mediaDirectory!.create(recursive: true);
      }

      // Create thumbnails directory
      _thumbnailsDirectory =
          Directory(path.join(appDocumentsDirectory.path, 'chat_thumbnails'));
      if (!await _thumbnailsDirectory!.exists()) {
        await _thumbnailsDirectory!.create(recursive: true);
      }

      print('💾 MessageStorageService: ✅ Media directories initialized');
    } catch (e) {
      print(
          '💾 MessageStorageService: ❌ Failed to initialize media directories: $e');
      rethrow;
    }
  }

  /// Save a conversation to the database
  Future<void> saveConversation(ChatConversation conversation) async {
    try {
      if (_database == null) {
        print(
            '💾 MessageStorageService: ❌ Database is null, attempting to initialize...');
        await initialize();
        if (_database == null) {
          throw Exception(
              'Database still not initialized after initialization attempt');
        }
      }

      // Check if database has correct schema
      if (!await isDatabaseReady()) {
        print(
            '💾 MessageStorageService: ⚠️ Database schema not ready, attempting upgrade...');
        await _database!.close();
        _database = null;
        await initialize();
        if (!await isDatabaseReady()) {
          throw Exception(
              'Database schema still not ready after upgrade attempt');
        }
      }

      final conversationData = conversation.toJson();
      print(
          '💾 MessageStorageService: 📊 Saving conversation data: $conversationData');

      await _database!.insert(
        'conversations',
        conversationData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      print(
          '💾 MessageStorageService: ✅ Conversation saved: ${conversation.id}');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to save conversation: $e');
      print(
          '💾 MessageStorageService: 🔍 Error details: ${e.runtimeType} - $e');
      rethrow;
    }
  }

  /// Get a conversation by ID
  Future<ChatConversation?> getConversation(String conversationId) async {
    try {
      if (_database == null) {
        throw Exception('Database not initialized');
      }

      final List<Map<String, dynamic>> results = await _database!.query(
        'conversations',
        where: 'id = ?',
        whereArgs: [conversationId],
      );

      if (results.isNotEmpty) {
        return ChatConversation.fromJson(results.first);
      }

      return null;
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to get conversation: $e');
      return null;
    }
  }

  /// Get all conversations for a user
  Future<List<ChatConversation>> getUserConversations(String userId) async {
    try {
      if (_database == null) {
        throw Exception('Database not initialized');
      }

      final List<Map<String, dynamic>> results = await _database!.query(
        'conversations',
        where: 'participant1_id = ? OR participant2_id = ?',
        whereArgs: [userId, userId],
        orderBy: 'updated_at DESC',
      );

      print(
          '💾 MessageStorageService: 📊 Found ${results.length} conversations for user $userId');

      if (results.isNotEmpty) {
        print(
            '💾 MessageStorageService: 🔍 Sample conversation data: ${results.first}');
      }

      final conversations = <ChatConversation>[];
      for (int i = 0; i < results.length; i++) {
        try {
          final conversation = ChatConversation.fromJson(results[i]);
          conversations.add(conversation);
        } catch (e) {
          print(
              '💾 MessageStorageService: ❌ Failed to parse conversation $i: $e');
          print('💾 MessageStorageService: 🔍 Raw data: ${results[i]}');
        }
      }

      return conversations;
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to get user conversations: $e');
      return [];
    }
  }

  /// Save a message to the database
  Future<void> saveMessage(Message message) async {
    try {
      if (_database == null) {
        throw Exception('Database not initialized');
      }

      await _database!.insert(
        'messages',
        message.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      print('💾 MessageStorageService: ✅ Message saved: ${message.id}');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to save message: $e');
      rethrow;
    }
  }

  /// Get messages for a conversation
  Future<List<Message>> getConversationMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      if (_database == null) {
        throw Exception('Database not initialized');
      }

      final List<Map<String, dynamic>> results = await _database!.query(
        'messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        orderBy: 'timestamp DESC',
        limit: limit,
        offset: offset,
      );

      return results.map((json) => Message.fromJson(json)).toList();
    } catch (e) {
      print(
          '💾 MessageStorageService: ❌ Failed to get conversation messages: $e');
      return [];
    }
  }

  /// Update message status
  Future<void> updateMessageStatus(
      String messageId, MessageStatus messageStatus) async {
    try {
      if (_database == null) {
        throw Exception('Database not initialized');
      }

      final updateData = <String, dynamic>{
        'status': messageStatus.name,
      };

      // Add timestamp based on status
      switch (messageStatus) {
        case MessageStatus.delivered:
          updateData['delivered_at'] = DateTime.now().toIso8601String();
          break;
        case MessageStatus.read:
          updateData['read_at'] = DateTime.now().toIso8601String();
          break;
        case MessageStatus.deleted:
          updateData['deleted_at'] = DateTime.now().toIso8601String();
          break;
        default:
          break;
      }

      await _database!.update(
        'messages',
        updateData,
        where: 'id = ?',
        whereArgs: [messageId],
      );

      print(
          '💾 MessageStorageService: ✅ Message status updated: $messageId -> ${messageStatus.name}');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to update message status: $e');
      rethrow;
    }
  }

  /// Save media message and file
  Future<void> saveMediaMessage(
    MediaMessage mediaMessage,
    Uint8List fileData, {
    Uint8List? thumbnailData,
  }) async {
    try {
      if (_mediaDirectory == null) {
        throw Exception('Media directory not initialized');
      }

      // Save media file
      final mediaFile =
          File(path.join(_mediaDirectory!.path, mediaMessage.fileName));
      await mediaFile.writeAsBytes(fileData);

      // Save thumbnail if provided
      String? thumbnailPath;
      if (thumbnailData != null && _thumbnailsDirectory != null) {
        final thumbnailFileName =
            'thumb_${mediaMessage.id}${path.extension(mediaMessage.fileName)}';
        final thumbnailFile =
            File(path.join(_thumbnailsDirectory!.path, thumbnailFileName));
        await thumbnailFile.writeAsBytes(thumbnailData);
        thumbnailPath = thumbnailFile.path;
      }

      // Update media message with actual file paths
      final updatedMediaMessage = mediaMessage.copyWith(
        filePath: mediaFile.path,
        thumbnailPath: thumbnailPath,
      );

      // Save to database
      if (_database != null) {
        await _database!.insert(
          'media_messages',
          updatedMediaMessage.toJson(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      print(
          '💾 MessageStorageService: ✅ Media message saved: ${mediaMessage.id}');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to save media message: $e');
      rethrow;
    }
  }

  /// Get media message by ID
  Future<MediaMessage?> getMediaMessage(String mediaMessageId) async {
    try {
      if (_database == null) {
        throw Exception('Database not initialized');
      }

      final List<Map<String, dynamic>> results = await _database!.query(
        'media_messages',
        where: 'id = ?',
        whereArgs: [mediaMessageId],
      );

      if (results.isNotEmpty) {
        return MediaMessage.fromJson(results.first);
      }

      return null;
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to get media message: $e');
      return null;
    }
  }

  /// Get media file as bytes
  Future<Uint8List?> getMediaFile(String mediaMessageId) async {
    try {
      final mediaMessage = await getMediaMessage(mediaMessageId);
      if (mediaMessage == null) return null;

      final file = File(mediaMessage.filePath);
      if (await file.exists()) {
        return await file.readAsBytes();
      }

      return null;
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to get media file: $e');
      return null;
    }
  }

  /// Get thumbnail file as bytes
  Future<Uint8List?> getThumbnail(String mediaMessageId) async {
    try {
      final mediaMessage = await getMediaMessage(mediaMessageId);
      if (mediaMessage?.thumbnailPath == null) return null;

      final file = File(mediaMessage!.thumbnailPath!);
      if (await file.exists()) {
        return await file.readAsBytes();
      }

      return null;
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to get thumbnail: $e');
      return null;
    }
  }

  /// Search messages by text content
  Future<List<Message>> searchMessages(String query, String userId) async {
    try {
      if (_database == null) {
        throw Exception('Database not initialized');
      }

      final List<Map<String, dynamic>> results = await _database!.query(
        'messages',
        where: '(sender_id = ? OR recipient_id = ?) AND content LIKE ?',
        whereArgs: [userId, userId, '%$query%'],
        orderBy: 'timestamp DESC',
        limit: 100,
      );

      return results.map((json) => Message.fromJson(json)).toList();
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to search messages: $e');
      return [];
    }
  }

  /// Get messages for a conversation
  Future<List<Message>> getMessages(String conversationId) async {
    try {
      if (_database == null) {
        throw Exception('Database not initialized');
      }

      final List<Map<String, dynamic>> results = await _database!.query(
        'messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        orderBy: 'timestamp ASC',
      );

      return results.map((row) => Message.fromJson(row)).toList();
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to get messages: $e');
      rethrow;
    }
  }

  /// Delete a conversation and all its messages
  Future<void> deleteConversation(String conversationId) async {
    try {
      if (_database == null) {
        throw Exception('Database not initialized');
      }

      print('💾 MessageStorageService: Deleting conversation: $conversationId');

      // Delete all messages for the conversation
      await _database!.delete(
        'messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
      );

      // Delete the conversation
      await _database!.delete(
        'conversations',
        where: 'id = ?',
        whereArgs: [conversationId],
      );

      // Clear media files for this conversation
      await clearConversationMedia(conversationId);

      print('💾 MessageStorageService: ✅ Conversation deleted successfully');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to delete conversation: $e');
      rethrow;
    }
  }

  /// Get documents directory path
  Future<String> _getDocumentsDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  /// Get current user ID
  String _getCurrentUserId() {
    try {
      // Get the current user ID from the session service
      final sessionId = SeSessionService().currentSessionId;
      if (sessionId != null && sessionId.isNotEmpty) {
        return sessionId;
      }

      // Fallback: generate a unique ID
      print(
          '💾 MessageStorageService: ⚠️ No user ID available, using timestamp fallback');
      return 'user_${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      print('💾 MessageStorageService: ❌ Error getting current user ID: $e');
      return 'user_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Get storage usage statistics
  Future<Map<String, dynamic>> getStorageStats() async {
    try {
      if (_database == null || _mediaDirectory == null) {
        throw Exception('Storage not initialized');
      }

      // Get database size
      final databaseFile = File(_database!.path);
      final databaseSize =
          await databaseFile.exists() ? await databaseFile.length() : 0;

      // Get media files size
      int mediaSize = 0;
      int mediaFileCount = 0;
      if (await _mediaDirectory!.exists()) {
        await for (final entity in _mediaDirectory!.list(recursive: true)) {
          if (entity is File) {
            mediaSize += await entity.length();
            mediaFileCount++;
          }
        }
      }

      // Get thumbnails size
      int thumbnailsSize = 0;
      int thumbnailCount = 0;
      if (_thumbnailsDirectory != null &&
          await _thumbnailsDirectory!.exists()) {
        await for (final entity
            in _thumbnailsDirectory!.list(recursive: true)) {
          if (entity is File) {
            thumbnailsSize += await entity.length();
            thumbnailCount++;
          }
        }
      }

      return {
        'database_size': databaseSize,
        'media_size': mediaSize,
        'thumbnails_size': thumbnailsSize,
        'total_size': databaseSize + mediaSize + thumbnailsSize,
        'media_file_count': mediaFileCount,
        'thumbnail_count': thumbnailCount,
        'total_file_count': mediaFileCount + thumbnailCount,
      };
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to get storage stats: $e');
      return {};
    }
  }

  /// Clean up old messages and media files
  Future<void> cleanupOldData({
    int maxMessageAge = 365, // days
    int maxMediaAge = 90, // days
    int maxDatabaseSize = 100 * 1024 * 1024, // 100MB
  }) async {
    try {
      if (_database == null) {
        throw Exception('Database not initialized');
      }

      print('💾 MessageStorageService: Starting cleanup...');

      // Clean up old messages
      final cutoffDate = DateTime.now().subtract(Duration(days: maxMessageAge));
      final deletedMessages = await _database!.delete(
        'messages',
        where: 'timestamp < ?',
        whereArgs: [cutoffDate.toIso8601String()],
      );

      // Clean up old media files
      final mediaCutoffDate =
          DateTime.now().subtract(Duration(days: maxMediaAge));
      final deletedMedia = await _database!.delete(
        'media_messages',
        where: 'created_at < ?',
        whereArgs: [mediaCutoffDate.toIso8601String()],
      );

      // Clean up orphaned media files
      await _cleanupOrphanedMediaFiles();

      print(
          '💾 MessageStorageService: ✅ Cleanup completed - Messages: $deletedMessages, Media: $deletedMedia');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to cleanup old data: $e');
      rethrow;
    }
  }

  /// Clear conversation media cache
  Future<void> clearConversationMedia(String conversationId) async {
    try {
      if (_database == null) {
        throw Exception('Database not initialized');
      }

      print(
          '💾 MessageStorageService: Clearing media cache for conversation: $conversationId');

      // Get all media messages for the conversation
      final List<Map<String, dynamic>> mediaMessages = await _database!.query(
        'media_messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
      );

      // Delete media files
      for (final media in mediaMessages) {
        final filePath = media['file_path'] as String?;
        final thumbnailPath = media['thumbnail_path'] as String?;

        if (filePath != null) {
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
            print('💾 MessageStorageService: Deleted media file: $filePath');
          }
        }

        if (thumbnailPath != null) {
          final thumbnail = File(thumbnailPath);
          if (await thumbnail.exists()) {
            await thumbnail.delete();
            print(
                '💾 MessageStorageService: Deleted thumbnail: $thumbnailPath');
          }
        }
      }

      // Delete media records from database
      final deletedCount = await _database!.delete(
        'media_messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
      );

      print(
          '💾 MessageStorageService: ✅ Cleared $deletedCount media files for conversation: $conversationId');
    } catch (e) {
      print(
          '💾 MessageStorageService: ❌ Failed to clear conversation media: $e');
      rethrow;
    }
  }

  /// Export conversation
  Future<void> exportConversation(String conversationId, String format) async {
    try {
      if (_database == null) {
        throw Exception('Database not initialized');
      }

      print(
          '💾 MessageStorageService: Exporting conversation: $conversationId as $format');

      // Get conversation details
      final conversation = await getConversation(conversationId);
      if (conversation == null) {
        throw Exception('Conversation not found: $conversationId');
      }

      // Get all messages for the conversation
      final messages = await getMessages(conversationId);

      // Create export directory
      final exportDir = Directory('${await _getDocumentsDirectory()}/exports');
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }

      // Generate filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'chat_${conversationId}_$timestamp.$format';
      final filePath = '${exportDir.path}/$filename';

      // Export based on format
      switch (format.toLowerCase()) {
        case 'txt':
          await _exportAsText(messages, filePath, conversation);
          break;
        case 'pdf':
          await _exportAsPdf(messages, filePath, conversation);
          break;
        case 'xlsx':
          await _exportAsExcel(messages, filePath, conversation);
          break;
        default:
          throw Exception('Unsupported export format: $format');
      }

      print('💾 MessageStorageService: ✅ Conversation exported to: $filePath');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to export conversation: $e');
      rethrow;
    }
  }

  /// Export as text file
  Future<void> _exportAsText(List<Message> messages, String filePath,
      ChatConversation conversation) async {
    final file = File(filePath);
    final buffer = StringBuffer();

    // Header
    buffer.writeln(
        'Chat Export - ${conversation.recipientName ?? conversation.id}');
    buffer.writeln('Exported on: ${DateTime.now().toString()}');
    buffer.writeln('Total messages: ${messages.length}');
    buffer.writeln('=' * 50);
    buffer.writeln();

    // Messages
    for (final message in messages) {
      final timestamp = message.timestamp.toLocal().toString();
      final sender = message.isFromCurrentUser(_getCurrentUserId())
          ? 'You'
          : (conversation.recipientName ?? 'Unknown');
      final content = _getMessageContent(message);

      buffer.writeln('[$timestamp] $sender:');
      buffer.writeln(content);
      buffer.writeln();
    }

    await file.writeAsString(buffer.toString());
  }

  /// Export as PDF
  Future<void> _exportAsPdf(List<Message> messages, String filePath,
      ChatConversation conversation) async {
    // This would require a PDF library like pdf or pdfx
    // For now, we'll create a simple text-based PDF-like structure
    final file = File(filePath);
    final buffer = StringBuffer();

    // Simple PDF-like header
    buffer.writeln('%PDF-1.4');
    buffer.writeln('1 0 obj');
    buffer.writeln('<< /Type /Catalog /Pages 2 0 R >>');
    buffer.writeln('endobj');
    buffer.writeln();

    // Content
    buffer.writeln(
        'Chat Export - ${conversation.recipientName ?? conversation.id}');
    buffer.writeln('Exported on: ${DateTime.now().toString()}');
    buffer.writeln('Total messages: ${messages.length}');

    for (final message in messages) {
      final timestamp = message.timestamp.toLocal().toString();
      final sender = message.isFromCurrentUser(_getCurrentUserId())
          ? 'You'
          : (conversation.recipientName ?? 'Unknown');
      final content = _getMessageContent(message);

      buffer.writeln('[$timestamp] $sender: $content');
    }

    await file.writeAsString(buffer.toString());
  }

  /// Export as Excel
  Future<void> _exportAsExcel(List<Message> messages, String filePath,
      ChatConversation conversation) async {
    // This would require an Excel library like excel
    // For now, we'll create a CSV-like structure
    final file = File(filePath);
    final buffer = StringBuffer();

    // Header
    buffer.writeln('Timestamp,Sender,Message Type,Content,Status');
    buffer.writeln();

    // Messages
    for (final message in messages) {
      final timestamp = message.timestamp.toLocal().toString();
      final sender = message.isFromCurrentUser(_getCurrentUserId())
          ? 'You'
          : (conversation.recipientName ?? 'Unknown');
      final messageType = message.type.name;
      final content =
          _getMessageContent(message).replaceAll(',', ';'); // Escape commas
      final status = message.status.name;

      buffer.writeln('$timestamp,$sender,$messageType,$content,$status');
    }

    await file.writeAsString(buffer.toString());
  }

  /// Get message content for export
  String _getMessageContent(Message message) {
    switch (message.type) {
      case MessageType.text:
        return message.content['text'] ?? 'Text message';
      case MessageType.voice:
        return '[Voice Message]';
      case MessageType.video:
        return '[Video Message]';
      case MessageType.image:
        return '[Image]';
      case MessageType.document:
        return '[Document]';
      case MessageType.location:
        return '[Location]';
      case MessageType.contact:
        return '[Contact]';
      case MessageType.emoticon:
        return '[Emoticon]';
      case MessageType.reply:
        return '[Reply] ${message.content['text'] ?? 'Reply message'}';
      case MessageType.system:
        return '[System] ${message.content['text'] ?? 'System message'}';
      default:
        return '[Unknown Message Type]';
    }
  }

  /// Clean up orphaned media files
  Future<void> _cleanupOrphanedMediaFiles() async {
    try {
      if (_mediaDirectory == null || _thumbnailsDirectory == null) return;

      // Get all media files from database
      final List<Map<String, dynamic>> mediaFiles =
          await _database!.query('media_messages');
      final validFilePaths =
          mediaFiles.map((m) => m['file_path'] as String).toSet();
      final validThumbnailPaths = mediaFiles
          .map((m) => m['thumbnail_path'] as String?)
          .where((p) => p != null)
          .toSet();

      // Check media directory
      if (await _mediaDirectory!.exists()) {
        await for (final entity in _mediaDirectory!.list(recursive: true)) {
          if (entity is File && !validFilePaths.contains(entity.path)) {
            await entity.delete();
            print(
                '💾 MessageStorageService: Deleted orphaned media file: ${entity.path}');
          }
        }
      }

      // Check thumbnails directory
      if (await _thumbnailsDirectory!.exists()) {
        await for (final entity
            in _thumbnailsDirectory!.list(recursive: true)) {
          if (entity is File && !validThumbnailPaths.contains(entity.path)) {
            await entity.delete();
            print(
                '💾 MessageStorageService: Deleted orphaned thumbnail: ${entity.path}');
          }
        }
      }
    } catch (e) {
      print(
          '💾 MessageStorageService: ❌ Failed to cleanup orphaned media files: $e');
    }
  }

  /// Clear database and force recreation
  Future<void> clearDatabase() async {
    try {
      if (_database != null) {
        await _database!.close();
        _database = null;
      }

      final documentsDirectory = await getApplicationDocumentsDirectory();
      final databasePath =
          path.join(documentsDirectory.path, 'chat_database.db');
      final databaseFile = File(databasePath);

      if (await databaseFile.exists()) {
        await databaseFile.delete();
        print('💾 MessageStorageService: ✅ Database file deleted');
      }

      // Reinitialize the database
      await initialize();
      print('💾 MessageStorageService: ✅ Database recreated');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to clear database: $e');
      rethrow;
    }
  }

  /// Force database recreation with proper schema
  Future<void> forceRecreateDatabase() async {
    try {
      print(
          '💾 MessageStorageService: 🔄 Force recreating database with proper schema...');

      // Close and clear current database
      if (_database != null) {
        await _database!.close();
        _database = null;
      }

      // Delete database file
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final databasePath =
          path.join(documentsDirectory.path, 'chat_database.db');
      final databaseFile = File(databasePath);

      if (await databaseFile.exists()) {
        await databaseFile.delete();
        print('💾 MessageStorageService: ✅ Database file deleted');
      }

      // Reinitialize with proper schema
      await initialize();

      // Verify schema is correct
      if (await isDatabaseReady()) {
        print(
            '💾 MessageStorageService: ✅ Database recreated with correct schema');
      } else {
        print(
            '💾 MessageStorageService: ❌ Database schema still not ready after recreation');
      }
    } catch (e) {
      print(
          '💾 MessageStorageService: ❌ Failed to force recreate database: $e');
      rethrow;
    }
  }

  /// Close database connection
  Future<void> close() async {
    try {
      if (_database != null) {
        await _database!.close();
        _database = null;
      }
      print('💾 MessageStorageService: ✅ Database connection closed');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to close database: $e');
    }
  }

  /// Create a message object with the correct type
  static Message createMessage({
    required String id,
    required String conversationId,
    required String senderId,
    required String recipientId,
    required Map<String, dynamic> content,
    required String status,
    DateTime? timestamp,
  }) {
    try {
      MessageType messageType = MessageType.text;
      MessageStatus messageStatus = MessageStatus.delivered;

      // Convert status string to MessageStatus enum
      switch (status) {
        case 'sending':
          messageStatus = MessageStatus.sending;
          break;
        case 'sent':
          messageStatus = MessageStatus.sent;
          break;
        case 'delivered':
          messageStatus = MessageStatus.delivered;
          break;
        case 'read':
          messageStatus = MessageStatus.read;
          break;
        case 'failed':
          messageStatus = MessageStatus.failed;
          break;
        case 'deleted':
          messageStatus = MessageStatus.deleted;
          break;
        case 'received':
        default:
          messageStatus = MessageStatus.delivered;
          break;
      }

      return Message(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        recipientId: recipientId,
        type: messageType,
        content: content,
        status: messageStatus,
        timestamp: timestamp ?? DateTime.now(),
      );
    } catch (e) {
      print('💾 MessageStorageService: ❌ Error creating message: $e');
      throw e;
    }
  }

  /// Check if database is ready and has correct schema
  Future<bool> isDatabaseReady() async {
    try {
      if (_database == null) {
        return false;
      }

      // Check if conversations table has the required columns
      final result = await _database!.query('conversations', limit: 1);
      if (result.isNotEmpty) {
        final columns = result.first.keys.toList();
        final requiredColumns = [
          'notifications_enabled',
          'sound_enabled',
          'vibration_enabled',
          'read_receipts_enabled',
          'typing_indicators_enabled',
          'last_seen_enabled',
          'media_auto_download',
          'encrypt_media',
          'media_quality',
          'message_retention',
          'is_blocked',
          'blocked_at',
          'recipient_id',
          'recipient_name',
        ];

        final missingColumns =
            requiredColumns.where((col) => !columns.contains(col)).toList();
        if (missingColumns.isNotEmpty) {
          print(
              '💾 MessageStorageService: ⚠️ Missing columns: $missingColumns');
          return false;
        }
      }

      return true;
    } catch (e) {
      print('💾 MessageStorageService: ❌ Database readiness check failed: $e');
      return false;
    }
  }
}
