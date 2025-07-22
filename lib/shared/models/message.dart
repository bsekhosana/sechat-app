import 'package:flutter/material.dart';

enum MessageType { text, image, voice, file }

class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String content;
  final MessageType type;
  final String status; // 'sent', 'delivered', 'read', 'pending', 'error'
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? localFilePath; // For images, voice, files
  final String? fileName; // Original file name
  final int? fileSize; // File size in bytes
  final bool isPending; // For offline messages
  final bool isDeleted; // For deleted messages
  final String? deleteType; // 'for_me' or 'for_everyone'

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.content,
    this.type = MessageType.text,
    this.status = 'sent',
    required this.createdAt,
    required this.updatedAt,
    this.localFilePath,
    this.fileName,
    this.fileSize,
    this.isPending = false,
    this.isDeleted = false,
    this.deleteType,
  });

  factory Message.fromJson(dynamic json) {
    try {
      // Convert LinkedMap to Map<String, dynamic> if needed
      final Map<String, dynamic> data = Map<String, dynamic>.from(json);

      return Message(
        id: data['id']?.toString() ?? '',
        chatId: data['chat_id']?.toString() ?? '',
        senderId: data['sender_id']?.toString() ?? '',
        content: data['content'] ?? '',
        type: MessageType.values.firstWhere(
          (e) => e.toString().split('.').last == (data['type'] ?? 'text'),
          orElse: () => MessageType.text,
        ),
        status: data['status'] ?? 'sent',
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
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
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
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'local_file_path': localFilePath,
      'file_name': fileName,
      'file_size': fileSize,
      'is_pending': isPending,
      'is_deleted': isDeleted,
      'delete_type': deleteType,
    };
  }

  // Status getters for message indicators
  bool get isSent => status == 'sent';
  bool get isDelivered => status == 'delivered' || status == 'read';
  bool get isRead => status == 'read';
  bool get isError => status == 'error';

  // Get the appropriate icon for message status
  IconData get statusIcon {
    if (isError) return Icons.error;
    if (isRead) return Icons.done_all;
    if (isDelivered) return Icons.done_all;
    return Icons.done;
  }

  // Get the appropriate color for message status
  Color getStatusColor(Color baseColor) {
    if (isError) return Colors.red;
    if (isRead) return Colors.blue;
    if (isDelivered) return baseColor;
    if (isPending) return Colors.orange;
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

  Message copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? content,
    MessageType? type,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? localFilePath,
    String? fileName,
    int? fileSize,
    bool? isPending,
    bool? isDeleted,
    String? deleteType,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      type: type ?? this.type,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      localFilePath: localFilePath ?? this.localFilePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      isPending: isPending ?? this.isPending,
      isDeleted: isDeleted ?? this.isDeleted,
      deleteType: deleteType ?? this.deleteType,
    );
  }
}
