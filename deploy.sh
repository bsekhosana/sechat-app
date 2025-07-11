#!/bin/bash

echo "🚀 SeChat Deployment Script"
echo "=========================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    print_error "Please run this script from the sechat_app directory"
    exit 1
fi

print_status "Starting deployment process..."

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean
flutter pub get

# Build Android AAB
echo "📱 Building Android AAB..."
if flutter build appbundle --release; then
    print_status "Android AAB built successfully"
    AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
    AAB_SIZE=$(ls -lh "$AAB_PATH" | awk '{print $5}')
    echo "   📦 AAB size: $AAB_SIZE"
    echo "   📍 Location: $AAB_PATH"
else
    print_error "Android build failed"
    exit 1
fi

# Build iOS IPA (if on macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "🍎 Building iOS IPA..."
    if flutter build ipa --release --export-options-plist=ios/ExportOptions.plist; then
        print_status "iOS IPA built successfully"
        IPA_PATH="build/ios/ipa/SeChat.ipa"
        if [ -f "$IPA_PATH" ]; then
            IPA_SIZE=$(ls -lh "$IPA_PATH" | awk '{print $5}')
            echo "   📦 IPA size: $IPA_SIZE"
            echo "   📍 Location: $IPA_PATH"
        else
            print_warning "IPA file not found at expected location"
        fi
    else
        print_error "iOS build failed"
    fi
else
    print_warning "iOS build skipped (not on macOS)"
fi

echo ""
echo "🎉 Deployment builds completed!"
echo ""
echo "📋 Next steps:"
echo "1. Upload AAB to Google Play Console:"
echo "   → $AAB_PATH"
echo ""
if [[ "$OSTYPE" == "darwin"* ]] && [ -f "build/ios/ipa/SeChat.ipa" ]; then
echo "2. Upload IPA to App Store Connect:"
echo "   → build/ios/ipa/SeChat.ipa"
echo ""
fi
echo "3. Or use this script with upload flags (coming soon)"

# Optional: Open file locations
read -p "Open build folders? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        open build/app/outputs/bundle/release/
        if [ -d "build/ios/ipa/" ]; then
            open build/ios/ipa/
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        xdg-open build/app/outputs/bundle/release/
    fi
fi 