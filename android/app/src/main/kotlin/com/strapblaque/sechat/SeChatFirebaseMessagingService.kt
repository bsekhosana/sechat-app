package com.strapblaque.sechat

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import android.util.Log
import io.flutter.plugin.common.MethodChannel

class SeChatFirebaseMessagingService : FirebaseMessagingService() {
    
    companion object {
        private const val CHANNEL_ID = "sechat_notifications"
        private const val CHANNEL_NAME = "SeChat Notifications"
        private const val CHANNEL_DESCRIPTION = "Notifications from SeChat"
    }
    
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d("SeChatFCM", "New FCM token: $token")
        
        // Send token to Flutter app
        sendTokenToFlutter(token)
    }
    
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        Log.d("SeChatFCM", "Message received: ${remoteMessage.data}")
        Log.d("SeChatFCM", "Message data keys: ${remoteMessage.data.keys}")
        Log.d("SeChatFCM", "Message data values: ${remoteMessage.data.values}")
        
        // Enhanced metadata extraction
        val enhancedData = HashMap<String, String>(remoteMessage.data)
        
        // Check for encrypted data
        val data = remoteMessage.data["data"]
        val encrypted = remoteMessage.data["encrypted"]
        val checksum = remoteMessage.data["checksum"]
        
        if (data != null) {
            try {
                // Check if this is encrypted data (base64 encoded)
                if (encrypted == "1" || encrypted == "true") {
                    Log.d("SeChatFCM", "Detected encrypted notification data")
                    enhancedData["isEncrypted"] = "true"
                    enhancedData["encryptedData"] = data
                    
                    if (checksum != null && checksum.isNotEmpty()) {
                        Log.d("SeChatFCM", "Notification checksum: $checksum")
                        enhancedData["checksum"] = checksum
                    }
                } else {
                    // Try to parse as JSON for non-encrypted data
                    try {
                        val dataMap = org.json.JSONObject(data)
                        Log.d("SeChatFCM", "Parsed JSON notification data")
                    } catch (e: Exception) {
                        Log.d("SeChatFCM", "Data is not JSON, treating as plain text")
                    }
                }
            } catch (e: Exception) {
                Log.e("SeChatFCM", "Error processing notification data: ${e.message}")
            }
        }
        
        // Log metadata if present
        val metadata = remoteMessage.data["metadata"]
        if (metadata != null) {
            Log.d("SeChatFCM", "Notification metadata: $metadata")
        }
        
        // Log notification details if present
        remoteMessage.notification?.let { notification ->
            Log.d("SeChatFCM", "Notification title: ${notification.title}")
            Log.d("SeChatFCM", "Notification body: ${notification.body}")
        }
        
        // Forward enhanced notification data to Flutter
        forwardNotificationToFlutter(enhancedData)
        
        // Handle notification when app is in background
        remoteMessage.notification?.let { notification ->
            showNotification(notification.title, notification.body, enhancedData)
        }
    }
    
    private fun showNotification(title: String?, body: String?, data: Map<String, String>) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        // Create notification channel for Android O and above
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = CHANNEL_DESCRIPTION
                enableLights(true)
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(channel)
        }
        
        // Create intent to open the app
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            // Add notification data
            data.forEach { (key, value) ->
                putExtra(key, value)
            }
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Build notification
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title ?: "SeChat")
            .setContentText(body ?: "New message")
            .setSmallIcon(android.R.drawable.ic_dialog_email)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        
        // Show notification
        notificationManager.notify(System.currentTimeMillis().toInt(), notification)
    }
    
    private fun sendTokenToFlutter(token: String) {
        // This will be handled by the MainActivity when the app is running
        // For background token updates, we could use a broadcast or shared preferences
        Log.d("SeChatFCM", "Token updated, will be sent to Flutter when app resumes")
    }
    
    private fun forwardNotificationToFlutter(data: Map<String, String>) {
        try {
            Log.d("SeChatFCM", "Forwarding notification data to Flutter: $data")
            
            // Convert Map<String, String> to Map<String, Any> for Flutter
            val flutterData = data.mapValues { it.value as Any }
            
            // Wrap the data in the correct structure that Flutter expects
            val wrappedData = HashMap<String, Any>()
            wrappedData["data"] = HashMap(flutterData)
            
            Log.d("SeChatFCM", "Wrapped notification data for Flutter: $wrappedData")
            
            // Method 1: Try EventChannel first (most reliable)
            try {
                val mainActivity = MainActivity.instance
                if (mainActivity != null) {
                    // Use Handler to post to main thread from service context
                    val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
                    mainHandler.post {
                        try {
                            mainActivity.sendNotificationViaEventChannel(wrappedData)
                            Log.d("SeChatFCM", "✅ EventChannel call successful")
                        } catch (e: Exception) {
                            Log.e("SeChatFCM", "EventChannel call failed: ${e.message}")
                        }
                    }
                    return
                } else {
                    Log.d("SeChatFCM", "MainActivity not available for EventChannel")
                }
            } catch (e: Exception) {
                Log.e("SeChatFCM", "EventChannel call failed: ${e.message}")
            }
            
            // Method 2: Fallback to broadcast (this is already thread-safe)
            val intent = Intent("FORWARD_NOTIFICATION_TO_FLUTTER")
            intent.putExtra("notification_data", wrappedData)
            sendBroadcast(intent)
            
            Log.d("SeChatFCM", "Fallback broadcast sent to MainActivity")
        } catch (e: Exception) {
            Log.e("SeChatFCM", "Error forwarding notification to Flutter: ${e.message}")
        }
    }
} 