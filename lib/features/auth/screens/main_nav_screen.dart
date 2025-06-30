import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../search/screens/search_screen.dart';
import '../../chat/screens/chat_list_screen.dart';
import '../../chat/screens/invitations_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../settings/screens/settings_screen.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _selectedIndex = 0;

  static final List<Widget> _screens = <Widget>[
    ChatListScreen(),
    InvitationsScreen(),
    SearchScreen(),
    ProfileScreen(),
    SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            color: Colors.white.withOpacity(0.6),
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Theme.of(context).colorScheme.secondary,
              backgroundColor: Colors.transparent,
              elevation: 0,
              items: [
                BottomNavigationBarItem(
                  icon: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 1.0,
                      end: _selectedIndex == 0 ? 1.2 : 1.0,
                    ),
                    duration: const Duration(milliseconds: 200),
                    builder: (context, scale, child) => Transform.scale(
                      scale: scale,
                      child: FaIcon(FontAwesomeIcons.solidComments),
                    ),
                  ),
                  label: 'Chats',
                ),
                BottomNavigationBarItem(
                  icon: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 1.0,
                      end: _selectedIndex == 1 ? 1.2 : 1.0,
                    ),
                    duration: const Duration(milliseconds: 200),
                    builder: (context, scale, child) => Transform.scale(
                      scale: scale,
                      child: FaIcon(FontAwesomeIcons.solidEnvelope),
                    ),
                  ),
                  label: 'Invitations',
                ),
                BottomNavigationBarItem(
                  icon: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 1.0,
                      end: _selectedIndex == 2 ? 1.2 : 1.0,
                    ),
                    duration: const Duration(milliseconds: 200),
                    builder: (context, scale, child) => Transform.scale(
                      scale: scale,
                      child: FaIcon(FontAwesomeIcons.magnifyingGlass),
                    ),
                  ),
                  label: 'Search',
                ),
                BottomNavigationBarItem(
                  icon: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 1.0,
                      end: _selectedIndex == 3 ? 1.2 : 1.0,
                    ),
                    duration: const Duration(milliseconds: 200),
                    builder: (context, scale, child) => Transform.scale(
                      scale: scale,
                      child: FaIcon(FontAwesomeIcons.solidUser),
                    ),
                  ),
                  label: 'Profile',
                ),
                BottomNavigationBarItem(
                  icon: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 1.0,
                      end: _selectedIndex == 4 ? 1.2 : 1.0,
                    ),
                    duration: const Duration(milliseconds: 200),
                    builder: (context, scale, child) => Transform.scale(
                      scale: scale,
                      child: FaIcon(FontAwesomeIcons.gear),
                    ),
                  ),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
