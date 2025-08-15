import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

/// Media message model for voice, video, image, and document messages
class MediaMessage {
  final String id;
  final String messageId;
  final MediaType type;
  final String filePath;
  final String fileName;
  final String mimeType;
  final int fileSize; // Size in bytes
  final int? duration; // Duration in seconds for audio/video
  final int? width; // Width in pixels for images/videos
  final int? height; // Height in pixels for images/videos
  final bool isCompressed;
  final String? thumbnailPath; // Path to thumbnail for videos/images
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime? processedAt;

  MediaMessage({
    String? id,
    required this.messageId,
    required this.type,
    required this.filePath,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    this.duration,
    this.width,
    this.height,
    this.isCompressed = false,
    this.thumbnailPath,
    this.metadata,
    DateTime? createdAt,
    this.processedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  /// Create a copy with updated fields
  MediaMessage copyWith({
    String? id,
    String? messageId,
    MediaType? type,
    String? filePath,
    String? fileName,
    String? mimeType,
    int? fileSize,
    int? duration,
    int? width,
    int? height,
    bool? isCompressed,
    String? thumbnailPath,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? processedAt,
  }) {
    return MediaMessage(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      type: type ?? this.type,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      duration: duration ?? this.duration,
      width: width ?? this.width,
      height: height ?? this.height,
      isCompressed: isCompressed ?? this.isCompressed,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      processedAt: processedAt ?? this.processedAt,
    );
  }

  /// Get file extension
  String get fileExtension => path.extension(fileName).toLowerCase();

  /// Get file size in human readable format
  String get fileSizeFormatted {
    if (fileSize < 1024) {
      return '${fileSize}B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)}KB';
    } else if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB';
    } else {
      return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }
  }

  /// Get duration in human readable format
  String get durationFormatted {
    if (duration == null) return '';

    final minutes = duration! ~/ 60;
    final seconds = duration! % 60;

    if (minutes > 0) {
      return '${minutes}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${seconds}s';
    }
  }

  /// Check if file exists
  Future<bool> get fileExists async {
    try {
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  /// Get file as File object
  File? get file {
    try {
      return File(filePath);
    } catch (e) {
      return null;
    }
  }

  /// Check if media type supports compression
  bool get supportsCompression =>
      type == MediaType.video || type == MediaType.image;

  /// Check if media type supports thumbnails
  bool get supportsThumbnails =>
      type == MediaType.video || type == MediaType.image;

  /// Get media type icon
  String get mediaIcon {
    switch (type) {
      case MediaType.voice:
        return '🎤';
      case MediaType.video:
        return '🎥';
      case MediaType.image:
        return '🖼️';
      case MediaType.document:
        return '📄';
    }
  }

  /// Get media type display name
  String get mediaTypeName {
    switch (type) {
      case MediaType.voice:
        return 'Voice Message';
      case MediaType.video:
        return 'Video Message';
      case MediaType.image:
        return 'Image';
      case MediaType.document:
        return 'Document';
    }
  }

  /// Check if file size is within limits
  bool get isWithinSizeLimit {
    switch (type) {
      case MediaType.voice:
        return fileSize <= 10 * 1024 * 1024; // 10MB
      case MediaType.video:
        return fileSize <= 50 * 1024 * 1024; // 50MB
      case MediaType.image:
        return fileSize <= 20 * 1024 * 1024; // 20MB
      case MediaType.document:
        return fileSize <= 100 * 1024 * 1024; // 100MB
    }
  }

  /// Get recommended compression settings
  Map<String, dynamic> get compressionSettings {
    switch (type) {
      case MediaType.voice:
        return {
          'audioCodec': 'aac',
          'bitrate': '64k',
          'sampleRate': 22050,
        };
      case MediaType.video:
        return {
          'videoCodec': 'h264',
          'audioCodec': 'aac',
          'videoBitrate': '500k',
          'audioBitrate': '64k',
          'resolution': '480p',
        };
      case MediaType.image:
        return {
          'quality': 80,
          'maxWidth': 1920,
          'maxHeight': 1080,
        };
      case MediaType.document:
        return {}; // No compression for documents
    }
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'message_id': messageId,
      'type': type.name,
      'file_path': filePath,
      'file_name': fileName,
      'mime_type': mimeType,
      'file_size': fileSize,
      'duration': duration,
      'width': width,
      'height': height,
      'is_compressed': isCompressed,
      'thumbnail_path': thumbnailPath,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
      'processed_at': processedAt?.toIso8601String(),
    };
  }

  /// Create from JSON
  factory MediaMessage.fromJson(Map<String, dynamic> json) {
    return MediaMessage(
      id: json['id'] as String,
      messageId: json['message_id'] as String,
      type: MediaType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MediaType.document,
      ),
      filePath: json['file_path'] as String,
      fileName: json['file_name'] as String,
      mimeType: json['mime_type'] as String,
      fileSize: json['file_size'] as int,
      duration: json['duration'] as int?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      isCompressed: json['is_compressed'] as bool? ?? false,
      thumbnailPath: json['thumbnail_path'] as String?,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      processedAt: json['processed_at'] != null
          ? DateTime.parse(json['processed_at'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaMessage &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'MediaMessage(id: $id, type: $type, fileName: $fileName, fileSize: $fileSizeFormatted)';
  }
}

/// Enum for media types
enum MediaType {
  voice, // Voice/audio messages
  video, // Video clips
  image, // Images
  document, // Documents/files
}

/// Media processing options
class MediaProcessingOptions {
  final bool enableCompression;
  final bool generateThumbnails;
  final int? maxFileSize; // Override default size limits
  final Map<String, dynamic>? customCompressionSettings;
  final bool preserveOriginal; // Keep original file after processing

  const MediaProcessingOptions({
    this.enableCompression = true,
    this.generateThumbnails = true,
    this.maxFileSize,
    this.customCompressionSettings,
    this.preserveOriginal = false,
  });

  /// Get compression settings for a specific media type
  Map<String, dynamic> getCompressionSettings(MediaType type) {
    if (customCompressionSettings != null) {
      return customCompressionSettings!;
    }

    switch (type) {
      case MediaType.voice:
        return {
          'audioCodec': 'aac',
          'bitrate': '64k',
          'sampleRate': 22050,
        };
      case MediaType.video:
        return {
          'videoCodec': 'h264',
          'audioCodec': 'aac',
          'videoBitrate': '500k',
          'audioBitrate': '64k',
          'resolution': '480p',
        };
      case MediaType.image:
        return {
          'quality': 80,
          'maxWidth': 1920,
          'maxHeight': 1080,
        };
      case MediaType.document:
        return {}; // No compression for documents
    }
  }
}
