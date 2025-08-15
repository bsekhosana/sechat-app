import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/message.dart';
import '../models/media_message.dart';
import '../models/chat_conversation.dart';
import 'message_storage_service.dart';
import 'chat_encryption_service.dart';
import 'message_status_tracking_service.dart';

/// Service for handling video message recording, compression, and management
class VideoMessageService {
  static VideoMessageService? _instance;
  static VideoMessageService get instance =>
      _instance ??= VideoMessageService._();

  final MessageStorageService _storageService = MessageStorageService.instance;
  final ChatEncryptionService _encryptionService =
      ChatEncryptionService.instance;
  final MessageStatusTrackingService _statusTrackingService =
      MessageStatusTrackingService.instance;

  // Recording state
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingDuration = 0; // in seconds
  String? _currentRecordingPath;
  StreamController<int>? _durationController;
  StreamController<VideoRecordingState>? _recordingStateController;

  // Compression state
  bool _isCompressing = false;
  StreamController<VideoCompressionProgress>? _compressionProgressController;

  VideoMessageService._();

  /// Stream for recording duration updates
  Stream<int>? get recordingDurationStream => _durationController?.stream;

  /// Stream for recording state updates
  Stream<VideoRecordingState>? get recordingStateStream =>
      _recordingStateController?.stream;

  /// Stream for compression progress updates
  Stream<VideoCompressionProgress>? get compressionProgressStream =>
      _compressionProgressController?.stream;

  /// Check if currently recording
  bool get isRecording => _isRecording;

  /// Check if currently compressing
  bool get isCompressing => _isCompressing;

  /// Get current recording duration
  int get currentRecordingDuration => _recordingDuration;

  /// Get current recording path
  String? get currentRecordingPath => _currentRecordingPath;

  /// Start recording a video message
  Future<bool> startRecording({
    required String conversationId,
    required String recipientId,
    VideoRecordingOptions options = const VideoRecordingOptions(),
  }) async {
    try {
      if (_isRecording) {
        print(
            '🎥 VideoMessageService: Already recording, stopping current recording');
        await stopRecording();
      }

      print(
          '🎥 VideoMessageService: Starting video recording with options: $options');

      // Initialize recording state
      _isRecording = true;
      _recordingDuration = 0;
      _durationController = StreamController<int>.broadcast();
      _recordingStateController =
          StreamController<VideoRecordingState>.broadcast();

      // Create temporary recording file
      final tempDir = await getTemporaryDirectory();
      final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      _currentRecordingPath = path.join(tempDir.path, fileName);

      // Emit recording started state
      _recordingStateController?.add(VideoRecordingState(
        isRecording: true,
        duration: 0,
        state: VideoRecordingStateType.recording,
        filePath: _currentRecordingPath,
      ));

      // Start recording timer
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _recordingDuration++;
        _durationController?.add(_recordingDuration);

        // Update recording state
        _recordingStateController?.add(VideoRecordingState(
          isRecording: true,
          duration: _recordingDuration,
          state: VideoRecordingStateType.recording,
          filePath: _currentRecordingPath,
        ));

        // Check if maximum duration reached (1 minute = 60 seconds)
        if (_recordingDuration >= 60) {
          print(
              '🎥 VideoMessageService: Maximum recording duration reached (1 minute)');
          stopRecording();
        }
      });

      print('🎥 VideoMessageService: ✅ Video recording started');
      return true;
    } catch (e) {
      print('🎥 VideoMessageService: ❌ Failed to start recording: $e');
      _resetRecordingState();
      return false;
    }
  }

  /// Stop recording and process the video message
  Future<Message?> stopRecording() async {
    try {
      if (!_isRecording) {
        print('🎥 VideoMessageService: Not currently recording');
        return null;
      }

      print('🎥 VideoMessageService: Stopping video recording');

      // Stop recording timer
      _recordingTimer?.cancel();
      _recordingTimer = null;

      // Stop duration stream
      await _durationController?.close();
      _durationController = null;

      // Check if recording is too short
      if (_recordingDuration < 1) {
        print('🎥 VideoMessageService: Recording too short, discarding');
        _resetRecordingState();
        return null;
      }

      // Emit recording stopped state
      _recordingStateController?.add(VideoRecordingState(
        isRecording: false,
        duration: _recordingDuration,
        state: VideoRecordingStateType.stopped,
        filePath: _currentRecordingPath,
      ));

      // Process the recorded video
      final message = await _processRecordedVideo();

      _resetRecordingState();
      return message;
    } catch (e) {
      print('🎥 VideoMessageService: ❌ Failed to stop recording: $e');
      _resetRecordingState();
      return null;
    }
  }

  /// Process the recorded video file
  Future<Message?> _processRecordedVideo() async {
    try {
      if (_currentRecordingPath == null) return null;

      final videoFile = File(_currentRecordingPath!);
      if (!await videoFile.exists()) {
        print('🎥 VideoMessageService: ❌ Recorded video file not found');
        return null;
      }

      // Get file size
      final fileSize = await videoFile.length();

      // Check file size limit (50MB for raw video)
      if (fileSize > 50 * 1024 * 1024) {
        print(
            '🎥 VideoMessageService: ❌ Video file too large: ${fileSize} bytes');
        return null;
      }

      // Create media message
      final mediaMessage = MediaMessage(
        messageId: const Uuid().v4(),
        type: MediaType.video,
        filePath: _currentRecordingPath!,
        fileName: path.basename(_currentRecordingPath!),
        mimeType: 'video/mp4',
        fileSize: fileSize,
        duration: _recordingDuration,
        isCompressed: false, // Raw recording
      );

      // Save media message to storage
      final videoData = await videoFile.readAsBytes();
      await _storageService.saveMediaMessage(mediaMessage, videoData);

      // Create video message
      final message = Message(
        conversationId: 'conversation_id', // Will be set by caller
        senderId: _getCurrentUserId(),
        recipientId: 'recipient_id', // Will be set by caller
        type: MessageType.video,
        content: {
          'duration': _recordingDuration,
          'file_size': fileSize,
          'mime_type': 'video/mp4',
          'is_compressed': false,
          'recording_timestamp': DateTime.now().millisecondsSinceEpoch,
          'resolution': 'unknown', // Will be updated after processing
          'frame_rate': 30, // Default assumption
        },
        status: MessageStatus.sending,
        fileSize: fileSize,
        mimeType: 'video/mp4',
      );

      print('🎥 VideoMessageService: ✅ Video message processed successfully');
      return message;
    } catch (e) {
      print('🎥 VideoMessageService: ❌ Failed to process recorded video: $e');
      return null;
    }
  }

  /// Send a video message
  Future<Message?> sendVideoMessage({
    required String conversationId,
    required String recipientId,
    required String videoFilePath,
    required int duration,
    VideoCompressionOptions compressionOptions =
        const VideoCompressionOptions(),
    Map<String, dynamic>? metadata,
  }) async {
    try {
      print('🎥 VideoMessageService: Sending video message to $recipientId');

      // Validate video message
      if (!_validateVideoMessage(videoFilePath, duration)) {
        throw Exception(
            'Invalid video message: File not found or duration invalid');
      }

      // Get video file
      final videoFile = File(videoFilePath);
      final fileSize = await videoFile.length();

      // Check if compression is needed
      bool shouldCompress = compressionOptions.enableCompression &&
          fileSize > compressionOptions.maxFileSize;

      String finalFilePath = videoFilePath;
      int finalFileSize = fileSize;
      bool isCompressed = false;

      // Compress video if needed
      if (shouldCompress) {
        print(
            '🎥 VideoMessageService: Compressing video (${fileSize} bytes -> target: ${compressionOptions.maxFileSize} bytes)');

        final compressedVideo = await _compressVideo(
          videoFilePath,
          compressionOptions,
        );

        if (compressedVideo != null) {
          finalFilePath = compressedVideo['file_path'];
          finalFileSize = compressedVideo['file_size'];
          isCompressed = true;
          print(
              '🎥 VideoMessageService: ✅ Video compressed successfully (${fileSize} -> ${finalFileSize} bytes)');
        } else {
          print(
              '🎥 VideoMessageService: ⚠️ Compression failed, using original file');
        }
      }

      // Create media message
      final mediaMessage = MediaMessage(
        messageId: const Uuid().v4(),
        type: MediaType.video,
        filePath: finalFilePath,
        fileName: path.basename(finalFilePath),
        mimeType: 'video/mp4',
        fileSize: finalFileSize,
        duration: duration,
        isCompressed: isCompressed,
      );

      // Save media message to storage
      final videoData = await File(finalFilePath).readAsBytes();
      await _storageService.saveMediaMessage(mediaMessage, videoData);

      // Create video message
      final message = Message(
        conversationId: conversationId,
        senderId: _getCurrentUserId(),
        recipientId: recipientId,
        type: MessageType.video,
        content: {
          'duration': duration,
          'file_size': finalFileSize,
          'mime_type': 'video/mp4',
          'is_compressed': isCompressed,
          'recording_timestamp': DateTime.now().millisecondsSinceEpoch,
          'compression_ratio': isCompressed ? fileSize / finalFileSize : 1.0,
          'original_size': fileSize,
          'resolution': metadata?['resolution'] ?? 'unknown',
          'frame_rate': metadata?['frame_rate'] ?? 30,
        },
        status: MessageStatus.sending,
        fileSize: finalFileSize,
        mimeType: 'video/mp4',
        replyToMessageId: metadata?['reply_to_message_id'],
        metadata: metadata,
      );

      // Save message to storage
      await _storageService.saveMessage(message);

      // Update conversation with new message
      await _updateConversationWithMessage(message);

      // Mark message as sent
      await _statusTrackingService.markMessageAsSent(message.id);

      print(
          '🎥 VideoMessageService: ✅ Video message sent successfully: ${message.id}');
      return message;
    } catch (e) {
      print('🎥 VideoMessageService: ❌ Failed to send video message: $e');
      rethrow;
    }
  }

  /// Compress video with specified options
  Future<Map<String, dynamic>?> _compressVideo(
    String videoFilePath,
    VideoCompressionOptions options,
  ) async {
    try {
      _isCompressing = true;
      _compressionProgressController =
          StreamController<VideoCompressionProgress>.broadcast();

      print('🎥 VideoMessageService: Starting video compression');

      // Emit compression started
      _compressionProgressController?.add(VideoCompressionProgress(
        progress: 0.0,
        status: VideoCompressionStatus.started,
        message: 'Initializing compression...',
      ));

      // Simulate compression progress (in real implementation, this would use FFmpeg or similar)
      for (int i = 1; i <= 10; i++) {
        await Future.delayed(Duration(milliseconds: 200)); // Simulate work

        _compressionProgressController?.add(VideoCompressionProgress(
          progress: i / 10.0,
          status: VideoCompressionStatus.compressing,
          message: 'Compressing video... ${(i * 10).toInt()}%',
        ));
      }

      // Create compressed file path
      final tempDir = await getTemporaryDirectory();
      final compressedFileName = 'compressed_${path.basename(videoFilePath)}';
      final compressedFilePath = path.join(tempDir.path, compressedFileName);

      // Simulate file size reduction (in real implementation, this would be actual compression)
      final originalFile = File(videoFilePath);
      final originalSize = await originalFile.length();
      final compressedSize = (originalSize * options.qualityFactor).round();

      // Copy file as "compressed" (in real implementation, this would be actual compression)
      await originalFile.copy(compressedFilePath);

      // Emit compression completed
      _compressionProgressController?.add(VideoCompressionProgress(
        progress: 1.0,
        status: VideoCompressionStatus.completed,
        message: 'Compression completed successfully',
        compressedFilePath: compressedFilePath,
        originalSize: originalSize,
        compressedSize: compressedSize,
      ));

      print('🎥 VideoMessageService: ✅ Video compression completed');

      return {
        'file_path': compressedFilePath,
        'file_size': compressedSize,
        'compression_ratio': originalSize / compressedSize,
      };
    } catch (e) {
      print('🎥 VideoMessageService: ❌ Video compression failed: $e');

      _compressionProgressController?.add(VideoCompressionProgress(
        progress: 0.0,
        status: VideoCompressionStatus.failed,
        message: 'Compression failed: $e',
      ));

      return null;
    } finally {
      _isCompressing = false;
      await _compressionProgressController?.close();
      _compressionProgressController = null;
    }
  }

  /// Generate thumbnail for video
  Future<String?> generateVideoThumbnail(String videoFilePath) async {
    try {
      print('🎥 VideoMessageService: Generating thumbnail for video');

      // In real implementation, this would use FFmpeg or similar to extract a frame
      // For now, we'll simulate thumbnail generation

      final tempDir = await getTemporaryDirectory();
      final thumbnailFileName =
          'thumb_${path.basenameWithoutExtension(videoFilePath)}.jpg';
      final thumbnailPath = path.join(tempDir.path, thumbnailFileName);

      // Simulate thumbnail creation (in real implementation, this would extract a frame)
      // For now, we'll create a placeholder file
      final thumbnailFile = File(thumbnailPath);
      await thumbnailFile
          .writeAsBytes(Uint8List(0)); // Empty file as placeholder

      print('🎥 VideoMessageService: ✅ Thumbnail generated: $thumbnailPath');
      return thumbnailPath;
    } catch (e) {
      print('🎥 VideoMessageService: ❌ Failed to generate thumbnail: $e');
      return null;
    }
  }

  /// Get video metadata
  Future<Map<String, dynamic>?> getVideoMetadata(String videoFilePath) async {
    try {
      final videoFile = File(videoFilePath);
      if (!await videoFile.exists()) return null;

      // In real implementation, this would use FFmpeg or similar to extract metadata
      // For now, return placeholder data
      return {
        'duration': 0,
        'resolution': 'unknown',
        'frame_rate': 30,
        'bitrate': 0,
        'codec': 'H.264',
        'audio_codec': 'AAC',
      };
    } catch (e) {
      print('🎥 VideoMessageService: ❌ Failed to get video metadata: $e');
      return null;
    }
  }

  /// Delete a video message
  Future<bool> deleteVideoMessage(String messageId) async {
    try {
      print('🎥 VideoMessageService: Deleting video message: $messageId');

      // Get the message
      final message = await _getMessageById(messageId);
      if (message == null) {
        print('🎥 VideoMessageService: ❌ Message not found: $messageId');
        return false;
      }

      // Check if it's a video message
      if (message.type != MessageType.video) {
        print('🎥 VideoMessageService: ❌ Not a video message: ${message.type}');
        return false;
      }

      // Mark message as deleted
      final deletedMessage = message.copyWith(
        status: MessageStatus.deleted,
        deletedAt: DateTime.now(),
      );

      await _storageService.saveMessage(deletedMessage);

      print('🎥 VideoMessageService: ✅ Video message deleted: $messageId');
      return true;
    } catch (e) {
      print('🎥 VideoMessageService: ❌ Failed to delete video message: $e');
      return false;
    }
  }

  /// Get video message statistics
  Future<Map<String, dynamic>> getVideoMessageStats() async {
    try {
      // This would typically query the storage service for statistics
      // For now, return placeholder data
      return {
        'total_video_messages': 0,
        'total_duration': 0,
        'average_duration': 0,
        'total_file_size': 0,
        'compression_ratio': 1.0,
        'total_compressed_videos': 0,
        'total_uncompressed_videos': 0,
      };
    } catch (e) {
      print('🎥 VideoMessageService: ❌ Failed to get video message stats: $e');
      return {};
    }
  }

  /// Validate video message
  bool _validateVideoMessage(String videoFilePath, int duration) {
    if (videoFilePath.isEmpty) return false;
    if (duration <= 0 || duration > 60) return false; // Max 1 minute
    return true;
  }

  /// Reset recording state
  void _resetRecordingState() {
    _isRecording = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingDuration = 0;
    _durationController?.close();
    _durationController = null;
    _recordingStateController?.close();
    _recordingStateController = null;
    _currentRecordingPath = null;
  }

  /// Update conversation with new message
  Future<void> _updateConversationWithMessage(Message message) async {
    try {
      final conversation =
          await _storageService.getConversation(message.conversationId);
      if (conversation == null) return;

      final updatedConversation = conversation.updateWithNewMessage(
        messageId: message.id,
        messagePreview: message.previewText,
        messageType: _convertToConversationMessageType(message.type),
        isFromCurrentUser: message.senderId == _getCurrentUserId(),
      );

      await _storageService.saveConversation(updatedConversation);
    } catch (e) {
      print('🎥 VideoMessageService: ❌ Failed to update conversation: $e');
    }
  }

  /// Convert MessageType to conversation MessageType
  MessageType _convertToConversationMessageType(MessageType type) {
    // Since we're using the same MessageType enum, just return the type directly
    return type;
  }

  /// Get message by ID
  Future<Message?> _getMessageById(String messageId) async {
    try {
      // This will be implemented when we add message retrieval to the storage service
      // For now, return null
      return null;
    } catch (e) {
      print('🎥 VideoMessageService: ❌ Failed to get message: $e');
      return null;
    }
  }

  /// Get current user ID
  String _getCurrentUserId() {
    // This will be implemented when we integrate with the session service
    // For now, return a placeholder
    return 'current_user_id';
  }

  /// Dispose of resources
  void dispose() {
    _resetRecordingState();
    print('🎥 VideoMessageService: ✅ Service disposed');
  }
}

/// Options for video recording
class VideoRecordingOptions {
  final int maxDuration; // in seconds
  final String resolution; // e.g., '720p', '1080p'
  final int frameRate; // e.g., 30, 60
  final bool enableStabilization;
  final bool enableHDR;

  const VideoRecordingOptions({
    this.maxDuration = 60, // 1 minute default
    this.resolution = '720p',
    this.frameRate = 30,
    this.enableStabilization = true,
    this.enableHDR = false,
  });
}

/// Options for video compression
class VideoCompressionOptions {
  final bool enableCompression;
  final int maxFileSize; // in bytes
  final double qualityFactor; // 0.0 to 1.0 (1.0 = no compression)
  final String targetResolution; // e.g., '480p', '720p'
  final int targetBitrate; // in kbps
  final bool preserveAudioQuality;

  const VideoCompressionOptions({
    this.enableCompression = true,
    this.maxFileSize = 10 * 1024 * 1024, // 10MB default
    this.qualityFactor = 0.7, // 70% quality
    this.targetResolution = '720p',
    this.targetBitrate = 1000, // 1Mbps
    this.preserveAudioQuality = true,
  });
}

/// Data class for video recording state
class VideoRecordingState {
  final bool isRecording;
  final int duration; // in seconds
  final VideoRecordingStateType state;
  final String? filePath;

  VideoRecordingState({
    required this.isRecording,
    required this.duration,
    required this.state,
    this.filePath,
  });
}

/// Enum for video recording state types
enum VideoRecordingStateType {
  recording,
  paused,
  stopped,
  error,
}

/// Data class for video compression progress
class VideoCompressionProgress {
  final double progress; // 0.0 to 1.0
  final VideoCompressionStatus status;
  final String message;
  final String? compressedFilePath;
  final int? originalSize;
  final int? compressedSize;

  VideoCompressionProgress({
    required this.progress,
    required this.status,
    required this.message,
    this.compressedFilePath,
    this.originalSize,
    this.compressedSize,
  });
}

/// Enum for video compression status
enum VideoCompressionStatus {
  started,
  compressing,
  completed,
  failed,
  cancelled,
}
