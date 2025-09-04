import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '/..//../core/utils/logger.dart';

class StoreLinkResolver {
  static const _fallbackWeb = 'https://sechat.app';
  static const _cacheTtlHours = 24;

  // Fallback URLs for when dynamic resolution fails
  static const _fallbackIOS =
      'https://apps.apple.com/app/sechat/id123456789'; // Replace with actual App Store ID
  static const _fallbackAndroid =
      'https://play.google.com/store/apps/details?id=com.sechat.app';

  static Future<String> resolve({String? fallback}) async {
    final prefs = await SharedPreferences.getInstance();
    final platformKey =
        Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'web');
    final cacheKey = 'store_link_$platformKey';
    final cacheWhenKey = '${cacheKey}_ts';

    // 1) Use fresh cache if available
    final cached = prefs.getString(cacheKey);
    final cachedAt = prefs.getInt(cacheWhenKey);
    if (cached != null && cachedAt != null) {
      final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
      if (age < Duration(hours: _cacheTtlHours).inMilliseconds) {
        return cached;
      }
    }

    String resolved = fallback ?? _fallbackWeb;

    try {
      if (Platform.isIOS) {
        resolved = await _resolveIOSStoreLink();
      } else if (Platform.isAndroid) {
        resolved = await _resolveAndroidStoreLink();
      } else {
        resolved = fallback ?? _fallbackWeb;
      }
    } catch (e) {
      // If dynamic resolution fails, use fallbacks
      if (Platform.isIOS) {
        resolved = fallback ?? _fallbackIOS;
      } else if (Platform.isAndroid) {
        resolved = fallback ?? _fallbackAndroid;
      } else {
        resolved = fallback ?? _fallbackWeb;
      }
    }

    // Cache it
    await prefs.setString(cacheKey, resolved);
    await prefs.setInt(cacheWhenKey, DateTime.now().millisecondsSinceEpoch);
    return resolved;
  }

  /// Dynamically resolves iOS App Store link using iTunes Search API
  static Future<String> _resolveIOSStoreLink() async {
    const bundleId = 'com.sechat.app'; // Your actual bundle ID

    try {
      final uri = Uri.https('itunes.apple.com', '/lookup', {
        'bundleId': bundleId,
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          final app = results.first as Map<String, dynamic>;
          final trackViewUrl = app['trackViewUrl'] as String?;

          if (trackViewUrl != null && trackViewUrl.isNotEmpty) {
            return trackViewUrl;
          }
        }
      }
    } catch (e) {
      // Log error for debugging but don't throw
      Logger.debug('iOS store link resolution failed: $e');
    }

    // Return fallback if dynamic resolution fails
    return _fallbackIOS;
  }

  /// Dynamically resolves Android Play Store link
  static Future<String> _resolveAndroidStoreLink() async {
    const packageName = 'com.sechat.app'; // Your actual package name
    final playStoreUrl =
        'https://play.google.com/store/apps/details?id=$packageName';

    try {
      // Verify the app exists by checking the Play Store page
      final response = await http
          .get(Uri.parse(playStoreUrl))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        // Check if the page contains app-specific content (not a 404 or error page)
        final body = response.body.toLowerCase();
        if (body.contains('sechat') || body.contains('com.sechat.app')) {
          return playStoreUrl;
        }
      }
    } catch (e) {
      // Log error for debugging but don't throw
      Logger.debug('Android store link resolution failed: $e');
    }

    // Return fallback if dynamic resolution fails
    return _fallbackAndroid;
  }
}
