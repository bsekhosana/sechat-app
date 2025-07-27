#!/bin/bash

# Test Updated AirNotifier Configuration
# This script tests the correct base URL and payload format

BASE_URL="https://push.strapblaque.com"
APP_NAME="sechat"
APP_KEY="ebea679133a7adfb9c4cd1f8b6a4fdc9"
SESSION_ID="gc4PvCrQg53LY4Kv10TXC0IISxJsf8uZ9t9THTiw0AA"

echo "🧪 Testing Updated AirNotifier Configuration..."
echo "📍 Base URL: $BASE_URL"
echo "📱 App Name: $APP_NAME"
echo "🔑 App Key: $APP_KEY"
echo "🆔 Session ID: $SESSION_ID"
echo ""

# Test 1: Check if session exists and has tokens
echo "🔍 Test 1: Checking session tokens for: $SESSION_ID..."
curl -s -X GET \
  -H "X-An-App-Name: $APP_NAME" \
  -H "X-An-App-Key: $APP_KEY" \
  "$BASE_URL/api/v2/sessions/$SESSION_ID/tokens" \
  -w "\nStatus: %{http_code}\n"

echo ""

# Test 2: Send a test notification with correct payload format
echo "🔍 Test 2: Sending test notification with correct payload format..."
curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "X-An-App-Name: $APP_NAME" \
  -H "X-An-App-Key: $APP_KEY" \
  -d "{
    \"session_id\": \"$SESSION_ID\",
    \"alert\": {
      \"title\": \"Test from Updated Postman\",
      \"body\": \"This is a test notification with correct format\"
    },
    \"data\": {
      \"type\": \"test\",
      \"message\": \"Hello from updated configuration!\"
    },
    \"sound\": \"default\",
    \"badge\": 1
  }" \
  "$BASE_URL/api/v2/notifications/session" \
  -w "\nStatus: %{http_code}\n"

echo ""

# Test 3: Send invitation notification with correct format
echo "🔍 Test 3: Sending invitation notification with correct format..."
curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "X-An-App-Name: $APP_NAME" \
  -H "X-An-App-Key: $APP_KEY" \
  -d "{
    \"session_id\": \"$SESSION_ID\",
    \"alert\": {
      \"title\": \"New Contact Invitation\",
      \"body\": \"John Doe would like to connect with you\"
    },
    \"data\": {
      \"type\": \"invitation\",
      \"invitationId\": \"inv_123456789\",
      \"senderName\": \"John Doe\",
      \"senderId\": \"$SESSION_ID\",
      \"message\": \"Would you like to connect?\",
      \"timestamp\": 1730728000000
    },
    \"sound\": \"invitation.wav\",
    \"badge\": 1
  }" \
  "$BASE_URL/api/v2/notifications/session" \
  -w "\nStatus: %{http_code}\n"

echo ""

echo "✅ Updated AirNotifier configuration tests completed!"
echo "📊 Check the status codes above to verify connectivity."
echo "🔗 The Postman collection has been updated with the correct format." 