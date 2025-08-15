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
import com.google.firebase.FirebaseApp
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "push_notifications"
        private const val SESSION_CHANNEL = "session_protocol"
        
        // Static instance for FCM service to access
        var instance: MainActivity? = null
            private set
    }
    
    private lateinit var sessionApiImpl: SessionApiImpl
    private lateinit var notificationReceiver: BroadcastReceiver
    private var notificationEventSink: io.flutter.plugin.common.EventChannel.EventSink? = null

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
        
        // Set up push notifications FIRST (before other setup)
        setupPushNotifications(flutterEngine)
        
        // Set up notification receiver
        setupNotificationReceiver()
        
        // Automatically get FCM token and send to Flutter
        getFCMTokenAndSendToFlutter(flutterEngine)
        
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
        Log.d("MainActivity", "Setting up push notifications channel...")
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        // Set up EventChannel for real-time notifications
        val eventChannel = io.flutter.plugin.common.EventChannel(flutterEngine.dartExecutor.binaryMessenger, "push_notifications_events")
        eventChannel.setStreamHandler(object : io.flutter.plugin.common.EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: io.flutter.plugin.common.EventChannel.EventSink?) {
                Log.d("MainActivity", "EventChannel listener attached")
                notificationEventSink = events
            }
            
            override fun onCancel(arguments: Any?) {
                Log.d("MainActivity", "EventChannel listener detached")
                notificationEventSink = null
            }
        })
        
        // Set up method call handler for Flutter requests
        channel.setMethodCallHandler { call, result ->
            Log.d("MainActivity", "Received method call: ${call.method}")
            when (call.method) {
                                    "requestDeviceToken" -> {
                        Log.d("MainActivity", "Flutter requested device token")
                        // Get FCM token
                        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                            if (task.isSuccessful) {
                                val deviceToken = task.result
                                Log.d("MainActivity", "FCM device token: $deviceToken")

                                // Send token to Flutter
                                channel.invokeMethod("onDeviceTokenReceived", deviceToken)
                                result.success(null)
                            } else {
                                Log.e("MainActivity", "Failed to get FCM token", task.exception)

                                // Fallback to UUID if FCM fails
                                val fallbackToken = UUID.randomUUID().toString()
                                Log.d("MainActivity", "Using fallback device token: $fallbackToken")
                                channel.invokeMethod("onDeviceTokenReceived", fallbackToken)
                                result.success(null)
                            }
                        }
                    }
                    "requestNotificationPermissions" -> {
                        Log.d("MainActivity", "Flutter requested notification permissions")
                        // Android 13+ requires runtime permission for notifications
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
                            }
                        }
                        result.success(true) // Android permissions are usually granted by default
                    }
                    "testMethodChannel" -> {
                        Log.d("MainActivity", "Flutter requested test method channel")
                        result.success("Android method channel is working!")
                    }
                    "testMainActivity" -> {
                        Log.d("MainActivity", "Flutter requested MainActivity test")
                        result.success("MainActivity is working! Session API: ${::sessionApiImpl.isInitialized}")
                    }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Get FCM token on app start
        Log.d("MainActivity", "Attempting to get FCM token on app start...")
        
        // Check if Firebase is initialized
        try {
            val firebaseApp = FirebaseApp.getInstance()
            Log.d("MainActivity", "✅ Firebase is initialized: ${firebaseApp.name}")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Firebase not initialized: ${e.message}")
        }
        
        // Check if FCM is available
        try {
            val isAutoInitEnabled = FirebaseMessaging.getInstance().isAutoInitEnabled
            Log.d("MainActivity", "FCM auto init enabled: $isAutoInitEnabled")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error checking FCM auto init: ${e.message}")
        }
        
        // Add timeout for FCM token retrieval
        val timeoutHandler = android.os.Handler(android.os.Looper.getMainLooper())
        val timeoutRunnable = Runnable {
            Log.e("MainActivity", "❌ FCM token retrieval timed out after 10 seconds")
            
            // Use fallback token
            val fallbackToken = UUID.randomUUID().toString()
            Log.d("MainActivity", "🔄 Using fallback device token due to timeout: $fallbackToken")
            try {
                channel.invokeMethod("onDeviceTokenReceived", fallbackToken)
                Log.d("MainActivity", "✅ Fallback token sent to Flutter successfully")
            } catch (e: Exception) {
                Log.e("MainActivity", "❌ Error sending fallback token to Flutter: ${e.message}")
            }
        }
        
        // Set 10-second timeout
        timeoutHandler.postDelayed(timeoutRunnable, 10000)
        
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            // Cancel timeout since we got a response
            timeoutHandler.removeCallbacks(timeoutRunnable)
            
            if (task.isSuccessful) {
                val deviceToken = task.result
                Log.d("MainActivity", "✅ FCM device token obtained: $deviceToken")
                
                // Send token to Flutter
                try {
                    channel.invokeMethod("onDeviceTokenReceived", deviceToken)
                    Log.d("MainActivity", "✅ Device token sent to Flutter successfully")
                } catch (e: Exception) {
                    Log.e("MainActivity", "❌ Error sending token to Flutter: ${e.message}")
                }
            } else {
                Log.e("MainActivity", "❌ Failed to get FCM token: ${task.exception?.message}")
                
                // Fallback to UUID if FCM fails
                val fallbackToken = UUID.randomUUID().toString()
                Log.d("MainActivity", "🔄 Using fallback device token: $fallbackToken")
                try {
                    channel.invokeMethod("onDeviceTokenReceived", fallbackToken)
                    Log.d("MainActivity", "✅ Fallback token sent to Flutter successfully")
                } catch (e: Exception) {
                    Log.e("MainActivity", "❌ Error sending fallback token to Flutter: ${e.message}")
                }
            }
        }
        
        // Handle incoming messages when app is in foreground
        FirebaseMessaging.getInstance().isAutoInitEnabled = true
    }
    
    private fun getFCMTokenAndSendToFlutter(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        Log.d("MainActivity", "Attempting to get FCM token on app start...")

        // Check if Firebase is initialized
        try {
            val firebaseApp = FirebaseApp.getInstance()
            Log.d("MainActivity", "✅ Firebase is initialized: ${firebaseApp.name}")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Firebase not initialized: ${e.message}")
        }

        // Check if FCM is available
        try {
            val isAutoInitEnabled = FirebaseMessaging.getInstance().isAutoInitEnabled
            Log.d("MainActivity", "FCM auto init enabled: $isAutoInitEnabled")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error checking FCM auto init: ${e.message}")
        }

        // Add timeout for FCM token retrieval
        val timeoutHandler = android.os.Handler(android.os.Looper.getMainLooper())
        val timeoutRunnable = Runnable {
            Log.e("MainActivity", "❌ FCM token retrieval timed out after 10 seconds")

            // Use fallback token
            val fallbackToken = UUID.randomUUID().toString()
            Log.d("MainActivity", "🔄 Using fallback device token due to timeout: $fallbackToken")
            try {
                channel.invokeMethod("onDeviceTokenReceived", fallbackToken)
                Log.d("MainActivity", "✅ Fallback token sent to Flutter successfully")
            } catch (e: Exception) {
                Log.e("MainActivity", "❌ Error sending fallback token to Flutter: ${e.message}")
            }
        }

        // Set 10-second timeout
        timeoutHandler.postDelayed(timeoutRunnable, 10000)

        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            // Cancel timeout since we got a response
            timeoutHandler.removeCallbacks(timeoutRunnable)

            if (task.isSuccessful) {
                val deviceToken = task.result
                Log.d("MainActivity", "✅ FCM device token obtained: $deviceToken")

                // Send token to Flutter
                try {
                    channel.invokeMethod("onDeviceTokenReceived", deviceToken)
                    Log.d("MainActivity", "✅ Device token sent to Flutter successfully")
                } catch (e: Exception) {
                    Log.e("MainActivity", "❌ Error sending token to Flutter: ${e.message}")
                }
            } else {
                Log.e("MainActivity", "❌ Failed to get FCM token: ${task.exception?.message}")

                // Fallback to UUID if FCM fails
                val fallbackToken = UUID.randomUUID().toString()
                Log.d("MainActivity", "🔄 Using fallback device token: $fallbackToken")
                try {
                    channel.invokeMethod("onDeviceTokenReceived", fallbackToken)
                    Log.d("MainActivity", "✅ Fallback token sent to Flutter successfully")
                } catch (e: Exception) {
                    Log.e("MainActivity", "❌ Error sending fallback token to Flutter: ${e.message}")
                }
            }
        }
    }
    
    private fun setupNotificationReceiver() {
        notificationReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "FORWARD_NOTIFICATION_TO_FLUTTER" || 
                    intent?.action == "com.strapblaque.sechat.NOTIFICATION_RECEIVED") {
                    
                    Log.d("MainActivity", "Received notification broadcast: ${intent.action}")
                    val notificationData = intent.getSerializableExtra("notification_data") as? HashMap<String, Any>
                    if (notificationData != null) {
                        Log.d("MainActivity", "Received notification data from FCM service: $notificationData")
                        
                        // Ensure we're on the main thread for Flutter method calls
                        if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) {
                            // Already on main thread
                            forwardNotificationToFlutter(notificationData)
                        } else {
                            // Switch to main thread using Handler (more reliable than runOnUiThread)
                            val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
                            mainHandler.post {
                                forwardNotificationToFlutter(notificationData)
                            }
                        }
                    } else {
                        Log.e("MainActivity", "❌ Notification data is null")
                    }
                }
            }
        }
        
        // Register the receiver with explicit export flag for Android 14+
        val filter = IntentFilter().apply {
            addAction("FORWARD_NOTIFICATION_TO_FLUTTER")
            addAction("com.strapblaque.sechat.NOTIFICATION_RECEIVED")
        }
        registerReceiver(notificationReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        Log.d("MainActivity", "✅ Notification receiver registered for multiple actions")
        
        // Process any stored notifications
        processStoredNotifications()
    }
    
    private fun processStoredNotifications() {
        try {
            Log.d("MainActivity", "Processing stored notifications...")
            
            // Get shared preferences
            val sharedPrefs = getSharedPreferences("pending_notifications", Context.MODE_PRIVATE)
            
            // Get all stored notification keys
            val allKeys = sharedPrefs.all.keys.toList()
            val notificationKeys = allKeys.filter { it.startsWith("notification_") && !it.contains("_type") }
            
            if (notificationKeys.isEmpty()) {
                Log.d("MainActivity", "No stored notifications found")
                return
            }
            
            Log.d("MainActivity", "Found ${notificationKeys.size} stored notifications")
            
            // Process each notification
            val gson = com.google.gson.Gson()
            val editor = sharedPrefs.edit()
            
            for (key in notificationKeys) {
                try {
                    val notificationJson = sharedPrefs.getString(key, null)
                    if (notificationJson != null) {
                        // Get notification type
                        val typeKey = "${key}_type"
                        val type = sharedPrefs.getString(typeKey, "unknown")
                        
                        Log.d("MainActivity", "Processing stored notification: $key (type: $type)")
                        
                        // Parse notification data
                        val notificationData = gson.fromJson(notificationJson, HashMap::class.java) as HashMap<String, Any>
                        
                        // Forward to Flutter
                        forwardNotificationToFlutter(notificationData)
                        
                        // Remove processed notification
                        editor.remove(key)
                        editor.remove(typeKey)
                    }
                } catch (e: Exception) {
                    Log.e("MainActivity", "Error processing stored notification $key: ${e.message}")
                }
            }
            
            // Apply changes
            editor.apply()
            
            Log.d("MainActivity", "✅ Finished processing stored notifications")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error processing stored notifications: ${e.message}")
        }
    }
    
    private fun forwardNotificationToFlutter(notificationData: HashMap<String, Any>) {
        try {
            // Try EventChannel first (most reliable)
            sendNotificationViaEventChannel(notificationData)
            
            // Also try MethodChannel as backup
            val channel = MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger ?: return, CHANNEL)
            channel.invokeMethod("onRemoteNotificationReceived", notificationData)
            Log.d("MainActivity", "✅ Successfully forwarded notification to Flutter via both channels")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error forwarding notification to Flutter: ${e.message}")
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        // Clear static instance
        instance = null
        
        // Unregister the receiver
        try {
            unregisterReceiver(notificationReceiver)
        } catch (e: Exception) {
            Log.e("MainActivity", "Error unregistering receiver: ${e.message}")
        }
    }
    
    // Method to send notification via EventChannel
    fun sendNotificationViaEventChannel(notificationData: Map<String, Any>) {
        try {
            // This method should only be called from the main thread
            // The FCM service now handles thread switching before calling this method
            sendNotificationToEventChannel(notificationData)
        } catch (e: Exception) {
            Log.e("MainActivity", "Error sending notification via EventChannel: ${e.message}")
        }
    }
    
    private fun sendNotificationToEventChannel(notificationData: Map<String, Any>) {
        try {
            if (notificationEventSink != null) {
                notificationEventSink!!.success(notificationData)
                Log.d("MainActivity", "✅ Notification sent via EventChannel")
            } else {
                Log.d("MainActivity", "EventChannel sink not available")
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error in sendNotificationToEventChannel: ${e.message}")
        }
    }
} 