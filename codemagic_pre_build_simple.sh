#!/bin/bash
set -e
set -x

echo "🚀 Starting pre-build script..."

# Setup Android keystore
echo "🔐 Setting up Android keystore..."
KEYSTORE_PATH="$CM_BUILD_DIR/android/app/app-release-key.jks"
mkdir -p "$(dirname "$KEYSTORE_PATH")"
echo "$ANDROID_SIGNING_KEY_BASE64" | base64 -d > "$KEYSTORE_PATH"
ls -la "$KEYSTORE_PATH"

# Test keystore
keytool -list -v -keystore "$KEYSTORE_PATH" -alias "$ANDROID_SIGNING_KEY_ALIAS" -storepass "$ANDROID_SIGNING_STORE_PASSWORD" -noprompt
echo "✅ Android keystore set up successfully"

# Version management
echo "📈 Setting up version management..."
flutter build-name "2.0.0"
flutter build-number "$CM_BUILD_NUMBER"
echo "✅ Version updated to 2.0.0+$CM_BUILD_NUMBER"

echo "✅ Pre-build script completed successfully!" 