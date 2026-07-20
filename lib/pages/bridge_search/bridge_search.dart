import 'dart:async';

import 'package:fluffychat/pages/bridge_search/bridge_search_view.dart';
import 'package:fluffychat/utils/bridge_search/bridge_provisioning_client.dart';
import 'package:fluffychat/utils/bridge_search/bridge_relay_config.dart';
import 'package:fluffychat/utils/bridge_search/bridge_search_config.dart';
import 'package:fluffychat/utils/bridge_search/configured_bridge.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class BridgeSearchResult {
  final ConfiguredBridge bridge;
  final BridgeContact contact;

  BridgeSearchResult(this.bridge, this.contact);
}

class BridgeSearch extends StatefulWidget {
  const BridgeSearch({super.key});

  @override
  State<BridgeSearch> createState() => BridgeSearchController();
}

class BridgeSearchController extends State<BridgeSearch> {
  final TextEditingController searchController = TextEditingController();
  final BridgeProvisioningClient _relayClient = BridgeProvisioningClient();
  List<ConfiguredBridge> bridges = [];
  List<BridgeSearchResult> results = [];
  final Map<String, String> bridgeErrors = {}; // bridge id -> error message
  bool loading = true;
  bool relayConfigured = true;
  Timer? _debounce;
  final Map<String, List<BridgeContact>> _contactsCache = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    bridges = await BridgeSearchConfig.getBridges();
    relayConfigured = await BridgeRelayConfig.isConfigured();
    if (mounted) setState(() => loading = false);
  }

  void onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  /// Digits only, so "+61 422 574 711", "tel:+61422574711", and
  /// "61422574711" (a WhatsApp ghost mxid's embedded number) all compare
  /// equal regardless of formatting.
  String _normalizePhone(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        results = [];
        bridgeErrors.clear();
      });
      return;
    }

    final newResults = <BridgeSearchResult>[];
    final newErrors = <String, String>{};
    // Tracks which (bridgeId, phone) pairs the per-bridge searches below
    // already surfaced, so the address-book merge afterward doesn't show
    // the same person twice for the same network.
    final coveredPhonesByBridge = <String, Set<String>>{};

    for (final bridge in bridges) {
      final covered = coveredPhonesByBridge[bridge.id] = {};
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
        newResults.addAll(matches.map((c) => BridgeSearchResult(bridge, c)));
        for (final c in matches) {
          for (final identifier in c.identifiers) {
            covered.add(_normalizePhone(identifier));
          }
        }
      } on BridgeProvisioningException catch (e) {
        newErrors[bridge.id] = e.message;
      } catch (e) {
        newErrors[bridge.id] = e.toString();
      }
    }

    // Merge in the real address book (contacts-sync's compiled data) -
    // neither bridge's own contact listing is a reliable substitute for
    // it (WhatsApp only knows phone-synced WhatsApp users, Google
    // Messages' own contact API returns a limited Google-curated list).
    // For each phone number, offer every bridge that accepts a raw phone
    // identifier (WhatsApp, Google Messages) - unless that bridge already
    // surfaced this exact number itself above.
    try {
      final addressBookMatches = await _relayClient.searchAddressBook(query);
      for (final person in addressBookMatches) {
        for (final phone in person.phones) {
          final normalized = _normalizePhone(phone);
          for (final bridge in bridges) {
            if (!bridge.kind.usesPhoneIdentifiers) continue;
            if (coveredPhonesByBridge[bridge.id]?.contains(normalized) ?? false) {
              continue;
            }
            newResults.add(
              BridgeSearchResult(
                bridge,
                BridgeContact(id: phone, name: person.name),
              ),
            );
            coveredPhonesByBridge[bridge.id]?.add(normalized);
          }
        }
      }
    } on BridgeProvisioningException catch (e) {
      newErrors['address book'] = e.message;
    } catch (e) {
      newErrors['address book'] = e.toString();
    }

    if (!mounted) return;
    setState(() {
      results = newResults;
      bridgeErrors
        ..clear()
        ..addAll(newErrors);
    });
  }

  Future<void> syncContacts(ConfiguredBridge bridge) async {
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => _relayClient.syncContacts(bridge.id, bridge.label),
    );
    if (result.error != null || !mounted) return;
    // Cached contacts (used for the contacts-list search fallback, e.g.
    // Google Messages) are now stale - drop them so the next search
    // re-fetches.
    _contactsCache.remove(bridge.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${bridge.label} contact sync triggered.')),
    );
  }

  Future<void> startChat(BridgeSearchResult result) async {
    final client = Matrix.of(context).client;
    final myUserId = client.userID!;

    final roomId = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final bridge = result.bridge;
        // Bridge-created DM rooms only have @bridgehub as a member (it's
        // whose token actually authenticated the request) - invite this
        // app's own user, then join immediately so there's no dangling
        // invite waiting to be accepted separately.
        final newRoomId =
            bridge.kind.supportsContactsList && !bridge.kind.supportsSearchUsers
            ? await _relayClient.resolveIdentifier(
                bridge.id,
                bridge.label,
                result.contact.actionIdentifier,
                createChat: true,
                inviteUserId: myUserId,
              )
            : await _relayClient.createDm(
                bridge.id,
                bridge.label,
                result.contact.actionIdentifier,
                inviteUserId: myUserId,
              );

        final waitForRoom = client.waitForRoomInSync(newRoomId, join: true);
        await client.joinRoom(newRoomId);
        await waitForRoom;
        return newRoomId;
      },
    );
    if (roomId.error != null || !mounted) return;
    context.go('/rooms/${roomId.result}');
  }

  @override
  void dispose() {
    searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BridgeSearchView(this);
}
