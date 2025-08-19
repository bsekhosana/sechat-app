import 'package:flutter/widgets.dart';

/// AppStateService
/// Tracks whether the app is in foreground or background so other services
/// (e.g., socket handlers) can decide how to present UI.
class AppStateService {
  AppStateService._internal();
  static final AppStateService _instance = AppStateService._internal();
  factory AppStateService() => _instance;

  AppLifecycleState _lastLifecycleState = AppLifecycleState.resumed;

  bool get isForeground => _lastLifecycleState == AppLifecycleState.resumed;

  void updateLifecycleState(AppLifecycleState state) {
    _lastLifecycleState = state;
  }
}
