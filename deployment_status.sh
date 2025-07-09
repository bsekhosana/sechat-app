#!/bin/bash

echo "🚀 SeChat Deployment Status Check"
echo "================================="
echo ""

# Check if we have Apple Distribution certificate
echo "📱 iOS Development Setup:"
if security find-identity -v -p codesigning | grep -q "Apple Distribution"; then
    echo "✅ Apple Distribution certificate found"
    security find-identity -v -p codesigning | grep "Apple Distribution"
else
    echo "❌ Apple Distribution certificate NOT found"
    echo "   You need to create one at: https://developer.apple.com/account/resources/certificates/list"
fi

# Check if ExportOptions.plist exists
if [ -f "ios/ExportOptions.plist" ]; then
    echo "✅ ExportOptions.plist configured"
else
    echo "❌ ExportOptions.plist missing"
fi

echo ""
echo "🔐 Required GitHub Secrets:"
echo "For iOS deployment, you need to add these secrets to your GitHub repository:"
echo ""
echo "1. APPLE_DISTRIBUTION_CERTIFICATE_P12 (base64 encoded .p12 file)"
echo "2. APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD (password for .p12 file)"
echo "3. APPLE_PROVISIONING_PROFILE (base64 encoded .mobileprovision file)"
echo "4. APPSTORE_ISSUER_ID (from App Store Connect API)"
echo "5. APPSTORE_API_KEY_ID (from App Store Connect API)"
echo "6. APPSTORE_API_PRIVATE_KEY (from App Store Connect API)"
echo ""

echo "🤖 Current CI/CD Status:"
echo "✅ Android deployment configured (Google Play Internal Testing)"
echo "⚠️  iOS deployment will be skipped until certificates are added"
echo ""

echo "📋 Next Steps:"
echo "1. Export your Apple Distribution certificate using: ./export_certificates.sh"
echo "2. Download your App Store provisioning profile for com.strapblaque.sechat"
echo "3. Convert them to base64 using: ./create_github_secrets.sh"
echo "4. Add the secrets to your GitHub repository"
echo "5. Push to master branch to trigger deployment"
echo ""

echo "🏪 Store Status:"
echo "- Google Play Console: com.strapblaque.sechat (configured)"
echo "- App Store Connect: com.strapblaque.sechat (needs certificates)"
echo ""

echo "For more help, run:"
echo "  ./export_certificates.sh     # Export certificates"
echo "  ./create_github_secrets.sh   # Convert to base64" 