import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../../core/services/session_service.dart';

class AppLifecycleHandler extends StatefulWidget {
  final Widget child;

  const AppLifecycleHandler({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  State<AppLifecycleHandler> createState() => _AppLifecycleHandlerState();
}

class _AppLifecycleHandlerState extends State<AppLifecycleHandler>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        print('📱 AppLifecycleHandler: App resumed - foreground active');
        _handleAppResumed();
        break;

      case AppLifecycleState.inactive:
        print('📱 AppLifecycleHandler: App inactive - transitioning');
        break;

      case AppLifecycleState.paused:
        print('📱 AppLifecycleHandler: App paused - background/minimized');
        _handleAppPaused();
        break;

      case AppLifecycleState.detached:
        print('📱 AppLifecycleHandler: App detached - terminating');
        _handleAppDetached();
        break;

      case AppLifecycleState.hidden:
        print('📱 AppLifecycleHandler: App hidden - by system UI');
        break;

      default:
        print('📱 AppLifecycleHandler: Unknown app lifecycle state: $state');
        break;
    }
  }

  void _handleAppResumed() async {
    try {
      await SessionService.instance.onAppResumed();
    } catch (e) {
      print('📱 AppLifecycleHandler: Error handling app resume: $e');
    }
  }

  void _handleAppPaused() async {
    try {
      await SessionService.instance.onAppPaused();
    } catch (e) {
      print('📱 AppLifecycleHandler: Error handling app pause: $e');
    }
  }

  void _handleAppDetached() async {
    try {
      await SessionService.instance.onAppDetached();
    } catch (e) {
      print('📱 AppLifecycleHandler: Error handling app detach: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
