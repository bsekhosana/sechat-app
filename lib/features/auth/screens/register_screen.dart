import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
// import '../../../shared/providers/auth_provider.dart'; // Temporarily disabled
import '../../../shared/widgets/app_icon.dart';
import '../../../core/services/se_shared_preference_service.dart';
import '../../../core/services/network_service.dart';
import 'main_nav_screen.dart';
import 'dart:convert';
import '../../../core/services/se_session_service.dart';
import '../../../shared/widgets/custom_elevated_button.dart';
import '../../../shared/widgets/custom_textfield.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String? _qrCodeData;
  String? _sessionId;
  String? _privateKey;

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _createSessionIdentity() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final displayName = _displayNameController.text.trim();

      if (displayName.isEmpty) {
        throw Exception('Please enter a display name');
      }

      // Use the new SeSessionService
      final seSessionService = SeSessionService();
      final result = await seSessionService.createSession(displayName);

      if (result != null) {
        final sessionData = result['sessionData'] as SessionData;
        final password = result['password'] as String;

        setState(() {
          _sessionId = sessionData.sessionId;
          _qrCodeData = sessionData.publicKey; // Use public key as QR data
          _privateKey = password; // Store password for display
        });

        // Debug: Check if session was created successfully
        print('🔐 Debug: Session ID: ${sessionData.sessionId}');
        print('🔐 Debug: Public Key: ${sessionData.publicKey}');
        print('🔐 Debug: Display Name: ${sessionData.displayName}');
        print('🔐 Debug: Password: $password');
        print('🔐 Debug: Created At: ${sessionData.createdAt}');

        // Show success dialog with Session details
        _showSuccessDialog();
      } else {
        setState(() {
          _error = 'Failed to create session';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          constraints: const BoxConstraints(
            maxHeight: 600,
            maxWidth: 400,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFFFF6B35),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Account Created!',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Scrollable Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your SeChat account has been created successfully.',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                      const SizedBox(height: 24),

                      // Login Details Section
                      _buildSectionHeader('Login Details'),
                      const SizedBox(height: 12),

                      if (_sessionId != null)
                        _buildDetailRow(
                          'Session ID',
                          _sessionId!,
                          Icons.copy,
                          () => _copyToClipboard(
                              context, _sessionId!, 'Session ID'),
                        ),

                      if (_privateKey != null) ...[
                        const SizedBox(height: 8),
                        _buildDetailRow(
                          'Login Password',
                          _privateKey!,
                          Icons.copy,
                          () => _copyToClipboard(
                              context, _privateKey!, 'Login Password'),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Personal Section
                      _buildSectionHeader('Personal'),
                      const SizedBox(height: 12),

                      _buildDetailRow(
                        'Display Name',
                        _displayNameController.text.trim(),
                        null,
                        null,
                      ),

                      const SizedBox(height: 8),

                      _buildDetailRow(
                        'Date',
                        _formatDate(DateTime.now()),
                        null,
                        null,
                      ),

                      const SizedBox(height: 20),

                      // Warning Box
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning,
                                    color: Colors.red, size: 16),
                                const SizedBox(width: 8),
                                const Text(
                                  'Important',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '• Save your login password securely\n'
                              '• You\'ll need it to access your account\n'
                              '• Never share your password with anyone',
                              style: TextStyle(color: Colors.red, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Action Button
              Container(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      // Initialize notification services with new session
                      final seSessionService = SeSessionService();
                      await seSessionService.initializeNotificationServices();

                      // Add welcome notification to SharedPreferences
                      await _addWelcomeNotification();

                      Navigator.of(context).pop();
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => MainNavScreen()),
                        (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B35),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Start Chatting',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.black,
        fontWeight: FontWeight.bold,
        fontSize: 16,
      ),
    );
  }

  Widget _buildDetailRow(
      String label, String value, IconData? copyIcon, VoidCallback? onCopy) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          if (copyIcon != null && onCopy != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: onCopy,
              icon: Icon(copyIcon, size: 18, color: const Color(0xFFFF6B35)),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35).withOpacity(0.1),
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(4),
              ),
              tooltip: 'Copy $label',
            ),
          ],
        ],
      ),
    );
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

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Create Session'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Consumer<NetworkService>(
          builder: (context, networkService, child) {
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 10),
                      // App Icon
                      AppIcon(widthPerc: 0.2),
                      const SizedBox(height: 30),
                      const Text(
                        'Create Your SeChat Account',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Set up your private messaging account',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black.withOpacity(0.7),
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),

                      // Connection Status
                      if (!networkService.isConnected)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: Colors.red.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.wifi_off, color: Colors.red, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'No internet connection',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ),

                      // const SizedBox(height: 10),

                      // Session Protocol Info
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B35).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFFFF6B35).withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.security,
                                    color: const Color(0xFFFF6B35), size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  'Why Choose SeChat?',
                                  style: TextStyle(
                                    color: Color(0xFFFF6B35),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildInfoRow(
                                Icons.lock, 'Your messages are private'),
                            _buildInfoRow(Icons.visibility_off,
                                'No phone numbers needed'),
                            _buildInfoRow(
                                Icons.storage, 'Your data stays on your phone'),
                            _buildInfoRow(Icons.person_off, 'Stay anonymous'),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Privacy Notice
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.grey[600], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Your SeChat account is completely private. We don\'t ask for personal information.',
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Display Name Field
                      CustomTextfield(
                        controller: _displayNameController,
                        label: 'Your Name',
                        icon: Icons.person_outline,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your name';
                          }
                          if (value.length < 2 || value.length > 30) {
                            return 'Name must be 2-30 characters';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      CustomElevatedButton(
                        isLoading: _isLoading,
                        onPressed: _createSessionIdentity,
                        text: 'Create Account',
                        icon: Icons.add_circle_outline,
                        isPrimary: true,
                        orangeLoading: true,
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: Colors.red.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error, color: Colors.red, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.black.withOpacity(0.7), size: 16),
          const SizedBox(width: 8),
          Text(
            text,
            style:
                TextStyle(color: Colors.black.withOpacity(0.7), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Future<void> _addWelcomeNotification() async {
    try {
      final prefsService = SeSharedPreferenceService();
      final existingNotificationsJson =
          await prefsService.getJsonList('notifications') ?? [];

      final welcomeNotification = {
        'id': 'welcome_${DateTime.now().millisecondsSinceEpoch}',
        'title': 'Welcome to SeChat!',
        'body': 'Your secure messaging app is ready to use.',
        'type': 'system',
        'data': {},
        'timestamp': DateTime.now().toIso8601String(),
        'isRead': false,
      };

      existingNotificationsJson.add(welcomeNotification);
      await prefsService.setJsonList(
          'notifications', existingNotificationsJson);
      print(
          '🔍 RegisterScreen: ✅ Welcome notification added to SharedPreferences');
    } catch (e) {
      print('🔍 RegisterScreen: ❌ Error adding welcome notification: $e');
    }
  }
}
