package com.strapblaque.sechat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.example.sechat_app.SessionProtocol
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {
    private lateinit var sessionProtocol: SessionProtocol
    private val scope = CoroutineScope(Dispatchers.Main)
    private val CHANNEL = "com.example.sechat_app/session_protocol"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize Session Protocol
        sessionProtocol = SessionProtocol(this)
        
        // Set up method channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "generateEd25519KeyPair" -> {
                    scope.launch {
                        try {
                            val keyPair = sessionProtocol.generateEd25519KeyPair()
                            result.success(keyPair)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                }
                "initializeSession" -> {
                    scope.launch {
                        try {
                            val sessionId = call.argument<String>("sessionId")
                            val privateKey = call.argument<String>("privateKey")
                            sessionProtocol.initializeSession(sessionId, privateKey)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                }
                "connect" -> {
                    scope.launch {
                        try {
                            sessionProtocol.connect()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                }
                "disconnect" -> {
                    scope.launch {
                        try {
                            sessionProtocol.disconnect()
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                }
                "sendMessage" -> {
                    scope.launch {
                        try {
                            val recipientId = call.argument<String>("recipientId") ?: ""
                            val content = call.argument<String>("content") ?: ""
                            val messageId = sessionProtocol.sendMessage(recipientId, content)
                            result.success(messageId)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                }
                "addContact" -> {
                    scope.launch {
                        try {
                            val sessionId = call.argument<String>("sessionId") ?: ""
                            val displayName = call.argument<String>("displayName") ?: ""
                            sessionProtocol.addContact(sessionId, displayName)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                }
                "removeContact" -> {
                    scope.launch {
                        try {
                            val sessionId = call.argument<String>("sessionId") ?: ""
                            sessionProtocol.removeContact(sessionId)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                }
                "getCurrentSessionId" -> {
                    try {
                        val sessionId = sessionProtocol.getCurrentSessionId()
                        result.success(sessionId)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "getCurrentPrivateKey" -> {
                    try {
                        val privateKey = sessionProtocol.getCurrentPrivateKey()
                        result.success(privateKey)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
} 