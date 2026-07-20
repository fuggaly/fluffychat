import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local device config for talking to matrix-bridge-relay. Mirrors
/// SchedulerConfig's split: base URL isn't secret (SharedPreferences), the
/// bearer token is a credential (FlutterSecureStorage). This is the
/// relay's own client-facing bearer token, unrelated to @bridgehub's
/// access token, which the relay holds server-side and this app never sees.
class BridgeRelayConfig {
  static const _baseUrlKey = 'chat.fuggaly.bridge_relay_base_url';
  static const _bearerTokenKey = 'chat.fuggaly.bridge_relay_bearer_token';

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

  static Future<bool> isConfigured() async {
    final baseUrl = await getBaseUrl();
    final token = await getBearerToken();
    return baseUrl != null && baseUrl.isNotEmpty && token != null && token.isNotEmpty;
  }
}
