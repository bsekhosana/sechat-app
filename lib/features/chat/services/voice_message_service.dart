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

/// Service for handling voice message recording, playback, and management
class VoiceMessageService {
  static VoiceMessageService? _instance;
  static VoiceMessageService get instance =>
      _instance ??= VoiceMessageService._();

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

  // Playback state
  bool _isPlaying = false;
  String? _currentlyPlayingMessageId;
  StreamController<PlaybackState>? _playbackController;

  VoiceMessageService._();

  /// Stream for recording duration updates
  Stream<int>? get recordingDurationStream => _durationController?.stream;

  /// Stream for playback state updates
  Stream<PlaybackState>? get playbackStateStream => _playbackController?.stream;

  /// Check if currently recording
  bool get isRecording => _isRecording;

  /// Check if currently playing
  bool get isPlaying => _isPlaying;

  /// Get current recording duration
  int get currentRecordingDuration => _recordingDuration;

  /// Get currently playing message ID
  String? get currentlyPlayingMessageId => _currentlyPlayingMessageId;

  /// Start recording a voice message
  Future<bool> startRecording({
    required String conversationId,
    required String recipientId,
  }) async {
    try {
      if (_isRecording) {
        print(
            '🎤 VoiceMessageService: Already recording, stopping current recording');
        await stopRecording();
      }

      print('🎤 VoiceMessageService: Starting voice recording');

      // Initialize recording state
      _isRecording = true;
      _recordingDuration = 0;
      _durationController = StreamController<int>.broadcast();

      // Create temporary recording file
      final tempDir = await getTemporaryDirectory();
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentRecordingPath = path.join(tempDir.path, fileName);

      // Start recording timer
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _recordingDuration++;
        _durationController?.add(_recordingDuration);

        // Check if maximum duration reached (2 minutes = 120 seconds)
        if (_recordingDuration >= 120) {
          print(
              '🎤 VoiceMessageService: Maximum recording duration reached (2 minutes)');
          stopRecording();
        }
      });

      print('🎤 VoiceMessageService: ✅ Voice recording started');
      return true;
    } catch (e) {
      print('🎤 VoiceMessageService: ❌ Failed to start recording: $e');
      _resetRecordingState();
      return false;
    }
  }

  /// Stop recording and process the voice message
  Future<Message?> stopRecording() async {
    try {
      if (!_isRecording) {
        print('🎤 VoiceMessageService: Not currently recording');
        return null;
      }

      print('🎤 VoiceMessageService: Stopping voice recording');

      // Stop recording timer
      _recordingTimer?.cancel();
      _recordingTimer = null;

      // Stop duration stream
      await _durationController?.close();
      _durationController = null;

      // Check if recording is too short
      if (_recordingDuration < 1) {
        print('🎤 VoiceMessageService: Recording too short, discarding');
        _resetRecordingState();
        return null;
      }

      // Process the recorded audio
      final message = await _processRecordedAudio();

      _resetRecordingState();
      return message;
    } catch (e) {
      print('🎤 VoiceMessageService: ❌ Failed to stop recording: $e');
      _resetRecordingState();
      return null;
    }
  }

  /// Process the recorded audio file
  Future<Message?> _processRecordedAudio() async {
    try {
      if (_currentRecordingPath == null) return null;

      final audioFile = File(_currentRecordingPath!);
      if (!await audioFile.exists()) {
        print('🎤 VoiceMessageService: ❌ Recorded audio file not found');
        return null;
      }

      // Get file size
      final fileSize = await audioFile.length();

      // Check file size limit (10MB)
      if (fileSize > 10 * 1024 * 1024) {
        print(
            '🎤 VoiceMessageService: ❌ Audio file too large: ${fileSize} bytes');
        return null;
      }

      // Create media message
      final mediaMessage = MediaMessage(
        messageId: const Uuid().v4(),
        type: MediaType.voice,
        filePath: _currentRecordingPath!,
        fileName: path.basename(_currentRecordingPath!),
        mimeType: 'audio/m4a',
        fileSize: fileSize,
        duration: _recordingDuration,
        isCompressed: false, // Raw recording
      );

      // Save media message to storage
      final audioData = await audioFile.readAsBytes();
      await _storageService.saveMediaMessage(mediaMessage, audioData);

      // Create voice message
      final message = Message(
        conversationId: 'conversation_id', // Will be set by caller
        senderId: _getCurrentUserId(),
        recipientId: 'recipient_id', // Will be set by caller
        type: MessageType.voice,
        content: {
          'duration': _recordingDuration,
          'file_size': fileSize,
          'mime_type': 'audio/m4a',
          'is_compressed': false,
          'recording_timestamp': DateTime.now().millisecondsSinceEpoch,
        },
        status: MessageStatus.sending,
        fileSize: fileSize,
        mimeType: 'audio/m4a',
      );

      print('🎤 VoiceMessageService: ✅ Voice message processed successfully');
      return message;
    } catch (e) {
      print('🎤 VoiceMessageService: ❌ Failed to process recorded audio: $e');
      return null;
    }
  }

  /// Send a voice message
  Future<Message?> sendVoiceMessage({
    required String conversationId,
    required String recipientId,
    required String audioFilePath,
    required int duration,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      print('🎤 VoiceMessageService: Sending voice message to $recipientId');

      // Validate voice message
      if (!_validateVoiceMessage(audioFilePath, duration)) {
        throw Exception(
            'Invalid voice message: File not found or duration invalid');
      }

      // Get audio file
      final audioFile = File(audioFilePath);
      final fileSize = await audioFile.length();

      // Create media message
      final mediaMessage = MediaMessage(
        messageId: const Uuid().v4(),
        type: MediaType.voice,
        filePath: audioFilePath,
        fileName: path.basename(audioFilePath),
        mimeType: 'audio/m4a',
        fileSize: fileSize,
        duration: duration,
        isCompressed: false,
      );

      // Save media message to storage
      final audioData = await audioFile.readAsBytes();
      await _storageService.saveMediaMessage(mediaMessage, audioData);

      // Create voice message
      final message = Message(
        conversationId: conversationId,
        senderId: _getCurrentUserId(),
        recipientId: recipientId,
        type: MessageType.voice,
        content: {
          'duration': duration,
          'file_size': fileSize,
          'mime_type': 'audio/m4a',
          'is_compressed': false,
          'recording_timestamp': DateTime.now().millisecondsSinceEpoch,
        },
        status: MessageStatus.sending,
        fileSize: fileSize,
        mimeType: 'audio/m4a',
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
          '🎤 VoiceMessageService: ✅ Voice message sent successfully: ${message.id}');
      return message;
    } catch (e) {
      print('🎤 VoiceMessageService: ❌ Failed to send voice message: $e');
      rethrow;
    }
  }

  /// Play a voice message
  Future<bool> playVoiceMessage(String messageId) async {
    try {
      if (_isPlaying) {
        print(
            '🎤 VoiceMessageService: Already playing, stopping current playback');
        await stopPlayback();
      }

      print('🎤 VoiceMessageService: Playing voice message: $messageId');

      // Get media message
      final mediaMessage = await _storageService.getMediaMessage(messageId);
      if (mediaMessage == null) {
        print('🎤 VoiceMessageService: ❌ Media message not found: $messageId');
        return false;
      }

      // Check if it's a voice message
      if (mediaMessage.type != MediaType.voice) {
        print(
            '🎤 VoiceMessageService: ❌ Not a voice message: ${mediaMessage.type}');
        return false;
      }

      // Initialize playback state
      _isPlaying = true;
      _currentlyPlayingMessageId = messageId;
      _playbackController = StreamController<PlaybackState>.broadcast();

      // Simulate playback (in real implementation, this would use audio player)
      _playbackController?.add(PlaybackState(
        messageId: messageId,
        isPlaying: true,
        position: 0,
        duration: mediaMessage.duration ?? 0,
        state: PlaybackStateType.playing,
      ));

      print('🎤 VoiceMessageService: ✅ Voice message playback started');
      return true;
    } catch (e) {
      print('🎤 VoiceMessageService: ❌ Failed to play voice message: $e');
      _resetPlaybackState();
      return false;
    }
  }

  /// Pause playback
  Future<bool> pausePlayback() async {
    try {
      if (!_isPlaying) {
        print('🎤 VoiceMessageService: Not currently playing');
        return false;
      }

      print('🎤 VoiceMessageService: Pausing playback');

      _playbackController?.add(PlaybackState(
        messageId: _currentlyPlayingMessageId!,
        isPlaying: false,
        position: 0, // Current position would be tracked in real implementation
        duration: 0,
        state: PlaybackStateType.paused,
      ));

      print('🎤 VoiceMessageService: ✅ Playback paused');
      return true;
    } catch (e) {
      print('🎤 VoiceMessageService: ❌ Failed to pause playback: $e');
      return false;
    }
  }

  /// Resume playback
  Future<bool> resumePlayback() async {
    try {
      if (_isPlaying) {
        print('🎤 VoiceMessageService: Already playing');
        return false;
      }

      if (_currentlyPlayingMessageId == null) {
        print('🎤 VoiceMessageService: No message to resume');
        return false;
      }

      print('🎤 VoiceMessageService: Resuming playback');

      _isPlaying = true;

      _playbackController?.add(PlaybackState(
        messageId: _currentlyPlayingMessageId!,
        isPlaying: true,
        position: 0, // Current position would be tracked in real implementation
        duration: 0,
        state: PlaybackStateType.playing,
      ));

      print('🎤 VoiceMessageService: ✅ Playback resumed');
      return true;
    } catch (e) {
      print('🎤 VoiceMessageService: ❌ Failed to resume playback: $e');
      return false;
    }
  }

  /// Stop playback
  Future<bool> stopPlayback() async {
    try {
      if (!_isPlaying) {
        print('🎤 VoiceMessageService: Not currently playing');
        return false;
      }

      print('🎤 VoiceMessageService: Stopping playback');

      _playbackController?.add(PlaybackState(
        messageId: _currentlyPlayingMessageId!,
        isPlaying: false,
        position: 0,
        duration: 0,
        state: PlaybackStateType.stopped,
      ));

      _resetPlaybackState();

      print('🎤 VoiceMessageService: ✅ Playback stopped');
      return true;
    } catch (e) {
      print('🎤 VoiceMessageService: ❌ Failed to stop playback: $e');
      return false;
    }
  }

  /// Seek to position in audio
  Future<bool> seekToPosition(String messageId, int positionSeconds) async {
    try {
      if (_currentlyPlayingMessageId != messageId) {
        print(
            '🎤 VoiceMessageService: Message not currently playing: $messageId');
        return false;
      }

      print('🎤 VoiceMessageService: Seeking to position: ${positionSeconds}s');

      // In real implementation, this would seek the audio player
      _playbackController?.add(PlaybackState(
        messageId: messageId,
        isPlaying: _isPlaying,
        position: positionSeconds,
        duration: 0,
        state:
            _isPlaying ? PlaybackStateType.playing : PlaybackStateType.paused,
      ));

      print(
          '🎤 VoiceMessageService: ✅ Seeked to position: ${positionSeconds}s');
      return true;
    } catch (e) {
      print('🎤 VoiceMessageService: ❌ Failed to seek: $e');
      return false;
    }
  }

  /// Set playback speed
  Future<bool> setPlaybackSpeed(String messageId, double speed) async {
    try {
      if (_currentlyPlayingMessageId != messageId) {
        print(
            '🎤 VoiceMessageService: Message not currently playing: $messageId');
        return false;
      }

      // Validate speed (0.5x to 2.0x)
      if (speed < 0.5 || speed > 2.0) {
        print('🎤 VoiceMessageService: Invalid playback speed: $speed');
        return false;
      }

      print('🎤 VoiceMessageService: Setting playback speed: ${speed}x');

      // In real implementation, this would set the audio player speed
      _playbackController?.add(PlaybackState(
        messageId: messageId,
        isPlaying: _isPlaying,
        position: 0,
        duration: 0,
        state:
            _isPlaying ? PlaybackStateType.playing : PlaybackStateType.paused,
        playbackSpeed: speed,
      ));

      print('🎤 VoiceMessageService: ✅ Playback speed set to: ${speed}x');
      return true;
    } catch (e) {
      print('🎤 VoiceMessageService: ❌ Failed to set playback speed: $e');
      return false;
    }
  }

  /// Delete a voice message
  Future<bool> deleteVoiceMessage(String messageId) async {
    try {
      print('🎤 VoiceMessageService: Deleting voice message: $messageId');

      // Get the message
      final message = await _getMessageById(messageId);
      if (message == null) {
        print('🎤 VoiceMessageService: ❌ Message not found: $messageId');
        return false;
      }

      // Check if it's a voice message
      if (message.type != MessageType.voice) {
        print('🎤 VoiceMessageService: ❌ Not a voice message: ${message.type}');
        return false;
      }

      // Stop playback if this message is currently playing
      if (_currentlyPlayingMessageId == messageId) {
        await stopPlayback();
      }

      // Mark message as deleted
      final deletedMessage = message.copyWith(
        status: MessageStatus.deleted,
        deletedAt: DateTime.now(),
      );

      await _storageService.saveMessage(deletedMessage);

      print('🎤 VoiceMessageService: ✅ Voice message deleted: $messageId');
      return true;
    } catch (e) {
      print('🎤 VoiceMessageService: ❌ Failed to delete voice message: $e');
      return false;
    }
  }

  /// Get voice message statistics
  Future<Map<String, dynamic>> getVoiceMessageStats() async {
    try {
      // This would typically query the storage service for statistics
      // For now, return placeholder data
      return {
        'total_voice_messages': 0,
        'total_duration': 0,
        'average_duration': 0,
        'total_file_size': 0,
        'compression_ratio': 1.0,
      };
    } catch (e) {
      print('🎤 VoiceMessageService: ❌ Failed to get voice message stats: $e');
      return {};
    }
  }

  /// Validate voice message
  bool _validateVoiceMessage(String audioFilePath, int duration) {
    if (audioFilePath.isEmpty) return false;
    if (duration <= 0 || duration > 120) return false; // Max 2 minutes
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
    _currentRecordingPath = null;
  }

  /// Reset playback state
  void _resetPlaybackState() {
    _isPlaying = false;
    _currentlyPlayingMessageId = null;
    _playbackController?.close();
    _playbackController = null;
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
      print('🎤 VoiceMessageService: ❌ Failed to update conversation: $e');
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
      print('🎤 VoiceMessageService: ❌ Failed to get message: $e');
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
    _resetPlaybackState();
    print('🎤 VoiceMessageService: ✅ Service disposed');
  }
}

/// Data class for playback state
class PlaybackState {
  final String messageId;
  final bool isPlaying;
  final int position; // in seconds
  final int duration; // in seconds
  final PlaybackStateType state;
  final double? playbackSpeed;

  PlaybackState({
    required this.messageId,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.state,
    this.playbackSpeed,
  });
}

/// Enum for playback state types
enum PlaybackStateType {
  playing,
  paused,
  stopped,
  buffering,
  error,
}
