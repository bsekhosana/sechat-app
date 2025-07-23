# Android Wireless Debugging Setup

## Current Status
- **Device IP:** 192.168.1.6
- **Port:** 44375
- **Network Connectivity:** ✅ Device is reachable (ping successful)
- **ADB Connection:** ❌ Connection refused

## Troubleshooting Steps

### 1. Enable Wireless Debugging on Android Device

1. **Open Developer Options:**
   - Go to Settings → About Phone
   - Tap "Build Number" 7 times to enable Developer Options

2. **Enable Developer Options:**
   - Go to Settings → System → Developer Options
   - Turn on "Developer Options"

3. **Enable Wireless Debugging:**
   - In Developer Options, find "Wireless Debugging"
   - Turn it ON
   - Tap on "Wireless Debugging" to open settings

4. **Get New Connection Details:**
   - In Wireless Debugging settings, you'll see:
     - IP Address (e.g., 192.168.1.6)
     - Port (e.g., 44375)
   - **Note:** The port may change when you restart wireless debugging

### 2. Connect via ADB

```bash
# Disconnect any existing connections
adb disconnect 192.168.1.6:44375

# Connect using the new port (if it changed)
adb connect 192.168.1.6:NEW_PORT

# Check connection status
adb devices
```

### 3. Alternative Connection Methods

#### Method 1: Pair Device First (Recommended)
1. In Wireless Debugging settings, tap "Pair device with pairing code"
2. Note the pairing code and IP:port
3. Run: `adb pair IP:PORT`
4. Enter the pairing code when prompted
5. Then run: `adb connect IP:PORT`

#### Method 2: Use ADB Over WiFi
1. Connect device via USB first
2. Run: `adb tcpip 5555`
3. Disconnect USB
4. Run: `adb connect 192.168.1.6:5555`

### 4. Verify Connection

```bash
# Check if device is connected
adb devices

# Should show something like:
# List of devices attached
# 192.168.1.6:44375    device
```

### 5. Deploy SeChat App

Once connected, you can deploy the app:

```bash
# Install the debug APK
flutter install

# Or build and install
flutter build apk --debug
flutter install
```

## Common Issues

### Connection Refused
- **Cause:** Wireless debugging disabled or port changed
- **Solution:** Re-enable wireless debugging and get new port

### Device Shows as "Offline"
- **Cause:** Device disconnected or debugging stopped
- **Solution:** Reconnect using new port

### Port Changes
- **Cause:** Android restarts wireless debugging
- **Solution:** Always check the current port in Wireless Debugging settings

## Current Commands to Try

```bash
# 1. Check current devices
adb devices

# 2. Try pairing (if pairing option is available)
adb pair 192.168.1.6:44375

# 3. Try connecting with different port
adb connect 192.168.1.6:5555

# 4. Check if device responds
adb -s 192.168.1.6:44375 shell echo "test"
```

## Next Steps

1. **On your Android device:** Re-enable wireless debugging and get the current port
2. **Update the port** in the connection command if it changed
3. **Try the connection** again
4. **Once connected:** Deploy and test the SeChat app

## Testing the App

Once connected successfully:

```bash
# Install the app
flutter install

# Run the app
flutter run

# Or install the built APK
flutter install --release
```

The SeChat app should then be installed and ready for testing on your Android device! 