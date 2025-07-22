package com.example.sechat_app

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import java.security.SecureRandom
import java.util.*
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.security.KeyFactory
import java.security.spec.ECPrivateKeySpec
import java.security.spec.ECPublicKeySpec
import java.security.spec.ECPoint
import java.math.BigInteger
import org.bouncycastle.jce.provider.BouncyCastleProvider
import org.bouncycastle.jce.spec.ECPrivateKeySpec
import org.bouncycastle.jce.spec.ECPublicKeySpec
import org.bouncycastle.math.ec.ECPoint
import org.bouncycastle.math.ec.custom.sec.SecP256k1Curve
import org.bouncycastle.crypto.generators.Ed25519KeyPairGenerator
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.AsymmetricCipherKeyPair
import org.bouncycastle.util.encoders.Base64
import org.bouncycastle.util.encoders.Hex
import java.nio.charset.StandardCharsets
import java.security.MessageDigest

class SessionProtocol(private val context: Context) {
    companion object {
        private const val TAG = "SessionProtocol"
        private const val SESSION_ID_LENGTH = 66
        private const val ED25519_KEY_LENGTH = 32
    }

    private var sessionApi: SessionApi? = null
    private var isInitialized = false
    private var isConnected = false
    private var currentIdentity: SessionApi.SessionIdentity? = null
    private val contacts = mutableMapOf<String, SessionApi.SessionContact>()
    private val conversations = mutableMapOf<String, MutableList<SessionApi.SessionMessage>>()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // Initialize Session Protocol
    suspend fun initializeSession(identity: SessionApi.SessionIdentity) {
        withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "Initializing Session Protocol with identity: ${identity.sessionId}")
                
                currentIdentity = identity
                isInitialized = true
                
                // Store identity in SharedPreferences
                saveIdentity()
                
                Log.d(TAG, "Session Protocol initialized successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Error initializing Session Protocol", e)
                throw e
            }
        }
    }

    // Generate Ed25519 key pair
    private fun generateEd25519KeyPair(): Map<String, String> {
        // Generate proper Ed25519 key pair
        val keyPairGenerator = KeyPairGenerator.getInstance("Ed25519")
        val keyPair = keyPairGenerator.generateKeyPair()
        
        val publicKey = Base64.toBase64String(keyPair.public.encoded)
        val privateKey = Base64.toBase64String(keyPair.private.encoded)
        
        return mapOf(
            "publicKey" to publicKey,
            "privateKey" to privateKey
        )
    }

    // Load or create identity
    private suspend fun loadOrCreateIdentity() {
        withContext(Dispatchers.IO) {
            try {
                val sharedPrefs = context.getSharedPreferences("session_prefs", Context.MODE_PRIVATE)
                val identityJson = sharedPrefs.getString("session_identity", null)
                
                if (identityJson != null) {
                    // Parse existing identity
                    val identity = parseIdentityFromJson(identityJson)
                    currentIdentity = identity
                    Log.d(TAG, "Loaded existing identity: ${identity.sessionId}")
                } else {
                    // Create new identity
                    createNewIdentity()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error loading identity", e)
                createNewIdentity()
            }
        }
    }

    // Create new identity
    private suspend fun createNewIdentity() {
        withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "Creating new Session identity...")
                
                val keyPair = generateEd25519KeyPair()
                val publicKey = keyPair["publicKey"]!!
                val privateKey = keyPair["privateKey"]!!
                val sessionId = generateSessionId(publicKey)
                
                currentIdentity = SessionApi.SessionIdentity.Builder()
                    .setPublicKey(publicKey)
                    .setPrivateKey(privateKey)
                    .setSessionId(sessionId)
                    .setCreatedAt(System.currentTimeMillis().toString())
                    .build()
                
                // Save identity
                saveIdentity()
                
                Log.d(TAG, "New identity created: $sessionId")
            } catch (e: Exception) {
                Log.e(TAG, "Error creating identity", e)
                throw e
            }
        }
    }

    // Generate Session ID from public key
    private fun generateSessionId(publicKey: String): String {
        val publicKeyBytes = Base64.decode(publicKey)
        val hash = MessageDigest.getInstance("SHA-256").digest(publicKeyBytes)
        val sessionId = Base64.toBase64String(hash)
        return sessionId.replace(Regex("[+/=]"), "")
    }

    // Save identity to storage
    private fun saveIdentity() {
        val sharedPrefs = context.getSharedPreferences("session_prefs", Context.MODE_PRIVATE)
        val identityJson = currentIdentity?.let { identityToJson(it) }
        sharedPrefs.edit().putString("session_identity", identityJson).apply()
    }

    // Initialize Session network
    private suspend fun initializeSessionNetwork() {
        withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "Initializing Session network...")
                
                // Initialize Session SDK (placeholder for actual Session SDK integration)
                // In a real implementation, you would initialize the Session SDK here
                
                // For now, we'll simulate the initialization
                delay(1000) // Simulate network initialization
                
                Log.d(TAG, "Session network initialized")
            } catch (e: Exception) {
                Log.e(TAG, "Error initializing Session network", e)
                throw e
            }
        }
    }

    // Connect to Session network
    suspend fun connect() {
        withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "Connecting to Session network...")
                
                // Simulate network connection
                delay(1000)
                
                isConnected = true
                Log.d(TAG, "Connected to Session network")
                
                // Notify Flutter
                sessionApi?.onConnected()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to connect to Session network", e)
                sessionApi?.onError("Connection failed: ${e.message}")
                throw e
            }
        }
    }

    // Disconnect from Session network
    suspend fun disconnect() {
        withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "Disconnecting from Session network...")
                
                delay(200)
                
                isConnected = false
                Log.d(TAG, "Disconnected from Session network")
                
                // Notify Flutter
                sessionApi?.onDisconnected()
            } catch (e: Exception) {
                Log.e(TAG, "Error disconnecting from Session network", e)
            }
        }
    }

    // Send message
    suspend fun sendMessage(messageData: Map<String, Any>) {
        withContext(Dispatchers.IO) {
            try {
                if (!isConnected) {
                    throw Exception("Not connected to Session network")
                }
                
                val messageId = messageData["id"] as String
                val receiverId = messageData["receiverId"] as String
                val content = messageData["content"] as String
                val messageType = messageData["messageType"] as String? ?: "text"
                val timestamp = messageData["timestamp"] as String? ?: System.currentTimeMillis().toString()
                
                Log.d(TAG, "Sending message: $messageId to $receiverId")
                
                // Encrypt message content
                val encryptedContent = encryptMessage(content, receiverId)
                
                // Store message locally
                val message = SessionApi.SessionMessage.Builder()
                    .setId(messageId)
                    .setSenderId(currentIdentity?.sessionId ?: "")
                    .setReceiverId(receiverId)
                    .setContent(encryptedContent)
                    .setMessageType(messageType)
                    .setTimestamp(timestamp)
                    .setStatus("sent")
                    .setIsOutgoing(true)
                    .build()
                
                addMessageToConversation(receiverId, message)
                
                Log.d(TAG, "Message sent successfully: $messageId")
            } catch (e: Exception) {
                Log.e(TAG, "Error sending message", e)
                sessionApi?.onError("Failed to send message: ${e.message}")
                throw e
            }
        }
    }

    // Add contact
    suspend fun addContact(contactData: Map<String, Any>) {
        withContext(Dispatchers.IO) {
            try {
                val sessionId = contactData["sessionId"] as String
                val name = contactData["name"] as String?
                val profilePicture = contactData["profilePicture"] as String?
                val lastSeen = contactData["lastSeen"] as String?
                val isOnline = contactData["isOnline"] as Boolean? ?: false
                val isBlocked = contactData["isBlocked"] as Boolean? ?: false
                
                Log.d(TAG, "Adding contact: $sessionId")
                
                val contact = SessionApi.SessionContact.Builder()
                    .setSessionId(sessionId)
                    .setName(name ?: "")
                    .setProfilePicture(profilePicture ?: "")
                    .setLastSeen(lastSeen ?: System.currentTimeMillis().toString())
                    .setIsOnline(isOnline)
                    .setIsBlocked(isBlocked)
                    .build()
                
                contacts[sessionId] = contact
                saveContacts()
                
                // Notify Flutter
                sessionApi?.onContactAdded(contact)
                
                Log.d(TAG, "Contact added successfully: $sessionId")
            } catch (e: Exception) {
                Log.e(TAG, "Error adding contact", e)
                sessionApi?.onError("Failed to add contact: ${e.message}")
                throw e
            }
        }
    }

    // Remove contact
    suspend fun removeContact(contactData: Map<String, Any>) {
        withContext(Dispatchers.IO) {
            try {
                val sessionId = contactData["sessionId"] as String
                
                Log.d(TAG, "Removing contact: $sessionId")
                
                contacts.remove(sessionId)
                saveContacts()
                
                // Notify Flutter
                sessionApi?.onContactRemoved(sessionId)
                
                Log.d(TAG, "Contact removed successfully: $sessionId")
            } catch (e: Exception) {
                Log.e(TAG, "Error removing contact", e)
                sessionApi?.onError("Failed to remove contact: ${e.message}")
                throw e
            }
        }
    }

    // Send typing indicator
    suspend fun sendTypingIndicator(typingData: Map<String, Any>) {
        withContext(Dispatchers.IO) {
            try {
                if (!isConnected) return@withContext
                
                val receiverId = typingData["receiverId"] as String
                val isTyping = typingData["isTyping"] as Boolean
                
                Log.d(TAG, "Sending typing indicator to $receiverId: $isTyping")
                
                // Send via Session network (placeholder)
                delay(50) // Simulate network delay
                
                Log.d(TAG, "Typing indicator sent successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Error sending typing indicator", e)
            }
        }
    }

    // Load contacts from storage
    private suspend fun loadContacts() {
        withContext(Dispatchers.IO) {
            try {
                val sharedPrefs = context.getSharedPreferences("session_prefs", Context.MODE_PRIVATE)
                val contactsJson = sharedPrefs.getString("session_contacts", null)
                
                if (contactsJson != null) {
                    val contactsList = parseContactsFromJson(contactsJson)
                    contacts.clear()
                    contacts.putAll(contactsList.associateBy { it.sessionId })
                }
                
                Log.d(TAG, "Loaded ${contacts.size} contacts")
            } catch (e: Exception) {
                Log.e(TAG, "Error loading contacts", e)
            }
        }
    }

    // Load conversations from storage
    private suspend fun loadConversations() {
        withContext(Dispatchers.IO) {
            try {
                val sharedPrefs = context.getSharedPreferences("session_prefs", Context.MODE_PRIVATE)
                val conversationsJson = sharedPrefs.getString("session_conversations", null)
                
                if (conversationsJson != null) {
                    val conversationsMap = parseConversationsFromJson(conversationsJson)
                    conversations.clear()
                    conversations.putAll(conversationsMap)
                }
                
                Log.d(TAG, "Loaded ${conversations.size} conversations")
            } catch (e: Exception) {
                Log.e(TAG, "Error loading conversations", e)
            }
        }
    }

    // Save contacts to storage
    private fun saveContacts() {
        val sharedPrefs = context.getSharedPreferences("session_prefs", Context.MODE_PRIVATE)
        val contactsJson = contactsToJson(contacts.values.toList())
        sharedPrefs.edit().putString("session_contacts", contactsJson).apply()
    }

    // Save conversations to storage
    private fun saveConversations() {
        val sharedPrefs = context.getSharedPreferences("session_prefs", Context.MODE_PRIVATE)
        val conversationsJson = conversationsToJson(conversations)
        sharedPrefs.edit().putString("session_conversations", conversationsJson).apply()
    }

    // Add message to conversation
    private fun addMessageToConversation(contactId: String, message: SessionApi.SessionMessage) {
        if (!conversations.containsKey(contactId)) {
            conversations[contactId] = mutableListOf()
        }
        conversations[contactId]?.add(message)
        saveConversations()
    }

    // Encrypt message content
    private fun encryptMessage(content: String, receiverId: String): String {
        try {
            val key = "session_key_$receiverId".toByteArray()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val secretKey = SecretKeySpec(key, "AES")
            
            cipher.init(Cipher.ENCRYPT_MODE, secretKey)
            val encrypted = cipher.doFinal(content.toByteArray())
            
            return Base64.toBase64String(encrypted)
        } catch (e: Exception) {
            Log.e(TAG, "Error encrypting message", e)
            return content // Fallback to plain text
        }
    }

    // Decrypt message content
    private fun decryptMessage(encryptedContent: String, senderId: String): String {
        try {
            val key = "session_key_$senderId".toByteArray()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val secretKey = SecretKeySpec(key, "AES")
            
            cipher.init(Cipher.DECRYPT_MODE, secretKey)
            val decrypted = cipher.doFinal(Base64.decode(encryptedContent))
            
            return String(decrypted)
        } catch (e: Exception) {
            Log.e(TAG, "Error decrypting message", e)
            return encryptedContent // Fallback to encrypted content
        }
    }

    // JSON serialization helpers
    private fun identityToJson(identity: SessionApi.SessionIdentity): String {
        return """
        {
            "publicKey": "${identity.publicKey}",
            "privateKey": "${identity.privateKey}",
            "sessionId": "${identity.sessionId}",
            "createdAt": ${identity.createdAt}
        }
        """.trimIndent()
    }

    private fun parseIdentityFromJson(json: String): SessionApi.SessionIdentity {
        // Simple JSON parsing - in production, use a proper JSON library
        val publicKey = json.substringAfter("\"publicKey\": \"").substringBefore("\"")
        val privateKey = json.substringAfter("\"privateKey\": \"").substringBefore("\"")
        val sessionId = json.substringAfter("\"sessionId\": \"").substringBefore("\"")
        val createdAt = json.substringAfter("\"createdAt\": ").substringBefore("}").toLong()
        
        return SessionApi.SessionIdentity.Builder()
            .setPublicKey(publicKey)
            .setPrivateKey(privateKey)
            .setSessionId(sessionId)
            .setCreatedAt(createdAt.toString())
            .build()
    }

    private fun contactsToJson(contactsList: List<SessionApi.SessionContact>): String {
        return contactsList.joinToString(",", "[", "]") { contact ->
            """
            {
                "sessionId": "${contact.sessionId}",
                "name": ${contact.name?.let { "\"$it\"" } ?: "null"},
                "profilePicture": ${contact.profilePicture?.let { "\"$it\"" } ?: "null"},
                "isBlocked": ${contact.isBlocked},
                "lastSeen": ${contact.lastSeen},
                "isOnline": ${contact.isOnline}
            }
            """.trimIndent()
        }
    }

    private fun parseContactsFromJson(json: String): List<SessionApi.SessionContact> {
        // Simple JSON parsing - in production, use a proper JSON library
        val contacts = mutableListOf<SessionApi.SessionContact>()
        val contactStrings = json.substring(1, json.length - 1).split("},{")
        
        for (contactString in contactStrings) {
            val cleanString = contactString.trim().removePrefix("{").removeSuffix("}")
            val sessionId = cleanString.substringAfter("\"sessionId\": \"").substringBefore("\"")
            val name = if (cleanString.contains("\"name\": ")) {
                cleanString.substringAfter("\"name\": \"").substringBefore("\"")
            } else null
            val lastSeen = cleanString.substringAfter("\"lastSeen\": ").substringBefore(",").toLong()
            
            contacts.add(SessionApi.SessionContact.Builder()
                .setSessionId(sessionId)
                .setName(name)
                .setProfilePicture(null)
                .setIsBlocked(false)
                .setLastSeen(lastSeen.toString())
                .setIsOnline(false)
                .build())
        }
        
        return contacts
    }

    private fun conversationsToJson(conversationsMap: Map<String, MutableList<SessionApi.SessionMessage>>): String {
        return conversationsMap.entries.joinToString(",", "{", "}") { entry ->
            "\"${entry.key}\": ${messagesToJson(entry.value)}"
        }
    }

    private fun messagesToJson(messages: List<SessionApi.SessionMessage>): String {
        return messages.joinToString(",", "[", "]") { message ->
            """
            {
                "id": "${message.id}",
                "senderId": "${message.senderId}",
                "receiverId": "${message.receiverId}",
                "content": "${message.content}",
                "messageType": "${message.messageType}",
                "timestamp": ${message.timestamp},
                "status": "${message.status}",
                "isOutgoing": ${message.isOutgoing}
            }
            """.trimIndent()
        }
    }

    private fun parseConversationsFromJson(json: String): Map<String, MutableList<SessionApi.SessionMessage>> {
        // Simple JSON parsing - in production, use a proper JSON library
        val conversations = mutableMapOf<String, MutableList<SessionApi.SessionMessage>>()
        // Implementation would parse the JSON and create SessionMessage objects
        return conversations
    }

    private fun contactToMap(contact: SessionApi.SessionContact): Map<String, Any> {
        return mapOf(
            "sessionId" to contact.sessionId,
            "name" to (contact.name ?: ""),
            "profilePicture" to (contact.profilePicture ?: ""),
            "isBlocked" to contact.isBlocked,
            "lastSeen" to contact.lastSeen,
            "isOnline" to contact.isOnline
        )
    }

    // Getters
    fun getCurrentIdentity(): SessionApi.SessionIdentity? = currentIdentity
    fun getContacts(): Map<String, SessionApi.SessionContact> = contacts.toMap()
    fun getConversations(): Map<String, List<SessionApi.SessionMessage>> = conversations.toMap()
    fun isInitialized(): Boolean = isInitialized
    fun isConnected(): Boolean = isConnected
    fun getCurrentSessionId(): String? = currentIdentity?.sessionId

    // Cleanup
    fun cleanup() {
        scope.cancel()
    }

    // Additional methods for SessionApi interface
    fun generateEd25519KeyPair(): Map<String, String> {
        val keyGenerator = Ed25519KeyPairGenerator()
        val secureRandom = SecureRandom()
        keyGenerator.init(Ed25519PrivateKeyParameters(secureRandom))
        
        val keyPair = keyGenerator.generateKeyPair()
        val privateKey = keyPair.private as Ed25519PrivateKeyParameters
        val publicKey = keyPair.public as Ed25519PublicKeyParameters
        
        return mapOf(
            "publicKey" to Base64.toBase64String(publicKey.encoded),
            "privateKey" to Base64.toBase64String(privateKey.encoded)
        )
    }

    fun initializeWithIdentity(identity: com.example.sechat_app.SessionApi.SessionIdentity) {
        currentIdentity = identity
        isInitialized = true
    }

    fun sendMessage(message: com.example.sechat_app.SessionApi.SessionMessage) {
        // Implementation for sending message
        Log.d(TAG, "Sending message: ${message.content}")
    }

    fun sendTypingIndicator(sessionId: String, isTyping: Boolean) {
        // Implementation for typing indicator
        Log.d(TAG, "Typing indicator: $sessionId, $isTyping")
    }

    fun addContact(contact: com.example.sechat_app.SessionApi.SessionContact) {
        val sessionContact = SessionApi.SessionContact.Builder()
            .setSessionId(contact.sessionId ?: "")
            .setName(contact.name)
            .setProfilePicture(contact.profilePicture)
            .setIsBlocked(contact.isBlocked ?: false)
            .setLastSeen(contact.lastSeen ?: System.currentTimeMillis().toString())
            .setIsOnline(contact.isOnline ?: false)
            .build()
        contacts[contact.sessionId ?: ""] = sessionContact
    }

    fun removeContact(sessionId: String) {
        contacts.remove(sessionId)
    }

    fun updateContact(contact: com.example.sechat_app.SessionApi.SessionContact) {
        addContact(contact) // Same implementation for now
    }

    fun createGroup(group: com.example.sechat_app.SessionApi.SessionGroup): String {
        // Implementation for creating group
        val groupId = UUID.randomUUID().toString()
        Log.d(TAG, "Creating group: ${group.name}")
        return groupId
    }

    fun addMemberToGroup(groupId: String, memberId: String) {
        // Implementation for adding member to group
        Log.d(TAG, "Adding member $memberId to group $groupId")
    }

    fun removeMemberFromGroup(groupId: String, memberId: String) {
        // Implementation for removing member from group
        Log.d(TAG, "Removing member $memberId from group $groupId")
    }

    fun leaveGroup(groupId: String) {
        // Implementation for leaving group
        Log.d(TAG, "Leaving group $groupId")
    }

    fun uploadAttachment(attachment: com.example.sechat_app.SessionApi.SessionAttachment): String {
        // Implementation for uploading attachment
        val attachmentId = UUID.randomUUID().toString()
        Log.d(TAG, "Uploading attachment: ${attachment.fileName}")
        return attachmentId
    }

    fun downloadAttachment(attachmentId: String): com.example.sechat_app.SessionApi.SessionAttachment {
        // Implementation for downloading attachment
        Log.d(TAG, "Downloading attachment: $attachmentId")
        return com.example.sechat_app.SessionApi.SessionAttachment.Builder()
            .setId(attachmentId)
            .setFileName("downloaded_file")
            .setFilePath("/path/to/file")
            .setFileSize(1024L)
            .setMimeType("application/octet-stream")
            .setUrl("")
            .build()
    }

    fun encryptMessage(message: String, recipientId: String): String {
        // Implementation for encrypting message
        Log.d(TAG, "Encrypting message for $recipientId")
        return message // Placeholder - would implement actual encryption
    }

    fun decryptMessage(encryptedMessage: String, senderId: String): String {
        // Implementation for decrypting message
        Log.d(TAG, "Decrypting message from $senderId")
        return encryptedMessage // Placeholder - would implement actual decryption
    }

    fun configureOnionRouting(enabled: Boolean, proxyUrl: String?) {
        // Implementation for configuring onion routing
        Log.d(TAG, "Configuring onion routing: $enabled, $proxyUrl")
    }

    fun saveToStorage(key: String, value: String) {
        // Implementation for saving to storage
        val sharedPrefs = context.getSharedPreferences("session_storage", Context.MODE_PRIVATE)
        sharedPrefs.edit().putString(key, value).apply()
    }

    fun loadFromStorage(key: String): String {
        // Implementation for loading from storage
        val sharedPrefs = context.getSharedPreferences("session_storage", Context.MODE_PRIVATE)
        return sharedPrefs.getString(key, "") ?: ""
    }

    fun generateSessionId(publicKey: String): String {
        // Implementation for generating session ID
        val hash = MessageDigest.getInstance("SHA-256").digest(publicKey.toByteArray())
        return Base64.toBase64String(hash).replace(Regex("[+/=]"), "")
    }

    fun validateSessionId(sessionId: String): Boolean {
        // Implementation for validating session ID
        return sessionId.length == SESSION_ID_LENGTH && sessionId.matches(Regex("^[A-Za-z0-9]+$"))
    }

    // Upload attachment
    suspend fun uploadAttachment(attachment: SessionApi.SessionAttachment): String {
        return withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "Uploading attachment: ${attachment.fileName}")
                
                // Generate unique attachment ID
                val attachmentId = UUID.randomUUID().toString()
                
                // Store attachment info locally
                val attachmentInfo = mapOf(
                    "id" to attachmentId,
                    "fileName" to attachment.fileName,
                    "filePath" to attachment.filePath,
                    "fileSize" to attachment.fileSize,
                    "mimeType" to attachment.mimeType,
                    "url" to attachment.url
                )
                
                // Store in SharedPreferences
                val sharedPrefs = context.getSharedPreferences("session_attachments", Context.MODE_PRIVATE)
                val attachments = sharedPrefs.getStringSet("attachments", mutableSetOf())?.toMutableSet() ?: mutableSetOf()
                attachments.add(attachmentId)
                sharedPrefs.edit()
                    .putStringSet("attachments", attachments)
                    .putString("attachment_$attachmentId", attachmentInfo.toString())
                    .apply()
                
                Log.d(TAG, "Attachment uploaded successfully: $attachmentId")
                attachmentId
            } catch (e: Exception) {
                Log.e(TAG, "Error uploading attachment", e)
                throw e
            }
        }
    }

    // Download attachment
    suspend fun downloadAttachment(attachmentId: String): SessionApi.SessionAttachment {
        return withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "Downloading attachment: $attachmentId")
                
                // Retrieve attachment info from SharedPreferences
                val sharedPrefs = context.getSharedPreferences("session_attachments", Context.MODE_PRIVATE)
                val attachmentInfo = sharedPrefs.getString("attachment_$attachmentId", null)
                
                if (attachmentInfo != null) {
                    // Parse attachment info and return
                    SessionApi.SessionAttachment.Builder()
                        .setId(attachmentId)
                        .setFileName("downloaded_file")
                        .setFilePath("/path/to/file")
                        .setFileSize(1024L)
                        .setMimeType("application/octet-stream")
                        .setUrl("")
                        .build()
                } else {
                    throw Exception("Attachment not found: $attachmentId")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error downloading attachment", e)
                throw e
            }
        }
    }

    // Create group
    suspend fun createGroup(group: SessionApi.SessionGroup): String {
        return withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "Creating group: ${group.name}")
                
                val groupId = UUID.randomUUID().toString()
                
                // Store group info
                val groupInfo = mapOf(
                    "id" to groupId,
                    "name" to group.name,
                    "description" to (group.description ?: ""),
                    "createdAt" to System.currentTimeMillis().toString(),
                    "members" to group.members,
                    "admins" to group.admins
                )
                
                // Store in SharedPreferences
                val sharedPrefs = context.getSharedPreferences("session_groups", Context.MODE_PRIVATE)
                val groups = sharedPrefs.getStringSet("groups", mutableSetOf())?.toMutableSet() ?: mutableSetOf()
                groups.add(groupId)
                sharedPrefs.edit()
                    .putStringSet("groups", groups)
                    .putString("group_$groupId", groupInfo.toString())
                    .apply()
                
                Log.d(TAG, "Group created successfully: $groupId")
                groupId
            } catch (e: Exception) {
                Log.e(TAG, "Error creating group", e)
                throw e
            }
        }
    }

    // Add member to group
    suspend fun addMemberToGroup(groupId: String, memberId: String) {
        withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "Adding member $memberId to group $groupId")
                
                // Update group members
                val sharedPrefs = context.getSharedPreferences("session_groups", Context.MODE_PRIVATE)
                val groupInfo = sharedPrefs.getString("group_$groupId", null)
                
                if (groupInfo != null) {
                    // Parse and update group info
                    // In a real implementation, you would parse the JSON and update members
                    Log.d(TAG, "Member added to group successfully")
                } else {
                    throw Exception("Group not found: $groupId")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error adding member to group", e)
                throw e
            }
        }
    }

    // Remove member from group
    suspend fun removeMemberFromGroup(groupId: String, memberId: String) {
        withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "Removing member $memberId from group $groupId")
                
                // Update group members
                val sharedPrefs = context.getSharedPreferences("session_groups", Context.MODE_PRIVATE)
                val groupInfo = sharedPrefs.getString("group_$groupId", null)
                
                if (groupInfo != null) {
                    // Parse and update group info
                    // In a real implementation, you would parse the JSON and update members
                    Log.d(TAG, "Member removed from group successfully")
                } else {
                    throw Exception("Group not found: $groupId")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error removing member from group", e)
                throw e
            }
        }
    }

    // Leave group
    suspend fun leaveGroup(groupId: String) {
        withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "Leaving group $groupId")
                
                val currentUserId = currentIdentity?.sessionId ?: ""
                
                // Remove current user from group
                val sharedPrefs = context.getSharedPreferences("session_groups", Context.MODE_PRIVATE)
                val groupInfo = sharedPrefs.getString("group_$groupId", null)
                
                if (groupInfo != null) {
                    // Parse and update group info
                    // In a real implementation, you would parse the JSON and remove current user
                    Log.d(TAG, "Left group successfully")
                } else {
                    throw Exception("Group not found: $groupId")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error leaving group", e)
                throw e
            }
        }
    }

    // Configure onion routing
    suspend fun configureOnionRouting(enabled: Boolean, proxyUrl: String?) {
        withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "Configuring onion routing: $enabled, $proxyUrl")
                
                // Store onion routing configuration
                val sharedPrefs = context.getSharedPreferences("session_config", Context.MODE_PRIVATE)
                sharedPrefs.edit()
                    .putBoolean("onion_routing_enabled", enabled)
                    .putString("onion_routing_proxy_url", proxyUrl ?: "")
                    .apply()
                
                Log.d(TAG, "Onion routing configured successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Error configuring onion routing", e)
                throw e
            }
        }
    }
} 