# Message Encryption Fix

## Problem

Messages were being sent with unencrypted data, causing decryption errors on the recipient side. The logs showed:

```
Failed to decrypt data: FormatException: Unexpected extension byte (at offset 0)
```

This happened because raw text was being passed as the `encryptedData` parameter instead of properly encrypted data.

## Root Cause Analysis

The issue was identified in both `ChatProvider` and `SessionChatProvider` classes:

1. In `ChatProvider.sendTextMessage()`, the raw text message was passed directly as the `encryptedData` parameter:
   ```dart
   encryptedData: text, // Will be encrypted by AirNotifier server
   ```

2. In `SessionChatProvider.sendMessage()`, the same issue existed:
   ```dart
   encryptedData: content, // For now, send content directly (will be encrypted by AirNotifier server)
   ```

The comment suggests that the AirNotifier server would handle encryption, but this is incorrect. The client is responsible for encrypting the data before sending it to the server.

## Solution

We implemented a comprehensive fix to ensure all message payloads are properly encrypted:

1. **Proper Message Structure**: Created a structured message data object with all necessary fields:
   ```dart
   final messageData = {
     'type': 'message',
     'message_id': messageId,
     'sender_id': senderId,
     'sender_name': senderName,
     'message': text,
     'conversation_id': conversationId,
     'timestamp': DateTime.now().millisecondsSinceEpoch,
   };
   ```

2. **Client-Side Encryption**: Used `EncryptionService.createEncryptedPayload()` to properly encrypt the message data:
   ```dart
   final encryptedPayload = await EncryptionService.createEncryptedPayload(
     messageData, 
     recipientId
   );
   ```

3. **Proper Payload Transmission**: Sent the encrypted data and checksum in the notification payload:
   ```dart
   encryptedData: encryptedPayload['data'] as String,
   checksum: encryptedPayload['checksum'] as String,
   ```

## Implementation Details

### 1. ChatProvider Fix

```dart
// Create message data for encryption
final messageData = {
  'type': 'message',
  'message_id': message?.id ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
  'sender_id': _getCurrentUserId(),
  'sender_name': _getCurrentUserId() ?? 'Anonymous User',
  'message': text,
  'conversation_id': _conversationId!,
  'timestamp': DateTime.now().millisecondsSinceEpoch,
};

// Create properly encrypted payload using EncryptionService
final encryptedPayload = await EncryptionService.createEncryptedPayload(
  messageData, 
  _recipientId!
);

// Send using the encrypted payload
final success = await SimpleNotificationService.instance.sendEncryptedMessage(
  recipientId: _recipientId!,
  senderName: _getCurrentUserId() ?? 'Anonymous User',
  message: text,
  conversationId: _conversationId!,
  encryptedData: encryptedPayload['data'] as String,
  checksum: encryptedPayload['checksum'] as String,
  messageId: message?.id ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
);
```

### 2. SessionChatProvider Fix

```dart
// Create message data for encryption
final messageData = {
  'type': 'message',
  'message_id': messageId,
  'sender_id': _airNotifier.currentUserId ?? '',
  'sender_name': _airNotifier.currentUserId ?? 'Anonymous User',
  'message': content,
  'conversation_id': recipientId,
  'timestamp': DateTime.now().millisecondsSinceEpoch,
};

// Create properly encrypted payload using EncryptionService
final encryptedPayload = await EncryptionService.createEncryptedPayload(
  messageData, 
  recipientId
);

// Send message via SimpleNotificationService with full encryption
final success = await SimpleNotificationService.instance.sendEncryptedMessage(
  recipientId: recipientId,
  senderName: _airNotifier.currentUserId ?? 'Anonymous User',
  message: content,
  conversationId: recipientId,
  encryptedData: encryptedPayload['data'] as String,
  checksum: encryptedPayload['checksum'] as String,
  messageId: messageId,
);
```

## Encryption Process

The `EncryptionService.createEncryptedPayload()` method:

1. Takes a JSON-serializable map and recipient ID
2. Uses AES-256-CBC/PKCS7 encryption to encrypt the data
3. Creates an envelope with encryption metadata
4. Generates a checksum for integrity verification
5. Returns the encrypted data and checksum

## Testing

The fix was tested by sending messages between devices and verifying:

1. Messages are properly encrypted before sending
2. Messages are successfully decrypted on the recipient side
3. Decrypted messages match the original content
4. No decryption errors occur

## Future Improvements

1. **Encryption Consistency**: Review all notification types to ensure they use the same encryption pattern
2. **Error Handling**: Add better error handling for encryption/decryption failures
3. **Key Management**: Improve key exchange and management for better security
4. **Encryption Performance**: Optimize encryption for large messages or media content
