import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'presence_manager.dart';

/// Manager for handling app lifecycle events and updating presence accordingly
class AppLifecycleManager extends StatefulWidget {
  final Widget child;
  final PresenceManager presenceManager;

  const AppLifecycleManager({
    super.key,
    required this.child,
    required this.presenceManager,
  });

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    print('📱 AppLifecycleManager: 🔧 Initialized');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    print('📱 AppLifecycleManager: 🗑️ Disposed');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _onAppResumed();
        break;
      case AppLifecycleState.paused:
        _onAppPaused();
        break;
      case AppLifecycleState.detached:
        _onAppDetached();
        break;
      case AppLifecycleState.hidden:
        _onAppHidden();
        break;
      case AppLifecycleState.inactive:
        _onAppInactive();
        break;
    }
  }

  /// Called when app comes to foreground
  void _onAppResumed() {
    print(
        '📱 AppLifecycleManager: 🚀 App resumed - updating presence to online');
    try {
      widget.presenceManager.onUserComingOnline();
    } catch (e) {
      print('📱 AppLifecycleManager: ❌ Error updating presence on resume: $e');
    }
  }

  /// Called when app goes to background
  void _onAppPaused() {
    print(
        '📱 AppLifecycleManager: ⏸️ App paused - updating presence to offline');
    try {
      widget.presenceManager.onUserGoingOffline();
    } catch (e) {
      print('📱 AppLifecycleManager: ❌ Error updating presence on pause: $e');
    }
  }

  /// Called when app is about to be terminated
  void _onAppDetached() {
    print(
        '📱 AppLifecycleManager: 🚨 App detached - updating presence to offline');
    try {
      widget.presenceManager.onUserGoingOffline();
    } catch (e) {
      print('📱 AppLifecycleManager: ❌ Error updating presence on detach: $e');
    }
  }

  /// Called when app is hidden (e.g., app switcher)
  void _onAppHidden() {
    print(
        '📱 AppLifecycleManager: 🙈 App hidden - updating presence to offline');
    try {
      widget.presenceManager.onUserGoingOffline();
    } catch (e) {
      print('📱 AppLifecycleManager: ❌ Error updating presence on hide: $e');
    }
  }

  /// Called when app becomes inactive (e.g., incoming call)
  void _onAppInactive() {
    print(
        '📱 AppLifecycleManager: ⚠️ App inactive - updating presence to offline');
    try {
      widget.presenceManager.onUserGoingOffline();
    } catch (e) {
      print(
          '📱 AppLifecycleManager: ❌ Error updating presence on inactive: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
