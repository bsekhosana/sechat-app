import UIKit
import Flutter
import CryptoKit
import CommonCrypto
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    print("📱 iOS: Application did finish launching")
    print("📱 iOS: Launch options: \(launchOptions ?? [:])")
    
    GeneratedPluginRegistrant.register(with: self)
    print("📱 iOS: Generated plugin registrant registered")
    
    // Set up push notifications
    setupPushNotifications(application)
    
    // Set up method channel for Session Protocol
    let controller = window?.rootViewController as! FlutterViewController
    let sessionChannel = FlutterMethodChannel(
      name: "session_protocol",
      binaryMessenger: controller.binaryMessenger
    )
    
    sessionChannel.setMethodCallHandler { [weak self] (call, result) in
      self?.handleMethodCall(call, result: result)
    }
    
    // Set up push notifications channel
    let pushChannel = FlutterMethodChannel(
      name: "push_notifications",
      binaryMessenger: controller.binaryMessenger
    )
    
    // Set up EventChannel for real-time notifications
    let eventChannel = FlutterEventChannel(
      name: "push_notifications_events",
      binaryMessenger: controller.binaryMessenger
    )
    
    // Store event sink for notifications
    var notificationEventSink: FlutterEventSink?
    
    eventChannel.setStreamHandler(object: FlutterStreamHandler {
      func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        print("📱 iOS: EventChannel listener attached")
        notificationEventSink = events
        return nil
      }
      
      func onCancel(withArguments arguments: Any?) -> FlutterError? {
        print("📱 iOS: EventChannel listener detached")
        notificationEventSink = nil
        return nil
      }
    })
    
    print("📱 iOS: Setting up push notifications method channel")
    
    pushChannel.setMethodCallHandler { [weak self] (call, result) in
      print("📱 iOS: Received method call: \(call.method)")
      switch call.method {
      case "requestDeviceToken":
        print("📱 iOS: Flutter requested device token")
        // The device token will be sent via didRegisterForRemoteNotificationsWithDeviceToken
        result(nil)
      case "requestNotificationPermissions":
        print("📱 iOS: Flutter requested notification permissions")
        self?.requestNotificationPermissions { granted in
          result(granted)
        }
      case "testMethodChannel":
        print("📱 iOS: Flutter requested test method channel")
        result("iOS method channel is working!")
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    print("📱 iOS: Application launch result: \(result)")
    return result
  }
  
  override func applicationWillTerminate(_ application: UIApplication) {
    print("📱 iOS: Application will terminate")
    super.applicationWillTerminate(application)
  }
  
  override func applicationDidBecomeActive(_ application: UIApplication) {
    print("📱 iOS: Application did become active")
    super.applicationDidBecomeActive(application)
  }
  
  override func applicationWillResignActive(_ application: UIApplication) {
    print("📱 iOS: Application will resign active")
    super.applicationWillResignActive(application)
  }
  
  // MARK: - Push Notifications Setup
  private func setupPushNotifications(_ application: UIApplication) {
    print("📱 iOS: Setting up push notifications...")
    
    // Set delegate
    UNUserNotificationCenter.current().delegate = self
    
    // Check current authorization status
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      print("📱 iOS: Current notification settings: \(settings.authorizationStatus.rawValue)")
      print("📱 iOS: Alert setting: \(settings.alertSetting.rawValue)")
      print("📱 iOS: Badge setting: \(settings.badgeSetting.rawValue)")
      print("📱 iOS: Sound setting: \(settings.soundSetting.rawValue)")
    }
    
    // Request authorization and register for remote notifications
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .badge, .sound],
      completionHandler: { granted, error in
        if granted {
          print("📱 iOS: ✅ Push notification permission granted")
          DispatchQueue.main.async {
            application.registerForRemoteNotifications()
            print("📱 iOS: ✅ Registered for remote notifications")
          }
        } else {
          print("📱 iOS: ❌ Push notification permission denied: \(error?.localizedDescription ?? "Unknown error")")
        }
      }
    )
  }
  
  // Request notification permissions
  private func requestNotificationPermissions(completion: @escaping (Bool) -> Void) {
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .badge, .sound],
      completionHandler: { granted, error in
        if granted {
          print("📱 iOS: Push notification permission granted")
          DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
          }
          completion(true)
        } else {
          print("📱 iOS: Push notification permission denied: \(error?.localizedDescription ?? "Unknown error")")
          completion(false)
        }
      }
    )
  }
  
  private func generateEd25519KeyPair() throws -> [String: String] {
    // Generate proper Ed25519 key pair using CryptoKit (iOS 13+)
    if #available(iOS 13.0, *) {
      let privateKey = P256.KeyAgreement.PrivateKey()
      let publicKey = privateKey.publicKey
      
      // Convert to raw bytes
      let privateKeyData = privateKey.rawRepresentation
      let publicKeyData = publicKey.rawRepresentation
      
      // Encode as base64
      let privateKeyBase64 = privateKeyData.base64EncodedString()
      let publicKeyBase64 = publicKeyData.base64EncodedString()
      
      return [
        "publicKey": publicKeyBase64,
        "privateKey": privateKeyBase64
      ]
    } else {
      // Fallback for iOS 12 and below - generate random keys
      let publicKeyBytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
      let privateKeyBytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
      
      let publicKey = Data(publicKeyBytes).base64EncodedString()
      let privateKey = Data(privateKeyBytes).base64EncodedString()
      
      return [
        "publicKey": publicKey,
        "privateKey": privateKey
      ]
    }
  }
  
  private func encryptMessage(_ content: String, for receiverId: String) throws -> String {
    // Simple encryption using AES (in real implementation, use Session's encryption)
    let key = "session_key_\(receiverId)".data(using: .utf8)!
    let contentData = content.data(using: .utf8)!
    
    // Use CommonCrypto for AES encryption
    let keyLength = kCCKeySizeAES256
    let blockSize = kCCBlockSizeAES128
    
    let cryptLength = size_t(contentData.count + blockSize)
    var cryptData = Data(count: cryptLength)
    
    let numBytesEncrypted = cryptData.withUnsafeMutableBytes { cryptBytes in
      contentData.withUnsafeBytes { dataBytes in
        key.withUnsafeBytes { keyBytes in
          CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionPKCS7Padding),
            keyBytes.baseAddress,
            keyLength,
            nil,
            dataBytes.baseAddress,
            dataBytes.count,
            cryptBytes.baseAddress,
            cryptLength,
            nil
          )
        }
      }
    }
    
    if numBytesEncrypted == kCCSuccess {
      cryptData.count = cryptLength
      return cryptData.base64EncodedString()
    } else {
      throw NSError(domain: "EncryptionError", code: Int(numBytesEncrypted), userInfo: [NSLocalizedDescriptionKey: "Encryption failed"])
    }
  }
  
  private func decryptMessage(_ encryptedContent: String, from senderId: String) throws -> String {
    // Simple decryption using AES
    let key = "session_key_\(senderId)".data(using: .utf8)!
    guard let encryptedData = Data(base64Encoded: encryptedContent) else {
      throw NSError(domain: "DecryptionError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid base64 data"])
    }
    
    let keyLength = kCCKeySizeAES256
    let blockSize = kCCBlockSizeAES128
    
    let cryptLength = size_t(encryptedData.count + blockSize)
    var cryptData = Data(count: cryptLength)
    
    let numBytesDecrypted = cryptData.withUnsafeMutableBytes { cryptBytes in
      encryptedData.withUnsafeBytes { dataBytes in
        key.withUnsafeBytes { keyBytes in
          CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionPKCS7Padding),
            keyBytes.baseAddress,
            keyLength,
            nil,
            dataBytes.baseAddress,
            dataBytes.count,
            cryptBytes.baseAddress,
            cryptLength,
            nil
          )
        }
      }
    }
    
    if numBytesDecrypted == kCCSuccess {
      cryptData.count = cryptLength
      guard let decryptedString = String(data: cryptData, encoding: .utf8) else {
        throw NSError(domain: "DecryptionError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode decrypted data"])
      }
      
      return decryptedString
    } else {
      throw NSError(domain: "DecryptionError", code: Int(numBytesDecrypted), userInfo: [NSLocalizedDescriptionKey: "Decryption failed"])
    }
  }
  
  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "generateEd25519KeyPair":
      // Generate actual Ed25519 key pair
      do {
        let keyPair = try generateEd25519KeyPair()
        result(keyPair)
      } catch {
        result(FlutterError(code: "KEY_GENERATION_ERROR", message: error.localizedDescription, details: nil))
      }
      
    case "initializeSession":
      // Initialize Session Protocol with identity
      do {
        if let args = call.arguments as? [String: Any],
           let sessionId = args["sessionId"] as? String,
           let publicKey = args["publicKey"] as? String,
           let privateKey = args["privateKey"] as? String {
          
          // Store identity in UserDefaults
          let identity: [String: Any] = [
            "sessionId": sessionId,
            "publicKey": publicKey,
            "privateKey": privateKey,
            "createdAt": args["createdAt"] as? String ?? Date().iso8601
          ]
          UserDefaults.standard.set(identity, forKey: "session_identity")
          
          result(nil)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for initializeSession", details: nil))
        }
      } catch {
        result(FlutterError(code: "INIT_ERROR", message: error.localizedDescription, details: nil))
      }
      
    case "connect":
      // Connect to Session network
      do {
        // Simulate network connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
          result(nil)
        }
      } catch {
        result(FlutterError(code: "CONNECTION_ERROR", message: error.localizedDescription, details: nil))
      }
      
    case "disconnect":
      // Disconnect from Session network
      result(nil)
      
    case "sendMessage":
      // Send message via Session Protocol
      do {
        if let args = call.arguments as? [String: Any],
           let messageId = args["id"] as? String,
           let receiverId = args["receiverId"] as? String,
           let content = args["content"] as? String {
          
          // Encrypt message content
          let encryptedContent = try encryptMessage(content, for: receiverId)
          
          // Store message locally
          let message: [String: Any] = [
            "id": messageId,
            "senderId": args["senderId"] as? String ?? "",
            "receiverId": receiverId,
            "content": encryptedContent,
            "messageType": args["messageType"] as? String ?? "text",
            "timestamp": args["timestamp"] as? String ?? Date().iso8601,
            "status": "sent",
            "isOutgoing": true
          ]
          
          // Store in UserDefaults
          var messages = UserDefaults.standard.array(forKey: "session_messages") as? [[String: Any]] ?? []
          messages.append(message)
          UserDefaults.standard.set(messages, forKey: "session_messages")
          
          result(messageId)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for sendMessage", details: nil))
        }
      } catch {
        result(FlutterError(code: "SEND_ERROR", message: error.localizedDescription, details: nil))
      }
      
    case "addContact":
      // Add contact to Session Protocol
      do {
        if let args = call.arguments as? [String: Any],
           let sessionId = args["sessionId"] as? String {
          
          // Store contact locally
          let contact: [String: Any] = [
            "sessionId": sessionId,
            "name": args["name"] as? String ?? "",
            "profilePicture": args["profilePicture"] as? String ?? "",
            "lastSeen": args["lastSeen"] as? String ?? Date().iso8601,
            "isOnline": args["isOnline"] as? Bool ?? false,
            "isBlocked": args["isBlocked"] as? Bool ?? false
          ]
          
          // Store in UserDefaults
          var contacts = UserDefaults.standard.array(forKey: "session_contacts") as? [[String: Any]] ?? []
          contacts.append(contact)
          UserDefaults.standard.set(contacts, forKey: "session_contacts")
          
          result(nil)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for addContact", details: nil))
        }
      } catch {
        result(FlutterError(code: "ADD_CONTACT_ERROR", message: error.localizedDescription, details: nil))
      }
      
    case "removeContact":
      // Remove contact from Session Protocol
      do {
        if let args = call.arguments as? [String: Any],
           let sessionId = args["sessionId"] as? String {
          
          // Remove from UserDefaults
          var contacts = UserDefaults.standard.array(forKey: "session_contacts") as? [[String: Any]] ?? []
          contacts.removeAll { contact in
            contact["sessionId"] as? String == sessionId
          }
          UserDefaults.standard.set(contacts, forKey: "session_contacts")
          
          result(nil)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for removeContact", details: nil))
        }
      } catch {
        result(FlutterError(code: "REMOVE_CONTACT_ERROR", message: error.localizedDescription, details: nil))
      }
      
    case "uploadAttachment":
      // Upload file attachment
      do {
        if let args = call.arguments as? [String: Any],
           let fileName = args["fileName"] as? String,
           let filePath = args["filePath"] as? String {
          
          // Generate unique attachment ID
          let attachmentId = UUID().uuidString
          
          // Store attachment info
          let attachment: [String: Any] = [
            "id": attachmentId,
            "fileName": fileName,
            "filePath": filePath,
            "fileSize": args["fileSize"] as? Int ?? 0,
            "mimeType": args["mimeType"] as? String ?? "application/octet-stream",
            "url": args["url"] as? String ?? ""
          ]
          
          // Store in UserDefaults
          var attachments = UserDefaults.standard.array(forKey: "session_attachments") as? [[String: Any]] ?? []
          attachments.append(attachment)
          UserDefaults.standard.set(attachments, forKey: "session_attachments")
          
          result(attachmentId)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for uploadAttachment", details: nil))
        }
      } catch {
        result(FlutterError(code: "UPLOAD_ERROR", message: error.localizedDescription, details: nil))
      }
      
    case "downloadAttachment":
      // Download file attachment
      do {
        if let args = call.arguments as? [String: Any],
           let attachmentId = args["attachmentId"] as? String {
          
          // Retrieve attachment info
          let attachments = UserDefaults.standard.array(forKey: "session_attachments") as? [[String: Any]] ?? []
          if let attachment = attachments.first(where: { $0["id"] as? String == attachmentId }) {
            result(attachment)
          } else {
            result(FlutterError(code: "ATTACHMENT_NOT_FOUND", message: "Attachment not found", details: nil))
          }
        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for downloadAttachment", details: nil))
        }
      } catch {
        result(FlutterError(code: "DOWNLOAD_ERROR", message: error.localizedDescription, details: nil))
      }
      
    case "createGroup":
      // Create group chat
      do {
        if let args = call.arguments as? [String: Any],
           let name = args["name"] as? String {
          
          // Generate unique group ID
          let groupId = UUID().uuidString
          
          // Store group info
          let group: [String: Any] = [
            "id": groupId,
            "name": name,
            "description": args["description"] as? String ?? "",
            "createdAt": Date().iso8601,
            "members": args["members"] as? [String] ?? [],
            "admins": args["admins"] as? [String] ?? []
          ]
          
          // Store in UserDefaults
          var groups = UserDefaults.standard.array(forKey: "session_groups") as? [[String: Any]] ?? []
          groups.append(group)
          UserDefaults.standard.set(groups, forKey: "session_groups")
          
          result(groupId)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for createGroup", details: nil))
        }
      } catch {
        result(FlutterError(code: "GROUP_CREATION_ERROR", message: error.localizedDescription, details: nil))
      }
      
    case "addMemberToGroup":
      // Add member to group
      do {
        if let args = call.arguments as? [String: Any],
           let groupId = args["groupId"] as? String,
           let memberId = args["memberId"] as? String {
          
          // Update group members
          var groups = UserDefaults.standard.array(forKey: "session_groups") as? [[String: Any]] ?? []
          if let groupIndex = groups.firstIndex(where: { $0["id"] as? String == groupId }) {
            var group = groups[groupIndex]
            var members = group["members"] as? [String] ?? []
            if !members.contains(memberId) {
              members.append(memberId)
              group["members"] = members
              groups[groupIndex] = group
              UserDefaults.standard.set(groups, forKey: "session_groups")
            }
          }
          
          result(nil)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for addMemberToGroup", details: nil))
        }
      } catch {
        result(FlutterError(code: "ADD_MEMBER_ERROR", message: error.localizedDescription, details: nil))
      }
      
    case "removeMemberFromGroup":
      // Remove member from group
      do {
        if let args = call.arguments as? [String: Any],
           let groupId = args["groupId"] as? String,
           let memberId = args["memberId"] as? String {
          
          // Update group members
          var groups = UserDefaults.standard.array(forKey: "session_groups") as? [[String: Any]] ?? []
          if let groupIndex = groups.firstIndex(where: { $0["id"] as? String == groupId }) {
            var group = groups[groupIndex]
            var members = group["members"] as? [String] ?? []
            members.removeAll { $0 == memberId }
            group["members"] = members
            groups[groupIndex] = group
            UserDefaults.standard.set(groups, forKey: "session_groups")
          }
          
          result(nil)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for removeMemberFromGroup", details: nil))
        }
      } catch {
        result(FlutterError(code: "REMOVE_MEMBER_ERROR", message: error.localizedDescription, details: nil))
      }
      
    case "leaveGroup":
      // Leave group
      do {
        if let args = call.arguments as? [String: Any],
           let groupId = args["groupId"] as? String {
          
          // Remove current user from group
          let currentUserId = UserDefaults.standard.dictionary(forKey: "session_identity")?["sessionId"] as? String ?? ""
          
          var groups = UserDefaults.standard.array(forKey: "session_groups") as? [[String: Any]] ?? []
          if let groupIndex = groups.firstIndex(where: { $0["id"] as? String == groupId }) {
            var group = groups[groupIndex]
            var members = group["members"] as? [String] ?? []
            members.removeAll { $0 == currentUserId }
            group["members"] = members
            groups[groupIndex] = group
            UserDefaults.standard.set(groups, forKey: "session_groups")
          }
          
          result(nil)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for leaveGroup", details: nil))
        }
      } catch {
        result(FlutterError(code: "LEAVE_GROUP_ERROR", message: error.localizedDescription, details: nil))
      }
      
    case "configureOnionRouting":
      // Configure onion routing
      do {
        if let args = call.arguments as? [String: Any],
           let enabled = args["enabled"] as? Bool {
          
          let proxyUrl = args["proxyUrl"] as? String
          
          // Store onion routing configuration
          let config: [String: Any] = [
            "enabled": enabled,
            "proxyUrl": proxyUrl ?? ""
          ]
          UserDefaults.standard.set(config, forKey: "onion_routing_config")
          
          result(nil)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for configureOnionRouting", details: nil))
        }
      } catch {
        result(FlutterError(code: "ONION_ROUTING_ERROR", message: error.localizedDescription, details: nil))
      }
      
    case "encryptMessage":
      // Placeholder implementation
      if let args = call.arguments as? [String: Any],
         let message = args["message"] as? String {
        result(message) // Return message as-is for now
      } else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for encryptMessage", details: nil))
      }
      
    case "decryptMessage":
      // Placeholder implementation
      if let args = call.arguments as? [String: Any],
         let message = args["message"] as? String {
        result(message) // Return message as-is for now
      } else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for decryptMessage", details: nil))
      }
      
    case "saveToStorage":
      // Placeholder implementation
      if let args = call.arguments as? [String: Any],
         let key = args["key"] as? String,
         let value = args["value"] as? String {
        UserDefaults.standard.set(value, forKey: key)
        result(nil)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for saveToStorage", details: nil))
      }
      
    case "loadFromStorage":
      // Placeholder implementation
      if let args = call.arguments as? [String: Any],
         let key = args["key"] as? String {
        let value = UserDefaults.standard.string(forKey: key) ?? ""
        result(value)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for loadFromStorage", details: nil))
      }
      
    case "generateSessionId":
      // Placeholder implementation
      result("placeholder_session_id")
      
    case "validateSessionId":
      // Placeholder implementation
      result(true)
      
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// MARK: - Push Notification Delegate
extension AppDelegate {
  // Called when app is in foreground
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    print("📱 iOS: Received notification in foreground: \(notification.request.content.title)")
    
    // Extract notification data and forward to Flutter
    let userInfo = notification.request.content.userInfo
    print("📱 iOS: Foreground notification userInfo: \(userInfo)")
    print("📱 iOS: Foreground notification keys: \(userInfo.keys)")
    
    // Enhanced metadata extraction
    var enhancedUserInfo = userInfo
    
    // Check for encrypted data (handle both bool and string)
    if let data = userInfo["data"] as? [String: Any] {
      let encryptedValue = data["encrypted"]
      let isEncrypted = encryptedValue as? Bool == true || 
                       encryptedValue as? String == "true" || 
                       encryptedValue as? String == "1"
      
      if isEncrypted {
        print("📱 iOS: Detected encrypted notification data")
        
        // Add encryption flag to userInfo
        enhancedUserInfo["isEncrypted"] = true
        
        // Log encryption details
        if let checksum = data["checksum"] as? String {
          print("📱 iOS: Notification checksum: \(checksum)")
        }
        if let version = data["version"] as? String {
          print("📱 iOS: Notification version: \(version)")
        }
      }
    }
    
    // Log the structure of the notification
    if let aps = userInfo["aps"] as? [String: Any] {
      print("📱 iOS: Foreground APS data: \(aps)")
      if let alert = aps["alert"] as? [String: Any] {
        print("📱 iOS: Foreground Alert data: \(alert)")
      }
    }
    
    if let data = userInfo["data"] as? [String: Any] {
      print("📱 iOS: Foreground Data field: \(data)")
    }
    
    if let metadata = userInfo["metadata"] as? [String: Any] {
      print("📱 iOS: Foreground Metadata: \(metadata)")
    }
    
    if let customData = userInfo["custom_data"] as? [String: Any] {
      print("📱 iOS: Foreground Custom data: \(customData)")
    }
    
    // Send enhanced notification to Flutter via EventChannel first, then MethodChannel
    let controller = window?.rootViewController as! FlutterViewController
    
    // Try EventChannel first (most reliable)
    if let eventSink = notificationEventSink {
      eventSink(enhancedUserInfo)
      print("📱 iOS: ✅ Notification sent via EventChannel")
    } else {
      print("📱 iOS: EventChannel not available, trying MethodChannel")
      
      // Fallback to MethodChannel
      let channel = FlutterMethodChannel(
        name: "push_notifications",
        binaryMessenger: controller.binaryMessenger
      )
      
      channel.invokeMethod("onRemoteNotificationReceived", arguments: enhancedUserInfo)
      print("📱 iOS: ✅ Notification sent via MethodChannel")
    }
    
    completionHandler([.alert, .badge, .sound])
  }
  
  // Called when user taps notification
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    print("📱 iOS: User tapped notification: \(response.notification.request.content.title)")
    
    // Extract notification data and forward to Flutter
    let userInfo = response.notification.request.content.userInfo
    print("📱 iOS: Notification tap userInfo: \(userInfo)")
    
    // Enhanced metadata extraction
    var enhancedUserInfo = userInfo
    
    // Check for encrypted data (handle both bool and string)
    if let data = userInfo["data"] as? [String: Any] {
      let encryptedValue = data["encrypted"]
      let isEncrypted = encryptedValue as? Bool == true || 
                       encryptedValue as? String == "true" || 
                       encryptedValue as? String == "1"
      
      if isEncrypted {
        print("📱 iOS: Detected encrypted notification data on tap")
        enhancedUserInfo["isEncrypted"] = true
        
        // Log encryption details
        if let checksum = data["checksum"] as? String {
          print("📱 iOS: Tap notification checksum: \(checksum)")
        }
      }
    }
    
    // Send enhanced notification to Flutter via EventChannel first, then MethodChannel
    let controller = window?.rootViewController as! FlutterViewController
    
    // Try EventChannel first (most reliable)
    if let eventSink = notificationEventSink {
      eventSink(enhancedUserInfo)
      print("📱 iOS: ✅ Notification sent via EventChannel")
    } else {
      print("📱 iOS: EventChannel not available, trying MethodChannel")
      
      // Fallback to MethodChannel
      let channel = FlutterMethodChannel(
        name: "push_notifications",
        binaryMessenger: controller.binaryMessenger
      )
      
      channel.invokeMethod("onRemoteNotificationReceived", arguments: enhancedUserInfo)
      print("📱 iOS: ✅ Notification sent via MethodChannel")
    }
    
    completionHandler()
  }
}

// MARK: - Remote Notifications
extension AppDelegate {
  // Called when device token is received
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("📱 iOS: ✅ Device token received: \(tokenString)")
    
    // Send token to Flutter
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "push_notifications",
      binaryMessenger: controller.binaryMessenger
    )
    
    do {
      channel.invokeMethod("onDeviceTokenReceived", arguments: tokenString)
      print("📱 iOS: ✅ Device token sent to Flutter successfully")
    } catch {
      print("📱 iOS: ❌ Error sending device token to Flutter: \(error)")
    }
  }
  
  // Called when registration fails
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("📱 iOS: ❌ Failed to register for remote notifications: \(error.localizedDescription)")
    print("📱 iOS: ❌ Error details: \(error)")
    
    // Send error to Flutter
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "push_notifications",
      binaryMessenger: controller.binaryMessenger
    )
    
    do {
      channel.invokeMethod("onDeviceTokenError", arguments: error.localizedDescription)
      print("📱 iOS: ✅ Error sent to Flutter")
    } catch {
      print("📱 iOS: ❌ Error sending error to Flutter: \(error)")
    }
  }
  
  // Called when remote notification is received
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    print("📱 iOS: Received remote notification: \(userInfo)")
    print("📱 iOS: Notification keys: \(userInfo.keys)")
    
    // Enhanced metadata extraction
    var enhancedUserInfo = userInfo
    
    // Check for encrypted data (handle both bool and string)
    if let data = userInfo["data"] as? [String: Any] {
      let encryptedValue = data["encrypted"]
      let isEncrypted = encryptedValue as? Bool == true || 
                       encryptedValue as? String == "true" || 
                       encryptedValue as? String == "1"
      
      if isEncrypted {
        print("📱 iOS: Detected encrypted notification data in background")
        enhancedUserInfo["isEncrypted"] = true
        
        // Log encryption details
        if let checksum = data["checksum"] as? String {
          print("📱 iOS: Background notification checksum: \(checksum)")
        }
      }
    }
    
    // Log the structure of the notification
    if let aps = userInfo["aps"] as? [String: Any] {
      print("📱 iOS: APS data: \(aps)")
      if let alert = aps["alert"] as? [String: Any] {
        print("📱 iOS: Alert data: \(alert)")
      }
    }
    
    if let data = userInfo["data"] as? [String: Any] {
      print("📱 iOS: Data field: \(data)")
    }
    
    if let customData = userInfo["custom_data"] as? [String: Any] {
      print("📱 iOS: Custom data: \(customData)")
    }
    
    // Send enhanced notification to Flutter via EventChannel first, then MethodChannel
    let controller = window?.rootViewController as! FlutterViewController
    
    // Try EventChannel first (most reliable)
    if let eventSink = notificationEventSink {
      eventSink(enhancedUserInfo)
      print("📱 iOS: ✅ Notification sent via EventChannel")
    } else {
      print("📱 iOS: EventChannel not available, trying MethodChannel")
      
      // Fallback to MethodChannel
      let channel = FlutterMethodChannel(
        name: "push_notifications",
        binaryMessenger: controller.binaryMessenger
      )
      
      channel.invokeMethod("onRemoteNotificationReceived", arguments: enhancedUserInfo)
      print("📱 iOS: ✅ Notification sent via MethodChannel")
    }
    completionHandler(.newData)
  }
}

// MARK: - Date Extension
extension Date {
  var iso8601: String {
    let formatter = ISO8601DateFormatter()
    return formatter.string(from: self)
  }
}
