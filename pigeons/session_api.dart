import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/core/generated/session_api.g.dart',
  dartOptions: DartOptions(copyrightHeader: []),
  javaOut: 'android/app/src/main/java/com/strapblaque/sechat/SessionApi.java',
  javaOptions: JavaOptions(package: 'com.strapblaque.sechat'),
  objcHeaderOut: 'ios/Runner/SessionApi.h',
  objcSourceOut: 'ios/Runner/SessionApi.m',
  objcOptions: ObjcOptions(prefix: ''),
))

// Data classes for better type safety
class SessionIdentity {
  String? publicKey;
  String? privateKey;
  String? sessionId;
  String? createdAt;
}

class SessionMessage {
  String? id;
  String? senderId;
  String? receiverId;
  String? content;
  String? messageType;
  String? timestamp;
  String? status;
  bool? isOutgoing;
}

class SessionContact {
  String? sessionId;
  String? name;
  String? profilePicture;
  String? lastSeen;
  bool? isOnline;
  bool? isBlocked;
}

class SessionGroup {
  String? groupId;
  String? name;
  String? description;
  String? avatar;
  List<String?>? members;
  String? adminId;
  String? createdAt;
}

class SessionAttachment {
  String? id;
  String? fileName;
  String? filePath;
  int? fileSize;
  String? mimeType;
  String? url;
}

// Session Protocol API
@HostApi()
abstract class SessionApiHandler {
  // Identity Management
  @async
  Map<String, String> generateEd25519KeyPair();

  @async
  void initializeSession(SessionIdentity identity);

  // Network Operations
  @async
  void connect();

  @async
  void disconnect();

  // Messaging
  @async
  void sendMessage(SessionMessage message);

  @async
  void sendTypingIndicator(String sessionId, bool isTyping);

  // Contact Management
  @async
  void addContact(SessionContact contact);

  @async
  void removeContact(String sessionId);

  @async
  void updateContact(SessionContact contact);

  // Group Operations
  @async
  String createGroup(SessionGroup group);

  @async
  void addMemberToGroup(String groupId, String memberId);

  @async
  void removeMemberFromGroup(String groupId, String memberId);

  @async
  void leaveGroup(String groupId);

  // File Operations
  @async
  String uploadAttachment(SessionAttachment attachment);

  @async
  SessionAttachment downloadAttachment(String attachmentId);

  // Encryption
  @async
  String encryptMessage(String message, String recipientId);

  @async
  String decryptMessage(String encryptedMessage, String senderId);

  // Onion Routing
  @async
  void configureOnionRouting(bool enabled, String? proxyUrl);

  // Storage
  @async
  void saveToStorage(String key, String value);

  @async
  String loadFromStorage(String key);

  // Utilities
  @async
  String generateSessionId(String publicKey);

  @async
  bool validateSessionId(String sessionId);
}

// Flutter to Native callbacks
@FlutterApi()
abstract class SessionCallbackApi {
  void onMessageReceived(SessionMessage message);

  void onContactAdded(SessionContact contact);

  void onContactUpdated(SessionContact contact);

  void onContactRemoved(String sessionId);

  void onTypingReceived(String sessionId);

  void onTypingStopped(String sessionId);

  void onMessageStatusUpdated(String messageId);

  void onConnected();

  void onDisconnected();

  void onError(String error);

  void onGroupCreated(String groupId);

  void onGroupUpdated(SessionGroup group);

  void onGroupDeleted(String groupId);

  void onMemberAdded(String groupId, String memberId);

  void onMemberRemoved(String groupId, String memberId);

  void onAttachmentUploaded(SessionAttachment attachment);

  void onAttachmentDownloaded(SessionAttachment attachment);
}
