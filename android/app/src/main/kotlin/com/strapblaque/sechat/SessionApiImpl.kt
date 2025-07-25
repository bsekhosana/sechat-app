package com.strapblaque.sechat

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import java.security.SecureRandom
import java.util.*
import java.util.Base64

class SessionApiImpl(private val context: Context) : SessionApi.SessionApiHandler {
    
    private val TAG = "SessionApiImpl"
    private val prefs: SharedPreferences = context.getSharedPreferences("session_storage", Context.MODE_PRIVATE)
    private val random = SecureRandom()
    
    override fun generateEd25519KeyPair(result: SessionApi.Result<Map<String, String>>) {
        try {
            Log.d(TAG, "Generating Ed25519 key pair...")
            
            // Generate a simple key pair for demo purposes
            val publicKey = generateRandomKey(32)
            val privateKey = generateRandomKey(64)
                
                val keyPair = mapOf(
                    "publicKey" to publicKey,
                    "privateKey" to privateKey
                )
                
                Log.d(TAG, "Key pair generated successfully")
                result.success(keyPair)
            } catch (e: Exception) {
            Log.e(TAG, "Error generating key pair: ${e.message}")
            result.error(e)
        }
    }

    override fun initializeSession(identity: SessionApi.SessionIdentity, result: SessionApi.Result<Void>) {
        try {
            Log.d(TAG, "Initializing Session with identity: ${identity.sessionId}")
            
            // Save the identity to storage
            prefs.edit().putString("session_identity", identity.sessionId ?: "").apply()
            prefs.edit().putString("public_key", identity.publicKey ?: "").apply()
            prefs.edit().putString("private_key", identity.privateKey ?: "").apply()
            
            Log.d(TAG, "Session initialized successfully")
                @Suppress("UNCHECKED_CAST")
            result.success(null as Void)
            } catch (e: Exception) {
            Log.e(TAG, "Error initializing session: ${e.message}")
            result.error(e)
        }
    }

    override fun connect(result: SessionApi.Result<Void>) {
        try {
            Log.d(TAG, "Connecting to Session network...")
            
            // Simulate connection delay
            Thread.sleep(1000)
            
                Log.d(TAG, "Connected to Session network")
                @Suppress("UNCHECKED_CAST")
            result.success(null as Void)
            } catch (e: Exception) {
            Log.e(TAG, "Error connecting: ${e.message}")
            result.error(e)
        }
    }

    override fun disconnect(result: SessionApi.Result<Void>) {
            try {
            Log.d(TAG, "Disconnecting from Session network...")
            
                Log.d(TAG, "Disconnected from Session network")
                @Suppress("UNCHECKED_CAST")
            result.success(null as Void)
            } catch (e: Exception) {
            Log.e(TAG, "Error disconnecting: ${e.message}")
            result.error(e)
        }
    }
    
    override fun saveToStorage(key: String, value: String, result: SessionApi.Result<Void>) {
            try {
                Log.d(TAG, "Saving to storage: $key")
            prefs.edit().putString(key, value).apply()
            @Suppress("UNCHECKED_CAST")
            result.success(null as Void)
            } catch (e: Exception) {
            Log.e(TAG, "Error saving to storage: ${e.message}")
            result.error(e)
        }
    }

    override fun loadFromStorage(key: String, result: SessionApi.Result<String>) {
            try {
                Log.d(TAG, "Loading from storage: $key")
            val value = prefs.getString(key, "") ?: ""
                result.success(value)
            } catch (e: Exception) {
            Log.e(TAG, "Error loading from storage: ${e.message}")
            result.error(e)
        }
    }

    override fun generateSessionId(publicKey: String, result: SessionApi.Result<String>) {
        try {
            Log.d(TAG, "Generating Session ID for public key...")
            
            // Generate a Session ID based on the public key
            val sessionId = generateSessionIdFromPublicKey(publicKey)
            
            Log.d(TAG, "Session ID generated: $sessionId")
                result.success(sessionId)
            } catch (e: Exception) {
            Log.e(TAG, "Error generating Session ID: ${e.message}")
            result.error(e)
        }
    }

    override fun validateSessionId(sessionId: String, result: SessionApi.Result<Boolean>) {
        try {
            Log.d(TAG, "Validating Session ID: $sessionId")
            
            // Basic validation - check if it's not empty and has reasonable length
            val isValid = sessionId.isNotEmpty() && sessionId.length >= 10
            
            Log.d(TAG, "Session ID validation result: $isValid")
                result.success(isValid)
            } catch (e: Exception) {
            Log.e(TAG, "Error validating Session ID: ${e.message}")
            result.error(e)
        }
    }
    
    private fun generateRandomKey(length: Int): String {
        val bytes = ByteArray(length)
        random.nextBytes(bytes)
        return Base64.getEncoder().encodeToString(bytes)
    }
    
    private fun generateSessionIdFromPublicKey(publicKey: String): String {
        // Simple hash-based Session ID generation
        val hash = publicKey.hashCode().toString(16)
        val timestamp = System.currentTimeMillis().toString(16)
        return (hash + timestamp).uppercase()
    }
    
    // Synchronous methods for legacy channel support
    fun generateEd25519KeyPairSync(): Map<String, String> {
        val publicKey = generateRandomKey(32)
        val privateKey = generateRandomKey(64)
        return mapOf("publicKey" to publicKey, "privateKey" to privateKey)
    }
    
    fun initializeSessionSync(identity: SessionApi.SessionIdentity) {
        Log.d(TAG, "Legacy: Initializing Session with identity: ${identity.sessionId}")
        prefs.edit().putString("session_identity", identity.sessionId ?: "").apply()
        prefs.edit().putString("public_key", identity.publicKey ?: "").apply()
        prefs.edit().putString("private_key", identity.privateKey ?: "").apply()
        Log.d(TAG, "Legacy: Session initialized successfully")
    }
    
    fun connectSync() {
        Log.d(TAG, "Legacy: Connecting to Session network...")
        Thread.sleep(1000) // Simulate connection delay
        Log.d(TAG, "Legacy: Connected to Session network")
    }
    
    fun disconnectSync() {
        Log.d(TAG, "Legacy: Disconnecting from Session network...")
        Log.d(TAG, "Legacy: Disconnected from Session network")
    }
} 