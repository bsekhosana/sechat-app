# Message Field Names Fix

## Problem

After implementing proper encryption for messages, we noticed that the decrypted message data was not being correctly processed. The logs showed:

```
flutter: 🔔 SimpleNotificationService: ⚠️ Missing fields in message notification data
flutter: 🔔 SimpleNotificationService: senderId: null, senderName: null, message: Bobby
flutter: 🔔 SimpleNotificationService: ❌ Invalid message notification data - missing required fields
```

The issue was that the decrypted message data contained fields with snake_case naming (`sender_id`, `sender_name`), but the code was looking for camelCase field names (`senderId`, `senderName`).

## Solution

We need to modify the `_handleMessageNotification` method in `SimpleNotificationService` to check for both naming conventions:

```dart
// In the encrypted message handling section:
message = data['message'] as String?;
        
// Check for both camelCase and snake_case field names (for compatibility)
senderId = data['senderId'] as String? ?? data['sender_id'] as String?;
senderName = data['senderName'] as String? ?? data['sender_name'] as String?;
conversationId = data['conversationId'] as String? ?? data['conversation_id'] as String?;
```

## Implementation

1. First, we need to modify the `_handleMessageNotification` method to check for both naming conventions.
2. We also need to ensure that the message field is extracted correctly from the decrypted data.

## Testing

The fix should be tested by sending messages between devices and verifying:

1. Messages are properly decrypted
2. The sender information is correctly extracted
3. Messages are saved to the database
4. Messages appear in the UI

## Future Improvements

1. **Standardize Field Names**: Consider standardizing on either camelCase or snake_case throughout the application to avoid similar issues in the future.
2. **Field Mapping**: Implement a more robust field mapping system that can handle different naming conventions.
3. **Schema Validation**: Add schema validation to ensure the decrypted data matches the expected format.
