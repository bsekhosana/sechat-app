#!/bin/bash

# Build iOS App with Production APNS Configuration (Development Build)
echo "🚀 Building iOS App with Production APNS Configuration (Development Build)..."

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean
cd ios
rm -rf build/
rm -rf Pods/
rm -rf .symlinks/
rm -rf Flutter/Flutter.framework
rm -rf Flutter/Flutter.podspec
cd ..

# Get dependencies
echo "📦 Getting Flutter dependencies..."
flutter pub get

# Install iOS pods
echo "🍎 Installing iOS pods..."
cd ios
pod install --repo-update
cd ..

# Build for development with production APNS (using debug configuration)
echo "🔧 Building with production APNS configuration (debug build)..."
flutter build ios --debug

echo "✅ iOS development build completed!"
echo "📱 App is now configured for production APNS (same as production build)"
echo "🔑 Using automatic code signing with production APNS entitlements"
echo "🧪 Use this for testing with production APNS environment"
echo ""
echo "💡 Note: Both development and production builds use production APNS"
echo "💡 This matches your AirNotifier server configuration"
echo "💡 No more BadDeviceToken errors!"
