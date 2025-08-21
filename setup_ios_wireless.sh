#!/bin/bash

echo "🔧 Setting up iOS wireless debugging for SeChat..."

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode not found. Please install Xcode from App Store."
    exit 1
fi

echo "✅ Xcode found"

# Check current devices
echo "📱 Current Flutter devices:"
flutter devices

echo ""
echo "🔧 Manual Setup Required in Xcode:"
echo "1. In Xcode (should be open now):"
echo "   - Go to Window > Devices and Simulators"
echo "   - Select your iPhone 'B Man iPhone'"
echo "   - Check the 'Connect via network' checkbox"
echo "   - Wait for 'Connected via network' status"
echo ""
echo "2. Once wireless is enabled:"
echo "   - Disconnect USB cable from iPhone"
echo "   - Verify iPhone still shows in Xcode"
echo ""
echo "3. Test wireless connection:"
echo "   - Run: flutter devices"
echo "   - Should show iPhone as wireless device"
echo ""
echo "4. Run app wirelessly:"
echo "   - Run: flutter run"
echo "   - Or: flutter run -d <DEVICE_ID>"
echo ""

# Wait for user to complete setup
read -p "Press Enter when you've completed the Xcode setup..."

echo "🔍 Checking wireless devices..."
flutter devices

echo ""
echo "🎯 Next steps:"
echo "- If iPhone shows as wireless device, you're ready!"
echo "- Run: flutter run"
echo "- Use 'r' for hot reload, 'R' for hot restart"
echo "- Test local notifications and messaging functionality" 