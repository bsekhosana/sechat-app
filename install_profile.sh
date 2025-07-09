#!/bin/bash

echo "📱 Installing Updated Provisioning Profile..."
echo "============================================="

# Check if profile file is provided
if [ -z "$1" ]; then
    echo "❌ Error: Please provide the path to the downloaded .mobileprovision file"
    echo "Usage: $0 <path-to-profile.mobileprovision>"
    echo ""
    echo "Example: $0 ~/Downloads/SeChat_App_Store.mobileprovision"
    exit 1
fi

PROFILE_FILE="$1"

# Check if file exists
if [ ! -f "$PROFILE_FILE" ]; then
    echo "❌ Error: Provisioning profile not found: $PROFILE_FILE"
    exit 1
fi

echo "📄 Installing profile: $(basename "$PROFILE_FILE")"

# Install the provisioning profile
cp "$PROFILE_FILE" ~/Library/MobileDevice/Provisioning\ Profiles/

if [ $? -eq 0 ]; then
    echo "✅ Provisioning profile installed successfully!"
    echo ""
    
    # Extract and show profile details
    echo "📋 Profile Details:"
    PROFILE_NAME=$(security cms -D -i "$PROFILE_FILE" 2>/dev/null | grep -A 1 "<key>Name</key>" | grep "<string>" | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
    echo "Name: $PROFILE_NAME"
    
    PROFILE_UUID=$(security cms -D -i "$PROFILE_FILE" 2>/dev/null | grep -A 1 "<key>UUID</key>" | grep "<string>" | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
    echo "UUID: $PROFILE_UUID"
    
    # Check if profile includes the certificate
    if security cms -D -i "$PROFILE_FILE" 2>/dev/null | grep -q "8A6FXCA4R9"; then
        echo "✅ Profile includes certificate for team 8A6FXCA4R9"
    else
        echo "❌ Profile does not include certificate for team 8A6FXCA4R9"
    fi
    
    echo ""
    echo "🎉 SUCCESS! Profile installed and ready!"
    echo ""
    echo "📝 Next steps:"
    echo "1. Go back to Xcode"
    echo "2. Runner → Signing & Capabilities → Release"
    echo "3. Uncheck and re-check 'Automatically manage signing' (if needed)"
    echo "4. The certificate should now be available"
    echo "5. Try building with ⌘+B"
    
else
    echo "❌ Error installing provisioning profile"
    exit 1
fi 