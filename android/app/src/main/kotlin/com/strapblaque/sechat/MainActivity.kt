package com.strapblaque.sechat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.strapblaque.sechat.SessionApi
import com.strapblaque.sechat.SessionApiImpl
import android.util.Log
import java.util.UUID
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.RemoteMessage

class MainActivity : FlutterActivity() {
    private lateinit var sessionApiImpl: SessionApiImpl
    private val CHANNEL = "push_notifications"
    private val SESSION_CHANNEL = "session_protocol"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize Session Protocol implementation
        sessionApiImpl = SessionApiImpl(this)
        
        // Set up Pigeon-generated SessionApi
        SessionApi.SessionApiHandler.setUp(flutterEngine.dartExecutor.binaryMessenger, sessionApiImpl)
        
        // Set up legacy Session Protocol channel
        setupSessionProtocolChannel(flutterEngine)
        
        // Set up push notifications
        setupPushNotifications(flutterEngine)
    }
    
    private fun setupSessionProtocolChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SESSION_CHANNEL)
        
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "generateEd25519KeyPair" -> {
                    try {
                        Log.d("MainActivity", "Legacy: Generating Ed25519 key pair...")
                        val keyPair = sessionApiImpl.generateEd25519KeyPairSync()
                        result.success(keyPair)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Legacy: Error generating key pair: ${e.message}")
                        result.error("KEY_GENERATION_ERROR", e.message, null)
                    }
                }
                
                "initializeSession" -> {
                    try {
                        Log.d("MainActivity", "Legacy: Initializing Session...")
                        val args = call.arguments as? Map<String, Any>
                        if (args != null) {
                            val identity = SessionApi.SessionIdentity.Builder()
                                .setPublicKey(args["publicKey"] as? String)
                                .setPrivateKey(args["privateKey"] as? String)
                                .setSessionId(args["sessionId"] as? String)
                                .setCreatedAt(args["createdAt"] as? String)
                                .build()
                            
                            sessionApiImpl.initializeSessionSync(identity)
                            result.success(null)
                        } else {
                            result.error("INVALID_ARGUMENTS", "Invalid arguments for initializeSession", null)
                        }
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Legacy: Error initializing session: ${e.message}")
                        result.error("INIT_ERROR", e.message, null)
                    }
                }
                
                "connect" -> {
                    try {
                        Log.d("MainActivity", "Legacy: Connecting to Session network...")
                        sessionApiImpl.connectSync()
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Legacy: Error connecting: ${e.message}")
                        result.error("CONNECTION_ERROR", e.message, null)
                    }
                }
                
                "disconnect" -> {
                    try {
                        Log.d("MainActivity", "Legacy: Disconnecting from Session network...")
                        sessionApiImpl.disconnectSync()
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Legacy: Error disconnecting: ${e.message}")
                        result.error("DISCONNECT_ERROR", e.message, null)
                    }
                }
                
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun setupPushNotifications(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        // Get FCM token
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (task.isSuccessful) {
                val deviceToken = task.result
                Log.d("MainActivity", "FCM device token: $deviceToken")
                
                // Send token to Flutter
                channel.invokeMethod("onDeviceTokenReceived", deviceToken)
            } else {
                Log.e("MainActivity", "Failed to get FCM token", task.exception)
                
                // Fallback to UUID if FCM fails
                val fallbackToken = UUID.randomUUID().toString()
                Log.d("MainActivity", "Using fallback device token: $fallbackToken")
                channel.invokeMethod("onDeviceTokenReceived", fallbackToken)
            }
        }
        
        // Handle incoming messages when app is in foreground
        FirebaseMessaging.getInstance().isAutoInitEnabled = true
    }
} 