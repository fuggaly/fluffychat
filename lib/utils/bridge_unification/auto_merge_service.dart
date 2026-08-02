import 'package:fluffychat/utils/bridge_search/bridge_provisioning_client.dart';
import 'package:fluffychat/utils/bridge_unification/bridge_label.dart';
import 'package:fluffychat/utils/bridge_unification/unified_contacts_service.dart';
import 'package:matrix/matrix.dart';

/// Silently creates a unified-contact group for every server-computed
/// suggestion (see BridgeProvisioningClient.suggestedGroupings) strong
/// enough to trust without asking - matched by a contact's stable vCard
/// uid rather than just a display-name string (see SuggestedGrouping),
/// where this device has actually joined 2+ of the suggested rooms, each
/// is a genuine 1:1 (room.isDirectChat - see below), and none are already
/// grouped.
///
/// The isDirectChat check has to happen here, not server-side: the relay
/// only has @bridgehub's perspective, and @bridgehub is a headless
/// automation account with no real client maintaining reliable
/// membership/m.direct semantics - an earlier attempt at this exact check
/// server-side (via room member counts, then via @bridgehub's own
/// m.direct) silently excluded every genuine 1:1 the human had actually
/// joined, since a bridge's own self-ghost (e.g. WhatsApp exposing the
/// linked account's own number as a room participant) or @bridgehub's own
/// sparse account_data threw off both approaches (see git history). The
/// human's own account, which this client is actually logged in as, has
/// this reliably via a normal client's own m.direct handling.
///
/// "name"-matched suggestions are deliberately left alone here - those
/// still need a human to review them in Settings > Unified Contacts,
/// since a shared display name can't be ruled out the way a uid can.
class AutoMergeService {
  static Future<void> run(Client client) async {
    List<SuggestedGrouping> suggestions;
    try {
      suggestions = await BridgeProvisioningClient().suggestedGroupings();
    } on BridgeProvisioningException {
      // bridge_relay not configured on this device, or unreachable - same
      // soft-fail convention used everywhere else this call is made (see
      // settings_unified_contacts.dart's own _loadSuggestions).
      return;
    } catch (e, s) {
      Logs().w('AutoMergeService: failed to fetch suggested groupings', e, s);
      return;
    }

    for (final suggestion in suggestions) {
      if (suggestion.matchedBy != 'uid') continue;

      final roomIds = suggestion.rooms.where((id) {
        final room = client.getRoomById(id);
        return room != null &&
            room.membership == Membership.join &&
            room.isDirectChat &&
            UnifiedContactsService.groupForRoom(client, id) == null;
      }).toList();
      if (roomIds.length < 2) continue;

      final roomLabels = <String, String>{};
      for (final roomId in roomIds) {
        final room = client.getRoomById(roomId);
        if (room == null) continue;
        roomLabels[roomId] =
            bridgeLabelForRoom(room) ??
            stripViaSuffix(room.getLocalizedDisplayname());
      }

      try {
        await UnifiedContactsService.createGroup(
          client,
          label: suggestion.label,
          roomIds: roomIds,
          roomLabels: roomLabels,
        );
      } catch (e, s) {
        // A concurrent grouping of one of these rooms between the filter
        // above and this call (e.g. another device, or the user acting in
        // Settings at the same moment) throws StateError here - skip this
        // suggestion rather than crash a background task.
        Logs().w(
          'AutoMergeService: failed to create group for "${suggestion.label}"',
          e,
          s,
        );
      }
    }
  }
}
