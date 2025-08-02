import 'dart:math';

class GuidGenerator {
  static const String _chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  static final Random _random = Random.secure();

  /// Generates a GUID (Globally Unique Identifier) for conversations
  /// Format: chat_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  static String generateGuid() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomPart = List.generate(32, (index) {
      if (index == 8 || index == 12 || index == 16 || index == 20) {
        return '-';
      }
      return _chars[_random.nextInt(_chars.length)];
    }).join();

    return 'chat_$timestamp-$randomPart';
  }

  /// Generates a unique session ID for SeSession
  /// Format: session_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  static String generateSessionGuid() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomPart = List.generate(32, (index) {
      if (index == 8 || index == 12 || index == 16 || index == 20) {
        return '-';
      }
      return _chars[_random.nextInt(_chars.length)];
    }).join();

    return 'session_$timestamp-$randomPart';
  }

  /// Generates a shorter unique ID for other purposes
  static String generateShortId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomPart =
        List.generate(8, (index) => _chars[_random.nextInt(_chars.length)])
            .join();

    return '${timestamp}_$randomPart';
  }

  /// Validates if a string is a valid GUID format
  static bool isValidGuid(String guid) {
    if (!guid.startsWith('chat_')) return false;

    final parts = guid.substring(5).split('-');
    if (parts.length != 5) return false;

    if (parts[0].length != 8 ||
        parts[1].length != 4 ||
        parts[2].length != 4 ||
        parts[3].length != 4 ||
        parts[4].length != 12) {
      return false;
    }

    return true;
  }

  /// Validates if a string is a valid session GUID format
  static bool isValidSessionGuid(String sessionGuid) {
    if (!sessionGuid.startsWith('session_')) return false;

    // final parts = sessionGuid.substring(8).split('-');
    // if (parts.length != 5) return false;

    // if (parts[0].length != 8 ||
    //     parts[1].length != 4 ||
    //     parts[2].length != 4 ||
    //     parts[3].length != 4 ||
    //     parts[4].length != 12) {
    //   return false;
    // }

    return true;
  }

  /// Generates a completely unique identifier with additional entropy
  static String generateUniqueId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final micros = DateTime.now().microsecond;
    final randomPart =
        List.generate(16, (index) => _chars[_random.nextInt(_chars.length)])
            .join();

    return '${timestamp}_${micros}_$randomPart';
  }
}
