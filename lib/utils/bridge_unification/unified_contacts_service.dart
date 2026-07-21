import 'package:matrix/matrix.dart';

import 'unified_contact_group.dart';

/// Groups of rooms (e.g. a contact's WhatsApp room + their Google Messages
/// room) that should be presented as one unified conversation. Stored as a
/// single Matrix account_data event, so grouping syncs automatically across
/// every device via the homeserver's normal account_data sync - no server
/// changes, works with any bridge (grouping is just "pick existing rooms",
/// not tied to specific bridge software).
class UnifiedContactsService {
  static const _accountDataType = 'chat.fuggaly.unified_contacts';

  static List<UnifiedContactGroup> getGroups(Client client) {
    final event = client.accountData[_accountDataType];
    final groupsJson = event?.content['groups'] as List? ?? [];
    return groupsJson
        .map((g) => UnifiedContactGroup.fromJson((g as Map).cast()))
        .toList();
  }

  static Future<void> _saveGroups(
    Client client,
    List<UnifiedContactGroup> groups,
  ) => client.setAccountData(client.userID!, _accountDataType, {
    'groups': groups.map((g) => g.toJson()).toList(),
  });

  /// A room can only belong to one group at a time, to avoid ambiguous
  /// send-routing (which group's dropdown would "own" it otherwise).
  static UnifiedContactGroup? groupForRoom(Client client, String roomId) {
    for (final group in getGroups(client)) {
      if (group.roomIds.contains(roomId)) return group;
    }
    return null;
  }

  static UnifiedContactGroup? groupById(Client client, String groupId) {
    for (final group in getGroups(client)) {
      if (group.id == groupId) return group;
    }
    return null;
  }

  /// Throws if any of [roomIds] already belongs to another group.
  static Future<UnifiedContactGroup> createGroup(
    Client client, {
    required String label,
    required List<String> roomIds,
    Map<String, String> roomLabels = const {},
  }) async {
    final groups = getGroups(client);
    for (final roomId in roomIds) {
      if (groups.any((g) => g.roomIds.contains(roomId))) {
        throw StateError(
          'Room $roomId already belongs to another unified contact.',
        );
      }
    }

    final group = UnifiedContactGroup(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: label,
      roomIds: roomIds,
      roomLabels: roomLabels,
    );

    await _saveGroups(client, [...groups, group]);
    return group;
  }

  static Future<void> deleteGroup(Client client, String groupId) async {
    final groups = getGroups(client);
    await _saveGroups(client, groups.where((g) => g.id != groupId).toList());
  }

  static Future<void> setLastUsedRoom(
    Client client,
    String groupId,
    String roomId,
  ) async {
    final groups = getGroups(client);
    final updated = groups
        .map(
          (g) => g.id == groupId ? g.copyWith(lastUsedRoomId: roomId) : g,
        )
        .toList();
    await _saveGroups(client, updated);
  }

  /// Drops a room from whichever group it belongs to (e.g. it was left or
  /// deleted) without breaking the rest of the group. No-op if the room
  /// isn't in any group, or if it's a group's only remaining room (the
  /// group itself is deleted instead, since a one-room "unified" contact
  /// isn't meaningful).
  static Future<void> removeRoomFromItsGroup(
    Client client,
    String roomId,
  ) async {
    final group = groupForRoom(client, roomId);
    if (group == null) return;

    final remainingRoomIds = group.roomIds.where((id) => id != roomId).toList();
    if (remainingRoomIds.length < 2) {
      await deleteGroup(client, group.id);
      return;
    }

    final remainingLabels = Map<String, String>.from(group.roomLabels)
      ..remove(roomId);
    final groups = getGroups(client);
    final updated = groups
        .map(
          (g) => g.id == group.id
              ? g.copyWith(
                  roomIds: remainingRoomIds,
                  roomLabels: remainingLabels,
                  lastUsedRoomId: group.lastUsedRoomId == roomId
                      ? remainingRoomIds.first
                      : group.lastUsedRoomId,
                )
              : g,
        )
        .toList();
    await _saveGroups(client, updated);
  }

  /// True only once every member room is muted - a merged conversation
  /// muting/unmuting acts as one unit rather than leaving some networks
  /// muted and others not, since it's presented as a single conversation.
  static bool isMuted(Client client, UnifiedContactGroup group) {
    return group.roomIds.every(
      (roomId) =>
          client.getRoomById(roomId)?.pushRuleState != PushRuleState.notify,
    );
  }

  static Future<void> toggleMuted(Client client, UnifiedContactGroup group) {
    final targetState = isMuted(client, group)
        ? PushRuleState.notify
        : PushRuleState.mentionsOnly;
    return Future.wait([
      for (final roomId in group.roomIds)
        if (client.getRoomById(roomId) case final room?)
          room.setPushRuleState(targetState),
    ]);
  }
}
