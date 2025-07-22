import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sechat_app/shared/providers/auth_provider.dart';
import 'package:sechat_app/shared/widgets/qr_generator_widget.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sessionIdController = TextEditingController();
  final _privateKeyController = TextEditingController();
  bool _isLoading = false;
  bool _showPrivateKey = false;
  bool _isCreatingNewAccount = false;

  @override
  void dispose() {
    _sessionIdController.dispose();
    _privateKeyController.dispose();
    super.dispose();
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
                  Image.asset(
                    'assets/logo/seChat_Logo.png',
                    height: isSmallScreen ? 80 : 120,
                    width: isSmallScreen ? 80 : 120,
                  ),
                  SizedBox(height: isSmallScreen ? 16 : 24),
                  Text(
                    'Welcome to SeChat',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 24 : 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
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
                        // Session ID Field
                        TextFormField(
                          controller: _sessionIdController,
                          decoration: InputDecoration(
                            labelText: 'Session ID (Optional)',
                            hintText: 'Enter your Session ID',
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          validator: (value) {
                            if (value != null && value.isNotEmpty) {
                              if (value.length < 10) {
                                return 'Session ID must be at least 10 characters';
                              }
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: isSmallScreen ? 16 : 20),

                        // Private Key Field
                        TextFormField(
                          controller: _privateKeyController,
                          obscureText: !_showPrivateKey,
                          decoration: InputDecoration(
                            labelText: 'Private Key (Optional)',
                            hintText: 'Enter your private key',
                            prefixIcon: const Icon(Icons.key),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPrivateKey
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _showPrivateKey = !_showPrivateKey;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          validator: (value) {
                            if (value != null && value.isNotEmpty) {
                              if (value.length < 20) {
                                return 'Private key must be at least 20 characters';
                              }
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: isSmallScreen ? 24 : 32),

                        // Buttons
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                vertical: isSmallScreen ? 14 : 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _isCreatingNewAccount
                                          ? 'Create New SeChat Account'
                                          : 'Login to SeChat',
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 14 : 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 16 : 20),

                        // Toggle Button
                        TextButton(
                          onPressed: _isLoading
                              ? null
                              : () {
                                  if (_isCreatingNewAccount) {
                                    // Switch to login mode
                                    setState(() {
                                      _isCreatingNewAccount = false;
                                    });
                                  } else {
                                    // Navigate to registration screen
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const RegisterScreen(),
                                      ),
                                    );
                                  }
                                },
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _isCreatingNewAccount
                                  ? 'Already have an account? Login'
                                  : 'New to SeChat? Create New Account',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 12 : 14,
                                color: Colors.blue,
                              ),
                            ),
                          ),
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
      final authProvider = context.read<AuthProvider>();

      if (_isCreatingNewAccount) {
        // Create new account
        final displayName = _sessionIdController.text.trim().isNotEmpty
            ? _sessionIdController.text.trim()
            : 'SeChat User';
        await authProvider.createSessionIdentity(displayName: displayName);
      } else {
        // Import existing account
        final sessionId = _sessionIdController.text.trim();
        final privateKey = _privateKeyController.text.trim();

        if (sessionId.isNotEmpty || privateKey.isNotEmpty) {
          await authProvider.importSessionIdentity(
            sessionId: sessionId.isNotEmpty ? sessionId : '',
            privateKey: privateKey.isNotEmpty ? privateKey : '',
          );
        } else {
          // Create new account if no credentials provided
          await authProvider.createSessionIdentity(displayName: 'SeChat User');
        }
      }

      // Navigate to main app
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/main');
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
