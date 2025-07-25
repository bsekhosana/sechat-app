import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sechat_app/shared/providers/auth_provider.dart';
import 'package:sechat_app/shared/widgets/qr_image_upload_widget.dart';
import 'package:sechat_app/shared/widgets/profile_icon_widget.dart';
import '../../features/invitations/providers/invitation_provider.dart';
import '../../core/services/session_service.dart';
import '../../core/services/notification_service.dart';

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
            child: SingleChildScrollView(
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

                  const SizedBox(height: 24),

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

  void _scanQRCode(BuildContext context) async {
    print('📱 InviteUserWidget: Starting QR scan navigation');

    // Check camera permission first
    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted) {
      if (context.mounted) {
        _showCameraPermissionDialog(context);
      }
      return;
    }

    Navigator.of(context).pop();
    // Use a post-frame callback to ensure the modal is fully closed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print(
          '📱 InviteUserWidget: Post-frame callback executed, context.mounted: ${context.mounted}');
      if (context.mounted) {
        // Simple navigation approach
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => QRImageUploadWidget(
              onQRCodeExtracted: (qrData) async {
                print('📱 InviteUserWidget: QR code extracted, processing...');
                // Don't pop here, let the QR screen handle its own navigation
                await _processQRCode(context, qrData);
              },
              onCancel: () {
                print('📱 InviteUserWidget: QR screen cancelled');
                // Don't pop here, let the QR screen handle its own navigation
              },
            ),
          ),
        );
      }
    });
  }

  void _showCameraPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF232323),
        title: const Text(
          'Camera Permission Required',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Camera access is required to scan QR codes for adding contacts.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            const Text(
              'To enable camera access:',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Go to Settings > SeChat\n'
              '2. Tap "Camera"\n'
              '3. Enable "Allow SeChat to Access Camera"',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text(
              'Open Settings',
              style: TextStyle(color: Color(0xFFFF6B35)),
            ),
          ),
        ],
      ),
    );
  }

  void _uploadQRImage(BuildContext context) {
    print('📱 InviteUserWidget: Starting QR upload navigation');
    Navigator.of(context).pop();
    // Use a post-frame callback to ensure the modal is fully closed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print(
          '📱 InviteUserWidget: Post-frame callback executed, context.mounted: ${context.mounted}');
      if (context.mounted) {
        // Simple navigation approach
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => QRImageUploadWidget(
              onQRCodeExtracted: (qrData) async {
                print('📱 InviteUserWidget: QR code extracted, processing...');
                // Don't pop here, let the QR screen handle its own navigation
                await _processQRCode(context, qrData);
              },
              onCancel: () {
                print('📱 InviteUserWidget: QR screen cancelled');
                // Don't pop here, let the QR screen handle its own navigation
              },
            ),
          ),
        );
      }
    });
  }

  void _enterSessionId(BuildContext context) {
    Navigator.of(context).pop();
    _showSessionIdDialog(context);
  }

  void _showMyQRCode(BuildContext context) {
    Navigator.of(context).pop();
    final sessionId = SessionService.instance.currentSessionId;

    if (sessionId != null) {
      // Show QR code in profile menu
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => const ProfileIconWidget(),
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
            onPressed: () async {
              final sessionId = sessionIdController.text.trim();
              final displayName = displayNameController.text.trim();

              if (sessionId.isNotEmpty) {
                Navigator.of(context).pop();
                await _processQRCode(context, sessionId,
                    displayName: displayName);
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

  Future<void> _processQRCode(BuildContext context, String qrData,
      {String? displayName}) async {
    print('📱 InviteUserWidget: Starting QR code processing');
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
        // Show loading indicator
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Adding contact...'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            ),
          );
        }

        print(
            '📱 InviteUserWidget: Sending invitation for sessionId: $sessionId with displayName: $extractedDisplayName');
        // Add timeout to prevent hanging
        final success = await context
            .read<InvitationProvider>()
            .sendInvitation(sessionId, displayName: extractedDisplayName)
            .timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw Exception('Invitation request timed out');
          },
        ).catchError((error) {
          print('📱 InviteUserWidget: Error sending invitation: $error');
          return false; // Return false on error instead of throwing
        });
        print('📱 InviteUserWidget: Invitation send result: $success');

        // Show instant notification with timeout (don't block on this)
        try {
          NotificationService.instance
              .showInvitationSentNotification(
            recipientUsername: extractedDisplayName ?? 'Anonymous',
            invitationId: sessionId,
          )
              .timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              print('Notification timeout - continuing anyway');
            },
          );
        } catch (e) {
          print('Notification failed: $e');
          // Don't fail the whole process if notification fails
        }

        if (context.mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('Contact added: ${extractedDisplayName ?? sessionId}'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          } else {
            // Check if it's a validation error
            final invitationProvider = context.read<InvitationProvider>();
            if (invitationProvider.isUserInvited(sessionId)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      '${extractedDisplayName ?? sessionId} is already in your contacts'),
                  backgroundColor: Colors.blue,
                  duration: const Duration(seconds: 3),
                ),
              );
            } else if (invitationProvider.isUserQueued(sessionId)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Invitation to ${extractedDisplayName ?? sessionId} is already pending'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 3),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      const Text('Contact added locally (network unavailable)'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        }
      } else {
        throw Exception('Invalid QR code format');
      }
    } catch (e) {
      print('📱 InviteUserWidget: Error in QR processing: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    print('📱 InviteUserWidget: QR code processing completed');
  }
}
