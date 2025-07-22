package com.strapblaque.sechat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.example.sechat_app.SessionApi
import com.example.sechat_app.SessionProtocol
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.*

class MainActivity : FlutterActivity(), SessionApi {
    private lateinit var sessionProtocol: SessionProtocol
    private val scope = CoroutineScope(Dispatchers.Main)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize Session Protocol
        sessionProtocol = SessionProtocol(this)
        
        // Set up SessionApi
        SessionApi.setUp(flutterEngine.dartExecutor.binaryMessenger, this)
        
        // Initialize Session Protocol
        scope.launch {
            try {
                val initialized = sessionProtocol.initialize(this@MainActivity)
                if (initialized) {
                    println("Session Protocol initialized successfully")
                } else {
                    println("Failed to initialize Session Protocol")
                }
            } catch (e: Exception) {
                println("Error initializing Session Protocol: ${e.message}")
            }
        }
    }

    // SessionApi implementation
    override fun generateEd25519KeyPair(result: SessionApi.Result<Map<String, String>>) {
        try {
            val keyPair = sessionProtocol.generateEd25519KeyPair()
            result.success(keyPair)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun initializeSession(identity: SessionApi.SessionIdentity, result: SessionApi.Result<Void>) {
        try {
            sessionProtocol.initializeWithIdentity(identity)
            result.success(null)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun connect(result: SessionApi.Result<Void>) {
        try {
            sessionProtocol.connect()
            result.success(null)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun disconnect(result: SessionApi.Result<Void>) {
        try {
            sessionProtocol.disconnect()
            result.success(null)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun sendMessage(message: SessionApi.SessionMessage, result: SessionApi.Result<Void>) {
        try {
            sessionProtocol.sendMessage(message)
            result.success(null)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun sendTypingIndicator(sessionId: String, isTyping: Boolean, result: SessionApi.Result<Void>) {
        try {
            sessionProtocol.sendTypingIndicator(sessionId, isTyping)
            result.success(null)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun addContact(contact: SessionApi.SessionContact, result: SessionApi.Result<Void>) {
        try {
            sessionProtocol.addContact(contact)
            result.success(null)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun removeContact(sessionId: String, result: SessionApi.Result<Void>) {
        try {
            sessionProtocol.removeContact(sessionId)
            result.success(null)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun updateContact(contact: SessionApi.SessionContact, result: SessionApi.Result<Void>) {
        try {
            sessionProtocol.updateContact(contact)
            result.success(null)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun createGroup(group: SessionApi.SessionGroup, result: SessionApi.Result<String>) {
        try {
            val groupId = sessionProtocol.createGroup(group)
            result.success(groupId)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun addMemberToGroup(groupId: String, memberId: String, result: SessionApi.Result<Void>) {
        try {
            sessionProtocol.addMemberToGroup(groupId, memberId)
            result.success(null)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun removeMemberFromGroup(groupId: String, memberId: String, result: SessionApi.Result<Void>) {
        try {
            sessionProtocol.removeMemberFromGroup(groupId, memberId)
            result.success(null)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun leaveGroup(groupId: String, result: SessionApi.Result<Void>) {
        try {
            sessionProtocol.leaveGroup(groupId)
            result.success(null)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun uploadAttachment(attachment: SessionApi.SessionAttachment, result: SessionApi.Result<String>) {
        try {
            val attachmentId = sessionProtocol.uploadAttachment(attachment)
            result.success(attachmentId)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun downloadAttachment(attachmentId: String, result: SessionApi.Result<SessionApi.SessionAttachment>) {
        try {
            val attachment = sessionProtocol.downloadAttachment(attachmentId)
            result.success(attachment)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun encryptMessage(message: String, recipientId: String, result: SessionApi.Result<String>) {
        try {
            val encryptedMessage = sessionProtocol.encryptMessage(message, recipientId)
            result.success(encryptedMessage)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun decryptMessage(encryptedMessage: String, senderId: String, result: SessionApi.Result<String>) {
        try {
            val decryptedMessage = sessionProtocol.decryptMessage(encryptedMessage, senderId)
            result.success(decryptedMessage)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun configureOnionRouting(enabled: Boolean, proxyUrl: String?, result: SessionApi.Result<Void>) {
        try {
            sessionProtocol.configureOnionRouting(enabled, proxyUrl)
            result.success(null)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun saveToStorage(key: String, value: String, result: SessionApi.Result<Void>) {
        try {
            sessionProtocol.saveToStorage(key, value)
            result.success(null)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun loadFromStorage(key: String, result: SessionApi.Result<String>) {
        try {
            val value = sessionProtocol.loadFromStorage(key)
            result.success(value)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun generateSessionId(publicKey: String, result: SessionApi.Result<String>) {
        try {
            val sessionId = sessionProtocol.generateSessionId(publicKey)
            result.success(sessionId)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun validateSessionId(sessionId: String, result: SessionApi.Result<Boolean>) {
        try {
            val isValid = sessionProtocol.validateSessionId(sessionId)
            result.success(isValid)
        } catch (e: Exception) {
            result.error(e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        sessionProtocol.cleanup()
    }
}
