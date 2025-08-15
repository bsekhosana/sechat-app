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

/// Service for handling document message sharing, compression, and management
class DocumentMessageService {
  static DocumentMessageService? _instance;
  static DocumentMessageService get instance =>
      _instance ??= DocumentMessageService._();

  final MessageStorageService _storageService = MessageStorageService.instance;
  final ChatEncryptionService _encryptionService =
      ChatEncryptionService.instance;
  final MessageStatusTrackingService _statusTrackingService =
      MessageStatusTrackingService.instance;

  // Processing state
  bool _isProcessing = false;
  StreamController<DocumentProcessingProgress>? _processingProgressController;

  DocumentMessageService._();

  /// Stream for document processing progress updates
  Stream<DocumentProcessingProgress>? get processingProgressStream =>
      _processingProgressController?.stream;

  /// Check if currently processing
  bool get isProcessing => _isProcessing;

  /// Select document from file picker
  Future<Message?> selectDocument({
    required String conversationId,
    required String recipientId,
    DocumentSelectionOptions options = const DocumentSelectionOptions(),
  }) async {
    try {
      print(
          '📄 DocumentMessageService: Selecting document with options: $options');

      // In real implementation, this would open the file picker
      // For now, we'll simulate document selection
      final documentPath = await _simulateDocumentSelection(options);
      if (documentPath == null) {
        print('📄 DocumentMessageService: ❌ Document selection failed');
        return null;
      }

      // Process the selected document
      final message = await _processDocument(
        documentPath: documentPath,
        conversationId: conversationId,
        recipientId: recipientId,
        options: options,
      );

      print(
          '📄 DocumentMessageService: ✅ Document selected and processed successfully');
      return message;
    } catch (e) {
      print('📄 DocumentMessageService: ❌ Failed to select document: $e');
      rethrow;
    }
  }

  /// Send a document message
  Future<Message?> sendDocumentMessage({
    required String conversationId,
    required String recipientId,
    required String documentFilePath,
    DocumentCompressionOptions compressionOptions =
        const DocumentCompressionOptions(),
    Map<String, dynamic>? metadata,
  }) async {
    try {
      print(
          '📄 DocumentMessageService: Sending document message to $recipientId');

      // Validate document file
      if (!_validateDocumentFile(documentFilePath)) {
        throw Exception(
            'Invalid document file: File not found or unsupported format');
      }

      // Get document file
      final documentFile = File(documentFilePath);
      final fileSize = await documentFile.length();

      // Check if compression is needed
      bool shouldCompress = compressionOptions.enableCompression &&
          fileSize > compressionOptions.maxFileSize;

      String finalFilePath = documentFilePath;
      int finalFileSize = fileSize;
      bool isCompressed = false;
      Map<String, dynamic> compressionInfo = {};

      // Compress document if needed
      if (shouldCompress) {
        print(
            '📄 DocumentMessageService: Compressing document (${fileSize} bytes -> target: ${compressionOptions.maxFileSize} bytes)');

        final compressedDocument = await _compressDocument(
          documentFilePath,
          compressionOptions,
        );

        if (compressedDocument != null) {
          finalFilePath = compressedDocument['file_path'];
          finalFileSize = compressedDocument['file_size'];
          isCompressed = true;
          compressionInfo = compressedDocument;
          print(
              '📄 DocumentMessageService: ✅ Document compressed successfully (${fileSize} -> ${finalFileSize} bytes)');
        } else {
          print(
              '📄 DocumentMessageService: ⚠️ Compression failed, using original file');
        }
      }

      // Generate thumbnail
      final thumbnailPath = await _generateDocumentThumbnail(finalFilePath);

      // Extract document metadata
      final documentMetadata = await _extractDocumentMetadata(finalFilePath);

      // Create media message
      final mediaMessage = MediaMessage(
        messageId: const Uuid().v4(),
        type: MediaType.document,
        filePath: finalFilePath,
        fileName: path.basename(finalFilePath),
        mimeType: _getMimeType(finalFilePath),
        fileSize: finalFileSize,
        duration: null, // Documents don't have duration
        isCompressed: isCompressed,
        thumbnailPath: thumbnailPath,
        metadata: {
          if (documentMetadata != null) ...documentMetadata,
          'compression_info': compressionInfo,
        },
      );

      // Save media message to storage
      final documentData = await File(finalFilePath).readAsBytes();
      await _storageService.saveMediaMessage(mediaMessage, documentData);

      // Create document message
      final message = Message(
        conversationId: conversationId,
        senderId: _getCurrentUserId(),
        recipientId: recipientId,
        type: MessageType.document,
        content: {
          'file_size': finalFileSize,
          'mime_type': _getMimeType(finalFilePath),
          'is_compressed': isCompressed,
          'compression_ratio': isCompressed ? fileSize / finalFileSize : 1.0,
          'original_size': fileSize,
          'thumbnail_path': thumbnailPath,
          'file_extension': path.extension(finalFilePath).toLowerCase(),
          'document_type': _getDocumentType(finalFilePath),
          'page_count': documentMetadata?['page_count'] ?? 0,
          'author': documentMetadata?['author'] ?? 'Unknown',
          'created_date': documentMetadata?['created_date'] ??
              DateTime.now().millisecondsSinceEpoch,
          'modified_date': documentMetadata?['modified_date'] ??
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
          '📄 DocumentMessageService: ✅ Document message sent successfully: ${message.id}');
      return message;
    } catch (e) {
      print('📄 DocumentMessageService: ❌ Failed to send document message: $e');
      rethrow;
    }
  }

  /// Process selected document
  Future<Message?> _processDocument({
    required String documentPath,
    required String conversationId,
    required String recipientId,
    required DocumentSelectionOptions options,
  }) async {
    try {
      print('📄 DocumentMessageService: Processing document: $documentPath');

      // Validate document file
      if (!_validateDocumentFile(documentPath)) {
        print('📄 DocumentMessageService: ❌ Invalid document file');
        return null;
      }

      // Check file size against options
      final documentFile = File(documentPath);
      final fileSize = await documentFile.length();

      if (fileSize > options.maxFileSize) {
        print(
            '📄 DocumentMessageService: ❌ Document file too large: ${fileSize} bytes');
        return null;
      }

      // Send the document message
      final message = await sendDocumentMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        documentFilePath: documentPath,
        compressionOptions: options.compressionOptions,
        metadata: {
          'source': 'file_picker',
          'selection_timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );

      return message;
    } catch (e) {
      print('📄 DocumentMessageService: ❌ Failed to process document: $e');
      return null;
    }
  }

  /// Compress document with specified options
  Future<Map<String, dynamic>?> _compressDocument(
    String documentFilePath,
    DocumentCompressionOptions options,
  ) async {
    try {
      _isProcessing = true;
      _processingProgressController =
          StreamController<DocumentProcessingProgress>.broadcast();

      print('📄 DocumentMessageService: Starting document compression');

      // Emit compression started
      _processingProgressController?.add(DocumentProcessingProgress(
        progress: 0.0,
        status: DocumentProcessingStatus.started,
        message: 'Initializing compression...',
        operation: DocumentOperation.compression,
      ));

      // Simulate compression progress (in real implementation, this would use compression library)
      for (int i = 1; i <= 8; i++) {
        await Future.delayed(Duration(milliseconds: 250)); // Simulate work

        _processingProgressController?.add(DocumentProcessingProgress(
          progress: i / 8.0,
          status: DocumentProcessingStatus.processing,
          message: 'Compressing document... ${(i * 12.5).toInt()}%',
          operation: DocumentOperation.compression,
        ));
      }

      // Create compressed file path
      final tempDir = await getTemporaryDirectory();
      final compressedFileName =
          'compressed_${path.basename(documentFilePath)}';
      final compressedFilePath = path.join(tempDir.path, compressedFileName);

      // Simulate file size reduction (in real implementation, this would be actual compression)
      final originalFile = File(documentFilePath);
      final originalSize = await originalFile.length();
      final compressedSize = (originalSize * options.qualityFactor).round();

      // Copy file as "compressed" (in real implementation, this would be actual compression)
      await originalFile.copy(compressedFilePath);

      // Emit compression completed
      _processingProgressController?.add(DocumentProcessingProgress(
        progress: 1.0,
        status: DocumentProcessingStatus.completed,
        message: 'Compression completed successfully',
        operation: DocumentOperation.compression,
        result: {
          'compressed_file_path': compressedFilePath,
          'original_size': originalSize,
          'compressed_size': compressedSize,
        },
      ));

      print('📄 DocumentMessageService: ✅ Document compression completed');

      return {
        'file_path': compressedFilePath,
        'file_size': compressedSize,
        'compression_ratio': originalSize / compressedSize,
      };
    } catch (e) {
      print('📄 DocumentMessageService: ❌ Document compression failed: $e');

      _processingProgressController?.add(DocumentProcessingProgress(
        progress: 0.0,
        status: DocumentProcessingStatus.failed,
        message: 'Compression failed: $e',
        operation: DocumentOperation.compression,
      ));

      return null;
    } finally {
      _isProcessing = false;
      await _processingProgressController?.close();
      _processingProgressController = null;
    }
  }

  /// Generate thumbnail for document
  Future<String?> _generateDocumentThumbnail(String documentFilePath) async {
    try {
      print('📄 DocumentMessageService: Generating thumbnail for document');

      // In real implementation, this would extract a preview from the document
      // For now, we'll create a placeholder thumbnail

      final tempDir = await getTemporaryDirectory();
      final thumbnailFileName =
          'thumb_${path.basenameWithoutExtension(documentFilePath)}.png';
      final thumbnailPath = path.join(tempDir.path, thumbnailFileName);

      // Simulate thumbnail creation (in real implementation, this would extract a preview)
      // For now, we'll create a placeholder file
      final thumbnailFile = File(thumbnailPath);
      await thumbnailFile
          .writeAsBytes(Uint8List(0)); // Empty file as placeholder

      print('📄 DocumentMessageService: ✅ Thumbnail generated: $thumbnailPath');
      return thumbnailPath;
    } catch (e) {
      print('📄 DocumentMessageService: ❌ Failed to generate thumbnail: $e');
      return null;
    }
  }

  /// Extract document metadata
  Future<Map<String, dynamic>?> _extractDocumentMetadata(
      String documentFilePath) async {
    try {
      final documentFile = File(documentFilePath);
      if (!await documentFile.exists()) return null;

      // In real implementation, this would use document processing library to extract metadata
      // For now, return placeholder data based on file extension
      final extension = path.extension(documentFilePath).toLowerCase();

      switch (extension) {
        case '.pdf':
          return {
            'page_count': 10,
            'author': 'Document Author',
            'title': 'Document Title',
            'subject': 'Document Subject',
            'keywords': ['keyword1', 'keyword2'],
            'created_date': DateTime.now().millisecondsSinceEpoch,
            'modified_date': DateTime.now().millisecondsSinceEpoch,
          };
        case '.doc':
        case '.docx':
          return {
            'page_count': 5,
            'author': 'Document Author',
            'title': 'Word Document',
            'word_count': 1500,
            'created_date': DateTime.now().millisecondsSinceEpoch,
            'modified_date': DateTime.now().millisecondsSinceEpoch,
          };
        case '.xls':
        case '.xlsx':
          return {
            'page_count': 3,
            'author': 'Document Author',
            'title': 'Excel Spreadsheet',
            'sheet_count': 2,
            'created_date': DateTime.now().millisecondsSinceEpoch,
            'modified_date': DateTime.now().millisecondsSinceEpoch,
          };
        case '.ppt':
        case '.pptx':
          return {
            'page_count': 8,
            'author': 'Document Author',
            'title': 'PowerPoint Presentation',
            'slide_count': 8,
            'created_date': DateTime.now().millisecondsSinceEpoch,
            'modified_date': DateTime.now().millisecondsSinceEpoch,
          };
        default:
          return {
            'page_count': 1,
            'author': 'Unknown',
            'title': 'Document',
            'created_date': DateTime.now().millisecondsSinceEpoch,
            'modified_date': DateTime.now().millisecondsSinceEpoch,
          };
      }
    } catch (e) {
      print(
          '📄 DocumentMessageService: ❌ Failed to extract document metadata: $e');
      return null;
    }
  }

  /// Simulate document selection (placeholder for file picker integration)
  Future<String?> _simulateDocumentSelection(
      DocumentSelectionOptions options) async {
    try {
      // In real implementation, this would open the file picker
      // For now, we'll create a placeholder document file
      final tempDir = await getTemporaryDirectory();
      final fileName = 'document_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final documentPath = path.join(tempDir.path, fileName);

      // Create a placeholder file
      final documentFile = File(documentPath);
      await documentFile.writeAsBytes(Uint8List(5120)); // 5KB placeholder

      print(
          '📄 DocumentMessageService: ✅ Simulated document selection: $documentPath');
      return documentPath;
    } catch (e) {
      print(
          '📄 DocumentMessageService: ❌ Simulated document selection failed: $e');
      return null;
    }
  }

  /// Get MIME type from file extension
  String _getMimeType(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    switch (extension) {
      case '.pdf':
        return 'application/pdf';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.xls':
        return 'application/vnd.ms-excel';
      case '.xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.ppt':
        return 'application/vnd.ms-powerpoint';
      case '.pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case '.txt':
        return 'text/plain';
      case '.rtf':
        return 'application/rtf';
      case '.odt':
        return 'application/vnd.oasis.opendocument.text';
      case '.ods':
        return 'application/vnd.oasis.opendocument.spreadsheet';
      case '.odp':
        return 'application/vnd.oasis.opendocument.presentation';
      default:
        return 'application/octet-stream';
    }
  }

  /// Get document type from file extension
  String _getDocumentType(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    switch (extension) {
      case '.pdf':
        return 'PDF Document';
      case '.doc':
      case '.docx':
        return 'Word Document';
      case '.xls':
      case '.xlsx':
        return 'Excel Spreadsheet';
      case '.ppt':
      case '.pptx':
        return 'PowerPoint Presentation';
      case '.txt':
        return 'Text Document';
      case '.rtf':
        return 'Rich Text Document';
      case '.odt':
        return 'OpenDocument Text';
      case '.ods':
        return 'OpenDocument Spreadsheet';
      case '.odp':
        return 'OpenDocument Presentation';
      default:
        return 'Document';
    }
  }

  /// Validate document file
  bool _validateDocumentFile(String documentFilePath) {
    if (documentFilePath.isEmpty) return false;

    final extension = path.extension(documentFilePath).toLowerCase();
    final supportedFormats = [
      '.pdf',
      '.doc',
      '.docx',
      '.xls',
      '.xlsx',
      '.ppt',
      '.pptx',
      '.txt',
      '.rtf',
      '.odt',
      '.ods',
      '.odp'
    ];

    if (!supportedFormats.contains(extension)) return false;

    return true;
  }

  /// Delete a document message
  Future<bool> deleteDocumentMessage(String messageId) async {
    try {
      print('📄 DocumentMessageService: Deleting document message: $messageId');

      // Get the message
      final message = await _getMessageById(messageId);
      if (message == null) {
        print('📄 DocumentMessageService: ❌ Message not found: $messageId');
        return false;
      }

      // Check if it's a document message
      if (message.type != MessageType.document) {
        print(
            '📄 DocumentMessageService: ❌ Not a document message: ${message.type}');
        return false;
      }

      // Mark message as deleted
      final deletedMessage = message.copyWith(
        status: MessageStatus.deleted,
        deletedAt: DateTime.now(),
      );

      await _storageService.saveMessage(deletedMessage);

      print(
          '📄 DocumentMessageService: ✅ Document message deleted: $messageId');
      return true;
    } catch (e) {
      print(
          '📄 DocumentMessageService: ❌ Failed to delete document message: $e');
      return false;
    }
  }

  /// Get document message statistics
  Future<Map<String, dynamic>> getDocumentMessageStats() async {
    try {
      // This would typically query the storage service for statistics
      // For now, return placeholder data
      return {
        'total_document_messages': 0,
        'total_file_size': 0,
        'average_file_size': 0,
        'compression_ratio': 1.0,
        'total_compressed_documents': 0,
        'total_uncompressed_documents': 0,
        'format_distribution': {
          'pdf': 0,
          'doc': 0,
          'docx': 0,
          'xls': 0,
          'xlsx': 0,
          'ppt': 0,
          'pptx': 0,
          'txt': 0,
          'rtf': 0,
          'odt': 0,
          'ods': 0,
          'odp': 0,
        },
      };
    } catch (e) {
      print(
          '📄 DocumentMessageService: ❌ Failed to get document message stats: $e');
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
      print('📄 DocumentMessageService: ❌ Failed to update conversation: $e');
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
      print('📄 DocumentMessageService: ❌ Failed to get message: $e');
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
    print('📄 DocumentMessageService: ✅ Service disposed');
  }
}

/// Options for document selection
class DocumentSelectionOptions {
  final bool allowMultiple;
  final List<String> allowedFormats; // e.g., ['pdf', 'doc', 'docx']
  final int maxFileSize; // in bytes
  final DocumentCompressionOptions compressionOptions;

  const DocumentSelectionOptions({
    this.allowMultiple = false,
    this.allowedFormats = const [
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'txt',
      'rtf',
      'odt',
      'ods',
      'odp'
    ],
    this.maxFileSize = 50 * 1024 * 1024, // 50MB default
    this.compressionOptions = const DocumentCompressionOptions(),
  });
}

/// Options for document compression
class DocumentCompressionOptions {
  final bool enableCompression;
  final int maxFileSize; // in bytes
  final double qualityFactor; // 0.0 to 1.0 (1.0 = no compression)
  final String compressionMethod; // e.g., 'zip', '7z', 'rar'
  final bool preserveMetadata;
  final bool createBackup;

  const DocumentCompressionOptions({
    this.enableCompression = true,
    this.maxFileSize = 10 * 1024 * 1024, // 10MB default
    this.qualityFactor = 0.8, // 80% quality
    this.compressionMethod = 'zip',
    this.preserveMetadata = true,
    this.createBackup = false,
  });
}

/// Data class for document processing progress
class DocumentProcessingProgress {
  final double progress; // 0.0 to 1.0
  final DocumentProcessingStatus status;
  final String message;
  final DocumentOperation operation;
  final Map<String, dynamic>? result;

  DocumentProcessingProgress({
    required this.progress,
    required this.status,
    required this.message,
    required this.operation,
    this.result,
  });
}

/// Enum for document processing status
enum DocumentProcessingStatus {
  started,
  processing,
  completed,
  failed,
  cancelled,
}

/// Enum for document operations
enum DocumentOperation {
  compression,
  thumbnailGeneration,
  metadataExtraction,
  formatConversion,
  validation,
}
