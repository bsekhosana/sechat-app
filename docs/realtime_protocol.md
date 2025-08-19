# SeChat Realtime Protocol

## Overview
This document defines the realtime communication protocol between SeChat clients and the socket server. The protocol is designed for reliability, low latency, and WhatsApp-style user experience.

## Protocol Version
**Current**: v2.0 (Breaking changes from v1.0)

## Event Format
All events follow the pattern: `category:action` (e.g., `presence:online`, `typing:start`)

## Core Events

### Presence Management

#### `presence:update`
**Direction**: Client → Server  
**Purpose**: Update user's online/offline status

```json
{
  "type": "presence:update",
  "sessionId": "session_1234567890-abc123",
  "isOnline": true,
  "timestamp": "2025-08-19T20:00:00.000Z",
  "deviceInfo": {
    "platform": "ios|android",
    "version": "1.0.0"
  }
}
```

**Server Response**: Broadcasts `presence:update` to all other users

#### `presence:ping`
**Direction**: Client → Server  
**Purpose**: Keepalive ping to maintain presence

```json
{
  "type": "presence:ping",
  "sessionId": "session_1234567890-abc123",
  "timestamp": "2025-08-19T20:00:00.000Z"
}
```

**Server Response**: None (silent acknowledgment)

#### `presence:update` (Server → Client)
**Direction**: Server → Client  
**Purpose**: Notify client of peer presence changes

```json
{
  "type": "presence:update",
  "sessionId": "session_1234567890-abc123",
  "isOnline": false,
  "timestamp": "2025-08-19T20:00:00.000Z"
}
```

### Typing Indicators

#### `typing`
**Direction**: Client → Server  
**Purpose**: Send typing start/stop indicator

```json
{
  "type": "typing",
  "conversationId": "chat_1234567890-abc123",
  "fromUserId": "session_1234567890-abc123",
  "toUserIds": ["session_0987654321-def456"],
  "isTyping": true,
  "timestamp": "2025-08-19T20:00:00.000Z"
}
```

**Server Response**: Broadcasts `typing:update` to specified recipients

#### `typing:update` (Server → Client)
**Direction**: Server → Client  
**Purpose**: Notify client of peer typing status

```json
{
  "type": "typing:update",
  "conversationId": "chat_1234567890-abc123",
  "fromUserId": "session_1234567890-abc123",
  "isTyping": true,
  "timestamp": "2025-08-19T20:00:00.000Z"
}
```

### Message Delivery

#### `message:send`
**Direction**: Client → Server  
**Purpose**: Send a new message

```json
{
  "type": "message:send",
  "messageId": "msg_1234567890-abc123",
  "conversationId": "chat_1234567890-abc123",
  "fromUserId": "session_1234567890-abc123",
  "toUserIds": ["session_0987654321-def456"],
  "body": "Hello, how are you?",
  "timestamp": "2025-08-19T20:00:00.000Z",
  "metadata": {
    "encrypted": true,
    "version": "1.0"
  }
}
```

**Server Response**: Sends `message:acked` to sender, then `message:delivered` to recipients

#### `message:acked`
**Direction**: Server → Client  
**Purpose**: Acknowledge message receipt (1 tick)

```json
{
  "type": "message:acked",
  "messageId": "msg_1234567890-abc123",
  "timestamp": "2025-08-19T20:00:00.000Z"
}
```

#### `message:delivered`
**Direction**: Server → Client  
**Purpose**: Confirm message delivery to recipient (2 ticks)

```json
{
  "type": "message:delivered",
  "messageId": "msg_1234567890-abc123",
  "timestamp": "2025-08-19T20:00:00.000Z"
}
```

#### `message:read`
**Direction**: Server → Client  
**Purpose**: Confirm message read by recipient (2 blue ticks)

```json
{
  "type": "message:read",
  "messageId": "msg_1234567890-abc123",
  "timestamp": "2025-08-19T20:00:00.000Z"
}
```

### Receipts

#### `receipt:delivered`
**Direction**: Client → Server  
**Purpose**: Send delivery receipt

```json
{
  "type": "receipt:delivered",
  "messageId": "msg_1234567890-abc123",
  "fromUserId": "session_0987654321-def456",
  "toUserId": "session_1234567890-abc123",
  "timestamp": "2025-08-19T20:00:00.000Z"
}
```

#### `receipt:read`
**Direction**: Client → Server  
**Purpose**: Send read receipt

```json
{
  "type": "receipt:read",
  "messageId": "msg_1234567890-abc123",
  "fromUserId": "session_0987654321-def456",
  "toUserId": "session_1234567890-abc123",
  "timestamp": "2025-08-19T20:00:00.000Z"
}
```

## Legacy Events (Deprecated)

### `typing_indicator` (v1.0)
**Status**: Deprecated, replaced by `typing`  
**Migration**: Update clients to use new format

### `online_status_update` (v1.0)
**Status**: Deprecated, replaced by `presence:update`  
**Migration**: Update clients to use new format

### `send_message` (v1.0)
**Status**: Deprecated, replaced by `message:send`  
**Migration**: Update clients to use new format

## Timing & Reliability

### Presence
- **Keepalive**: Every 25 seconds when online
- **Server TTL**: 35 seconds (server evicts after this)
- **Background Delay**: 5 seconds to handle quick transitions

### Typing
- **Debounce**: 250ms before sending to server
- **Heartbeat**: Every 3 seconds while typing
- **Auto-stop**: 700ms after last input activity
- **Server Timeout**: 4 seconds (server auto-stops after this)

### Messages
- **Ack Timeout**: 10 seconds for server acknowledgment
- **Retry Logic**: Exponential backoff with 20% jitter, max 3 attempts
- **State Machine**: localQueued → socketSent → serverAcked → delivered → read

## Error Handling

### Client Errors
- **Invalid Event**: Server responds with `error` event
- **Missing Fields**: Server responds with `error` event
- **Rate Limiting**: Server responds with `error` event

### Server Errors
- **Internal Error**: Server responds with `error` event
- **Service Unavailable**: Server responds with `error` event
- **Maintenance Mode**: Server responds with `maintenance` event

### Error Event Format
```json
{
  "type": "error",
  "code": "INVALID_EVENT",
  "message": "Invalid event type",
  "details": {
    "event": "invalid_event",
    "timestamp": "2025-08-19T20:00:00.000Z"
  }
}
```

## Migration Guide

### For Clients (v1.0 → v2.0)
1. Replace `typing_indicator` with `typing`
2. Replace `online_status_update` with `presence:update`
3. Replace `send_message` with `message:send`
4. Handle new delivery states (acked, delivered, read)
5. Implement receipt sending (delivered, read)

### For Server (v1.0 → v2.0)
1. Add new event handlers
2. Implement presence TTL and keepalive
3. Implement typing heartbeat and auto-stop
4. Implement message delivery state machine
5. Maintain backward compatibility during transition

## Testing

### Test Scenarios
1. **Presence**: App foreground/background, network disconnection
2. **Typing**: Debouncing, heartbeat, auto-stop, multiple users
3. **Messages**: Delivery states, retry logic, reconnection
4. **Edge Cases**: Rapid state changes, network instability

### Performance Targets
- **Typing Latency**: <250ms
- **Presence Updates**: <1 second
- **Message Delivery**: <500ms
- **Reconnection**: <2 seconds

---
**Version**: 2.0  
**Last Updated**: $(date)  
**Status**: Active Development
