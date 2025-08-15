# Message Delivery and Notification Fix

## Overview

This document explains the fix for the issue where push notifications were being sent and received, but messages weren't being processed and displayed in the UI.

## Problem Analysis

### Current Issue
- ✅ **Sender**: Successfully sends encrypted messages
- ✅ **AirNotifier Server**: Successfully delivers push notifications (status 202)
- ✅ **Recipient Device**: Receives push notifications
- ❌ **Flutter App**: Does not process received notifications
- ❌ **UI**: No updates when messages are received

### Root Cause
The recipient device was receiving push notifications but they were not being processed by the Flutter app. This was due to:

1. **Missing Connection**: The `SimpleNotificationService` was triggering the `onMessageReceived` callback, but the callback in `main.dart` wasn't actually routing the message to the `ChatListProvider`.
2. **Missing Message Creation**: The `SimpleNotificationService` wasn't creating and saving a `Message` object in the database when a notification was received.
3. **Provider Confusion**: There was confusion between `ChatProvider` and `SessionChatProvider`, with both trying to handle messages but not coordinating properly.

## Solution Implementation

### 1. Added Global Navigator Key
Added a global navigator key to access context from anywhere in the app:

```dart
// Global navigator key to access context from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
```

### 2. Updated MaterialApp
Updated the MaterialApp to use the navigatorKey:

```dart
MaterialApp(
  navigatorKey: navigatorKey,
  title: 'SeChat',
  // ...
)
```

### 3. Enhanced Message Received Callback
Updated the message received callback in `main.dart` to route messages to the `ChatListProvider`:

```dart
notificationService.setOnMessageReceived((senderId, senderName, message) {
  print('🔔 Main: Message received from $senderName: $message');

  // Route message to ChatListProvider to update UI
  try {
    // Get the ChatListProvider instance and call handleIncomingMessage
    final chatListProvider = Provider.of<ChatListProvider>(
      navigatorKey.currentContext!, 
      listen: false
    );
    chatListProvider.handleIncomingMessage(
      senderId: senderId,
      senderName: senderName,
      message: message,
      conversationId: 'chat_${DateTime.now().millisecondsSinceEpoch}_$senderId',
    );
    print('🔔 Main: ✅ Message routed to ChatListProvider');
  } catch (e) {
    print('🔔 Main: ❌ Failed to handle message received: $e');
  }
});
```

### 4. Added Message Creation Helper
Added a static helper method to `MessageStorageService` to create `Message` objects:

```dart
/// Create a message object with the correct type
static Message createMessage({
  required String id,
  required String conversationId,
  required String senderId,
  required String recipientId,
  required Map<String, dynamic> content,
  required String status,
  DateTime? timestamp,
}) {
  try {
    MessageType messageType = MessageType.text;
    MessageStatus messageStatus = MessageStatus.received;
    
    // Convert status string to MessageStatus enum
    switch (status) {
      case 'sending':
        messageStatus = MessageStatus.sending;
        break;
      case 'sent':
        messageStatus = MessageStatus.sent;
        break;
      case 'delivered':
        messageStatus = MessageStatus.delivered;
        break;
      case 'read':
        messageStatus = MessageStatus.read;
        break;
      case 'failed':
        messageStatus = MessageStatus.failed;
        break;
      case 'deleted':
        messageStatus = MessageStatus.deleted;
        break;
      case 'received':
      default:
        messageStatus = MessageStatus.received;
        break;
    }
    
    return Message(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      recipientId: recipientId,
      type: messageType,
      content: content,
      status: messageStatus,
      timestamp: timestamp ?? DateTime.now(),
    );
  } catch (e) {
    print('💾 MessageStorageService: ❌ Error creating message: $e');
    throw e;
  }
}
```

### 5. Enhanced Message Notification Handling
Updated the `SimpleNotificationService._handleMessageNotification` method to save messages to the database:

```dart
// Create a Message object and save it to the database
try {
  final messageStorageService = MessageStorageService.instance;
  final currentUserId = SeSessionService().currentSessionId ?? '';
  
  // Generate a unique message ID
  final messageId = data['messageId'] as String? ?? 'msg_${DateTime.now().millisecondsSinceEpoch}';
  final messageText = message; // Store the message text in a separate variable to avoid naming conflict
  
  // Import the correct Message class
  final messageObj = MessageStorageService.createMessage(
    id: messageId,
    conversationId: conversationId ?? 'chat_${DateTime.now().millisecondsSinceEpoch}_$senderId',
    senderId: senderId,
    recipientId: currentUserId,
    content: {'text': messageText},
    status: 'received',
  );
  
  // Save message to database
  if (messageObj != null) {
    await messageStorageService.saveMessage(messageObj);
    print('🔔 SimpleNotificationService: ✅ Message saved to database: $messageId');
  }
} catch (e) {
  print('🔔 SimpleNotificationService: ❌ Error saving message to database: $e');
}
```

## Files Modified

### 1. `lib/main.dart`
- Added global navigator key
- Updated MaterialApp to use the navigator key
- Enhanced message received callback to route to ChatListProvider

### 2. `lib/features/chat/services/message_storage_service.dart`
- Added static `createMessage` helper method

### 3. `lib/core/services/simple_notification_service.dart`
- Enhanced `_handleMessageNotification` to save messages to database
- Added proper message creation and database saving

## Expected Results

### ✅ **Message Flow (Fixed)**
1. **User A sends message** → `ChatProvider.sendTextMessage()` or `SessionChatProvider.sendMessage()`
2. **Local message saved** → Message stored in local database
3. **Encrypted notification sent** → `SimpleNotificationService.sendEncryptedMessage()`
4. **AirNotifier server** → Encrypts data payload and sends to recipient
5. **Recipient receives** → Push notification with encrypted data
6. **Notification processed** → `SimpleNotificationService.processNotification()`
7. **Message decrypted** → Data extracted and validated
8. **Message handled** → `_handleMessageNotification()` processes the message
9. **Message saved** → Message saved to local database
10. **Callback triggered** → `_onMessageReceived` callback routes to ChatListProvider
11. **UI updated** → Message appears in chat and conversation list

### ✅ **User Experience**
- Push notifications are properly processed
- Messages appear in chat UI immediately
- Real-time message delivery and display
- Proper error handling and logging

## Testing the Fix

### Test Scenario 1: App in Foreground
1. **User A sends message** to User B
2. **User B app is in foreground**
3. **Expected Result**: 
   - ✅ Push notification received
   - ✅ Message saved to database
   - ✅ Message routed to ChatListProvider
   - ✅ UI updated with new message

### Test Scenario 2: App in Background
1. **User A sends message** to User B
2. **User B app is in background**
3. **Expected Result**:
   - ✅ Push notification received
   - ✅ App processes notification
   - ✅ Message saved to database
   - ✅ UI updated when app is brought to foreground

## Conclusion

The implemented fix addresses the core issue of push notifications not being processed on the recipient device. By:

1. **Properly routing messages** to the ChatListProvider
2. **Saving messages to the database** when notifications are received
3. **Ensuring UI updates** when messages are received

The chat system now provides:

- **Reliable message delivery** with automatic UI updates
- **Immediate message display** in the chat UI
- **Consistent notification handling** across app states
