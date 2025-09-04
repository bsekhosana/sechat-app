import '../services/unified_chat_integration_service.dart';
import '../services/message_status_tracking_service.dart';
import '../models/message.dart';
import '../models/message_status.dart' as msg_status;
import '/../core/utils/logger.dart';

/// Service to integrate unified chat system with existing socket event handling
class UnifiedChatSocketIntegration {
  static final UnifiedChatSocketIntegration _instance =
      UnifiedChatSocketIntegration._internal();
  factory UnifiedChatSocketIntegration() => _instance;
  UnifiedChatSocketIntegration._internal();

  final UnifiedChatIntegrationService _integrationService =
      UnifiedChatIntegrationService();

  /// Handle incoming message from socket (called from main.dart)
  void handleIncomingMessage({
    required String messageId,
    required String senderId,
    required String conversationId,
    required String body,
    required String senderName,
  }) {
    Logger.debug(
        'UnifiedChatSocketIntegration:  Handling incoming message: $messageId');

    // Notify integration service
    _integrationService.handleNewMessageArrival(
      messageId: messageId,
      senderId: senderId,
      content: body,
      conversationId: conversationId,
      timestamp: DateTime.now(),
      messageType: MessageType.text,
    );
  }

  /// Handle typing indicator from socket (called from main.dart)
  void handleTypingIndicator({
    required String senderId,
    required bool isTyping,
    required String conversationId,
  }) {
    Logger.debug(
        'UnifiedChatSocketIntegration:  Handling typing indicator: $senderId -> $isTyping');

    // Notify integration service
    _integrationService.handleTypingIndicatorUpdate(
      senderId: senderId,
      isTyping: isTyping,
      conversationId: conversationId,
    );
  }

  /// Handle presence update from socket (called from main.dart)
  void handlePresenceUpdate({
    required String userId,
    required bool isOnline,
    DateTime? lastSeen,
  }) {
    Logger.debug(
        'UnifiedChatSocketIntegration: 🟢 Handling presence update: $userId -> $isOnline');

    // Notify integration service
    _integrationService.handlePresenceUpdate(
      userId: userId,
      isOnline: isOnline,
      lastSeen: lastSeen,
    );
  }

  /// Handle message status update from socket (called from main.dart)
  void handleMessageStatusUpdate({
    required String messageId,
    required msg_status.MessageDeliveryStatus status,
    required String senderId,
  }) {
    Logger.debug(
        'UnifiedChatSocketIntegration: 📊 Handling message status update: $messageId -> $status');

    // Create status update object
    final statusUpdate = MessageStatusUpdate(
      messageId: messageId,
      status: status,
      timestamp: DateTime.now(),
      senderId: senderId,
    );

    // Notify integration service
    _integrationService.handleMessageStatusUpdate(statusUpdate);
  }

  /// Get integration service for direct access if needed
  UnifiedChatIntegrationService get integrationService => _integrationService;
}
