import '../models/message.dart';
import 'message_storage_service.dart';
import 'chat_encryption_service.dart';
import 'message_status_tracking_service.dart';
import '/../core/utils/logger.dart';

/// Service for handling text messages only
class TextMessageService {
  static TextMessageService? _instance;
  static TextMessageService get instance =>
      _instance ??= TextMessageService._();

  final MessageStorageService _storageService = MessageStorageService.instance;
  final ChatEncryptionService _encryptionService =
      ChatEncryptionService.instance;
  final MessageStatusTrackingService _statusTrackingService =
      MessageStatusTrackingService.instance;

  TextMessageService._();

  /// Send a text message
  Future<Message?> sendTextMessage({
    required String conversationId,
    required String recipientId,
    required String text,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      Logger.debug(
          '💬 TextMessageService: Sending text message to $recipientId');

      // Validate text message
      if (!_validateTextMessage(text)) {
        throw Exception(
            'Invalid text message: Text cannot be empty or too long');
      }

      // Create message
      final message = Message(
        conversationId: conversationId,
        senderId: _getCurrentUserId(),
        recipientId: recipientId,
        type: MessageType.text,
        content: {
          'text': text.trim(),
          'length': text.trim().length,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
        replyToMessageId: replyToMessageId,
        metadata: metadata,
        status: MessageStatus.sending,
      );

      // Save message to storage
      await _storageService.saveMessage(message);

      // Update conversation with new message
      await _updateConversationWithMessage(message);

      // Mark message as sent
      await _statusTrackingService.markMessageAsSent(message.id);

      Logger.success(
          '💬 TextMessageService:  Text message sent successfully: ${message.id}');
      return message;
    } catch (e) {
      Logger.error('💬 TextMessageService:  Failed to send text message: $e');
      rethrow;
    }
  }

  /// Get text messages for a conversation
  Future<List<Message>> getTextMessages(String conversationId,
      {int limit = 50, int offset = 0}) async {
    try {
      final messages = await _storageService.getMessages(conversationId,
          limit: limit, offset: offset);

      // Filter only text messages
      final textMessages = messages
          .where((message) => message.type == MessageType.text)
          .toList();

      Logger.success(
          '💬 TextMessageService:  Retrieved ${textMessages.length} text messages for conversation: $conversationId');
      return textMessages;
    } catch (e) {
      Logger.error('💬 TextMessageService:  Failed to get text messages: $e');
      rethrow;
    }
  }

  /// Update message text
  Future<void> updateMessageText(String messageId, String newText) async {
    try {
      if (!_validateTextMessage(newText)) {
        throw Exception(
            'Invalid text message: Text cannot be empty or too long');
      }

      // Get the existing message
      final messages = await _storageService.getMessages('', limit: 1000);
      final message = messages.firstWhere((m) => m.id == messageId);

      if (message.type != MessageType.text) {
        throw Exception('Cannot update text of non-text message');
      }

      // Create updated message
      final updatedMessage = message.copyWith(
        content: {
          'text': newText.trim(),
          'length': newText.trim().length,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'edited': true,
          'edited_at': DateTime.now().millisecondsSinceEpoch,
        },
      );

      // Save updated message
      await _storageService.saveMessage(updatedMessage);

      Logger.success(
          '💬 TextMessageService:  Message text updated: $messageId');
    } catch (e) {
      Logger.error('💬 TextMessageService:  Failed to update message text: $e');
      rethrow;
    }
  }

  /// Delete a text message
  Future<void> deleteTextMessage(String messageId) async {
    try {
      await _storageService.deleteMessage(messageId);
      Logger.success(
          '💬 TextMessageService:  Text message deleted: $messageId');
    } catch (e) {
      Logger.error('💬 TextMessageService:  Failed to delete text message: $e');
      rethrow;
    }
  }

  /// Validate text message
  bool _validateTextMessage(String text) {
    if (text.trim().isEmpty) return false;
    if (text.trim().length > 1000) return false; // Max 1000 characters
    return true;
  }

  /// Get current user ID (placeholder - should be implemented based on your auth system)
  String _getCurrentUserId() {
    // TODO: Implement based on your authentication system
    return 'current_user_id';
  }

  /// Update conversation with new message
  Future<void> _updateConversationWithMessage(Message message) async {
    try {
      // Get existing conversation
      final conversations = await _storageService.getConversations();
      final conversation = conversations.firstWhere(
        (c) => c.id == message.conversationId,
        orElse: () => throw Exception(
            'Conversation not found: ${message.conversationId}'),
      );

      // Update conversation
      final updatedConversation = conversation.copyWith(
        updatedAt: DateTime.now(),
        lastMessageAt: message.timestamp,
        lastMessageId: message.id,
        lastMessagePreview: message.previewText,
        lastMessageType: message.type,
        unreadCount: conversation.unreadCount + 1,
      );

      // Save updated conversation
      await _storageService.saveConversation(updatedConversation);

      Logger.success(
          '💬 TextMessageService:  Conversation updated with new message');
    } catch (e) {
      Logger.error('💬 TextMessageService:  Failed to update conversation: $e');
      rethrow;
    }
  }
}
