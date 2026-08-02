import 'dart:convert';

import 'package:http/http.dart' as http;

import 'address_book_contact.dart';
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

/// A server-verified pairing of rooms likely belonging to the same real
/// contact across two or more bridged networks - computed once by
/// matrix-bridge-relay (see its suggestedGroupings.mjs) from
/// contacts-sync's cross-bridge ghost mapping plus @bridgehub's own room
/// membership, cached, and read here as-is. [rooms] are Matrix room ids
/// (mxids) - the caller still needs to check which of them this device
/// actually has joined locally before treating it as actionable.
///
/// [matchedBy] is "uid" when every room came from ghosts resolved to the
/// exact same address-book contact by its stable vCard uid - strong enough
/// to auto-merge with zero user interaction (see AutoMergeService), which
/// still separately checks room.isDirectChat on the human's own account
/// before doing so (the relay can't reliably tell a 1:1 from a group chat
/// itself - @bridgehub is a headless account with no real client
/// maintaining that state, see suggestedGroupings.mjs). "name" means the
/// match fell back to comparing display_name strings only (e.g. a contact
/// with no vCard uid), which can't rule out two different contacts sharing
/// the same name - shown for manual review in Settings > Unified Contacts
/// instead, same as this whole feature worked before the uid distinction
/// existed.
class SuggestedGrouping {
  final String label;
  final List<String> rooms;
  final String matchedBy;

  SuggestedGrouping({
    required this.label,
    required this.rooms,
    this.matchedBy = 'name',
  });

  factory SuggestedGrouping.fromJson(Map<String, Object?> json) =>
      SuggestedGrouping(
        label: json['label'] as String,
        rooms: (json['rooms'] as List).cast<String>(),
        matchedBy: (json['matchedBy'] as String?) ?? 'name',
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

  /// Searches the real address book (contacts-sync's compiled data),
  /// independent of any single bridge's own contact cache - see
  /// matrix-bridge-relay's contactsSearch.mjs for why this exists (both
  /// bridges' own contact listings turned out to be incomplete substitutes
  /// for the actual address book).
  Future<List<AddressBookContact>> searchAddressBook(String query) async {
    final res = await http.get(
      await _uri('/contacts/search?query=${Uri.encodeComponent(query)}'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) {
      throw BridgeProvisioningException('address book', _errorMessage(res));
    }
    final list = (jsonDecode(res.body) as Map)['contacts'] as List;
    return list
        .map((c) => AddressBookContact.fromJson((c as Map).cast()))
        .toList();
  }

  /// The relay's already-computed, cached list of likely cross-bridge
  /// contact pairings ("calculate once, read many" - every device just
  /// reads this, no per-client matching). See [SuggestedGrouping].
  Future<List<SuggestedGrouping>> suggestedGroupings() async {
    final res = await http.get(
      await _uri('/suggested_groupings'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) {
      throw BridgeProvisioningException(
        'suggested groupings',
        _errorMessage(res),
      );
    }
    final list = (jsonDecode(res.body) as Map)['suggestions'] as List;
    return list
        .map((s) => SuggestedGrouping.fromJson((s as Map).cast()))
        .toList();
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

  /// A live reachability check for a phone number on a specific bridge -
  /// resolve_identifier with create_chat=false, but returning the full
  /// resolved contact (for display) instead of just a room id, and
  /// treating "not on this network" as a clean null rather than an
  /// exception. Confirmed via each bridge's own source (see
  /// matrix-bridge-relay's CLAUDE.md): for WhatsApp this actually queries
  /// IsOnWhatsApp and 404s for a number with no WhatsApp account (e.g. a
  /// landline) - for Google Messages it's a no-op "fake success" for any
  /// syntactically valid number, since SMS has no real reachability check
  /// to make. This is what the address-book cross-offer step should use
  /// instead of blindly assuming every known number works on every
  /// phone-identifier bridge.
  Future<BridgeContact?> checkReachable(
    String bridgeId,
    String bridgeLabel,
    String id,
  ) async {
    final res = await http.get(
      await _uri(
        '/bridges/$bridgeId/resolve_identifier/${Uri.encodeComponent(id)}?create_chat=false',
      ),
      headers: await _authHeaders(),
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw BridgeProvisioningException(bridgeLabel, _errorMessage(res));
    }
    return BridgeContact.fromJson(
      (jsonDecode(res.body) as Map).cast(),
    );
  }

  Future<String> createDm(
    String bridgeId,
    String bridgeLabel,
    String id, {
    String? inviteUserId,
  }) async {
    final inviteParam = inviteUserId != null
        ? '?invite=${Uri.encodeComponent(inviteUserId)}'
        : '';
    final res = await http.post(
      await _uri('/bridges/$bridgeId/create_dm/${Uri.encodeComponent(id)}$inviteParam'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) {
      throw BridgeProvisioningException(bridgeLabel, _errorMessage(res));
    }
    final json = jsonDecode(res.body) as Map<String, Object?>;
    final dmRoomMxid = json['dm_room_mxid'] as String?;
    if (dmRoomMxid == null) {
      // Defensive: a 200 with no dm_room_mxid is a real thing at least one
      // bridge can return (confirmed on Google Messages' resolve_identifier,
      // see git history) - fail with a clear message here too rather than
      // risking the same unhandled type-cast crash if it ever happens on
      // create_dm.
      throw BridgeProvisioningException(
        bridgeLabel,
        'create_dm did not return a room',
      );
    }
    return dmRoomMxid;
  }

  /// Triggers the bridge's own contact resync (e.g. WhatsApp's "sync
  /// contacts" admin command) via the relay, without needing interactive
  /// access to @bridgehub's session. Useful when a contact known to exist
  /// on the linked phone doesn't show up in search - most likely because
  /// sync hasn't run since they were added.
  Future<void> syncContacts(String bridgeId, String bridgeLabel) async {
    final res = await http.post(
      await _uri('/bridges/$bridgeId/sync_contacts'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) {
      throw BridgeProvisioningException(bridgeLabel, _errorMessage(res));
    }
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
