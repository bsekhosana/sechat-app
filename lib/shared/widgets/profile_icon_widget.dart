import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/network_service.dart';
import '../../core/services/global_user_service.dart';
import 'package:sechat_app/features/auth/screens/welcome_screen.dart';
import 'package:sechat_app/core/services/local_storage_service.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'dart:math';

class ProfileIconWidget extends StatefulWidget {
  const ProfileIconWidget({super.key});

  @override
  State<ProfileIconWidget> createState() => _ProfileIconWidgetState();
}

class _ProfileIconWidgetState extends State<ProfileIconWidget>
    with TickerProviderStateMixin {
  late Animation<double> _glowAnimation;
  late AnimationController _glowController;
  late Animation<double> _pulseAnimation;
  late AnimationController _pulseController;
  bool _showCopySuccess = false;

  @override
  void dispose() {
    _glowController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    // Glow animation for connected state
    _glowController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _glowAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeInOut,
    ));

    // Pulse animation for reconnecting state
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  void _updateAnimationStatus(bool isConnected, bool isReconnecting) {
    if (isConnected) {
      _glowController.repeat(reverse: true);
      _pulseController.stop();
    } else if (isReconnecting) {
      _glowController.stop();
      _pulseController.repeat(reverse: true);
    } else {
      _glowController.stop();
      _pulseController.stop();
    }
  }

  // Method to get current connection status for debugging
  String _getConnectionStatusText(NetworkService networkService) {
    final seSessionService = SeSessionService();
    final session = seSessionService.currentSession;
    bool isConnected = networkService.isConnected && session != null;
    bool isReconnecting = networkService.isReconnecting;

    if (!networkService.isConnected) {
      return 'No Internet Connection';
    } else if (isReconnecting) {
      return 'Reconnecting...';
    } else if (isConnected) {
      return 'Fully Connected';
    } else {
      return 'Session Disconnected';
    }
  }

  void _showProfileMenu() {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          final screenHeight = MediaQuery.of(context).size.height;
          final statusBarHeight = MediaQuery.of(context).padding.top;
          final bottomPadding = MediaQuery.of(context).padding.bottom;
          final availableHeight =
              screenHeight - statusBarHeight - bottomPadding;

          return Container(
            height: screenHeight * 0.95,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Header
                Container(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Profile icon
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(40),
                          image: const DecorationImage(
                            image: AssetImage('assets/logo/seChat_Logo.png'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Username
                      Text(
                        GlobalUserService.instance.currentUsername ?? 'User',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Network status
                      Consumer<NetworkService>(
                        builder: (context, networkService, child) {
                          final seSessionService = SeSessionService();
                          final session = seSessionService.currentSession;
                          bool isConnected =
                              networkService.isConnected && session != null;
                          bool isReconnecting = networkService.isReconnecting;

                          // Determine status text and color
                          String statusText;
                          Color statusColor;

                          if (!networkService.isConnected) {
                            statusText = 'No Network';
                            statusColor = Colors.red;
                          } else if (!networkService.isInternetAvailable) {
                            statusText = 'No Internet';
                            statusColor = Colors.red;
                          } else if (isReconnecting) {
                            statusText = 'Reconnecting...';
                            statusColor = Colors.orange;
                          } else if (isConnected) {
                            statusText = 'Connected';
                            statusColor = const Color(0xFF4CAF50);
                          } else {
                            statusText = 'Session Disconnected';
                            statusColor = Colors.orange;
                          }

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                statusText,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // Content - Scrollable
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                    child: Column(
                      children: [
                        // Menu options container
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Column(
                            children: [
                              _buildMenuButton(
                                icon: Icons.delete_sweep,
                                title: 'Clear All Chats',
                                subtitle: 'Delete all your conversations',
                                onTap: () => _showClearChatsConfirmation(),
                                isDestructive: true,
                              ),
                              const SizedBox(height: 16),
                              _buildMenuButton(
                                icon: Icons.account_circle_outlined,
                                title: 'Delete Account',
                                subtitle: 'Permanently delete your account',
                                onTap: () => _showDeleteAccountConfirmation(),
                                isDestructive: true,
                              ),
                              const SizedBox(height: 16),
                              _buildMenuButton(
                                icon: Icons.qr_code,
                                title: 'My QR Code',
                                subtitle: 'Share your Session ID with others',
                                onTap: () => _showQRCode(),
                                isDestructive: false,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        });
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDestructive
                      ? Colors.red.withValues(alpha: 0.1)
                      : const Color(0xFFFF6B35).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: isDestructive ? Colors.red : const Color(0xFFFF6B35),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isDestructive ? Colors.red : Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.grey[400],
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showClearChatsConfirmation() {
    Navigator.pop(context); // Close the bottom sheet first
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Clear All Chats',
          style: TextStyle(color: Colors.black),
        ),
        content: const Text(
          'Are you sure you want to delete all your conversations? This action cannot be reversed.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearAllChats();
            },
            child: const Text(
              'Delete All',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountConfirmation() {
    Navigator.pop(context); // Close the bottom sheet first
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Delete Account',
          style: TextStyle(color: Colors.black),
        ),
        content: const Text(
          'Are you sure you want to permanently delete your account? This action cannot be reversed and all your data will be lost.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAccount();
            },
            child: const Text(
              'Delete Account',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllChats() async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Clear all conversations in Session Protocol
      // Clear conversations using SeSessionService
      final seSessionService = SeSessionService();
      await seSessionService.clearSessionMessages(
          seSessionService.currentSession?.sessionId ?? '');

      // Clear local storage
      await LocalStorageService.instance.clearAllData();

      Navigator.pop(context); // Close loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All chats cleared successfully'),
          backgroundColor: Color(0xFFFF6B35),
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteAccount() async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Clear all data in Session Protocol
      // Clear all data using SeSessionService
      final seSessionService = SeSessionService();
      await seSessionService.deleteSession();

      // Clear local storage
      await LocalStorageService.instance.clearAllData();

      Navigator.pop(context); // Close loading dialog

      // Navigate to welcome screen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const WelcomeScreen()),
        (route) => false,
      );
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showQRCode() {
    Navigator.pop(context); // Close the bottom sheet first
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final sessionId =
            SeSessionService().currentSessionId ?? 'No session ID';
        final displayName =
            GlobalUserService.instance.currentUsername ?? 'SeChat User';

        return Container(
          height: MediaQuery.of(context).size.height * 0.95,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Icon
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Icon(
                        Icons.qr_code,
                        color: Color(0xFFFF6B35),
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Title
                    const Text(
                      'My QR Code',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Subtitle
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

              // QR Code Container
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      // QR Code Image
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[300]!),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            // QR Code
                            Positioned.fill(
                              child: CustomPaint(
                                painter: QRCodePainter(sessionId),
                              ),
                            ),
                            // Center logo
                            Center(
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    image: const DecorationImage(
                                      image: AssetImage(
                                          'assets/logo/seChat_Logo.png'),
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Copy Success Message
                      if (_showCopySuccess)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Session ID copied to clipboard',
                                style: TextStyle(
                                  color: Colors.green[700],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Session ID with Copy Button
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Session ID',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border:
                                          Border.all(color: Colors.grey[300]!),
                                    ),
                                    child: SelectableText(
                                      sessionId,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _copySessionId(context),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF6B35)
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.copy,
                                      color: Color(0xFFFF6B35),
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Action Buttons
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _shareQRCode(context),
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFFF6B35).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.share,
                                color: Color(0xFFFF6B35),
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Share QR Code',
                                style: TextStyle(
                                  color: Color(0xFFFF6B35),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _copySessionId(BuildContext context) {
    final sessionId = SeSessionService().currentSessionId;
    if (sessionId != null) {
      Clipboard.setData(ClipboardData(text: sessionId));
      // Show success message above the session ID container
      setState(() {
        _showCopySuccess = true;
      });

      // Hide the message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showCopySuccess = false;
          });
        }
      });
    }
  }

  void _shareQRCode(BuildContext context) async {
    try {
      final sessionId = SeSessionService().currentSessionId;
      final displayName =
          GlobalUserService.instance.currentUsername ?? 'SeChat User';

      if (sessionId != null) {
        // Create QR code data
        final qrData = {
          'sessionId': sessionId,
          'displayName': displayName,
          'app': 'SeChat',
          'version': '2.0.0',
        };

        // Convert QR data to JSON string
        final qrString = qrData.toString();

        // Generate QR code image using custom painter
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final painter = QRCodePainter(qrString);
        painter.paint(canvas, const Size(400, 400));
        final picture = recorder.endRecording();
        final image = await picture.toImage(400, 400);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        final bytes = byteData!.buffer.asUint8List();

        // Save to temporary directory first
        final tempDir = await getTemporaryDirectory();
        final fileName =
            'sechat_qr_${DateTime.now().millisecondsSinceEpoch}.png';
        final tempFile = File('${tempDir.path}/$fileName');
        await tempFile.writeAsBytes(bytes);

        await Share.shareXFiles(
          [XFile(tempFile.path)],
          text:
              'Connect with me on SeChat!\n\nMy Session ID: $sessionId\n\nDownload SeChat to start chatting securely.',
          subject: 'Connect on SeChat',
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR code shared successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error sharing QR code: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share QR code: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _shareSessionId() {
    final sessionId = SeSessionService().currentSessionId;
    if (sessionId != null) {
      Share.share(
        'Connect with me on SeChat! My Session ID: $sessionId',
        subject: 'SeChat Session ID',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NetworkService>(
      builder: (context, networkService, child) {
        // Determine connection status and color
        Color statusColor;
        bool isConnected = false;
        bool isReconnecting = networkService.isReconnecting;
        bool isInternetAvailable = networkService.isInternetAvailable;

        if (!networkService.isConnected || !isInternetAvailable) {
          // Network is disconnected or no internet
          statusColor = Colors.red;
          isConnected = false;
        } else if (networkService.isReconnecting) {
          // Network is reconnecting
          statusColor = Colors.orange;
          isConnected = false;
        } else {
          // Network is connected, check SeSession status
          final seSessionService = SeSessionService();
          final session = seSessionService.currentSession;
          if (session != null) {
            statusColor = Colors.green;
            isConnected = true;
          } else {
            statusColor = Colors.orange;
            isConnected = false;
          }
        }

        // Update animation status based on connection state
        _updateAnimationStatus(isConnected, isReconnecting);

        return GestureDetector(
          onTap: _showProfileMenu,
          child: AnimatedBuilder(
            animation: Listenable.merge([_glowAnimation, _pulseAnimation]),
            builder: (context, child) {
              // Determine which animation to use
              double animationValue;
              if (isConnected) {
                animationValue = _glowAnimation.value;
              } else if (isReconnecting) {
                animationValue = _pulseAnimation.value;
              } else {
                animationValue = 0.3; // Static low glow for disconnected
              }

              return Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color:
                          statusColor.withValues(alpha: animationValue * 0.6),
                      blurRadius: isReconnecting ? 8 : 12,
                      spreadRadius: isReconnecting ? 1 : 2,
                    ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor.withValues(alpha: animationValue),
                      width: isReconnecting ? 1.5 : 2,
                    ),
                    image: const DecorationImage(
                      image: AssetImage('assets/logo/seChat_Logo.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// Simple QR Code Painter
class QRCodePainter extends CustomPainter {
  QRCodePainter(this.data);

  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    // Generate a simple pattern based on the data
    final bytes = data.codeUnits;
    final gridSize = 25;
    final cellSize = size.width / gridSize;

    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        final index = (i * gridSize + j) % bytes.length;
        final shouldFill = bytes[index] % 2 == 0;

        if (shouldFill) {
          canvas.drawRect(
            Rect.fromLTWH(i * cellSize, j * cellSize, cellSize, cellSize),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
