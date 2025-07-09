#!/bin/bash

echo "🔐 Updating Provisioning Profile for GitHub Secrets"
echo "=================================================="

# Find the correct provisioning profile
PROFILE_PATH="$HOME/Library/MobileDevice/Provisioning Profiles/55e045df-c7db-4467-9a00-48ecd06503d2.mobileprovision"

if [ ! -f "$PROFILE_PATH" ]; then
    echo "❌ Provisioning profile not found at: $PROFILE_PATH"
    echo "Please make sure the SeChat App Store provisioning profile is installed."
    exit 1
fi

echo "✅ Found provisioning profile: $(basename "$PROFILE_PATH")"

# Extract profile details
echo "📋 Profile Details:"
PROFILE_NAME=$(security cms -D -i "$PROFILE_PATH" 2>/dev/null | grep -A 1 "<key>Name</key>" | grep "<string>" | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
echo "Name: $PROFILE_NAME"

PROFILE_UUID=$(security cms -D -i "$PROFILE_PATH" 2>/dev/null | grep -A 1 "<key>UUID</key>" | grep "<string>" | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
echo "UUID: $PROFILE_UUID"

# Create certificates directory
mkdir -p certificates

# Copy the profile to certificates directory
cp "$PROFILE_PATH" certificates/SeChat_App_Store.mobileprovision

echo ""
echo "🔑 APPLE_PROVISIONING_PROFILE (base64):"
echo "Copy this value to your GitHub secrets:"
echo "----------------------------------------"
base64 -i certificates/SeChat_App_Store.mobileprovision | tr -d '\n'
echo ""
echo "----------------------------------------"
echo ""

echo "✅ Profile copied to: certificates/SeChat_App_Store.mobileprovision"
echo "📝 Now update your GitHub secret 'APPLE_PROVISIONING_PROFILE' with the base64 value above"
echo ""
echo "🔄 After updating the secret, push your changes to trigger a new build" 