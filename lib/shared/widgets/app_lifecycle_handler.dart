import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

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
        break;

      case AppLifecycleState.inactive:
        print('📱 AppLifecycleHandler: App inactive - transitioning');
        break;

      case AppLifecycleState.paused:
        print('📱 AppLifecycleHandler: App paused - background/minimized');
        break;

      case AppLifecycleState.detached:
        print('📱 AppLifecycleHandler: App detached - terminating');
        break;

      case AppLifecycleState.hidden:
        print('📱 AppLifecycleHandler: App hidden - by system UI');
        break;

      default:
        print('📱 AppLifecycleHandler: Unknown app lifecycle state: $state');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
