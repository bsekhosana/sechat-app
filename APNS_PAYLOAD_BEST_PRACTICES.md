# APNS Payload Best Practices for iOS

## 🎯 Overview

This document outlines the best practices for structuring push notification payloads for iOS APNS (Apple Push Notification Service), following Apple's official documentation and guidelines.

## ✅ **Apple's APNS Requirements**

### **1. aps Dictionary Structure**
The `aps` dictionary must contain **ONLY** system-defined keys:

```json
{
  "aps": {
    "alert": {
      "title": "Notification Title",
      "body": "Notification Body"
    },
    "badge": 1,
    "sound": "default",
    "category": "INVITATION",
    "content-available": 1
  }
}
```

**Allowed aps keys:**
- `alert` - Notification content (title, body, subtitle)
- `badge` - App icon badge number
- `sound` - Sound file name
- `category` - Notification category for actions
- `content-available` - Silent notification flag
- `mutable-content` - Rich media support
- `thread-id` - Thread grouping

### **2. Custom Metadata Placement**
**❌ WRONG** - Custom data inside aps:
```json
{
  "aps": {
    "alert": {"title": "Hi", "body": "There"},
    "customData": {"foo": "bar"}  // ❌ VIOLATION
  }
}
```

**✅ CORRECT** - Custom data outside aps:
```json
{
  "aps": {
    "alert": {"title": "Hi", "body": "There"},
    "badge": 1,
    "sound": "default"
  },
  "customData": {"foo": "bar"},  // ✅ CORRECT
  "userId": 123,
  "invitationId": "inv_abc123"
}
```

## 🔧 **Implementation in SeChat**

### **Current Structure**
Our AirNotifier service now creates simple, direct APNS-compliant payloads:

```dart
// Simple, direct APNS payload (following Apple's best practices)
final payload = _formatNotificationPayload(
  sessionId: sessionId,
  title: title,
  body: body,
  data: data,
  sound: sound,
  badge: badge,
);
```

### **Generated iOS Payload**
```json
{
  "session_id": "session_789",
  "aps": {
    "alert": {
      "title": "Invitation Accepted",
      "body": "Jane accepted your invitation"
    },
    "sound": "default",
    "badge": 1
  },
  "type": "invitation",
  "invitationId": "inv_123",
  "chatGuid": "chat_456"
}
```

## 🚀 **Key Benefits of This Structure**

### **1. APNS Compliance**
- ✅ **No violations**: Custom data is outside the `aps` dictionary
- ✅ **System keys only**: `aps` contains only Apple-defined keys
- ✅ **Proper parsing**: iOS can safely parse the payload

### **2. Simple and Clean**
- ✅ **Direct structure**: No complex nesting or platform-specific sections
- ✅ **Easy parsing**: Custom data accessible directly at root level
- ✅ **Minimal overhead**: Efficient payload size and structure

### **3. Developer Experience**
- ✅ **Easy access**: Custom data at root level
- ✅ **Type safety**: JSON-compatible data types only
- ✅ **Debugging**: Clear, simple payload structure
- ✅ **Maintenance**: Easy to modify and extend

## 📱 **iOS Notification Handling**

### **1. Foreground Notifications**
```dart
// In your iOS app delegate
func userNotificationCenter(_ center: UNUserNotificationCenter, 
                          willPresent notification: UNNotification, 
                          withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
  
  let userInfo = notification.request.content.userInfo
  
  // Access custom data (outside aps) - directly at root level
  let invitationId = userInfo["invitationId"] as? String
  let chatGuid = userInfo["chatGuid"] as? String
  let type = userInfo["type"] as? String
  
  // Access system data (inside aps)
  let title = userInfo["aps"]?["alert"]?["title"] as? String
  let body = userInfo["aps"]?["alert"]?["body"] as? String
  
  completionHandler([.alert, .badge, .sound])
}
```

### **2. Background Notifications**
```dart
// Silent notifications with content-available
{
  "aps": {
    "content-available": 1,
    "badge": 1
  },
  "type": "silent_update",
  "data": "background_data"
}
```

### **3. Action Notifications**
```json
{
  "aps": {
    "alert": {
      "title": "New Invitation",
      "body": "John Doe wants to connect with you"
    },
    "category": "INVITATION_ACTIONS",
    "badge": 1
  },
  "invitationId": "inv_abc123",
  "senderId": "user_456"
}
```

## 🛠️ **Payload Size Optimization**

### **1. Size Limits**
- **Standard notifications**: 4 KB maximum
- **VoIP notifications**: 5 KB maximum
- **Critical notifications**: 4 KB maximum

### **2. Optimization Strategies**
```dart
// Remove unnecessary fields for large payloads
if (payloadSize > 3500) { // Leave buffer for encoding
  // Remove non-critical fields
  payload.remove('detailedMetadata');
  payload.remove('debugInfo');
}
```

### **3. Data Compression**
```dart
// Use short field names
payload['invId'] = invitationId;        // Instead of 'invitationId'
payload['sId'] = senderId;              // Instead of 'senderId'
payload['sName'] = senderName;          // Instead of 'senderName'
```

## 🔒 **Security Considerations**

### **1. Sensitive Data**
**❌ DON'T** include sensitive information in push payloads:
```json
{
  "aps": {"alert": {"title": "Security Alert", "body": "Action Required"}},
  "password": "secret123",           // ❌ SECURITY RISK
  "creditCard": "1234-5678-9012",    // ❌ SECURITY RISK
  "ssn": "123-45-6789"               // ❌ SECURITY RISK
}
```

**✅ DO** use push as a signal to fetch secure data:
```json
{
  "aps": {"alert": {"title": "Security Alert", "body": "Action Required"}},
  "alertId": "alert_123",            // ✅ Safe identifier
  "requiresAction": true,             // ✅ Safe flag
  "fetchUrl": "/api/alerts/123"      // ✅ Safe endpoint
}
```

### **2. Data Validation**
```dart
// Validate data types before sending
Map<String, dynamic> sanitizeData(Map<String, dynamic> data) {
  final sanitized = <String, dynamic>{};
  
  data.forEach((key, value) {
    if (value is String || value is num || value is bool || 
        value is List || value is Map) {
      sanitized[key] = value;
    } else {
      // Convert non-JSON types to strings
      sanitized[key] = value.toString();
    }
  });
  
  return sanitized;
}
```

## 🧪 **Testing APNS Payloads**

### **1. Development Testing**
```bash
# Test with APNS development certificate
curl -v \
  -d '{"aps":{"alert":{"title":"Test","body":"Message"},"badge":1},"testData":"value"}' \
  -H "apns-topic: com.yourapp.bundle" \
  -H "apns-push-type: alert" \
  --http2 \
  --cert /path/to/cert.pem \
  --key /path/to/key.pem \
  https://api.development.push.apple.com/3/device/DEVICE_TOKEN
```

### **2. Production Testing**
```bash
# Test with APNS production certificate
curl -v \
  -d '{"aps":{"alert":{"title":"Test","body":"Message"},"badge":1},"testData":"value"}' \
  -H "apns-topic: com.yourapp.bundle" \
  -H "apns-push-type: alert" \
  --http2 \
  --cert /path/to/cert.pem \
  --key /path/to/key.pem \
  https://api.push.apple.com/3/device/DEVICE_TOKEN
```

### **3. Payload Validation**
```dart
// Validate payload structure
bool isValidAPNSPayload(Map<String, dynamic> payload) {
  // Check if aps exists and contains only valid keys
  if (!payload.containsKey('aps')) return false;
  
  final aps = payload['aps'] as Map<String, dynamic>;
  final validKeys = ['alert', 'badge', 'sound', 'category', 'content-available'];
  
  // Ensure aps only contains valid keys
  for (final key in aps.keys) {
    if (!validKeys.contains(key)) return false;
  }
  
  return true;
}
```

## 📊 **Monitoring and Analytics**

### **1. Delivery Tracking**
```dart
// Track notification delivery
class NotificationAnalytics {
  static void trackDelivery(String notificationId, bool success) {
    // Log delivery status
    print('📊 Notification $notificationId delivery: ${success ? "SUCCESS" : "FAILED"}');
  }
  
  static void trackPayloadSize(int size) {
    // Monitor payload sizes
    if (size > 3500) {
      print('⚠️ Large payload detected: ${size} bytes');
    }
  }
}
```

### **2. Error Monitoring**
```dart
// Monitor APNS errors
class APNSErrorMonitor {
  static void handleError(String error, Map<String, dynamic> payload) {
    print('❌ APNS Error: $error');
    print('❌ Payload: $payload');
    
    // Log for analysis
    // Send to monitoring service
    // Alert developers if needed
  }
}
```

## 🎉 **Summary**

### **✅ What We've Implemented**
1. **APNS-compliant structure**: Custom data outside `aps` dictionary
2. **Simple and clean**: Direct payload structure without complex nesting
3. **Type safety**: JSON-compatible data types only
4. **Size optimization**: Efficient payload structure
5. **Security**: No sensitive data in payloads

### **✅ Benefits**
- **No APNS violations**: Follows Apple's guidelines exactly
- **Better delivery**: Optimized for iOS notification system
- **Developer friendly**: Easy to access custom data at root level
- **Future proof**: Compatible with iOS updates
- **Professional**: Meets enterprise app standards
- **Simple maintenance**: Easy to modify and extend

### **✅ Best Practices Followed**
- ✅ Custom metadata outside `aps` dictionary
- ✅ Only system-defined keys in `aps`
- ✅ JSON-compatible data types
- ✅ No sensitive information
- ✅ Payload size optimization
- ✅ Simple, direct structure
- ✅ Proper error handling

The implemented solution ensures your iOS push notifications will work reliably and comply with Apple's APNS requirements while maintaining excellent user experience and developer productivity.
