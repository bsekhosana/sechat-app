#!/bin/bash

echo "🔧 Adding SessionApiImpl.swift to Xcode project..."

# Path to the Xcode project file
PROJECT_FILE="ios/Runner.xcodeproj/project.pbxproj"

# Check if project file exists
if [ ! -f "$PROJECT_FILE" ]; then
    echo "❌ Xcode project file not found: $PROJECT_FILE"
    exit 1
fi

# Check if SessionApiImpl.swift exists
if [ ! -f "ios/Runner/SessionApiImpl.swift" ]; then
    echo "❌ SessionApiImpl.swift not found"
    exit 1
fi

echo "✅ Found SessionApiImpl.swift file"
echo "✅ Found Xcode project file"

echo ""
echo "📝 To add SessionApiImpl.swift to your Xcode project:"
echo "1. Open ios/Runner.xcworkspace in Xcode"
echo "2. Right-click on the Runner folder in the project navigator"
echo "3. Select 'Add Files to Runner'"
echo "4. Navigate to ios/Runner/SessionApiImpl.swift"
echo "5. Make sure 'Add to target: Runner' is checked"
echo "6. Click 'Add'"
echo ""
echo "After adding the file to Xcode, uncomment the SessionApi setup in AppDelegate.swift"
echo "and rebuild the project."

echo ""
echo "🔧 Current status:"
echo "- ✅ SessionApiImpl.swift file created"
echo "- ✅ iOS build works without SessionApi"
echo "- ⏳ SessionApiImpl.swift needs to be added to Xcode project"
echo "- ⏳ SessionApi setup needs to be uncommented in AppDelegate.swift" 