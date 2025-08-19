import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/message.dart';
import '../models/chat_conversation.dart';
import '../../../core/services/se_shared_preference_service.dart';

/// Simplified service for managing local storage of text-based chat messages and conversations
class MessageStorageService {
  static MessageStorageService? _instance;
  static MessageStorageService get instance =>
      _instance ??= MessageStorageService._();

  Database? _database;
  final SeSharedPreferenceService _prefsService = SeSharedPreferenceService();

  MessageStorageService._();

  /// Initialize the storage service
  Future<void> initialize() async {
    try {
      print('💾 MessageStorageService: Initializing storage service');

      // Initialize database
      await _initializeDatabase();

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
        version: 1,
        onCreate: _createDatabaseTables,
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
          last_seen_enabled INTEGER DEFAULT 1
        )
      ''');

      // Messages table (simplified for text messages only)
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
          FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE
        )
      ''');

      // Create indexes for better performance
      await db.execute(
          'CREATE INDEX idx_messages_conversation_id ON messages (conversation_id)');
      await db.execute(
          'CREATE INDEX idx_messages_timestamp ON messages (timestamp)');
      await db.execute(
          'CREATE INDEX idx_messages_sender_id ON messages (sender_id)');

      print('💾 MessageStorageService: ✅ Database tables created');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to create database tables: $e');
      rethrow;
    }
  }

  /// Save a conversation
  Future<void> saveConversation(ChatConversation conversation) async {
    if (_database == null) {
      throw Exception('Database not initialized');
    }

    try {
      await _database!.insert(
        'conversations',
        {
          'id': conversation.id,
          'participant1_id': conversation.participant1Id,
          'participant2_id': conversation.participant2Id,
          'display_name': conversation.displayName,
          'created_at': conversation.createdAt.toIso8601String(),
          'updated_at': conversation.updatedAt.toIso8601String(),
          'last_message_at': conversation.lastMessageAt?.toIso8601String(),
          'last_message_id': conversation.lastMessageId,
          'last_message_preview': conversation.lastMessagePreview,
          'last_message_type': conversation.lastMessageType?.name,
          'unread_count': conversation.unreadCount,
          'is_archived': conversation.isArchived ? 1 : 0,
          'is_muted': conversation.isMuted ? 1 : 0,
          'is_pinned': conversation.isPinned ? 1 : 0,
          'metadata': conversation.metadata?.toString(),
          'last_seen': conversation.lastSeen?.toIso8601String(),
          'is_typing': conversation.isTyping == true ? 1 : 0,
          'typing_started_at': conversation.typingStartedAt?.toIso8601String(),
          'notifications_enabled':
              conversation.notificationsEnabled == true ? 1 : 0,
          'sound_enabled': conversation.soundEnabled == true ? 1 : 0,
          'vibration_enabled': conversation.vibrationEnabled == true ? 1 : 0,
          'read_receipts_enabled':
              conversation.readReceiptsEnabled == true ? 1 : 0,
          'typing_indicators_enabled':
              conversation.typingIndicatorsEnabled == true ? 1 : 0,
          'last_seen_enabled': conversation.lastSeenEnabled == true ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      print(
          '💾 MessageStorageService: ✅ Conversation saved: ${conversation.id}');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to save conversation: $e');
      rethrow;
    }
  }

  /// Save a message
  Future<void> saveMessage(Message message) async {
    if (_database == null) {
      throw Exception('Database not initialized');
    }

    try {
      await _database!.insert(
        'messages',
        {
          'id': message.id,
          'conversation_id': message.conversationId,
          'sender_id': message.senderId,
          'recipient_id': message.recipientId,
          'type': message.type.name,
          'content': message.content.toString(),
          'status': message.status.name,
          'timestamp': message.timestamp.toIso8601String(),
          'delivered_at': message.deliveredAt?.toIso8601String(),
          'read_at': message.readAt?.toIso8601String(),
          'deleted_at': message.deletedAt?.toIso8601String(),
          'reply_to_message_id': message.replyToMessageId,
          'metadata': message.metadata?.toString(),
          'is_encrypted': message.isEncrypted ? 1 : 0,
          'checksum': message.checksum,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      print('💾 MessageStorageService: ✅ Message saved: ${message.id}');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to save message: $e');
      rethrow;
    }
  }

  /// Get messages for a conversation
  Future<List<Message>> getMessages(String conversationId,
      {int limit = 50, int offset = 0}) async {
    if (_database == null) {
      throw Exception('Database not initialized');
    }

    try {
      final List<Map<String, dynamic>> maps = await _database!.query(
        'messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        orderBy: 'timestamp DESC',
        limit: limit,
        offset: offset,
      );

      final messages = maps.map((map) => _mapToMessage(map)).toList();
      print(
          '💾 MessageStorageService: ✅ Retrieved ${messages.length} messages for conversation: $conversationId');
      return messages;
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to get messages: $e');
      rethrow;
    }
  }

  /// Get conversations
  Future<List<ChatConversation>> getConversations() async {
    if (_database == null) {
      throw Exception('Database not initialized');
    }

    try {
      final List<Map<String, dynamic>> maps = await _database!.query(
        'conversations',
        orderBy: 'updated_at DESC',
      );

      final conversations = maps.map((map) => _mapToConversation(map)).toList();
      print(
          '💾 MessageStorageService: ✅ Retrieved ${conversations.length} conversations');
      return conversations;
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to get conversations: $e');
      rethrow;
    }
  }

  /// Get conversation by ID
  Future<ChatConversation?> getConversation(String conversationId) async {
    if (_database == null) {
      throw Exception('Database not initialized');
    }

    try {
      final List<Map<String, dynamic>> maps = await _database!.query(
        'conversations',
        where: 'id = ?',
        whereArgs: [conversationId],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        final conversation = _mapToConversation(maps.first);
        print(
            '💾 MessageStorageService: ✅ Retrieved conversation: $conversationId');
        return conversation;
      }
      return null;
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to get conversation: $e');
      rethrow;
    }
  }

  /// Get user conversations
  Future<List<ChatConversation>> getUserConversations(String userId) async {
    if (_database == null) {
      throw Exception('Database not initialized');
    }

    try {
      final List<Map<String, dynamic>> maps = await _database!.query(
        'conversations',
        where: 'participant1_id = ? OR participant2_id = ?',
        whereArgs: [userId, userId],
        orderBy: 'updated_at DESC',
      );

      final conversations = maps.map((map) => _mapToConversation(map)).toList();
      print(
          '💾 MessageStorageService: ✅ Retrieved ${conversations.length} conversations for user: $userId');
      return conversations;
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to get user conversations: $e');
      rethrow;
    }
  }

  /// Delete conversation
  Future<void> deleteConversation(String conversationId) async {
    if (_database == null) {
      throw Exception('Database not initialized');
    }

    try {
      // Delete all messages in the conversation first
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

      print(
          '💾 MessageStorageService: ✅ Conversation deleted: $conversationId');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to delete conversation: $e');
      rethrow;
    }
  }

  /// Delete ALL chat conversations and messages permanently
  Future<void> deleteAllChats() async {
    if (_database == null) {
      throw Exception('Database not initialized');
    }

    try {
      print('💾 MessageStorageService: 🗑️ Starting complete chat deletion...');

      // Delete all messages first
      final messagesDeleted = await _database!.delete('messages');
      print('💾 MessageStorageService: ✅ Deleted $messagesDeleted messages');

      // Delete all conversations
      final conversationsDeleted = await _database!.delete('conversations');
      print(
          '💾 MessageStorageService: ✅ Deleted $conversationsDeleted conversations');

      print('💾 MessageStorageService: 🗑️ All chats permanently deleted');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to delete all chats: $e');
      rethrow;
    }
  }

  /// Force recreate database (for testing/debugging)
  Future<void> forceRecreateDatabase() async {
    try {
      if (_database != null) {
        await _database!.close();
        _database = null;
      }

      final documentsDirectory = await getApplicationDocumentsDirectory();
      final databasePath =
          path.join(documentsDirectory.path, 'chat_database.db');

      // Delete existing database file
      final databaseFile = File(databasePath);
      if (await databaseFile.exists()) {
        await databaseFile.delete();
      }

      // Reinitialize
      await initialize();
      print('💾 MessageStorageService: ✅ Database recreated');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to recreate database: $e');
      rethrow;
    }
  }

  /// Update message status
  Future<void> updateMessageStatus(
      String messageId, MessageStatus status) async {
    if (_database == null) {
      throw Exception('Database not initialized');
    }

    try {
      await _database!.update(
        'messages',
        {'status': status.name},
        where: 'id = ?',
        whereArgs: [messageId],
      );

      print(
          '💾 MessageStorageService: ✅ Message status updated: $messageId -> ${status.name}');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to update message status: $e');
      rethrow;
    }
  }

  /// Delete a message
  Future<void> deleteMessage(String messageId) async {
    if (_database == null) {
      throw Exception('Database not initialized');
    }

    try {
      await _database!.delete(
        'messages',
        where: 'id = ?',
        whereArgs: [messageId],
      );

      print('💾 MessageStorageService: ✅ Message deleted: $messageId');
    } catch (e) {
      print('💾 MessageStorageService: ❌ Failed to delete message: $e');
      rethrow;
    }
  }

  /// Close the database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      print('💾 MessageStorageService: ✅ Database closed');
    }
  }

  /// Helper method to map database row to Message object
  Message _mapToMessage(Map<String, dynamic> map) {
    return Message(
      id: map['id'],
      conversationId: map['conversation_id'],
      senderId: map['sender_id'],
      recipientId: map['recipient_id'],
      type: MessageType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => MessageType.text,
      ),
      content: _parseContent(map['content']),
      status: MessageStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MessageStatus.sending,
      ),
      timestamp: DateTime.parse(map['timestamp']),
      deliveredAt: map['delivered_at'] != null
          ? DateTime.parse(map['delivered_at'])
          : null,
      readAt: map['read_at'] != null ? DateTime.parse(map['read_at']) : null,
      deletedAt:
          map['deleted_at'] != null ? DateTime.parse(map['deleted_at']) : null,
      replyToMessageId: map['reply_to_message_id'],
      metadata:
          map['metadata'] != null ? _parseMetadata(map['metadata']) : null,
      isEncrypted: map['is_encrypted'] == 1,
      checksum: map['checksum'],
    );
  }

  /// Helper method to map database row to ChatConversation object
  ChatConversation _mapToConversation(Map<String, dynamic> map) {
    return ChatConversation(
      id: map['id'] as String,
      participant1Id: map['participant1_id'] as String,
      participant2Id: map['participant2_id'] as String,
      displayName: map['display_name'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      lastMessageAt: map['last_message_at'] != null
          ? DateTime.parse(map['last_message_at'] as String)
          : null,
      lastMessageId: map['last_message_id'] as String?,
      lastMessagePreview: map['last_message_preview'] as String?,
      lastMessageType: map['last_message_type'] != null
          ? MessageType.values.firstWhere(
              (e) => e.name == (map['last_message_type'] as String? ?? ''),
              orElse: () => MessageType.text,
            )
          : null,
      unreadCount: (map['unread_count'] as int?) ?? 0,
      isArchived: (map['is_archived'] as int?) == 1,
      isMuted: (map['is_muted'] as int?) == 1,
      isPinned: (map['is_pinned'] as int?) == 1,
      metadata:
          map['metadata'] != null ? _parseMetadata(map['metadata']) : null,
      lastSeen: map['last_seen'] != null
          ? DateTime.parse(map['last_seen'] as String)
          : null,
      isTyping: (map['is_typing'] as int?) == 1,
      typingStartedAt: map['typing_started_at'] != null
          ? DateTime.parse(map['typing_started_at'] as String)
          : null,
      notificationsEnabled: (map['notifications_enabled'] as int?) == 1,
      soundEnabled: (map['sound_enabled'] as int?) == 1,
      vibrationEnabled: (map['vibration_enabled'] as int?) == 1,
      readReceiptsEnabled: (map['read_receipts_enabled'] as int?) == 1,
      typingIndicatorsEnabled: (map['typing_indicators_enabled'] as int?) == 1,
      lastSeenEnabled: (map['last_seen_enabled'] as int?) == 1,
    );
  }

  /// Helper method to parse content from database
  Map<String, dynamic> _parseContent(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) return value;
    if (value is String) {
      try {
        // Try to parse as string representation of Map
        if (value.startsWith('{') && value.endsWith('}')) {
          // Simple parsing for basic content structure
          final content = <String, dynamic>{};
          final pairs = value.substring(1, value.length - 1).split(',');
          for (final pair in pairs) {
            final keyValue = pair.split(':');
            if (keyValue.length == 2) {
              final key = keyValue[0].trim().replaceAll('"', '');
              final valueStr = keyValue[1].trim().replaceAll('"', '');
              content[key] = valueStr;
            }
          }
          return content;
        }
        return {'text': value};
      } catch (e) {
        print('💾 MessageStorageService: ❌ Failed to parse content: $e');
        return {'text': value};
      }
    }
    return {};
  }

  /// Helper method to parse metadata from database
  Map<String, dynamic>? _parseMetadata(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is String) {
      try {
        // Simple parsing for basic metadata structure
        if (value.startsWith('{') && value.endsWith('}')) {
          final metadata = <String, dynamic>{};
          final pairs = value.substring(1, value.length - 1).split(',');
          for (final pair in pairs) {
            final keyValue = pair.split(':');
            if (keyValue.length == 2) {
              final key = keyValue[0].trim().replaceAll('"', '');
              final valueStr = keyValue[1].trim().replaceAll('"', '');
              metadata[key] = valueStr;
            }
          }
          return metadata;
        }
        return null;
      } catch (e) {
        print('💾 MessageStorageService: ❌ Failed to parse metadata: $e');
        return null;
      }
    }
    return null;
  }
}
