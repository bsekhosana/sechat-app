import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

class QRGeneratorWidget extends StatelessWidget {
  final String sessionId;
  final String? displayName;

  const QRGeneratorWidget({
    Key? key,
    required this.sessionId,
    this.displayName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final qrData = {
      'sessionId': sessionId,
      'displayName': displayName ?? 'SeChat User',
      'app': 'SeChat',
      'version': '2.0.0',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('My QR Code'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareQRCode(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  QrImageView(
                    data: sessionId,
                    version: QrVersions.auto,
                    size: 200.0,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    displayName ?? 'SeChat User',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          sessionId,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontFamily: 'monospace',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        onPressed: () => _copySessionId(context),
                        icon: const Icon(Icons.copy, size: 16),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.blue.withOpacity(0.1),
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(4),
                        ),
                        tooltip: 'Copy Session ID',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Share this QR code with others to connect on SeChat',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _shareQRCode(context),
                    icon: const Icon(Icons.share),
                    label: const Text('Share'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _copySessionId(context),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy ID'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _shareQRCode(BuildContext context) {
    Share.share(
      'Connect with me on SeChat!\n\nMy Session ID: $sessionId\n\nDownload SeChat to start chatting securely.',
      subject: 'Connect on SeChat',
    );
  }

  void _copySessionId(BuildContext context) {
    Clipboard.setData(ClipboardData(text: sessionId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Session ID copied to clipboard'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
