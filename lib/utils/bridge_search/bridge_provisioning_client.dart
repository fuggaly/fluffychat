import 'dart:convert';

import 'package:http/http.dart' as http;

import 'bridge_relay_config.dart';

class BridgeContact {
  final String id;
  final String name;
  final String? avatarUrl;
  final List<String> identifiers;
  final String? mxid;

  BridgeContact({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.identifiers = const [],
    this.mxid,
  });

  /// The identifier to pass back to resolve_identifier/create_dm to act on
  /// this specific contact. Prefer [mxid] when present - the bridgev2
  /// provisioning API tries to parse the identifier as a ghost mxid first,
  /// which is the robust path (bypasses each network connector's own,
  /// less-reliable string-based identifier resolution entirely). Falls
  /// back to [id] only when no mxid was returned (e.g. a fresh
  /// search_users hit with no existing ghost yet).
  String get actionIdentifier => (mxid != null && mxid!.isNotEmpty) ? mxid! : id;

  factory BridgeContact.fromJson(Map<String, Object?> json) => BridgeContact(
    id: json['id'] as String,
    name: (json['name'] as String?) ?? (json['id'] as String),
    avatarUrl: json['avatar_url'] as String?,
    identifiers:
        (json['identifiers'] as List?)?.cast<String>() ?? const [],
    mxid: json['mxid'] as String?,
  );
}

class BridgeProvisioningException implements Exception {
  final String bridgeLabel;
  final String message;

  BridgeProvisioningException(this.bridgeLabel, this.message);

  @override
  String toString() => '$bridgeLabel: $message';
}

/// Client for matrix-bridge-relay's HTTP API. Bridge sessions on this
/// homeserver are established under @bridgehub, not the app user's own
/// account, so provisioning requests can't be made with the user's own
/// Matrix access token (the bridge would correctly say "not logged in") -
/// the relay holds @bridgehub's token server-side and this client never
/// sees it, authenticating only with its own relay bearer token.
class BridgeProvisioningClient {
  Future<Map<String, String>> _authHeaders() async {
    final token = await BridgeRelayConfig.getBearerToken();
    if (token == null || token.isEmpty) {
      throw BridgeProvisioningException(
        'relay',
        'Bridge search is not configured yet (missing relay token).',
      );
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<Uri> _uri(String path) async {
    final baseUrl = await BridgeRelayConfig.getBaseUrl();
    if (baseUrl == null || baseUrl.isEmpty) {
      throw BridgeProvisioningException(
        'relay',
        'Bridge search is not configured yet (missing relay URL).',
      );
    }
    return Uri.parse('$baseUrl$path');
  }

  Future<List<BridgeContact>> contacts(String bridgeId, String bridgeLabel) async {
    final res = await http.get(
      await _uri('/bridges/$bridgeId/contacts'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) {
      throw BridgeProvisioningException(bridgeLabel, _errorMessage(res));
    }
    final list = (jsonDecode(res.body) as Map)['contacts'] as List;
    return list
        .map((c) => BridgeContact.fromJson((c as Map).cast()))
        .toList();
  }

  Future<List<BridgeContact>> searchUsers(
    String bridgeId,
    String bridgeLabel,
    String query,
  ) async {
    final res = await http.post(
      await _uri('/bridges/$bridgeId/search_users'),
      headers: await _authHeaders(),
      body: jsonEncode({'query': query}),
    );
    if (res.statusCode != 200) {
      throw BridgeProvisioningException(bridgeLabel, _errorMessage(res));
    }
    final list = (jsonDecode(res.body) as Map)['results'] as List;
    return list
        .map((c) => BridgeContact.fromJson((c as Map).cast()))
        .toList();
  }

  Future<String> resolveIdentifier(
    String bridgeId,
    String bridgeLabel,
    String id, {
    bool createChat = false,
  }) async {
    // Encoded exactly once here - id may now be a full mxid (@user:server),
    // which needs escaping to survive as a single path segment. The relay
    // decodes this once and re-encodes once more on its own outbound hop -
    // never double-encode along the way.
    final res = await http.get(
      await _uri(
        '/bridges/$bridgeId/resolve_identifier/${Uri.encodeComponent(id)}?create_chat=$createChat',
      ),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) {
      throw BridgeProvisioningException(bridgeLabel, _errorMessage(res));
    }
    final json = jsonDecode(res.body) as Map<String, Object?>;
    return json['dm_room_mxid'] as String;
  }

  Future<String> createDm(String bridgeId, String bridgeLabel, String id) async {
    final res = await http.post(
      await _uri('/bridges/$bridgeId/create_dm/${Uri.encodeComponent(id)}'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) {
      throw BridgeProvisioningException(bridgeLabel, _errorMessage(res));
    }
    final json = jsonDecode(res.body) as Map<String, Object?>;
    return json['dm_room_mxid'] as String;
  }

  String _errorMessage(http.Response res) {
    try {
      final json = jsonDecode(res.body);
      return (json['error'] as String?) ?? 'Unexpected error (${res.statusCode})';
    } catch (_) {
      return 'Unexpected error (${res.statusCode})';
    }
  }
}
