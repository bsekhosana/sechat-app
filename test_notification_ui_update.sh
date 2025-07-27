#!/bin/bash

# Test Notification UI Update Flow
# This script sends a test invitation notification to verify UI updates

BASE_URL="https://push.strapblaque.com"
APP_NAME="sechat"
APP_KEY="ebea679133a7adfb9c4cd1f8b6a4fdc9"
SESSION_ID="gc4PvCrQg53LY4Kv10TXC0IISxJsf8uZ9t9THTiw0AA"

echo "🧪 Testing Notification UI Update Flow..."
echo "📍 Base URL: $BASE_URL"
echo "🆔 Session ID: $SESSION_ID"
echo ""

# Send test invitation notification
echo "🔍 Sending test invitation notification..."
curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "X-An-App-Name: $APP_NAME" \
  -H "X-An-App-Key: $APP_KEY" \
  -d "{
    \"session_id\": \"$SESSION_ID\",
    \"alert\": {
      \"title\": \"Test UI Update\",
      \"body\": \"Testing UI update flow\"
    },
    \"data\": {
      \"type\": \"invitation\",
      \"invitationId\": \"test_ui_update_$(date +%s)\",
      \"senderName\": \"Test User\",
      \"senderId\": \"test_sender_$(date +%s)\",
      \"message\": \"Testing UI update functionality\",
      \"timestamp\": $(date +%s)000
    },
    \"sound\": \"invitation.wav\",
    \"badge\": 1
  }" \
  "$BASE_URL/api/v2/notifications/session" \
  -w "\nStatus: %{http_code}\n"

echo ""
echo "✅ Test notification sent!"
echo "📱 Check the app logs for:"
echo "   - Notification received"
echo "   - Data extracted from nested field"
echo "   - Invitation saved to local storage"
echo "   - InvitationProvider local storage change"
echo "   - UI update triggered"
echo ""
echo "🔍 Expected log sequence:"
echo "   1. 🔔 SimpleNotificationService: Found data in nested field"
echo "   2. 🔔 SimpleNotificationService: Processing invitation from Test User"
echo "   3. 🔔 SimpleNotificationService: ✅ Invitation saved to local storage"
echo "   4. 📱 InvitationProvider: Local storage changed, reloading invitations..."
echo "   5. 📱 InvitationProvider: ✅ Notified listeners of invitation update" 