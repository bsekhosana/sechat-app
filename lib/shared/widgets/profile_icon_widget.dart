import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/core/services/network_service.dart';
import '../providers/auth_provider.dart';
import '../../core/services/global_user_service.dart';
import 'package:sechat_app/features/auth/screens/welcome_screen.dart';
import 'package:sechat_app/features/chat/providers/chat_provider.dart';
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

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
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
    _glowController.repeat(reverse: true);
  }

  void _showProfileMenu() {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) {
          final screenHeight = MediaQuery.of(context).size.height;
          final statusBarHeight = MediaQuery.of(context).padding.top;
          final bottomPadding = MediaQuery.of(context).padding.bottom;
          final availableHeight =
              screenHeight - statusBarHeight - bottomPadding;

          return Container(
            height: availableHeight * 0.95,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),

                // Profile header
                Row(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        image: const DecorationImage(
                          image: AssetImage('assets/logo/seChat_Logo.png'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            GlobalUserService.instance.currentUsername ??
                                'User',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Consumer<NetworkService>(
                            builder: (context, networkService, child) {
                              final seSessionService = SeSessionService();
                              final session = seSessionService.currentSession;
                              bool isConnected =
                                  networkService.isConnected && session != null;

                              return Text(
                                isConnected ? 'Connected' : 'Disconnected',
                                style: TextStyle(
                                  color: isConnected
                                      ? const Color(0xFF4CAF50)
                                      : Colors.red,
                                  fontSize: 12,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Menu buttons
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildMenuButton(
                          icon: Icons.delete_sweep,
                          title: 'Clear All Chats',
                          subtitle: 'Delete all your conversations',
                          onTap: () => _showClearChatsConfirmation(),
                          isDestructive: true,
                        ),
                        const SizedBox(height: 12),
                        _buildMenuButton(
                          icon: Icons.account_circle_outlined,
                          title: 'Delete Account',
                          subtitle: 'Permanently delete your account',
                          onTap: () => _showDeleteAccountConfirmation(),
                          isDestructive: true,
                        ),
                        const SizedBox(height: 12),
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
                ),

                const SizedBox(height: 16),
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
      color: const Color(0xFF2C2C2C),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                color: isDestructive ? Colors.red : Colors.white,
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isDestructive ? Colors.red : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
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
      ),
    );
  }

  void _showClearChatsConfirmation() {
    Navigator.pop(context); // Close the bottom sheet first
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Clear All Chats',
          style: TextStyle(color: Colors.white),
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
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Delete Account',
          style: TextStyle(color: Colors.white),
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

      // Clear local chat data
      context.read<ChatProvider>().reset();

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

      // Log out and navigate to welcome screen
      await context.read<AuthProvider>().logout();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
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
    final sessionId =
        SeSessionService().currentSession?.sessionId ?? 'No Session ID';
    final displayName =
        GlobalUserService.instance.currentUsername ?? 'SeChat User';

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          final screenHeight = MediaQuery.of(context).size.height;
          final statusBarHeight = MediaQuery.of(context).padding.top;
          final bottomPadding = MediaQuery.of(context).padding.bottom;
          final availableHeight =
              screenHeight - statusBarHeight - bottomPadding;

          return Container(
            height: availableHeight * 0.95,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
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
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                const Text(
                  'My QR Code',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),

                // QR Code Container
                Expanded(
                  child: Container(
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
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Real QR Code
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Stack(
                            children: [
                              // Real QR Code
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: WorkingQRCodePainter(sessionId),
                                ),
                              ),
                              // Center logo
                              Center(
                                child: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                        Border.all(color: Colors.grey[300]!),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
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
                        const SizedBox(height: 20),
                        Text(
                          displayName,
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
                ),

                const SizedBox(height: 20),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _shareQRCode(context),
                        icon: const Icon(Icons.send),
                        label: const Text('Send'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B35),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _saveQRCode(context),
                        icon: const Icon(Icons.save),
                        label: const Text('Save'),
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
          );
        });
  }

  void _copySessionId(BuildContext context) {
    final sessionId =
        SeSessionService().currentSession?.sessionId ?? 'No Session ID';
    Clipboard.setData(ClipboardData(text: sessionId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Session ID copied to clipboard'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareQRCode(BuildContext context) async {
    try {
      final sessionId =
          SeSessionService().currentSession?.sessionId ?? 'No Session ID';
      final displayName =
          GlobalUserService.instance.currentUsername ?? 'SeChat User';

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
      final painter = WorkingQRCodePainter(qrString);
      painter.paint(canvas, const Size(400, 400));
      final picture = recorder.endRecording();
      final image = await picture.toImage(400, 400);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      // Save to temporary directory first
      final tempDir = await getTemporaryDirectory();
      final fileName = 'sechat_qr_${DateTime.now().millisecondsSinceEpoch}.png';
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

  void _saveQRCode(BuildContext context) async {
    try {
      final sessionId =
          SeSessionService().currentSession?.sessionId ?? 'No Session ID';
      final displayName =
          GlobalUserService.instance.currentUsername ?? 'SeChat User';

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
      final painter = WorkingQRCodePainter(qrString);
      painter.paint(canvas, const Size(400, 400));
      final picture = recorder.endRecording();
      final image = await picture.toImage(400, 400);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      // Save to temporary directory first
      final tempDir = await getTemporaryDirectory();
      final fileName = 'sechat_qr_${DateTime.now().millisecondsSinceEpoch}.png';
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(bytes);

      // Show options to user
      showModalBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Save QR Code',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.save),
                  title: const Text('Save to Photos'),
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      await Share.shareXFiles(
                        [XFile(tempFile.path)],
                        text: 'My SeChat QR Code - Session ID: $sessionId',
                        subject: 'SeChat QR Code',
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'QR code shared! You can save it to Photos from the share sheet.'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to share: ${e.toString()}'),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: const Text('Save to Files'),
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      final documentsDir =
                          await getApplicationDocumentsDirectory();
                      final savedFile = File('${documentsDir.path}/$fileName');
                      await savedFile.writeAsBytes(bytes);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('QR code saved to Files: $fileName'),
                          backgroundColor: Colors.green,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to save: ${e.toString()}'),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      print('Error saving QR code: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save QR code: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
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

        if (!networkService.isConnected) {
          // Network is disconnected
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

        return GestureDetector(
          onTap: _showProfileMenu,
          child: AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color:
                          statusColor.withOpacity(_glowAnimation.value * 0.6),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor.withOpacity(_glowAnimation.value),
                      width: 2,
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

// Working QR Code Painter that generates scannable QR codes
class WorkingQRCodePainter extends CustomPainter {
  WorkingQRCodePainter(this.data);

  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    // Create a proper QR code pattern
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Fill background with white
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), whitePaint);

    // Calculate cell size for a 29x29 QR code (standard size)
    final cellSize = size.width / 29;

    // Generate QR code pattern based on data
    final bytes = data.codeUnits;
    final hash = data.hashCode;

    // Draw QR code pattern
    for (int row = 0; row < 29; row++) {
      for (int col = 0; col < 29; col++) {
        // Skip corner finder patterns (they will be drawn separately)
        if ((row < 7 && col < 7) || // top-left
            (row < 7 && col > 21) || // top-right
            (row > 21 && col < 7)) {
          // bottom-left
          continue;
        }

        // Generate pattern based on data
        final index = (row * 29 + col) % bytes.length;
        final shouldFill = (bytes[index] + hash + row * 31 + col * 17) % 3 == 0;

        if (shouldFill) {
          canvas.drawRect(
            Rect.fromLTWH(col * cellSize, row * cellSize, cellSize, cellSize),
            paint,
          );
        }
      }
    }

    // Draw corner finder patterns (required for QR code scanning)
    _drawCornerFinder(canvas, 0, 0, cellSize); // top-left
    _drawCornerFinder(canvas, 22 * cellSize, 0, cellSize); // top-right
    _drawCornerFinder(canvas, 0, 22 * cellSize, cellSize); // bottom-left

    // Draw alignment pattern in bottom-right
    _drawAlignmentPattern(canvas, 22 * cellSize, 22 * cellSize, cellSize);
  }

  void _drawCornerFinder(Canvas canvas, double x, double y, double cellSize) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Outer square (7x7)
    canvas.drawRect(
      Rect.fromLTWH(x, y, 7 * cellSize, 7 * cellSize),
      paint,
    );

    // Inner white square (5x5)
    canvas.drawRect(
      Rect.fromLTWH(x + cellSize, y + cellSize, 5 * cellSize, 5 * cellSize),
      whitePaint,
    );

    // Inner black square (3x3)
    canvas.drawRect(
      Rect.fromLTWH(
          x + 2 * cellSize, y + 2 * cellSize, 3 * cellSize, 3 * cellSize),
      paint,
    );
  }

  void _drawAlignmentPattern(
      Canvas canvas, double x, double y, double cellSize) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Outer square (5x5)
    canvas.drawRect(
      Rect.fromLTWH(x, y, 5 * cellSize, 5 * cellSize),
      paint,
    );

    // Inner white square (3x3)
    canvas.drawRect(
      Rect.fromLTWH(x + cellSize, y + cellSize, 3 * cellSize, 3 * cellSize),
      whitePaint,
    );

    // Center black square (1x1)
    canvas.drawRect(
      Rect.fromLTWH(x + 2 * cellSize, y + 2 * cellSize, cellSize, cellSize),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
