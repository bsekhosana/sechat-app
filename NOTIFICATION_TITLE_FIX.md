# Notification Title Fix - Contact Name Resolution

## Problem
Push notifications for incoming messages were sometimes showing session IDs instead of contact names in the title, making them less user-friendly and harder to identify.

## Root Cause
The notification title was using `senderName` which could be:
1. **Session ID** - When `data['senderName']` was not provided by the server
2. **fromUserId** - When falling back to `data['fromUserId']` (also a session ID)
3. **"Unknown User"** - When both were missing

## Solution Implemented

### 1. Enhanced Socket Service Contact Resolution

**File**: `lib/core/services/se_socket_service.dart`
**Location**: `message:received` event handler (lines 792-808)

**Added contact name resolution**:
```dart
// Extract sender name from data or use senderId as fallback
String senderName = data['senderName'] ?? data['fromUserId'] ?? 'Unknown User';

// Try to resolve contact name if senderName is a session ID
if (senderName == data['fromUserId'] || senderName.startsWith('session_')) {
  try {
    final contactService = ContactService.instance;
    final contact = contactService.getContact(data['fromUserId'] ?? '');
    if (contact != null && contact.displayName.isNotEmpty) {
      senderName = contact.displayName;
      Logger.debug('💬 SeSocketService:  Resolved contact name: ${data['fromUserId']} -> $senderName');
    }
  } catch (e) {
    Logger.debug('💬 SeSocketService:  Could not resolve contact name: $e');
  }
}
```

### 2. Enhanced Main Notification Handler

**File**: `lib/main.dart`
**Location**: Message received callback (lines 369-382)

**Added additional contact name resolution**:
```dart
// Resolve contact name for notification title
String contactName = senderName;
try {
  final contactService = ContactService.instance;
  final contact = contactService.getContact(senderId);
  if (contact != null && contact.displayName.isNotEmpty) {
    contactName = contact.displayName;
    Logger.debug(' Main:  Resolved contact name: $senderId -> $contactName');
  } else {
    Logger.warning(' Main:  Contact not found for $senderId, using fallback: $senderName');
  }
} catch (e) {
  Logger.warning(' Main:  Error resolving contact name: $e, using fallback: $senderName');
}
```

### 3. Updated Notification Title

**File**: `lib/main.dart`
**Location**: Notification creation (line 422)

**Changed from**:
```dart
title: 'New message from $senderName',
```

**Changed to**:
```dart
title: 'New message from $contactName',
```

## Technical Implementation Details

### Contact Resolution Flow

1. **Socket Service Level** (First attempt):
   - Check if `senderName` is a session ID
   - Use `ContactService.getContact()` to resolve to display name
   - Update `senderName` with resolved contact name

2. **Main Handler Level** (Second attempt):
   - Use `ContactService.getContact()` again for additional safety
   - Fall back to original `senderName` if contact not found
   - Log resolution success/failure for debugging

3. **Notification Creation**:
   - Use resolved `contactName` for notification title
   - Ensure proper contact name is always displayed

### Error Handling

- **Graceful Fallbacks**: If contact resolution fails, falls back to original sender name
- **Comprehensive Logging**: Debug logs for successful resolution, warnings for failures
- **No Breaking Changes**: Maintains backward compatibility

### Contact Service Integration

- **Uses existing ContactService**: Leverages `ContactService.instance.getContact(sessionId)`
- **No additional dependencies**: Uses already imported service
- **Efficient resolution**: Quick lookup by session ID

## Expected Behavior

### Before Fix
- ❌ "New message from session_1757027400340-8vjevw7r-i9c-q6h-89p-t3vufmkcru4"
- ❌ "New message from Unknown User"
- ❌ Inconsistent notification titles

### After Fix
- ✅ "New message from John Doe"
- ✅ "New message from Alice Smith"
- ✅ "New message from Contact Name"
- ✅ Consistent, user-friendly notification titles

## Fallback Strategy

### Primary Resolution
1. **Server-provided senderName** (if available and not session ID)
2. **ContactService resolution** (if contact exists in local database)
3. **Session ID fallback** (if contact not found)
4. **"Unknown User"** (if all else fails)

### Logging Levels
- **Debug**: Successful contact resolution
- **Warning**: Contact not found, using fallback
- **Error**: Contact resolution failed

## Benefits

1. **User-Friendly Notifications**: Clear contact names instead of session IDs
2. **Better User Experience**: Easy identification of message senders
3. **Consistent Display**: Uniform notification titles across the app
4. **Robust Fallbacks**: Graceful handling when contact resolution fails
5. **Enhanced Debugging**: Comprehensive logging for troubleshooting
6. **No Breaking Changes**: Maintains existing functionality

## Testing Scenarios

### 1. **Known Contact**
- Send message from known contact
- **Expected**: "New message from [Contact Name]"

### 2. **Unknown Contact**
- Send message from unknown contact
- **Expected**: "New message from [Session ID]" or "Unknown User"

### 3. **Contact Resolution Failure**
- Contact service unavailable
- **Expected**: Falls back to session ID gracefully

### 4. **Server-Provided Name**
- Server sends proper senderName
- **Expected**: Uses server-provided name

## Files Modified

### Primary Changes
- **`lib/main.dart`**: Added contact name resolution in notification handler
- **`lib/core/services/se_socket_service.dart`**: Added contact name resolution in message received handler

### Supporting Infrastructure
- **`lib/core/services/contact_service.dart`**: Already available (no changes needed)
- **`lib/features/notifications/services/local_notification_badge_service.dart`**: No changes needed

## Monitoring

### Success Indicators
- Notification titles show contact names instead of session IDs
- Debug logs show successful contact resolution
- No critical errors in contact resolution

### Log Messages to Watch
```
✅ "Resolved contact name: session_xxx -> Contact Name"
⚠️ "Contact not found for session_xxx, using fallback"
❌ "Error resolving contact name: [error]"
```

## Notes
- Contact resolution happens at two levels for maximum reliability
- Fallback strategy ensures notifications always work
- Comprehensive logging helps with debugging
- No performance impact as ContactService uses efficient lookups
- Maintains backward compatibility with existing code
