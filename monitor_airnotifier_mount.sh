#!/bin/bash

# Quick AirNotifier Mount Status Check
# Run this from within the sechat_app directory

echo "🔍 Checking AirNotifier mount status..."
echo ""

# Check if mount is active
if mount | grep -q "root@41.76.111.100:/opt/airnotifier"; then
    echo "✅ AirNotifier mount is ACTIVE"
    echo "📍 Location: airnotifier_server/ (symbolic link)"
    echo "🌐 Server: root@41.76.111.100:1337"
    echo ""
    
    # Show some file info
    if [ -d "airnotifier_server" ]; then
        echo "📁 Mounted directory contents:"
        ls -la airnotifier_server/ | head -5
        echo "..."
        echo ""
        
        # Check if we can read a file
        if [ -f "airnotifier_server/config.py" ]; then
            echo "📄 Test file access (config.py):"
            head -3 airnotifier_server/config.py
        fi
    fi
else
    echo "❌ AirNotifier mount is NOT ACTIVE"
    echo ""
    echo "To mount, run from parent directory:"
    echo "  cd .. && ./manage_airnotifier_mount.sh mount"
    echo ""
    echo "Or use the management script:"
    echo "  cd .. && ./manage_airnotifier_mount.sh help"
fi

echo ""
echo "💡 Tip: Use '../manage_airnotifier_mount.sh' from this directory to manage the mount"
