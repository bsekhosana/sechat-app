#!/bin/bash

echo "🚀 Exporting Certificates for CI/CD..."
echo "===================================="

# Certificate hash from the working certificate
CERT_HASH="B471E6C0EBCDCD9F7A81450AC2B6712F21FE03C8"

# Create export directory
mkdir -p ci_export

echo "📱 Step 1: Exporting Apple Distribution Certificate..."

# Export the certificate with private key as P12
security export -t identities -f pkcs12 -k ~/Library/Keychains/login.keychain-db -o ci_export/distribution_certificate.p12 -P "ci_password" "$CERT_HASH"

if [ $? -eq 0 ]; then
    echo "✅ Certificate exported successfully!"
    
    # Convert to base64
    echo ""
    echo "🔐 APPLE_DISTRIBUTION_CERTIFICATE_P12 (base64):"
    echo "Copy this value to GitHub secrets:"
    echo "----------------------------------------"
    base64 -i ci_export/distribution_certificate.p12 | tr -d '\n'
    echo ""
    echo "----------------------------------------"
    echo ""
    echo "🔑 APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD:"
    echo "ci_password"
    echo ""
    
else
    echo "❌ Failed to export certificate"
    echo "Please check if the certificate is accessible"
    exit 1
fi

echo "📄 Step 2: Exporting Provisioning Profile..."

# Find the latest provisioning profile
LATEST_PROFILE=$(ls -t ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision 2>/dev/null | head -1)

if [ -n "$LATEST_PROFILE" ]; then
    echo "✅ Found provisioning profile: $(basename "$LATEST_PROFILE")"
    
    # Copy to export directory
    cp "$LATEST_PROFILE" ci_export/SeChat_App_Store.mobileprovision
    
    # Convert to base64
    echo ""
    echo "📱 APPLE_PROVISIONING_PROFILE (base64):"
    echo "Copy this value to GitHub secrets:"
    echo "----------------------------------------"
    base64 -i ci_export/SeChat_App_Store.mobileprovision | tr -d '\n'
    echo ""
    echo "----------------------------------------"
    echo ""
    
    # Show profile details
    PROFILE_NAME=$(security cms -D -i "$LATEST_PROFILE" 2>/dev/null | grep -A 1 "<key>Name</key>" | grep "<string>" | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
    echo "📋 Profile Name: $PROFILE_NAME"
    
    # Check if profile includes the certificate
    if security cms -D -i "$LATEST_PROFILE" 2>/dev/null | grep -q "8A6FXCA4R9"; then
        echo "✅ Profile includes certificate for team 8A6FXCA4R9"
    else
        echo "❌ Profile does not include certificate for team 8A6FXCA4R9"
        echo "Please update the provisioning profile in Apple Developer Portal"
    fi
    
else
    echo "❌ No provisioning profile found"
    echo "Please install the updated provisioning profile first"
    exit 1
fi

echo ""
echo "🎯 GitHub Secrets to Update:"
echo "============================="
echo "1. APPLE_DISTRIBUTION_CERTIFICATE_P12 → (base64 value above)"
echo "2. APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD → ci_password"
echo "3. APPLE_PROVISIONING_PROFILE → (base64 value above)"
echo ""
echo "📝 How to update GitHub secrets:"
echo "1. Go to your GitHub repository"
echo "2. Settings → Secrets and variables → Actions"
echo "3. Update each secret with the new values"
echo "4. Push your changes to trigger CI/CD"
echo ""
echo "🚀 After updating secrets, your CI/CD will work!" 