import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'configured_bridge.dart';

/// Editable list of configured bridges (not hardcoded) - so adding a
/// future bridge is a settings entry, not a code change. Pre-populated
/// with sensible defaults for the two bridges already confirmed reachable
/// (their own config.yaml already declares these exact public addresses).
class BridgeSearchConfig {
  static const _key = 'chat.fuggaly.configured_bridges';

  static const _defaults = [
    ConfiguredBridge(
      id: 'whatsapp',
      kind: BridgeKind.whatsapp,
      label: 'WhatsApp',
      baseUrl: 'https://whatsapp.matrix.fuggaly.com',
    ),
    ConfiguredBridge(
      id: 'gmessages',
      kind: BridgeKind.googleMessages,
      label: 'Google Messages',
      baseUrl: 'https://gmessages.matrix.fuggaly.com',
    ),
  ];

  static Future<List<ConfiguredBridge>> getBridges() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return _defaults;
    final list = jsonDecode(raw) as List;
    return list
        .map((b) => ConfiguredBridge.fromJson((b as Map).cast()))
        .toList();
  }

  static Future<void> setBridges(List<ConfiguredBridge> bridges) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(bridges.map((b) => b.toJson()).toList()),
    );
  }
}
