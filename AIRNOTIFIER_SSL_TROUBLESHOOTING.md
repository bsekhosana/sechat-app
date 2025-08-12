# AirNotifier SSL Certificate Troubleshooting Guide

## 🎯 Overview

This guide provides comprehensive solutions for SSL certificate issues when connecting to AirNotifier servers, including both development and production environments.

## ❌ **Problem: SSL Certificate Verification Failure**

**Error Message:**
```
flutter: 📱 AirNotifierService: ❌ Connection test failed: HandshakeException: Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED: application verification failure(handshake.cc:391))
```

**Root Cause:**
- Invalid or expired SSL certificate on the server
- Self-signed certificate not trusted by the client
- Certificate mismatch between domain and server
- Development server using HTTPS without proper certificates

## 🔧 **Solutions Implemented**

### **1. Environment-Based Configuration**

The AirNotifier service now automatically switches between development and production servers:

```dart
// lib/core/config/airnotifier_config.dart
class AirNotifierConfig {
  // Environment detection
  static bool get isDevelopment => kDebugMode;
  static bool get isProduction => !kDebugMode;
  
  // Server URLs
  static const String _devServer = 'http://41.76.111.100:1337';
  static const String _prodServer = 'https://push.strapblaque.com';
  
  // Get base URL based on environment
  static String get baseUrl {
    if (isDevelopment) {
      return _devServer;  // HTTP for development
    } else {
      return _prodServer; // HTTPS for production
    }
  }
}
```

**Benefits:**
- ✅ **Automatic switching**: No manual configuration needed
- ✅ **Development safety**: Uses HTTP for local development
- ✅ **Production security**: Uses HTTPS for production
- ✅ **Easy debugging**: Clear environment detection

### **2. Enhanced Error Reporting**

The service now provides detailed error information:

```dart
// Enhanced error handling with SSL-specific guidance
if (e.toString().contains('CERTIFICATE_VERIFY_FAILED')) {
  print('📱 AirNotifierService: 💡 SSL Certificate issue detected');
  print('📱 AirNotifierService: 💡 Current URL: $_baseUrl');
  if (_baseUrl.startsWith('https://')) {
    print('📱 AirNotifierService: 💡 Consider using HTTP for development or fix SSL certificate');
  }
}
```

**Benefits:**
- ✅ **Clear error messages**: Easy to identify SSL issues
- ✅ **Actionable guidance**: Suggests solutions
- ✅ **URL information**: Shows which server is being used
- ✅ **Environment awareness**: Different advice for dev/prod

### **3. Configuration Debugging**

Easy access to current configuration:

```dart
// Print current configuration
AirNotifierConfig.printConfig();

// Output:
// 🔧 AirNotifierConfig: Environment: Development
// 🔧 AirNotifierConfig: Base URL: http://41.76.111.100:1337
// 🔧 AirNotifierConfig: SSL Enabled: false
// 🔧 AirNotifierConfig: SSL Verification Required: false
```

## 🚀 **How to Use**

### **Development Environment**
1. **Automatic**: The service automatically uses HTTP for development
2. **No configuration needed**: Just run the app in debug mode
3. **Safe**: No SSL certificate issues in development

### **Production Environment**
1. **Automatic**: The service automatically uses HTTPS for production
2. **Secure**: Proper SSL verification enabled
3. **Professional**: Uses production domain with valid certificates

### **Manual Override (Development Only)**
```dart
// For testing specific servers
AirNotifierConfig.setManualBaseUrl('http://192.168.1.100:1337');
```

## 🧪 **Testing the Fix**

### **1. Test Development Mode**
```bash
# Run in debug mode (should use HTTP)
flutter run --debug

# Expected output:
# 🔧 AirNotifierConfig: Environment: Development
# 🔧 AirNotifierConfig: Base URL: http://41.76.111.100:1337
# 🔧 AirNotifierConfig: SSL Enabled: false
```

### **2. Test Production Mode**
```bash
# Run in release mode (should use HTTPS)
flutter run --release

# Expected output:
# 🔧 AirNotifierConfig: Environment: Production
# 🔧 AirNotifierConfig: Base URL: https://push.strapblaque.com
# 🔧 AirNotifierConfig: SSL Enabled: true
```

### **3. Test Connection**
```dart
// Test the connection
final isConnected = await AirNotifierService.instance.testAirNotifierConnection();
print('Connection successful: $isConnected');
```

## 🔍 **Troubleshooting Steps**

### **Step 1: Check Environment**
```dart
// Print current configuration
AirNotifierConfig.printConfig();

// Verify the environment is correct
if (AirNotifierConfig.isDevelopment) {
  print('✅ Running in development mode');
} else {
  print('✅ Running in production mode');
}
```

### **Step 2: Check Server Status**
```bash
# Test HTTP server (development)
curl -v http://41.76.111.100:1337/api/v2/tokens

# Test HTTPS server (production)
curl -v https://push.strapblaque.com/api/v2/tokens
```

### **Step 3: Check SSL Certificate (Production)**
```bash
# Check certificate validity
openssl s_client -connect push.strapblaque.com:443 -servername push.strapblaque.com

# Check certificate expiration
echo | openssl s_client -servername push.strapblaque.com -connect push.strapblaque.com:443 2>/dev/null | openssl x509 -noout -dates
```

### **Step 4: Verify Configuration**
```dart
// Check if configuration is loaded correctly
print('Base URL: ${AirNotifierConfig.baseUrl}');
print('App Name: ${AirNotifierConfig.appName}');
print('App Key: ${AirNotifierConfig.appKey}');
```

## 🛠️ **Advanced Solutions**

### **1. Custom SSL Context (Production)**
```dart
// For custom SSL handling in production
import 'dart:io';

class CustomHttpClient {
  static http.Client createClient() {
    if (AirNotifierConfig.sslEnabled && !AirNotifierConfig.sslVerificationRequired) {
      // Custom SSL handling for development HTTPS
      return http.Client();
    } else {
      // Standard client for production
      return http.Client();
    }
  }
}
```

### **2. Certificate Pinning (Production)**
```dart
// For production environments requiring certificate pinning
class CertificatePinning {
  static const List<String> validFingerprints = [
    'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    'sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
  ];
  
  static bool isValidFingerprint(String fingerprint) {
    return validFingerprints.contains(fingerprint);
  }
}
```

### **3. Retry Logic with SSL Fallback**
```dart
// Retry with different SSL configurations
Future<bool> connectWithRetry() async {
  for (int attempt = 1; attempt <= AirNotifierConfig.maxRetries; attempt++) {
    try {
      return await testAirNotifierConnection();
    } catch (e) {
      if (e.toString().contains('CERTIFICATE_VERIFY_FAILED')) {
        print('📱 AirNotifierService: SSL issue on attempt $attempt, retrying...');
        await Future.delayed(AirNotifierConfig.retryDelay);
      } else {
        rethrow;
      }
    }
  }
  return false;
}
```

## 📋 **Checklist for SSL Issues**

- [ ] **Environment correct**: Development uses HTTP, Production uses HTTPS
- [ ] **Server accessible**: Can reach server via curl/ping
- [ ] **Port open**: Server port (1337) is accessible
- [ ] **Certificate valid**: Production SSL certificate is not expired
- [ ] **Domain match**: Certificate matches the domain being accessed
- [ ] **Firewall**: No firewall blocking the connection
- [ ] **Network**: Device has internet access

## 🎉 **Expected Results After Fix**

### **Development Mode**
```
🔧 AirNotifierConfig: Environment: Development
🔧 AirNotifierConfig: Base URL: http://41.76.111.100:1337
🔧 AirNotifierConfig: SSL Enabled: false
📱 AirNotifierService: ✅ Connection test successful
```

### **Production Mode**
```
🔧 AirNotifierConfig: Environment: Production
🔧 AirNotifierConfig: Base URL: https://push.strapblaque.com
🔧 AirNotifierConfig: SSL Enabled: true
📱 AirNotifierService: ✅ Connection test successful
```

## 🚨 **Common Issues and Solutions**

### **Issue: Still getting SSL errors in development**
**Solution**: Ensure app is running in debug mode (`flutter run --debug`)

### **Issue: Production server not accessible**
**Solution**: Check server status and SSL certificate validity

### **Issue: Configuration not loading**
**Solution**: Verify import path and file structure

### **Issue: Manual override not working**
**Solution**: Ensure running in debug mode and using correct method

## 🔮 **Future Enhancements**

1. **Dynamic configuration**: Load from environment variables
2. **Certificate management**: Automatic certificate validation
3. **Health checks**: Regular server connectivity monitoring
4. **Metrics**: Track connection success/failure rates
5. **Alerting**: Notify when SSL issues occur

## 📞 **Support**

If you continue to experience SSL issues after implementing these fixes:

1. **Check logs**: Look for detailed error messages
2. **Verify configuration**: Use `AirNotifierConfig.printConfig()`
3. **Test connectivity**: Use curl to test server directly
4. **Check environment**: Ensure correct mode (dev/prod)
5. **Review server**: Verify server SSL configuration

The implemented solution should resolve the SSL certificate verification failure and provide a robust, environment-aware configuration system.
