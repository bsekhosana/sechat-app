# Invitation Notifications & Blue Dot Badge System

## Overview

The SeChat Flutter app now includes a comprehensive real-time notification system for invitations with a modern blue dot badge indicator. This system ensures users are notified of new invitations even when they're not actively viewing the invitations screen.

## Features

### 🔵 Blue Dot Badge
- **Replaces counter badge**: Clean, modern blue dot instead of number counter
- **Real-time updates**: Badge appears/disappears instantly with Socket.IO events
- **Smart visibility**: Only shows when there are unread invitations
- **Visual design**: Blue glow effect with subtle shadow for better visibility

### 📱 Local Notifications
- **Platform-aware**: Works on mobile, gracefully skips on web
- **Smart triggering**: Only shows notifications when user is not on invitations screen
- **Rich content**: Includes sender username and invitation message
- **Response notifications**: Notifies when invitations are accepted/declined

### 🔄 Real-time Integration
- **Socket.IO powered**: Instant badge updates and notifications
- **Screen tracking**: Knows when user is viewing invitations
- **Lifecycle aware**: Handles app backgrounding/foregrounding
- **Fallback support**: Works with REST API when Socket.IO unavailable

## Architecture

### Badge State Management

The badge system tracks three key states:
- `_pendingReceivedCount`: New invitations from others
- `_responsesSentCount`: Responses to sent invitations  
- `_hasUnreadInvitations`: Overall badge visibility

### Screen Tracking

The system tracks when users are on the invitations screen:
- `_isOnInvitationsScreen`: Boolean flag for current screen state
- Automatic badge clearing when entering invitations screen
- Notification suppression when on screen

### Notification Flow

```
New Invitation Received
         ↓
Check if user on invitations screen
         ↓
If NOT on screen → Show local notification
         ↓
Update badge state
         ↓
Real-time UI update
```

## Implementation Details

### InvitationProvider Updates

```dart
class InvitationProvider extends ChangeNotifier {
  bool _isOnInvitationsScreen = false;
  bool _hasUnreadInvitations = false;
  
  // Track screen state
  void setOnInvitationsScreen(bool isOnScreen) {
    _isOnInvitationsScreen = isOnScreen;
    if (isOnScreen) {
      markAllInvitationsAsRead();
    }
  }
  
  // Smart notification triggering
  void _handleInvitationReceived(Map<String, dynamic> data) {
    // ... process invitation ...
    
    // Only show notification if not on screen
    if (!_isOnInvitationsScreen) {
      _triggerInvitationReceivedNotification(invitation);
    }
  }
}
```

### Main Navigation Badge

```dart
Widget _buildNavItem(int index, IconData icon, String label) {
  return Consumer<InvitationProvider>(
    builder: (context, invitationProvider, child) {
      final showBadge = index == 1 && invitationProvider.hasUnreadInvitations;
      
      return Stack(
        children: [
          // Navigation item content
          if (showBadge)
            Positioned(
              top: -2,
              right: 4,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2196F3).withOpacity(0.6),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
```

### Screen Lifecycle Management

```dart
class _InvitationsScreenState extends State<InvitationsScreen> 
    with WidgetsBindingObserver {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Mark as on invitations screen
    context.read<InvitationProvider>().setOnInvitationsScreen(true);
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Mark as not on invitations screen
    context.read<InvitationProvider>().setOnInvitationsScreen(false);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      context.read<InvitationProvider>().setOnInvitationsScreen(false);
    } else if (state == AppLifecycleState.resumed) {
      context.read<InvitationProvider>().setOnInvitationsScreen(true);
    }
  }
}
```

## Notification Service

### Platform Handling

```dart
Future<void> showInvitationReceivedNotification({
  required String senderUsername,
  required String message,
  required String invitationId,
}) async {
  if (kIsWeb) return; // Skip on web platform
  if (!_isInitialized) await initialize();
  
  // Show notification with rich content
  await _flutterLocalNotificationsPlugin.show(
    invitationId.hashCode,
    'New Invitation from $senderUsername',
    message,
    notificationDetails,
    payload: 'invitation_received:$invitationId',
  );
}
```

### Deep Linking

Notifications include payload data for deep linking:
- `invitation_received:$invitationId` → Navigate to received tab
- `invitation_response:$invitationId:$status` → Navigate to sent tab

## User Experience

### Badge Behavior
1. **Appears instantly** when new invitation received
2. **Disappears immediately** when user enters invitations screen
3. **Reappears** when new invitations arrive while on other screens
4. **Real-time updates** via Socket.IO connection

### Notification Behavior
1. **Shows on mobile** when invitation received and user not on screen
2. **Skips on web** (platform limitation)
3. **Rich content** with sender name and message
4. **Tap to navigate** directly to invitations screen

### Screen State Management
1. **Automatic tracking** of invitations screen visibility
2. **Badge clearing** when entering screen
3. **Notification suppression** when on screen
4. **Lifecycle awareness** for app backgrounding

## Testing

### Manual Testing Steps

1. **Send invitation** from another user/device
2. **Verify badge appears** on invitations tab
3. **Navigate to invitations** → badge should disappear
4. **Send another invitation** → notification should appear (mobile only)
5. **Tap notification** → should navigate to invitations screen
6. **Background app** → notifications should still work
7. **Web testing** → notifications should be skipped gracefully

### Socket.IO Testing

Use the Socket.IO test screen to verify real-time functionality:
1. Connect to socket server
2. Send test invitation
3. Verify badge updates instantly
4. Check notification delivery

## Configuration

### Badge Styling

The blue dot badge can be customized in `main_nav_screen.dart`:

```dart
// Badge appearance
color: const Color(0xFF2196F3), // Blue color
borderRadius: BorderRadius.circular(6),
boxShadow: [
  BoxShadow(
    color: const Color(0xFF2196F3).withOpacity(0.6),
    blurRadius: 4,
    spreadRadius: 1,
  ),
],
```

### Notification Channels

Android notification channels are configured in `notification_service.dart`:
- `invitation_received`: High priority, vibration, sound
- `invitation_response`: High priority, vibration, sound

## Troubleshooting

### Common Issues

1. **Badge not appearing**: Check Socket.IO connection and invitation provider state
2. **Notifications not showing**: Verify notification permissions on mobile
3. **Web notifications**: Expected behavior - notifications are skipped on web
4. **Badge not clearing**: Ensure proper screen state tracking

### Debug Logging

Enable debug logging to troubleshoot:
```dart
print('📱 InvitationProvider: Badge counts updated - Pending received: $_pendingReceivedCount, Responses sent: $_responsesSentCount, Has unread: $_hasUnreadInvitations');
```

## Future Enhancements

### Potential Improvements

1. **Web notifications**: Browser notification API integration
2. **Custom badge colors**: Different colors for different invitation types
3. **Badge animations**: Smooth fade in/out animations
4. **Notification grouping**: Group multiple invitations in single notification
5. **Sound customization**: User-configurable notification sounds

### Performance Considerations

- Badge updates are lightweight and real-time
- Screen tracking uses minimal resources
- Notifications are platform-optimized
- Socket.IO ensures efficient real-time updates

## Migration Notes

### From Counter Badge

The system replaces the previous counter badge with a cleaner dot design:
- **Before**: Red badge with number (e.g., "3")
- **After**: Blue dot with glow effect
- **Benefits**: More space-efficient, modern design, better UX

### Backward Compatibility

- All existing invitation functionality preserved
- Socket.IO integration maintains compatibility
- Notification payloads remain unchanged
- Deep linking behavior consistent 