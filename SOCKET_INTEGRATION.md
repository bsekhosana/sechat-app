# Socket.IO Integration for SeChat Flutter App

## Overview

The SeChat Flutter app now integrates with the Socket.IO server for real-time messaging, online status, and user presence. This integration replaces the previous WebSocket implementation with a more robust Socket.IO solution.

## Architecture

### Socket.IO Service (`lib/core/services/socket_service.dart`)

The main Socket.IO service handles:
- Connection management with automatic reconnection
- User authentication using device ID and user ID
- Real-time message sending and receiving
- Online/offline status updates
- Typing indicators
- Error handling and logging

### Chat Provider Integration (`lib/features/chat/providers/chat_provider.dart`)

The ChatProvider has been updated to:
- Use Socket.IO for real-time messaging
- Handle incoming messages from Socket.IO
- Update user online status in real-time
- Fall back to REST API when Socket.IO is unavailable

## Features

### Real-time Messaging
- Messages are sent and received in real-time via Socket.IO
- Automatic fallback to REST API if Socket.IO is unavailable
- Message status updates (sent, delivered, read)

### Online Status
- Real-time online/offline status updates
- Last seen timestamps
- Visual indicators in chat list and chat screens

### Connection Management
- Automatic reconnection with exponential backoff
- Connection status indicators
- Manual connection/disconnection for testing

## Configuration

### Server Connection
The app connects to the Socket.IO server at:
- **Production**: `https://sechat.strapblaque.com:3001`
- **Development**: `https://sechat.strapblaque.com:3001`

### Authentication
Users are authenticated using:
- `device_id`: Stored in secure storage
- `user_id`: Stored in secure storage

## Testing

### Socket.IO Test Screen
Access the test screen via:
1. Open the app
2. Go to Settings
3. Tap "Socket.IO Test"

The test screen provides:
- Connection status display
- Manual connect/disconnect buttons
- Test message sending
- Real-time event logging

### Testing Real-time Messaging
1. Open the test screen on two devices
2. Connect both devices
3. Send test messages
4. Verify messages appear in real-time

## Implementation Details

### Message Format
Socket.IO messages use the following format:
```json
{
  "senderId": 123,
  "receiverId": 456,
  "message": "Hello world",
  "messageType": "text"
}
```

### Event Handling
The app listens for these Socket.IO events:
- `authenticated`: Successful authentication
- `auth_error`: Authentication failure
- `new_message`: Incoming message
- `message_sent`: Message sent confirmation
- `user_online`: User came online
- `user_offline`: User went offline
- `user_typing`: Typing indicator

### Error Handling
- Connection failures are handled gracefully
- Automatic reconnection with exponential backoff
- Fallback to REST API when Socket.IO is unavailable
- User-friendly error messages

## Troubleshooting

### Common Issues

1. **Connection Failed**
   - Check if the Socket.IO server is running
   - Verify the server URL is correct
   - Check network connectivity

2. **Authentication Failed**
   - Ensure device_id and user_id are stored in secure storage
   - Verify user exists in the database
   - Check server logs for authentication errors

3. **Messages Not Received**
   - Check if both users are authenticated
   - Verify Socket.IO connection is active
   - Check server logs for message delivery errors

### Debug Logging
Enable debug logging by checking the console output for:
- `🔌 Socket.IO:` prefixed messages
- `📱 ChatProvider:` prefixed messages

## Future Enhancements

1. **Message Encryption**: Implement end-to-end encryption for messages
2. **File Sharing**: Add support for file and media sharing
3. **Group Chats**: Extend to support group conversations
4. **Push Notifications**: Integrate with push notification service
5. **Message Sync**: Implement message synchronization across devices

## Dependencies

The Socket.IO integration requires:
- `socket_io_client: ^3.1.2`
- `flutter_secure_storage: ^9.2.4`
- `provider: ^6.1.5`

## Security Considerations

1. **Authentication**: All Socket.IO connections require valid device_id and user_id
2. **Message Validation**: Messages are validated on both client and server
3. **Connection Security**: Uses HTTPS/WSS for secure communication
4. **Data Storage**: Sensitive data stored in secure storage

## Performance

1. **Connection Pooling**: Efficient connection management
2. **Message Batching**: Messages are batched when possible
3. **Automatic Reconnection**: Minimal disruption during network issues
4. **Memory Management**: Proper cleanup of Socket.IO resources 