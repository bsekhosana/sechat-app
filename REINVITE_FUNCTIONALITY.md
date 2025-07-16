# Reinvite Functionality for SeChat

## Overview

The SeChat app now includes a comprehensive reinvite system that allows users to send new invitations to users who have previously declined or deleted invitations. This feature enhances the user experience by providing clear visual feedback and easy reinvitation capabilities.

## Features

### 🔄 **Smart Invitation Status Tracking**
- **Detailed status tracking**: Tracks invitation status (pending, accepted, declined, deleted)
- **Visual indicators**: Different buttons and colors based on invitation status
- **Reinvite capability**: Allows sending new invitations to declined/deleted users
- **Status persistence**: Maintains invitation history for proper reinvite logic

### 🎨 **Visual Design System**
- **Pending invitations**: Orange "Invited" badge
- **New invitations**: Orange "Invite" button with person icon
- **Reinvite**: Blue "Reinvite" button with refresh icon
- **Accepted invitations**: Green "Accepted" badge
- **Declined/Deleted**: Red status text with reinvite option

### 🔧 **Backend Integration**
- **Enhanced search API**: Returns detailed invitation status information
- **Database migration**: Added 'deleted' status to invitation enum
- **Smart invitation logic**: Prevents duplicate pending invitations while allowing reinvites
- **Clean data management**: Automatically removes old declined/deleted invitations

## Implementation Details

### User Model Updates

The `User` model now includes detailed invitation status tracking:

```dart
class User {
  final String? invitationStatus; // 'pending', 'accepted', 'declined', 'deleted', null
  final String? invitationId; // ID of the invitation if exists
  
  // Helper methods for invitation status
  bool get canReinvite => 
      invitationStatus == 'declined' || 
      invitationStatus == 'deleted' || 
      (!alreadyInvited && invitationStatus == null);
  
  bool get hasPendingInvitation => invitationStatus == 'pending';
  bool get hasDeclinedInvitation => invitationStatus == 'declined';
  bool get hasDeletedInvitation => invitationStatus == 'deleted';
  
  String get invitationStatusText {
    switch (invitationStatus) {
      case 'pending': return 'Invited';
      case 'accepted': return 'Accepted';
      case 'declined': return 'Declined';
      case 'deleted': return 'Deleted';
      default: return 'Invite';
    }
  }
}
```

### Search API Enhancement

The backend search endpoint now returns detailed invitation information:

```php
// Fetch invitation information for each user
$invitationData = [];
if ($currentUser) {
    $invitations = \App\Models\Invitation::where('sender_id', $currentUser->id)
        ->select('recipient_id', 'status', 'id')
        ->get();
    
    foreach ($invitations as $invitation) {
        $invitationData[$invitation->recipient_id] = [
            'status' => $invitation->status,
            'id' => $invitation->id,
        ];
    }
}

$results = $users->map(function ($user) use ($invitationData) {
    $invitationInfo = $invitationData[$user->id] ?? null;
    
    return [
        'id' => $user->id,
        'username' => $user->username,
        'is_online' => $user->is_online,
        'last_seen' => $user->last_seen,
        'created_at' => $user->created_at,
        'already_invited' => $invitationInfo !== null,
        'invitation_status' => $invitationInfo['status'] ?? null,
        'invitation_id' => $invitationInfo['id'] ?? null,
    ];
})->values();
```

### Database Migration

Added 'deleted' status to the invitations table:

```php
Schema::table('invitations', function (Blueprint $table) {
    $table->enum('status', ['pending', 'accepted', 'declined', 'deleted'])
          ->default('pending')
          ->change();
});
```

### Invitation Creation Logic

Updated invitation creation to allow reinviting:

```php
// Check if pending invitation already exists
$existingPendingInvitation = Invitation::where('sender_id', $user->id)
    ->where('recipient_id', $request->recipient_id)
    ->where('status', 'pending')
    ->first();

if ($existingPendingInvitation) {
    return response()->json([
        'success' => false,
        'message' => 'Invitation already sent'
    ], 400);
}

// Delete any previous declined/deleted invitations to allow reinviting
Invitation::where('sender_id', $user->id)
    ->where('recipient_id', $request->recipient_id)
    ->whereIn('status', ['declined', 'deleted'])
    ->delete();

// Create new invitation
$invitation = Invitation::create([
    'sender_id' => $user->id,
    'recipient_id' => $request->recipient_id,
    'message' => $request->message,
    'status' => 'pending',
]);
```

### UI Implementation

The search overlay now shows different buttons based on invitation status:

```dart
trailing: user.hasPendingInvitation
    ? Container(
        // "Invited" badge for pending invitations
        child: const Text('Invited'),
      )
    : user.canReinvite
        ? Container(
            // Invite/Reinvite button
            decoration: BoxDecoration(
              color: user.hasDeclinedInvitation || user.hasDeletedInvitation
                  ? const Color(0xFF2196F3) // Blue for reinvite
                  : const Color(0xFFFF6B35), // Orange for new invite
            ),
            child: IconButton(
              icon: Icon(
                user.hasDeclinedInvitation || user.hasDeletedInvitation
                    ? Icons.refresh // Refresh icon for reinvite
                    : Icons.person_add, // Person add for new invite
              ),
              onPressed: () => _handleInvitation(user),
            ),
          )
        : Container(
            // Status text for accepted/other states
            child: Text(user.invitationStatusText),
          ),
```

## User Experience Flow

### 1. **New User Search**
- User searches for someone they haven't invited
- Shows orange "Invite" button with person icon
- Clicking sends invitation and changes to "Invited" status

### 2. **Pending Invitation**
- User searches for someone with pending invitation
- Shows orange "Invited" badge
- No action button (invitation already sent)

### 3. **Declined Invitation**
- User searches for someone who declined their invitation
- Shows blue "Reinvite" button with refresh icon
- Clicking sends new invitation and changes to "Invited" status

### 4. **Deleted Invitation**
- User searches for someone whose invitation was deleted
- Shows blue "Reinvite" button with refresh icon
- Clicking sends new invitation and changes to "Invited" status

### 5. **Accepted Invitation**
- User searches for someone who accepted their invitation
- Shows green "Accepted" badge
- No action button (chat already exists)

## Visual Design System

### Color Scheme
- **Orange (#FF6B35)**: New invitations and pending status
- **Blue (#2196F3)**: Reinvite actions
- **Green (#4CAF50)**: Accepted invitations
- **Red (#FF5555)**: Declined/deleted status text

### Icon System
- **Person Add Icon**: New invitations
- **Refresh Icon**: Reinvite actions
- **No Icon**: Status badges (Invited, Accepted, etc.)

### Button States
- **Primary Action**: Orange/Blue buttons for invite/reinvite
- **Status Display**: Text badges for current status
- **Disabled State**: No button for pending/accepted invitations

## Backend Architecture

### Database Schema
```sql
CREATE TABLE invitations (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    sender_id BIGINT NOT NULL,
    recipient_id BIGINT NOT NULL,
    message TEXT NOT NULL,
    status ENUM('pending', 'accepted', 'declined', 'deleted') DEFAULT 'pending',
    accepted_at TIMESTAMP NULL,
    declined_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_recipient_status (recipient_id, status),
    INDEX idx_sender_status (sender_id, status)
);
```

### API Endpoints
- **GET /api/search**: Returns users with invitation status
- **POST /api/invitations**: Creates new invitation (handles reinvite)
- **POST /api/invitations/{id}/accept**: Accepts invitation
- **POST /api/invitations/{id}/decline**: Declines invitation
- **DELETE /api/invitations/{id}**: Deletes invitation

### Business Logic
1. **Prevent Duplicate Pending**: Only one pending invitation allowed
2. **Allow Reinvite**: Delete old declined/deleted invitations before creating new ones
3. **Status Tracking**: Maintain complete invitation history
4. **Real-time Updates**: Socket.IO integration for instant status updates

## Testing Scenarios

### Manual Testing Checklist

1. **New Invitation**
   - [ ] Search for new user
   - [ ] Verify orange "Invite" button appears
   - [ ] Send invitation
   - [ ] Verify button changes to "Invited" badge

2. **Reinvite Declined User**
   - [ ] Search for user who declined invitation
   - [ ] Verify blue "Reinvite" button appears
   - [ ] Send reinvitation
   - [ ] Verify button changes to "Invited" badge

3. **Reinvite Deleted User**
   - [ ] Search for user whose invitation was deleted
   - [ ] Verify blue "Reinvite" button appears
   - [ ] Send reinvitation
   - [ ] Verify button changes to "Invited" badge

4. **Accepted Invitation**
   - [ ] Search for user who accepted invitation
   - [ ] Verify green "Accepted" badge appears
   - [ ] Verify no action button is shown

5. **Pending Invitation**
   - [ ] Search for user with pending invitation
   - [ ] Verify orange "Invited" badge appears
   - [ ] Verify no action button is shown

### API Testing
```bash
# Search for users with invitation status
curl -X GET "https://sechat.strapblaque.com/api/search?query=username" \
  -H "Device-ID: your-device-id"

# Send invitation (new or reinvite)
curl -X POST "https://sechat.strapblaque.com/api/invitations" \
  -H "Content-Type: application/json" \
  -H "Device-ID: your-device-id" \
  -d '{"recipient_id": "123", "message": "Hi! Let\'s chat!"}'
```

## Error Handling

### Common Error Scenarios
1. **Duplicate Pending**: "Invitation already sent"
2. **Self Invitation**: "Cannot send invitation to yourself"
3. **Existing Chat**: "Chat already exists with this user"
4. **User Not Found**: "User not found"

### Graceful Degradation
- Fallback to basic invitation status if detailed info unavailable
- Clear error messages for user feedback
- Automatic retry logic for network issues

## Performance Considerations

### Database Optimization
- Indexed queries for invitation status lookups
- Efficient joins for user search with invitation data
- Cleanup of old declined/deleted invitations

### Frontend Optimization
- Debounced search to reduce API calls
- Cached invitation status data
- Efficient UI updates with minimal re-renders

## Future Enhancements

### Potential Improvements
1. **Bulk Reinvite**: Reinvite multiple users at once
2. **Invitation Templates**: Predefined invitation messages
3. **Invitation Analytics**: Track invitation success rates
4. **Smart Suggestions**: Suggest users to reinvite based on activity
5. **Invitation Scheduling**: Schedule invitations for later

### Advanced Features
1. **Invitation Limits**: Prevent spam with rate limiting
2. **Invitation Expiry**: Auto-expire old pending invitations
3. **Invitation Categories**: Different types of invitations
4. **Invitation Responses**: Allow custom decline reasons

## Migration Notes

### From Previous Version
- **Breaking Changes**: None - fully backward compatible
- **Database Changes**: Added 'deleted' status to invitations table
- **API Changes**: Enhanced search endpoint with invitation status
- **UI Changes**: New button states and visual indicators

### Backward Compatibility
- Existing invitations continue to work normally
- Old API responses still supported
- Gradual migration to new invitation status system

## Troubleshooting

### Common Issues
1. **Reinvite button not showing**: Check invitation status in database
2. **Duplicate invitations**: Verify pending invitation check logic
3. **Status not updating**: Check Socket.IO connection and event handling
4. **Button colors incorrect**: Verify invitation status mapping

### Debug Information
```dart
// Debug invitation status
print('User: ${user.username}');
print('Already invited: ${user.alreadyInvited}');
print('Invitation status: ${user.invitationStatus}');
print('Can reinvite: ${user.canReinvite}');
print('Has declined: ${user.hasDeclinedInvitation}');
print('Has deleted: ${user.hasDeletedInvitation}');
```

The reinvite functionality provides a seamless user experience for managing invitations and maintaining connections with other users in the SeChat platform. 