#!/bin/bash

# Run Flutter with comprehensive log filtering
echo "🚀 Starting SeChat with quiet logs..."

# Filter out common noisy logs
flutter run --debug 2>&1 | grep -v -E "(EGL_emulation|libEGL|app_time_stats|RenderFlex overflowed|I/flutter|D/EGL|E/libEGL|W/EGL|I/EGL)" 