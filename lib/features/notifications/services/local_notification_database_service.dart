import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import '../models/local_notification_item.dart';
import 'package:sechat_app//../core/utils/logger.dart';

/// Database service for local notification items
class LocalNotificationDatabaseService {
  static final LocalNotificationDatabaseService _instance =
      LocalNotificationDatabaseService._internal();
  factory LocalNotificationDatabaseService() => _instance;
  LocalNotificationDatabaseService._internal();

  Database? _database;
  static const String _tableName = 'local_notification_items';

  /// Get database instance
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize database
  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'sechat_local_notifications.db');

    return await openDatabase(
      path,
      version: 1,
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
        icon TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        status TEXT NOT NULL,
        direction TEXT NOT NULL,
        senderId TEXT,
        recipientId TEXT,
        conversationId TEXT,
        metadata TEXT,
        date TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_type ON $_tableName(type)');
    await db.execute('CREATE INDEX idx_status ON $_tableName(status)');
    await db.execute('CREATE INDEX idx_date ON $_tableName(date)');
    await db.execute('CREATE INDEX idx_senderId ON $_tableName(senderId)');
    await db
        .execute('CREATE INDEX idx_recipientId ON $_tableName(recipientId)');

    Logger.success(
        '📱 LocalNotificationDatabaseService:  Database created successfully');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle future database schema changes here
    Logger.info(
        '📱 LocalNotificationDatabaseService:  Database upgraded from $oldVersion to $newVersion');
  }

  /// Insert a new notification item
  Future<void> insertNotification(LocalNotificationItem notification) async {
    final db = await database;
    await db.insert(
      _tableName,
      notification.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    Logger.success(
        '📱 LocalNotificationDatabaseService:  Notification inserted: ${notification.id}');
  }

  /// Get all notifications ordered by date (newest first)
  Future<List<LocalNotificationItem>> getAllNotifications() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _tableName,
        orderBy: 'date DESC',
      );

      return List.generate(maps.length, (i) {
        try {
          return LocalNotificationItem.fromMap(maps[i]);
        } catch (e) {
          Logger.error(
              ' LocalNotificationDatabaseService: Error parsing notification ${maps[i]['id']}: $e');
          // Return a default notification if parsing fails
          return LocalNotificationItem(
            type: 'error',
            icon: 'bell',
            title: 'Error Loading Notification',
            status: 'read',
            direction: 'incoming',
            date: DateTime.now(),
          );
        }
      });
    } catch (e) {
      Logger.error(
          ' LocalNotificationDatabaseService: Error getting notifications: $e');
      rethrow;
    }
  }

  /// Get notifications by type
  Future<List<LocalNotificationItem>> getNotificationsByType(
      String type) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'date DESC',
    );

    return List.generate(maps.length, (i) {
      return LocalNotificationItem.fromMap(maps[i]);
    });
  }

  /// Get unread notifications count
  Future<int> getUnreadCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName WHERE status = ?',
      ['unread'],
    );
    return result.first['count'] as int? ?? 0;
  }

  /// Get unread notifications
  Future<List<LocalNotificationItem>> getUnreadNotifications() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'status = ?',
      whereArgs: ['unread'],
      orderBy: 'date DESC',
    );

    return List.generate(maps.length, (i) {
      return LocalNotificationItem.fromMap(maps[i]);
    });
  }

  /// Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    final db = await database;
    await db.update(
      _tableName,
      {'status': 'read'},
      where: 'id = ?',
      whereArgs: [notificationId],
    );
    Logger.success(
        '📱 LocalNotificationDatabaseService:  Notification marked as read: $notificationId');
  }

  /// Mark notification as archived
  Future<void> markAsArchived(String notificationId) async {
    final db = await database;
    await db.update(
      _tableName,
      {'status': 'archived'},
      where: 'id = ?',
      whereArgs: [notificationId],
    );
    Logger.success(
        '📱 LocalNotificationDatabaseService:  Notification archived: $notificationId');
  }

  /// Delete notification by ID
  Future<void> deleteNotification(String notificationId) async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [notificationId],
    );
    Logger.success(
        '📱 LocalNotificationDatabaseService:  Notification deleted: $notificationId');
  }

  /// Clear all notifications
  Future<void> clearAllNotifications() async {
    final db = await database;
    await db.delete(_tableName);
    Logger.success(
        '📱 LocalNotificationDatabaseService:  All notifications cleared');
  }

  /// Reset database (delete and recreate)
  Future<void> resetDatabase() async {
    try {
      final db = await database;
      await db.close();
      _database = null;

      // Delete the database file
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'sechat_local_notifications.db');
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        Logger.success(
            '📱 LocalNotificationDatabaseService:  Database file deleted');
      }

      // Reinitialize
      await database;
      Logger.success(
          '📱 LocalNotificationDatabaseService:  Database reset successfully');
    } catch (e) {
      Logger.error(
          '📱 LocalNotificationDatabaseService:  Failed to reset database: $e');
      rethrow;
    }
  }

  /// Clear old notifications (older than specified days)
  Future<void> clearOldNotifications(int daysOld) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
    final cutoffDateString = cutoffDate.toIso8601String();

    await db.delete(
      _tableName,
      where: 'date < ?',
      whereArgs: [cutoffDateString],
    );

    final deletedCount = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName WHERE date < ?',
      [cutoffDateString],
    );

    Logger.debug(
        '📱 LocalNotificationDatabaseService: ✅ Old notifications cleared (older than $daysOld days)');
  }

  /// Check if welcome notification exists for user
  Future<bool> hasWelcomeNotification(String userId) async {
    final db = await database;
    final result = await db.query(
      _tableName,
      where: 'type = ? AND recipientId = ?',
      whereArgs: ['welcome', userId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Get notification by ID
  Future<LocalNotificationItem?> getNotificationById(
      String notificationId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'id = ?',
      whereArgs: [notificationId],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return LocalNotificationItem.fromMap(maps.first);
  }

  /// Close database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      Logger.success('📱 LocalNotificationDatabaseService:  Database closed');
    }
  }
}
