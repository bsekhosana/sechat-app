# Android Camera Permissions & Wireless Debugging Setup

## 🎯 **1. Android Camera Permissions**

### ✅ **Permissions Added to AndroidManifest.xml:**

```xml
<!-- Camera permissions for QR code scanning -->
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" android:required="false" />
<uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />

<!-- Storage permissions for saving QR codes and images -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />

<!-- Internet permissions for messaging -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

<!-- Notification permissions -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

### 🔧 **Android Permission Handling:**

The app already uses `permission_handler` package which automatically handles:
- Runtime permission requests for Android 6.0+
- Permission status checking
- Settings navigation for denied permissions

### 🧪 **Testing Android Permissions:**

1. **Install app on Android device**
2. **Try QR code scanning** - Should show permission dialog
3. **Check app permissions** - Go to Settings > Apps > SeChat > Permissions
4. **Verify camera access** - Should be listed and toggleable

---

## 📱 **2. Wireless Debugging Setup**

### **Prerequisites:**
- Android device with Android 11+ (API level 30+)
- Device and computer on same WiFi network
- USB cable for initial setup

### **Step 1: Enable Developer Options**
1. Go to **Settings > About phone**
2. Tap **Build number** 7 times
3. Go back to **Settings > System > Developer options**
4. Enable **Developer options**

### **Step 2: Enable Wireless Debugging**
1. In **Developer options**, find **Wireless debugging**
2. Enable **Wireless debugging**
3. Tap **Wireless debugging** to open settings
4. Tap **Use wireless debugging**

### **Step 3: Connect Device Wirelessly**

#### **Method 1: Using ADB (Recommended)**
```bash
# 1. Connect device via USB first
adb devices

# 2. Enable wireless debugging
adb tcpip 5555

# 3. Get device IP address (shown in wireless debugging settings)
# Or use: adb shell ip addr show wlan0

# 4. Disconnect USB and connect wirelessly
adb connect <DEVICE_IP>:5555

# 5. Verify connection
adb devices
```

#### **Method 2: Using Flutter**
```bash
# 1. Connect via USB first
flutter devices

# 2. Enable wireless debugging
flutter run --debug

# 3. In another terminal, get device IP
adb shell ip addr show wlan0

# 4. Connect wirelessly
flutter run -d <DEVICE_IP>:5555
```

### **Step 4: Flutter Wireless Debugging Commands**

#### **List Wireless Devices:**
```bash
flutter devices
```

#### **Run App Wirelessly:**
```bash
flutter run -d <DEVICE_IP>:5555
```

#### **Hot Reload Wirelessly:**
```bash
# Press 'r' in the terminal where flutter run is active
```

#### **Hot Restart Wirelessly:**
```bash
# Press 'R' in the terminal where flutter run is active
```

### **Step 5: Troubleshooting Wireless Debugging**

#### **Issue 1: Device Not Found**
```bash
# Check if device is connected
adb devices

# Restart ADB server
adb kill-server
adb start-server

# Reconnect device
adb connect <DEVICE_IP>:5555
```

#### **Issue 2: Connection Lost**
```bash
# Check network connectivity
ping <DEVICE_IP>

# Restart wireless debugging on device
# Settings > Developer options > Wireless debugging > Turn off/on

# Reconnect
adb connect <DEVICE_IP>:5555
```

#### **Issue 3: Port Already in Use**
```bash
# Kill existing ADB processes
adb kill-server

# Use different port
adb tcpip 5556
adb connect <DEVICE_IP>:5556
```

### **Step 6: Advanced Wireless Debugging**

#### **Persistent Wireless Connection:**
```bash
# Create script for easy connection
echo '#!/bin/bash
adb kill-server
adb start-server
adb connect <DEVICE_IP>:5555
flutter devices' > connect_wireless.sh

chmod +x connect_wireless.sh
./connect_wireless.sh
```

#### **Multiple Device Support:**
```bash
# Connect multiple devices
adb connect <DEVICE1_IP>:5555
adb connect <DEVICE2_IP>:5555

# List all devices
flutter devices

# Run on specific device
flutter run -d <DEVICE_ID>
```

### **Step 7: Security Considerations**

#### **Network Security:**
- Use private WiFi network
- Avoid public WiFi for debugging
- Consider VPN for additional security

#### **Device Security:**
- Disable wireless debugging when not in use
- Use strong WiFi passwords
- Keep device and computer updated

---

## 🚀 **Quick Setup Commands**

### **Complete Setup Script:**
```bash
#!/bin/bash
echo "Setting up wireless debugging..."

# 1. Check if device is connected via USB
if ! adb devices | grep -q "device$"; then
    echo "Please connect device via USB first"
    exit 1
fi

# 2. Enable wireless debugging
echo "Enabling wireless debugging..."
adb tcpip 5555

# 3. Get device IP
DEVICE_IP=$(adb shell ip addr show wlan0 | grep "inet " | cut -d" " -f6 | cut -d"/" -f1)
echo "Device IP: $DEVICE_IP"

# 4. Disconnect USB and connect wirelessly
echo "Disconnect USB cable now, then press Enter..."
read

echo "Connecting wirelessly..."
adb connect $DEVICE_IP:5555

# 5. Verify connection
if adb devices | grep -q "$DEVICE_IP"; then
    echo "✅ Wireless debugging connected successfully!"
    echo "Device IP: $DEVICE_IP"
    echo "Run: flutter run -d $DEVICE_IP:5555"
else
    echo "❌ Connection failed. Please check network and try again."
fi
```

### **Save as `setup_wireless_debugging.sh` and run:**
```bash
chmod +x setup_wireless_debugging.sh
./setup_wireless_debugging.sh
```

---

## 📋 **Verification Checklist**

### **Android Permissions:**
- [ ] Camera permission declared in AndroidManifest.xml
- [ ] App requests camera permission at runtime
- [ ] Permission dialog appears when scanning QR codes
- [ ] Camera settings accessible in device settings
- [ ] QR code scanning works after permission granted

### **Wireless Debugging:**
- [ ] Developer options enabled
- [ ] Wireless debugging enabled
- [ ] Device and computer on same WiFi
- [ ] ADB can connect wirelessly
- [ ] Flutter can run wirelessly
- [ ] Hot reload works wirelessly
- [ ] App can be installed wirelessly

### **Testing Commands:**
```bash
# Test wireless connection
adb devices

# Test Flutter wireless
flutter devices
flutter run -d <DEVICE_IP>:5555

# Test hot reload
# Press 'r' in terminal

# Test hot restart
# Press 'R' in terminal
```

---

## 🔄 **Next Steps:**

1. **Test Android permissions** on physical Android device
2. **Set up wireless debugging** using the guide above
3. **Test QR code scanning** with camera permissions
4. **Verify wireless debugging** works for development
5. **Test both platforms** (iOS and Android) for camera functionality

The Android camera permissions are now properly configured, and you have a complete guide for setting up wireless debugging! 