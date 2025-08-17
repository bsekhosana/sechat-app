import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import '../../../shared/providers/auth_provider.dart'; // Temporarily disabled
import 'login_screen.dart';
import 'register_screen.dart';
import '../../../shared/widgets/app_icon.dart';
import '../../../shared/widgets/custom_elevated_button.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _checking = true;
  bool _hasExistingUser = false;

  @override
  void initState() {
    super.initState();
    _checkExistingUser();
  }

  Future<void> _checkExistingUser() async {
    try {
      // Check if Session identity exists in local storage
      // final authProvider = context.read<AuthProvider>(); // Temporarily disabled

      // Check if user has existing Session identity - temporarily disabled
      // if (authProvider.isAuthenticated) {
      //   // User has existing Session identity, show login option
      //   setState(() {
      //     _hasExistingUser = true;
      //     _checking = false;
      //   });
      // } else {
      //   // No Session identity exists, only show registration
      //   setState(() {
      //       _hasExistingUser = false;
      //       _checking = false;
      //   });
      // }

      // Temporarily show only registration
      setState(() {
        _hasExistingUser = false;
        _checking = false;
      });
    } catch (e) {
      // If there's an error, default to showing only registration
      setState(() {
        _hasExistingUser = false;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFFF6B35),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 60),
              // App Icon and Title
              AppIcon(widthPerc: 0.32, heroTag: 'sechat_app_icon'),
              const SizedBox(height: 40),
              const Text(
                'Welcome to SeChat',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Private messaging that keeps your conversations safe',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black.withOpacity(0.7),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Chat with friends and family knowing your messages are private and secure. No phone numbers needed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black.withOpacity(0.5),
                  height: 1.5,
                ),
              ),
              const Spacer(),
              // Action Buttons
              Column(
                children: [
                  // Only show login button if user data exists
                  if (_hasExistingUser) ...[
                    Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF6B35), Color(0xFFFF8A65)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF6B35).withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.black,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Sign In to SeChat',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF404040),
                        width: 1,
                      ),
                    ),
                    child: CustomElevatedButton(
                      isLoading: false,
                      isPrimary: false,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const RegisterScreen(),
                          ),
                        );
                      },
                      text: 'Create New SeChat Account',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
