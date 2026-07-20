import 'package:flutter/material.dart';
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

/// Bridged ghost/room display names are commonly suffixed by the bridge
/// itself (e.g. "Martin Davidson via WhatsApp") - strips that for display
/// contexts that already show the network separately (a badge/icon),
/// where repeating it in the name is just clutter. No-op if there's no
/// " via " suffix to strip.
String stripViaSuffix(String name) =>
    name.replaceFirst(RegExp(r' via .+$'), '');

/// Icon (+ a brand-ish tint) for a bridge label, used wherever we'd
/// otherwise show the network as text (the unified-conversation send
/// dropdown, per-message badges). Generic Material icons rather than real
/// brand marks - no new asset/font dependency for this.
IconData iconForBridgeLabel(String label) => switch (label) {
  'WhatsApp' => Icons.chat_outlined,
  'Google Messages' => Icons.sms_outlined,
  'Slack' => Icons.tag_outlined,
  _ => Icons.forum_outlined,
};

Color colorForBridgeLabel(String label) => switch (label) {
  'WhatsApp' => const Color(0xFF25D366),
  'Google Messages' => const Color(0xFF1A73E8),
  'Slack' => const Color(0xFF4A154B),
  _ => Colors.grey,
};
