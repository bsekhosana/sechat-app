# Badge Update Payload Error Fix

## Problem Fixed

**Issue**: Android app coming back into foreground error - "Payload is not JSON" when handling `badge_update` notifications.

**Error Log**:
```
SeChat ℹ️ 📱 LocalNotificationBadgeService:  Payload is not JSON, trying string parsing: FormatException: Unexpected character (at character 1)
badge_update
^
```

## Root Cause

The `badge_update` and `badge_reset` notifications use plain string payloads (`'badge_update'` and `'badge_reset'`), but the notification tap handler was trying to parse them as JSON, causing a `FormatException`.

## Solution Implemented

**File**: `lib/features/notifications/services/local_notification_badge_service.dart`

**Added special handling for non-JSON payloads** before attempting JSON parsing:

```dart
// Handle special payloads that are not JSON
if (payload == 'badge_update' || payload == 'badge_reset') {
  Logger.info(
      '📱 LocalNotificationBadgeService:  Badge update notification tapped - no action needed');
  return;
}

// Try to parse as JSON first
try {
  final Map<String, dynamic> payloadMap = jsonDecode(payload);
  // ... JSON parsing logic
} catch (jsonError) {
  // ... fallback logic
}
```

## Technical Details

### **What Was Happening:**

1. **Badge Update Notification**: When the app badge count is updated, a silent notification is sent with payload `'badge_update'`
2. **Notification Tap Handler**: The `_onNotificationTapped` method tried to parse this as JSON
3. **JSON Parsing Error**: `jsonDecode('badge_update')` threw a `FormatException`
4. **Error Logging**: The error was logged but the app continued functioning

### **What's Fixed:**

1. **Special Payload Detection**: Added check for `badge_update` and `badge_reset` payloads
2. **Early Return**: These payloads are handled without JSON parsing
3. **No Action Needed**: Badge update notifications don't require user interaction
4. **Clean Error Handling**: Improved error logging for unknown payload formats

## Expected Behavior After Fix

### ✅ **Before Fix:**
- Error logged when app comes to foreground
- `FormatException` when parsing `badge_update` payload
- App continues functioning but with error logs

### ✅ **After Fix:**
- No error when app comes to foreground
- `badge_update` payload handled gracefully
- Clean log: "Badge update notification tapped - no action needed"
- No JSON parsing errors

## Code Changes

### **1. Added Special Payload Handling:**
```dart
// Handle special payloads that are not JSON
if (payload == 'badge_update' || payload == 'badge_reset') {
  Logger.info(
      '📱 LocalNotificationBadgeService:  Badge update notification tapped - no action needed');
  return;
}
```

### **2. Enhanced Error Handling:**
```dart
} else {
  Logger.info(
      '📱 LocalNotificationBadgeService:  Unknown payload format: $payload');
}
```

## Testing Scenarios

### **1. App Foreground Transition:**
- Put app in background
- Update badge count (triggers `badge_update` notification)
- Bring app to foreground
- **Expected**: No error logs, clean transition

### **2. Badge Reset:**
- Reset badge count (triggers `badge_reset` notification)
- Tap notification
- **Expected**: No error logs, no action taken

### **3. Message Notifications:**
- Receive message notification (JSON payload)
- Tap notification
- **Expected**: Navigate to chat screen (unchanged behavior)

## Files Modified

1. **`lib/features/notifications/services/local_notification_badge_service.dart`**
   - Added special handling for `badge_update` and `badge_reset` payloads
   - Enhanced error handling for unknown payload formats
   - Improved logging for better debugging

## Notes

- **Backward Compatibility**: JSON payloads still work as before
- **Performance**: Early return for badge updates improves performance
- **User Experience**: No more error logs when app comes to foreground
- **Maintainability**: Clear separation between JSON and non-JSON payloads
