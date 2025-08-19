package com.strapblaque.sechat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Boot receiver to ensure notifications work after device restart
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> {
                Log.d("BootReceiver", "Device boot completed, initializing notification services")
                // Initialize notification services after boot
                initializeNotificationServices(context)
            }
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.d("BootReceiver", "App package replaced, reinitializing notification services")
                initializeNotificationServices(context)
            }
            Intent.ACTION_PACKAGE_REPLACED -> {
                Log.d("BootReceiver", "Package replaced, checking if it's our app")
                val packageName = intent.data?.schemeSpecificPart
                if (packageName == context.packageName) {
                    Log.d("BootReceiver", "Our app was replaced, reinitializing notification services")
                    initializeNotificationServices(context)
                }
            }
        }
    }

    private fun initializeNotificationServices(context: Context) {
        try {
            // This will be handled by Flutter when the app starts
            // For now, we just log that we're ready
            Log.d("BootReceiver", "Notification services ready for initialization")
        } catch (e: Exception) {
            Log.e("BootReceiver", "Error initializing notification services", e)
        }
    }
}
