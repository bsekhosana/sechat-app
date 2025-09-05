package com.strapblaque.sechat

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Method channel handler for communication between Flutter and native Android code
 * Handles foreground service control and other platform-specific operations
 */
class MethodChannelHandler(private val context: Context) {
    companion object {
        private const val CHANNEL_NAME = "com.strapblaque.sechat/foreground_service"
    }

    fun setupMethodChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    try {
                        SocketForegroundService.startService(context)
                        Log.d("MethodChannelHandler", "Foreground service started")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MethodChannelHandler", "Failed to start foreground service", e)
                        result.error("SERVICE_ERROR", "Failed to start foreground service", e.message)
                    }
                }
                "stopForegroundService" -> {
                    try {
                        SocketForegroundService.stopService(context)
                        Log.d("MethodChannelHandler", "Foreground service stopped")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MethodChannelHandler", "Failed to stop foreground service", e)
                        result.error("SERVICE_ERROR", "Failed to stop foreground service", e.message)
                    }
                }
                "isForegroundServiceRunning" -> {
                    try {
                        // Check if service is running by checking if it's in the foreground
                        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                        val runningServices = activityManager.getRunningServices(Integer.MAX_VALUE)
                        val isRunning = runningServices.any { it.service.className == SocketForegroundService::class.java.name }
                        result.success(isRunning)
                    } catch (e: Exception) {
                        Log.e("MethodChannelHandler", "Failed to check service status", e)
                        result.error("SERVICE_ERROR", "Failed to check service status", e.message)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
