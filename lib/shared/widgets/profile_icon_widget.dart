import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../providers/auth_provider.dart';
import '../../core/services/api_service.dart';
import '../../features/auth/screens/welcome_screen.dart';

class ProfileIconWidget extends StatefulWidget {
  const ProfileIconWidget({super.key});

  @override
  State<ProfileIconWidget> createState() => _ProfileIconWidgetState();
}

class _ProfileIconWidgetState extends State<ProfileIconWidget>
    with SingleTickerProviderStateMixin {
  bool _isOnline = true;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

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
    _checkOnlineStatus();
  }

  void _checkOnlineStatus() async {
    // Check internet connectivity
    final connectivityResult = await Connectivity().checkConnectivity();
    setState(() {
      _isOnline = connectivityResult.contains(ConnectivityResult.mobile) ||
          connectivityResult.contains(ConnectivityResult.wifi) ||
          connectivityResult.contains(ConnectivityResult.ethernet);
    });

    // Listen to connectivity changes
    Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> result) {
      if (mounted) {
        setState(() {
          _isOnline = result.contains(ConnectivityResult.mobile) ||
              result.contains(ConnectivityResult.wifi) ||
              result.contains(ConnectivityResult.ethernet);
        });
      }
    });
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  void _showProfileMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: const DecorationImage(
                      image: AssetImage('assets/logo/seChat_cleanLogo.png'),
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
                        context.read<AuthProvider>().currentUser?.username ??
                            'User',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          color:
                              _isOnline ? const Color(0xFF4CAF50) : Colors.red,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Menu buttons
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

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
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

      final response = await ApiService.clearAllChats();

      Navigator.pop(context); // Close loading dialog

      if (response['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All chats cleared successfully'),
            backgroundColor: Color(0xFFFF6B35),
          ),
        );
      } else {
        throw Exception(response['message'] ?? 'Failed to clear chats');
      }
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

      final response = await ApiService.deleteAccount();

      Navigator.pop(context); // Close loading dialog

      if (response['success']) {
        // Log out and navigate to welcome screen
        await context.read<AuthProvider>().logout();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      } else {
        throw Exception(response['message'] ?? 'Failed to delete account');
      }
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

  @override
  Widget build(BuildContext context) {
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
                  color: (_isOnline ? const Color(0xFF4CAF50) : Colors.red)
                      .withOpacity(_glowAnimation.value * 0.6),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (_isOnline ? const Color(0xFF4CAF50) : Colors.red)
                      .withOpacity(_glowAnimation.value),
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
  }
}
