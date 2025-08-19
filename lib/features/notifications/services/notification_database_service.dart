import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sechat_app/features/notifications/models/socket_notification.dart';

/// Database service for storing socket notifications
class NotificationDatabaseService {
  static final NotificationDatabaseService _instance =
      NotificationDatabaseService._internal();
  factory NotificationDatabaseService() => _instance;
  NotificationDatabaseService._internal();

  static Database? _database;
  static const String _tableName = 'socket_notifications';

  /// Get database instance
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize database
  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'socket_notifications.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        is_read INTEGER NOT NULL DEFAULT 0,
        metadata TEXT,
        sender_id TEXT,
        recipient_id TEXT,
        conversation_id TEXT,
        message_id TEXT,
        priority TEXT NOT NULL DEFAULT 'normal',
        icon TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_type ON $_tableName (type)');
    await db.execute('CREATE INDEX idx_timestamp ON $_tableName (timestamp)');
    await db.execute('CREATE INDEX idx_is_read ON $_tableName (is_read)');
    await db.execute('CREATE INDEX idx_sender_id ON $_tableName (sender_id)');
    await db.execute(
        'CREATE INDEX idx_conversation_id ON $_tableName (conversation_id)');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add icon column to existing table
      try {
        await db.execute('ALTER TABLE $_tableName ADD COLUMN icon TEXT');
        print(
            '📱 NotificationDatabaseService: ✅ Added icon column to existing table');
      } catch (e) {
        print(
            '📱 NotificationDatabaseService: ℹ️ Icon column may already exist: $e');
      }
    }
  }

  /// Add a new notification
  Future<String> addNotification(SocketNotification notification) async {
    final db = await database;

    try {
      await db.insert(
        _tableName,
        {
          ...notification.toJson(),
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      print(
          '📱 NotificationDatabaseService: ✅ Added notification: ${notification.title}');
      return notification.id;
    } catch (e) {
      print('📱 NotificationDatabaseService: ❌ Failed to add notification: $e');
      rethrow;
    }
  }

  /// Get all notifications with optional filters
  Future<List<SocketNotification>> getNotifications({
    String? type,
    String? senderId,
    String? conversationId,
    bool? isRead,
    int? limit,
    int? offset,
    String? orderBy = 'timestamp',
    bool descending = true,
  }) async {
    final db = await database;

    try {
      String whereClause = '1=1';
      List<Object> whereArgs = [];

      if (type != null) {
        whereClause += ' AND type = ?';
        whereArgs.add(type);
      }

      if (senderId != null) {
        whereClause += ' AND sender_id = ?';
        whereArgs.add(senderId);
      }

      if (conversationId != null) {
        whereClause += ' AND conversation_id = ?';
        whereArgs.add(conversationId);
      }

      if (isRead != null) {
        whereClause += ' AND is_read = ?';
        whereArgs.add(isRead ? 1 : 0);
      }

      final orderDirection = descending ? 'DESC' : 'ASC';
      final limitClause = limit != null ? 'LIMIT $limit' : '';
      final offsetClause = offset != null ? 'OFFSET $offset' : '';

      final query = '''
        SELECT * FROM $_tableName 
        WHERE $whereClause 
        ORDER BY $orderBy $orderDirection 
        $limitClause $offsetClause
      '''
          .trim();

      final results = await db.rawQuery(query, whereArgs);

      return results.map((row) => _notificationFromRow(row)).toList();
    } catch (e) {
      print(
          '📱 NotificationDatabaseService: ❌ Failed to get notifications: $e');
      return [];
    }
  }

  /// Get unread notifications count
  Future<int> getUnreadCount() async {
    final db = await database;

    try {
      final result = await db.rawQuery(
          'SELECT COUNT(*) as count FROM $_tableName WHERE is_read = 0');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      print('📱 NotificationDatabaseService: ❌ Failed to get unread count: $e');
      return 0;
    }
  }

  /// Get notifications by type
  Future<List<SocketNotification>> getNotificationsByType(String type,
      {int? limit}) async {
    return await getNotifications(type: type, limit: limit);
  }

  /// Get notifications for a specific conversation
  Future<List<SocketNotification>> getConversationNotifications(
      String conversationId,
      {int? limit}) async {
    return await getNotifications(conversationId: conversationId, limit: limit);
  }

  /// Get notifications from a specific sender
  Future<List<SocketNotification>> getSenderNotifications(String senderId,
      {int? limit}) async {
    return await getNotifications(senderId: senderId, limit: limit);
  }

  /// Mark notification as read
  Future<bool> markAsRead(String notificationId) async {
    final db = await database;

    try {
      final result = await db.update(
        _tableName,
        {'is_read': 1},
        where: 'id = ?',
        whereArgs: [notificationId],
      );

      if (result > 0) {
        print(
            '📱 NotificationDatabaseService: ✅ Marked notification as read: $notificationId');
        return true;
      }
      return false;
    } catch (e) {
      print(
          '📱 NotificationDatabaseService: ❌ Failed to mark notification as read: $e');
      return false;
    }
  }

  /// Mark all notifications as read
  Future<bool> markAllAsRead() async {
    final db = await database;

    try {
      final result = await db.update(
        _tableName,
        {'is_read': 1},
        where: 'is_read = 0',
      );

      print(
          '📱 NotificationDatabaseService: ✅ Marked $result notifications as read');
      return true;
    } catch (e) {
      print(
          '📱 NotificationDatabaseService: ❌ Failed to mark all notifications as read: $e');
      return false;
    }
  }

  /// Mark conversation notifications as read
  Future<bool> markConversationAsRead(String conversationId) async {
    final db = await database;

    try {
      final result = await db.update(
        _tableName,
        {'is_read': 1},
        where: 'conversation_id = ? AND is_read = 0',
        whereArgs: [conversationId],
      );

      print(
          '📱 NotificationDatabaseService: ✅ Marked $result conversation notifications as read');
      return true;
    } catch (e) {
      print(
          '📱 NotificationDatabaseService: ❌ Failed to mark conversation as read: $e');
      return false;
    }
  }

  /// Delete a notification
  Future<bool> deleteNotification(String notificationId) async {
    final db = await database;

    try {
      final result = await db.delete(
        _tableName,
        where: 'id = ?',
        whereArgs: [notificationId],
      );

      if (result > 0) {
        print(
            '📱 NotificationDatabaseService: ✅ Deleted notification: $notificationId');
        return true;
      }
      return false;
    } catch (e) {
      print(
          '📱 NotificationDatabaseService: ❌ Failed to delete notification: $e');
      return false;
    }
  }

  /// Delete expired notifications (older than 30 days)
  Future<int> deleteExpiredNotifications() async {
    final db = await database;

    try {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final result = await db.delete(
        _tableName,
        where: 'timestamp < ?',
        whereArgs: [thirtyDaysAgo.toIso8601String()],
      );

      print(
          '📱 NotificationDatabaseService: ✅ Deleted $result expired notifications');
      return result;
    } catch (e) {
      print(
          '📱 NotificationDatabaseService: ❌ Failed to delete expired notifications: $e');
      return 0;
    }
  }

  /// Clear all notifications
  Future<bool> clearAllNotifications() async {
    final db = await database;

    try {
      final result = await db.delete(_tableName);
      print('📱 NotificationDatabaseService: ✅ Cleared all notifications');
      return true;
    } catch (e) {
      print(
          '📱 NotificationDatabaseService: ❌ Failed to clear all notifications: $e');
      return false;
    }
  }

  /// Get notification statistics
  Future<Map<String, dynamic>> getStatistics() async {
    final db = await database;

    try {
      final totalResult =
          await db.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
      final unreadResult = await db.rawQuery(
          'SELECT COUNT(*) as count FROM $_tableName WHERE is_read = 0');
      final typeResult = await db.rawQuery(
          'SELECT type, COUNT(*) as count FROM $_tableName GROUP BY type');

      final total = Sqflite.firstIntValue(totalResult) ?? 0;
      final unread = Sqflite.firstIntValue(unreadResult) ?? 0;

      final typeCounts = <String, int>{};
      for (final row in typeResult) {
        typeCounts[row['type'] as String] = row['count'] as int;
      }

      return {
        'total': total,
        'unread': unread,
        'read': total - unread,
        'type_counts': typeCounts,
      };
    } catch (e) {
      print('📱 NotificationDatabaseService: ❌ Failed to get statistics: $e');
      return {
        'total': 0,
        'unread': 0,
        'read': 0,
        'type_counts': {},
      };
    }
  }

  /// Convert database row to SocketNotification
  SocketNotification _notificationFromRow(Map<String, dynamic> row) {
    return SocketNotification(
      id: row['id'] as String,
      type: row['type'] as String,
      title: row['title'] as String,
      message: row['message'] as String,
      timestamp: DateTime.parse(row['timestamp'] as String),
      isRead: (row['is_read'] as int) == 1,
      metadata: row['metadata'] != null
          ? jsonDecode(row['metadata'] as String) as Map<String, dynamic>
          : null,
      senderId: row['sender_id'] as String?,
      recipientId: row['recipient_id'] as String?,
      conversationId: row['conversation_id'] as String?,
      messageId: row['message_id'] as String?,
      priority: NotificationPriority.values.firstWhere(
        (e) => e.name == row['priority'],
        orElse: () => NotificationPriority.normal,
      ),
    );
  }

  /// Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
