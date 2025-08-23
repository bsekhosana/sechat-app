import '../services/se_session_service.dart';

/// Centralized utility for generating consistent conversation IDs
/// This ensures all parts of the app use the same conversation ID format
class ConversationIdGenerator {
  /// Generate consistent conversation ID that both users will have
  /// This ensures messages appear in the same conversation for both users
  /// Updated to match server's new consistent ID format
  static String generateConsistentConversationId(
      String user1Id, String user2Id) {
    // Sort user IDs alphabetically to ensure consistency
    final sortedIds = [user1Id, user2Id]..sort();
    // Server expects conversation IDs to start with 'chat_' prefix
    return 'chat_${sortedIds[0]}_${sortedIds[1]}';
  }

  /// Generate a consistent conversation ID for the current user and a recipient
  ///
  /// [recipientId] - The recipient's user ID
  ///
  /// Returns: A consistent conversation ID that both users will have
  static String generateForCurrentUser(String recipientId) {
    final currentUserId = SeSessionService().currentSessionId ?? '';
    if (currentUserId.isEmpty) {
      throw Exception('Current user session not found');
    }
    return generateConsistentConversationId(currentUserId, recipientId);
  }

  /// Generate a key exchange conversation ID
  /// This is used for temporary communication during key exchange
  ///
  /// [recipientId] - The recipient's user ID
  ///
  /// Returns: A key exchange conversation ID
  static String generateKeyExchangeConversationId(String recipientId) {
    return 'key_exchange_$recipientId';
  }

  /// Generate a temporary conversation ID for testing/debugging
  /// This should not be used in production
  ///
  /// [prefix] - Optional prefix for the conversation ID
  ///
  /// Returns: A temporary conversation ID
  static String generateTemporaryConversationId([String prefix = 'temp']) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${prefix}_chat_$timestamp';
  }

  /// Validate if a conversation ID follows the expected format
  ///
  /// [conversationId] - The conversation ID to validate
  ///
  /// Returns: true if the format is valid, false otherwise
  static bool isValidConversationId(String conversationId) {
    if (conversationId.isEmpty) return false;

    // Check for key exchange format
    if (conversationId.startsWith('key_exchange_')) return true;

    // Check for temporary format
    if (conversationId.startsWith('temp_chat_')) return true;

    // Check for standard chat format: chat_user1_user2
    if (conversationId.startsWith('chat_')) {
      final parts = conversationId.split('_');
      return parts.length >= 3; // chat + user1 + user2
    }

    return false;
  }

  /// Extract participant IDs from a conversation ID
  ///
  /// [conversationId] - The conversation ID to parse
  ///
  /// Returns: List of participant IDs, or empty list if invalid format
  static List<String> extractParticipantIds(String conversationId) {
    if (!conversationId.startsWith('chat_')) return [];

    final parts = conversationId.split('_');
    if (parts.length < 3) return [];

    return parts.sublist(1); // Skip 'chat' prefix
  }

  /// Check if a user is a participant in a conversation
  ///
  /// [conversationId] - The conversation ID to check
  /// [userId] - The user ID to check
  ///
  /// Returns: true if the user is a participant, false otherwise
  static bool isParticipant(String conversationId, String userId) {
    final participants = extractParticipantIds(conversationId);
    return participants.contains(userId);
  }

  /// Get the other participant's ID in a conversation
  ///
  /// [conversationId] - The conversation ID
  /// [currentUserId] - The current user's ID
  ///
  /// Returns: The other participant's ID, or null if not found
  static String? getOtherParticipant(
      String conversationId, String currentUserId) {
    final participants = extractParticipantIds(conversationId);
    if (participants.length != 2) return null;

    if (participants[0] == currentUserId) {
      return participants[1];
    } else if (participants[1] == currentUserId) {
      return participants[0];
    }

    return null;
  }
}
