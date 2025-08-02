import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sechat_app/core/services/se_session_service.dart';
import 'package:sechat_app/features/auth/screens/register_screen.dart';
import 'package:sechat_app/features/auth/screens/welcome_screen.dart';
import 'package:sechat_app/features/auth/screens/main_nav_screen.dart';
import 'package:sechat_app/features/chat/screens/chat_screen.dart';
import 'package:sechat_app/shared/widgets/app_icon.dart';
import 'package:sechat_app/shared/widgets/custom_textfield.dart';
import 'package:sechat_app/shared/widgets/custom_elevated_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _showPassword = false;
  bool _isCreatingNewAccount = false;
  String _sessionDisplayName = '';

  @override
  void initState() {
    super.initState();
    _loadDisplayName();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadDisplayName() async {
    final seSessionService = SeSessionService();
    final session = await seSessionService.loadSession();
    if (session != null) {
      setState(() {
        _displayNameController.text = session.displayName;
        _sessionDisplayName = session.displayName;
      });
      print('🔍 LoginScreen: Loaded display name: ${session.displayName}');
    } else {
      print('🔍 LoginScreen: No session found');
    }
  }

  String _getDisplayName() {
    // Use the stored session display name if available
    if (_sessionDisplayName.isNotEmpty) {
      return _sessionDisplayName;
    }
    // Fall back to the controller text or default
    return _displayNameController.text.isNotEmpty
        ? _displayNameController.text
        : 'User';
  }

  void _showForgotPasswordDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Forgot Password',
            style: TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Since SeChat uses local encryption, passwords cannot be recovered. You\'ll need to create a new account to start fresh.',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[600],
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showDeleteSessionConfirmation();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Create New Account',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteSessionConfirmation() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
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
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Title
            const Text(
              'Create New Account',
              style: TextStyle(
                color: Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Message
            Text(
              'This will delete your current session and all associated data. You\'ll need to create a new account with a new password.',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: CustomElevatedButton(
                    isLoading: false,
                    onPressed: () => Navigator.of(context).pop(),
                    text: 'Cancel',
                    icon: Icons.close,
                    isPrimary: false,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CustomElevatedButton(
                    isLoading: false,
                    onPressed: () {
                      Navigator.of(context).pop();
                      _deleteSessionAndNavigate();
                    },
                    text: 'Delete & Create New',
                    icon: Icons.delete_forever,
                    isPrimary: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSessionAndNavigate() async {
    try {
      final seSessionService = SeSessionService();
      await seSessionService.deleteSession();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const RegisterScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenHeight < 600 || screenWidth < 350;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isSmallScreen ? 16.0 : 24.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: screenHeight -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo and Title
                  SizedBox(height: isSmallScreen ? 20 : 40),
                  AppIcon(widthPerc: 0.32),
                  SizedBox(height: isSmallScreen ? 16 : 24),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Welcome back, ',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 24 : 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        TextSpan(
                          text: _getDisplayName(),
                          style: TextStyle(
                            fontSize: isSmallScreen ? 24 : 32,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFFF6B35),
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: isSmallScreen ? 8 : 12),
                  Text(
                    'Secure, private messaging with Session Protocol',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: isSmallScreen ? 32 : 48),

                  // Form
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // Password Field
                        CustomTextfield(
                          controller: _passwordController,
                          isPassword: true,
                          label: 'Password',
                          icon: Icons.lock,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your password';
                            }
                            if (value.length != 6) {
                              return 'Password must be exactly 6 characters';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: isSmallScreen ? 24 : 32),

                        // Login Button
                        CustomElevatedButton(
                          isLoading: _isLoading,
                          onPressed: _handleLogin,
                          text: 'Login to SeChat',
                          icon: Icons.login,
                          isPrimary: true,
                          orangeLoading: true,
                        ),
                        SizedBox(height: isSmallScreen ? 16 : 20),

                        // Forgot Password Button
                        CustomElevatedButton(
                          isLoading: _isLoading,
                          onPressed: _showForgotPasswordDialog,
                          text: 'Forgot Password',
                          icon: Icons.help_outline,
                          isPrimary: false,
                        ),
                      ],
                    ),
                  ),

                  // Spacer to push content to center
                  const Spacer(),

                  // Footer
                  SizedBox(height: isSmallScreen ? 16 : 24),
                  Text(
                    'Your privacy is our priority',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 12 : 14,
                      color: Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: isSmallScreen ? 16 : 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final seSessionService = SeSessionService();
      final displayName = _displayNameController.text.trim();
      final password = _passwordController.text.trim();

      if (_isCreatingNewAccount) {
        // Navigate to registration screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const RegisterScreen(),
          ),
        );
      } else {
        // Login with existing account
        final success = await seSessionService.login(displayName, password);

        if (success) {
          // Initialize notification services with logged in session
          await seSessionService.initializeNotificationServices();

          // Navigate to main app
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => MainNavScreen()),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Invalid display name or password'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
