import 'package:flutter/material.dart';

import '../models/message.dart';
import '../../../core/services/encryption_service.dart';

/// Widget for displaying text message bubbles with modern Material 3 design
class TextMessageBubble extends StatefulWidget {
  final Message message;
  final bool isFromCurrentUser;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TextMessageBubble({
    super.key,
    required this.message,
    required this.isFromCurrentUser,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<TextMessageBubble> createState() => _TextMessageBubbleState();
}

class _TextMessageBubbleState extends State<TextMessageBubble> {
  String? _decryptedText;
  bool _isDecrypting = false;
  bool _hasDecryptionError = false;
  String? _lastProcessedMessageId;

  @override
  void initState() {
    super.initState();
    _decryptMessageIfNeeded();
  }

  @override
  void didUpdateWidget(TextMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only decrypt if message changed
    if (oldWidget.message.id != widget.message.id) {
      _decryptedText = null;
      _isDecrypting = false;
      _hasDecryptionError = false;
      _lastProcessedMessageId = null;
      _decryptMessageIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use cached decrypted text or show appropriate status
    String displayText;

    if (_hasDecryptionError) {
      // Show more helpful error message based on message type
      if (widget.message.metadata?['isFromCurrentUser'] == true) {
        displayText = '[Your message - tap to retry decryption]';
      } else {
        // Check if this is an encrypted message that failed decryption
        if (widget.message.content.containsKey('isIncomingEncrypted') &&
            widget.message.content['isIncomingEncrypted'] == true) {
          displayText = '[Encrypted message - decryption failed]';
        } else {
          displayText = '[Message content unavailable]';
        }
      }
    } else if (_decryptedText != null) {
      displayText = _decryptedText!;
    } else if (_isDecrypting) {
      displayText = 'Decrypting message...';
    } else if (widget.message.isEncrypted) {
      displayText = '[Encrypted Message]';
    } else {
      // Non-encrypted message
      displayText = widget.message.content['text'] as String? ??
          'Message content unavailable';
    }

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: widget.isFromCurrentUser
              ? Theme.of(context)
                  .colorScheme
                  .primary // Keep orange for current user
              : Colors.grey[100], // Light grey for received messages
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(widget.isFromCurrentUser ? 20 : 8),
            bottomRight: Radius.circular(widget.isFromCurrentUser ? 8 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reply preview (if this is a reply)
            if (widget.message.replyToMessageId != null) ...[
              _buildReplyPreview(context),
              const SizedBox(height: 10),
            ],

            // Main text content
            GestureDetector(
              onTap: _hasDecryptionError ? _retryDecryption : null,
              child: Text(
                displayText,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: widget.isFromCurrentUser
                          ? Colors.white // White text on orange background
                          : Colors
                              .grey[800], // Dark grey text on light background
                      height: 1.5,
                      fontSize: 15,
                      decoration:
                          _hasDecryptionError ? TextDecoration.underline : null,
                      decorationColor: widget.isFromCurrentUser
                          ? Colors.white.withOpacity(0.7)
                          : Colors.blue.withOpacity(0.7),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build reply preview with modern design
  Widget _buildReplyPreview(BuildContext context) {
    final replyText =
        widget.message.content['replyText'] as String? ?? 'Reply to message';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: widget.isFromCurrentUser
            ? Colors.white.withOpacity(0.15)
            : Colors.grey[200], // Light grey for reply background
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.isFromCurrentUser
              ? Colors.white.withOpacity(0.25)
              : Colors.grey[300]!, // Grey border for reply
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Reply indicator
          Icon(
            Icons.reply,
            size: 16,
            color: widget.isFromCurrentUser
                ? Colors.white.withOpacity(0.8)
                : Colors.grey[600], // Grey for reply icon
          ),
          const SizedBox(width: 6),
          // Reply text
          Expanded(
            child: Text(
              replyText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: widget.isFromCurrentUser
                        ? Colors.white.withOpacity(0.8)
                        : Colors.grey[600], // Grey for reply text
                    fontSize: 13,
                    height: 1.3,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Decrypt message if needed (only once per message)
  Future<void> _decryptMessageIfNeeded() async {
    // Prevent processing the same message multiple times
    if (_lastProcessedMessageId == widget.message.id) {
      return;
    }

    _lastProcessedMessageId = widget.message.id;

    // Check if message already has decrypted text (legacy messages)
    if (widget.message.content.containsKey('decryptedText')) {
      final legacyDecryptedText =
          widget.message.content['decryptedText'] as String?;
      if (legacyDecryptedText != null && legacyDecryptedText.isNotEmpty) {
        _decryptedText = legacyDecryptedText;
        if (mounted) {
          setState(() {});
        }
        return;
      }
    }

    // Only decrypt if we haven't already and the message is encrypted
    if (_decryptedText == null &&
        !_isDecrypting &&
        !_hasDecryptionError &&
        widget.message.isEncrypted &&
        widget.message.content.containsKey('text')) {
      final encryptedText = widget.message.content['text'] as String?;
      if (encryptedText != null && encryptedText.isNotEmpty) {
        _isDecrypting = true;

        try {
          // CRITICAL: Use the correct decryption strategy based on message direction
          String? decryptedText;

          if (widget.message.metadata?['isFromCurrentUser'] == true) {
            decryptedText = encryptedText; // This is already the original text
          } else {
            // Incoming message - check if it needs decryption

            if (widget.message.content.containsKey('isIncomingEncrypted') &&
                (widget.message.content['isIncomingEncrypted'] == true ||
                    widget.message.content['isIncomingEncrypted'] == 'true')) {
              decryptedText = await _decryptMessageContent(encryptedText);
            } else {
              // This is a regular message (no decryption needed)

              // Additional check: if the text looks like encrypted data, try to decrypt it anyway
              if (encryptedText.length > 100 && encryptedText.contains('eyJ')) {
                decryptedText = await _decryptMessageContent(encryptedText);
              } else {
                decryptedText = encryptedText;
              }
            }
          }

          // Additional safety: if decryption fails, try to show a more helpful message
          if (decryptedText == null) {
            // For incoming messages, we might have the encrypted text but can't decrypt
            if (widget.message.metadata?['isFromCurrentUser'] == false) {
              // Try to show the encrypted text as a fallback (for debugging)
              if (widget.message.content.containsKey('text')) {
                final encryptedText = widget.message.content['text'] as String?;
                if (encryptedText != null && encryptedText.isNotEmpty) {
                  print(
                      '🔐 TextMessageBubble: 🔍 Encrypted text preview: ${encryptedText.substring(0, encryptedText.length > 50 ? 50 : encryptedText.length)}...');
                }
              }
            }
          }

          if (decryptedText != null) {
            _decryptedText = decryptedText;
            _isDecrypting = false;
            if (mounted) {
              setState(() {});
            }
          } else {
            _hasDecryptionError = true;
            _isDecrypting = false;
            if (mounted) {
              setState(() {});
            }
          }
        } catch (e) {
          _hasDecryptionError = true;
          _isDecrypting = false;
          if (mounted) {
            setState(() {});
          }
        }
      }
    }
  }

  /// Decrypt message content using EncryptionService
  Future<String?> _decryptMessageContent(String encryptedText) async {
    try {
      // Use EncryptionService to decrypt the message
      final decryptedData =
          await EncryptionService.decryptAesCbcPkcs7(encryptedText);

      if (decryptedData != null && decryptedData.containsKey('text')) {
        final decryptedText = decryptedData['text'] as String;

        // Check if the decrypted text is still encrypted (double encryption scenario)
        if (decryptedText.length > 100 && decryptedText.contains('eyJ')) {
          try {
            // Decrypt the inner encrypted content
            final innerDecryptedData =
                await EncryptionService.decryptAesCbcPkcs7(decryptedText);

            if (innerDecryptedData != null &&
                innerDecryptedData.containsKey('text')) {
              final finalDecryptedText = innerDecryptedData['text'] as String;

              return finalDecryptedText;
            } else {
              return decryptedText; // Return the first layer decrypted text as fallback
            }
          } catch (e) {
            return decryptedText; // Return the first layer decrypted text as fallback
          }
        } else {
          // Single layer encryption, return as is
          return decryptedText;
        }
      } else {
        return null;
      }
    } catch (e) {
      print('🔐 TextMessageBubble: ❌ Error decrypting message: $e');
      print('🔐 TextMessageBubble: 🔍 Error details: ${e.toString()}');

      // Try to provide a more helpful error message
      if (e.toString().contains('FormatException')) {
        print(
            '🔐 TextMessageBubble: ℹ️ Format error - message may not be properly encrypted');
      } else if (e.toString().contains('key')) {
        print(
            '🔐 TextMessageBubble: ℹ️ Key error - encryption key may be incorrect');
      }

      return null;
    }
  }

  /// Retry decryption when it fails
  Future<void> _retryDecryption() async {
    // Reset error state
    _hasDecryptionError = false;
    _decryptedText = null;
    _lastProcessedMessageId = null;

    // Trigger decryption again
    await _decryptMessageIfNeeded();
  }
}
