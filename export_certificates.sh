#!/bin/bash

# Script to export iOS certificates for GitHub Actions
echo "🔐 Exporting iOS Certificates for GitHub Actions..."

# Create certificates directory
mkdir -p certificates

# Export Apple Distribution Certificate
echo "📱 Exporting Apple Distribution Certificate..."
security find-identity -v -p codesigning | grep "Apple Distribution"

echo ""
echo "📋 To export your certificate:"
echo "1. Open Keychain Access"
echo "2. Find your 'Apple Distribution' certificate"
echo "3. Right-click and select 'Export'"
echo "4. Choose 'Personal Information Exchange (.p12)'"
echo "5. Save as 'certificates/distribution_certificate.p12'"
echo "6. Set a strong password and remember it!"

echo ""
echo "📄 Don't forget to:"
echo "1. Download your App Store provisioning profile"
echo "2. Save it as 'certificates/SeChat_App_Store.mobileprovision'"

echo ""
echo "🔑 You'll need these for GitHub secrets:"
echo "- APPLE_DISTRIBUTION_CERTIFICATE_P12 (base64 encoded .p12 file)"
echo "- APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD (password for .p12)"
echo "- APPLE_PROVISIONING_PROFILE (base64 encoded .mobileprovision file)" 