import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:sechat_app//../core/utils/logger.dart';

/// Database service for storing key pairs locally
class KeyPairsDatabaseService {
  static final KeyPairsDatabaseService _instance =
      KeyPairsDatabaseService._internal();
  factory KeyPairsDatabaseService() => _instance;
  KeyPairsDatabaseService._internal();

  Database? _database;
  static const String _tableName = 'key_pairs';

  /// Get database instance
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize database
  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'sechat_key_pairs.db');

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
        userId TEXT NOT NULL,
        keyType TEXT NOT NULL,
        keyData TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        isActive INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Create indexes for better performance
    await db.execute('''
      CREATE INDEX idx_key_pairs_user_id ON $_tableName (userId)
    ''');

    await db.execute('''
      CREATE INDEX idx_key_pairs_key_type ON $_tableName (keyType)
    ''');

    await db.execute('''
      CREATE INDEX idx_key_pairs_active ON $_tableName (isActive)
    ''');

    Logger.success(' KeyPairsDatabaseService:  Database table created');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle future database schema changes here
    Logger.info(
        ' KeyPairsDatabaseService:  Database upgraded from $oldVersion to $newVersion');
  }

  /// Store a key pair
  Future<void> storeKeyPair({
    required String userId,
    required String keyType,
    required String keyData,
  }) async {
    try {
      final db = await database;
      final now = DateTime.now().millisecondsSinceEpoch;

      // First, deactivate any existing keys of the same type for this user
      await db.update(
        _tableName,
        {'isActive': 0, 'updatedAt': now},
        where: 'userId = ? AND keyType = ?',
        whereArgs: [userId, keyType],
      );

      // Insert the new key
      await db.insert(
        _tableName,
        {
          'id': '${userId}_${keyType}_${now}',
          'userId': userId,
          'keyType': keyType,
          'keyData': keyData,
          'createdAt': now,
          'updatedAt': now,
          'isActive': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      Logger.success(
          ' KeyPairsDatabaseService:  Stored $keyType key for user: $userId');
    } catch (e) {
      Logger.error(' KeyPairsDatabaseService:  Error storing key pair: $e');
      rethrow;
    }
  }

  /// Get a key pair
  Future<String?> getKeyPair({
    required String userId,
    required String keyType,
  }) async {
    try {
      final db = await database;

      final result = await db.query(
        _tableName,
        columns: ['keyData'],
        where: 'userId = ? AND keyType = ? AND isActive = 1',
        whereArgs: [userId, keyType],
        orderBy: 'createdAt DESC',
        limit: 1,
      );

      if (result.isNotEmpty) {
        final keyData = result.first['keyData'] as String;
        Logger.success(
            ' KeyPairsDatabaseService:  Retrieved $keyType key for user: $userId');
        return keyData;
      } else {
        Logger.error(
            ' KeyPairsDatabaseService:  No $keyType key found for user: $userId');
        return null;
      }
    } catch (e) {
      Logger.error(' KeyPairsDatabaseService:  Error getting key pair: $e');
      return null;
    }
  }

  /// Get all key pairs for a user
  Future<Map<String, String>> getAllKeyPairs(String userId) async {
    try {
      final db = await database;

      final result = await db.query(
        _tableName,
        columns: ['keyType', 'keyData'],
        where: 'userId = ? AND isActive = 1',
        whereArgs: [userId],
        orderBy: 'createdAt DESC',
      );

      final keyPairs = <String, String>{};
      for (final row in result) {
        final keyType = row['keyType'] as String;
        final keyData = row['keyData'] as String;
        keyPairs[keyType] = keyData;
      }

      Logger.success(
          ' KeyPairsDatabaseService:  Retrieved ${keyPairs.length} key pairs for user: $userId');
      return keyPairs;
    } catch (e) {
      Logger.error(
          ' KeyPairsDatabaseService:  Error getting all key pairs: $e');
      return {};
    }
  }

  /// Delete a key pair
  Future<void> deleteKeyPair({
    required String userId,
    required String keyType,
  }) async {
    try {
      final db = await database;

      await db.update(
        _tableName,
        {'isActive': 0, 'updatedAt': DateTime.now().millisecondsSinceEpoch},
        where: 'userId = ? AND keyType = ?',
        whereArgs: [userId, keyType],
      );

      Logger.success(
          ' KeyPairsDatabaseService:  Deleted $keyType key for user: $userId');
    } catch (e) {
      Logger.error(' KeyPairsDatabaseService:  Error deleting key pair: $e');
      rethrow;
    }
  }

  /// Delete all key pairs for a user
  Future<void> deleteAllKeyPairs(String userId) async {
    try {
      final db = await database;

      await db.update(
        _tableName,
        {'isActive': 0, 'updatedAt': DateTime.now().millisecondsSinceEpoch},
        where: 'userId = ?',
        whereArgs: [userId],
      );

      Logger.success(
          ' KeyPairsDatabaseService:  Deleted all key pairs for user: $userId');
    } catch (e) {
      Logger.error(
          ' KeyPairsDatabaseService:  Error deleting all key pairs: $e');
      rethrow;
    }
  }

  /// Check if a key pair exists
  Future<bool> hasKeyPair({
    required String userId,
    required String keyType,
  }) async {
    try {
      final db = await database;

      final result = await db.query(
        _tableName,
        columns: ['id'],
        where: 'userId = ? AND keyType = ? AND isActive = 1',
        whereArgs: [userId, keyType],
        limit: 1,
      );

      final exists = result.isNotEmpty;
      Logger.info(
          ' KeyPairsDatabaseService:  Key pair exists check - User: $userId, Type: $keyType, Exists: $exists');
      return exists;
    } catch (e) {
      Logger.error(
          ' KeyPairsDatabaseService:  Error checking key pair existence: $e');
      return false;
    }
  }

  /// Get key pair count for a user
  Future<int> getKeyPairCount(String userId) async {
    try {
      final db = await database;

      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $_tableName WHERE userId = ? AND isActive = 1',
        [userId],
      );

      final count = result.first['count'] as int;
      Logger.debug(
          ' KeyPairsDatabaseService: 📊 Key pair count for user $userId: $count');
      return count;
    } catch (e) {
      Logger.error(
          ' KeyPairsDatabaseService:  Error getting key pair count: $e');
      return 0;
    }
  }

  /// Close database connection
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      Logger.debug(' KeyPairsDatabaseService: 🔒 Database connection closed');
    }
  }
}
