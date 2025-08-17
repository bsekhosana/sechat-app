import 'package:sechat_app/features/chat/services/optimized_chat_database_service.dart';

/// Optimized Chat Demo Data Generator
/// Utility to generate sample data for testing and demonstration
class OptimizedChatDemoData {
  static final _databaseService = OptimizedChatDatabaseService();

  /// Generate demo conversations and messages
  static Future<void> generateDemoData() async {
    try {
      print('🎭 OptimizedChatDemoData: 🚀 Starting demo data generation...');

      // Generate demo conversations
      await _generateDemoConversations();

      // Generate demo messages
      await _generateDemoMessages();

      print('🎭 OptimizedChatDemoData: ✅ Demo data generation completed!');
    } catch (e) {
      print('🎭 OptimizedChatDemoData: ❌ Demo data generation failed: $e');
      rethrow;
    }
  }

  /// Generate demo conversations
  static Future<void> _generateDemoConversations() async {
    final conversations = [
      {
        'id': 'demo_conv_1',
        'participant1_id': 'user_1',
        'participant2_id': 'user_2',
        'display_name': 'Alice Johnson',
        'created_at':
            DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
        'updated_at':
            DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        'last_message_at':
            DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        'last_message_preview': 'Thanks for the help!',
        'unread_count': 2,
        'is_typing': 0,
        'typing_user_id': null,
        'is_online': 1,
        'last_seen': DateTime.now()
            .subtract(const Duration(minutes: 30))
            .toIso8601String(),
        'is_pinned': 0,
      },
      {
        'id': 'demo_conv_2',
        'participant1_id': 'user_1',
        'participant2_id': 'user_3',
        'display_name': 'Bob Smith',
        'created_at':
            DateTime.now().subtract(const Duration(days: 5)).toIso8601String(),
        'updated_at':
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'last_message_at':
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'last_message_preview': 'See you tomorrow!',
        'unread_count': 0,
        'is_typing': 0,
        'typing_user_id': null,
        'is_online': 0,
        'last_seen':
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'is_pinned': 1,
      },
      {
        'id': 'demo_conv_3',
        'participant1_id': 'user_1',
        'participant2_id': 'user_4',
        'display_name': 'Carol Davis',
        'created_at':
            DateTime.now().subtract(const Duration(hours: 6)).toIso8601String(),
        'updated_at': DateTime.now()
            .subtract(const Duration(minutes: 45))
            .toIso8601String(),
        'last_message_at': DateTime.now()
            .subtract(const Duration(minutes: 45))
            .toIso8601String(),
        'last_message_preview': 'How are you doing?',
        'unread_count': 1,
        'is_typing': 1,
        'typing_user_id': 'user_4',
        'is_online': 1,
        'last_seen': DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
        'is_pinned': 0,
      },
      {
        'id': 'demo_conv_4',
        'participant1_id': 'user_1',
        'participant2_id': 'user_5',
        'display_name': 'David Wilson',
        'created_at': DateTime.now()
            .subtract(const Duration(hours: 12))
            .toIso8601String(),
        'updated_at': DateTime.now()
            .subtract(const Duration(hours: 12))
            .toIso8601String(),
        'last_message_at': DateTime.now()
            .subtract(const Duration(hours: 12))
            .toIso8601String(),
        'last_message_preview': 'Hello there!',
        'unread_count': 0,
        'is_typing': 0,
        'typing_user_id': null,
        'is_online': 0,
        'last_seen': DateTime.now()
            .subtract(const Duration(hours: 12))
            .toIso8601String(),
        'is_pinned': 0,
      },
    ];

    for (final conversation in conversations) {
      await _databaseService.saveConversation(conversation);
      print(
          '🎭 OptimizedChatDemoData: ✅ Saved conversation: ${conversation['display_name']}');
    }
  }

  /// Generate demo messages
  static Future<void> _generateDemoMessages() async {
    final messages = [
      // Conversation 1: Alice Johnson
      {
        'id': 'demo_msg_1_1',
        'conversation_id': 'demo_conv_1',
        'sender_id': 'user_2',
        'recipient_id': 'user_1',
        'content': 'Hey! How are you doing today?',
        'message_type': 'text',
        'status': 'read',
        'timestamp':
            DateTime.now().subtract(const Duration(hours: 4)).toIso8601String(),
        'delivered_at': DateTime.now()
            .subtract(const Duration(hours: 4, minutes: 1))
            .toIso8601String(),
        'read_at': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 30))
            .toIso8601String(),
        'metadata': '{"messageDirection": "incoming"}',
      },
      {
        'id': 'demo_msg_1_2',
        'conversation_id': 'demo_conv_1',
        'sender_id': 'user_1',
        'recipient_id': 'user_2',
        'content': 'I\'m doing great! Just working on some new features.',
        'message_type': 'text',
        'status': 'read',
        'timestamp': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 45))
            .toIso8601String(),
        'delivered_at': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 44))
            .toIso8601String(),
        'read_at': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 30))
            .toIso8601String(),
        'metadata': '{"messageDirection": "outgoing"}',
      },
      {
        'id': 'demo_msg_1_3',
        'conversation_id': 'demo_conv_1',
        'sender_id': 'user_2',
        'recipient_id': 'user_1',
        'content': 'That sounds exciting! Can I help with anything?',
        'message_type': 'text',
        'status': 'read',
        'timestamp': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 30))
            .toIso8601String(),
        'delivered_at': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 29))
            .toIso8601String(),
        'read_at': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 25))
            .toIso8601String(),
        'metadata': '{"messageDirection": "incoming"}',
      },
      {
        'id': 'demo_msg_1_4',
        'conversation_id': 'demo_conv_1',
        'sender_id': 'user_1',
        'recipient_id': 'user_2',
        'content': 'Actually, yes! I could use some feedback on the UI design.',
        'message_type': 'text',
        'status': 'read',
        'timestamp': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 20))
            .toIso8601String(),
        'delivered_at': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 19))
            .toIso8601String(),
        'read_at': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 15))
            .toIso8601String(),
        'metadata': '{"messageDirection": "outgoing"}',
      },
      {
        'id': 'demo_msg_1_5',
        'conversation_id': 'demo_conv_1',
        'sender_id': 'user_2',
        'recipient_id': 'user_1',
        'content': 'I\'d be happy to help! Send me some screenshots.',
        'message_type': 'text',
        'status': 'read',
        'timestamp': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 15))
            .toIso8601String(),
        'delivered_at': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 14))
            .toIso8601String(),
        'read_at': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 10))
            .toIso8601String(),
        'metadata': '{"messageDirection": "incoming"}',
      },
      {
        'id': 'demo_msg_1_6',
        'conversation_id': 'demo_conv_1',
        'sender_id': 'user_1',
        'recipient_id': 'user_2',
        'content': 'Perfect! I\'ll send them over in a bit.',
        'message_type': 'text',
        'status': 'read',
        'timestamp': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 10))
            .toIso8601String(),
        'delivered_at': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 9))
            .toIso8601String(),
        'read_at': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 5))
            .toIso8601String(),
        'metadata': '{"messageDirection": "outgoing"}',
      },
      {
        'id': 'demo_msg_1_7',
        'conversation_id': 'demo_conv_1',
        'sender_id': 'user_2',
        'recipient_id': 'user_1',
        'content':
            'Great! Looking forward to seeing what you\'ve been working on.',
        'message_type': 'text',
        'status': 'read',
        'timestamp': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 5))
            .toIso8601String(),
        'delivered_at': DateTime.now()
            .subtract(const Duration(hours: 3, minutes: 4))
            .toIso8601String(),
        'read_at':
            DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
        'metadata': '{"messageDirection": "incoming"}',
      },
      {
        'id': 'demo_msg_1_8',
        'conversation_id': 'demo_conv_1',
        'sender_id': 'user_1',
        'recipient_id': 'user_2',
        'content': 'Thanks for the help!',
        'message_type': 'text',
        'status': 'delivered',
        'timestamp':
            DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        'delivered_at': DateTime.now()
            .subtract(const Duration(hours: 1, minutes: 59))
            .toIso8601String(),
        'read_at': null,
        'metadata': '{"messageDirection": "outgoing"}',
      },

      // Conversation 2: Bob Smith
      {
        'id': 'demo_msg_2_1',
        'conversation_id': 'demo_conv_2',
        'sender_id': 'user_3',
        'recipient_id': 'user_1',
        'content': 'Hey! Are we still meeting tomorrow?',
        'message_type': 'text',
        'status': 'read',
        'timestamp': DateTime.now()
            .subtract(const Duration(days: 1, hours: 2))
            .toIso8601String(),
        'delivered_at': DateTime.now()
            .subtract(const Duration(days: 1, hours: 1, minutes: 59))
            .toIso8601String(),
        'read_at': DateTime.now()
            .subtract(const Duration(days: 1, hours: 1))
            .toIso8601String(),
        'metadata': '{"messageDirection": "incoming"}',
      },
      {
        'id': 'demo_msg_2_2',
        'conversation_id': 'demo_conv_2',
        'sender_id': 'user_1',
        'recipient_id': 'user_3',
        'content': 'Yes, absolutely! 2 PM at the coffee shop.',
        'message_type': 'text',
        'status': 'read',
        'timestamp': DateTime.now()
            .subtract(const Duration(days: 1, hours: 1, minutes: 45))
            .toIso8601String(),
        'delivered_at': DateTime.now()
            .subtract(const Duration(days: 1, hours: 1, minutes: 44))
            .toIso8601String(),
        'read_at': DateTime.now()
            .subtract(const Duration(days: 1, hours: 1, minutes: 30))
            .toIso8601String(),
        'metadata': '{"messageDirection": "outgoing"}',
      },
      {
        'id': 'demo_msg_2_3',
        'conversation_id': 'demo_conv_2',
        'sender_id': 'user_3',
        'recipient_id': 'user_1',
        'content': 'Perfect! See you tomorrow!',
        'message_type': 'text',
        'status': 'read',
        'timestamp': DateTime.now()
            .subtract(const Duration(days: 1, hours: 1, minutes: 30))
            .toIso8601String(),
        'delivered_at': DateTime.now()
            .subtract(const Duration(days: 1, hours: 1, minutes: 29))
            .toIso8601String(),
        'read_at': DateTime.now()
            .subtract(const Duration(days: 1, hours: 1, minutes: 15))
            .toIso8601String(),
        'metadata': '{"messageDirection": "incoming"}',
      },

      // Conversation 3: Carol Davis
      {
        'id': 'demo_msg_3_1',
        'conversation_id': 'demo_conv_3',
        'sender_id': 'user_4',
        'recipient_id': 'user_1',
        'content': 'Hi there! How are you doing?',
        'message_type': 'text',
        'status': 'delivered',
        'timestamp': DateTime.now()
            .subtract(const Duration(minutes: 45))
            .toIso8601String(),
        'delivered_at': DateTime.now()
            .subtract(const Duration(minutes: 44))
            .toIso8601String(),
        'read_at': null,
        'metadata': '{"messageDirection": "incoming"}',
      },

      // Conversation 4: David Wilson
      {
        'id': 'demo_msg_4_1',
        'conversation_id': 'demo_conv_4',
        'sender_id': 'user_5',
        'recipient_id': 'user_1',
        'content': 'Hello there!',
        'message_type': 'text',
        'status': 'read',
        'timestamp': DateTime.now()
            .subtract(const Duration(hours: 12))
            .toIso8601String(),
        'delivered_at': DateTime.now()
            .subtract(const Duration(hours: 11, minutes: 59))
            .toIso8601String(),
        'read_at': DateTime.now()
            .subtract(const Duration(hours: 11, minutes: 30))
            .toIso8601String(),
        'metadata': '{"messageDirection": "incoming"}',
      },
    ];

    for (final message in messages) {
      await _databaseService.saveMessage(message);
      print('🎭 OptimizedChatDemoData: ✅ Saved message: ${message['content']}');
    }
  }

  /// Clear all demo data
  static Future<void> clearDemoData() async {
    try {
      await _databaseService.clearAllData();
      print('🎭 OptimizedChatDemoData: ✅ Demo data cleared!');
    } catch (e) {
      print('🎭 OptimizedChatDemoData: ❌ Failed to clear demo data: $e');
      rethrow;
    }
  }

  /// Get demo data statistics
  static Future<Map<String, int>> getDemoDataStats() async {
    try {
      return await _databaseService.getDatabaseStats();
    } catch (e) {
      print('🎭 OptimizedChatDemoData: ❌ Failed to get demo data stats: $e');
      return {'conversations': 0, 'messages': 0};
    }
  }
}
