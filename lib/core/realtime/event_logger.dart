import 'package:flutter/foundation.dart';

mixin EventLogger {
  bool get enableLogs => true;
  void logE(String tag, String message) {
    if (!enableLogs) return;
    debugPrint('$tag $message');
  }
}
