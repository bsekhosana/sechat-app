import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io' show Platform, ProcessSignal, Process;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import '/../core/utils/logger.dart';

// Import models for message status updates
import 'features/chat/services/message_status_tracking_service.dart';
import 'features/chat/models/message.dart';
import 'features/chat/models/message_status.dart' as msg_status;

// import feature providers
import 'features/key_exchange/providers/key_exchange_request_provider.dart';
import 'features/chat/providers/chat_list_provider.dart';
import 'features/chat/providers/session_chat_provider.dart';
import 'features/chat/services/unified_chat_socket_integration.dart';
import 'shared/providers/socket_provider.dart';

// import screens
import 'features/auth/screens/welcome_screen.dart';
import 'features/auth/screens/main_nav_screen.dart';
import 'features/auth/screens/login_screen.dart';

// import widgets
import 'shared/widgets/app_lifecycle_handler.dart';

// import services
import 'core/services/se_session_service.dart';
import 'core/services/se_shared_preference_service.dart';
import 'core/services/network_service.dart';
import 'core/services/local_storage_service.dart';
import 'features/chat/services/message_storage_service.dart';
import 'core/services/se_socket_service.dart';
import 'core/services/key_exchange_service.dart';
import 'core/services/ui_service.dart';
import 'core/services/presence_manager.dart';
import 'core/services/contact_service.dart';
import 'core/services/app_lifecycle_manager.dart';
import 'features/notifications/services/local_notification_items_service.dart';
import 'features/notifications/services/local_notification_badge_service.dart';
import 'core/services/message_notification_service.dart';
import 'realtime/realtime_service_manager.dart';
import 'realtime/realtime_test.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import 'core/services/indicator_service.dart';
import 'core/services/encryption_service.dart';
import 'package:sechat_app/shared/providers/socket_status_provider.dart';
import 'package:sechat_app/core/services/network_service.dart';
import 'package:sechat_app/core/services/unified_message_service.dart';

import 'package:sechat_app/core/utils/conversation_id_generator.dart';

// Global navigator key to access context from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global variable to track current screen index
int _currentScreenIndex = 0;

/// Update the current screen index (called from MainNavScreen)
void updateCurrentScreenIndex(int index) {
  _currentScreenIndex = index;
  Logger.debug('Current screen index updated to: $index', 'Main');
}

/// CRITICAL: Set up app termination handler to prevent socket service memory leaks
void _setupAppTerminationHandler() {
  // Handle app termination signals
  ProcessSignal.sigterm.watch().listen((_) {
    Logger.warning('SIGTERM received - cleaning up socket services...', 'Main');
    _cleanupSocketServices();
  });

  ProcessSignal.sigint.watch().listen((_) {
    Logger.warning('SIGINT received - cleaning up socket services...', 'Main');
    _cleanupSocketServices();
  });

  Logger.success('App termination handlers configured', 'Main');
}

/// Clean up socket services to prevent memory leaks
void _cleanupSocketServices() {
  try {
    Logger.debug('Starting socket service cleanup...', 'Main');

    // Force cleanup all socket services
    SeSocketService.forceCleanup();
    Logger.success('Socket services force cleanup completed', 'Main');
  } catch (e) {
    Logger.error('Error during socket service cleanup: $e', 'Main');
  }
}

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  Logger.info('Starting SeChat application...', 'Main');
  Logger.info(
      'Platform: ${Platform.isIOS ? 'iOS' : Platform.isAndroid ? 'Android' : 'Web'}',
      'Main');

  // CRITICAL: Set up app termination handler to prevent memory leaks
  _setupAppTerminationHandler();

  // Only use native splash on mobile platforms
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }

  // Initialize core services in parallel for faster startup
  await Future.wait([
    LocalStorageService.instance.initialize(),
    SeSharedPreferenceService().initialize(),
    MessageStorageService.instance.initialize(),
  ]);

  // Initialize local notification services
  try {
    final localNotificationService = LocalNotificationItemsService();
    final localNotificationBadgeService = LocalNotificationBadgeService();

    // Force reset any old notification counts first
    await localNotificationBadgeService.forceResetAndReinitialize();

    Logger.success(
        'Local notification services initialized successfully', 'Main');
  } catch (e) {
    Logger.warning(
        'Failed to initialize local notification services: $e', 'Main');
  }

  // Initialize message notification service
  try {
    await MessageNotificationService.instance.initialize();
    Logger.success(
        'Message notification service initialized successfully', 'Main');
  } catch (e) {
    Logger.warning(
        'Failed to initialize message notification service: $e', 'Main');
  }

  // Initialize presence management system
  try {
    final presenceManager = PresenceManager.instance;
    await presenceManager.initialize();
    Logger.success(
        'Presence management system initialized successfully', 'Main');
  } catch (e) {
    Logger.error('Failed to initialize presence management system: $e', 'Main');
  }

  // Initialize realtime services
  try {
    final realtimeManager = RealtimeServiceManager();
    await realtimeManager.initialize();
    Logger.success('Realtime services initialized successfully', 'Main');

    // Run basic tests in debug mode
    if (kDebugMode) {
      try {
        await RealtimeTest.runBasicTests();
        Logger.success('Realtime service tests passed', 'Main');
      } catch (e) {
        Logger.warning('Realtime service tests failed: $e', 'Main');
      }
    }
  } catch (e) {
    Logger.error('Failed to initialize realtime services: $e', 'Main');
  }

  // Initialize SeSessionService
  final seSessionService = SeSessionService();
  await seSessionService.loadSession();

  // Set up socket callbacks for realtime features
  final socketService = SeSocketService.instance;

  // Ensure socket service is ready for new connections
  if (SeSocketService.isDestroyed) {
    Logger.info(
        ' Main:  Socket service was destroyed, resetting for new session...');
    SeSocketService.resetForNewConnection();
  }

  // CRITICAL: Set up socket callbacks IMMEDIATELY to avoid race conditions
  Logger.info('Setting up socket callbacks immediately...', 'Main');
  _setupSocketCallbacks(socketService);
  Logger.success('Socket callbacks set up successfully', 'Main');

  // Verify callback setup
  Logger.info(' Main:  Verifying onKeyExchangeResponse callback setup...');
  if (socketService.onKeyExchangeResponse != null) {
    Logger.success(' Main:  onKeyExchangeResponse callback is properly set');
  } else {
    Logger.error(
        ' Main:  onKeyExchangeResponse callback is NULL - this will cause issues!');
  }

  // Set up contact listeners for the current user's contacts
  // This will enable receiving typing indicators and other events
  if (seSessionService.currentSession != null) {
    // For now, we'll set up a basic listener
    // In the future, this should be populated with actual contact session IDs
    final currentUserId = seSessionService.currentSessionId;
    if (currentUserId != null) {
      Logger.success(
          ' Main:  Channel-based socket service initialized for user: $currentUserId');
    }
  }

  // Note: Typing indicators are now handled through the ChannelSocketService event system
  // The realtime services will automatically receive and process these events

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => IndicatorService()),
        ChangeNotifierProvider(create: (_) => SessionChatProvider()),
        ChangeNotifierProvider(create: (_) => KeyExchangeRequestProvider()),
        ChangeNotifierProvider(create: (_) => ContactService.instance),
        ChangeNotifierProvider(create: (_) => PresenceManager.instance),
        ChangeNotifierProvider(create: (_) {
          final provider = SocketProvider();
          // Initialize in the next frame to avoid blocking the UI
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await provider.initialize();
            // Refresh connection state after initialization
            provider.refreshConnectionState();
          });
          return provider;
        }),
        ChangeNotifierProvider(create: (_) {
          final provider = ChatListProvider();
          // Initialize in the next frame to avoid blocking the UI
          WidgetsBinding.instance.addPostFrameCallback((_) {
            provider.initialize();

            // CRITICAL: Set up ChatListProvider to listen to UnifiedMessageService
            final unifiedMessageService = UnifiedMessageService.instance;
            unifiedMessageService.addListener(() {
              Logger.debug(
                  ' Main: 🔔 ChatListProvider UnifiedMessageService update received');
              // Refresh the chat list to show latest messages
              provider.refreshConversations();
            });
            Logger.success(
                ' Main:  ChatListProvider UnifiedMessageService listener set up');
          });
          return provider;
        }),
        ChangeNotifierProvider(create: (_) {
          final provider = SessionChatProvider();
          // Set up online status callback to ChatListProvider
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final chatListProvider = Provider.of<ChatListProvider>(
                navigatorKey.currentContext!,
                listen: false);
            chatListProvider
                .setOnOnlineStatusChanged((userId, isOnline, lastSeen) {
              provider.updateRecipientStatus(
                recipientId: userId,
                isOnline: isOnline,
                lastSeen: lastSeen,
              );
            });
          });
          return provider;
        }),
        ChangeNotifierProvider(create: (_) => NetworkService.instance),
        ChangeNotifierProvider(create: (_) => LocalStorageService.instance),
        ChangeNotifierProvider(create: (_) => SocketStatusProvider.instance),
      ],
      child: AppLifecycleManager(
        presenceManager: PresenceManager.instance,
        child: const SeChatApp(),
      ),
    ),
  );

  // CRITICAL: Set up global UnifiedMessageService listener after app is built
  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      final globalSessionChatProvider = Provider.of<SessionChatProvider>(
          navigatorKey.currentContext!,
          listen: false);

      // Set up a global listener for UnifiedMessageService
      final unifiedMessageService = UnifiedMessageService.instance;
      Logger.info(' Main:  Setting up global UnifiedMessageService listener');
      Logger.info(
          ' Main:  Global SessionChatProvider instance: ${globalSessionChatProvider.hashCode}');
      Logger.info(
          ' Main:  UnifiedMessageService instance: ${unifiedMessageService.hashCode}');

      // Add the global provider as a listener
      unifiedMessageService.addListener(() {
        Logger.debug(' Main: 🔔 Global UnifiedMessageService update received');
        // Notify the global SessionChatProvider to refresh
        globalSessionChatProvider.notifyListeners();
      });

      Logger.success(
          ' Main:  Global UnifiedMessageService listener set up successfully');
    } catch (e) {
      Logger.error(
          ' Main:  Failed to set up global UnifiedMessageService listener: $e');
    }
  });
}

// Note: Push notifications are now handled by UnifiedMessageService

// Set up socket callbacks
void _setupSocketCallbacks(SeSocketService socketService) {
  // Set up callbacks for the socket service
  socketService.setOnMessageReceived(
      (senderId, senderName, message, conversationId, messageId) async {
    Logger.debug(
        ' Main: Message received callback from socket: $senderName: $message');

    // CRITICAL: Save incoming message to database via UnifiedMessageService
    try {
      final unifiedMessageService = UnifiedMessageService.instance;
      Logger.info(
          ' Main:  Using UnifiedMessageService instance: ${unifiedMessageService.hashCode}');

      // Check if message is encrypted (default to true for security)
      bool isEncrypted = true;
      String? checksum;

      // CRITICAL: Declare conversation ID outside the if block for use in callback
      String? actualConversationId;

      // If the message payload contains encryption info, extract it
      // This would come from the socket event data structure
      if (messageId.isNotEmpty && message.isNotEmpty) {
        // CRITICAL: Use consistent conversation ID for both users
        final currentUserId = SeSessionService().currentSessionId ?? '';
        actualConversationId =
            _generateConsistentConversationId(currentUserId, senderId);

        Logger.info(' Main:  Socket conversationId: $conversationId');
        Logger.info(' Main:  SenderId: $senderId');
        Logger.info(' Main:  Using conversationId: $actualConversationId');

        // CRITICAL: Ensure conversation exists before saving message
        _ensureConversationExists(actualConversationId, senderId, senderName);

        // Store message to database with encrypted text only
        unifiedMessageService.handleIncomingMessage(
          messageId: messageId,
          fromUserId: senderId,
          conversationId: actualConversationId,
          body: message,
          timestamp: DateTime.now(),
          isEncrypted: isEncrypted,
          checksum: checksum,
        );
        Logger.success(
            ' Main:  Incoming message saved to database via UnifiedMessageService');

        // Push notification will be shown later in the callback

        // CRITICAL: Update conversation with new message and decrypt preview
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            final indicatorService = Provider.of<IndicatorService>(
                navigatorKey.currentContext!,
                listen: false);

            final chatListProvider = Provider.of<ChatListProvider>(
                navigatorKey.currentContext!,
                listen: false);

            try {
              // CRITICAL: Decrypt the message content first
              String decryptedContent = message;

              // Check if this looks like encrypted content
              if (message.length > 100 && message.contains('eyJ')) {
                Logger.debug(
                    ' Main: 🔓 Attempting to decrypt message for chat list preview');
                try {
                  // Use EncryptionService to decrypt the message (first layer)
                  final decryptedData =
                      await EncryptionService.decryptAesCbcPkcs7(message);

                  if (decryptedData != null &&
                      decryptedData.containsKey('text')) {
                    final firstLayerDecrypted = decryptedData['text'] as String;
                    Logger.success(
                        ' Main:  First layer decrypted: $firstLayerDecrypted');

                    // Check if the decrypted text is still encrypted (double encryption scenario)
                    if (firstLayerDecrypted.length > 100 &&
                        firstLayerDecrypted.contains('eyJ')) {
                      Logger.info(
                          ' Main:  Detected double encryption, decrypting inner layer...');
                      try {
                        // Decrypt the inner encrypted content
                        final innerDecryptedData =
                            await EncryptionService.decryptAesCbcPkcs7(
                                firstLayerDecrypted);

                        if (innerDecryptedData != null &&
                            innerDecryptedData.containsKey('text')) {
                          final finalDecryptedText =
                              innerDecryptedData['text'] as String;
                          Logger.success(
                              ' Main:  Inner layer decrypted successfully');
                          decryptedContent = finalDecryptedText;
                        } else {
                          Logger.warning(
                              ' Main:  Inner layer decryption failed, using first layer');
                          decryptedContent = firstLayerDecrypted;
                        }
                      } catch (e) {
                        Logger.error(
                            ' Main:  Inner layer decryption error: $e, using first layer');
                        decryptedContent = firstLayerDecrypted;
                      }
                    } else {
                      // Single layer encryption, use as is
                      Logger.success(
                          ' Main:  Single layer decryption completed');
                      decryptedContent = firstLayerDecrypted;
                    }
                  } else {
                    Logger.warning(
                        ' Main:  Decryption failed - invalid format, using encrypted text');
                    decryptedContent = '[Encrypted Message]';
                  }
                } catch (e) {
                  Logger.error(' Main:  Decryption failed: $e');
                  decryptedContent = '[Encrypted Message]';
                }
              } else {
                Logger.info(
                    ' Main:  Message appears to be plain text, using as-is');
              }

              // Call handleIncomingMessage to decrypt the message preview
              if (actualConversationId != null) {
                chatListProvider.handleIncomingMessage(
                  senderId: senderId,
                  senderName: senderName,
                  message: decryptedContent, // Use decrypted content
                  conversationId: actualConversationId,
                  messageId: messageId,
                );
                Logger.success(
                    ' Main:  Conversation updated with decrypted message preview');

                // CRITICAL: Also update chat list in real-time with new message using decrypted content
                chatListProvider.handleNewMessageArrival(
                  messageId: messageId,
                  senderId: senderId,
                  content:
                      decryptedContent, // Use decrypted content instead of raw message
                  conversationId: actualConversationId,
                  timestamp: DateTime.now(),
                  messageType: MessageType.text,
                );
                Logger.success(
                    ' Main:  Chat list updated in real-time with decrypted message');
              }
            } catch (e) {
              Logger.warning(
                  ' Main:  Failed to update conversation with decrypted preview: $e');
            }

            // CRITICAL: Update SessionChatProvider if the message is for the current conversation
            try {
              final sessionChatProvider = Provider.of<SessionChatProvider>(
                  navigatorKey.currentContext!,
                  listen: false);

              // Check if this message is for the current conversation
              if (sessionChatProvider.currentConversationId ==
                      actualConversationId ||
                  (sessionChatProvider.currentRecipientId == senderId)) {
                Logger.info(
                    ' Main:  Updating SessionChatProvider for current conversation');

                // Trigger message refresh from database
                await sessionChatProvider.refreshMessages();
                Logger.success(
                    ' Main:  SessionChatProvider messages refreshed');

                // CRITICAL FIX: Don't send immediate read receipts
                // According to SeChat API docs, read receipts should only be sent when user actually reads
                // The server will handle the proper receipt:read event flow
                Logger.info(
                    ' Main:  Message received - read receipts will be sent via proper server flow');
              } else {
                Logger.info(
                    ' Main:  Message not for current conversation - SessionChatProvider not updated');
              }
            } catch (e) {
              Logger.warning(
                  ' Main:  Failed to update SessionChatProvider: $e');
            }

            // CRITICAL: Update UnifiedChatProvider if the message is for the current conversation
            try {
              final unifiedChatSocketIntegration =
                  UnifiedChatSocketIntegration();
              unifiedChatSocketIntegration.handleIncomingMessage(
                messageId: messageId,
                senderId: senderId,
                conversationId: actualConversationId ?? '',
                body: message,
                senderName: senderName,
              );
              Logger.success(
                  ' Main:  UnifiedChatProvider updated for incoming message');
            } catch (e) {
              Logger.warning(
                  ' Main:  Failed to update UnifiedChatProvider: $e');
            }

            // Count unread conversations
            final unreadCount = chatListProvider.conversations
                .where((conv) => conv.unreadCount > 0)
                .length;

            // Update the indicator service
            indicatorService.updateCounts(unreadChats: unreadCount);
            Logger.success(' Main:  Chat badge count updated for new message');

            // Note: Push notifications are now handled by UnifiedMessageService
            // to avoid duplicate notifications
          } catch (e) {
            Logger.error(' Main:  Failed to update chat badge count: $e');
          }
        });
      } else {
        Logger.warning(' Main:  Invalid message data received');
      }
    } catch (e) {
      Logger.error(' Main:  Failed to save incoming message to database: $e');
    }
  });

  Logger.debug(' Main: 🔧 Setting up typing indicator callback...');
  socketService.setOnTypingIndicator((senderId, isTyping) {
    Logger.debug(
        ' Main: 🔔 Typing indicator callback EXECUTED: $senderId -> $isTyping');

    // CRITICAL: Filter out own typing indicators
    final currentUserId = SeSessionService().currentSessionId;
    if (currentUserId != null && senderId == currentUserId) {
      Logger.warning(' Main:  Ignoring own typing indicator from: $senderId');
      return; // Don't process own typing indicator
    }

    // Forward typing indicator to both SessionChatProvider and ChatListProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // Update ChatListProvider for chat list items
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Find conversation by participant ID and update typing indicator
        // This will show the typing indicator on the recipient's side (not the sender's)
        chatListProvider.updateTypingIndicatorByParticipant(senderId, isTyping);

        // Also notify SessionChatProvider if there's an active chat
        try {
          final sessionChatProvider = Provider.of<SessionChatProvider>(
              navigatorKey.currentContext!,
              listen: false);

          // Check if this typing indicator is for the current conversation
          if (sessionChatProvider.currentRecipientId != null) {
            final currentRecipientId = sessionChatProvider.currentRecipientId;

            // CRITICAL: The typing indicator should be shown when:
            // 1. The sender is the current recipient (meaning we're seeing someone else type)
            // 2. The currentRecipientId contains the sender ID (conversation match)
            bool shouldUpdate = false;

            if (currentRecipientId == senderId) {
              // Direct match with current recipient - show typing indicator
              shouldUpdate = true;
            } else if (currentRecipientId?.startsWith('chat_') == true &&
                currentRecipientId?.contains(senderId) == true) {
              // Conversation ID contains the sender ID - show typing indicator
              shouldUpdate = true;
            }

            if (shouldUpdate) {
              // CRITICAL: Only show typing indicator if the sender is NOT the current user
              final currentUserId = SeSessionService().currentSessionId;
              if (currentUserId != null && senderId != currentUserId) {
                sessionChatProvider.updateRecipientTypingState(isTyping);
                Logger.success(
                    ' Main:  Typing indicator updated for current conversation: $senderId -> $isTyping');
              } else {
                Logger.warning(
                    ' Main:  Not showing typing indicator for own typing: $senderId');
              }
            } else {
              Logger.info(
                  'Typing indicator from different conversation: $senderId (current: $currentRecipientId)',
                  'Main');
            }
          } else {
            Logger.info(' Main:  No active chat conversation');
          }
        } catch (e) {
          Logger.warning(' Main:  SessionChatProvider not available: $e');
        }

        // Also notify UnifiedChatProvider if there's an active unified chat
        try {
          // Import the UnifiedChatSocketIntegration to handle typing indicators
          final unifiedChatSocketIntegration = UnifiedChatSocketIntegration();
          unifiedChatSocketIntegration.handleTypingIndicator(
            senderId: senderId,
            isTyping: isTyping,
            conversationId:
                'temp_conversation_id', // This will be resolved in the integration service
          );
          Logger.success(
              ' Main:  Typing indicator forwarded to UnifiedChatProvider');
        } catch (e) {
          Logger.warning(' Main:  UnifiedChatProvider not available: $e');
        }

        Logger.success(' Main:  Typing indicator processed successfully');
      } catch (e) {
        Logger.error(' Main:  Failed to process typing indicator: $e');
      }
    });
  });
  Logger.success(' Main:  Typing indicator callback setup complete');

  // Handle presence updates (online/offline status)
  socketService.setOnOnlineStatusUpdate((senderId, isOnline, lastSeen) {
    Logger.debug(
        '🔌 Main: Presence update received: $senderId -> ${isOnline ? 'online' : 'offline'} (lastSeen: $lastSeen)');

    // Update ChatListProvider for chat list items
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        Logger.info(' Main:  Starting presence update processing...');

        // Update ContactService for presence management
        try {
          Logger.info(
              ' Main:  Attempting to get ContactService from context...');
          final contactService = Provider.of<ContactService>(
              navigatorKey.currentContext!,
              listen: false);

          Logger.success(' Main:  ContactService obtained successfully');
          // 🆕 FIXED: Use existing lastSeen from ContactService when server doesn't provide one
          DateTime lastSeenDateTime;
          if (lastSeen != null && lastSeen.isNotEmpty) {
            lastSeenDateTime = DateTime.parse(lastSeen);
          } else {
            // Try to get existing lastSeen from ContactService to preserve offline time
            try {
              final existingContact = contactService.getContact(senderId);
              lastSeenDateTime = existingContact?.lastSeen ??
                  DateTime.now().subtract(Duration(hours: 1));
            } catch (e) {
              // Fallback to 1 hour ago if we can't get existing contact
              lastSeenDateTime = DateTime.now().subtract(Duration(hours: 1));
            }
          }

          Logger.info(
              ' Main:  Calling contactService.updateContactPresence...');
          contactService.updateContactPresence(
              senderId, isOnline, lastSeenDateTime);
          Logger.success(
              ' Main:  Presence update sent to ContactService for: $senderId -> ${isOnline ? 'online' : 'offline'}');
        } catch (e) {
          Logger.error(' Main:  ContactService error: $e');
          Logger.info(' Main:  Stack trace: ${StackTrace.current}');
        }

        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Update conversation online status
        chatListProvider.updateConversationOnlineStatus(
            senderId, isOnline, lastSeen);
        Logger.success(
            ' Main:  Conversation online status updated for: $senderId -> ${isOnline ? 'online' : 'offline'}');

        // Also notify SessionChatProvider if there's an active chat
        try {
          Logger.info(' Main:  Attempting to get SessionChatProvider...');
          final sessionChatProvider = Provider.of<SessionChatProvider>(
              navigatorKey.currentContext!,
              listen: false);

          Logger.success(' Main:  SessionChatProvider obtained');
          Logger.info(
              ' Main:  Current recipient ID: ${sessionChatProvider.currentRecipientId}');
          Logger.info(' Main:  Sender ID: $senderId');

          // If the sender is the current recipient, update their online state
          // Use more flexible matching to handle different conversation ID formats
          bool shouldUpdatePresence = false;

          Logger.info(
              ' Main:  Checking presence update for SessionChatProvider');
          Logger.info(
              ' Main:  Current recipient ID: ${sessionChatProvider.currentRecipientId}');
          Logger.info(
              ' Main:  Current conversation ID: ${sessionChatProvider.currentConversationId}');
          Logger.info(' Main:  Sender ID: $senderId');
          Logger.info(' Main:  Is online: $isOnline');
          Logger.info(' Main:  Last seen: $lastSeen');

          if (sessionChatProvider.currentRecipientId == senderId) {
            shouldUpdatePresence = true;
            Logger.success(' Main:  Direct recipient ID match for presence');
          } else if (sessionChatProvider.currentConversationId != null &&
              sessionChatProvider.currentConversationId!.contains(senderId)) {
            shouldUpdatePresence = true;
            Logger.success(
                ' Main:  Conversation ID contains sender ID for presence');
          }

          if (shouldUpdatePresence) {
            Logger.info(
                ' Main:  Updating SessionChatProvider recipient status...');
            sessionChatProvider.updateRecipientStatus(
              recipientId: senderId,
              isOnline: isOnline,
              lastSeen: lastSeen != null && lastSeen.isNotEmpty
                  ? DateTime.parse(lastSeen)
                  : null,
            );
            Logger.success(
                ' Main:  Presence update forwarded to SessionChatProvider for current recipient: $senderId');
          } else {
            Logger.info(
                ' Main:  Sender is not current recipient, skipping SessionChatProvider update');
          }
        } catch (e) {
          Logger.error(' Main:  SessionChatProvider error: $e');
          Logger.info(' Main:  Stack trace: ${StackTrace.current}');
        }

        // CRITICAL: Also update UnifiedChatProvider for real-time UI updates
        try {
          final unifiedChatSocketIntegration = UnifiedChatSocketIntegration();
          unifiedChatSocketIntegration.handlePresenceUpdate(
            userId: senderId,
            isOnline: isOnline,
            lastSeen: lastSeen != null && lastSeen.isNotEmpty
                ? DateTime.parse(lastSeen)
                : null,
          );
          Logger.success(
              ' Main:  UnifiedChatProvider updated for presence: $senderId -> ${isOnline ? 'online' : 'offline'}');
        } catch (e) {
          Logger.warning(
              ' Main:  Failed to update UnifiedChatProvider for presence: $e');
        }

        Logger.success(
            ' Main:  Presence update processed successfully for: $senderId');
      } catch (e) {
        Logger.error(' Main:  Failed to process presence update: $e');
      }
    });
  });

  // Set up message delivery receipt callback
  socketService.setOnMessageDelivered((messageId, fromUserId, toUserId) {
    Logger.success(
        ' Main: Message delivered: $messageId from $fromUserId to $toUserId');

    // Process delivered status update
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Create a MessageStatusUpdate for delivered status
        final statusUpdate = MessageStatusUpdate(
          messageId: messageId,
          status: msg_status.MessageDeliveryStatus.delivered,
          timestamp: DateTime.now(),
          senderId: fromUserId,
        );

        // Generate consistent conversation ID for lookup
        final conversationId =
            _generateConsistentConversationId(fromUserId, toUserId);

        // Pass additional data for conversation lookup
        chatListProvider.processMessageStatusUpdateWithContext(statusUpdate,
            conversationId: conversationId, recipientId: toUserId);
        Logger.success(
            ' Main: Message delivery status processed successfully with enhanced context');

        // CRITICAL: Also update SessionChatProvider for real-time UI updates
        try {
          final sessionChatProvider = Provider.of<SessionChatProvider>(
              navigatorKey.currentContext!,
              listen: false);

          // Check if this message is for the current conversation
          // Use more flexible matching to handle different conversation ID formats
          bool shouldUpdate = false;

          Logger.success(
              ' Main: 🔍 Checking message status update for SessionChatProvider');
          Logger.success(
              ' Main: 🔍 Current conversation ID: ${sessionChatProvider.currentConversationId}');
          Logger.success(' Main: 🔍 Message conversation ID: $conversationId');
          Logger.success(
              ' Main: 🔍 Current recipient ID: ${sessionChatProvider.currentRecipientId}');
          Logger.success(' Main: 🔍 Message from user ID: $fromUserId');

          if (sessionChatProvider.currentConversationId == conversationId) {
            shouldUpdate = true;
            Logger.success(' Main: ✅ Direct conversation ID match');
          } else if (sessionChatProvider.currentRecipientId == fromUserId) {
            shouldUpdate = true;
            Logger.success(' Main: ✅ Direct recipient ID match');
          } else if (sessionChatProvider.currentConversationId != null &&
              sessionChatProvider.currentConversationId!.contains(fromUserId)) {
            shouldUpdate = true;
            Logger.success(' Main: ✅ Conversation ID contains sender ID');
          }

          if (shouldUpdate) {
            Logger.success(
                ' Main: 🔄 Updating SessionChatProvider for delivered message');
            sessionChatProvider.handleMessageStatusUpdate(statusUpdate);
            Logger.success(
                ' Main: ✅ SessionChatProvider updated for delivered message');
          } else {
            Logger.success(
                ' Main: ℹ️ Message not for current conversation - SessionChatProvider not updated');
          }
        } catch (e) {
          Logger.success(
              ' Main: ⚠️ Failed to update SessionChatProvider for delivery: $e');
        }

        // CRITICAL: Also update UnifiedChatProvider for real-time UI updates
        try {
          final unifiedChatSocketIntegration = UnifiedChatSocketIntegration();
          unifiedChatSocketIntegration.handleMessageStatusUpdate(
            messageId: messageId,
            status: msg_status.MessageDeliveryStatus.delivered,
            senderId: fromUserId,
          );
          Logger.success(
              ' Main: ✅ UnifiedChatProvider updated for delivered message');
        } catch (e) {
          Logger.success(
              ' Main: ⚠️ Failed to update UnifiedChatProvider for delivered: $e');
        }
      } catch (e) {
        Logger.error(' Main: Failed to process message delivery status: $e');
      }
    });
  });

  // Set up message read receipt callback
  socketService.setOnMessageRead((messageId, fromUserId, toUserId) {
    Logger.success(
        ' Main: Message read: $messageId from $fromUserId to $toUserId');

    // Process read status update
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Create a MessageStatusUpdate for read status
        final statusUpdate = MessageStatusUpdate(
          messageId: messageId,
          status: msg_status.MessageDeliveryStatus.read,
          timestamp: DateTime.now(),
          senderId: fromUserId,
        );

        // Generate consistent conversation ID for lookup
        final conversationId =
            _generateConsistentConversationId(fromUserId, toUserId);

        // Pass additional data for conversation lookup
        chatListProvider.processMessageStatusUpdateWithContext(statusUpdate,
            conversationId: conversationId, recipientId: toUserId);
        Logger.success(
            ' Main: Message read status processed successfully with enhanced context');

        // CRITICAL: Also update SessionChatProvider for real-time UI updates
        try {
          final sessionChatProvider = Provider.of<SessionChatProvider>(
              navigatorKey.currentContext!,
              listen: false);

          // Check if this message is for the current conversation
          // Use more flexible matching to handle different conversation ID formats
          bool shouldUpdate = false;

          Logger.debug(
              '✅ Main: 🔍 Checking message status update for SessionChatProvider (read)');
          Logger.success(
              ' Main: 🔍 Current conversation ID: ${sessionChatProvider.currentConversationId}');
          Logger.success(' Main: 🔍 Message conversation ID: $conversationId');
          Logger.success(
              ' Main: 🔍 Current recipient ID: ${sessionChatProvider.currentRecipientId}');
          Logger.success(' Main: 🔍 Message from user ID: $fromUserId');

          if (sessionChatProvider.currentConversationId == conversationId) {
            shouldUpdate = true;
            Logger.debug('✅ Main: ✅ Direct conversation ID match (read)');
          } else if (sessionChatProvider.currentRecipientId == fromUserId) {
            shouldUpdate = true;
            Logger.debug('✅ Main: ✅ Direct recipient ID match (read)');
          } else if (sessionChatProvider.currentConversationId != null &&
              sessionChatProvider.currentConversationId!.contains(fromUserId)) {
            shouldUpdate = true;
            Logger.debug('✅ Main: ✅ Conversation ID contains sender ID (read)');
          }

          if (shouldUpdate) {
            Logger.success(
                ' Main: 🔄 Updating SessionChatProvider for read message');
            sessionChatProvider.handleMessageStatusUpdate(statusUpdate);
            Logger.success(
                ' Main: ✅ SessionChatProvider updated for read message');
          } else {
            Logger.debug(
                '✅ Main: ℹ️ Message not for current conversation - SessionChatProvider not updated (read)');
          }
        } catch (e) {
          Logger.success(
              ' Main: ⚠️ Failed to update SessionChatProvider for read: $e');
        }

        // CRITICAL: Also update UnifiedChatProvider for real-time UI updates
        try {
          final unifiedChatSocketIntegration = UnifiedChatSocketIntegration();
          unifiedChatSocketIntegration.handleMessageStatusUpdate(
            messageId: messageId,
            status: msg_status.MessageDeliveryStatus.read,
            senderId: fromUserId,
          );
          Logger.success(
              ' Main: ✅ UnifiedChatProvider updated for read message');
        } catch (e) {
          Logger.success(
              ' Main: ⚠️ Failed to update UnifiedChatProvider for read: $e');
        }
      } catch (e) {
        Logger.error(' Main: Failed to process message read status: $e');
      }
    });
  });

  socketService.setOnMessageStatusUpdate(
      (senderId, messageId, status, conversationId, recipientId) {
    Logger.debug(
        '🔌 Main: Message status update from socket: $messageId -> $status (conversationId: $conversationId, recipientId: $recipientId)');

    // 🆕 FIXED: Only process certain status updates, ignore delivered/read from message:status_update
    // These should only come through receipt:delivered and receipt:read events
    if (status.toLowerCase() == 'delivered' || status.toLowerCase() == 'read') {
      Logger.warning(
          ' Main:  Ignoring delivered/read status from message:status_update - waiting for proper receipt events');
      return; // Don't process delivered/read status from message:status_update
    }

    // Update message status in ChatListProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Parse the status string to enum
        msg_status.MessageDeliveryStatus parsedStatus;
        switch (status.toLowerCase()) {
          case 'sent':
            parsedStatus = msg_status.MessageDeliveryStatus.sent;
            break;
          case 'queued':
            parsedStatus = msg_status
                .MessageDeliveryStatus.sent; // Keep as sent until delivered
            break;
          default:
            parsedStatus = msg_status.MessageDeliveryStatus.sent;
            Logger.warning(
                ' Main:  Unknown status: $status, defaulting to sent');
            break;
        }

        // Create a MessageStatusUpdate with enhanced data for better conversation lookup
        final statusUpdate = MessageStatusUpdate(
          messageId: messageId,
          status: parsedStatus,
          timestamp: DateTime.now(),
          senderId: senderId,
        );

        // Pass additional data for conversation lookup via a custom method
        chatListProvider.processMessageStatusUpdateWithContext(statusUpdate,
            conversationId: conversationId, recipientId: recipientId);
        Logger.success(
            ' Main:  Message status updated in ChatListProvider with enhanced lookup data: $status');

        // CRITICAL: Also update UnifiedChatProvider for real-time UI updates
        try {
          final unifiedChatSocketIntegration = UnifiedChatSocketIntegration();
          unifiedChatSocketIntegration.handleMessageStatusUpdate(
            messageId: messageId,
            status: parsedStatus,
            senderId: senderId,
          );
          Logger.success(
              ' Main:  UnifiedChatProvider updated for status: $status');
        } catch (e) {
          Logger.warning(
              ' Main:  Failed to update UnifiedChatProvider for status: $e');
        }
      } catch (e) {
        Logger.error(' Main:  Failed to process message status update: $e');
      }
    });
  });

  // Set up key exchange callbacks
  socketService.setOnKeyExchangeRequestReceived((data) {
    Logger.debug(' Main: 🔥 Key exchange request received from socket: $data');
    Logger.debug(' Main: 🔥 Callback is being triggered!');

    // Process the received key exchange request
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final keyExchangeProvider = Provider.of<KeyExchangeRequestProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Process the received key exchange request
        await keyExchangeProvider.processReceivedKeyExchangeRequest(data);
        Logger.success(' Main:  Key exchange request processed by provider');
        Logger.debug(
            ' Main: 📊 Provider received requests count: ${keyExchangeProvider.receivedRequests.length}');

        // No need to refresh - processReceivedKeyExchangeRequest already handles everything
        Logger.success(
            ' Main:  No refresh needed - processReceivedKeyExchangeRequest handles everything');

        // Update badge counts in real-time ONLY if user is not on K.Exchange screen
        final indicatorService = Provider.of<IndicatorService>(
            navigatorKey.currentContext!,
            listen: false);

        // Check if user is currently on K.Exchange screen (index 1)
        final isOnKeyExchangeScreen = _currentScreenIndex == 1;

        // Always update badge count using context-aware method
        // The indicator service will handle screen context internally
        // Only count pending/received requests that haven't been processed yet
        final pendingCount = keyExchangeProvider.receivedRequests
            .where((req) => req.status == 'received' || req.status == 'pending')
            .length;

        Logger.debug(' Main: 🔥 Updating badge count to: $pendingCount');
        Logger.debug(' Main: 🔥 Current screen index: $_currentScreenIndex');

        indicatorService.updateCountsWithContext(
            pendingKeyExchange: pendingCount);
        Logger.success(
            ' Main:  Badge count updated for new key exchange request using context-aware method');
      } catch (e) {
        Logger.error(' Main:  Failed to process key exchange request: $e');
      }
    });
  });

  socketService.setOnKeyExchangeDeclined((data) {
    Logger.debug(' Main: Key exchange declined from socket: $data');

    // Process the declined key exchange request
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final keyExchangeProvider = Provider.of<KeyExchangeRequestProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Process the declined key exchange request
        await keyExchangeProvider.handleKeyExchangeDeclined(data);
        Logger.success(' Main:  Key exchange decline processed by provider');

        // Update badge counts
        final indicatorService = Provider.of<IndicatorService>(
            navigatorKey.currentContext!,
            listen: false);

        // Recalculate the actual pending count after decline
        final keyExchangeProvider2 = Provider.of<KeyExchangeRequestProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // For decline, we need to update the sent requests count (decline affects sent requests)
        final pendingSentCount = keyExchangeProvider2.sentRequests
            .where((req) => req.status == 'pending' || req.status == 'sent')
            .length;

        // Also update received requests count
        final pendingReceivedCount = keyExchangeProvider2.receivedRequests
            .where((req) => req.status == 'received' || req.status == 'pending')
            .length;

        // Update badge with the total pending count
        final totalPendingCount = pendingSentCount + pendingReceivedCount;
        indicatorService.updateCountsWithContext(
            pendingKeyExchange: totalPendingCount);
        Logger.debug(
            '🔌 Main: ✅ Badge count updated for key exchange decline (sent: $pendingSentCount, received: $pendingReceivedCount, total: $totalPendingCount)');
      } catch (e) {
        Logger.error(' Main:  Failed to process key exchange decline: $e');
      }
    });
  });

  socketService.setOnKeyExchangeAccepted((data) {
    Logger.debug(' Main: Key exchange accepted from socket: $data');

    // Process the accepted key exchange request
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final keyExchangeProvider = Provider.of<KeyExchangeRequestProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Process the accepted key exchange request
        await keyExchangeProvider.handleKeyExchangeAccepted(data);
        Logger.success(' Main:  Key exchange acceptance processed by provider');

        // Update badge counts
        final indicatorService = Provider.of<IndicatorService>(
            navigatorKey.currentContext!,
            listen: false);

        // Recalculate the actual pending count after acceptance
        final keyExchangeProvider2 = Provider.of<KeyExchangeRequestProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // For acceptance, we need to update the sent requests count (acceptance affects sent requests)
        final pendingSentCount = keyExchangeProvider2.sentRequests
            .where((req) => req.status == 'pending' || req.status == 'sent')
            .length;

        // Also update received requests count
        final pendingReceivedCount = keyExchangeProvider2.receivedRequests
            .where((req) => req.status == 'received' || req.status == 'pending')
            .length;

        // Update badge with the total pending count
        final totalPendingCount = pendingSentCount + pendingReceivedCount;
        indicatorService.updateCountsWithContext(
            pendingKeyExchange: totalPendingCount);
        Logger.success(
            ' Main:  Badge count updated after key exchange accepted using context-aware method');
      } catch (e) {
        Logger.error(' Main:  Failed to process key exchange acceptance: $e');
      }
    });
  });

  // Handle key exchange response (when someone accepts/declines our request)
  socketService.setOnKeyExchangeResponse((data) {
    Logger.info(' Main: 🔍🔍 KEY EXCHANGE RESPONSE RECEIVED!');
    Logger.info(' Main: 🔍🔍 Full data: $data');
    Logger.info(' Main: 🔍🔍 Data type: ${data.runtimeType}');
    Logger.debug('🔌 Main: 🔍🔍🔍 Data keys: ${data.keys.toList()}');

    // Process the key exchange response using KeyExchangeService
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        Logger.info(' Main:  Processing key exchange response...');
        await KeyExchangeService.instance.processKeyExchangeResponse(data);
        Logger.success(' Main:  Key exchange response processed successfully');
      } catch (e) {
        Logger.error(' Main:  Failed to process key exchange response: $e');
        Logger.error(' Main:  Stack trace: ${StackTrace.current}');
      }
    });
  });

  // CRITICAL: Verify the callback was set up correctly
  Logger.info(
      ' Main:  Verifying onKeyExchangeResponse callback after setup...');
  if (socketService.onKeyExchangeResponse != null) {
    Logger.success(
        ' Main:  onKeyExchangeResponse callback successfully configured');
  } else {
    Logger.error(
        ' Main:  CRITICAL ERROR: onKeyExchangeResponse callback failed to set up!');
    // Try to set it up again as a fallback
    Logger.info(' Main:  Attempting fallback callback setup...');
    socketService.setOnKeyExchangeResponse((data) {
      Logger.debug(' Main: 🚨 FALLBACK: Key exchange response received: $data');
      // Process with KeyExchangeService
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await KeyExchangeService.instance.processKeyExchangeResponse(data);
          Logger.success(' Main:  Fallback callback processed successfully');
        } catch (e) {
          Logger.error(' Main:  Fallback callback failed: $e');
        }
      });
    });
    Logger.info(' Main:  Fallback callback setup completed');
  }

  // CRITICAL: Check all callback statuses for debugging
  Logger.info(' Main:  Checking all socket callback statuses...');
  final callbackStatus = socketService.getCallbackStatus();
  callbackStatus.forEach((callbackName, value) {
    // Handle both boolean and string values safely
    final isSet = value == true || (value is String && value.isNotEmpty);
    final status = isSet ? '✅ SET' : '❌ NULL';
    Logger.debug(' Main: $status - $callbackName');
  });
  Logger.info(' Main:  Callback status check completed');

  // CRITICAL: Handle user data exchange to complete key exchange flow
  socketService.setOnUserDataExchange((data) {
    Logger.debug(' Main: User data exchange received from socket: $data');
    Logger.info(' Main:  Data type: ${data.runtimeType}');
    Logger.debug('🔑 Main: 🔍 Data keys: ${data.keys.toList()}');

    // Process the user data exchange and create conversation
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        Logger.info(' Main:  Starting to process user data exchange...');

        // Extract the required parameters from the socket data
        final senderId = data['senderId']?.toString();
        final encryptedData = data['encryptedData']?.toString();
        final conversationId = data['conversationId']?.toString();

        if (senderId != null && encryptedData != null) {
          await KeyExchangeService.instance.processUserDataExchange(
            senderId: senderId,
            encryptedData: encryptedData,
            conversationId: conversationId,
          );
          Logger.success(' Main:  User data exchange processed successfully');
        } else {
          Logger.error(
              ' Main:  Invalid user data exchange data: senderId=$senderId, encryptedData=${encryptedData != null}');
        }

        // CRITICAL: Also update the conversation display name in ChatListProvider
        try {
          final senderId = data['senderId']?.toString();
          final displayName = data['displayName']?.toString() ?? 'Unknown User';

          if (senderId != null) {
            final chatListProvider = Provider.of<ChatListProvider>(
                navigatorKey.currentContext!,
                listen: false);

            // Update the conversation display name
            chatListProvider.handleUserDataExchange(senderId, displayName);
            Logger.success(
                ' Main:  Conversation display name updated via ChatListProvider');
          }
        } catch (e) {
          Logger.warning(
              ' Main:  Warning: Failed to update conversation display name: $e');
        }
      } catch (e) {
        Logger.error(' Main:  Failed to process user data exchange: $e');
        Logger.error(' Main:  Stack trace: ${StackTrace.current}');
      }
    });
  });

  // Handle conversation creation events from other users
  // REMOVED: This is now handled in ChatListProvider to avoid duplicate callbacks
  // socketService.setOnConversationCreated((data) {
  //   Logger.debug('💬 Main: Conversation created event received from socket: $data');

  //   // Process the conversation creation with requester's user data
  //   WidgetsBinding.instance.addPostFrameCallback((_) async {
  //     try {
  //       // This will handle the conversation creation on the acceptor's side
  //       // when they receive the conversation:created event with requester's user data
  //       await KeyExchangeService.instance.handleConversationCreated(data);
  //       Logger.success('💬 Main:  Conversation created event processed successfully');
  //     } catch (e) {
  //       Logger.error('💬 Main:  Failed to process conversation created event: $e');
  //     }
  //   });
  // });

  // CRITICAL: Connect KeyExchangeService with ChatListProvider for real-time UI updates
  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      KeyExchangeService.instance.setOnConversationCreated((conversation) {
        Logger.info(' Main:  Conversation created, updating UI...');

        // Create notification item for conversation created
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            final notificationService = LocalNotificationItemsService();
            await notificationService.createConversationCreatedNotification(
              conversationId: conversation.id,
              participantName: conversation.displayName ?? 'Unknown User',
              participantId: conversation.participant2Id,
            );
            Logger.success(
                ' Main:  Conversation created notification item created');
          } catch (e) {
            Logger.error(
                ' Main:  Failed to create conversation notification: $e');
          }
        });

        // Show push notification for conversation created
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            final localNotificationBadgeService =
                LocalNotificationBadgeService();
            await localNotificationBadgeService.showKerNotification(
              title: 'New Conversation',
              body:
                  'You can now chat with ${conversation.displayName ?? 'Unknown User'}',
              type: 'conversation_created',
              payload: {
                'type': 'conversation_created',
                'conversationId': conversation.id,
                'participantName': conversation.displayName ?? 'Unknown User',
                'participantId': conversation.participant2Id,
                'timestamp': DateTime.now().toIso8601String(),
              },
            );
            Logger.success(
                ' Main:  Conversation created push notification sent');
          } catch (e) {
            Logger.error(
                ' Main:  Failed to send conversation push notification: $e');
          }
        });

        // Update the ChatListProvider to refresh the UI
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            final chatListProvider = Provider.of<ChatListProvider>(
                navigatorKey.currentContext!,
                listen: false);

            // Add the new conversation to the provider
            chatListProvider.addConversation(conversation);
            Logger.success(
                ' Main:  Conversation added to ChatListProvider, UI will update');
          } catch (e) {
            Logger.error(' Main:  Failed to update ChatListProvider: $e');
          }
        });
      });

      // CRITICAL: Connect user data exchange to update conversation display names
      // This is now handled directly in the socket service callback to avoid conflicts
      Logger.info(
          ' Main:  User data exchange callback handled by socket service directly');

      Logger.success(
          ' Main:  KeyExchangeService conversation callback connected');
    } catch (e) {
      Logger.error(' Main:  Failed to connect KeyExchangeService callback: $e');
    }
  });

  // Handle message acknowledgment events
  socketService.setOnMessageAcked((messageId) {
    Logger.success(' Main: Message acknowledged: $messageId');

    // Update message status in ChatListProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Create a MessageStatusUpdate for acknowledgment
        final statusUpdate = MessageStatusUpdate(
          messageId: messageId,
          status: msg_status.MessageDeliveryStatus.sent,
          timestamp: DateTime.now(),
        );

        // Update the message status in the provider
        chatListProvider.processMessageStatusUpdate(statusUpdate);
        Logger.success(' Main:  Message status updated in ChatListProvider');
      } catch (e) {
        Logger.error(' Main:  Failed to update message status: $e');
      }
    });
  });

  // Handle key exchange revoked events
  socketService.setOnKeyExchangeRevoked((data) {
    Logger.debug(' Main: Key exchange revoked event received: $data');

    // Update badge counts for revoked requests
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final indicatorService = Provider.of<IndicatorService>(
            navigatorKey.currentContext!,
            listen: false);

        // Recalculate the actual pending count after revocation
        final keyExchangeProvider = Provider.of<KeyExchangeRequestProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Only count pending/received requests that haven't been processed yet
        final pendingCount = keyExchangeProvider.receivedRequests
            .where((req) => req.status == 'received' || req.status == 'pending')
            .length;

        indicatorService.updateCountsWithContext(
            pendingKeyExchange: pendingCount);
        Logger.success(
            ' Main:  Badge count updated after key exchange revoked using context-aware method');
      } catch (e) {
        Logger.error(' Main:  Failed to update badge count after revoke: $e');
      }
    });
  });

  // Handle user deleted events
  socketService.setOnUserDeleted((data) {
    Logger.info(' Main: User deleted event received: $data');

    // Handle user deletion cleanup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        Logger.success(' Main:  User deletion event processed');
        // Note: Conversation cleanup will be handled by the socket service
        // when it receives the user:deleted event
      } catch (e) {
        Logger.error(' Main:  Failed to handle user deletion: $e');
      }
    });
  });

  // Handle conversation created events from other users
  socketService.setOnConversationCreated((data) {
    Logger.debug(
        '💬 Main: Conversation created event received from socket: $data');

    // Process the conversation creation
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await KeyExchangeService.instance.handleConversationCreated(data);
        Logger.success(
            '💬 Main:  Conversation created event processed successfully');
      } catch (e) {
        Logger.error(
            '💬 Main:  Failed to process conversation created event: $e');
      }
    });
  });

  // 🆕 ADD THIS: Handle queued message events
  socketService.setOnMessageQueued((messageId, toUserId, fromUserId) {
    Logger.debug(
        '📬 Main: Message queued: $messageId from $fromUserId to $toUserId');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Create a MessageStatusUpdate for queued status
        final statusUpdate = MessageStatusUpdate(
          messageId: messageId,
          status: msg_status
              .MessageDeliveryStatus.sent, // Keep as sent until delivered
          timestamp: DateTime.now(),
          senderId: fromUserId,
        );

        chatListProvider.processMessageStatusUpdateWithContext(statusUpdate);
        Logger.success(
            '📬 Main:  Queued message status processed successfully');
      } catch (e) {
        Logger.error('📬 Main:  Failed to process queued message status: $e');
      }
    });
  });

  // Handle key exchange revocation events
  socketService.setOnKeyExchangeRevoked((data) {
    Logger.debug(' Main: Key exchange revoked: $data');

    // Update badge counts when key exchange is revoked
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final indicatorService = Provider.of<IndicatorService>(
            navigatorKey.currentContext!,
            listen: false);

        final keyExchangeProvider = Provider.of<KeyExchangeRequestProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Update counts using context-aware method
        // Only count pending/received requests that haven't been processed yet
        final pendingCount = keyExchangeProvider.receivedRequests
            .where((req) => req.status == 'received' || req.status == 'pending')
            .length;
        indicatorService.updateCountsWithContext(
            pendingKeyExchange: pendingCount);
        Logger.success(
            ' Main:  Badge count updated after key exchange revoked using context-aware method');
      } catch (e) {
        Logger.error(
            ' Main:  Failed to update badge count after revocation: $e');
      }
    });
  });

  // Handle user deletion events
  socketService.setOnUserDeleted((data) {
    Logger.info(' Main: User deleted event received: $data');

    // Handle user deletion - this might involve cleaning up local data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // This could involve:
        // 1. Removing conversations with the deleted user
        // 2. Cleaning up any cached data
        // 3. Updating UI to reflect the deletion

        Logger.info(' Main: User deletion event processed successfully');
      } catch (e) {
        Logger.error(' Main: Failed to process user deletion event: $e');
      }
    });
  });

  // Handle session registration confirmation
  socketService.setOnSessionRegistered((data) {
    Logger.success(' Main:  Session registered: ${data['sessionId']}');

    // Initialize presence management system for the new session
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final presenceManager = Provider.of<PresenceManager>(
            navigatorKey.currentContext!,
            listen: false);

        // Set up presence system for the new session
        presenceManager.onSessionRegistered();

        // Create welcome notification for the new user
        try {
          final sessionId = data['sessionId'] as String?;
          if (sessionId != null) {
            final notificationService = LocalNotificationItemsService();
            await notificationService.createWelcomeNotification(sessionId);
            Logger.success(
                ' Main:  Welcome notification created for new user: $sessionId');
          }
        } catch (e) {
          Logger.warning(' Main:  Failed to create welcome notification: $e');
        }

        Logger.success(' Main:  Presence system initialized for new session');
      } catch (e) {
        Logger.warning(' Main:  Failed to initialize presence system: $e');
      }
    });
  });
}

/// Parse message status string to MessageDeliveryStatus enum
msg_status.MessageDeliveryStatus _parseMessageStatus(String status) {
  switch (status.toLowerCase()) {
    case 'sending':
      return msg_status.MessageDeliveryStatus.pending;
    case 'sent':
      return msg_status.MessageDeliveryStatus.sent;
    case 'delivered':
      return msg_status.MessageDeliveryStatus.delivered;
    case 'read':
      return msg_status.MessageDeliveryStatus.read;
    case 'failed':
      return msg_status.MessageDeliveryStatus.failed;
    case 'deleted':
      return msg_status.MessageDeliveryStatus.failed; // Map deleted to failed
    default:
      return msg_status.MessageDeliveryStatus.sent; // Default to sent
  }
}

class SeChatApp extends StatelessWidget {
  const SeChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Attach navigator key for global UI access
    UIService().attachNavigatorKey(navigatorKey);

    // Set navigator key for notification deep linking
    // Navigator key is set globally, no need for NotificationManagerService

    return AppLifecycleHandler(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'SeChat',
        theme: ThemeData(
          colorScheme: ColorScheme.dark(
            brightness: Brightness.dark,
            primary: const Color(0xFFFF6B35), // Orange from designs
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFF2C2C2C), // Dark grey containers
            onPrimaryContainer: Colors.white,
            secondary: const Color(0xFF666666), // Medium grey
            onSecondary: Colors.white,
            secondaryContainer: const Color(0xFF1A1A1A), // Very dark grey
            onSecondaryContainer: Colors.white,
            surface: const Color(0xFF1E1E1E), // Dark surface
            onSurface: Colors.white,
            surfaceContainerHighest:
                const Color(0xFF2C2C2C), // Card backgrounds
            onSurfaceVariant: const Color(0xFFCCCCCC), // Text on cards
            outline: const Color(0xFF404040), // Borders
            error: const Color(0xFFFF5555),
            onError: Colors.white,
          ),
          scaffoldBackgroundColor: const Color(0xFF121212),
          useMaterial3: true,
          fontFamily: 'System',
        ),
        home: const AuthChecker(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

/// Generate consistent conversation ID that both users will have
/// This ensures messages appear in the same conversation for both users
/// Updated to match server's new consistent ID format
String _generateConsistentConversationId(String user1Id, String user2Id) {
  return ConversationIdGenerator.generateConsistentConversationId(
      user1Id, user2Id);
}

/// Ensure conversation exists before saving message
Future<void> _ensureConversationExists(
    String conversationId, String senderId, String senderName) async {
  try {
    // Get ChatListProvider to create/update conversation
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final chatListProvider = Provider.of<ChatListProvider>(
            navigatorKey.currentContext!,
            listen: false);

        // Create conversation if it doesn't exist
        await chatListProvider.ensureConversationExists(
            conversationId, senderId, senderName);
        Logger.success(' Main:  Conversation ensured: $conversationId');
      } catch (e) {
        Logger.error(' Main:  Failed to ensure conversation: $e');
      }
    });
  } catch (e) {
    Logger.error(' Main:  Error in _ensureConversationExists: $e');
  }
}

class AuthChecker extends StatefulWidget {
  const AuthChecker({super.key});

  @override
  State<AuthChecker> createState() => _AuthCheckerState();
}

class _AuthCheckerState extends State<AuthChecker> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthAndNavigate();
    });
  }

  Future<void> _checkAuthAndNavigate() async {
    // Remove native splash screen (only on mobile)
    if (!kIsWeb) {
      FlutterNativeSplash.remove();
    }

    // Small delay for smooth transition
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    try {
      final seSessionService = SeSessionService();
      final session = await seSessionService.loadSession();

      Logger.info(' AuthChecker: Session loaded: ${session != null}');
      if (session != null) {
        Logger.info(' AuthChecker: Session ID: ${session.sessionId}');
        Logger.info(' AuthChecker: Display Name: ${session.displayName}');
        Logger.info(
            ' AuthChecker: Has encrypted private key: ${session.encryptedPrivateKey.isNotEmpty}');
      }

      if (session != null) {
        // Session exists, check if user is currently logged in
        final isLoggedIn = await seSessionService.isUserLoggedIn();
        Logger.info(' AuthChecker: Is user logged in: $isLoggedIn');

        if (isLoggedIn) {
          // User is logged in, initialize socket services and go to main screen
          Logger.info(
              ' AuthChecker: User is logged in, initializing socket services...');

          // Initialize socket connection
          final socketService = SeSocketService.instance;
          await socketService.connect(session!.sessionId);

          Logger.success(
              '🔍 AuthChecker:  Socket service initialized successfully');

          Logger.info(
              ' AuthChecker: User is logged in, navigating to main screen');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => MainNavScreen()),
          );
        } else {
          // Session exists but user needs to login, go to login screen
          Logger.info(
              ' AuthChecker: Session exists but user needs login, navigating to login screen');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      } else {
        // No session exists, go to welcome screen
        Logger.info(
            ' AuthChecker: No session found, navigating to welcome screen');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        );
      }
    } catch (e) {
      // Handle any errors by showing welcome screen
      Logger.info(' AuthChecker: Error during auth check: $e');

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
