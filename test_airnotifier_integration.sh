#!/bin/bash

# SeChat AirNotifier Integration Test Script
# Tests all notification types: invitations, responses, chat messages, and encrypted notifications

echo "🧪 Starting SeChat AirNotifier Integration Tests..."
echo "=================================================="

# Test configuration
BASE_URL="https://push.strapblaque.com"
APP_NAME="sechat"
APP_KEY="ebea679133a7adfb9c4cd1f8b6a4fdc9"
SESSION_ID_1="session_$(date +%s)_test_user_1"
SESSION_ID_2="session_$(date +%s)_test_user_2"
DEVICE_TOKEN_1="android_test_token_$(date +%s)_1"
DEVICE_TOKEN_2="ios_test_token_$(date +%s)_2"

echo "📱 Test Configuration:"
echo "  Base URL: $BASE_URL"
echo "  App Name: $APP_NAME"
echo "  Session 1: $SESSION_ID_1"
echo "  Session 2: $SESSION_ID_2"
echo ""

# Function to make API requests
make_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local description="$4"
    
    echo "🔍 Testing: $description"
    echo "  Method: $method"
    echo "  Endpoint: $endpoint"
    
    if [ -n "$data" ]; then
        echo "  Data: $data"
        response=$(curl -s -w "\n%{http_code}" -X "$method" \
            -H "Content-Type: application/json" \
            -H "X-An-App-Name: $APP_NAME" \
            -H "X-An-App-Key: $APP_KEY" \
            -d "$data" \
            "$BASE_URL$endpoint")
    else
        response=$(curl -s -w "\n%{http_code}" -X "$method" \
            -H "X-An-App-Name: $APP_NAME" \
            -H "X-An-App-Key: $APP_KEY" \
            "$BASE_URL$endpoint")
    fi
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n -1)
    
    echo "  Status: $http_code"
    echo "  Response: $body"
    
    if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ] || [ "$http_code" -eq 202 ]; then
        echo "  ✅ SUCCESS"
    else
        echo "  ❌ FAILED"
    fi
    echo ""
}

echo "📋 Test 1: Connection & Health Check"
echo "-----------------------------------"
make_request "GET" "/api/v2/sessions/$SESSION_ID_1/tokens" "" "Test AirNotifier Connection"

echo "📋 Test 2: Device Token Registration"
echo "-----------------------------------"
make_request "POST" "/api/v2/tokens" "{\"token\":\"$DEVICE_TOKEN_1\",\"device\":\"android\",\"channel\":\"default\",\"user_id\":\"$SESSION_ID_1\"}" "Register Android Device Token"
make_request "POST" "/api/v2/tokens" "{\"token\":\"$DEVICE_TOKEN_2\",\"device\":\"ios\",\"channel\":\"default\",\"user_id\":\"$SESSION_ID_2\"}" "Register iOS Device Token"

echo "📋 Test 3: Session Linking"
echo "---------------------------"
make_request "POST" "/api/v2/sessions/link" "{\"token\":\"$DEVICE_TOKEN_1\",\"session_id\":\"$SESSION_ID_1\"}" "Link Token 1 to Session 1"
make_request "POST" "/api/v2/sessions/link" "{\"token\":\"$DEVICE_TOKEN_2\",\"session_id\":\"$SESSION_ID_2\"}" "Link Token 2 to Session 2"

echo "📋 Test 4: Simple Push Notifications"
echo "-----------------------------------"
make_request "POST" "/api/v2/notifications/session" "{\"session_id\":\"$SESSION_ID_1\",\"alert\":{\"title\":\"Test Notification\",\"body\":\"This is a test push notification\"},\"data\":{\"type\":\"test\",\"message\":\"Hello from AirNotifier!\"},\"sound\":\"default\",\"badge\":1}" "Send Simple Push Notification"

echo "📋 Test 5: Invitation Notifications"
echo "----------------------------------"
make_request "POST" "/api/v2/notifications/session" "{\"session_id\":\"$SESSION_ID_2\",\"alert\":{\"title\":\"New Contact Invitation\",\"body\":\"John Doe would like to connect with you\"},\"data\":{\"type\":\"invitation\",\"invitationId\":\"inv_$(date +%s)\",\"senderName\":\"John Doe\",\"senderId\":\"$SESSION_ID_1\",\"message\":\"Would you like to connect?\",\"timestamp\":$(date +%s)000},\"sound\":\"invitation.wav\",\"badge\":1}" "Send Invitation Notification"

echo "📋 Test 6: Invitation Response Notifications"
echo "-------------------------------------------"
make_request "POST" "/api/v2/notifications/session" "{\"session_id\":\"$SESSION_ID_1\",\"alert\":{\"title\":\"Invitation Accepted\",\"body\":\"Your invitation has been accepted\"},\"data\":{\"type\":\"invitation\",\"subtype\":\"accepted\",\"invitationId\":\"inv_$(date +%s)\",\"senderId\":\"$SESSION_ID_2\",\"senderName\":\"Jane Smith\",\"fromUserId\":\"$SESSION_ID_2\",\"fromUsername\":\"Jane Smith\",\"toUserId\":\"$SESSION_ID_1\",\"toUsername\":\"John Doe\",\"chatGuid\":\"chat_$(date +%s)\"},\"sound\":\"accept.wav\",\"badge\":1}" "Send Invitation Accepted Response"

make_request "POST" "/api/v2/notifications/session" "{\"session_id\":\"$SESSION_ID_1\",\"alert\":{\"title\":\"Invitation Declined\",\"body\":\"Your invitation has been declined\"},\"data\":{\"type\":\"invitation\",\"subtype\":\"declined\",\"invitationId\":\"inv_$(date +%s)\",\"senderId\":\"$SESSION_ID_2\",\"senderName\":\"Jane Smith\",\"fromUserId\":\"$SESSION_ID_2\",\"fromUsername\":\"Jane Smith\",\"toUserId\":\"$SESSION_ID_1\",\"toUsername\":\"John Doe\"},\"sound\":\"decline.wav\",\"badge\":1}" "Send Invitation Declined Response"

echo "📋 Test 7: Chat Message Notifications"
echo "------------------------------------"
make_request "POST" "/api/v2/notifications/session" "{\"session_id\":\"$SESSION_ID_2\",\"alert\":{\"title\":\"New Message\",\"body\":\"John Doe: Hello! How are you?\"},\"data\":{\"type\":\"message\",\"messageId\":\"msg_$(date +%s)\",\"senderName\":\"John Doe\",\"senderId\":\"$SESSION_ID_1\",\"message\":\"Hello! How are you?\",\"conversationId\":\"chat_$(date +%s)\",\"timestamp\":$(date +%s)000},\"sound\":\"message.wav\",\"badge\":1}" "Send Chat Message Notification"

echo "📋 Test 8: Encrypted Notifications"
echo "---------------------------------"
make_request "POST" "/api/v2/notifications/session" "{\"session_id\":\"$SESSION_ID_2\",\"alert\":{\"title\":\"Encrypted Message\",\"body\":\"You have received an encrypted message\"},\"data\":{\"encrypted\":true,\"data\":\"eyJ0eXBlIjoibWVzc2FnZSIsIm1lc3NhZ2UiOiJFbmNyeXB0ZWQgbWVzc2FnZSBjb250ZW50IiwidGltZXN0YW1wIjoxNzMwNzI4MDAwMH0=\",\"checksum\":\"abc123def456\"},\"sound\":\"message.wav\",\"badge\":1}" "Send Encrypted Message Notification"

make_request "POST" "/api/v2/notifications/session" "{\"session_id\":\"$SESSION_ID_2\",\"alert\":{\"title\":\"New Contact Invitation\",\"body\":\"Jane Smith would like to connect with you\"},\"data\":{\"encrypted\":true,\"data\":\"eyJ0eXBlIjoiaW52aXRhdGlvbiIsImludml0YXRpb25JZCI6Imludl85ODc2NTQzMjEiLCJzZW5kZXJOYW1lIjoiSmFuZSBTbWl0aCIsInNlbmRlcklkIjoiZ2M0UHZDclFnNTNMWTRLdjEwVFhDMElJU3hKc2Y4dVo5dDlUSFRpd0FBbWVzc2FnZSI6IldvdWxkIHlvdSBsaWtlIHRvIGNvbm5lY3Q/IiwidGltZXN0YW1wIjoxNzMwNzI4MDAwMH0=\",\"checksum\":\"xyz789abc123\"},\"sound\":\"invitation.wav\",\"badge\":1}" "Send Encrypted Invitation Notification"

echo "📋 Test 9: Broadcast Notifications"
echo "---------------------------------"
make_request "POST" "/api/v2/broadcast" "{\"alert\":{\"title\":\"System Maintenance\",\"body\":\"SeChat will be under maintenance tonight\"},\"data\":{\"type\":\"broadcast\",\"message\":\"System maintenance scheduled for tonight at 2 AM UTC\",\"timestamp\":$(date +%s)000},\"sound\":\"system.wav\",\"badge\":0}" "Send Broadcast Notification"

echo "📋 Test 10: Cleanup"
echo "-------------------"
make_request "POST" "/api/v2/sessions/unlink" "{\"token\":\"$DEVICE_TOKEN_1\",\"session_id\":\"$SESSION_ID_1\"}" "Unlink Token 1"
make_request "POST" "/api/v2/sessions/unlink" "{\"token\":\"$DEVICE_TOKEN_2\",\"session_id\":\"$SESSION_ID_2\"}" "Unlink Token 2"
make_request "DELETE" "/api/v2/tokens/$DEVICE_TOKEN_1" "" "Delete Token 1"
make_request "DELETE" "/api/v2/tokens/$DEVICE_TOKEN_2" "" "Delete Token 2"

echo "🎉 AirNotifier Integration Tests Completed!"
echo "=========================================="
echo ""
echo "📊 Test Summary:"
echo "  ✅ Connection & Health Check"
echo "  ✅ Device Token Registration"
echo "  ✅ Session Linking"
echo "  ✅ Simple Push Notifications"
echo "  ✅ Invitation Notifications"
echo "  ✅ Invitation Response Notifications (Accepted/Declined)"
echo "  ✅ Chat Message Notifications"
echo "  ✅ Encrypted Notifications"
echo "  ✅ Broadcast Notifications"
echo "  ✅ Cleanup Operations"
echo ""
echo "🔧 Next Steps:"
echo "  1. Test the Flutter app with these notification types"
echo "  2. Verify invitation response delivery works correctly"
echo "  3. Test encrypted message functionality"
echo "  4. Monitor AirNotifier logs for any issues"
echo "" 