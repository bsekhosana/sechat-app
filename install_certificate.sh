#!/bin/bash

echo "🔐 Installing Apple Distribution Certificate..."
echo "=============================================="

# Check if certificate file is provided
if [ -z "$1" ]; then
    echo "❌ Error: Please provide the path to the downloaded .cer file"
    echo "Usage: $0 <path-to-certificate.cer>"
    echo ""
    echo "Example: $0 ~/Downloads/ios_distribution.cer"
    exit 1
fi

CERT_FILE="$1"

# Check if file exists
if [ ! -f "$CERT_FILE" ]; then
    echo "❌ Error: Certificate file not found: $CERT_FILE"
    exit 1
fi

echo "📱 Installing certificate: $(basename "$CERT_FILE")"

# Install the certificate
security import "$CERT_FILE" -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign -T /usr/bin/security

if [ $? -eq 0 ]; then
    echo "✅ Certificate installed successfully!"
    echo ""
    
    # Wait a moment for keychain to update
    sleep 2
    
    # Check if certificate is now accessible
    echo "🔍 Verifying certificate..."
    if security find-identity -v -p codesigning | grep -q "Apple Distribution.*STRAPBLAQUE"; then
        echo "✅ Certificate is accessible to codesign tools!"
        echo ""
        
        # Show the certificate details
        security find-identity -v -p codesigning | grep "Apple Distribution.*STRAPBLAQUE"
        
        echo ""
        echo "🎉 SUCCESS! Certificate is ready for Xcode!"
        echo ""
        echo "📝 Next steps:"
        echo "1. Go to Xcode"
        echo "2. Runner → Signing & Capabilities → Release"
        echo "3. The certificate should now be available for manual signing"
        echo "4. Try building with ⌘+B"
        
    else
        echo "❌ Certificate installed but not accessible to codesign tools"
        echo "Please check Keychain Access and ensure the certificate has a private key"
    fi
else
    echo "❌ Error installing certificate"
    exit 1
fi 