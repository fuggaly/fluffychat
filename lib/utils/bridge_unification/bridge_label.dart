import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
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

/// Best current label for a room in a unified group: prefers the room's
/// live `m.bridge` state (always fresh, self-healing if the group's
/// stored roomLabels predate a labelling change) over whatever was
/// snapshotted into account_data when the group was created, falling
/// back to the stored value only if the room has no `m.bridge` state to
/// read (shouldn't normally happen for a bridged room, but defensive).
String effectiveRoomLabel(Room? room, String? storedLabel) {
  if (room != null) {
    final liveLabel = bridgeLabelForRoom(room);
    if (liveLabel != null) return liveLabel;
  }
  if (storedLabel != null && storedLabel.isNotEmpty) return storedLabel;
  return room == null ? 'Unknown' : stripViaSuffix(room.getLocalizedDisplayname());
}

/// Bridged ghost/room display names are commonly suffixed by the bridge
/// itself (e.g. "Martin Davidson via WhatsApp") - strips that for display
/// contexts that already show the network separately (a badge/icon),
/// where repeating it in the name is just clutter. No-op if there's no
/// " via " suffix to strip.
String stripViaSuffix(String name) =>
    name.replaceFirst(RegExp(r' via .+$'), '');

/// Icon (+ a brand-ish tint) for a bridge label, used wherever we'd
/// otherwise show the network as text (the unified-conversation send
/// dropdown, per-message badges). WhatsApp has a real brand mark in
/// FontAwesome; there's no "Google Messages" brand icon anywhere, but its
/// dedicated SMS icon reads distinctly rather than reusing a generic chat
/// bubble for both. Render with FaIcon (not the plain Material Icon
/// widget) - required for FaIconData to display correctly.
///
/// Matches by substring, case-insensitive - labels stored in an existing
/// group's account_data may not be the exact clean strings this code
/// produces today (e.g. a group created before stripViaSuffix existed
/// could have "Martin Davidson via WhatsApp" baked in, not just
/// "WhatsApp"), so exact equality would silently fall through to the
/// generic icon for old data.
FaIconData iconForBridgeLabel(String label) {
  final lower = label.toLowerCase();
  if (lower.contains('whatsapp')) return FontAwesomeIcons.whatsapp;
  if (lower.contains('sms') || lower.contains('google messages')) {
    return FontAwesomeIcons.commentSms;
  }
  if (lower.contains('slack')) return FontAwesomeIcons.slack;
  return FaIconData(Icons.forum_outlined);
}

Color colorForBridgeLabel(String label) {
  final lower = label.toLowerCase();
  if (lower.contains('whatsapp')) return const Color(0xFF25D366);
  if (lower.contains('sms') || lower.contains('google messages')) {
    return const Color(0xFF1A73E8);
  }
  if (lower.contains('slack')) return const Color(0xFF4A154B);
  return Colors.grey;
}
