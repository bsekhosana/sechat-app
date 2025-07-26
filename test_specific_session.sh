#!/bin/bash

# Test Specific Session ID
# This script tests if a specific session ID exists and has tokens

BASE_URL="http://41.76.111.100:8801"
APP_NAME="sechat"
APP_KEY="ebea679133a7adfb9c4cd1f8b6a4fdc9"

# Test with the session ID from the logs
SESSION_ID="gc4PvCrQg53LY4Kv10TXC0IISxJsf8uZ9t9THTiw0AA"

echo "🧪 Testing Specific Session ID..."
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

# Test 2: Register a token for this session
DEVICE_TOKEN="android_real_token_$(date +%s)"
echo "🔍 Test 2: Registering token for session: $DEVICE_TOKEN..."
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

# Test 3: Link the token to the session
echo "🔍 Test 3: Linking token to session..."
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

# Test 4: Check session tokens again
echo "🔍 Test 4: Checking session tokens after registration..."
curl -s -X GET \
  -H "X-An-App-Name: $APP_NAME" \
  -H "X-An-App-Key: $APP_KEY" \
  "$BASE_URL/api/v2/sessions/$SESSION_ID/tokens" \
  -w "\nStatus: %{http_code}\n"

echo ""

# Test 5: Send a test notification to this session
echo "🔍 Test 5: Sending test notification to session..."
curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "X-An-App-Name: $APP_NAME" \
  -H "X-An-App-Key: $APP_KEY" \
  -d "{
    \"session_id\": \"$SESSION_ID\",
    \"alert\": {
      \"title\": \"Test from Postman\",
      \"body\": \"This is a test notification from Postman\"
    },
    \"data\": {
      \"type\": \"test\",
      \"message\": \"Hello from Postman!\"
    },
    \"sound\": \"default\",
    \"badge\": 1
  }" \
  "$BASE_URL/api/v2/notifications/session" \
  -w "\nStatus: %{http_code}\n"

echo ""

echo "✅ Specific session tests completed!" 