#!/bin/bash

# SeChat Device Runner Script
# Usage: ./run_device.sh [--release]

DEVICE_ID="60f30b8d800c920ac0276beb3f95c456de23892e"
RELEASE_MODE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --release)
      RELEASE_MODE=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [--release]"
      echo ""
      echo "Options:"
      echo "  --release    Run in release mode (default: debug mode)"
      echo "  --help, -h   Show this help message"
      echo ""
      echo "Device ID: $DEVICE_ID"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Check if device is connected
echo "🔍 Checking if device $DEVICE_ID is connected..."
if ! flutter devices | grep -q "$DEVICE_ID"; then
    echo "❌ Device $DEVICE_ID not found!"
    echo "Available devices:"
    flutter devices
    exit 1
fi

echo "✅ Device $DEVICE_ID found!"

# Set mode
if [ "$RELEASE_MODE" = true ]; then
    echo "🚀 Running in RELEASE mode..."
    MODE="--release"
else
    echo "🐛 Running in DEBUG mode..."
    MODE="--debug"
fi

# Clean and get dependencies
echo "🧹 Cleaning project..."
flutter clean

echo "📦 Getting dependencies..."
flutter pub get

# Run the app
echo "🎯 Starting SeChat on device $DEVICE_ID..."
echo "Mode: $MODE"

# Filter out noisy logs
if [ "$RELEASE_MODE" = true ]; then
    # Release mode - minimal logging
    flutter run -d "$DEVICE_ID" $MODE 2>&1 | grep -v -E "(EGL_emulation|libEGL|app_time_stats|RenderFlex overflowed|I/flutter|D/EGL|E/libEGL|W/EGL|I/EGL|I/TextInputPlugin|W/RemoteInputConnectionImpl|I/ImeTracker|W/WindowOnBackDispatcher)"
else
    # Debug mode - more verbose but still filtered
    flutter run -d "$DEVICE_ID" $MODE 2>&1 | grep -v -E "(EGL_emulation|libEGL|app_time_stats|RenderFlex overflowed|I/TextInputPlugin|W/RemoteInputConnectionImpl|I/ImeTracker|W/WindowOnBackDispatcher)"
fi 