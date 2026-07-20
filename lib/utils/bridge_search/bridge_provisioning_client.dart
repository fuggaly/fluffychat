import 'dart:convert';

import 'package:http/http.dart' as http;

import 'configured_bridge.dart';

class BridgeContact {
  final String id;
  final String name;
  final String? avatarUrl;
  final List<String> identifiers;

  BridgeContact({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.identifiers = const [],
  });

  factory BridgeContact.fromJson(Map<String, Object?> json) => BridgeContact(
    id: json['id'] as String,
    name: (json['name'] as String?) ?? (json['id'] as String),
    avatarUrl: json['avatar_url'] as String?,
    identifiers:
        (json['identifiers'] as List?)?.cast<String>() ?? const [],
  );
}

class BridgeProvisioningException implements Exception {
  final String bridgeLabel;
  final String message;

  BridgeProvisioningException(this.bridgeLabel, this.message);

  @override
  String toString() => '$bridgeLabel: $message';
}

/// Thin client for one bridge's bridgev2 provisioning API
/// (`/_matrix/provision/v3/...`), authenticated with the user's own
/// logged-in Matrix access token (works when the bridge has
/// `allow_matrix_auth: true`, which whatsapp/gmessages already do here -
/// no separate bridge secret needed client-side).
class BridgeProvisioningClient {
  final ConfiguredBridge bridge;
  final String matrixAccessToken;
  final String matrixUserId;

  BridgeProvisioningClient({
    required this.bridge,
    required this.matrixAccessToken,
    required this.matrixUserId,
  });

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $matrixAccessToken',
  };

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse(
    '${bridge.baseUrl}/_matrix/provision/v3$path',
  ).replace(queryParameters: {'user_id': matrixUserId, ...?query});

  Future<bool> whoami() async {
    final res = await http.get(_uri('/whoami'), headers: _headers);
    return res.statusCode == 200;
  }

  Future<List<BridgeContact>> contacts() async {
    final res = await http.get(_uri('/contacts'), headers: _headers);
    if (res.statusCode != 200) {
      throw BridgeProvisioningException(bridge.label, _errorMessage(res));
    }
    final list = jsonDecode(res.body) as List;
    return list
        .map((c) => BridgeContact.fromJson((c as Map).cast()))
        .toList();
  }

  Future<List<BridgeContact>> searchUsers(String query) async {
    final res = await http.post(
      _uri('/search_users'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'query': query}),
    );
    if (res.statusCode != 200) {
      throw BridgeProvisioningException(bridge.label, _errorMessage(res));
    }
    final list = jsonDecode(res.body) as List;
    return list
        .map((c) => BridgeContact.fromJson((c as Map).cast()))
        .toList();
  }

  /// Resolves an identifier to a room, creating the DM if [createChat] is
  /// true (needed for Google Messages, which has no create_dm endpoint of
  /// its own - resolve_identifier does double duty).
  Future<String> resolveIdentifier(String id, {bool createChat = false}) async {
    final res = await http.get(
      _uri('/resolve_identifier/$id', {'create_chat': createChat.toString()}),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw BridgeProvisioningException(bridge.label, _errorMessage(res));
    }
    final json = jsonDecode(res.body) as Map<String, Object?>;
    return json['dm_room_mxid'] as String;
  }

  Future<String> createDm(String id) async {
    final res = await http.post(_uri('/create_dm/$id'), headers: _headers);
    if (res.statusCode != 200) {
      throw BridgeProvisioningException(bridge.label, _errorMessage(res));
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
