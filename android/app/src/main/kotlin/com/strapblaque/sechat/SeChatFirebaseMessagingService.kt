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
        
        // Handle notification when app is in background
        remoteMessage.notification?.let { notification ->
            showNotification(notification.title, notification.body, remoteMessage.data)
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
} 