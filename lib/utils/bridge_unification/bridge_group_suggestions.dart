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

/// Finds pairs of currently-ungrouped bridged rooms that are very likely
/// the same real contact reachable over two networks, using only
/// information already visible to the client - no address-book/PII
/// lookup needed. WhatsApp ghost mxids embed the raw phone number directly
/// (e.g. "@whatsapp_61422422071:..."), and bridges like Google
/// Messages/SMS commonly fall back to showing the bare phone number as the
/// room/contact name when they haven't resolved a real contact name for it
/// (e.g. "0487 366 283 via SMS").
///
/// Matching is intentionally loose (compares the last 8 digits, so a local
/// "0487 366 283" matches an internationalized "61487366283") since this
/// only ever produces a *suggestion* the user reviews and explicitly
/// confirms - a false positive here just means an unhelpful suggestion,
/// not a silent wrong merge.
List<SuggestedGroup> findSuggestedGroupings(Client client) {
  final groupedRoomIds = <String>{
    for (final group in UnifiedContactsService.getGroups(client))
      ...group.roomIds,
  };

  // Loosely-normalized phone key -> candidate rooms.
  final byPhone = <String, List<Room>>{};

  for (final room in client.rooms) {
    if (room.membership != Membership.join) continue;
    if (groupedRoomIds.contains(room.id)) continue;
    if (isBridgeManagementRoom(room)) continue;
    final label = bridgeLabelForRoom(room);
    if (label == null) continue; // not a bridged room at all

    final phoneKey = _phoneKeyForRoom(client, room, label);
    if (phoneKey == null) continue;

    (byPhone[phoneKey] ??= []).add(room);
  }

  return byPhone.values
      .where((rooms) => rooms.length >= 2)
      .map(
        (rooms) => SuggestedGroup(
          roomIds: rooms.map((r) => r.id).toList(),
          suggestedLabel: stripViaSuffix(rooms.first.getLocalizedDisplayname()),
        ),
      )
      .toList();
}

/// The phone number (normalized for loose matching) this room is reachable
/// at, if determinable from information already visible to the client -
/// null if it can't be determined at all (most bridges other than
/// WhatsApp, or an SMS contact that's already been resolved to a real
/// name, don't expose one this way).
String? _phoneKeyForRoom(Client client, Room room, String bridgeLabel) {
  if (bridgeLabel.toLowerCase().contains('whatsapp')) {
    final otherId = _otherPartyMxid(client, room);
    if (otherId == null) return null;
    final match = RegExp(r'^@whatsapp_(\d+):').firstMatch(otherId);
    return _loosePhoneKey(match?.group(1));
  }

  // Any other bridge: only usable when its displayname (with the " via X"
  // suffix stripped) looks like nothing but a phone number - i.e. the
  // bridge hasn't resolved a real contact name for it.
  final name = stripViaSuffix(room.getLocalizedDisplayname()).trim();
  if (!RegExp(r'^[+\d][\d \-()]{6,}$').hasMatch(name)) return null;
  return _loosePhoneKey(name);
}

String? _otherPartyMxid(Client client, Room room) {
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
