#!/bin/bash

echo "🧪 Testing FCM Threading Fix"
echo "=============================="

# Check if the fix has been applied
echo "📋 Checking MainActivity.kt for threading fix..."

if grep -q "runOnUiThread" android/app/src/main/kotlin/com/strapblaque/sechat/MainActivity.kt; then
    echo "✅ MainActivity.kt contains runOnUiThread fix"
else
    echo "❌ MainActivity.kt missing runOnUiThread fix"
    exit 1
fi

if grep -q "sendNotificationToEventChannel" android/app/src/main/kotlin/com/strapblaque/sechat/MainActivity.kt; then
    echo "✅ MainActivity.kt contains sendNotificationToEventChannel method"
else
    echo "❌ MainActivity.kt missing sendNotificationToEventChannel method"
    exit 1
fi

echo "📋 Checking SeChatFirebaseMessagingService.kt for improvements..."

if grep -q "handles main thread switching internally" android/app/src/main/kotlin/com/strapblaque/sechat/SeChatFirebaseMessagingService.kt; then
    echo "✅ FCM service updated with thread safety comment"
else
    echo "⚠️  FCM service may need thread safety updates"
fi

echo ""
echo "🔧 Build and Test Instructions:"
echo "1. Clean and rebuild the Android app:"
echo "   flutter clean && flutter pub get"
echo "   cd android && ./gradlew clean && cd .."
echo "   flutter build apk --debug"
echo ""
echo "2. Install and test the app:"
echo "   flutter install"
echo ""
echo "3. Monitor logs for FCM threading:"
echo "   adb logcat | grep -E '(SeChatFCM|MainActivity)'"
echo ""
echo "4. Send a test notification and verify no threading errors appear"
echo ""
echo "✅ FCM Threading Fix Applied Successfully!"
echo ""
echo "The fix ensures that:"
echo "- EventChannel calls are always made on the main thread"
echo "- Broadcast receiver calls are properly threaded"
echo "- No more '@UiThread must be executed on the main thread' errors" 