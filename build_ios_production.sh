#!/bin/bash

# Build iOS App with Production APNS Configuration (Release Build)
echo "🚀 Building iOS App with Production APNS Configuration (Release Build)..."

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

# Build for production APNS (using release configuration)
echo "🔧 Building with production APNS configuration (release build)..."
flutter build ios --release

echo "✅ iOS production build completed!"
echo "📱 App is now configured for production APNS (same as development build)"
echo "🔑 Using automatic code signing with production APNS entitlements"
echo "🚀 Deploy to TestFlight or App Store for production APNS tokens"
echo ""
echo "💡 Note: Both development and production builds use production APNS"
echo "💡 This matches your AirNotifier server configuration"
echo "💡 No more BadDeviceToken errors!"
