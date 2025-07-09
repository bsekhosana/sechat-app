#!/bin/bash

echo "🔐 Verifying Apple Distribution Certificate..."
echo "============================================"

# Check if Apple Distribution certificate exists
if security find-identity -v -p codesigning | grep -q "Apple Distribution*STRAPBLAQUE"; then
    echo "✅ Apple Distribution certificate found!"
    security find-identity -v -p codesigning | grep "Apple Distribution.*STRAPBLAQUE"
    
    # Get the certificate hash
    CERT_HASH=$(security find-identity -v -p codesigning | grep "Apple Distribution.*STRAPBLAQUE" | awk '{print $2}' | sed 's/)$//')
    
    echo ""
    echo "🔑 Checking private key..."
    
    # Test if we can use the certificate (this will fail if no private key)
    if security find-identity -v -p codesigning -s "$CERT_HASH" > /dev/null 2>&1; then
        echo "✅ Private key is accessible!"
        echo ""
        echo "🎉 Certificate is ready for Xcode!"
        echo ""
        echo "📝 Next steps:"
        echo "1. Go back to Xcode"
        echo "2. Runner → Signing & Capabilities → Release"
        echo "3. Uncheck and re-check 'Automatically manage signing'"
        echo "4. You should now see the Apple Distribution certificate"
    else
        echo "❌ Private key not accessible"
        echo "Please try installing the certificate again"
    fi
else
    echo "❌ Apple Distribution certificate not found"
    echo "Please follow the steps to create and install the certificate"
fi 