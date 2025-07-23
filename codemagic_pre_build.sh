#!/bin/bash
set -e # exit on first failed command
set -x # print all executed commands to the log

echo "🚀 Starting pre-build script..."

# Function to handle errors
handle_error() {
    echo "❌ Error occurred in pre-build script at line $1"
    exit 1
}

# Set error handler
trap 'handle_error $LINENO' ERR

# Display environment information
echo "📋 Environment Information:"
echo "CM_BUILD_DIR: $CM_BUILD_DIR"
echo "CM_BUILD_NUMBER: $CM_BUILD_NUMBER"
echo "CM_COMMIT: $CM_COMMIT"
echo "CM_BRANCH: $CM_BRANCH"
echo "Current directory: $(pwd)"

# Verify required environment variables
echo "🔍 Checking required environment variables..."
if [ -z "$ANDROID_SIGNING_KEY_BASE64" ]; then
    echo "❌ ANDROID_SIGNING_KEY_BASE64 is not set"
    exit 1
fi

if [ -z "$ANDROID_SIGNING_KEY_ALIAS" ]; then
    echo "❌ ANDROID_SIGNING_KEY_ALIAS is not set"
    exit 1
fi

if [ -z "$ANDROID_SIGNING_STORE_PASSWORD" ]; then
    echo "❌ ANDROID_SIGNING_STORE_PASSWORD is not set"
    exit 1
fi

echo "✅ All required environment variables are set"

# Setup Android keystore
echo "🔐 Setting up Android keystore..."

# Create the keystore file
KEYSTORE_PATH="$CM_BUILD_DIR/android/app/app-release-key.jks"
echo "Creating keystore at: $KEYSTORE_PATH"

# Ensure directory exists
mkdir -p "$(dirname "$KEYSTORE_PATH")"

# Create the keystore file from base64
echo "Decoding base64 keystore..."
echo "$ANDROID_SIGNING_KEY_BASE64" | base64 -d > "$KEYSTORE_PATH"

# Verify file was created and has content
echo "Verifying keystore file..."
if [ ! -f "$KEYSTORE_PATH" ]; then
    echo "❌ Keystore file was not created"
    exit 1
fi

echo "Keystore file size: $(ls -lh "$KEYSTORE_PATH" | awk '{print $5}')"

# Test the keystore
echo "Testing keystore..."
keytool -list -v -keystore "$KEYSTORE_PATH" \
    -alias "$ANDROID_SIGNING_KEY_ALIAS" \
    -storepass "$ANDROID_SIGNING_STORE_PASSWORD" \
    -noprompt

echo "✅ Android keystore set up successfully"

# Version management
echo "📈 Setting up version management..."

# Get current version from pubspec.yaml
CURRENT_VERSION=$(grep "^version:" pubspec.yaml | sed 's/version: //' | sed 's/+.*//')
echo "Current version in pubspec.yaml: $CURRENT_VERSION"

# Set new version and build number
NEW_VERSION="2.0.0"
NEW_BUILD_NUMBER="$CM_BUILD_NUMBER"

echo "Setting version to: $NEW_VERSION+$NEW_BUILD_NUMBER"

# Update pubspec.yaml with new version and build number
flutter build-name "$NEW_VERSION"
flutter build-number "$NEW_BUILD_NUMBER"

# Verify the update
echo "Verifying version update..."
UPDATED_VERSION=$(grep "^version:" pubspec.yaml | sed 's/version: //')
echo "Updated version: $UPDATED_VERSION"

# Display final configuration
echo "🎯 Final Configuration:"
echo "Version: $NEW_VERSION"
echo "Build Number: $NEW_BUILD_NUMBER"
echo "Full Version: $NEW_VERSION+$NEW_BUILD_NUMBER"
echo "Keystore: $KEYSTORE_PATH"

echo "✅ Pre-build script completed successfully!" 