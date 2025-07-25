# iOS Wireless Debugging Setup

## 🎯 **iOS Wireless Debugging Overview**

iOS wireless debugging requires:
- **macOS** with **Xcode** installed
- **iPhone** with **iOS 16.1+** 
- **Same WiFi network** for both devices
- **Developer account** (free Apple ID works)

---

## 📱 **Step 1: Enable Developer Mode on iPhone**

### **Enable Developer Mode:**
1. Go to **Settings > Privacy & Security**
2. Scroll down to **Developer Mode**
3. Toggle **Developer Mode** ON
4. Restart your iPhone when prompted

### **Enable Wireless Debugging:**
1. Connect iPhone to Mac via **USB cable**
2. Open **Xcode**
3. Go to **Window > Devices and Simulators**
4. Select your iPhone
5. Check **"Connect via network"** checkbox
6. Disconnect USB cable

---

## 🖥️ **Step 2: Configure Xcode for Wireless Debugging**

### **Open Xcode:**
```bash
# Open Xcode workspace
open ios/Runner.xcworkspace
```

### **Configure Project Settings:**
1. Select **Runner** project in Xcode
2. Select **Runner** target
3. Go to **Signing & Capabilities**
4. Ensure **Team** is selected (your Apple ID)
5. Check **"Automatically manage signing"**

### **Enable Network Debugging:**
1. In **Devices and Simulators** window
2. Select your iPhone
3. Check **"Connect via network"**
4. Your iPhone should show as **"Connected via network"**

---

## 🔧 **Step 3: Flutter Wireless Debugging Commands**

### **List Wireless Devices:**
```bash
flutter devices
```

### **Run App Wirelessly:**
```bash
# Run on wireless iPhone
flutter run -d <DEVICE_ID>

# Or run on all devices
flutter run
```

### **Install App Wirelessly:**
```bash
# Install debug version
flutter install

# Install release version
flutter install --release
```

### **Hot Reload/Restart:**
```bash
# In the terminal where flutter run is active:
# Press 'r' for hot reload
# Press 'R' for hot restart
# Press 'q' to quit
```

---

## 🚀 **Step 4: Quick Setup Commands**

### **Complete iOS Wireless Setup:**
```bash
#!/bin/bash
echo "Setting up iOS wireless debugging..."

# 1. Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode not found. Please install Xcode from App Store."
    exit 1
fi

# 2. Open Xcode workspace
echo "Opening Xcode workspace..."
open ios/Runner.xcworkspace

# 3. Check Flutter devices
echo "Checking available devices..."
flutter devices

# 4. Instructions for manual setup
echo ""
echo "📱 Manual Setup Required:"
echo "1. In Xcode: Window > Devices and Simulators"
echo "2. Select your iPhone"
echo "3. Check 'Connect via network'"
echo "4. Disconnect USB cable"
echo "5. Verify device shows as 'Connected via network'"
echo ""
echo "Then run: flutter run"
```

### **Save and Run:**
```bash
chmod +x setup_ios_wireless.sh
./setup_ios_wireless.sh
```

---

## 🔍 **Step 5: Troubleshooting iOS Wireless Debugging**

### **Issue 1: Device Not Showing as Wireless**
**Solution:**
1. Ensure iPhone is connected via USB first
2. In Xcode: **Window > Devices and Simulators**
3. Select iPhone and check **"Connect via network"**
4. Wait for "Connected via network" status
5. Disconnect USB cable

### **Issue 2: Flutter Can't Find Wireless Device**
**Solution:**
```bash
# Restart Flutter daemon
flutter daemon --shutdown
flutter doctor

# Check devices again
flutter devices

# If still not working, restart Xcode and reconnect
```

### **Issue 3: Connection Lost**
**Solution:**
1. Check both devices are on same WiFi
2. Reconnect via USB and re-enable wireless
3. Restart Xcode if needed
4. Try different WiFi network

### **Issue 4: Code Signing Issues**
**Solution:**
1. In Xcode: **Runner > Signing & Capabilities**
2. Select your **Team** (Apple ID)
3. Check **"Automatically manage signing"**
4. Clean and rebuild:
```bash
flutter clean
flutter pub get
flutter build ios
```

---

## 📋 **Step 6: Verification Checklist**

### **Prerequisites:**
- [ ] macOS with Xcode installed
- [ ] iPhone with iOS 16.1+
- [ ] Both devices on same WiFi
- [ ] Apple Developer account (free)
- [ ] iPhone connected via USB initially

### **Xcode Setup:**
- [ ] Xcode can see iPhone via USB
- [ ] "Connect via network" enabled
- [ ] iPhone shows "Connected via network"
- [ ] Code signing configured properly

### **Flutter Setup:**
- [ ] `flutter devices` shows wireless iPhone
- [ ] `flutter run` works wirelessly
- [ ] Hot reload works (`r` key)
- [ ] Hot restart works (`R` key)
- [ ] App installs wirelessly

---

## 🧪 **Step 7: Testing Commands**

### **Basic Testing:**
```bash
# List all devices (USB and wireless)
flutter devices

# Run on wireless iPhone
flutter run -d <DEVICE_ID>

# Install app wirelessly
flutter install

# Check Flutter doctor
flutter doctor
```

### **Advanced Testing:**
```bash
# Run with verbose output
flutter run -v

# Run in profile mode
flutter run --profile

# Run in release mode
flutter run --release

# Check device logs
flutter logs
```

---

## 🔄 **Step 8: Development Workflow**

### **Daily Workflow:**
1. **Start Xcode** and ensure wireless connection
2. **Check devices:** `flutter devices`
3. **Run app:** `flutter run`
4. **Make changes** and use hot reload (`r`)
5. **Test thoroughly** on wireless device

### **When Connection Issues Occur:**
1. **Reconnect via USB**
2. **Re-enable wireless** in Xcode
3. **Disconnect USB**
4. **Verify connection** with `flutter devices`

---

## 🚨 **Common Issues & Solutions**

### **"No devices found"**
- Check Xcode Devices window
- Re-enable "Connect via network"
- Restart Xcode and Flutter

### **"Code signing failed"**
- Check signing in Xcode
- Select correct team
- Clean and rebuild project

### **"Connection lost"**
- Check WiFi connectivity
- Reconnect via USB and re-enable wireless
- Try different WiFi network

### **"App won't install"**
- Check device storage
- Verify code signing
- Try `flutter clean` and rebuild

---

## 📱 **iOS-Specific Features**

### **Camera Permission Testing:**
```bash
# Run app wirelessly
flutter run -d <DEVICE_ID>

# Test QR code scanning
# Should show camera permission dialog
# Check iOS Settings > SeChat > Camera
```

### **Notification Testing:**
```bash
# Test push notifications
# Verify notifications appear on wireless device
# Check notification settings in iOS
```

### **Performance Testing:**
```bash
# Run in profile mode for performance testing
flutter run --profile -d <DEVICE_ID>

# Monitor performance on wireless device
```

---

## 🔄 **Next Steps:**

1. **Follow the setup guide** above
2. **Test wireless debugging** with your iPhone
3. **Verify camera permissions** work wirelessly
4. **Test QR code scanning** functionality
5. **Confirm notifications** work properly
6. **Set up daily workflow** for wireless development

The iOS wireless debugging setup will allow you to develop and test your SeChat app without keeping your iPhone connected via USB! 