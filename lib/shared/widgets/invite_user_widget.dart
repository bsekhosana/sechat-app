import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/invitations/providers/invitation_provider.dart';
import 'qr_scanner_widget.dart';
import 'qr_generator_widget.dart';
import 'qr_image_upload_widget.dart';
import '../../shared/providers/auth_provider.dart';
import '../../core/services/session_service.dart';

class InviteUserWidget extends StatelessWidget {
  const InviteUserWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showInviteOptions(context),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2C),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Icon(
            Icons.person_add,
            color: Color(0xFF666666),
            size: 24,
          ),
        ),
      ),
    );
  }

  void _showInviteOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _InviteOptionsSheet(),
    );
  }
}

class _InviteOptionsSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Add New Contact',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 8),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Choose how you want to add a new contact',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),
          ),

          const SizedBox(height: 30),

          // Options
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // Scan QR Code Option
                  _buildOptionCard(
                    context,
                    icon: Icons.qr_code_scanner,
                    title: 'Scan QR Code',
                    subtitle: 'Scan a contact\'s QR code to add them',
                    color: Colors.blue,
                    onTap: () => _scanQRCode(context),
                  ),

                  const SizedBox(height: 16),

                  // Upload Image Option
                  _buildOptionCard(
                    context,
                    icon: Icons.upload,
                    title: 'Upload QR Image',
                    subtitle: 'Upload an image containing a QR code',
                    color: Colors.green,
                    onTap: () => _uploadQRImage(context),
                  ),

                  const SizedBox(height: 16),

                  // Manual Entry Option
                  _buildOptionCard(
                    context,
                    icon: Icons.edit,
                    title: 'Enter Session ID',
                    subtitle: 'Manually enter a contact\'s Session ID',
                    color: Colors.orange,
                    onTap: () => _enterSessionId(context),
                  ),

                  const SizedBox(height: 16),

                  // Share My QR Code Option
                  _buildOptionCard(
                    context,
                    icon: Icons.qr_code,
                    title: 'Show My QR Code',
                    subtitle: 'Share your QR code with others',
                    color: Colors.purple,
                    onTap: () => _showMyQRCode(context),
                  ),

                  const Spacer(),

                  // Cancel Button
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey[600],
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _scanQRCode(BuildContext context) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QRScannerWidget(
          onQRCodeScanned: (qrData) {
            Navigator.of(context).pop();
            _processQRCode(context, qrData);
          },
        ),
      ),
    );
  }

  void _uploadQRImage(BuildContext context) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QRImageUploadWidget(
          onQRCodeExtracted: (qrData) {
            Navigator.of(context).pop();
            _processQRCode(context, qrData);
          },
          onCancel: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _enterSessionId(BuildContext context) {
    Navigator.of(context).pop();
    _showSessionIdDialog(context);
  }

  void _showMyQRCode(BuildContext context) {
    Navigator.of(context).pop();
    final sessionId = SessionService.instance.currentSessionId;

    if (sessionId != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => QRGeneratorWidget(
            sessionId: sessionId,
            displayName: 'SeChat User', // TODO: Get from user profile
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session ID not available'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showSessionIdDialog(BuildContext context) {
    final TextEditingController sessionIdController = TextEditingController();
    final TextEditingController displayNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF232323),
        title: const Text(
          'Add Contact',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: sessionIdController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Session ID',
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: displayNameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Display Name (Optional)',
                labelStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              final sessionId = sessionIdController.text.trim();
              final displayName = displayNameController.text.trim();

              if (sessionId.isNotEmpty) {
                Navigator.of(context).pop();
                _processQRCode(context, sessionId, displayName: displayName);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Add Contact'),
          ),
        ],
      ),
    );
  }

  void _processQRCode(BuildContext context, String qrData,
      {String? displayName}) {
    try {
      // Try to parse as JSON first
      Map<String, dynamic> data;
      if (qrData.startsWith('{')) {
        data = Map<String, dynamic>.from(json.decode(qrData));
      } else {
        data = {'sessionId': qrData};
      }

      final sessionId = data['sessionId'] as String?;
      final extractedDisplayName =
          data['displayName'] as String? ?? displayName;

      if (sessionId != null) {
        context.read<InvitationProvider>().addContact(
              sessionId: sessionId,
              displayName: extractedDisplayName,
            );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Contact added: ${extractedDisplayName ?? sessionId}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('Invalid QR code format');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid QR code: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
