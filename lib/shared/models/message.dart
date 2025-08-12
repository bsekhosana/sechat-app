import 'package:flutter/material.dart';

enum MessageType { text, image, voice, file }

/// Status for WhatsApp-style message delivery/read handshake
enum MessageStatus {
  pending, // Message waiting to be sent (local only, not yet sent)
  sending, // Message is being sent
  sent, // Step 1: Message sent to server (1 tick)
  delivered, // Step 2: Message delivered to recipient's device (2 ticks)
  read, // Step 3: Message read by recipient (2 blue ticks)
  error // Error occurred during sending
}

class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String content;
  final MessageType type;
  final String
      status; // Status string representation for backward compatibility
  final MessageStatus? messageStatus; // New enum status
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? localFilePath; // For images, voice, files
  final String? fileName; // Original file name
  final int? fileSize; // File size in bytes
  final bool isPending; // For offline messages
  final bool isDeleted; // For deleted messages
  final String? deleteType; // 'for_me' or 'for_everyone'
  final String? encryptionInfo; // Information about the encryption
  final DateTime? deliveredAt; // When the message was delivered
  final DateTime? readAt; // When the message was read
  final bool isEncrypted; // Whether the message is encrypted
  final String? encryptionVersion; // Version of encryption used

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.content,
    this.type = MessageType.text,
    this.status = 'sent',
    this.messageStatus, // New enum status
    required this.createdAt,
    required this.updatedAt,
    this.localFilePath,
    this.fileName,
    this.fileSize,
    this.isPending = false,
    this.isDeleted = false,
    this.deleteType,
    this.encryptionInfo,
    this.deliveredAt,
    this.readAt,
    this.isEncrypted = true, // Default to true for new messages
    this.encryptionVersion,
  });

  factory Message.fromJson(dynamic json) {
    try {
      // Convert LinkedMap to Map<String, dynamic> if needed
      final Map<String, dynamic> data = Map<String, dynamic>.from(json);

      // Parse status string to enum
      final statusStr = data['status'] as String? ?? 'sent';
      final messageStatus = _parseStatusString(statusStr);

      return Message(
        id: data['id']?.toString() ?? '',
        chatId: data['chat_id']?.toString() ?? '',
        senderId: data['sender_id']?.toString() ?? '',
        content: data['content'] ?? '',
        type: MessageType.values.firstWhere(
          (e) => e.toString().split('.').last == (data['type'] ?? 'text'),
          orElse: () => MessageType.text,
        ),
        status: statusStr,
        messageStatus: messageStatus,
        createdAt: data['created_at'] != null
            ? DateTime.parse(data['created_at'])
            : DateTime.now(),
        updatedAt: data['updated_at'] != null
            ? DateTime.parse(data['updated_at'])
            : DateTime.now(),
        localFilePath: data['local_file_path'],
        fileName: data['file_name'],
        fileSize: data['file_size'],
        isPending: data['is_pending'] ?? false,
        isDeleted: data['is_deleted'] ?? false,
        deleteType: data['delete_type'],
        encryptionInfo: data['encryption_info'],
        deliveredAt: data['delivered_at'] != null
            ? DateTime.parse(data['delivered_at'])
            : null,
        readAt:
            data['read_at'] != null ? DateTime.parse(data['read_at']) : null,
        isEncrypted: data['is_encrypted'] ?? true,
        encryptionVersion: data['encryption_version'],
      );
    } catch (e) {
      print('📱 Message.fromJson error: $e for data: $json');
      // Return a default message with available data
      return Message(
        id: json['id']?.toString() ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        chatId: json['chat_id']?.toString() ?? '',
        senderId: json['sender_id']?.toString() ?? '',
        content: json['content'] ?? 'Error loading message',
        type: MessageType.text,
        status: 'error',
        messageStatus: MessageStatus.error,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isEncrypted: false, // Default error messages as unencrypted
      );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chat_id': chatId,
      'sender_id': senderId,
      'content': content,
      'type': type.toString().split('.').last,
      'status': status,
      'message_status': messageStatus?.toString().split('.').last,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'local_file_path': localFilePath,
      'file_name': fileName,
      'file_size': fileSize,
      'is_pending': isPending,
      'is_deleted': isDeleted,
      'delete_type': deleteType,
      'encryption_info': encryptionInfo,
      'delivered_at': deliveredAt?.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
      'is_encrypted': isEncrypted,
      'encryption_version': encryptionVersion,
    };
  }

  // Convert a status string to enum
  static MessageStatus _parseStatusString(String status) {
    switch (status) {
      case 'pending':
        return MessageStatus.pending;
      case 'sending':
        return MessageStatus.sending;
      case 'sent':
        return MessageStatus.sent;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      case 'error':
        return MessageStatus.error;
      default:
        return MessageStatus.sent; // Default to sent for backward compatibility
    }
  }

  // Status getters for message indicators
  bool get isSending =>
      status == 'sending' || messageStatus == MessageStatus.sending;
  bool get isSent => status == 'sent' || messageStatus == MessageStatus.sent;
  bool get isDelivered =>
      status == 'delivered' || messageStatus == MessageStatus.delivered;
  bool get isRead => status == 'read' || messageStatus == MessageStatus.read;
  bool get isError => status == 'error' || messageStatus == MessageStatus.error;
  bool get isPendingStatus =>
      status == 'pending' || messageStatus == MessageStatus.pending;

  // Get the appropriate icon for message status (WhatsApp-style)
  IconData get statusIcon {
    if (isError) return Icons.error;
    if (isRead) return Icons.done_all; // 2 blue ticks - handled by color
    if (isDelivered) return Icons.done_all; // 2 ticks
    if (isSent) return Icons.done; // 1 tick
    if (isSending) return Icons.access_time;
    return Icons.schedule; // For pending
  }

  // Get the appropriate color for message status
  Color getStatusColor(Color baseColor) {
    if (isError) return Colors.red;
    if (isRead) return Colors.blue; // Blue ticks for read messages
    if (isDelivered) return baseColor;
    if (isPendingStatus) return Colors.orange;
    if (isSending) return Colors.orange;
    return baseColor.withOpacity(0.5);
  }

  // Check if message is a file type
  bool get isFile =>
      type == MessageType.image ||
      type == MessageType.voice ||
      type == MessageType.file;

  // Check if message has a local file
  bool get hasLocalFile => localFilePath != null && localFilePath!.isNotEmpty;

  // Get file size in human readable format
  String get fileSizeFormatted {
    if (fileSize == null) return '';

    if (fileSize! < 1024) {
      return '${fileSize!} B';
    } else if (fileSize! < 1024 * 1024) {
      return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  // Get the handshake step (1, 2, or 3)
  int get handshakeStep {
    if (isRead) return 3;
    if (isDelivered) return 2;
    if (isSent) return 1;
    return 0; // Not in handshake yet
  }

  Message copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? content,
    MessageType? type,
    String? status,
    MessageStatus? messageStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? localFilePath,
    String? fileName,
    int? fileSize,
    bool? isPending,
    bool? isDeleted,
    String? deleteType,
    String? encryptionInfo,
    DateTime? deliveredAt,
    DateTime? readAt,
    bool? isEncrypted,
    String? encryptionVersion,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      type: type ?? this.type,
      status: status ?? this.status,
      messageStatus: messageStatus ?? this.messageStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      localFilePath: localFilePath ?? this.localFilePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      isPending: isPending ?? this.isPending,
      isDeleted: isDeleted ?? this.isDeleted,
      deleteType: deleteType ?? this.deleteType,
      encryptionInfo: encryptionInfo ?? this.encryptionInfo,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      encryptionVersion: encryptionVersion ?? this.encryptionVersion,
    );
  }

  // Update message status to delivered
  Message markAsDelivered() {
    return copyWith(
      status: 'delivered',
      messageStatus: MessageStatus.delivered,
      deliveredAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  // Update message status to read
  Message markAsRead() {
    return copyWith(
      status: 'read',
      messageStatus: MessageStatus.read,
      readAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  // Check if a message needs a read receipt
  bool get needsReadReceipt =>
      isDelivered && !isRead && !isError && !isPendingStatus && !isDeleted;

  // Check if a message needs a delivery receipt
  bool get needsDeliveryReceipt =>
      isSent &&
      !isDelivered &&
      !isRead &&
      !isError &&
      !isPendingStatus &&
      !isDeleted;
}
