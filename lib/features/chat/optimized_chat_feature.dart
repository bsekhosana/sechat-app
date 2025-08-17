import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sechat_app/features/chat/providers/optimized_chat_list_provider.dart';
import 'package:sechat_app/features/chat/providers/optimized_session_chat_provider.dart';
import 'package:sechat_app/features/chat/screens/optimized_chat_list_screen.dart';
import 'package:sechat_app/features/chat/screens/optimized_chat_screen.dart';
import 'package:sechat_app/core/services/optimized_notification_service.dart';

/// Optimized Chat Feature
/// Main entry point that brings together all optimized chat components
class OptimizedChatFeature extends StatelessWidget {
  const OptimizedChatFeature({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => OptimizedChatListProvider()),
        ChangeNotifierProvider(create: (_) => OptimizedSessionChatProvider()),
      ],
      child: const OptimizedChatFeatureRouter(),
    );
  }
}

/// Router for the optimized chat feature
class OptimizedChatFeatureRouter extends StatefulWidget {
  const OptimizedChatFeatureRouter({super.key});

  @override
  State<OptimizedChatFeatureRouter> createState() =>
      _OptimizedChatFeatureRouterState();
}

class _OptimizedChatFeatureRouterState
    extends State<OptimizedChatFeatureRouter> {
  final _notificationService = OptimizedNotificationService();

  @override
  void initState() {
    super.initState();
    _setupNotificationCallbacks();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Optimized Chat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const OptimizedChatListScreen(),
      routes: {
        '/chat': (context) => const OptimizedChatScreen(
              conversationId: '', // Will be set via arguments
              recipientName: '', // Will be set via arguments
            ),
      },
    );
  }

  /// Setup notification service callbacks
  void _setupNotificationCallbacks() {
    // Get providers from context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatListProvider = context.read<OptimizedChatListProvider>();
      final sessionChatProvider = context.read<OptimizedSessionChatProvider>();

      // Set up message received callback
      _notificationService.setOnMessageReceived(
          (senderId, senderName, message, conversationId, messageId) {
        print('🔔 OptimizedChatFeature: Message received callback triggered');

        // Update chat list
        chatListProvider.handleIncomingMessage(
          senderId: senderId,
          senderName: senderName,
          message: message,
          conversationId: conversationId,
          messageId: messageId,
        );

        // Update active chat session if it matches
        sessionChatProvider.handleIncomingMessage(
          senderId: senderId,
          senderName: senderName,
          message: message,
          conversationId: conversationId,
          messageId: messageId,
        );
      });

      // Set up typing indicator callback
      _notificationService.setOnTypingIndicator((senderId, isTyping) {
        print('🔔 OptimizedChatFeature: Typing indicator callback triggered');

        // Update chat list
        chatListProvider.handleTypingIndicator(senderId, isTyping);

        // Update active chat session if it matches
        sessionChatProvider.handleTypingIndicator(senderId, isTyping);
      });

      // Set up online status callback
      _notificationService
          .setOnOnlineStatusUpdate((senderId, isOnline, lastSeen) {
        print('🔔 OptimizedChatFeature: Online status callback triggered');

        // Update chat list
        chatListProvider.handleOnlineStatusUpdate(senderId, isOnline, lastSeen);

        // Update active chat session if it matches
        sessionChatProvider.handleOnlineStatusUpdate(
            senderId, isOnline, lastSeen);
      });

      // Set up message status callback
      _notificationService
          .setOnMessageStatusUpdate((senderId, messageId, status) {
        print('🔔 OptimizedChatFeature: Message status callback triggered');

        // Update active chat session
        sessionChatProvider.handleMessageStatusUpdate(
            senderId, messageId, status);
      });

      print('🔔 OptimizedChatFeature: ✅ All notification callbacks configured');
    });
  }
}

/// Extension to provide easy access to chat providers
extension ChatProviders on BuildContext {
  OptimizedChatListProvider get chatListProvider =>
      read<OptimizedChatListProvider>();
  OptimizedSessionChatProvider get sessionChatProvider =>
      read<OptimizedSessionChatProvider>();
}

/// Helper class for navigation between chat screens
class OptimizedChatNavigator {
  /// Navigate to chat screen
  static void navigateToChat(
      BuildContext context, String conversationId, String recipientName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OptimizedChatScreen(
          conversationId: conversationId,
          recipientName: recipientName,
        ),
      ),
    );
  }

  /// Navigate back to chat list
  static void navigateBackToList(BuildContext context) {
    Navigator.pop(context);
  }

  /// Navigate to new conversation
  static void navigateToNewConversation(BuildContext context) {
    // TODO: Implement new conversation flow
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('New conversation feature coming soon!'),
      ),
    );
  }
}
