import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SeSharedPreferenceService {
  static final SeSharedPreferenceService _instance =
      SeSharedPreferenceService._internal();
  factory SeSharedPreferenceService() => _instance;
  SeSharedPreferenceService._internal();

  // SharedPreferences instance
  SharedPreferences? _prefs;
  bool _isInitializing = false;

  // Initialize the service
  Future<void> initialize() async {
    if (_prefs != null) return;
    if (_isInitializing) return;
    
    _isInitializing = true;
    try {
      _prefs = await SharedPreferences.getInstance();
      print('🔍 SeSharedPreferenceService: Initialized successfully');
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error initializing: $e');
    } finally {
      _isInitializing = false;
    }
  }

  // Generic methods for data persistence
  Future<bool> setString(String key, String value) async {
    try {
      await _ensureInitialized();
      final result = await _prefs!.setString(key, value);
      return result;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error setting string for key "$key": $e');
      return false;
    }
  }

  Future<String?> getString(String key) async {
    try {
      await _ensureInitialized();
      return _prefs!.getString(key);
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error getting string for key "$key": $e');
      return null;
    }
  }

  Future<bool> setBool(String key, bool value) async {
    try {
      await _ensureInitialized();
      final result = await _prefs!.setBool(key, value);
      return result;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error setting bool for key "$key": $e');
      return false;
    }
  }

  Future<bool?> getBool(String key) async {
    try {
      await _ensureInitialized();
      return _prefs!.getBool(key);
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error getting bool for key "$key": $e');
      return null;
    }
  }

  Future<bool> setInt(String key, int value) async {
    try {
      await _ensureInitialized();
      final result = await _prefs!.setInt(key, value);
      return result;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error setting int for key "$key": $e');
      return false;
    }
  }

  Future<int?> getInt(String key) async {
    try {
      await _ensureInitialized();
      return _prefs!.getInt(key);
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error getting int for key "$key": $e');
      return null;
    }
  }

  Future<bool> setDouble(String key, double value) async {
    try {
      await _ensureInitialized();
      final result = await _prefs!.setDouble(key, value);
      return result;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error setting double for key "$key": $e');
      return false;
    }
  }

  Future<double?> getDouble(String key) async {
    try {
      await _ensureInitialized();
      return _prefs!.getDouble(key);
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error getting double for key "$key": $e');
      return null;
    }
  }

  Future<bool> setStringList(String key, List<String> value) async {
    try {
      await _ensureInitialized();
      final result = await _prefs!.setStringList(key, value);
      return result;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error setting string list for key "$key": $e');
      return false;
    }
  }

  Future<List<String>?> getStringList(String key) async {
    try {
      await _ensureInitialized();
      return _prefs!.getStringList(key);
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error getting string list for key "$key": $e');
      return null;
    }
  }

  // Generic JSON methods
  Future<bool> setJson(String key, Map<String, dynamic> data) async {
    try {
      final jsonString = jsonEncode(data);
      final result = await setString(key, jsonString);
      return result;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error setting JSON for key "$key": $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getJson(String key) async {
    try {
      final jsonString = await getString(key);
      if (jsonString != null) {
        final data = jsonDecode(jsonString) as Map<String, dynamic>;
        return data;
      }
      return null;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error getting JSON for key "$key": $e');
      return null;
    }
  }

  // Generic list methods
  Future<bool> setJsonList(
      String key, List<Map<String, dynamic>> dataList) async {
    try {
      final jsonString = jsonEncode(dataList);
      final result = await setString(key, jsonString);
      return result;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error setting JSON list for key "$key": $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>?> getJsonList(String key) async {
    try {
      final jsonString = await getString(key);
      if (jsonString != null) {
        final dataList = jsonDecode(jsonString) as List;
        final result = dataList.cast<Map<String, dynamic>>();
        return result;
      }
      return null;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error getting JSON list for key "$key": $e');
      return null;
    }
  }

  // Remove methods
  Future<bool> remove(String key) async {
    try {
      await _ensureInitialized();
      final result = await _prefs!.remove(key);
      return result;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error removing key "$key": $e');
      return false;
    }
  }

  Future<bool> removeMultiple(List<String> keys) async {
    try {
      await _ensureInitialized();
      bool allSuccess = true;
      for (final key in keys) {
        final result = await _prefs!.remove(key);
        if (!result) allSuccess = false;
      }
      return allSuccess;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error removing multiple keys: $e');
      return false;
    }
  }

  // Clear all data
  Future<bool> clear() async {
    try {
      await _ensureInitialized();
      final result = await _prefs!.clear();
      return result;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error clearing all data: $e');
      return false;
    }
  }

  // Check if key exists
  Future<bool> containsKey(String key) async {
    try {
      await _ensureInitialized();
      final exists = _prefs!.containsKey(key);
      return exists;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error checking key "$key": $e');
      return false;
    }
  }

  // Get all keys
  Future<Set<String>> getKeys() async {
    try {
      await _ensureInitialized();
      final keys = _prefs!.getKeys();
      return keys;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error getting all keys: $e');
      return <String>{};
    }
  }

  // Get all data for debugging
  Future<Map<String, dynamic>> getAllData() async {
    try {
      await _ensureInitialized();
      final keys = _prefs!.getKeys();
      final data = <String, dynamic>{};

      for (final key in keys) {
        final value = _prefs!.get(key);
        data[key] = value;
      }

      return data;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error getting all data: $e');
      return <String, dynamic>{};
    }
  }

  // Ensure service is initialized
  Future<void> _ensureInitialized() async {
    if (_prefs == null) {
      await initialize();
    }
  }

  // Validate data integrity
  Future<Map<String, dynamic>> validateDataIntegrity() async {
    try {
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

      return validation;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error validating data integrity: $e');
      return <String, dynamic>{};
    }
  }

  // Backup all data
  Future<Map<String, dynamic>> backupAllData() async {
    try {
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

      return backupData;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error creating backup: $e');
      return <String, dynamic>{};
    }
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

      return true;
    } catch (e) {
      print('🔍 SeSharedPreferenceService: Error restoring from backup: $e');
      return false;
    }
  }
}
