import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'user_existence_guard.dart';
import 'package:sechat_app//../core/utils/logger.dart';

class ApiService {
  static String get baseUrl {
    return 'https://sechat.strapblaque.com';
  }

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<Map<String, String>> get _headers async {
    final deviceId = await _storage.read(key: 'device_id');
    Logger.info(' API Service - Device ID from storage: $deviceId');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Device-ID': deviceId ?? '',
    };
  }

  // User existence guard - checks if user still exists in database
  static Future<bool> _checkUserExists() async {
    try {
      final userId = await _storage.read(key: 'user_id');
      if (userId == null) {
        Logger.info(' API Service - No user ID found, user not logged in');
        return false;
      }

      Logger.info(
          ' API Service - Checking if user $userId still exists in database');

      final response = await http.get(
        Uri.parse('$baseUrl/api/users/$userId/exists'),
        headers: await _headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final exists = data['exists'] ?? false;
        Logger.info(' API Service - User existence check result: $exists');
        return exists;
      } else {
        Logger.info(
            ' API Service - User existence check failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      Logger.info(' API Service - User existence check error: $e');
      return false;
    }
  }

  // Guard wrapper for all API calls
  static Future<Map<String, dynamic>> _guardedApiCall(
    Future<Map<String, dynamic>> Function() apiCall,
    String operation,
  ) async {
    try {
      // Check if user exists before making API call
      final userExists = await _checkUserExists();
      if (!userExists) {
        Logger.info(' API Service - User no longer exists, triggering logout');
        await UserExistenceGuard.instance.handleUserNotFound();
        throw Exception('User account no longer exists');
      }

      // Proceed with API call
      return await apiCall();
    } catch (e) {
      if (e.toString().contains('User account no longer exists')) {
        rethrow; // Re-throw user existence errors
      }

      // Check for 401/403 errors that might indicate user issues
      if (e.toString().contains('401') || e.toString().contains('403')) {
        Logger.info(
            ' API Service - Authentication error detected, checking user existence');
        final userExists = await _checkUserExists();
        if (!userExists) {
          Logger.info(
              ' API Service - User no longer exists after auth error, triggering logout');
          await UserExistenceGuard.instance.handleUserNotFound();
          throw Exception('User account no longer exists');
        }
      }

      rethrow;
    }
  }

  static Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    return _guardedApiCall(() async {
      final response = await http.post(
        Uri.parse('$baseUrl/api$endpoint'),
        headers: await _headers,
        body: json.encode(data),
      );

      return _handleResponse(response);
    }, 'POST $endpoint');
  }

  static Future<Map<String, dynamic>> get(String endpoint) async {
    return _guardedApiCall(() async {
      final headers = await _headers;
      Logger.info(' API Service - GET $endpoint with headers: $headers');

      final response = await http.get(
        Uri.parse('$baseUrl/api$endpoint'),
        headers: headers,
      );

      Logger.info(' API Service - Response status: ${response.statusCode}');
      Logger.info(' API Service - Response body: ${response.body}');

      return _handleResponse(response);
    }, 'GET $endpoint');
  }

  static Map<String, dynamic> _handleResponse(http.Response response) {
    final body = json.decode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    } else {
      throw Exception(body['message'] ?? 'Request failed');
    }
  }

  // Unguarded API calls for endpoints that don't require authentication
  static Future<Map<String, dynamic>> _unguardedPost(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api$endpoint'),
      headers: await _headers,
      body: json.encode(data),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> _unguardedGet(String endpoint) async {
    final headers = await _headers;
    Logger.info(
        ' API Service - Unguarded GET $endpoint with headers: $headers');

    final response = await http.get(
      Uri.parse('$baseUrl/api$endpoint'),
      headers: headers,
    );

    Logger.info(
        ' API Service - Unguarded response status: ${response.statusCode}');
    Logger.info(' API Service - Unguarded response body: ${response.body}');

    return _handleResponse(response);
  }

  // User management endpoints
  static Future<Map<String, dynamic>> blockUser(String userId) {
    return post('/users/block', {'user_id': userId});
  }

  static Future<Map<String, dynamic>> removeUserChats(String userId) {
    return post('/users/remove-chats', {'user_id': userId});
  }

  // User endpoints
  static Future<Map<String, dynamic>> register(Map<String, dynamic> data) {
    return _unguardedPost('/register', data);
  }

  static Future<Map<String, dynamic>> login(Map<String, dynamic> data) {
    return _unguardedPost('/login', data);
  }

  static Future<Map<String, dynamic>> searchUsers(String query) {
    Logger.info(' API Service - Search request for: $query');
    return _unguardedGet('/search?query=$query');
  }

  static Future<Map<String, dynamic>> updateUserStatus(bool isOnline) {
    return post('/profile/status', {'is_online': isOnline});
  }

  static Future<Map<String, dynamic>> getUserProfile() {
    return get('/profile');
  }

  static Future<Map<String, dynamic>> getUsersOnlineStatus(
      List<String> userIds) {
    return post('/users/online-status', {'user_ids': userIds});
  }

  // Chat endpoints
  static Future<Map<String, dynamic>> getChats() {
    return get('/chats');
  }

  static Future<Map<String, dynamic>> createChat(Map<String, dynamic> data) {
    return post('/chats', data);
  }

  static Future<Map<String, dynamic>> getChat(String chatId) {
    return get('/chats/$chatId');
  }

  static Future<Map<String, dynamic>> updateChat(
    String chatId,
    Map<String, dynamic> data,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/chats/$chatId'),
      headers: await _headers,
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> deleteChat(String chatId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/chats/$chatId'),
      headers: await _headers,
    );
    return _handleResponse(response);
  }

  // Invitation endpoints
  static Future<Map<String, dynamic>> getInvitations() {
    return get('/invitations');
  }

  static Future<Map<String, dynamic>> sendInvitation(
    Map<String, dynamic> data,
  ) {
    return post('/invitations', data);
  }

  static Future<Map<String, dynamic>> getInvitation(String invitationId) {
    return get('/invitations/$invitationId');
  }

  static Future<Map<String, dynamic>> acceptInvitation(String invitationId) {
    return post('/invitations/$invitationId/accept', {});
  }

  static Future<Map<String, dynamic>> declineInvitation(String invitationId) {
    return post('/invitations/$invitationId/decline', {});
  }

  static Future<Map<String, dynamic>> deleteInvitation(
    String invitationId,
  ) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/invitations/$invitationId'),
      headers: await _headers,
    );
    return _handleResponse(response);
  }

  // Message endpoints - REMOVED: Messages are now stored locally only
  // static Future<Map<String, dynamic>> getMessages(
  //   String chatId, {
  //   int page = 1,
  //   int limit = 20,
  // }) {
  //   return get('/chats/$chatId/messages?page=$page&limit=$limit');
  // }

  // static Future<Map<String, dynamic>> sendMessage(
  //   String chatId,
  //   Map<String, dynamic> data,
  // ) {
  //   return post('/chats/$chatId/messages', data);
  // }

  // static Future<Map<String, dynamic>> getMessage(
  //   String chatId,
  //   String messageId,
  // ) {
  //   return get('/chats/$chatId/messages/$messageId');
  // }

  // static Future<Map<String, dynamic>> updateMessageStatus(
  //   String chatId,
  //   String messageId,
  //   Map<String, dynamic> data,
  // ) async {
  //   final response = await http.put(
  //     Uri.parse('$baseUrl/api/chats/$chatId/messages/$messageId'),
  //     headers: await _headers,
  //     body: json.encode(data),
  //   );
  //   return _handleResponse(response);
  // }

  // static Future<Map<String, dynamic>> markMessagesAsRead(String chatId) {
  //   return post('/chats/$chatId/messages/mark-read', {});
  // }

  // static Future<Map<String, dynamic>> deleteMessage(
  //   String chatId,
  //   String messageId,
  // ) async {
  //   final response = await http.delete(
  //     Uri.parse('$baseUrl/api/chats/$chatId/messages/$messageId'),
  //     headers: await _headers,
  //   );
  //   return _handleResponse(response);
  // }

  // Profile management endpoints
  static Future<Map<String, dynamic>> clearAllChats() async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/chats/clear-all'),
      headers: await _headers,
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> deleteAccount() async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/profile/delete'),
      headers: await _headers,
    );
    return _handleResponse(response);
  }

  // Security Questions & Password Reset endpoints
  static Future<Map<String, dynamic>> getSecurityQuestions() {
    return _unguardedGet('/security-questions');
  }

  static Future<Map<String, dynamic>> getUserSecurityQuestion() {
    Logger.info(' API Service - Getting user security question');
    return _guardedApiCall(() async {
      final response = await http.get(
        Uri.parse('$baseUrl/api/security-question'),
        headers: await _headers,
      );
      return _handleResponse(response);
    }, 'GET /security-question');
  }

  static Future<Map<String, dynamic>> verifySecurityAnswer(String answer) {
    return _guardedApiCall(() async {
      final response = await http.post(
        Uri.parse('$baseUrl/api/verify-security-answer'),
        headers: await _headers,
        body: json.encode({'answer': answer}),
      );
      return _handleResponse(response);
    }, 'POST /verify-security-answer');
  }

  static Future<Map<String, dynamic>> resetPassword(String newPassword) {
    return _unguardedPost('/reset-password', {'new_password': newPassword});
  }

  // Test method to simulate user deletion (for testing user existence guard)
  static Future<Map<String, dynamic>> testDeleteUser(String userId) async {
    return _guardedApiCall(() async {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/users/$userId/test-delete'),
        headers: await _headers,
      );

      return _handleResponse(response);
    }, 'DELETE /users/$userId/test-delete');
  }
}
