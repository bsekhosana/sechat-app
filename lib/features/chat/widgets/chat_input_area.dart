import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';
import '../services/contact_message_service.dart' show ContactData;
import 'input_media_selector.dart';
import 'input_emoticon_selector.dart';
import 'input_voice_recorder.dart';

/// Comprehensive chat input area for all message types
class ChatInputArea extends StatefulWidget {
  final Function(String) onTextMessageSent;
  final Function(int, String) onVoiceMessageRecorded;
  final Function(String) onImageSelected;
  final Function(String) onVideoSelected;
  final Function(String) onDocumentSelected;
  final Function(double, double) onLocationShared;
  final Function(ContactData) onContactShared;
  final Function(String) onEmoticonSelected;
  final Function(bool) isTyping;

  const ChatInputArea({
    super.key,
    required this.onTextMessageSent,
    required this.onVoiceMessageRecorded,
    required this.onImageSelected,
    required this.onVideoSelected,
    required this.onDocumentSelected,
    required this.onLocationShared,
    required this.onContactShared,
    required this.onEmoticonSelected,
    required this.isTyping,
  });

  @override
  State<ChatInputArea> createState() => _ChatInputAreaState();
}

class _ChatInputAreaState extends State<ChatInputArea>
    with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  bool _isRecording = false;
  bool _isExpanded = false;
  bool _isEmoticonSelectorOpen = false;
  bool _isMediaSelectorOpen = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupTextListener();
  }

  void _initializeAnimations() {
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _expandAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    ));
  }

  void _setupTextListener() {
    _textController.addListener(() {
      final isTyping = _textController.text.isNotEmpty;
      widget.isTyping(isTyping);
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _expandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Media selector (when open)
            if (_isMediaSelectorOpen) _buildMediaSelector(),

            // Emoticon selector (when open)
            if (_isEmoticonSelectorOpen) _buildEmoticonSelector(),

            // Main input area
            _buildMainInputArea(),
          ],
        ),
      ),
    );
  }

  /// Build media selector
  Widget _buildMediaSelector() {
    return InputMediaSelector(
      onImageSelected: (path) {
        setState(() {
          _isMediaSelectorOpen = false;
        });
        widget.onImageSelected(path);
      },
      onVideoSelected: (path) {
        setState(() {
          _isMediaSelectorOpen = false;
        });
        widget.onVideoSelected(path);
      },
      onDocumentSelected: (path) {
        setState(() {
          _isMediaSelectorOpen = false;
        });
        widget.onDocumentSelected(path);
      },
      onLocationShared: (lat, lng) {
        setState(() {
          _isMediaSelectorOpen = false;
        });
        widget.onLocationShared(lat, lng);
      },
      onContactShared: (contactData) {
        setState(() {
          _isMediaSelectorOpen = false;
        });
        widget.onContactShared(contactData);
      },
      onClose: () {
        setState(() {
          _isMediaSelectorOpen = false;
        });
      },
    );
  }

  /// Build emoticon selector
  Widget _buildEmoticonSelector() {
    return InputEmoticonSelector(
      onEmoticonSelected: (emoticon) {
        setState(() {
          _isEmoticonSelectorOpen = false;
        });
        widget.onEmoticonSelected(emoticon);
      },
      onClose: () {
        setState(() {
          _isEmoticonSelectorOpen = false;
        });
      },
    );
  }

  /// Build main input area
  Widget _buildMainInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Voice recording button
          _buildVoiceRecordingButton(),

          const SizedBox(width: 12),

          // Text input field
          Expanded(
            child: _buildTextInputField(),
          ),

          const SizedBox(width: 12),

          // Emoticon button
          _buildEmoticonButton(),

          const SizedBox(width: 8),

          // Media button
          _buildMediaButton(),

          const SizedBox(width: 8),

          // Send button
          _buildSendButton(),
        ],
      ),
    );
  }

  /// Build voice recording button
  Widget _buildVoiceRecordingButton() {
    return GestureDetector(
      onTapDown: (_) => _startVoiceRecording(),
      onTapUp: (_) => _stopVoiceRecording(),
      onTapCancel: () => _cancelVoiceRecording(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _isRecording
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(
          _isRecording ? Icons.stop : Icons.mic,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  /// Build text input field
  Widget _buildTextInputField() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: TextField(
        controller: _textController,
        focusNode: _focusNode,
        maxLines: null,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: 'Type a message...',
          hintStyle: TextStyle(
            color:
                Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        onSubmitted: (text) {
          if (text.trim().isNotEmpty) {
            _sendTextMessage();
          }
        },
      ),
    );
  }

  /// Build emoticon button
  Widget _buildEmoticonButton() {
    return IconButton(
      onPressed: _toggleEmoticonSelector,
      icon: Icon(
        Icons.emoji_emotions,
        color: _isEmoticonSelectorOpen
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      tooltip: 'Emoticons',
    );
  }

  /// Build media button
  Widget _buildMediaButton() {
    return IconButton(
      onPressed: _toggleMediaSelector,
      icon: Icon(
        Icons.attach_file,
        color: _isMediaSelectorOpen
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      tooltip: 'Attach media',
    );
  }

  /// Build send button
  Widget _buildSendButton() {
    final hasText = _textController.text.trim().isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: hasText ? 40 : 0,
      height: 40,
      child: hasText
          ? IconButton(
              onPressed: _sendTextMessage,
              icon: Icon(
                Icons.send,
                color: Theme.of(context).colorScheme.primary,
              ),
              tooltip: 'Send message',
            )
          : null,
    );
  }

  /// Start voice recording
  void _startVoiceRecording() {
    setState(() {
      _isRecording = true;
    });

    // TODO: Integrate with VoiceMessageService
    print('🎤 Starting voice recording...');
  }

  /// Stop voice recording
  void _stopVoiceRecording() {
    if (!_isRecording) return;

    setState(() {
      _isRecording = false;
    });

    // TODO: Get recorded file path and duration from VoiceMessageService
    final duration = 30; // Placeholder duration in seconds
    final filePath = '/path/to/recorded/audio.m4a'; // Placeholder file path

    widget.onVoiceMessageRecorded(duration, filePath);
    print('🎤 Voice recording stopped');
  }

  /// Cancel voice recording
  void _cancelVoiceRecording() {
    if (!_isRecording) return;

    setState(() {
      _isRecording = false;
    });

    // TODO: Cancel recording in VoiceMessageService
    print('🎤 Voice recording cancelled');
  }

  /// Toggle emoticon selector
  void _toggleEmoticonSelector() {
    setState(() {
      _isEmoticonSelectorOpen = !_isEmoticonSelectorOpen;
      _isMediaSelectorOpen = false;
    });
  }

  /// Toggle media selector
  void _toggleMediaSelector() {
    setState(() {
      _isMediaSelectorOpen = !_isMediaSelectorOpen;
      _isEmoticonSelectorOpen = false;
    });
  }

  /// Send text message
  void _sendTextMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    widget.onTextMessageSent(text);
    _textController.clear();
    _focusNode.requestFocus();
  }
}
