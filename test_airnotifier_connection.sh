#!/bin/bash

# Test AirNotifier Connection Script
# This script tests the basic connectivity to AirNotifier

BASE_URL="http://41.76.111.100:8801"
APP_NAME="sechat"
APP_KEY="ebea679133a7adfb9c4cd1f8b6a4fdc9"

echo "🧪 Testing AirNotifier Connection..."
echo "📍 Base URL: $BASE_URL"
echo "📱 App Name: $APP_NAME"
echo "🔑 App Key: $APP_KEY"
echo ""

# Test 1: Basic API endpoint
echo "🔍 Test 1: Testing basic API endpoint..."
curl -s -X GET \
  -H "X-An-App-Name: $APP_NAME" \
  -H "X-An-App-Key: $APP_KEY" \
  "$BASE_URL/api/v2/tokens" \
  -w "\nStatus: %{http_code}\n" \
  -o /dev/null

echo ""

# Test 2: Test with a sample session ID
SESSION_ID="test_session_123"
echo "🔍 Test 2: Testing session tokens endpoint with session ID: $SESSION_ID..."
curl -s -X GET \
  -H "X-An-App-Name: $APP_NAME" \
  -H "X-An-App-Key: $APP_KEY" \
  "$BASE_URL/api/v2/sessions/$SESSION_ID/tokens" \
  -w "\nStatus: %{http_code}\n" \
  -o /dev/null

echo ""

# Test 3: Register a test device token
DEVICE_TOKEN="test_device_token_$(date +%s)"
echo "🔍 Test 3: Registering test device token: $DEVICE_TOKEN..."
curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "X-An-App-Name: $APP_NAME" \
  -H "X-An-App-Key: $APP_KEY" \
  -d "{
    \"token\": \"$DEVICE_TOKEN\",
    \"device\": \"android\",
    \"channel\": \"default\",
    \"user_id\": \"$SESSION_ID\"
  }" \
  "$BASE_URL/api/v2/tokens" \
  -w "\nStatus: %{http_code}\n"

echo ""

# Test 4: Link token to session
echo "🔍 Test 4: Linking token to session..."
curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "X-An-App-Name: $APP_NAME" \
  -H "X-An-App-Key: $APP_KEY" \
  -d "{
    \"token\": \"$DEVICE_TOKEN\",
    \"session_id\": \"$SESSION_ID\"
  }" \
  "$BASE_URL/api/v2/sessions/link" \
  -w "\nStatus: %{http_code}\n"

echo ""

# Test 5: Send a test notification
echo "🔍 Test 5: Sending test notification..."
curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "X-An-App-Name: $APP_NAME" \
  -H "X-An-App-Key: $APP_KEY" \
  -d "{
    \"session_id\": \"$SESSION_ID\",
    \"alert\": {
      \"title\": \"Test Notification\",
      \"body\": \"This is a test notification from SeChat\"
    },
    \"data\": {
      \"type\": \"test\",
      \"message\": \"Hello from AirNotifier!\"
    },
    \"sound\": \"default\",
    \"badge\": 1
  }" \
  "$BASE_URL/api/v2/notifications/session" \
  -w "\nStatus: %{http_code}\n"

echo ""

echo "✅ AirNotifier connection tests completed!"
echo "📊 Check the status codes above to verify connectivity."
echo "🔗 Use the Postman collection for more detailed testing." 