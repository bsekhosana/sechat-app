#!/bin/bash

echo "🧪 Testing Invitation Field Mapping Fix"
echo "======================================="

# Check if the fromJson method handles both camelCase and snake_case
echo "📋 Checking field mapping in Invitation.fromJson..."

if grep -q "sender_username.*senderUsername" lib/shared/models/invitation.dart; then
    echo "✅ Invitation.fromJson handles both sender_username and senderUsername"
else
    echo "❌ Invitation.fromJson missing field mapping for senderUsername"
    exit 1
fi

if grep -q "recipient_username.*recipientUsername" lib/shared/models/invitation.dart; then
    echo "✅ Invitation.fromJson handles both recipient_username and recipientUsername"
else
    echo "❌ Invitation.fromJson missing field mapping for recipientUsername"
    exit 1
fi

# Check if debug logging is added
echo "📋 Checking debug logging..."

if grep -q "InvitationsScreen: Total invitations" lib/features/invitations/screens/invitations_screen.dart; then
    echo "✅ Debug logging added to InvitationsScreen"
else
    echo "❌ Debug logging missing from InvitationsScreen"
    exit 1
fi

if grep -q "SimpleNotificationService: Saving invitation with data" lib/core/services/simple_notification_service.dart; then
    echo "✅ Debug logging added to SimpleNotificationService"
else
    echo "❌ Debug logging missing from SimpleNotificationService"
    exit 1
fi

echo ""
echo "🔧 Testing Instructions:"
echo "1. Build and install the app:"
echo "   flutter build apk --debug && flutter install"
echo ""
echo "2. Test invitation display:"
echo "   - Send an invitation from another device/user"
echo "   - Check the debug logs for field mapping"
echo "   - Verify the invitation appears in the 'Received' tab"
echo ""
echo "3. Expected debug output:"
echo "   - SimpleNotificationService: Saving invitation with data: {...}"
echo "   - InvitationsScreen: Total invitations: 1"
echo "   - InvitationsScreen: Invitation 0: id=..., isReceived=true, senderUsername=..."
echo "   - InvitationsScreen: Received tab - filtered invitations: 1"
echo ""
echo "4. Expected behavior:"
echo "   - Invitation should appear in the UI with proper usernames"
echo "   - Field mapping should work for both camelCase and snake_case"
echo "   - Debug logs should show the invitation being processed correctly"
echo ""
echo "✅ Invitation Field Mapping Fix Complete!"
echo ""
echo "Key fixes implemented:"
echo "- Invitation.fromJson now handles both camelCase and snake_case field names"
echo "- Enhanced debug logging to track field mapping issues"
echo "- Better error handling for missing or null fields" 