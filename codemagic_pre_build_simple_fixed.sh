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

# Use timestamp as build number to ensure uniqueness
BUILD_NUMBER=$(date +%s)
FULL_VERSION="2.0.0+$BUILD_NUMBER"

echo "Setting version to: $FULL_VERSION"

# Update pubspec.yaml with new version using sed
sed -i.bak "s/^version: .*/version: $FULL_VERSION/" pubspec.yaml

# Verify the update
UPDATED_VERSION=$(grep "^version:" pubspec.yaml | sed 's/version: //')
echo "Updated version: $UPDATED_VERSION"

echo "✅ Pre-build script completed successfully!" 