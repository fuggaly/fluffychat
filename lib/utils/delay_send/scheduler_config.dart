import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local device config for talking to the matrix-send-scheduler service.
///
/// The base URL is not secret (just an endpoint), so it lives in
/// SharedPreferences like other app settings. The bearer token is a
/// credential and lives in FlutterSecureStorage instead.
class SchedulerConfig {
  static const _baseUrlKey = 'chat.fuggaly.scheduler_base_url';
  static const _bearerTokenKey = 'chat.fuggaly.scheduler_bearer_token';

  static const _secureStorage = FlutterSecureStorage();

  static Future<String?> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey);
  }

  static Future<void> setBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, value);
  }

  static Future<String?> getBearerToken() =>
      _secureStorage.read(key: _bearerTokenKey);

  static Future<void> setBearerToken(String value) =>
      _secureStorage.write(key: _bearerTokenKey, value: value);

  /// True once both the base URL and bearer token are configured.
  static Future<bool> isConfigured() async {
    final baseUrl = await getBaseUrl();
    final token = await getBearerToken();
    return baseUrl != null && baseUrl.isNotEmpty && token != null && token.isNotEmpty;
  }
}
