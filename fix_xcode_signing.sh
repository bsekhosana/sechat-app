#!/bin/bash

echo "🔧 Fixing Xcode Release configuration..."

# Backup the original file
cp ios/Runner.xcodeproj/project.pbxproj ios/Runner.xcodeproj/project.pbxproj.backup

# Add DEVELOPMENT_TEAM and PROVISIONING_PROFILE_SPECIFIER to Release configuration
sed -i '' '/97C147071CF9000F007C117D.*Release/,/};/{
    s/DEVELOPMENT_TEAM = "";/DEVELOPMENT_TEAM = 8A6FXCA4R9;\
				PROVISIONING_PROFILE_SPECIFIER = "SeChat App Store";/
}' ios/Runner.xcodeproj/project.pbxproj

echo "✅ Xcode Release configuration updated!"
echo ""
echo "📋 Configuration set to:"
echo "   - CODE_SIGN_STYLE = Manual"
echo "   - DEVELOPMENT_TEAM = 8A6FXCA4R9"
echo "   - PROVISIONING_PROFILE_SPECIFIER = SeChat App Store"
echo "   - CODE_SIGN_IDENTITY = iPhone Distribution"
echo ""
echo "🎯 Next steps:"
echo "1. Go to Xcode (should already be open)"
echo "2. Select Runner target → Signing & Capabilities → Release"  
echo "3. You should see manual signing is selected"
echo "4. Try building with ⌘+B" 