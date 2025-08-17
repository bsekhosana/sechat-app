import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

/// Optimized Chat Database Service
/// Clean, simplified database schema for robust chat functionality
class OptimizedChatDatabaseService {
  static final OptimizedChatDatabaseService _instance =
      OptimizedChatDatabaseService._internal();
  factory OptimizedChatDatabaseService() => _instance;
  OptimizedChatDatabaseService._internal();

  Database? _database;
  static const String _databaseName = 'optimized_chat.db';
  static const int _databaseVersion = 1;

  /// Get database instance
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize database
  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    try {
      // Conversations table - simplified and focused
      await db.execute('''
        CREATE TABLE conversations (
          id TEXT PRIMARY KEY,
          participant1_id TEXT NOT NULL,
          participant2_id TEXT NOT NULL,
          display_name TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          last_message_at TEXT,
          last_message_preview TEXT,
          unread_count INTEGER DEFAULT 0,
          is_typing INTEGER DEFAULT 0,
          typing_user_id TEXT,
          is_online INTEGER DEFAULT 0,
          last_seen TEXT,
          is_pinned INTEGER DEFAULT 0
        )
      ''');

      // Messages table - clean and efficient
      await db.execute('''
        CREATE TABLE messages (
          id TEXT PRIMARY KEY,
          conversation_id TEXT NOT NULL,
          sender_id TEXT NOT NULL,
          recipient_id TEXT NOT NULL,
          content TEXT NOT NULL,
          message_type TEXT DEFAULT 'text',
          status TEXT DEFAULT 'sending',
          timestamp TEXT NOT NULL,
          delivered_at TEXT,
          read_at TEXT,
          metadata TEXT,
          FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE
        )
      ''');

      // Create indexes for optimal performance
      await db.execute(
          'CREATE INDEX idx_conversations_participants ON conversations (participant1_id, participant2_id)');
      await db.execute(
          'CREATE INDEX idx_messages_conversation_id ON messages (conversation_id)');
      await db.execute(
          'CREATE INDEX idx_messages_timestamp ON messages (timestamp)');
      await db.execute(
          'CREATE INDEX idx_messages_sender_id ON messages (sender_id)');

      print(
          '🗄️ OptimizedChatDatabaseService: ✅ Database tables created successfully');
    } catch (e) {
      print(
          '🗄️ OptimizedChatDatabaseService: ❌ Failed to create database tables: $e');
      rethrow;
    }
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // For now, we're starting fresh, so no upgrade logic needed
    print(
        '🗄️ OptimizedChatDatabaseService: 🔄 Database upgrade from $oldVersion to $newVersion');
  }

  /// Close database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  // ===== CONVERSATION OPERATIONS =====

  /// Save or update conversation
  Future<void> saveConversation(Map<String, dynamic> conversation) async {
    final db = await database;
    try {
      await db.insert(
        'conversations',
        conversation,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print(
          '🗄️ OptimizedChatDatabaseService: ✅ Conversation saved: ${conversation['id']}');
    } catch (e) {
      print(
          '🗄️ OptimizedChatDatabaseService: ❌ Failed to save conversation: $e');
      rethrow;
    }
  }

  /// Get conversation by ID
  Future<Map<String, dynamic>?> getConversation(String conversationId) async {
    final db = await database;
    try {
      final results = await db.query(
        'conversations',
        where: 'id = ?',
        whereArgs: [conversationId],
        limit: 1,
      );
      return results.isNotEmpty ? results.first : null;
    } catch (e) {
      print(
          '🗄️ OptimizedChatDatabaseService: ❌ Failed to get conversation: $e');
      return null;
    }
  }

  /// Get all conversations for a user
  Future<List<Map<String, dynamic>>> getUserConversations(String userId) async {
    final db = await database;
    try {
      final results = await db.query(
        'conversations',
        where: 'participant1_id = ? OR participant2_id = ?',
        whereArgs: [userId, userId],
        orderBy: 'last_message_at DESC, updated_at DESC',
      );
      return results;
    } catch (e) {
      print(
          '🗄️ OptimizedChatDatabaseService: ❌ Failed to get user conversations: $e');
      return [];
    }
  }

  /// Find conversation between two users
  Future<Map<String, dynamic>?> findConversationBetweenUsers(
      String user1Id, String user2Id) async {
    final db = await database;
    try {
      final results = await db.query(
        'conversations',
        where:
            '(participant1_id = ? AND participant2_id = ?) OR (participant1_id = ? AND participant2_id = ?)',
        whereArgs: [user1Id, user2Id, user2Id, user1Id],
        limit: 1,
      );
      return results.isNotEmpty ? results.first : null;
    } catch (e) {
      print(
          '🗄️ OptimizedChatDatabaseService: ❌ Failed to find conversation: $e');
      return null;
    }
  }

  /// Update conversation
  Future<void> updateConversation(
      String conversationId, Map<String, dynamic> updates) async {
    final db = await database;
    try {
      await db.update(
        'conversations',
        updates,
        where: 'id = ?',
        whereArgs: [conversationId],
      );
      print(
          '🗄️ OptimizedChatDatabaseService: ✅ Conversation updated: $conversationId');
    } catch (e) {
      print(
          '🗄️ OptimizedChatDatabaseService: ❌ Failed to update conversation: $e');
      rethrow;
    }
  }

  // ===== MESSAGE OPERATIONS =====

  /// Save message
  Future<void> saveMessage(Map<String, dynamic> message) async {
    final db = await database;
    try {
      await db.insert(
        'messages',
        message,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print(
          '🗄️ OptimizedChatDatabaseService: ✅ Message saved: ${message['id']}');
    } catch (e) {
      print('🗄️ OptimizedChatDatabaseService: ❌ Failed to save message: $e');
      rethrow;
    }
  }

  /// Get messages for a conversation
  Future<List<Map<String, dynamic>>> getConversationMessages(
      String conversationId,
      {int limit = 50,
      int offset = 0}) async {
    final db = await database;
    try {
      final results = await db.query(
        'messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        orderBy: 'timestamp DESC',
        limit: limit,
        offset: offset,
      );
      return results.reversed.toList(); // Return in chronological order
    } catch (e) {
      print(
          '🗄️ OptimizedChatDatabaseService: ❌ Failed to get conversation messages: $e');
      return [];
    }
  }

  /// Update message status
  Future<void> updateMessageStatus(String messageId, String status,
      {String? deliveredAt, String? readAt}) async {
    final db = await database;
    try {
      final updates = <String, dynamic>{
        'status': status,
        if (deliveredAt != null) 'delivered_at': deliveredAt,
        if (readAt != null) 'read_at': readAt,
      };

      await db.update(
        'messages',
        updates,
        where: 'id = ?',
        whereArgs: [messageId],
      );
      print(
          '🗄️ OptimizedChatDatabaseService: ✅ Message status updated: $messageId -> $status');
    } catch (e) {
      print(
          '🗄️ OptimizedChatDatabaseService: ❌ Failed to update message status: $e');
      rethrow;
    }
  }

  /// Get message by ID
  Future<Map<String, dynamic>?> getMessage(String messageId) async {
    final db = await database;
    try {
      final results = await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: [messageId],
        limit: 1,
      );
      return results.isNotEmpty ? results.first : null;
    } catch (e) {
      print('🗄️ OptimizedChatDatabaseService: ❌ Failed to get message: $e');
      return null;
    }
  }

  // ===== UTILITY OPERATIONS =====

  /// Clear all data (for testing/reset)
  Future<void> clearAllData() async {
    final db = await database;
    try {
      await db.delete('messages');
      await db.delete('conversations');
      print('🗄️ OptimizedChatDatabaseService: ✅ All data cleared');
    } catch (e) {
      print('🗄️ OptimizedChatDatabaseService: ❌ Failed to clear data: $e');
      rethrow;
    }
  }

  /// Get database statistics
  Future<Map<String, int>> getDatabaseStats() async {
    final db = await database;
    try {
      final conversationCount = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM conversations')) ??
          0;

      final messageCount = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM messages')) ??
          0;

      return {
        'conversations': conversationCount,
        'messages': messageCount,
      };
    } catch (e) {
      print(
          '🗄️ OptimizedChatDatabaseService: ❌ Failed to get database stats: $e');
      return {'conversations': 0, 'messages': 0};
    }
  }
}
