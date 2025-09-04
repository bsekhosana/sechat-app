import 'package:flutter/foundation.dart';
import '../providers/unified_chat_provider.dart';
import '../providers/chat_list_provider.dart';
import '../models/message.dart';
import '../services/message_status_tracking_service.dart';
import '../models/message_status.dart' as msg_status;
import '/../core/utils/logger.dart';

/// Service to handle integration between UnifiedChatProvider and existing systems
class UnifiedChatIntegrationService {
  static final UnifiedChatIntegrationService _instance =
      UnifiedChatIntegrationService._internal();
  factory UnifiedChatIntegrationService() => _instance;
  UnifiedChatIntegrationService._internal();

  final Map<String, UnifiedChatProvider> _activeProviders = {};
  ChatListProvider? _chatListProvider;

  /// Register an active chat provider
  void registerActiveProvider(
      String conversationId, UnifiedChatProvider provider) {
    _activeProviders[conversationId] = provider;
    Logger.success(
        'UnifiedChatIntegrationService:  Registered provider for conversation: $conversationId');
  }

  /// Unregister an active chat provider
  void unregisterActiveProvider(String conversationId) {
    _activeProviders.remove(conversationId);
    Logger.error(
        'UnifiedChatIntegrationService:  Unregistered provider for conversation: $conversationId');
  }

  /// Set the chat list provider for integration
  void setChatListProvider(ChatListProvider? provider) {
    _chatListProvider = provider;
    Logger.success(
        'UnifiedChatIntegrationService: ${provider != null ? '' : '❌'} Chat list provider ${provider != null ? 'set' : 'cleared'}');
  }

  /// Handle new message arrival
  void handleNewMessageArrival({
    required String messageId,
    required String senderId,
    required String content,
    required String conversationId,
    required DateTime timestamp,
    required MessageType messageType,
  }) {
    // Update chat list if available
    if (_chatListProvider != null) {
      _chatListProvider!.handleNewMessageArrival(
        messageId: messageId,
        senderId: senderId,
        content: content,
        conversationId: conversationId,
        timestamp: timestamp,
        messageType: messageType,
      );
    }

    // Notify active provider if it's for the current conversation
    final provider = _activeProviders[conversationId];
    if (provider != null) {
      Logger.info(
          'UnifiedChatIntegrationService:  Notifying active provider for conversation: $conversationId');
      // The provider will handle the message through its own socket callbacks
    }
  }

  /// Handle message status updates
  void handleMessageStatusUpdate(MessageStatusUpdate update) {
    // Find the provider that has this message
    for (final provider in _activeProviders.values) {
      final hasMessage =
          provider.messages.any((msg) => msg.id == update.messageId);
      if (hasMessage) {
        provider.handleMessageStatusUpdate(update);
        Logger.success(
            'UnifiedChatIntegrationService:  Status update forwarded to provider');
        break;
      }
    }
  }

  /// Handle typing indicator updates
  void handleTypingIndicatorUpdate({
    required String senderId,
    required bool isTyping,
    required String conversationId,
  }) {
    final provider = _activeProviders[conversationId];
    if (provider != null && provider.currentRecipientId == senderId) {
      // The provider will handle typing through its socket callbacks
      Logger.debug(
          'UnifiedChatIntegrationService:  Typing indicator for active conversation: $conversationId');
    }
  }

  /// Handle presence updates
  void handlePresenceUpdate({
    required String userId,
    required bool isOnline,
    DateTime? lastSeen,
  }) {
    // Update all active providers that have this user as recipient
    for (final provider in _activeProviders.values) {
      if (provider.currentRecipientId == userId) {
        provider.updateRecipientPresence(isOnline, lastSeen);
        Logger.debug(
            'UnifiedChatIntegrationService: 🟢 Presence update for active conversation');
      }
    }

    // Update chat list if available
    if (_chatListProvider != null) {
      // The chat list provider will handle presence updates through its own system
    }
  }

  /// Get active provider for a conversation
  UnifiedChatProvider? getActiveProvider(String conversationId) {
    return _activeProviders[conversationId];
  }

  /// Check if a conversation has an active provider
  bool hasActiveProvider(String conversationId) {
    return _activeProviders.containsKey(conversationId);
  }

  /// Get all active conversation IDs
  List<String> getActiveConversationIds() {
    return _activeProviders.keys.toList();
  }

  /// Clear all active providers (for cleanup)
  void clearAllProviders() {
    _activeProviders.clear();
    Logger.info('UnifiedChatIntegrationService:  Cleared all active providers');
  }
}
