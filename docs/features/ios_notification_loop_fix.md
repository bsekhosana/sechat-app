# iOS Notification Loop Fix

## Problem

The app was experiencing an infinite notification loop on iOS where:
1. A message is sent locally
2. A local notification is shown
3. iOS processes the local notification and sends it back to Flutter
4. Flutter processes it as a remote notification and shows another local notification
5. This creates an infinite loop of notifications

## Root Cause Analysis

### 1. Local Notification Processing
The issue was in the `_handleMessageNotification` method in `SimpleNotificationService`. It was showing local notifications for every message, including messages from the current user.

### 2. iOS Notification Structure
iOS notifications have a different structure than Android, and the `fromLocalNotification` flag was not being properly detected because it was nested inside a JSON string in the `payload` field.

### 3. Sender ID Mismatch
The notification data contained `"sender_id": "current_user_id"` instead of the actual sender's ID, causing the system to think the message was from the current user.

### 4. Insufficient Deduplication
The iOS notification deduplication was not robust enough to prevent the same notification from being processed multiple times.

## Solution

### 1. Enhanced Local Notification Detection

Added multiple checks to detect and skip local notifications:

```dart
// Check for fromLocalNotification in nested JSON strings (iOS specific)
if (Platform.isIOS) {
  final payload = notificationData['payload'];
  if (payload is String) {
    try {
      final payloadData = jsonDecode(payload);
      if (payloadData is Map && payloadData['fromLocalNotification'] == true) {
        print('🔔 SimpleNotificationService: ℹ️ Skipping local notification (found in nested JSON)');
        return;
      }
    } catch (e) {
      // Ignore JSON parsing errors
    }
  }
}
```

### 2. Improved iOS Deduplication

Enhanced the iOS-specific deduplication to handle message notifications:

```dart
// Additional iOS deduplication: check for message_id in nested JSON
try {
  final payloadData = jsonDecode(payloadStr);
  if (payloadData is Map && payloadData['message_id'] != null) {
    final messageId = payloadData['message_id'];
    final messageNotificationId = 'ios_msg_$messageId';
    
    if (_processedNotifications.contains(messageNotificationId)) {
      print('🔔 SimpleNotificationService: ℹ️ Skipping duplicate iOS message notification: $messageId');
      return;
    }
    
    _processedNotifications.add(messageNotificationId);
  }
} catch (e) {
  // Ignore JSON parsing errors
}
```

### 3. Sender ID Validation

Added checks to prevent processing notifications from the current user:

```dart
// Additional check for iOS notifications with "current_user_id" sender
if (Platform.isIOS && senderId == 'current_user_id') {
  print('🔔 SimpleNotificationService: ℹ️ Skipping iOS notification with current_user_id sender');
  return;
}
```

### 4. Message Notification Logic Fix

Modified the message notification handling to skip local notifications for messages from the current user:

```dart
// CRITICAL FIX: Don't show local notifications for messages from the current user
// This prevents the infinite notification loop
final currentUserId = SeSessionService().currentSessionId;
if (currentUserId != null && senderId == currentUserId) {
  print('🔔 SimpleNotificationService: ℹ️ Skipping local notification for message from self');
  return;
}
```

## Implementation Details

### Notification Processing Flow

1. **Initial Check**: Skip if `fromLocalNotification` is true
2. **iOS JSON Check**: Parse nested JSON payload to check for `fromLocalNotification` flag
3. **iOS Deduplication**: Use message ID for additional deduplication
4. **Sender Validation**: Skip notifications from current user or with `current_user_id`
5. **Message Processing**: Only process valid remote messages

### Deduplication Strategy

- **Payload Hash**: Generate unique ID based on notification payload content
- **Message ID**: Additional deduplication using message ID for message notifications
- **Sender Check**: Skip notifications from the current user
- **Memory Management**: Limit processed notifications to prevent memory buildup

## Testing

The fix should be tested by:

1. **Sending Messages**: Verify that sending a message doesn't trigger infinite notifications
2. **Receiving Messages**: Ensure that legitimate remote messages are still processed
3. **iOS Behavior**: Test specifically on iOS devices to confirm the loop is broken
4. **Notification Count**: Verify that only one notification is shown per message

## Expected Results

After implementing this fix:

- ✅ No more infinite notification loops on iOS
- ✅ Local notifications are properly detected and skipped
- ✅ Remote messages are still processed correctly
- ✅ Message delivery receipts work without loops
- ✅ iOS notification deduplication is robust

## Future Improvements

1. **AirNotifier Server**: Investigate why `sender_id` is being set to `current_user_id`
2. **Notification Structure**: Standardize notification payload structure across platforms
3. **Testing**: Add automated tests for notification loop scenarios
4. **Monitoring**: Add logging to detect potential notification loops early
