#!/bin/bash

# Run Flutter with filtered logs to remove emulation noise
echo "🚀 Starting SeChat with clean logs..."

# Run Flutter and filter out emulation logs
flutter run --debug 2>&1 | grep -v "EGL_emulation\|libEGL\|app_time_stats\|RenderFlex overflowed" 