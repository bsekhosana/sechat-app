import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/providers/auth_provider.dart';
import '../screens/main_nav_screen.dart';
import '../../../shared/widgets/app_icon.dart';
import '../../../core/services/encryption_service.dart';
import 'package:local_auth/local_auth.dart';
import '../screens/welcome_screen.dart';
import '../../../shared/widgets/orange_button.dart';

class LoginScreen extends StatefulWidget {
  final String? username;
  final bool showBackButton;
  const LoginScreen({super.key, this.username, this.showBackButton = true});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _username;
  String? _errorMessage;
  final LocalAuthentication auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _initUsername();
  }

  Future<void> _initUsername() async {
    if (widget.username != null) {
      setState(() {
        _username = widget.username;
      });
    } else {
      // Try to get username from local storage
      final authProvider = context.read<AuthProvider>();
      final storedUsername = await authProvider.getStoredUsername();
      if (storedUsername != null) {
        setState(() {
          _username = storedUsername;
        });
      }
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final deviceId = await EncryptionService.getDeviceId();
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(
      deviceId: deviceId,
      password: _passwordController.text,
    );

    if (success && mounted) {
      setState(() {
        _errorMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login successful!'),
          backgroundColor: Color(0xFFFF6B35),
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => MainNavScreen()),
        (route) => false,
      );
    } else {
      setState(() {
        final error = authProvider.error?.toLowerCase() ?? '';
        if (error.contains('invalid credentials')) {
          _errorMessage = 'Incorrect credentials, please try again.';
        } else {
          _errorMessage = 'Login failed. Please try again.';
        }
      });
    }
  }

  void _onForgotPassword() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => _PasswordResetSheet(),
    );
  }

  Future<void> _biometricLogin() async {
    try {
      final canCheck = await auth.canCheckBiometrics;
      final isAvailable = await auth.isDeviceSupported();
      if (!canCheck || !isAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric authentication not available'),
            backgroundColor: Color(0xFF666666),
          ),
        );
        return;
      }
      final didAuthenticate = await auth.authenticate(
        localizedReason: 'Please authenticate to login',
        options: const AuthenticationOptions(biometricOnly: true),
      );
      if (didAuthenticate) {
        // If you want passwordless, just call login with deviceId and a dummy password
        final deviceId = await EncryptionService.getDeviceId();
        final authProvider = context.read<AuthProvider>();
        final success = await authProvider.login(
          deviceId: deviceId,
          password:
              _passwordController.text, // or store/retrieve password securely
        );
        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Login successful!'),
              backgroundColor: Color(0xFFFF6B35),
            ),
          );
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => MainNavScreen()),
            (route) => false,
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric authentication failed'),
            backgroundColor: Color(0xFF666666),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Biometric error: $e'),
          backgroundColor: const Color(0xFF666666),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
        backgroundColor: const Color(0xFF121212),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('Login'),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: widget.showBackButton
              ? IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
        ),
        body: SafeArea(
          child: Center(
            child: Consumer<AuthProvider>(
              builder: (context, authProvider, child) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      // mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        AppIcon(widthPerc: 0.3),
                        SizedBox(height: screenHeight * 0.05), // ~2% spacing
                        if (_username != null && _username!.isNotEmpty) ...[
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Welcome Back ',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                TextSpan(
                                  text: '$_username!',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFFF6B35),
                                  ),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        if (_username == null || _username!.isEmpty) ...[
                          Text(
                            'Welcome Back',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        SizedBox(height: screenHeight * 0.02),
                        Text(
                          'Sign in to continue chatting',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: screenHeight * 0.05), // ~2% spacing

                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle:
                                TextStyle(color: Colors.white.withOpacity(0.7)),
                            prefixIcon: Icon(Icons.lock_outline,
                                color: Colors.white.withOpacity(0.7)),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: Colors.white.withOpacity(0.7),
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFF404040)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: Color(0xFF404040)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: Color(0xFFFF6B35), width: 2),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF1E1E1E),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your password';
                            }
                            return null;
                          },
                        ),

                        if (_errorMessage != null)
                          SizedBox(height: screenHeight * 0.02),

                        if (_errorMessage != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              border: Border.all(color: Colors.red),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        SizedBox(height: screenHeight * 0.05),
                        OrangeButton(
                          label: 'Login',
                          onPressed: _login,
                          primary: true,
                        ),
                        SizedBox(height: screenHeight * 0.02),
                        OrangeButton(
                          label: 'Forgot password?',
                          onPressed: _onForgotPassword,
                          primary: false,
                        ),
                        if (widget.username != null) ...[
                          SizedBox(height: screenHeight * 0.02), // ~2% spacing
                          Center(
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2C2C2C),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFF404040),
                                  width: 1,
                                ),
                              ),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.fingerprint,
                                  size: 32,
                                  color: Color(0xFFFF6B35),
                                ),
                                onPressed: _biometricLogin,
                                tooltip: 'Login with biometrics',
                              ),
                            ),
                          ),
                        ],
                        SizedBox(height: screenHeight * 0.02), // ~2% spacing
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ));
  }
}

class _PasswordResetSheet extends StatefulWidget {
  @override
  State<_PasswordResetSheet> createState() => _PasswordResetSheetState();
}

class _PasswordResetSheetState extends State<_PasswordResetSheet> {
  String? _securityQuestion;
  String? _securityAnswer;
  String? _error;
  bool _loading = false;
  bool _showNewPassword = false;
  final _answerController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchSecurityQuestion();
  }

  Future<void> _fetchSecurityQuestion() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final authProvider = context.read<AuthProvider>();
      final deviceId = await authProvider.storage.read(key: 'device_id');
      if (deviceId == null) {
        setState(() {
          _error = 'No device ID found.';
          _loading = false;
        });
        return;
      }
      final question = await authProvider.getUserSecurityQuestion();
      if (question != null) {
        setState(() {
          _securityQuestion = question;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Could not fetch security question.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _verifyAnswer() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final authProvider = context.read<AuthProvider>();
      final correct =
          await authProvider.verifySecurityAnswer(_answerController.text);
      if (correct) {
        setState(() {
          _showNewPassword = true;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Incorrect answer. Please try again.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _resetPassword() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_newPasswordController.text.isEmpty ||
          _confirmPasswordController.text.isEmpty) {
        setState(() {
          _error = 'Please fill in all fields.';
          _loading = false;
        });
        return;
      }
      if (_newPasswordController.text != _confirmPasswordController.text) {
        setState(() {
          _error = 'Passwords do not match.';
          _loading = false;
        });
        return;
      }
      final authProvider = context.read<AuthProvider>();
      final success =
          await authProvider.resetPassword(_newPasswordController.text);
      if (success) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password reset successful!'),
              backgroundColor: Color(0xFFFF6B35),
            ),
          );
          // Auto-login
          final deviceId = await authProvider.storage.read(key: 'device_id');
          if (deviceId != null) {
            await authProvider.login(
              deviceId: deviceId,
              password: _newPasswordController.text,
            );
          }
        }
      } else {
        setState(() {
          _error = 'Failed to reset password.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
            'Are you sure you want to delete your account? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() {
        _loading = true;
        _error = null;
      });
      final authProvider = context.read<AuthProvider>();
      final success = await authProvider.deleteAccount();
      if (success) {
        if (mounted) {
          Navigator.of(context).pop();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            (route) => false,
          );
        }
      } else {
        setState(() {
          _error = 'Failed to delete account.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF232323),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF6B35)))
            : ListView(
                controller: scrollController,
                shrinkWrap: true,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 24),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red)),
                    ),
                  ],
                  if (_securityQuestion != null && !_showNewPassword) ...[
                    Text(
                      'Security Question',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _securityQuestion!,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _answerController,
                      decoration: const InputDecoration(
                        labelText: 'Your Answer',
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OrangeButton(
                      onPressed: _verifyAnswer,
                      label: 'Submit',
                      primary: true,
                    ),
                  ],
                  if (_showNewPassword) ...[
                    TextField(
                      controller: _newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm Password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OrangeButton(
                      onPressed: _resetPassword,
                      label: 'Reset Password',
                      primary: true,
                    ),
                  ],
                  const SizedBox(height: 32),
                  Divider(color: Colors.white.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Center(
                    child: OrangeButton(
                      onPressed: _deleteAccount,
                      label: 'Delete Account',
                      primary: false,
                      isDelete: true,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
