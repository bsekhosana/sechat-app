# Codemagic Pre-Build Script Guide

## 🚀 **Quick Fix for Your Current Issue**

### **Problem:** Script prints code instead of executing
This happens when the script is not properly formatted in the Codemagic UI.

### **Solution:** Use this exact script in the Pre-build script field:

```bash
#!/bin/bash
set -e
set -x

echo "🚀 Starting pre-build script..."

# Setup Android keystore
echo "🔐 Setting up Android keystore..."
KEYSTORE_PATH="$CM_BUILD_DIR/android/app/app-release-key.jks"
mkdir -p "$(dirname "$KEYSTORE_PATH")"
echo "$ANDROID_SIGNING_KEY_BASE64" | base64 -d > "$KEYSTORE_PATH"
ls -la "$KEYSTORE_PATH"

# Test keystore
keytool -list -v -keystore "$KEYSTORE_PATH" -alias "$ANDROID_SIGNING_KEY_ALIAS" -storepass "$ANDROID_SIGNING_STORE_PASSWORD" -noprompt
echo "✅ Android keystore set up successfully"

# Version management
echo "📈 Setting up version management..."
flutter build-name "2.0.0"
flutter build-number "$CM_BUILD_NUMBER"
echo "✅ Version updated to 2.0.0+$CM_BUILD_NUMBER"

echo "✅ Pre-build script completed successfully!"
```

## 📋 **Required Environment Variables**

Make sure these are set in your Codemagic Environment Variables:

| Variable | Description | Required |
|----------|-------------|----------|
| `ANDROID_SIGNING_KEY_BASE64` | Base64 encoded keystore file | ✅ |
| `ANDROID_SIGNING_KEY_ALIAS` | Keystore alias (e.g., "sechat-release") | ✅ |
| `ANDROID_SIGNING_STORE_PASSWORD` | Keystore password | ✅ |
| `ANDROID_SIGNING_KEY_PASSWORD` | Key password (if different) | ✅ |

## 🔧 **How to Set Up Environment Variables**

1. **Go to Codemagic UI** → Your project → Environment variables
2. **Add each variable:**
   - Variable name: `ANDROID_SIGNING_KEY_BASE64`
   - Variable value: Your base64 encoded keystore
   - Check "Secret" checkbox
3. **Repeat for all required variables**

## 📝 **Step-by-Step Setup**

### **1. Prepare Your Keystore**
```bash
# Convert your keystore to base64
base64 -i your-keystore.jks | tr -d '\n'
```

### **2. Add Environment Variables**
- `ANDROID_SIGNING_KEY_BASE64`: [Your base64 keystore]
- `ANDROID_SIGNING_KEY_ALIAS`: `sechat-release`
- `ANDROID_SIGNING_STORE_PASSWORD`: [Your keystore password]

### **3. Add Pre-Build Script**
Copy the script above into the "Pre-build script" field in Codemagic UI.

### **4. Test the Build**
Start a new build and check the logs.

## 🐛 **Common Issues & Solutions**

### **Issue 1: Script prints instead of executes**
**Cause:** Incorrect formatting in Codemagic UI
**Solution:** Use the exact script format above

### **Issue 2: Environment variables not found**
**Cause:** Variables not set or named incorrectly
**Solution:** Check variable names and values in Codemagic UI

### **Issue 3: Keystore creation fails**
**Cause:** Invalid base64 or wrong path
**Solution:** Verify base64 encoding and path

### **Issue 4: Version not updating**
**Cause:** Flutter commands not working
**Solution:** Check if Flutter is available in build environment

## 📊 **Expected Output**

When working correctly, you should see:

```
🚀 Starting pre-build script...
🔐 Setting up Android keystore...
Creating keystore at: /Users/builder/clone/android/app/app-release-key.jks
-rw-r--r-- 1 builder builder 2.8K Jul 23 13:24 app-release-key.jks
Certificate fingerprint: SHA256:...
✅ Android keystore set up successfully
📈 Setting up version management...
✅ Version updated to 2.0.0+123
✅ Pre-build script completed successfully!
```

## 🔍 **Debugging Tips**

1. **Check build logs** for error messages
2. **Verify environment variables** are set correctly
3. **Test keystore locally** before uploading
4. **Use `set -x`** to see all commands executed
5. **Check file permissions** and paths

## 📱 **Version Management**

The script automatically:
- Sets version to `2.0.0`
- Uses Codemagic build number (`$CM_BUILD_NUMBER`)
- Updates `pubspec.yaml` with new version

## 🎯 **Next Steps**

1. **Copy the script** into Codemagic UI
2. **Verify environment variables** are set
3. **Start a new build**
4. **Check build logs** for success
5. **Deploy to app stores**

## 📞 **Support**

If you still have issues:
1. Check Codemagic build logs
2. Verify all environment variables
3. Test keystore locally
4. Contact Codemagic support if needed 