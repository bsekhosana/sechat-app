# Socket Persistence Fix - Background Notifications

## Problem
Push notifications stop working after 30 seconds when the app is in the background because the socket connection disconnects and doesn't reconnect properly.

## Root Cause
The socket connection was disconnecting after 30 seconds in the background due to:
1. **Insufficient keepalive frequency** - 30-second intervals were too long
2. **Lack of aggressive reconnection** - No immediate reconnection attempts
3. **Inadequate foreground service persistence** - Service wasn't persistent enough
4. **No immediate ping on background** - No immediate connection verification

## Solution Implemented

### 1. Enhanced Background Connection Manager

**File**: `lib/core/services/background_connection_manager.dart`

**Key Changes**:
- **Reduced ping interval**: From 30 seconds to 15 seconds
- **Added aggressive ping timer**: Every 5 seconds for first 5 minutes
- **Immediate ping on background**: Sends ping immediately when going to background
- **Enhanced reconnection logic**: Immediate reconnection attempts on disconnection
- **Reduced connection check interval**: From 60 seconds to 30 seconds

**New Features**:
```dart
// Immediate ping when going to background
_sendImmediatePing();

// Aggressive pinging for first 5 minutes (every 5 seconds)
_startAggressivePingTimer();

// Regular pinging every 15 seconds
_startBackgroundPingTimer();

// Connection health checks every 30 seconds
_startConnectionCheckTimer();
```

### 2. Enhanced Socket Service

**File**: `lib/core/services/se_socket_service.dart`

**Key Changes**:
- **Reduced client heartbeat**: From 30 seconds to 15 seconds
- **Faster reconnection**: Reduced delays from 1000ms to 500ms
- **Shorter max reconnection delay**: From 10 seconds to 5 seconds

**Configuration Updates**:
```dart
'reconnectionDelay': 500,        // Was 1000ms
'reconnectionDelayMax': 5000,    // Was 10000ms
Timer.periodic(const Duration(seconds: 15), // Was 30 seconds
```

### 3. Enhanced Android Foreground Service

**File**: `android/app/src/main/kotlin/com/strapblaque/sechat/SocketForegroundService.kt`

**Key Changes**:
- **Enhanced service persistence**: Added `START_REDELIVER_INTENT` flag
- **Better service restart**: Service will restart if killed by system

**Service Configuration**:
```kotlin
// Return START_STICKY to restart service if killed by system
// Also return START_REDELIVER_INTENT to redeliver the intent if service is killed
return START_STICKY or START_REDELIVER_INTENT
```

## Technical Implementation Details

### Aggressive Ping Strategy

**Phase 1 (First 5 minutes)**:
- **Frequency**: Every 5 seconds
- **Purpose**: Maintain connection during critical period
- **Auto-stop**: After 60 pings (5 minutes)

**Phase 2 (Ongoing)**:
- **Frequency**: Every 15 seconds
- **Purpose**: Long-term connection maintenance
- **Continuous**: Until app returns to foreground

### Immediate Reconnection Logic

**On Disconnection Detection**:
1. **Immediate reconnection attempt** via `socketService.connect()`
2. **Comprehensive logging** for debugging
3. **Error handling** for failed reconnection attempts
4. **Multiple trigger points** (ping failures, connection checks)

### Enhanced Monitoring

**Connection Health Checks**:
- **Frequency**: Every 30 seconds
- **Actions**: Immediate reconnection if disconnected
- **Logging**: Comprehensive status reporting

**Status Tracking**:
```dart
Map<String, dynamic> getStatus() {
  return {
    'isBackgroundMode': _isBackgroundMode,
    'backgroundPingCount': _backgroundPingCount,
    'aggressivePingCount': _aggressivePingCount,
    'isPingTimerActive': _backgroundPingTimer?.isActive ?? false,
    'isAggressivePingTimerActive': _aggressivePingTimer?.isActive ?? false,
    'isCheckTimerActive': _connectionCheckTimer?.isActive ?? false,
  };
}
```

## Expected Behavior

### Before Fix
- ❌ Notifications work for first 20 seconds
- ❌ Socket disconnects after 30 seconds
- ❌ No notifications after 30 seconds
- ❌ No automatic reconnection

### After Fix
- ✅ Notifications work immediately
- ✅ Aggressive pinging for first 5 minutes
- ✅ Regular pinging every 15 seconds
- ✅ Immediate reconnection on disconnection
- ✅ Notifications work for extended background periods

## Testing Scenarios

### 1. **Immediate Background Test**
- Send message within 5 seconds of going to background
- **Expected**: Notification received immediately

### 2. **Short Background Test**
- Send message after 30 seconds in background
- **Expected**: Notification received (aggressive pinging active)

### 3. **Medium Background Test**
- Send message after 2 minutes in background
- **Expected**: Notification received (aggressive pinging active)

### 4. **Long Background Test**
- Send message after 10 minutes in background
- **Expected**: Notification received (regular pinging active)

### 5. **Reconnection Test**
- Force socket disconnection, then send message
- **Expected**: Automatic reconnection and notification

## Monitoring and Debugging

### Key Log Messages
```
🔧 BackgroundConnectionManager: 🚀 Sending immediate ping
🔧 BackgroundConnectionManager: 🚀 Aggressive ping #X
🔧 BackgroundConnectionManager: 🔄 Background ping #X
🔧 BackgroundConnectionManager: 🔄 Attempting immediate reconnection
🔧 BackgroundConnectionManager: ✅ Reconnection attempt initiated
```

### Status Monitoring
- **Aggressive ping count**: Tracks pings in first 5 minutes
- **Background ping count**: Tracks ongoing pings
- **Timer status**: Shows which timers are active
- **Connection status**: Real-time socket connection state

## Performance Considerations

### Battery Usage
- **Aggressive pinging**: Only for first 5 minutes
- **Optimized intervals**: Balanced between reliability and battery
- **Foreground service**: Low-priority notification

### Network Usage
- **Efficient pings**: Small presence updates
- **Smart reconnection**: Only when needed
- **Connection reuse**: Maintains existing connections

## Files Modified

### Primary Changes
- **`lib/core/services/background_connection_manager.dart`**: Enhanced ping strategy and reconnection
- **`lib/core/services/se_socket_service.dart`**: Faster reconnection and heartbeat
- **`android/app/src/main/kotlin/com/strapblaque/sechat/SocketForegroundService.kt`**: Enhanced persistence

### Supporting Infrastructure
- **Notification service**: Already enhanced for background notifications
- **App lifecycle handler**: Already integrated with background manager
- **Android manifest**: Already configured for foreground service

## Next Steps

1. **Test the enhanced implementation** - Send messages at various background intervals
2. **Monitor logs** - Check for aggressive pinging and reconnection attempts
3. **Verify notifications** - Ensure notifications work after 30+ seconds
4. **Performance monitoring** - Check battery usage and network efficiency

## Notes
- The aggressive pinging strategy ensures connection stability during the critical first 5 minutes
- Regular pinging maintains long-term connection health
- Immediate reconnection attempts minimize notification delays
- Enhanced foreground service provides better Android background support
- Comprehensive logging helps identify any remaining issues
