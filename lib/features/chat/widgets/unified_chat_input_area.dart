import 'dart:async';
import 'package:flutter/material.dart';

/// Modern chat input area with WhatsApp-like design
class UnifiedChatInputArea extends StatefulWidget {
  final Function(String) onTextMessageSent;
  final Function(bool) isTyping;
  final bool isConnected;

  const UnifiedChatInputArea({
    super.key,
    required this.onTextMessageSent,
    required this.isTyping,
    required this.isConnected,
  });

  @override
  State<UnifiedChatInputArea> createState() => _UnifiedChatInputAreaState();
}

class _UnifiedChatInputAreaState extends State<UnifiedChatInputArea> {
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
        color: Colors.white, // Match main screen background
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).padding.bottom +
              12, // Add bottom padding for home indicator
        ),
        child: Row(
          children: [
            // Text input field
            Expanded(
              child: _buildTextInputField(),
            ),

            const SizedBox(width: 12),

            // Send button
            _buildSendButton(),
          ],
        ),
      ),
    );
  }

  /// Build text input field
  Widget _buildTextInputField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50], // Lighter background to match main screen
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.grey[200]!, // Lighter border to match main screen
        ),
      ),
      child: TextField(
        style: const TextStyle(
            color: Colors.black), // Match main screen text color
        controller: _textController,
        focusNode: _focusNode,
        maxLines: null,
        textCapitalization: TextCapitalization.sentences,
        enabled: widget.isConnected,
        onChanged: (text) {
          // Immediate response to text changes
          _onTextChanged();
        },
        decoration: InputDecoration(
          hintText: widget.isConnected
              ? 'Type a message...'
              : 'No internet connection',
          hintStyle: TextStyle(
            color: widget.isConnected
                ? Colors.grey[400]
                : Colors.grey[300], // Lighter hint text to match main screen
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        onSubmitted: (text) {
          if (text.trim().isNotEmpty && widget.isConnected) {
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
        final isEnabled = hasTextValue && widget.isConnected;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 40,
          height: 40,
          child: IconButton(
            onPressed: isEnabled ? _sendTextMessage : null,
            icon: Icon(
              Icons.send,
              color: isEnabled
                  ? const Color(0xFFFF6B35) // Use app's primary orange color
                  : Colors.grey[400],
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
    if (text.isEmpty || !widget.isConnected) return;

    widget.onTextMessageSent(text);
    _textController.clear();

    // Hide keyboard and remove focus
    _focusNode.unfocus();
  }
}
