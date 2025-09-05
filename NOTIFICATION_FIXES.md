# Notification Fixes - iOS Background & Duplicate Issues

## Problems Fixed

### 1. **iOS Background Notifications Not Working**
- **Issue**: iOS notifications not showing when app is in background
- **Root Cause**: iOS notification settings were not properly configured for background display
- **Solution**: Enhanced iOS notification settings with proper interruption level and badge support

### 2. **Duplicate Notifications**
- **Issue**: Receiving 2 notifications for each message
- **Root Cause**: Both `UnifiedMessageService` and `main.dart` were calling notification services
- **Solution**: Removed duplicate notification call from `UnifiedMessageService`

### 3. **Notification Body Showing Actual Message**
- **Issue**: Background notifications showing decrypted message content instead of "encrypted message"
- **Root Cause**: Message decryption was happening regardless of app state
- **Solution**: Added background state check to only decrypt messages in foreground

### 4. **Session ID Instead of Contact Name**
- **Issue**: Notification title showing session ID instead of contact display name
- **Root Cause**: Contact name resolution was working but title format was incorrect
- **Solution**: Enhanced title format and improved contact name resolution

## Technical Changes Made

### 1. Fixed Duplicate Notifications

**File**: `lib/core/services/unified_message_service.dart`

**Change**: Commented out duplicate notification call
```dart
// Notification is now handled in main.dart to avoid duplicates
// await MessageNotificationService.instance.showMessageNotification(
//   messageId: messageId,
//   senderName: senderName,
//   messageContent: decryptedBody,
//   conversationId: consistentConversationId,
//   isEncrypted: isEncrypted,
// );
Logger.debug(
    '📤 UnifiedMessageService:  Notification handled by main.dart for message: $messageId from: $senderName');
```

### 2. Fixed Notification Body Content

**File**: `lib/main.dart`

**Change**: Added background state check for message decryption
```dart
// Check if app is in background - if so, show encrypted message
final isAppInBackground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused ||
    WidgetsBinding.instance.lifecycleState == AppLifecycleState.detached;

String notificationBody = '[Encrypted Message]';

// Only decrypt message for foreground notifications
if (!isAppInBackground && message.length > 100 && message.contains('eyJ')) {
  // ... decryption logic ...
}
```

### 3. Enhanced iOS Notification Settings

**File**: `lib/features/notifications/services/local_notification_badge_service.dart`

**Change**: Improved iOS notification configuration
```dart
final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
  presentAlert: true,
  presentBadge: true, // Enable badge for iOS
  presentSound: true,
  interruptionLevel: InterruptionLevel.active, // Ensure notification is shown
);
```

### 4. Improved Notification Title Format

**File**: `lib/main.dart`

**Change**: Enhanced title format with better contact name resolution
```dart
await localNotificationBadgeService.showMessageNotification(
  title: 'New message from $contactName',
  body: notificationBody,
  type: 'message_received',
  payload: {
    'messageId': messageId,
    'senderId': senderId,
    'conversationId': actualConversationId,
    'timestamp': DateTime.now().toIso8601String(),
  },
);
```

### 5. Added Debugging for iOS Notifications

**File**: `lib/features/notifications/services/local_notification_badge_service.dart`

**Change**: Added comprehensive logging for debugging
```dart
// Log notification details for debugging
Logger.debug('📱 LocalNotificationBadgeService: 🔍 Notification title: $title');
Logger.debug('📱 LocalNotificationBadgeService: 🔍 Notification body: $body');
Logger.debug('📱 LocalNotificationBadgeService: 🔍 Notification type: $type');
```

## Expected Behavior After Fixes

### ✅ **iOS Background Notifications**
- **Before**: No notifications when app is in background
- **After**: Notifications work properly in background with proper iOS settings

### ✅ **Single Notification Per Message**
- **Before**: 2 notifications for each message
- **After**: 1 notification per message

### ✅ **Proper Notification Content**
- **Foreground**: Shows decrypted message content
- **Background**: Shows "[Encrypted Message]" for security

### ✅ **Contact Name in Title**
- **Before**: "session_1757021548155-w0dym5gp-8nc-fhr-sth-awze5wx8fuu"
- **After**: "New message from ContactName"

## Testing Scenarios

### 1. **iOS Background Test**
- Put app in background
- Send message from another device
- **Expected**: Single notification with "New message from ContactName" and "[Encrypted Message]"

### 2. **iOS Foreground Test**
- Keep app in foreground
- Send message from another device
- **Expected**: Single notification with "New message from ContactName" and actual message content

### 3. **Android Background Test**
- Put app in background
- Send message from another device
- **Expected**: Single notification with proper title and encrypted message body

### 4. **Contact Name Resolution Test**
- Send message from known contact
- **Expected**: Notification title shows contact display name, not session ID

## Debugging Information

The enhanced logging will show:
- App background state
- Notification title and body content
- Contact name resolution process
- iOS-specific notification settings

## Files Modified

1. **`lib/core/services/unified_message_service.dart`** - Removed duplicate notification call
2. **`lib/main.dart`** - Enhanced notification logic with background state check
3. **`lib/features/notifications/services/local_notification_badge_service.dart`** - Improved iOS settings and debugging

## Notes

- **Security**: Background notifications now properly show "[Encrypted Message]" instead of decrypted content
- **Performance**: Removed duplicate notification calls to improve performance
- **iOS Compatibility**: Enhanced iOS notification settings for better background support
- **Debugging**: Added comprehensive logging to help identify any remaining issues
