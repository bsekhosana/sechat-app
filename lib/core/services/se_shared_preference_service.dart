import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SeSharedPreferenceService {
  static final SeSharedPreferenceService _instance =
      SeSharedPreferenceService._internal();
  factory SeSharedPreferenceService() => _instance;
  SeSharedPreferenceService._internal();

  // SharedPreferences instance
  SharedPreferences? _prefs;

  // Initialize the service
  Future<void> initialize() async {
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
      print('🔍 SeSharedPreferenceService: Initialized successfully');
    }
  }

  // Generic methods for data persistence
  Future<bool> setString(String key, String value) async {
    await _ensureInitialized();
    final result = await _prefs!.setString(key, value);
    print(
        '🔍 SeSharedPreferenceService: Set string for key "$key": ${result ? 'success' : 'failed'}');
    return result;
  }

  Future<String?> getString(String key) async {
    await _ensureInitialized();
    final value = _prefs!.getString(key);
    print(
        '🔍 SeSharedPreferenceService: Get string for key "$key": ${value != null ? 'found' : 'not found'}');
    return value;
  }

  Future<bool> setBool(String key, bool value) async {
    await _ensureInitialized();
    final result = await _prefs!.setBool(key, value);
    print(
        '🔍 SeSharedPreferenceService: Set bool for key "$key": ${result ? 'success' : 'failed'}');
    return result;
  }

  Future<bool?> getBool(String key) async {
    await _ensureInitialized();
    final value = _prefs!.getBool(key);
    print(
        '🔍 SeSharedPreferenceService: Get bool for key "$key": ${value != null ? 'found' : 'not found'}');
    return value;
  }

  Future<bool> setInt(String key, int value) async {
    await _ensureInitialized();
    final result = await _prefs!.setInt(key, value);
    print(
        '🔍 SeSharedPreferenceService: Set int for key "$key": ${result ? 'success' : 'failed'}');
    return result;
  }

  Future<int?> getInt(String key) async {
    await _ensureInitialized();
    final value = _prefs!.getInt(key);
    print(
        '🔍 SeSharedPreferenceService: Get int for key "$key": ${value != null ? 'found' : 'not found'}');
    return value;
  }

  Future<bool> setDouble(String key, double value) async {
    await _ensureInitialized();
    final result = await _prefs!.setDouble(key, value);
    print(
        '🔍 SeSharedPreferenceService: Set double for key "$key": ${result ? 'success' : 'failed'}');
    return result;
  }

  Future<double?> getDouble(String key) async {
    await _ensureInitialized();
    final value = _prefs!.getDouble(key);
    print(
        '🔍 SeSharedPreferenceService: Get double for key "$key": ${value != null ? 'found' : 'not found'}');
    return value;
  }

  Future<bool> setStringList(String key, List<String> value) async {
    await _ensureInitialized();
    final result = await _prefs!.setStringList(key, value);
    print(
        '🔍 SeSharedPreferenceService: Set string list for key "$key": ${result ? 'success' : 'failed'}');
    return result;
  }

  Future<List<String>?> getStringList(String key) async {
    await _ensureInitialized();
    final value = _prefs!.getStringList(key);
    print(
        '🔍 SeSharedPreferenceService: Get string list for key "$key": ${value != null ? 'found (${value.length} items)' : 'not found'}');
    return value;
  }

  // Generic JSON methods
  Future<bool> setJson(String key, Map<String, dynamic> data) async {
    try {
      final jsonString = jsonEncode(data);
      final result = await setString(key, jsonString);
      print(
          '🔍 SeSharedPreferenceService: Set JSON for key "$key": ${result ? 'success' : 'failed'}');
      return result;
    } catch (e) {
      print(
          '🔍 SeSharedPreferenceService: Error setting JSON for key "$key": $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getJson(String key) async {
    try {
      final jsonString = await getString(key);
      if (jsonString != null) {
        final data = jsonDecode(jsonString) as Map<String, dynamic>;
        print('🔍 SeSharedPreferenceService: Get JSON for key "$key": found');
        return data;
      }
      print('🔍 SeSharedPreferenceService: Get JSON for key "$key": not found');
      return null;
    } catch (e) {
      print(
          '🔍 SeSharedPreferenceService: Error getting JSON for key "$key": $e');
      return null;
    }
  }

  // Generic list methods
  Future<bool> setJsonList(
      String key, List<Map<String, dynamic>> dataList) async {
    try {
      final jsonString = jsonEncode(dataList);
      final result = await setString(key, jsonString);
      print(
          '🔍 SeSharedPreferenceService: Set JSON list for key "$key": ${result ? 'success' : 'failed'} (${dataList.length} items)');
      return result;
    } catch (e) {
      print(
          '🔍 SeSharedPreferenceService: Error setting JSON list for key "$key": $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>?> getJsonList(String key) async {
    try {
      final jsonString = await getString(key);
      if (jsonString != null) {
        final dataList = jsonDecode(jsonString) as List;
        final result = dataList.cast<Map<String, dynamic>>();
        print(
            '🔍 SeSharedPreferenceService: Get JSON list for key "$key": found (${result.length} items)');
        return result;
      }
      print(
          '🔍 SeSharedPreferenceService: Get JSON list for key "$key": not found');
      return null;
    } catch (e) {
      print(
          '🔍 SeSharedPreferenceService: Error getting JSON list for key "$key": $e');
      return null;
    }
  }

  // Remove methods
  Future<bool> remove(String key) async {
    await _ensureInitialized();
    final result = await _prefs!.remove(key);
    print(
        '🔍 SeSharedPreferenceService: Remove key "$key": ${result ? 'success' : 'failed'}');
    return result;
  }

  Future<bool> removeMultiple(List<String> keys) async {
    await _ensureInitialized();
    bool allSuccess = true;
    for (final key in keys) {
      final result = await _prefs!.remove(key);
      if (!result) allSuccess = false;
    }
    print(
        '🔍 SeSharedPreferenceService: Remove multiple keys: ${allSuccess ? 'all successful' : 'some failed'}');
    return allSuccess;
  }

  // Clear all data
  Future<bool> clear() async {
    await _ensureInitialized();
    final result = await _prefs!.clear();
    print(
        '🔍 SeSharedPreferenceService: Clear all data: ${result ? 'success' : 'failed'}');
    return result;
  }

  // Check if key exists
  Future<bool> containsKey(String key) async {
    await _ensureInitialized();
    final exists = _prefs!.containsKey(key);
    print('🔍 SeSharedPreferenceService: Contains key "$key": $exists');
    return exists;
  }

  // Get all keys
  Future<Set<String>> getKeys() async {
    await _ensureInitialized();
    final keys = _prefs!.getKeys();
    print(
        '🔍 SeSharedPreferenceService: Get all keys: ${keys.length} keys found');
    return keys;
  }

  // Get all data for debugging
  Future<Map<String, dynamic>> getAllData() async {
    await _ensureInitialized();
    final keys = _prefs!.getKeys();
    final data = <String, dynamic>{};

    for (final key in keys) {
      final value = _prefs!.get(key);
      data[key] = value;
    }

    print('🔍 SeSharedPreferenceService: Get all data: ${data.length} entries');
    return data;
  }

  // Ensure service is initialized
  Future<void> _ensureInitialized() async {
    if (_prefs == null) {
      await initialize();
    }
  }

  // Validate data integrity
  Future<Map<String, dynamic>> validateDataIntegrity() async {
    await _ensureInitialized();
    final keys = _prefs!.getKeys();
    final validation = <String, dynamic>{
      'totalKeys': keys.length,
      'keys': keys.toList(),
      'hasData': keys.isNotEmpty,
    };

    // Check for common data types
    validation['hasSessionData'] =
        keys.any((key) => key.startsWith('se_session'));
    validation['hasChatData'] = keys.any((key) => key.startsWith('se_chat'));
    validation['hasInvitationData'] =
        keys.any((key) => key.startsWith('se_invitation'));
    validation['hasMessageData'] =
        keys.any((key) => key.startsWith('se_message'));

    print(
        '🔍 SeSharedPreferenceService: Data integrity validation: $validation');
    return validation;
  }

  // Backup all data
  Future<Map<String, dynamic>> backupAllData() async {
    await _ensureInitialized();
    final keys = _prefs!.getKeys();
    final backup = <String, dynamic>{};

    for (final key in keys) {
      final value = _prefs!.get(key);
      backup[key] = value;
    }

    final backupData = {
      'timestamp': DateTime.now().toIso8601String(),
      'totalEntries': backup.length,
      'data': backup,
    };

    print(
        '🔍 SeSharedPreferenceService: Backup created with ${backup.length} entries');
    return backupData;
  }

  // Restore data from backup
  Future<bool> restoreFromBackup(Map<String, dynamic> backupData) async {
    try {
      await _ensureInitialized();
      final data = backupData['data'] as Map<String, dynamic>;

      for (final entry in data.entries) {
        final key = entry.key;
        final value = entry.value;

        if (value is String) {
          await setString(key, value);
        } else if (value is bool) {
          await setBool(key, value);
        } else if (value is int) {
          await setInt(key, value);
        } else if (value is double) {
          await setDouble(key, value);
        } else if (value is List) {
          await setStringList(key, value.cast<String>());
        }
      }

      print(
          '🔍 SeSharedPreferenceService: Restore completed with ${data.length} entries');
      return true;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error restoring from backup: $e');
      return false;
    }
  }
}
