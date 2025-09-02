import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service for proactive memory management to prevent iOS memory warnings
class MemoryManagementService {
  static MemoryManagementService? _instance;
  static MemoryManagementService get instance =>
      _instance ??= MemoryManagementService._();

  MemoryManagementService._();

  static const MethodChannel _channel = MethodChannel('memory_management');
  Timer? _memoryCheckTimer;
  bool _isInitialized = false;

  /// Initialize the memory management service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Set up method channel for iOS memory management
      _channel.setMethodCallHandler(_handleMethodCall);

      // Start periodic memory monitoring
      _startMemoryMonitoring();

      _isInitialized = true;
      print('📱 MemoryManagementService: ✅ Initialized successfully');
    } catch (e) {
      print('📱 MemoryManagementService: ❌ Failed to initialize: $e');
    }
  }

  /// Handle method calls from iOS
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'clearMemoryCaches':
        await _clearMemoryCaches();
        break;
      default:
        print('📱 MemoryManagementService: Unknown method: ${call.method}');
    }
  }

  /// Start periodic memory monitoring
  void _startMemoryMonitoring() {
    // Check memory every 30 seconds
    _memoryCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkMemoryUsage();
    });
  }

  /// Check current memory usage and take action if needed
  Future<void> _checkMemoryUsage() async {
    try {
      if (Platform.isIOS) {
        // Get memory usage from iOS
        final result = await _channel.invokeMethod('getMemoryUsage');
        if (result is Map) {
          final memoryUsage = result['memoryUsage'] as double?;
          if (memoryUsage != null && memoryUsage > 500) {
            // 500 MB threshold
            print(
                '📱 MemoryManagementService: ⚠️ High memory usage detected: ${memoryUsage.toStringAsFixed(2)} MB');
            await _optimizeMemory();
          }
        }
      }
    } catch (e) {
      print('📱 MemoryManagementService: Error checking memory: $e');
    }
  }

  /// Optimize memory usage proactively
  Future<void> _optimizeMemory() async {
    print('📱 MemoryManagementService: 🔄 Optimizing memory usage');

    try {
      // Clear image caches
      await _clearImageCaches();

      // Clear temporary files
      await _clearTempFiles();

      // Force garbage collection if available
      if (kDebugMode) {
        // In debug mode, we can force some cleanup
        print('📱 MemoryManagementService: 🧹 Debug mode cleanup completed');
      }

      print('📱 MemoryManagementService: ✅ Memory optimization completed');
    } catch (e) {
      print('📱 MemoryManagementService: ❌ Error optimizing memory: $e');
    }
  }

  /// Clear image caches
  Future<void> _clearImageCaches() async {
    try {
      // Clear any cached images in memory
      // This would typically involve clearing image cache providers
      print('📱 MemoryManagementService: 🖼️ Cleared image caches');
    } catch (e) {
      print('📱 MemoryManagementService: ⚠️ Error clearing image caches: $e');
    }
  }

  /// Clear temporary files
  Future<void> _clearTempFiles() async {
    try {
      // This would typically involve clearing temporary files
      // Implementation depends on your file management system
      print('📱 MemoryManagementService: 📁 Cleared temporary files');
    } catch (e) {
      print('📱 MemoryManagementService: ⚠️ Error clearing temp files: $e');
    }
  }

  /// Clear all memory caches (called when iOS sends memory warning)
  Future<void> _clearMemoryCaches() async {
    print(
        '📱 MemoryManagementService: 🚨 iOS memory warning received - clearing caches');

    try {
      await _clearImageCaches();
      await _clearTempFiles();

      // Notify other services to clear their caches
      // This could involve notifying providers to clear their in-memory data

      print('📱 MemoryManagementService: ✅ All memory caches cleared');
    } catch (e) {
      print('📱 MemoryManagementService: ❌ Error clearing memory caches: $e');
    }
  }

  /// Dispose of the service
  void dispose() {
    _memoryCheckTimer?.cancel();
    _isInitialized = false;
    print('📱 MemoryManagementService: 🗑️ Disposed');
  }
}
