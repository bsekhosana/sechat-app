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
import '../../../core/services/channel_socket_service.dart';
import '../../../shared/widgets/custom_elevated_button.dart';
import '../../../shared/widgets/custom_textfield.dart';
import 'package:sechat_app/core/services/se_socket_service.dart';
import '/../core/utils/logger.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _AccountCreatedActionSheet extends StatefulWidget {
  final String? sessionId;
  final String? privateKey;
  final String displayName;
  final VoidCallback onStartChatting;

  const _AccountCreatedActionSheet({
    required this.sessionId,
    required this.privateKey,
    required this.displayName,
    required this.onStartChatting,
  });

  @override
  State<_AccountCreatedActionSheet> createState() =>
      _AccountCreatedActionSheetState();
}

class _AccountCreatedActionSheetState
    extends State<_AccountCreatedActionSheet> {
  // Copy feedback states
  bool _showSessionIdCopied = false;
  bool _showPasswordCopied = false;

  // Loading state for start chatting button
  bool _isStartChattingLoading = false;

  void _copySessionIdToClipboard() {
    if (widget.sessionId != null) {
      Clipboard.setData(ClipboardData(text: widget.sessionId!));
      Logger.debug(' Debug: Copying Session ID to clipboard');

      // Force UI rebuild
      setState(() {
        _showSessionIdCopied = true;
      });
      Logger.debug(
          ' Debug: _showSessionIdCopied set to: $_showSessionIdCopied');

      // Hide the copied message after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _showSessionIdCopied = false;
          });
          Logger.debug(
              ' Debug: _showSessionIdCopied reset to: $_showSessionIdCopied');
        }
      });
    }
  }

  void _copyPasswordToClipboard() {
    if (widget.privateKey != null) {
      Clipboard.setData(ClipboardData(text: widget.privateKey!));
      Logger.debug(' Debug: Copying Password to clipboard');

      // Force UI rebuild
      setState(() {
        _showPasswordCopied = true;
      });
      Logger.debug(' Debug: _showPasswordCopied set to: $_showPasswordCopied');

      // Hide the copied message after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _showPasswordCopied = false;
          });
          Logger.debug(
              ' Debug: _showPasswordCopied reset to: $_showPasswordCopied');
        }
      });
    }
  }

  Future<void> _handleStartChatting() async {
    setState(() {
      _isStartChattingLoading = true;
    });

    try {
      widget.onStartChatting();
    } finally {
      if (mounted) {
        setState(() {
          _isStartChattingLoading = false;
        });
      }
    }
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

  Widget _buildDetailRowWithCopyFeedback(String label, String value,
      IconData? copyIcon, VoidCallback? onCopy, bool showCopied) {
    Logger.debug(
        ' Debug: Building detail row for $label with showCopied: $showCopied');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  icon:
                      Icon(copyIcon, size: 18, color: const Color(0xFFFF6B35)),
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
          // Copy feedback label
          if (showCopied) ...[
            const SizedBox(height: 8),
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
                  Icon(Icons.check_circle, color: Colors.green, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '$label copied successfully!',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.95,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFFFF6B35), size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${widget.displayName}\'s Session Created!',
                      style: TextStyle(
                        color: Color(0xFFFF6B35),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your SeChat session has been created successfully.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 24),

                    // Warning Box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning, color: Colors.red, size: 16),
                              SizedBox(width: 8),
                              Text(
                                'Important',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 4),
                          Text(
                            '• Save your login password securely\n'
                            '• You\'ll need it to access your account\n'
                            '• Never share your password with anyone',
                            style: TextStyle(color: Colors.red, fontSize: 11),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    // Login Details Section
                    _buildSectionHeader('Login Details'),
                    const SizedBox(height: 12),

                    if (widget.sessionId != null)
                      _buildDetailRowWithCopyFeedback(
                        'Session ID',
                        widget.sessionId!,
                        Icons.copy,
                        _copySessionIdToClipboard,
                        _showSessionIdCopied,
                      ),

                    if (widget.privateKey != null) ...[
                      const SizedBox(height: 8),
                      _buildDetailRowWithCopyFeedback(
                        'Login Password',
                        widget.privateKey!,
                        Icons.copy,
                        _copyPasswordToClipboard,
                        _showPasswordCopied,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Action Button (kept outside the scroll view)
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed:
                    _isStartChattingLoading ? null : _handleStartChatting,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: _isStartChattingLoading
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Starting...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.chat_bubble_outline, size: 20),
                          const SizedBox(width: 12),
                          const Text(
                            'Start Chatting',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  bool _isLoading = false;
  bool _isStartChattingLoading = false;
  bool _isWhyChooseExpanded = false;
  String? _error;

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

      final sessionData = result['sessionData'] as SessionData;
      final password = result['password'] as String;

      setState(() {
        _sessionId = sessionData.sessionId;
        _privateKey = password; // Store password for display
      });

      // Debug: Check if session was created successfully
      Logger.debug(' Debug: Session ID: ${sessionData.sessionId}');
      Logger.debug(' Debug: Public Key: ${sessionData.publicKey}');
      Logger.debug(' Debug: Display Name: ${sessionData.displayName}');
      Logger.debug(' Debug: Password: $password');
      Logger.debug(' Debug: Created At: ${sessionData.createdAt}');

      // Show success dialog with Session details
      await _showSuccessDialog();
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

  Future<void> _showSuccessDialog() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => _AccountCreatedActionSheet(
        sessionId: _sessionId,
        privateKey: _privateKey,
        displayName: _displayNameController.text.trim(),
        onStartChatting: () async {
          setState(() => _isStartChattingLoading = true);
          try {
            // Initialize notification services with new session
            final seSessionService = SeSessionService();
            await seSessionService.initializeNotificationServices();

            // Connect to socket with the new session ID
            if (_sessionId != null) {
              final socketService = SeSocketService.instance;

              // CRITICAL: Use connect() instead of initialize() for SeSocketService
              try {
                await socketService.connect(_sessionId!);
                Logger.success(
                    ' RegisterScreen:  Socket connection initiated for session: $_sessionId');

                // Wait a moment for connection to establish
                await Future.delayed(const Duration(seconds: 2));

                // Check if socket is connected
                if (socketService.isConnected) {
                  Logger.success(
                      ' RegisterScreen:  Socket connected successfully with session: $_sessionId');
                } else {
                  Logger.warning(
                      ' RegisterScreen:  Socket connection failed, but continuing with registration');
                }
              } catch (e) {
                Logger.error(' RegisterScreen:  Error connecting socket: $e');
                // Continue with registration even if socket fails
              }
            }

            // Add welcome notification to SharedPreferences
            await _addWelcomeNotification();

            if (context.mounted) {
              Navigator.of(context).pop();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const MainNavScreen()),
                (route) => false,
              );
            }
          } finally {
            if (mounted) {
              setState(() => _isStartChattingLoading = false);
            }
          }
        },
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
                      AppIcon(widthPerc: 0.2, heroTag: 'sechat_app_icon'),
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
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _isWhyChooseExpanded = !_isWhyChooseExpanded;
                                });
                              },
                              child: Row(
                                children: [
                                  Icon(Icons.security,
                                      color: const Color(0xFFFF6B35), size: 20),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Why Choose SeChat?',
                                      style: TextStyle(
                                        color: Color(0xFFFF6B35),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  AnimatedRotation(
                                    turns: _isWhyChooseExpanded ? 0.5 : 0.0,
                                    duration: const Duration(milliseconds: 300),
                                    child: Icon(
                                      Icons.keyboard_arrow_down,
                                      color: const Color(0xFFFF6B35),
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              child: _isWhyChooseExpanded
                                  ? Column(
                                      children: [
                                        const SizedBox(height: 12),
                                        _buildInfoRow(Icons.lock,
                                            'Your messages are private'),
                                        _buildInfoRow(Icons.visibility_off,
                                            'No phone numbers needed'),
                                        _buildInfoRow(Icons.storage,
                                            'Your data stays on your phone'),
                                        _buildInfoRow(
                                            Icons.person_off, 'Stay anonymous'),
                                      ],
                                    )
                                  : const SizedBox.shrink(),
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

                      CustomElevatedButton(
                        isLoading: _isLoading,
                        onPressed: _createSessionIdentity,
                        text: 'Create Session',
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

      // Mark that welcome notification has been shown to prevent it from appearing again
      await prefsService.setBool('has_shown_welcome_notification', true);

      Logger.success(
          '🔍 RegisterScreen:  Welcome notification added to SharedPreferences');
    } catch (e) {
      Logger.error('🔍 RegisterScreen:  Error adding welcome notification: $e');
    }
  }
}
