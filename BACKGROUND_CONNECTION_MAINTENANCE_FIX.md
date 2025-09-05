# Background Connection Maintenance Fix

## Problem
The app was disconnecting from the server when left in background for too long, preventing users from receiving messages and push notifications. This was caused by:

1. **Android system killing background processes** to preserve battery
2. **Socket connection not being maintained** in background
3. **Foreground service not starting** properly
4. **LED notification errors** on older Android versions

## Root Causes Identified

### 1. Socket Disconnection in Background
- Android aggressively kills background processes
- Socket connections are lost when app goes to background
- No mechanism to maintain connection during background state

### 2. Foreground Service Issues
- Foreground service wasn't starting when app went to background
- Missing proper error handling and debugging
- Service not properly integrated with app lifecycle

### 3. Notification Errors
- LED notification configuration missing required parameters
- Causing crashes on older Android versions (pre-Oreo)

## Solutions Implemented

### 1. Enhanced Foreground Service Management

#### Android Foreground Service
- **File**: `android/app/src/main/kotlin/com/strapblaque/sechat/SocketForegroundService.kt`
- **Features**:
  - Low-priority notification to avoid user annoyance
  - Automatic restart if killed by system (START_STICKY)
  - Proper lifecycle management
  - Data sync foreground service type

#### Method Channel Integration
- **File**: `android/app/src/main/kotlin/com/strapblaque/sechat/MethodChannelHandler.kt`
- **Methods**:
  - `startForegroundService()`: Start the service
  - `stopForegroundService()`: Stop the service
  - `isForegroundServiceRunning()`: Check service status

#### Flutter Service Manager
- **File**: `lib/core/services/foreground_service_manager.dart`
- **Purpose**: Flutter interface to control Android foreground service
- **Features**:
  - Platform-specific implementation (Android only)
  - Error handling and logging
  - Simple API for service control

### 2. Background Connection Manager

#### New Service
- **File**: `lib/core/services/background_connection_manager.dart`
- **Purpose**: Maintains socket connection in background
- **Features**:
  - Background ping timer (every 30 seconds)
  - Connection health checks (every 60 seconds)
  - Automatic reconnection attempts
  - Foreground service integration

#### Key Methods
```dart
// Start background maintenance
await BackgroundConnectionManager().startBackgroundMaintenance();

// Stop background maintenance
await BackgroundConnectionManager().stopBackgroundMaintenance();

// Get status
Map<String, dynamic> status = BackgroundConnectionManager().getStatus();
```

### 3. Enhanced App Lifecycle Handling

#### Updated App Lifecycle Handler
- **File**: `lib/shared/widgets/app_lifecycle_handler.dart`
- **Changes**:
  - Integrated BackgroundConnectionManager
  - Enhanced debugging and logging
  - Better error handling
  - Platform-specific logic

#### Background State Handling
```dart
void _handleAppPaused() async {
  // Start background connection maintenance
  await BackgroundConnectionManager().startBackgroundMaintenance();
}

void _handleAppResumed() async {
  // Stop background connection maintenance
  await BackgroundConnectionManager().stopBackgroundMaintenance();
}
```

### 4. Fixed Notification LED Errors

#### Android Notification Configuration
- **File**: `lib/features/notifications/services/local_notification_badge_service.dart`
- **Fix**: Added required LED parameters for older Android versions
- **Changes**:
  ```dart
  enableLights: true,
  ledColor: Color(0xFFFF6B35),
  ledOnMs: 1000,        // Added
  ledOffMs: 1000,       // Added
  ```

## Technical Implementation Details

### Background Connection Maintenance Flow

1. **App Goes to Background**:
   - `_handleAppPaused()` is called
   - `BackgroundConnectionManager.startBackgroundMaintenance()` is invoked
   - Android foreground service starts
   - Background ping timer starts (30s intervals)
   - Connection check timer starts (60s intervals)

2. **Background Maintenance**:
   - Sends keepalive pings to maintain socket connection
   - Monitors connection health
   - Attempts reconnection if disconnected
   - Foreground service keeps app process alive

3. **App Returns to Foreground**:
   - `_handleAppResumed()` is called
   - `BackgroundConnectionManager.stopBackgroundMaintenance()` is invoked
   - Android foreground service stops
   - All background timers are cancelled

### Socket Service Integration

The socket service already has built-in reconnection capabilities:
- **Reconnection enabled**: `reconnection: true`
- **Max attempts**: `reconnectionAttempts: 10`
- **Exponential backoff**: `reconnectionDelayFactor: 1.5`
- **Transport fallback**: `transports: ['websocket', 'polling']`

### Foreground Service Configuration

#### Android Manifest
```xml
<service
    android:name=".SocketForegroundService"
    android:enabled="true"
    android:exported="false"
    android:foregroundServiceType="dataSync" />
```

#### Service Features
- **Low priority notification**: Minimal user impact
- **Data sync type**: Appropriate for messaging apps
- **Automatic restart**: START_STICKY behavior
- **Proper cleanup**: Resource management

## Expected Behavior

### Android
1. **Foreground**: Normal operation, no foreground service
2. **Background**: 
   - Foreground service starts with low-priority notification
   - Background ping timer maintains socket connection
   - Connection health monitoring
   - Automatic reconnection if needed
3. **Return to Foreground**: 
   - Foreground service stops
   - Background timers cancelled
   - Normal operation resumes

### iOS
1. **Foreground**: Normal operation
2. **Background**: 
   - Background processing capabilities enabled
   - Socket connection maintained through background modes
3. **Return to Foreground**: Normal operation resumes

## Monitoring and Debugging

### Log Messages
The implementation includes comprehensive logging:
- **Background service start/stop**: Clear success/failure messages
- **Connection health**: Regular status updates
- **Reconnection attempts**: Detailed reconnection logs
- **Error handling**: Proper error reporting

### Status Monitoring
```dart
Map<String, dynamic> status = BackgroundConnectionManager().getStatus();
// Returns: isBackgroundMode, backgroundPingCount, timer status
```

## Files Modified

### Android
- `android/app/src/main/kotlin/com/strapblaque/sechat/SocketForegroundService.kt` (new)
- `android/app/src/main/kotlin/com/strapblaque/sechat/MethodChannelHandler.kt` (new)
- `android/app/src/main/kotlin/com/strapblaque/sechat/MainActivity.kt` (updated)
- `android/app/src/main/AndroidManifest.xml` (updated)

### Flutter
- `lib/core/services/background_connection_manager.dart` (new)
- `lib/core/services/foreground_service_manager.dart` (new)
- `lib/shared/widgets/app_lifecycle_handler.dart` (updated)
- `lib/features/notifications/services/local_notification_badge_service.dart` (updated)

## Benefits

1. **Reliable Background Messaging**: Users receive messages even when app is backgrounded
2. **Battery Efficient**: Low-priority foreground service with minimal impact
3. **Automatic Recovery**: Handles network issues and reconnections
4. **Cross-Platform**: Works on both Android and iOS
5. **User-Friendly**: Minimal notification impact, seamless experience
6. **Robust Error Handling**: Comprehensive error management and logging

## Testing

### Manual Testing Steps
1. **Start app** and verify normal operation
2. **Send app to background** and verify:
   - Foreground service notification appears (Android)
   - Socket connection remains active
   - Background ping logs appear
3. **Send test message** from another device
4. **Verify message is received** in background
5. **Return to foreground** and verify:
   - Foreground service stops
   - Normal operation resumes

### Expected Results
- ✅ Socket stays connected in background
- ✅ Messages received in background
- ✅ Push notifications work properly
- ✅ Foreground service starts/stops correctly
- ✅ No notification LED errors
- ✅ Automatic reconnection works
- ✅ Battery usage remains reasonable

## Notes
- The foreground service uses minimal resources
- Background pings are lightweight and efficient
- Connection health checks prevent silent failures
- All timers are properly cleaned up
- Platform-specific optimizations applied
