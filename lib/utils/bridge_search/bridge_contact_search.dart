import 'package:fluffychat/utils/bridge_search/bridge_provisioning_client.dart';
import 'package:fluffychat/utils/bridge_search/bridge_search_config.dart';
import 'package:fluffychat/utils/bridge_search/configured_bridge.dart';
import 'package:fluffychat/utils/bridge_unification/bridge_label.dart';
import 'package:matrix/matrix.dart';

class BridgeSearchResult {
  final ConfiguredBridge bridge;
  final BridgeContact contact;
  final String displayName;

  /// Defaults to the bridge-provided name with any "via WhatsApp"-style
  /// suffix stripped (the network is already shown separately, e.g. as
  /// this tile's subtitle) - overridden with the real address-book name
  /// + phone label ("Chris Moore (work)") when [BridgeContactSearch] can
  /// match this result back to a specific address-book number.
  BridgeSearchResult(this.bridge, this.contact, {String? displayName})
      : displayName = displayName ?? stripViaSuffix(contact.name);
}

class BridgeContactSearchResults {
  final List<BridgeSearchResult> results;
  final Map<String, String> errors; // bridge id (or 'address book') -> message

  BridgeContactSearchResults(this.results, this.errors);
}

/// Cross-bridge contact search: queries every configured bridge's own
/// provisioning API plus the compiled address book, then cross-offers any
/// phone number found by one source across every other phone-identifier
/// -capable bridge. Shared between the dedicated BridgeSearch page and the
/// main chat-list search bar so both stay backed by one implementation
/// rather than two copies of the cross-offer logic drifting apart.
class BridgeContactSearch {
  final BridgeProvisioningClient _relayClient = BridgeProvisioningClient();
  final Map<String, List<BridgeContact>> _contactsCache = {};
  // "bridgeId|normalizedPhone" -> reachable contact, or null if confirmed
  // unreachable (e.g. a landline). The relay sits behind an HAProxy rate
  // limit (20 req/min per source IP - see matrix-bridge-relay's own
  // deploy config) shared across every endpoint it exposes, and
  // reachability barely ever changes within a session, so caching here
  // (kept for the lifetime of this object, same as _contactsCache above)
  // is what keeps repeated/overlapping searches - e.g. retyping or
  // backspacing while narrowing a query - from re-firing identical
  // resolve_identifier probes and tripping that limit.
  final Map<String, BridgeContact?> _reachabilityCache = {};

  Future<List<ConfiguredBridge>> get bridges => BridgeSearchConfig.getBridges();

  void invalidateContactsCache(String bridgeId) =>
      _contactsCache.remove(bridgeId);

  /// Digits only, so "+61 422 574 711", "tel:+61422574711", and
  /// "61422574711" (a WhatsApp ghost mxid's embedded number) all compare
  /// equal regardless of formatting. Used only for dedup comparisons - the
  /// properly formatted phone (see _phoneFromIdentifier) is what actually
  /// gets sent to resolve_identifier/create_dm.
  String _normalizePhone(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');

  /// Strips a "tel:" prefix if present, leaving a usable "+614..."
  /// identifier. Address-book phones already come in this form with no
  /// prefix to strip.
  String _phoneFromIdentifier(String identifier) =>
      identifier.replaceFirst('tel:', '');

  /// Fallback gate for bridges without a genuine reachability check (see
  /// BridgeKind.hasRealReachabilityCheck) - e.g. Google Messages, whose
  /// resolve_identifier returns success for any syntactically valid
  /// number, landline included, since it has no real way to pre-check SMS
  /// reachability. This app is only ever used against Australian numbers
  /// (this homeserver's sole user base), so a lightweight AU mobile
  /// heuristic (04xx / +614xx) is enough here - not a general E.164
  /// mobile classifier. Unrecognized formats are let through rather than
  /// silently dropped. Bridges with a real check (WhatsApp) skip this
  /// entirely and rely on the live query instead.
  bool _looksLikeMobileNumber(String normalized) {
    if (normalized.startsWith('61')) return normalized.startsWith('614');
    if (normalized.startsWith('0')) return normalized.startsWith('04');
    return true;
  }

  Future<BridgeContactSearchResults> search(String query) async {
    if (query.trim().isEmpty) {
      return BridgeContactSearchResults(const [], const {});
    }

    final bridges = await this.bridges;
    final newErrors = <String, String>{};
    // Every result (native bridge hit or address-book cross-offer) is
    // deduped through this map, keyed per bridge by normalized phone - or,
    // when no phone is known at all, by the contact's own id. This is what
    // collapses multiple ghosts for one real person into a single result:
    // WhatsApp in particular can hold two separate ghosts for the same
    // contact - one keyed by phone-JID, one by "LID" (WhatsApp's newer
    // privacy-preserving id scheme) - both carrying the same tel:
    // identifier, which search_users happily returns as two separate hits.
    final byBridge = <String, Map<String, BridgeSearchResult>>{};
    // Every phone number found by ANY source (a bridge's own native
    // search, or the address book) - cross-offered across every
    // phone-identifier-capable bridge afterward, regardless of which
    // source actually found it. Without this, someone found only via
    // WhatsApp's own contact sync (never in the address book, e.g. a
    // contact synced independently on that phone) would never get offered
    // on Google Messages, and vice versa.
    final knownPhones = <String>[];
    // normalizedPhone -> (address book name, phone label e.g. "mobile"/
    // "work") - used to override the display name of ANY final result
    // (native bridge hit or cross-offer) that matches one of these
    // numbers, since the address book is the only source that actually
    // knows which specific number a result corresponds to.
    final addressBookLabels = <String, (String name, String label)>{};

    void addResult(ConfiguredBridge bridge, BridgeContact c) {
      final dedupeMap = byBridge[bridge.id] ??= {};
      final phones = <String>{
        for (final identifier in c.identifiers) _normalizePhone(identifier),
        if (bridge.kind.usesPhoneIdentifiers) _normalizePhone(c.id),
      }..removeWhere((p) => p.isEmpty);
      final key = phones.isNotEmpty ? phones.first : 'id:${c.id}';
      // Prefer a hit that already has an mxid (an established ghost) over
      // one that doesn't, since that's the more robust action target.
      final existing = dedupeMap[key];
      if (existing == null ||
          (existing.contact.mxid == null && c.mxid != null)) {
        dedupeMap[key] = BridgeSearchResult(bridge, c);
      }
      for (final identifier in c.identifiers) {
        if (_normalizePhone(identifier).isEmpty) continue;
        knownPhones.add(_phoneFromIdentifier(identifier));
      }
    }

    for (final bridge in bridges) {
      try {
        List<BridgeContact> matches;
        if (bridge.kind.supportsSearchUsers) {
          matches = await _relayClient.searchUsers(bridge.id, bridge.label, query);
        } else if (bridge.kind.supportsContactsList) {
          final contacts = _contactsCache[bridge.id] ??=
              await _relayClient.contacts(bridge.id, bridge.label);
          final lowerQuery = query.toLowerCase();
          matches = contacts
              .where(
                (c) =>
                    c.name.toLowerCase().contains(lowerQuery) ||
                    c.identifiers.any((i) => i.contains(query)),
              )
              .toList();
        } else {
          continue;
        }
        for (final c in matches) {
          addResult(bridge, c);
        }
      } on BridgeProvisioningException catch (e) {
        newErrors[bridge.id] = e.message;
      } catch (e) {
        newErrors[bridge.id] = e.toString();
      }
    }

    // Merge in the real address book (contacts-sync's compiled data) -
    // neither bridge's own contact listing is a reliable substitute for it
    // (WhatsApp only knows phone-synced WhatsApp users, Google Messages'
    // own contact API returns a limited Google-curated list).
    try {
      final addressBookMatches = await _relayClient.searchAddressBook(query);
      for (final person in addressBookMatches) {
        for (final phone in person.phones) {
          knownPhones.add(phone.value);
          final normalized = _normalizePhone(phone.value);
          if (normalized.isEmpty) continue;
          addressBookLabels[normalized] = (person.name, phone.label);
        }
      }
    } on BridgeProvisioningException catch (e) {
      newErrors['address book'] = e.message;
    } catch (e) {
      newErrors['address book'] = e.toString();
    }

    // Cross-offer: for every phone number found by ANY source above, offer
    // every phone-identifier-capable bridge that hasn't already surfaced
    // that exact number natively. Rather than assuming a number works on
    // a bridge just because it's a phone number, actually check
    // reachability via resolve_identifier(create_chat=false) first - see
    // BridgeProvisioningClient.checkReachable. This is what a naive
    // "offer every known number to every phone bridge" approach got
    // wrong: a contact's landline (present in the address book alongside
    // their real mobile) would otherwise surface as a phantom, non
    // -functional result. That live check is only trustworthy on bridges
    // where it's a real query (WhatsApp's IsOnWhatsApp) - Google Messages
    // returns success for any syntactically valid number regardless of
    // whether it can actually receive SMS, so bridges without a real
    // check (BridgeKind.hasRealReachabilityCheck) are additionally gated
    // by _looksLikeMobileNumber before a probe is even fired. Runs the
    // checks in parallel per candidate rather than sequentially, since a
    // single search can involve several (contact x bridge) pairs.
    final probes = <Future<void>>[];
    final launchedProbes = <String>{}; // "bridgeId|normalizedPhone"
    for (final phone in knownPhones) {
      final normalized = _normalizePhone(phone);
      if (normalized.isEmpty) continue;
      for (final bridge in bridges) {
        if (!bridge.kind.usesPhoneIdentifiers) continue;
        if (!bridge.kind.hasRealReachabilityCheck &&
            !_looksLikeMobileNumber(normalized)) {
          continue;
        }
        final dedupeMap = byBridge[bridge.id] ??= {};
        if (dedupeMap.containsKey(normalized)) continue;
        final cacheKey = '${bridge.id}|$normalized';
        if (!launchedProbes.add(cacheKey)) continue;
        if (_reachabilityCache.containsKey(cacheKey)) {
          final cached = _reachabilityCache[cacheKey];
          if (cached != null) {
            dedupeMap.putIfAbsent(normalized, () => BridgeSearchResult(bridge, cached));
          }
          continue;
        }
        probes.add(() async {
          BridgeContact? reachable;
          try {
            reachable = await _relayClient.checkReachable(
              bridge.id,
              bridge.label,
              phone,
            );
          } catch (_) {
            // A failed reachability check (network error, relay down)
            // just means this candidate is silently dropped (and not
            // cached, so it's retried on the next search) - the same
            // bridge's own native search errors (if any) are already
            // surfaced separately via newErrors above.
            return;
          }
          _reachabilityCache[cacheKey] = reachable;
          if (reachable == null) return;
          dedupeMap.putIfAbsent(
            normalized,
            () => BridgeSearchResult(bridge, reachable!),
          );
        }());
      }
    }
    await Future.wait(probes);

    final newResults = [
      for (final dedupeMap in byBridge.values)
        for (final entry in dedupeMap.entries)
          _applyAddressBookName(entry.key, entry.value, addressBookLabels),
    ];
    return BridgeContactSearchResults(newResults, newErrors);
  }

  /// [key] is the dedupe key the result was stored under - either a
  /// normalized phone number, or "id:..." for a non-phone identifier
  /// (e.g. Slack), which never has an address-book match.
  BridgeSearchResult _applyAddressBookName(
    String key,
    BridgeSearchResult result,
    Map<String, (String name, String label)> addressBookLabels,
  ) {
    final match = addressBookLabels[key];
    if (match == null) return result;
    final (name, label) = match;
    final displayName = (label.isEmpty || label == 'unknown')
        ? name
        : '$name ($label)';
    return BridgeSearchResult(result.bridge, result.contact, displayName: displayName);
  }

  Future<void> syncContacts(ConfiguredBridge bridge) async {
    await _relayClient.syncContacts(bridge.id, bridge.label);
    // Cached contacts (used for the contacts-list search fallback, e.g.
    // Google Messages) are now stale - drop them so the next search
    // re-fetches.
    invalidateContactsCache(bridge.id);
  }

  /// Resolves a search result to a joined room, inviting this app's own
  /// user into it first - bridge-created DM rooms only have @bridgehub as
  /// a member (it's whose token actually authenticated the request).
  /// Context-free (no dialogs/navigation) so it can be shared between call
  /// sites (the main chat-list search bar), which wrap it with their own
  /// loading UI.
  ///
  /// Always goes through create_dm, never resolve_identifier(create_chat:
  /// true) - confirmed live against the Google Messages bridge that the
  /// latter is a no-op there regardless of create_chat ("Returning fake
  /// phone number response" in its own logs, never returns a real
  /// dm_room_mxid), while create_dm actually creates the chat. Only
  /// resolve_identifier(create_chat: false) - see
  /// BridgeProvisioningClient.checkReachable - is trustworthy, and only for
  /// bridges with a real check (BridgeKind.hasRealReachabilityCheck).
  Future<String> startChat(Client client, BridgeSearchResult result) async {
    final myUserId = client.userID!;
    final bridge = result.bridge;
    final newRoomId = await _relayClient.createDm(
      bridge.id,
      bridge.label,
      result.contact.actionIdentifier,
      inviteUserId: myUserId,
    );

    // create_dm is idempotent per contact - re-contacting someone already
    // messaged before returns that same existing room, and since this
    // device is very likely already joined to it, waiting for a *fresh*
    // join transition below would hang forever (nothing new is ever going
    // to arrive over sync for a membership that never changes). Skip the
    // join dance entirely when already joined.
    if (client.getRoomById(newRoomId)?.membership == Membership.join) {
      return newRoomId;
    }

    final waitForRoom = client.waitForRoomInSync(newRoomId, join: true);
    await client.joinRoom(newRoomId);
    await waitForRoom;
    return newRoomId;
  }
}
