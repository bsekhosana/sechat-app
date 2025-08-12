# Universal Notification Payload Standard

## 🎯 **Overview**

This document defines the universal notification payload standard implemented in SeChat for consistent communication with AirNotifier servers and other notification services.

## 📱 **Standard Payload Structure**

### **Core Format**
```json
{
  "session_id": "your_session_id_here",
  "alert": {
    "title": "Notification Title", 
    "body": "Notification Body"
  },
  "sound": "default",
  "badge": 1,
  "data": {
    "type": "notification_type",
    "customField1": "value1",
    "customField2": "value2"
  }
}
```

### **Field Definitions**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `session_id` | String | ✅ | Unique session identifier for the recipient |
| `alert` | Object | ✅ | Notification content structure |
| `alert.title` | String | ✅ | Notification title |
| `alert.body` | String | ✅ | Notification body text |
| `sound` | String | ❌ | Sound file name (defaults to "default") |
| `badge` | Number | ❌ | App icon badge number (defaults to 1) |
| `data` | Object | ❌ | Custom metadata and application data |

## 🔧 **Implementation in SeChat**

### **Method Signature**
```dart
Map<String, dynamic> _formatUniversalPayload({
  required String sessionId,
  required String title,
  required String body,
  Map<String, dynamic>? data,
  String? sound,
  int badge = 1,
  bool encrypted = false,
  String? checksum,
})
```

### **Usage Example**
```dart
final payload = _formatUniversalPayload(
  sessionId: 'session_123',
  title: 'New Invitation',
  body: 'John wants to connect with you',
  data: {
    'type': 'invitation',
    'invitationId': 'inv_456',
    'senderName': 'John Doe',
  },
  sound: 'invitation.wav',
  badge: 1,
);
```

## 📋 **Notification Types**

### **1. Invitation Notifications**
```json
{
  "session_id": "session_recipient",
  "alert": {
    "title": "New Invitation",
    "body": "Jane wants to connect with you"
  },
  "sound": "invitation.wav",
  "badge": 1,
  "data": {
    "type": "invitation",
    "invitationId": "inv_123",
    "senderId": "session_sender",
    "senderName": "Jane",
    "fromUserId": "session_sender",
    "fromUsername": "Jane",
    "toUserId": "session_recipient",
    "toUsername": "Recipient"
  }
}
```

### **2. Message Notifications**
```json
{
  "session_id": "session_recipient",
  "alert": {
    "title": "John Doe",
    "body": "Hello! How are you doing?"
  },
  "sound": "message.wav",
  "badge": 1,
  "data": {
    "type": "message",
    "senderName": "John Doe",
    "senderId": "session_sender",
    "conversationId": "chat_123",
    "message": "Hello! How are you doing?",
    "action": "message_received",
    "timestamp": 1755029770583
  }
}
```

### **3. Invitation Response Notifications**
```json
{
  "session_id": "session_recipient",
  "alert": {
    "title": "Invitation Accepted",
    "body": "Jane accepted your invitation"
  },
  "sound": "accepted.wav",
  "badge": 1,
  "data": {
    "type": "invitation_response",
    "invitationId": "inv_123",
    "responderName": "Jane",
    "responderId": "session_responder",
    "status": "accepted",
    "chatId": "chat_456",
    "action": "invitation_response",
    "timestamp": 1755029770583
  }
}
```

### **4. Silent Notifications**
```json
{
  "session_id": "session_recipient",
  "alert": {
    "title": "",
    "body": ""
  },
  "sound": null,
  "badge": 0,
  "data": {
    "type": "typing_indicator",
    "senderName": "John Doe",
    "senderId": "session_sender",
    "isTyping": true,
    "action": "typing_indicator",
    "timestamp": 1755029770583
  }
}
```

## 🔒 **Encryption Support**

### **Encrypted Notification Structure**
```json
{
  "session_id": "session_recipient",
  "alert": {
    "title": "Encrypted Message",
    "body": "You have received an encrypted message"
  },
  "sound": "message.wav",
  "badge": 1,
  "data": {
    "encrypted": true,
    "data": "encrypted_data_string",
    "checksum": "data_checksum_hash"
  }
}
```

## 🚀 **Benefits of the Standard**

### **✅ Consistency**
- **Uniform structure** across all notification types
- **Predictable format** for developers and services
- **Easy parsing** and processing

### **✅ Compatibility**
- **AirNotifier server** compatibility
- **iOS APNS** compliance
- **Android FCM** support
- **Cross-platform** notification handling

### **✅ Maintainability**
- **Clear separation** of notification content and custom data
- **Easy extension** for new notification types
- **Simple debugging** and troubleshooting

### **✅ Scalability**
- **Flexible data structure** for future enhancements
- **Support for complex** notification scenarios
- **Easy integration** with new services

## 🧪 **Testing and Validation**

### **Payload Validation**
```dart
bool isValidUniversalPayload(Map<String, dynamic> payload) {
  // Check required fields
  if (!payload.containsKey('session_id')) return false;
  if (!payload.containsKey('alert')) return false;
  if (!payload['alert'].containsKey('title')) return false;
  if (!payload['alert'].containsKey('body')) return false;
  
  // Check data structure
  if (payload.containsKey('data') && payload['data'] is! Map) return false;
  
  return true;
}
```

### **Test Cases**
1. **Valid invitation notification**
2. **Valid message notification**
3. **Valid silent notification**
4. **Valid encrypted notification**
5. **Invalid payload (missing required fields)**
6. **Invalid payload (wrong data types)**

## 🔄 **Migration Guide**

### **From Old Format**
```dart
// Old format (causing errors)
final payload = {
  'session_id': sessionId,
  'aps': {
    'alert': {'title': title, 'body': body},
    'sound': sound,
    'badge': badge,
  },
  'customField': 'value', // Mixed with aps
};
```

### **To New Universal Format**
```dart
// New universal format
final payload = _formatUniversalPayload(
  sessionId: sessionId,
  title: title,
  body: body,
  data: {
    'customField': 'value', // Properly organized in data
  },
  sound: sound,
  badge: badge,
);
```

## 📊 **Monitoring and Analytics**

### **Payload Metrics**
- **Size tracking**: Monitor payload sizes for optimization
- **Type distribution**: Track notification types for analytics
- **Delivery success**: Monitor notification delivery rates
- **Error tracking**: Log and analyze payload errors

### **Performance Considerations**
- **Payload size**: Keep under 4KB for optimal delivery
- **Data efficiency**: Use concise field names and values
- **Caching**: Cache common notification templates
- **Batch processing**: Group similar notifications when possible

## 🎉 **Summary**

The Universal Notification Payload Standard provides:

✅ **Consistent structure** across all notification types
✅ **Server compatibility** with AirNotifier and other services
✅ **Easy maintenance** and debugging
✅ **Future extensibility** for new features
✅ **Cross-platform support** for iOS and Android

This standard ensures reliable notification delivery and provides a solid foundation for future notification enhancements in SeChat. 🎯
