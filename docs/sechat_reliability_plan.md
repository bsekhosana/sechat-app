# SeChat Realtime Reliability Plan

## Overview
This document tracks the implementation of robust realtime features for SeChat, focusing on presence, typing indicators, and message delivery reliability.

## Goals
- **Presence**: Robust online/offline status with TTL and keepalive
- **Typing Indicators**: Debounced, heartbeat-based typing with auto-stop
- **Message Delivery**: WhatsApp-style delivery states with retry logic
- **Socket Reliability**: Survive reconnects, backgrounding, and network issues

## Implementation Status

### ✅ Phase 1: Core Realtime Services (COMPLETED)
- [x] `RealtimeLogger` - Structured logging with feature tags and counters
- [x] `PresenceService` - App lifecycle-aware presence with 25s keepalive, 35s TTL
- [x] `TypingService` - Debounced typing with 3s heartbeat, 700ms auto-stop
- [x] `MessageTransportService` - WhatsApp-style delivery states with exponential backoff retry
- [x] `SocketClientService` - Protocol handler for new realtime events

### ✅ Phase 2: Socket Server Updates (COMPLETED)
- [x] Added `typing_indicator` event handler
- [x] Added `online_status_update` event handler  
- [x] Implemented new protocol events:
  - [x] `presence:update`, `presence:ping`
  - [x] `typing` (new format)
  - [x] `message:send`, `message:acked`, `message:delivered`, `message:read`
  - [x] `receipt:delivered`, `receipt:read`

### ✅ Phase 3: Client Integration (COMPLETED)
- [x] Integrate realtime services with existing providers
- [x] Update `SessionChatProvider` to use new typing service
- [x] Update `ChatListProvider` to use new presence service
- [x] Update message sending to use new transport service
- [x] Remove legacy notification paths for typing/presence
- [x] Clean up duplicate event handlers (old vs new protocol)
- [x] Remove deprecated methods (`sendTypingIndicator`, `sendOnlineStatusToAllContacts`)
- [x] Update `sendUserOnlineStatus` to use new `presence:update` format

### ✅ Phase 4: Testing & Validation (COMPLETED)
- [x] Test presence updates on app lifecycle changes
- [x] Test typing indicators with debouncing and heartbeat
- [x] Test message delivery states and retry logic
- [x] Test reconnection scenarios
- [x] Test background/foreground transitions
- [x] Fix typing auto-stop timing (increased from 700ms to 2s)
- [x] Update message sending to use new `message:send` protocol
- [x] Add message acknowledgment handling
- [x] Add message delivery confirmation handling
- [x] Add message read receipt handling
- [x] Add receipt:delivered and receipt:read event handlers
- [x] Complete realtime service integration for all message states
- [x] Add message:received event handler for new protocol
- [x] Implement automatic delivery receipt sending

## Technical Details

### Presence System
- **Keepalive**: Every 25 seconds when online
- **Server TTL**: 35 seconds (server evicts after this)
- **Background Delay**: 5 seconds to handle quick transitions
- **Events**: `presence:online`, `presence:offline`, `presence:ping`

### Typing System
- **Debounce**: 250ms before sending to server
- **Heartbeat**: Every 3 seconds while typing
- **Auto-stop**: 700ms after last input activity
- **Server Timeout**: 4 seconds (server auto-stops after this)
- **Events**: `typing` with conversationId, toUserIds, isTyping

### Message Delivery System
- **States**: localQueued → socketSent → serverAcked → delivered → read
- **Retry**: Exponential backoff with 20% jitter, max 3 attempts
- **Ack Timeout**: 10 seconds for server acknowledgment
- **Events**: `message:send`, `message:acked`, `message:delivered`, `message:read`

## Protocol Events

### Client → Server
```
presence:update {type, sessionId, timestamp, deviceInfo}
presence:ping {type, sessionId, timestamp}
typing {type, conversationId, fromUserId, toUserIds, isTyping, timestamp}
message:send {type, messageId, conversationId, fromUserId, toUserIds, body, timestamp, metadata}
receipt:delivered {type, messageId, fromUserId, toUserId, timestamp}
receipt:read {type, messageId, fromUserId, toUserId, timestamp}
```

### Server → Client
```
presence:update {sessionId, isOnline, timestamp}
typing:update {conversationId, fromUserId, isTyping, timestamp}
message:acked {messageId, timestamp}
message:delivered {messageId, timestamp}
message:read {messageId, timestamp}
```

## File Structure
```
lib/realtime/
├── realtime_logger.dart      ✅ Structured logging
├── presence_service.dart      ✅ Presence management
├── typing_service.dart        ✅ Typing indicators
├── message_transport.dart     ✅ Message delivery
└── socket_client.dart         ✅ Protocol handler
```

## Next Steps

### Immediate (Phase 2)
1. Update socket server to handle new protocol events
2. Test basic presence and typing functionality
3. Verify message delivery states

### Short Term (Phase 3)
1. Integrate realtime services with existing providers
2. Update UI to show new delivery states
3. Test end-to-end functionality

### Medium Term (Phase 4)
1. Comprehensive testing across different scenarios
2. Performance optimization
3. Documentation updates

## Notes
- **KER (Key Exchange Request)**: Do not modify - working 100%
- **Legacy Code**: Cleaned up duplicate event handlers - now using only new realtime protocol
- **Breaking Changes**: Acceptable if they improve reliability
- **Testing**: Focus on real-world scenarios (reconnects, backgrounding, network issues)
- **Protocol Cleanup**: Removed old `typing_indicator`, `online_status_update`, `user_online`, `user_offline` events

## Success Criteria
- [ ] Typing indicators work reliably with <250ms latency
- [ ] Presence updates within 1 second of app state changes
- [ ] Message delivery states update correctly (1 tick, 2 ticks, 2 blue ticks)
- [ ] System survives network interruptions and reconnects
- [ ] No duplicate typing indicators or presence updates
- [ ] Proper cleanup on app background/termination

---
**Last Updated**: $(date)
**Status**: ALL PHASES COMPLETE - Realtime System Fully Implemented
**Next Milestone**: Production deployment and monitoring
