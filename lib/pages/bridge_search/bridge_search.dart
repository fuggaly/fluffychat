import 'dart:async';

import 'package:fluffychat/pages/bridge_search/bridge_search_view.dart';
import 'package:fluffychat/utils/bridge_search/bridge_provisioning_client.dart';
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
  List<ConfiguredBridge> bridges = [];
  List<BridgeSearchResult> results = [];
  final Map<String, String> bridgeErrors = {}; // bridge id -> error message
  bool loading = true;
  Timer? _debounce;
  final Map<String, List<BridgeContact>> _contactsCache = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    bridges = await BridgeSearchConfig.getBridges();
    if (mounted) setState(() => loading = false);
  }

  BridgeProvisioningClient _clientFor(ConfiguredBridge bridge) {
    final client = Matrix.of(context).client;
    return BridgeProvisioningClient(
      bridge: bridge,
      matrixAccessToken: client.accessToken!,
      matrixUserId: client.userID!,
    );
  }

  void onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

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

    for (final bridge in bridges) {
      try {
        List<BridgeContact> matches;
        if (bridge.kind.supportsSearchUsers) {
          matches = await _clientFor(bridge).searchUsers(query);
        } else if (bridge.kind.supportsContactsList) {
          final contacts = _contactsCache[bridge.id] ??=
              await _clientFor(bridge).contacts();
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
      } on BridgeProvisioningException catch (e) {
        newErrors[bridge.id] = e.message;
      } catch (e) {
        newErrors[bridge.id] = e.toString();
      }
    }

    if (!mounted) return;
    setState(() {
      results = newResults;
      bridgeErrors
        ..clear()
        ..addAll(newErrors);
    });
  }

  Future<void> startChat(BridgeSearchResult result) async {
    final roomId = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final client = _clientFor(result.bridge);
        return result.bridge.kind.supportsContactsList &&
                !result.bridge.kind.supportsSearchUsers
            ? client.resolveIdentifier(result.contact.id, createChat: true)
            : client.createDm(result.contact.id);
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
