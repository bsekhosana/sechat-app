package com.strapblaque.sechat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.strapblaque.sechat.SessionApi
import com.strapblaque.sechat.SessionApiImpl
import android.util.Log
import java.util.UUID
// Firebase imports removed - socket-based communication only
import android.os.Bundle

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "push_notifications"
        private const val SESSION_CHANNEL = "session_protocol"
        
        // Static instance for FCM service to access
        var instance: MainActivity? = null
            private set
    }
    
    private lateinit var sessionApiImpl: SessionApiImpl
    // Notification-related variables removed - socket-based communication only

    init {
        Log.d("MainActivity", "MainActivity constructor called")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d("MainActivity", "MainActivity onCreate called")
        instance = this
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        Log.d("MainActivity", "Configuring Flutter engine...")
        
        // Initialize Session Protocol implementation
        sessionApiImpl = SessionApiImpl(this)
        
        // Set up Pigeon-generated SessionApi
        try {
            SessionApi.SessionApiHandler.setUp(flutterEngine.dartExecutor.binaryMessenger, sessionApiImpl)
            Log.d("MainActivity", "SessionApi.SessionApiHandler.setUp called successfully")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error setting up SessionApi: ${e.message}")
        }
        
        // Set up legacy Session Protocol channel
        setupSessionProtocolChannel(flutterEngine)
        
        // Set up simplified method channel - socket-based communication only
        setupPushNotifications(flutterEngine)
        
        Log.d("MainActivity", "Flutter engine configuration complete")
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
        Log.d("MainActivity", "Setting up simplified method channel - socket-based communication only")
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        // Method channel handler simplified - socket-based communication only
        channel.setMethodCallHandler { call, result ->
            Log.d("MainActivity", "Received method call: ${call.method}")
            when (call.method) {
                "testMethodChannel" -> {
                    Log.d("MainActivity", "testMethodChannel called")
                    result.success("MainActivity method channel is working")
                }
                
                "testMainActivity" -> {
                    Log.d("MainActivity", "testMainActivity called")
                    result.success("MainActivity is responsive")
                }
                
                else -> {
                    Log.d("MainActivity", "Method not implemented: ${call.method}")
                    result.notImplemented()
                }
            }
        }
        
        Log.d("MainActivity", "✅ Method channel setup completed - socket-based communication only")
    }
    
    // FCM token methods removed - socket-based communication only
    
    // FCM token retrieval methods removed - socket-based communication only
    
    // Token sending methods removed - socket-based communication only
    
    // Notification receiver methods removed - socket-based communication only
    
    // Stored notification processing removed - socket-based communication only
    
    // Notification forwarding methods removed - socket-based communication only
    
    // Permission request result handling removed - socket-based communication only
    
    override fun onDestroy() {
        super.onDestroy()
        // Clear static instance
        instance = null
        Log.d("MainActivity", "✅ MainActivity destroyed - socket-based communication only")
    }
    
    // All notification methods removed - socket-based communication only
} 