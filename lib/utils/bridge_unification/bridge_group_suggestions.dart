import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'bridge_label.dart';
import 'known_bridge_bots.dart';
import 'unified_contacts_service.dart';

/// A suggested (not yet created) unified-contact grouping - purely
/// client-side, never written anywhere until the user explicitly confirms
/// it via the "merge" action that consumes this.
class SuggestedGroup {
  final List<String> roomIds;
  final String suggestedLabel;

  SuggestedGroup({required this.roomIds, required this.suggestedLabel});
}

/// Finds sets of currently-ungrouped bridged rooms that are very likely
/// the same real contact reachable over two networks, using only
/// information already visible to the client - no address-book/PII lookup
/// needed. Two independent strategies, both suggestion-only (a false
/// positive just costs an unhelpful suggestion the user can dismiss, never
/// a silent wrong merge):
///
/// - Phone number: WhatsApp ghost mxids embed the raw phone number
///   directly (e.g. "@whatsapp_61422422071:..."), and bridges like Google
///   Messages/SMS commonly fall back to showing the bare phone number as
///   the room name when they haven't resolved a real contact name for it
///   yet (e.g. "0487 366 283 via SMS"). Compares the last 8 digits rather
///   than requiring an exact match, so a local format and an
///   internationalized one for the same number still match.
/// - Same resolved name: once both bridges already know who a contact is
///   (e.g. via each network's own contact list), their portal rooms
///   commonly end up with the exact same display name on both sides
///   (stripped of the " via X" suffix) - "Fudge Raco via WhatsApp" and
///   "Fudge Raco via SMS" are almost certainly the same person. This is
///   actually the more common case once contacts are properly resolved on
///   both sides, and needs no phone-number extraction at all - just
///   comparing two strings already shown in the room list today.
List<SuggestedGroup> findSuggestedGroupings(Client client) {
  final groupedRoomIds = <String>{
    for (final group in UnifiedContactsService.getGroups(client))
      ...group.roomIds,
  };

  final candidates = <Room>[];
  for (final room in client.rooms) {
    if (room.membership != Membership.join) continue;
    if (groupedRoomIds.contains(room.id)) continue;
    if (isBridgeManagementRoom(room)) continue;
    if (bridgeLabelForRoom(room) == null) continue; // not bridged at all
    candidates.add(room);
  }

  final byPhone = <String, List<Room>>{};
  final byName = <String, List<Room>>{};

  for (final room in candidates) {
    final label = bridgeLabelForRoom(room)!;
    final strippedName = stripViaSuffix(
      room.getLocalizedDisplayname(),
    ).trim();
    final looksLikeBarePhoneNumber = RegExp(
      r'^[+\d][\d \-()]{6,}$',
    ).hasMatch(strippedName);

    final phoneKey = _phoneKeyForRoom(client, room, label, strippedName);
    if (phoneKey != null) (byPhone[phoneKey] ??= []).add(room);

    // A bare, unresolved phone number isn't a "name" to match on here -
    // two different unresolved numbers that happen to render identically
    // would be a coincidence, not a match, and it's already covered (more
    // precisely) by the phone-key strategy above when it applies.
    if (strippedName.isNotEmpty && !looksLikeBarePhoneNumber) {
      (byName[strippedName.toLowerCase()] ??= []).add(room);
    }
  }

  final suggestions = <String, SuggestedGroup>{};
  for (final rooms in [...byPhone.values, ...byName.values]) {
    if (rooms.length < 2) continue;
    final ids = rooms.map((r) => r.id).toList();
    final key = (List<String>.from(ids)..sort()).join(',');
    suggestions.putIfAbsent(
      key,
      () => SuggestedGroup(
        roomIds: ids,
        suggestedLabel: stripViaSuffix(rooms.first.getLocalizedDisplayname()),
      ),
    );
  }
  return suggestions.values.toList();
}

/// The phone number (normalized for loose matching) this room is reachable
/// at, if determinable from information already visible to the client -
/// null if it can't be determined at all (most bridges other than
/// WhatsApp, or a contact that's already been resolved to a real name,
/// don't expose one this way - that's what the by-name strategy is for).
String? _phoneKeyForRoom(
  Client client,
  Room room,
  String bridgeLabel,
  String strippedName,
) {
  if (bridgeLabel.toLowerCase().contains('whatsapp')) {
    final otherId = _otherPartyMxid(client, room);
    if (otherId == null) return null;
    final match = RegExp(r'^@whatsapp_(\d+):').firstMatch(otherId);
    return _loosePhoneKey(match?.group(1));
  }

  // Any other bridge: only usable when its displayname looks like nothing
  // but a phone number - i.e. the bridge hasn't resolved a real contact
  // name for it.
  if (!RegExp(r'^[+\d][\d \-()]{6,}$').hasMatch(strippedName)) return null;
  return _loosePhoneKey(strippedName);
}

String? _otherPartyMxid(Client client, Room room) {
  // room.summary.mHeroes is what getLocalizedDisplayname() itself uses to
  // compute a DM's name - it's part of the room summary sent eagerly on
  // every sync, unlike full member state, which is normally lazy-loaded
  // and often just isn't present yet for a room that hasn't been opened.
  // getParticipants()/directChatMatrixID depend on that lazy-loaded state
  // being present, so for a room sitting unopened in the room list (the
  // common case suggestions need to work for) they'd silently return
  // nothing. Note this can *also* come up empty - some servers only
  // populate heroes when a room has no name/alias of its own, and bridge
  // portals normally do have an explicit name - hence the by-name
  // matching strategy existing as an independent fallback rather than
  // depending on this resolving reliably.
  final hero = room.summary.mHeroes
      ?.where((id) => id != client.userID)
      .firstOrNull;
  if (hero != null) return hero;

  final direct = room.directChatMatrixID;
  if (direct != null) return direct;

  for (final participant in room.getParticipants()) {
    if (participant.id != client.userID) return participant.id;
  }
  return null;
}

const _loosePhoneTailLength = 8;

String? _loosePhoneKey(String? raw) {
  if (raw == null) return null;
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length < _loosePhoneTailLength) return null;
  return digits.substring(digits.length - _loosePhoneTailLength);
}
