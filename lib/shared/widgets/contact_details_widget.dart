import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

class ContactDetailsWidget extends StatelessWidget {
  final String sessionId;
  final String? displayName;
  final String? profilePicture;
  final DateTime? createdAt;
  final VoidCallback? onClose;

  const ContactDetailsWidget({
    super.key,
    required this.sessionId,
    this.displayName,
    this.profilePicture,
    this.createdAt,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.5),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  const Icon(
                    Icons.person,
                    size: 24,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Contact Details',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onClose ?? () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[100],
                      shape: const CircleBorder(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Profile Picture (if available)
              if (profilePicture != null) ...[
                CircleAvatar(
                  radius: 40,
                  backgroundImage: NetworkImage(profilePicture!),
                  onBackgroundImageError: (_, __) {},
                  child: profilePicture!.isEmpty
                      ? const Icon(Icons.person, size: 40, color: Colors.grey)
                      : null,
                ),
                const SizedBox(height: 16),
              ],

              // Display Name
              _buildDetailRow(
                context,
                label: 'Display Name',
                value: displayName ?? 'Not set',
                icon: Icons.badge,
                canCopy: true,
              ),
              const SizedBox(height: 16),

              // Session ID
              _buildDetailRow(
                context,
                label: 'Session ID',
                value: sessionId,
                icon: Icons.fingerprint,
                canCopy: true,
                isMonospace: true,
              ),
              const SizedBox(height: 16),

              // Created Date
              if (createdAt != null) ...[
                _buildDetailRow(
                  context,
                  label: 'Created',
                  value: _formatDate(createdAt!),
                  icon: Icons.calendar_today,
                  canCopy: false,
                ),
                const SizedBox(height: 16),
              ],

              // Contact Code JSON
              _buildJsonSection(context),

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _copyContactCode(context),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy Contact Code'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _shareContactCode(context),
                      icon: const Icon(Icons.share),
                      label: const Text('Share'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required bool canCopy,
    bool isMonospace = false,
  }) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool showCopySuccess = false;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: isMonospace ? 'monospace' : null,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  if (canCopy) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        _copyToClipboard(context, value, label);
                        setState(() {
                          showCopySuccess = true;
                        });
                        Future.delayed(const Duration(seconds: 2), () {
                          setState(() {
                            showCopySuccess = false;
                          });
                        });
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.blue.withOpacity(0.1),
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(4),
                      ),
                      tooltip: 'Copy $label',
                    ),
                  ],
                ],
              ),
            ),
            if (showCopySuccess) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle,
                        size: 12, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      '$label copied!',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildJsonSection(BuildContext context) {
    final contactCode = {
      'sessionId': sessionId,
      'displayName': displayName ?? 'SeChat User',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.code, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 8),
            const Text(
              'Contact Code',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[700]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatJson(contactCode),
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Colors.green,
                        height: 1.4,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _copyToClipboard(
                      context,
                      _formatJson(contactCode),
                      'Contact Code',
                    ),
                    icon: const Icon(Icons.copy, size: 16, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[700],
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(4),
                    ),
                    tooltip: 'Copy Contact Code',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatJson(Map<String, dynamic> json) {
    final buffer = StringBuffer();
    buffer.writeln('{');

    final entries = json.entries.toList();
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final isLast = i == entries.length - 1;

      buffer.write('  "${entry.key}": "${entry.value}"');
      if (!isLast) buffer.write(',');
      buffer.writeln();
    }

    buffer.write('}');
    return buffer.toString();
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  void _copyContactCode(BuildContext context) {
    final contactCode = {
      'sessionId': sessionId,
      'displayName': displayName ?? 'SeChat User',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _copyToClipboard(context, _formatJson(contactCode), 'Contact Code');
  }

  void _shareContactCode(BuildContext context) {
    // This would integrate with the share functionality
    // For now, we'll just copy to clipboard
    _copyContactCode(context);
  }
}

// Simple JSON encoder for formatting
class JsonEncoder {
  static String withIndent(String indent) {
    return indent;
  }

  String convert(Map<String, dynamic> json) {
    final buffer = StringBuffer();
    buffer.writeln('{');

    final entries = json.entries.toList();
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final isLast = i == entries.length - 1;

      buffer.write('  "${entry.key}": "${entry.value}"');
      if (!isLast) buffer.write(',');
      buffer.writeln();
    }

    buffer.write('}');
    return buffer.toString();
  }
}
