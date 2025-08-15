import 'package:uuid/uuid.dart';

import '../models/message.dart';
import '../models/chat_conversation.dart';
import 'message_storage_service.dart';
import 'chat_encryption_service.dart';
import 'message_status_tracking_service.dart';

/// Service for handling text messages, emoticons, and reply functionality
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
      print('💬 TextMessageService: Sending text message to $recipientId');

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

      print(
          '💬 TextMessageService: ✅ Text message sent successfully: ${message.id}');
      return message;
    } catch (e) {
      print('💬 TextMessageService: ❌ Failed to send text message: $e');
      rethrow;
    }
  }

  /// Send an emoticon message
  Future<Message?> sendEmoticonMessage({
    required String conversationId,
    required String recipientId,
    required String emoticon,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      print('😊 TextMessageService: Sending emoticon message to $recipientId');

      // Validate emoticon
      if (!_validateEmoticon(emoticon)) {
        throw Exception('Invalid emoticon: Must be a valid emoticon character');
      }

      // Create message
      final message = Message(
        conversationId: conversationId,
        senderId: _getCurrentUserId(),
        recipientId: recipientId,
        type: MessageType.emoticon,
        content: {
          'emoticon': emoticon,
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

      print(
          '😊 TextMessageService: ✅ Emoticon message sent successfully: ${message.id}');
      return message;
    } catch (e) {
      print('😊 TextMessageService: ❌ Failed to send emoticon message: $e');
      rethrow;
    }
  }

  /// Send a reply message
  Future<Message?> sendReplyMessage({
    required String conversationId,
    required String recipientId,
    required String text,
    required String replyToMessageId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      print('↩️ TextMessageService: Sending reply message to $recipientId');

      // Validate reply message
      if (!_validateTextMessage(text)) {
        throw Exception(
            'Invalid reply message: Text cannot be empty or too long');
      }

      // Get the message being replied to
      final replyToMessage = await _getMessageById(replyToMessageId);
      if (replyToMessage == null) {
        throw Exception('Reply target message not found');
      }

      // Create reply message
      final message = Message(
        conversationId: conversationId,
        senderId: _getCurrentUserId(),
        recipientId: recipientId,
        type: MessageType.reply,
        content: {
          'text': text.trim(),
          'length': text.trim().length,
          'reply_to_message_id': replyToMessageId,
          'reply_text': replyToMessage.previewText,
          'reply_type': replyToMessage.type.name,
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

      print(
          '↩️ TextMessageService: ✅ Reply message sent successfully: ${message.id}');
      return message;
    } catch (e) {
      print('↩️ TextMessageService: ❌ Failed to send reply message: $e');
      rethrow;
    }
  }

  /// Edit a text message
  Future<bool> editTextMessage({
    required String messageId,
    required String newText,
  }) async {
    try {
      print('✏️ TextMessageService: Editing message $messageId');

      // Get the message to edit
      final message = await _getMessageById(messageId);
      if (message == null) {
        throw Exception('Message not found');
      }

      // Check if message can be edited
      if (!_canEditMessage(message)) {
        throw Exception('Message cannot be edited');
      }

      // Validate new text
      if (!_validateTextMessage(newText)) {
        throw Exception('Invalid text: Text cannot be empty or too long');
      }

      // Create edited message
      final editedMessage = message.copyWith(
        content: {
          ...message.content,
          'text': newText.trim(),
          'length': newText.trim().length,
          'edited_at': DateTime.now().millisecondsSinceEpoch,
          'is_edited': true,
        },
      );

      // Save edited message
      await _storageService.saveMessage(editedMessage);

      // Update conversation
      await _updateConversationWithMessage(editedMessage);

      print('✏️ TextMessageService: ✅ Message edited successfully: $messageId');
      return true;
    } catch (e) {
      print('✏️ TextMessageService: ❌ Failed to edit message: $e');
      return false;
    }
  }

  /// Delete a message
  Future<bool> deleteMessage({
    required String messageId,
    required bool deleteForEveryone,
  }) async {
    try {
      print('🗑️ TextMessageService: Deleting message $messageId');

      // Get the message to delete
      final message = await _getMessageById(messageId);
      if (message == null) {
        throw Exception('Message not found');
      }

      // Check if message can be deleted
      if (!_canDeleteMessage(message)) {
        throw Exception('Message cannot be deleted');
      }

      if (deleteForEveryone) {
        // Mark message as deleted for everyone
        final deletedMessage = message.copyWith(
          status: MessageStatus.deleted,
          deletedAt: DateTime.now(),
        );

        await _storageService.saveMessage(deletedMessage);
        print(
            '🗑️ TextMessageService: ✅ Message deleted for everyone: $messageId');
      } else {
        // Mark message as deleted locally
        final deletedMessage = message.copyWith(
          status: MessageStatus.deleted,
          deletedAt: DateTime.now(),
        );

        await _storageService.saveMessage(deletedMessage);
        print('🗑️ TextMessageService: ✅ Message deleted locally: $messageId');
      }

      return true;
    } catch (e) {
      print('🗑️ TextMessageService: ❌ Failed to delete message: $e');
      return false;
    }
  }

  /// Forward a message to another conversation
  Future<Message?> forwardMessage({
    required String messageId,
    required String targetConversationId,
    required String targetRecipientId,
  }) async {
    try {
      print('↪️ TextMessageService: Forwarding message $messageId');

      // Get the message to forward
      final originalMessage = await _getMessageById(messageId);
      if (originalMessage == null) {
        throw Exception('Message not found');
      }

      // Check if message can be forwarded
      if (!_canForwardMessage(originalMessage)) {
        throw Exception('Message cannot be forwarded');
      }

      // Create forwarded message
      final forwardedMessage = Message(
        conversationId: targetConversationId,
        senderId: _getCurrentUserId(),
        recipientId: targetRecipientId,
        type: originalMessage.type,
        content: {
          ...originalMessage.content,
          'forwarded_from': originalMessage.senderId,
          'forwarded_at': DateTime.now().millisecondsSinceEpoch,
          'is_forwarded': true,
        },
        status: MessageStatus.sending,
        metadata: {
          'forwarded_message_id': messageId,
          'original_conversation_id': originalMessage.conversationId,
        },
      );

      // Save forwarded message
      await _storageService.saveMessage(forwardedMessage);

      // Update target conversation
      await _updateConversationWithMessage(forwardedMessage);

      // Mark message as sent
      await _statusTrackingService.markMessageAsSent(forwardedMessage.id);

      print(
          '↪️ TextMessageService: ✅ Message forwarded successfully: ${forwardedMessage.id}');
      return forwardedMessage;
    } catch (e) {
      print('↪️ TextMessageService: ❌ Failed to forward message: $e');
      rethrow;
    }
  }

  /// Search messages by text content
  Future<List<Message>> searchMessages({
    required String query,
    String? conversationId,
    int limit = 50,
  }) async {
    try {
      print('🔍 TextMessageService: Searching for messages with query: $query');

      final currentUserId = _getCurrentUserId();
      List<Message> results;

      if (conversationId != null) {
        // Search within specific conversation
        final messages = await _storageService
            .getConversationMessages(conversationId, limit: 1000);
        results = messages.where((message) {
          if (message.type != MessageType.text &&
              message.type != MessageType.reply) return false;
          final text = message.content['text'] as String? ?? '';
          return text.toLowerCase().contains(query.toLowerCase());
        }).toList();
      } else {
        // Search across all conversations
        results = await _storageService.searchMessages(query, currentUserId);
      }

      // Sort by timestamp (newest first)
      results.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Limit results
      if (results.length > limit) {
        results = results.take(limit).toList();
      }

      print('🔍 TextMessageService: ✅ Found ${results.length} messages');
      return results;
    } catch (e) {
      print('🔍 TextMessageService: ❌ Failed to search messages: $e');
      return [];
    }
  }

  /// Validate text message
  bool _validateTextMessage(String text) {
    if (text.trim().isEmpty) return false;
    if (text.length > 4096) return false; // Max 4096 characters
    return true;
  }

  /// Validate emoticon
  bool _validateEmoticon(String emoticon) {
    // Check if it's a valid emoticon (basic validation)
    if (emoticon.isEmpty) return false;
    if (emoticon.length > 10) return false; // Reasonable emoticon length
    return true;
  }

  /// Check if message can be edited
  bool _canEditMessage(Message message) {
    // Only text messages can be edited
    if (message.type != MessageType.text) return false;

    // Only sender can edit
    if (message.senderId != _getCurrentUserId()) return false;

    // Cannot edit deleted messages
    if (message.status == MessageStatus.deleted) return false;

    // Check time limit (e.g., 15 minutes)
    final timeLimit = DateTime.now().difference(message.timestamp);
    if (timeLimit.inMinutes > 15) return false;

    return true;
  }

  /// Check if message can be deleted
  bool _canDeleteMessage(Message message) {
    // Cannot delete deleted messages
    if (message.status == MessageStatus.deleted) return false;

    // Only sender can delete
    if (message.senderId != _getCurrentUserId()) return false;

    return true;
  }

  /// Check if message can be forwarded
  bool _canForwardMessage(Message message) {
    // Cannot forward deleted messages
    if (message.status == MessageStatus.deleted) return false;

    // Cannot forward system messages
    if (message.type == MessageType.system) return false;

    return true;
  }

  /// Update conversation with new message
  Future<void> _updateConversationWithMessage(Message message) async {
    try {
      final conversation =
          await _storageService.getConversation(message.conversationId);
      if (conversation == null) return;

      final updatedConversation = conversation.updateWithNewMessage(
        messageId: message.id,
        messagePreview: message.previewText,
        messageType: _convertToConversationMessageType(message.type),
        isFromCurrentUser: message.senderId == _getCurrentUserId(),
      );

      await _storageService.saveConversation(updatedConversation);
    } catch (e) {
      print('💬 TextMessageService: ❌ Failed to update conversation: $e');
    }
  }

  /// Get message by ID
  Future<Message?> _getMessageById(String messageId) async {
    try {
      // This will be implemented when we add message retrieval to the storage service
      // For now, return null
      return null;
    } catch (e) {
      print('💬 TextMessageService: ❌ Failed to get message: $e');
      return null;
    }
  }

  /// Get current user ID
  String _getCurrentUserId() {
    // This will be implemented when we integrate with the session service
    // For now, return a placeholder
    return 'current_user_id';
  }

  /// Convert MessageType to conversation MessageType
  MessageType _convertToConversationMessageType(MessageType type) {
    // Since we're using the same MessageType enum, just return the type directly
    return type;
  }

  /// Get supported emoticons
  List<String> getSupportedEmoticons() {
    return [
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '😂',
      '🤣',
      '😊',
      '😇',
      '🙂',
      '🙃',
      '😉',
      '😌',
      '😍',
      '🥰',
      '😘',
      '😗',
      '😙',
      '😚',
      '😋',
      '😛',
      '😝',
      '😜',
      '🤪',
      '🤨',
      '🧐',
      '🤓',
      '😎',
      '🤩',
      '🥳',
      '😏',
      '😒',
      '😞',
      '😔',
      '😟',
      '😕',
      '🙁',
      '☹️',
      '😣',
      '😖',
      '😫',
      '😩',
      '🥺',
      '😢',
      '😭',
      '😤',
      '😠',
      '😡',
      '🤬',
      '🤯',
      '😳',
      '🥵',
      '🥶',
      '😱',
      '😨',
      '😰',
      '😥',
      '😓',
      '🤗',
      '🤔',
      '🤭',
      '🤫',
      '🤥',
      '😶',
      '😐',
      '😑',
      '😯',
      '😦',
      '😧',
      '😮',
      '😲',
      '🥱',
      '😴',
      '🤤',
      '😪',
      '😵',
      '🤐',
      '🥴',
      '🤢',
      '🤮',
      '🤧',
      '😷',
      '🤒',
      '🤕',
      '🤑',
      '🤠',
      '💩',
      '👻',
      '👽',
      '🤖',
      '😈',
      '👿',
      '👹',
      '👺',
      '💀',
      '☠️',
      '👻',
      '👽',
      '🤖',
      '😺',
      '😸',
      '😹',
      '😻',
      '😼',
      '😽',
      '🙀',
      '😿',
      '😾',
      '🙈',
      '🙉',
      '🙊',
      '💌',
      '💘',
      '💝',
      '💖',
      '💗',
      '💙',
      '💚',
      '❣️',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💘',
      '💝',
      '💟',
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '🤎',
      '💔',
      '❣️',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💘',
      '💝',
      '💟',
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '🤎',
      '💔',
      '❣️',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💘',
      '💝',
      '💟',
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '🤎',
      '💔',
      '❣️',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💘',
      '💝',
      '💟',
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '🤎',
      '💔',
      '❣️',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💘',
      '💝',
      '💟',
      '❤️',
      '🧡',
      '💛',
      ' ',
    ];
  }
}
