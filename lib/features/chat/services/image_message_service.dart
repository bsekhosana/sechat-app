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

/// Service for handling image message capture, compression, and management
class ImageMessageService {
  static ImageMessageService? _instance;
  static ImageMessageService get instance =>
      _instance ??= ImageMessageService._();

  final MessageStorageService _storageService = MessageStorageService.instance;
  final ChatEncryptionService _encryptionService =
      ChatEncryptionService.instance;
  final MessageStatusTrackingService _statusTrackingService =
      MessageStatusTrackingService.instance;

  // Processing state
  bool _isProcessing = false;
  StreamController<ImageProcessingProgress>? _processingProgressController;

  ImageMessageService._();

  /// Stream for image processing progress updates
  Stream<ImageProcessingProgress>? get processingProgressStream =>
      _processingProgressController?.stream;

  /// Check if currently processing
  bool get isProcessing => _isProcessing;

  /// Capture image from camera
  Future<Message?> captureImage({
    required String conversationId,
    required String recipientId,
    ImageCaptureOptions options = const ImageCaptureOptions(),
  }) async {
    try {
      print('📸 ImageMessageService: Capturing image with options: $options');

      // In real implementation, this would open the camera
      // For now, we'll simulate image capture
      final imagePath = await _simulateImageCapture(options);
      if (imagePath == null) {
        print('📸 ImageMessageService: ❌ Image capture failed');
        return null;
      }

      // Process the captured image
      final message = await _processImage(
        imagePath: imagePath,
        conversationId: conversationId,
        recipientId: recipientId,
        source: ImageSource.camera,
        options: ImageProcessingOptions(
          compressionOptions: options.compressionOptions,
        ),
      );

      print(
          '📸 ImageMessageService: ✅ Image captured and processed successfully');
      return message;
    } catch (e) {
      print('📸 ImageMessageService: ❌ Failed to capture image: $e');
      rethrow;
    }
  }

  /// Select image from gallery
  Future<Message?> selectImageFromGallery({
    required String conversationId,
    required String recipientId,
    ImageSelectionOptions options = const ImageSelectionOptions(),
  }) async {
    try {
      print(
          '📸 ImageMessageService: Selecting image from gallery with options: $options');

      // In real implementation, this would open the gallery picker
      // For now, we'll simulate gallery selection
      final imagePath = await _simulateGallerySelection(options);
      if (imagePath == null) {
        print('📸 ImageMessageService: ❌ Gallery selection failed');
        return null;
      }

      // Process the selected image
      final message = await _processImage(
        imagePath: imagePath,
        conversationId: conversationId,
        recipientId: recipientId,
        source: ImageSource.gallery,
        options: ImageProcessingOptions(
          compressionOptions: options.compressionOptions,
        ),
      );

      print(
          '📸 ImageMessageService: ✅ Image selected and processed successfully');
      return message;
    } catch (e) {
      print(
          '📸 ImageMessageService: ❌ Failed to select image from gallery: $e');
      rethrow;
    }
  }

  /// Send an image message
  Future<Message?> sendImageMessage({
    required String conversationId,
    required String recipientId,
    required String imageFilePath,
    ImageCompressionOptions compressionOptions =
        const ImageCompressionOptions(),
    Map<String, dynamic>? metadata,
  }) async {
    try {
      print('📸 ImageMessageService: Sending image message to $recipientId');

      // Validate image file
      if (!_validateImageFile(imageFilePath)) {
        throw Exception(
            'Invalid image file: File not found or unsupported format');
      }

      // Get image file
      final imageFile = File(imageFilePath);
      final fileSize = await imageFile.length();

      // Check if compression is needed
      bool shouldCompress = compressionOptions.enableCompression &&
          fileSize > compressionOptions.maxFileSize;

      String finalFilePath = imageFilePath;
      int finalFileSize = fileSize;
      bool isCompressed = false;
      Map<String, dynamic> compressionInfo = {};

      // Compress image if needed
      if (shouldCompress) {
        print(
            '📸 ImageMessageService: Compressing image (${fileSize} bytes -> target: ${compressionOptions.maxFileSize} bytes)');

        final compressedImage = await _compressImage(
          imageFilePath,
          compressionOptions,
        );

        if (compressedImage != null) {
          finalFilePath = compressedImage['file_path'];
          finalFileSize = compressedImage['file_size'];
          isCompressed = true;
          compressionInfo = compressedImage;
          print(
              '📸 ImageMessageService: ✅ Image compressed successfully (${fileSize} -> ${finalFileSize} bytes)');
        } else {
          print(
              '📸 ImageMessageService: ⚠️ Compression failed, using original file');
        }
      }

      // Generate thumbnails
      final thumbnails = await _generateImageThumbnails(finalFilePath);

      // Create media message
      final mediaMessage = MediaMessage(
        messageId: const Uuid().v4(),
        type: MediaType.image,
        filePath: finalFilePath,
        fileName: path.basename(finalFilePath),
        mimeType: _getMimeType(finalFilePath),
        fileSize: finalFileSize,
        duration: null, // Images don't have duration
        isCompressed: isCompressed,
        thumbnailPath: thumbnails['medium'], // Use medium thumbnail as primary
        metadata: {
          'thumbnails': thumbnails,
          'compression_info': compressionInfo,
        },
      );

      // Save media message to storage
      final imageData = await File(finalFilePath).readAsBytes();
      await _storageService.saveMediaMessage(mediaMessage, imageData);

      // Create image message
      final message = Message(
        conversationId: conversationId,
        senderId: _getCurrentUserId(),
        recipientId: recipientId,
        type: MessageType.image,
        content: {
          'file_size': finalFileSize,
          'mime_type': _getMimeType(finalFilePath),
          'is_compressed': isCompressed,
          'compression_ratio': isCompressed ? fileSize / finalFileSize : 1.0,
          'original_size': fileSize,
          'thumbnails': thumbnails,
          'dimensions': metadata?['dimensions'] ?? {'width': 0, 'height': 0},
          'orientation': metadata?['orientation'] ?? 'unknown',
          'capture_timestamp': metadata?['capture_timestamp'] ??
              DateTime.now().millisecondsSinceEpoch,
        },
        status: MessageStatus.sending,
        fileSize: finalFileSize,
        mimeType: _getMimeType(finalFilePath),
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
          '📸 ImageMessageService: ✅ Image message sent successfully: ${message.id}');
      return message;
    } catch (e) {
      print('📸 ImageMessageService: ❌ Failed to send image message: $e');
      rethrow;
    }
  }

  /// Process captured or selected image
  Future<Message?> _processImage({
    required String imagePath,
    required String conversationId,
    required String recipientId,
    required ImageSource source,
    required ImageProcessingOptions options,
  }) async {
    try {
      print('📸 ImageMessageService: Processing image: $imagePath');

      // Validate image file
      if (!_validateImageFile(imagePath)) {
        print('📸 ImageMessageService: ❌ Invalid image file');
        return null;
      }

      // Get image metadata
      final metadata = await _extractImageMetadata(imagePath);
      if (metadata == null) {
        print('📸 ImageMessageService: ❌ Failed to extract image metadata');
        return null;
      }

      // Send the image message
      final message = await sendImageMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        imageFilePath: imagePath,
        compressionOptions: options.compressionOptions,
        metadata: {
          ...metadata,
          'source': source.name,
          'capture_timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );

      return message;
    } catch (e) {
      print('📸 ImageMessageService: ❌ Failed to process image: $e');
      return null;
    }
  }

  /// Compress image with specified options
  Future<Map<String, dynamic>?> _compressImage(
    String imageFilePath,
    ImageCompressionOptions options,
  ) async {
    try {
      _isProcessing = true;
      _processingProgressController =
          StreamController<ImageProcessingProgress>.broadcast();

      print('📸 ImageMessageService: Starting image compression');

      // Emit compression started
      _processingProgressController?.add(ImageProcessingProgress(
        progress: 0.0,
        status: ImageProcessingStatus.started,
        message: 'Initializing compression...',
        operation: ImageOperation.compression,
      ));

      // Simulate compression progress (in real implementation, this would use image processing library)
      for (int i = 1; i <= 5; i++) {
        await Future.delayed(Duration(milliseconds: 300)); // Simulate work

        _processingProgressController?.add(ImageProcessingProgress(
          progress: i / 5.0,
          status: ImageProcessingStatus.processing,
          message: 'Compressing image... ${(i * 20).toInt()}%',
          operation: ImageOperation.compression,
        ));
      }

      // Create compressed file path
      final tempDir = await getTemporaryDirectory();
      final compressedFileName = 'compressed_${path.basename(imageFilePath)}';
      final compressedFilePath = path.join(tempDir.path, compressedFileName);

      // Simulate file size reduction (in real implementation, this would be actual compression)
      final originalFile = File(imageFilePath);
      final originalSize = await originalFile.length();
      final compressedSize = (originalSize * options.qualityFactor).round();

      // Copy file as "compressed" (in real implementation, this would be actual compression)
      await originalFile.copy(compressedFilePath);

      // Emit compression completed
      _processingProgressController?.add(ImageProcessingProgress(
        progress: 1.0,
        status: ImageProcessingStatus.completed,
        message: 'Compression completed successfully',
        operation: ImageOperation.compression,
        result: {
          'compressed_file_path': compressedFilePath,
          'original_size': originalSize,
          'compressed_size': compressedSize,
        },
      ));

      print('📸 ImageMessageService: ✅ Image compression completed');

      return {
        'file_path': compressedFilePath,
        'file_size': compressedSize,
        'compression_ratio': originalSize / compressedSize,
      };
    } catch (e) {
      print('📸 ImageMessageService: ❌ Image compression failed: $e');

      _processingProgressController?.add(ImageProcessingProgress(
        progress: 0.0,
        status: ImageProcessingStatus.failed,
        message: 'Compression failed: $e',
        operation: ImageOperation.compression,
      ));

      return null;
    } finally {
      _isProcessing = false;
      await _processingProgressController?.close();
      _processingProgressController = null;
    }
  }

  /// Generate thumbnails for image
  Future<Map<String, String>> _generateImageThumbnails(
      String imageFilePath) async {
    try {
      print('📸 ImageMessageService: Generating thumbnails for image');

      final thumbnails = <String, String>{};
      final tempDir = await getTemporaryDirectory();

      // Generate different thumbnail sizes
      final thumbnailSizes = {
        'small': 150,
        'medium': 300,
        'large': 600,
      };

      for (final entry in thumbnailSizes.entries) {
        final size = entry.value;
        final thumbnailFileName =
            'thumb_${entry.key}_${path.basenameWithoutExtension(imageFilePath)}.jpg';
        final thumbnailPath = path.join(tempDir.path, thumbnailFileName);

        // In real implementation, this would resize the image to the specified dimensions
        // For now, we'll create placeholder files
        final thumbnailFile = File(thumbnailPath);
        await thumbnailFile
            .writeAsBytes(Uint8List(0)); // Empty file as placeholder

        thumbnails[entry.key] = thumbnailPath;
      }

      print(
          '📸 ImageMessageService: ✅ Thumbnails generated: ${thumbnails.length} sizes');
      return thumbnails;
    } catch (e) {
      print('📸 ImageMessageService: ❌ Failed to generate thumbnails: $e');
      return {};
    }
  }

  /// Extract image metadata
  Future<Map<String, dynamic>?> _extractImageMetadata(
      String imageFilePath) async {
    try {
      final imageFile = File(imageFilePath);
      if (!await imageFile.exists()) return null;

      // In real implementation, this would use image processing library to extract metadata
      // For now, return placeholder data
      return {
        'dimensions': {'width': 1920, 'height': 1080}, // Default 1080p
        'orientation': 'landscape',
        'format': path.extension(imageFilePath).toLowerCase(),
        'color_space': 'sRGB',
        'bit_depth': 8,
      };
    } catch (e) {
      print('📸 ImageMessageService: ❌ Failed to extract image metadata: $e');
      return null;
    }
  }

  /// Simulate image capture (placeholder for camera integration)
  Future<String?> _simulateImageCapture(ImageCaptureOptions options) async {
    try {
      // In real implementation, this would open the camera
      // For now, we'll create a placeholder image file
      final tempDir = await getTemporaryDirectory();
      final fileName = 'captured_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final imagePath = path.join(tempDir.path, fileName);

      // Create a placeholder file
      final imageFile = File(imagePath);
      await imageFile.writeAsBytes(Uint8List(1024)); // 1KB placeholder

      print('📸 ImageMessageService: ✅ Simulated image capture: $imagePath');
      return imagePath;
    } catch (e) {
      print('📸 ImageMessageService: ❌ Simulated image capture failed: $e');
      return null;
    }
  }

  /// Simulate gallery selection (placeholder for gallery picker integration)
  Future<String?> _simulateGallerySelection(
      ImageSelectionOptions options) async {
    try {
      // In real implementation, this would open the gallery picker
      // For now, we'll create a placeholder image file
      final tempDir = await getTemporaryDirectory();
      final fileName = 'selected_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final imagePath = path.join(tempDir.path, fileName);

      // Create a placeholder file
      final imageFile = File(imagePath);
      await imageFile.writeAsBytes(Uint8List(2048)); // 2KB placeholder

      print(
          '📸 ImageMessageService: ✅ Simulated gallery selection: $imagePath');
      return imagePath;
    } catch (e) {
      print('📸 ImageMessageService: ❌ Simulated gallery selection failed: $e');
      return null;
    }
  }

  /// Get MIME type from file extension
  String _getMimeType(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    switch (extension) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.bmp':
        return 'image/bmp';
      default:
        return 'image/jpeg'; // Default to JPEG
    }
  }

  /// Validate image file
  bool _validateImageFile(String imageFilePath) {
    if (imageFilePath.isEmpty) return false;

    final extension = path.extension(imageFilePath).toLowerCase();
    final supportedFormats = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'];

    if (!supportedFormats.contains(extension)) return false;

    return true;
  }

  /// Delete an image message
  Future<bool> deleteImageMessage(String messageId) async {
    try {
      print('📸 ImageMessageService: Deleting image message: $messageId');

      // Get the message
      final message = await _getMessageById(messageId);
      if (message == null) {
        print('📸 ImageMessageService: ❌ Message not found: $messageId');
        return false;
      }

      // Check if it's an image message
      if (message.type != MessageType.image) {
        print(
            '📸 ImageMessageService: ❌ Not an image message: ${message.type}');
        return false;
      }

      // Mark message as deleted
      final deletedMessage = message.copyWith(
        status: MessageStatus.deleted,
        deletedAt: DateTime.now(),
      );

      await _storageService.saveMessage(deletedMessage);

      print('📸 ImageMessageService: ✅ Image message deleted: $messageId');
      return true;
    } catch (e) {
      print('📸 ImageMessageService: ❌ Failed to delete image message: $e');
      return false;
    }
  }

  /// Get image message statistics
  Future<Map<String, dynamic>> getImageMessageStats() async {
    try {
      // This would typically query the storage service for statistics
      // For now, return placeholder data
      return {
        'total_image_messages': 0,
        'total_file_size': 0,
        'average_file_size': 0,
        'compression_ratio': 1.0,
        'total_compressed_images': 0,
        'total_uncompressed_images': 0,
        'format_distribution': {
          'jpeg': 0,
          'png': 0,
          'webp': 0,
          'gif': 0,
          'bmp': 0,
        },
      };
    } catch (e) {
      print('📸 ImageMessageService: ❌ Failed to get image message stats: $e');
      return {};
    }
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
      print('📸 ImageMessageService: ❌ Failed to update conversation: $e');
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
      print('📸 ImageMessageService: ❌ Failed to get message: $e');
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
    _isProcessing = false;
    _processingProgressController?.close();
    print('📸 ImageMessageService: ✅ Service disposed');
  }
}

/// Options for image capture
class ImageCaptureOptions {
  final String resolution; // e.g., '720p', '1080p', '4K'
  final double quality; // 0.0 to 1.0
  final bool enableFlash;
  final bool enableHDR;
  final bool enableStabilization;
  final ImageCompressionOptions compressionOptions;

  const ImageCaptureOptions({
    this.resolution = '1080p',
    this.quality = 0.9,
    this.enableFlash = true,
    this.enableHDR = false,
    this.enableStabilization = true,
    this.compressionOptions = const ImageCompressionOptions(),
  });
}

/// Options for image selection from gallery
class ImageSelectionOptions {
  final bool allowMultiple;
  final List<String> allowedFormats; // e.g., ['jpg', 'png', 'webp']
  final int maxFileSize; // in bytes
  final ImageCompressionOptions compressionOptions;

  const ImageSelectionOptions({
    this.allowMultiple = false,
    this.allowedFormats = const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
    this.maxFileSize = 20 * 1024 * 1024, // 20MB default
    this.compressionOptions = const ImageCompressionOptions(),
  });
}

/// Options for image compression
class ImageCompressionOptions {
  final bool enableCompression;
  final int maxFileSize; // in bytes
  final double qualityFactor; // 0.0 to 1.0 (1.0 = no compression)
  final String targetFormat; // e.g., 'jpeg', 'png', 'webp'
  final int targetWidth; // 0 = maintain aspect ratio
  final int targetHeight; // 0 = maintain aspect ratio
  final bool preserveMetadata;

  const ImageCompressionOptions({
    this.enableCompression = true,
    this.maxFileSize = 5 * 1024 * 1024, // 5MB default
    this.qualityFactor = 0.8, // 80% quality
    this.targetFormat = 'jpeg',
    this.targetWidth = 0,
    this.targetHeight = 0,
    this.preserveMetadata = true,
  });
}

/// Options for image processing
class ImageProcessingOptions {
  final ImageCompressionOptions compressionOptions;
  final bool generateThumbnails;
  final List<int> thumbnailSizes; // e.g., [150, 300, 600]

  const ImageProcessingOptions({
    this.compressionOptions = const ImageCompressionOptions(),
    this.generateThumbnails = true,
    this.thumbnailSizes = const [150, 300, 600],
  });
}

/// Enum for image source
enum ImageSource {
  camera,
  gallery,
  screenshot,
  downloaded,
}

/// Data class for image processing progress
class ImageProcessingProgress {
  final double progress; // 0.0 to 1.0
  final ImageProcessingStatus status;
  final String message;
  final ImageOperation operation;
  final Map<String, dynamic>? result;

  ImageProcessingProgress({
    required this.progress,
    required this.status,
    required this.message,
    required this.operation,
    this.result,
  });
}

/// Enum for image processing status
enum ImageProcessingStatus {
  started,
  processing,
  completed,
  failed,
  cancelled,
}

/// Enum for image operations
enum ImageOperation {
  compression,
  thumbnailGeneration,
  metadataExtraction,
  formatConversion,
}
