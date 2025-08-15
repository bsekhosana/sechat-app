# SQLite Boolean Fix

## Problem

The app was experiencing SQLite warnings when saving conversation data:

```
Invalid argument false with type bool.
Only num, String and Uint8List are supported.
```

This warning occurred because SQLite doesn't support boolean values directly - they need to be converted to integers (0 or 1) or strings.

## Root Cause

The issue was in the `ChatConversation.toJson()` method, which was returning boolean values directly:

```dart
// Before (causing SQLite warnings)
'is_archived': isArchived,        // bool -> SQLite error
'is_muted': isMuted,              // bool -> SQLite error
'is_pinned': isPinned,            // bool -> SQLite error
'is_typing': isTyping,            // bool -> SQLite error
'notifications_enabled': notificationsEnabled,  // bool? -> SQLite error
// ... other boolean fields
```

## Solution

Modified the `toJson()` method to convert boolean values to integers before saving to SQLite:

```dart
// After (SQLite compatible)
'is_archived': isArchived ? 1 : 0,        // bool -> int
'is_muted': isMuted ? 1 : 0,              // bool -> int
'is_pinned': isPinned ? 1 : 0,            // bool -> int
'is_typing': isTyping ? 1 : 0,            // bool -> int
'notifications_enabled': notificationsEnabled ?? true ? 1 : 0,  // bool? -> int
// ... other boolean fields converted
```

## Implementation Details

### Boolean Field Conversion

All boolean fields in the `ChatConversation` model are now converted to integers:

- `true` → `1`
- `false` → `0`
- `null` → default value (usually `true` for settings, `false` for flags)

### Nullable Boolean Handling

For nullable boolean fields, we provide sensible defaults:

```dart
// Settings fields default to true when null
'notifications_enabled': notificationsEnabled ?? true ? 1 : 0,
'sound_enabled': soundEnabled ?? true ? 1 : 0,
'vibration_enabled': vibrationEnabled ?? true ? 1 : 0,

// Flag fields default to false when null
'is_blocked': isBlocked ?? false ? 1 : 0,
```

### Reading from Database

The existing `_parseBool()` method already handles reading integer values from the database:

```dart
static bool? _parseBool(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is int) return value == 1;  // 1 = true, 0 = false
  if (value is String) {
    final lowerValue = value.toLowerCase();
    return lowerValue == 'true' || lowerValue == '1';
  }
  return false;
}
```

## Testing

The fix should be tested by:

1. Opening a chat conversation (which triggers `markAsRead`)
2. Verifying that no SQLite boolean warnings appear in the logs
3. Checking that conversation data is properly saved and loaded
4. Ensuring that boolean settings are preserved correctly

## Future Improvements

1. **Consistent Boolean Handling**: Apply the same pattern to other models that use SQLite
2. **Database Schema Validation**: Add validation to ensure all boolean fields are stored as integers
3. **Migration Script**: If needed, create a migration script to convert existing boolean data to integers
4. **Type Safety**: Consider using a more type-safe approach for database operations
