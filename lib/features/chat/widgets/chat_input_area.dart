import 'dart:async';
import 'package:flutter/material.dart';
import '/../core/utils/logger.dart';

/// Simplified chat input area for text messages only
class ChatInputArea extends StatefulWidget {
  final Function(String) onTextMessageSent;
  final Function(bool) isTyping;

  const ChatInputArea({
    super.key,
    required this.onTextMessageSent,
    required this.isTyping,
  });

  @override
  State<ChatInputArea> createState() => _ChatInputAreaState();
}

class _ChatInputAreaState extends State<ChatInputArea> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _typingTimer;
  bool _lastTypingState = false;

  late final ValueNotifier<bool> hasText;

  @override
  void initState() {
    super.initState();
    hasText = ValueNotifier<bool>(_textController.text.trim().isNotEmpty);
    _textController.addListener(_onTextChanged);
    _setupTextListener();
  }

  void _onTextChanged() {
    final hasTextValue = _textController.text.trim().isNotEmpty;
    if (hasText.value != hasTextValue) {
      hasText.value = hasTextValue;
    }
  }

  void _setupTextListener() {
    _textController.addListener(() {
      final isTyping = _textController.text.isNotEmpty;

      // Only send typing indicator if state changed
      if (isTyping != _lastTypingState) {
        _lastTypingState = isTyping;

        // Cancel previous timer
        _typingTimer?.cancel();

        if (isTyping) {
          // Send typing started immediately
          widget.isTyping(true);
        } else {
          // Delay typing stopped to avoid rapid on/off notifications
          _typingTimer = Timer(const Duration(milliseconds: 1000), () {
            if (_textController.text.isEmpty) {
              widget.isTyping(false);
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    _textController.removeListener(_onTextChanged);
    hasText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, // White background
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Text input field (maximized space)
              Expanded(
                child: _buildTextInputField(),
              ),

              const SizedBox(width: 12),

              // Send button
              _buildSendButton(),
            ],
          ),
        ),
      ),
    );
  }

  /// Build text input field
  Widget _buildTextInputField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100], // Light grey input background
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.grey[300]!, // Light grey border
        ),
      ),
      child: TextField(
        // text input color grey
        style: TextStyle(color: Colors.grey[800]),
        controller: _textController,
        focusNode: _focusNode,
        maxLines: null,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (text) {
          // Immediate response to text changes
          _onTextChanged();
        },
        decoration: InputDecoration(
          hintText: 'Type a message...',
          hintStyle: TextStyle(
            color: Colors.grey[500], // Light grey hint text
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

  /// Build send button
  Widget _buildSendButton() {
    return ValueListenableBuilder<bool>(
      valueListenable: hasText,
      builder: (context, hasTextValue, child) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 40,
          height: 40,
          child: IconButton(
            onPressed: hasTextValue ? _sendTextMessage : null,
            icon: Icon(
              Icons.send,
              color: hasTextValue
                  ? Theme.of(context)
                      .colorScheme
                      .primary // Keep orange when active
                  : Colors.grey[400], // Grey when inactive
            ),
            tooltip: 'Send message',
          ),
        );
      },
    );
  }

  /// Send text message
  void _sendTextMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    Logger.debug('📱 ChatInputArea: 🔧 _sendTextMessage called with: "$text"');
    Logger.info('📱 ChatInputArea:  onTextMessageSent callback: SET');
    Logger.info('📱 ChatInputArea:  Text length: ${text.length}');

    widget.onTextMessageSent(text);
    _textController.clear();

    Logger.success('📱 ChatInputArea:  Message sent to callback, text cleared');

    // Hide keyboard and remove focus
    _focusNode.unfocus();
  }
}
