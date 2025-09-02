# 🔌 SeChat Socket.IO Testing Guide

## 📋 Overview

This comprehensive testing guide provides everything you need to test all SeChat Socket.IO features without real devices. The Postman collection (`sechat-socket-testing.postman_collection.json`) contains detailed test cases for all functionality.

**Server URL:** `https://sechat-socket.strapblaque.com/`

## 🚀 Quick Start

### 1. Import Postman Collection
- Download `sechat-socket-testing.postman_collection.json`
- Import into Postman (File → Import)
- The collection will be available in your Postman workspace

### 2. Setup Socket.IO Client
You'll need a Socket.IO client to actually test the events. Here are your options:

#### Option A: Browser Console (Easiest)
```html
<!-- Add this to any HTML page -->
<script src="https://cdn.socket.io/4.7.2/socket.io.min.js"></script>
```

#### Option B: Node.js Script
```bash
npm install socket.io-client
```

#### Option C: Use the Test HTML Page
We've also created `test-screens.html` for visual testing.

### 3. Start Testing
Follow the testing workflow outlined in the collection.

## 🧪 Testing Features

### 📱 Session Management
- **Register Session**: Create new user sessions
- **Join Session**: Connect existing sessions
- **Session Monitoring**: Track active connections

### 🔑 Key Exchange Request (KER)
Complete KER handshake testing:

1. **Send KER Request** - Device A → Device B
2. **Accept KER Request** - Device B accepts
3. **Decline KER Request** - Device B declines
4. **Revoke KER Request** - Device A revokes

**Test Flow:**
```
Device A (Requester) → KER Request → Device B (Recipient)
Device B → Accept/Decline → Device A receives response
Device A → Revoke (if needed) → Device B notified
```

### 💬 Messaging & Chat
- **Send Messages**: Between two users
- **Typing Indicators**: Start/stop typing status
- **Message Management**: Delete single/all messages

### 🟢 Presence Management
- **Online/Offline Status**: Set and monitor user presence
- **Presence Monitoring**: Check specific user status
- **Real-time Updates**: Broadcast presence changes

### 🚫 Block & Unblock
- **User Blocking**: Block/unblock specific users
- **Conversation Blocking**: Block/unblock chat conversations
- **Block Status Monitoring**: Track blocking states

## 🔧 Detailed Testing Instructions

### Step 1: Session Setup
```javascript
// Connect to server
const socket = io('https://sechat-socket.strapblaque.com');

// Register Device A
socket.emit('register_session', {
    sessionId: 'device_a_001',
    publicKey: 'public_key_a_123'
});

// Register Device B
socket.emit('register_session', {
    sessionId: 'device_b_002',
    publicKey: 'public_key_b_456'
});
```

### Step 2: KER Testing
```javascript
// Device A sends KER request
socket.emit('key_exchange:request', {
    senderId: 'device_a_001',
    recipientId: 'device_b_002',
    publicKey: 'public_key_a_123',
    requestId: 'ker_1234567890',
    requestPhrase: 'Hello Device B, let\'s exchange keys!',
    version: '1'
});

// Device B accepts
socket.emit('key_exchange:accept', {
    requestId: 'ker_1234567890',
    recipientId: 'device_b_002',
    senderId: 'device_a_001',
    encryptedUserData: 'encrypted_user_data_from_device_b'
});
```

### Step 3: Messaging Testing
```javascript
// Send message
socket.emit('message:send', {
    messageId: 'msg_1234567890',
    fromUserId: 'device_a_001',
    recipientId: 'device_b_002',
    conversationId: 'chat_001',
    body: 'Hello from Device A!',
    timestamp: new Date().toISOString()
});

// Typing indicator
socket.emit('typing:update', {
    fromUserId: 'device_a_001',
    recipientId: 'device_b_002',
    conversationId: 'chat_001',
    isTyping: true
});
```

### Step 4: Presence Testing
```javascript
// Go online
socket.emit('presence:update', {
    sessionId: 'device_a_001',
    isOnline: true,
    timestamp: new Date().toISOString()
});

// Go offline
socket.emit('presence:update', {
    sessionId: 'device_a_001',
    isOnline: false,
    timestamp: new Date().toISOString()
});
```

### Step 5: Blocking Testing
```javascript
// Block user
socket.emit('user:blocked', {
    blockerId: 'device_a_001',
    blockedId: 'device_b_002',
    reason: 'User blocked from test interface',
    timestamp: new Date().toISOString()
});

// Block conversation
socket.emit('conversation:blocked', {
    conversationId: 'chat_001',
    blockerId: 'device_a_001',
    timestamp: new Date().toISOString()
});
```

## 📊 Monitoring & Debugging

### Server Monitoring
Visit `https://sechat-socket.strapblaque.com/admin/api-docs` to:
- View real-time server logs
- Monitor active sessions
- Track event flow
- Debug connection issues

### Client Debugging
```javascript
// Add these listeners for debugging
socket.on('connect', () => {
    console.log('✅ Connected to server');
});

socket.on('disconnect', () => {
    console.log('❌ Disconnected from server');
});

socket.on('connect_error', (error) => {
    console.error('🔴 Connection error:', error);
});

// Listen for all events
socket.onAny((eventName, ...args) => {
    console.log(`📡 Event received: ${eventName}`, args);
});
```

## 🚨 Common Issues & Solutions

### Connection Issues
- **"Connection refused"**: Check if server is running
- **"CORS error"**: Server should handle CORS properly
- **"Socket timeout"**: Check network connectivity

### Event Issues
- **Events not received**: Verify session registration
- **Wrong recipients**: Check session ID mapping
- **Missing payloads**: Ensure all required fields are present

### KER Specific Issues
- **Decline not working**: Check the critical bug we've been investigating
- **Wrong recipient**: Verify `deliverToSession` function
- **Payload corruption**: Check event routing logic

## 📱 Testing Without Real Devices

### Browser Testing
1. Open `test-screens.html` in multiple browser tabs
2. Each tab represents a different device
3. Use browser console for Socket.IO commands
4. Monitor network tab for WebSocket traffic

### Node.js Testing
```javascript
const { io } = require('socket.io-client');

// Create multiple socket instances
const deviceA = io('https://sechat-socket.strapblaque.com');
const deviceB = io('https://sechat-socket.strapblaque.com');

// Test events between them
deviceA.emit('key_exchange:request', {...});
deviceB.on('key_exchange:request', (data) => {
    console.log('KER request received:', data);
});
```

## 🔍 Advanced Testing Scenarios

### Load Testing
```javascript
// Create multiple connections
const connections = [];
for (let i = 0; i < 100; i++) {
    const socket = io('https://sechat-socket.strapblaque.com');
    connections.push(socket);
}
```

### Stress Testing
```javascript
// Rapid event emission
setInterval(() => {
    socket.emit('message:send', {
        messageId: Date.now().toString(),
        fromUserId: 'device_a_001',
        recipientId: 'device_b_002',
        conversationId: 'chat_001',
        body: 'Stress test message',
        timestamp: new Date().toISOString()
    });
}, 100);
```

### Offline/Online Testing
```javascript
// Simulate network issues
socket.on('disconnect', () => {
    console.log('Simulating offline mode');
    // Test queuing system
});

socket.on('connect', () => {
    console.log('Back online - check queued messages');
});
```

## 📚 Additional Resources

### API Documentation
- **Live API Docs**: `https://sechat-socket.strapblaque.com/admin/api-docs`
- **Event Reference**: See the Postman collection for all events
- **Payload Examples**: Each test case includes sample payloads

### Socket.IO Resources
- [Socket.IO Official Docs](https://socket.io/docs/)
- [Socket.IO Client API](https://socket.io/docs/v4/client-api/)
- [Socket.IO Testing Guide](https://socket.io/docs/v4/testing/)

### Monitoring Tools
- **Server Dashboard**: `https://sechat-socket.strapblaque.com/`
- **Real-time Logs**: Available in admin panel
- **Connection Map**: Visual representation of connections

## 🎯 Testing Checklist

- [ ] Session registration working
- [ ] KER request/accept flow working
- [ ] KER decline/revoke flow working
- [ ] Message sending/receiving working
- [ ] Typing indicators working
- [ ] Message deletion working
- [ ] Presence updates working
- [ ] User blocking working
- [ ] Conversation blocking working
- [ ] Queuing system working (offline messages)
- [ ] Error handling working
- [ ] Performance acceptable under load

## 🆘 Support

If you encounter issues:
1. Check the server logs at `/admin/api-docs`
2. Verify your Socket.IO client setup
3. Check the browser console for errors
4. Review the event payloads in the Postman collection
5. Test with the provided `test-screens.html` file

---

**Happy Testing! 🚀**

This comprehensive testing suite will help you validate all SeChat Socket.IO functionality before implementing the frontend.
