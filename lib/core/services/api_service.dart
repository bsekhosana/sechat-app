import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static String get baseUrl {
    return 'https://sechat.strapblaque.com';
  }

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<Map<String, String>> get _headers async {
    final deviceId = await _storage.read(key: 'device_id');
    print('🔍 API Service - Device ID from storage: $deviceId');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Device-ID': deviceId ?? '',
    };
  }

  static Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api$endpoint'),
        headers: await _headers,
        body: json.encode(data),
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      final headers = await _headers;
      print('🔍 API Service - GET $endpoint with headers: $headers');

      final response = await http.get(
        Uri.parse('$baseUrl/api$endpoint'),
        headers: headers,
      );

      print('🔍 API Service - Response status: ${response.statusCode}');
      print('🔍 API Service - Response body: ${response.body}');

      return _handleResponse(response);
    } catch (e) {
      print('🔍 API Service - GET Error: $e');
      throw Exception('Network error: $e');
    }
  }

  static Map<String, dynamic> _handleResponse(http.Response response) {
    final body = json.decode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    } else {
      throw Exception(body['message'] ?? 'Request failed');
    }
  }

  // User endpoints
  static Future<Map<String, dynamic>> register(Map<String, dynamic> data) {
    return post('/register', data);
  }

  static Future<Map<String, dynamic>> login(Map<String, dynamic> data) {
    return post('/login', data);
  }

  static Future<Map<String, dynamic>> searchUsers(String query) {
    print('🔍 API Service - Search request for: $query');
    return get('/search?query=$query');
  }

  static Future<Map<String, dynamic>> updateUserStatus(bool isOnline) {
    return post('/profile/status', {'is_online': isOnline});
  }

  static Future<Map<String, dynamic>> getUserProfile() {
    return get('/profile');
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

  // Message endpoints
  static Future<Map<String, dynamic>> getMessages(
    String chatId, {
    int page = 1,
    int limit = 20,
  }) {
    return get('/chats/$chatId/messages?page=$page&limit=$limit');
  }

  static Future<Map<String, dynamic>> sendMessage(
    String chatId,
    Map<String, dynamic> data,
  ) {
    return post('/chats/$chatId/messages', data);
  }

  static Future<Map<String, dynamic>> getMessage(
    String chatId,
    String messageId,
  ) {
    return get('/chats/$chatId/messages/$messageId');
  }

  static Future<Map<String, dynamic>> updateMessageStatus(
    String chatId,
    String messageId,
    Map<String, dynamic> data,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/chats/$chatId/messages/$messageId'),
      headers: await _headers,
      body: json.encode(data),
    );
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> markMessagesAsRead(String chatId) {
    return post('/chats/$chatId/messages/mark-read', {});
  }

  static Future<Map<String, dynamic>> deleteMessage(
    String chatId,
    String messageId,
  ) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/chats/$chatId/messages/$messageId'),
      headers: await _headers,
    );
    return _handleResponse(response);
  }

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
    return get('/security-questions');
  }

  static Future<Map<String, dynamic>> getUserSecurityQuestion() {
    print('🔍 API Service - Getting user security question');
    return get('/security-question');
  }

  static Future<Map<String, dynamic>> verifySecurityAnswer(String answer) {
    return post('/verify-security-answer', {'answer': answer});
  }

  static Future<Map<String, dynamic>> resetPassword(String newPassword) {
    return post('/reset-password', {'new_password': newPassword});
  }
}
