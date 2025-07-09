#!/bin/bash

# Script to convert certificates to base64 for GitHub secrets
echo "🔐 Converting certificates to base64 for GitHub secrets..."

# Create certificates directory if it doesn't exist
mkdir -p certificates

# Check if files exist
if [ ! -f "certificates/distribution_certificate.p12" ]; then
    echo "❌ Error: certificates/distribution_certificate.p12 not found!"
    echo "Please export your Apple Distribution certificate first."
    exit 1
fi

if [ ! -f "certificates/SeChat_App_Store.mobileprovision" ]; then
    echo "❌ Error: certificates/SeChat_App_Store.mobileprovision not found!"
    echo "Please download your App Store provisioning profile first."
    exit 1
fi

echo "📱 Converting certificates to base64..."

# Convert distribution certificate to base64
echo "🔑 APPLE_DISTRIBUTION_CERTIFICATE_P12:"
echo "Copy this value to GitHub secrets:"
echo "----------------------------------------"
base64 -i certificates/distribution_certificate.p12 | tr -d '\n'
echo ""
echo "----------------------------------------"
echo ""

# Convert provisioning profile to base64
echo "📄 APPLE_PROVISIONING_PROFILE:"
echo "Copy this value to GitHub secrets:"
echo "----------------------------------------"
base64 -i certificates/SeChat_App_Store.mobileprovision | tr -d '\n'
echo ""
echo "----------------------------------------"
echo ""

echo "🔐 Don't forget to add these GitHub secrets:"
echo "1. APPLE_DISTRIBUTION_CERTIFICATE_P12 (base64 from above)"
echo "2. APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD (password you set for .p12)"
echo "3. APPLE_PROVISIONING_PROFILE (base64 from above)"
echo ""
echo "📝 To add secrets to GitHub:"
echo "1. Go to your repository on GitHub"
echo "2. Go to Settings → Secrets and variables → Actions"
echo "3. Click 'New repository secret'"
echo "4. Add each secret with the exact name shown above" 