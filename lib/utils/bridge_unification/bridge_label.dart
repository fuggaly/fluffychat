import 'package:matrix/matrix.dart';

/// Derives a human-readable bridge label from a room's `m.bridge` state
/// event (per the de-facto mautrix/MSC2346 shape:
/// `{ protocol: { id, displayname }, ... }`), the same event
/// `autobot.mjs`'s `isBridgedRoom()` already checks for on the server side.
/// Returns null for un-bridged rooms (e.g. a plain Matrix DM) - callers
/// should fall back to manual labelling in that case.
String? bridgeLabelForRoom(Room room) {
  final bridgeState = room.getState('m.bridge');
  if (bridgeState == null) return null;

  final protocol = bridgeState.content['protocol'] as Map?;
  final displayName = protocol?['displayname'] as String?;
  if (displayName != null && displayName.isNotEmpty) return displayName;

  final id = protocol?['id'] as String?;
  if (id != null && id.isNotEmpty) {
    // Title-case the bare protocol id (e.g. "whatsapp" -> "Whatsapp") as a
    // reasonable fallback when no displayname is set.
    return id[0].toUpperCase() + id.substring(1);
  }

  return null;
}
