import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/utils/bridge_unification/unified_contact_actions.dart';
import 'package:fluffychat/utils/bridge_unification/unified_contact_group.dart';
import 'package:fluffychat/utils/bridge_unification/unified_group_avatar.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// A room-list entry for a unified-contact group - stands in for its
/// (hidden, see ChatListController.filteredRooms) member rooms. Not backed
/// by a single Room, so this is a small standalone tile rather than
/// reusing ChatListItem, which is written specifically around one Room.
class UnifiedConversationTile extends StatelessWidget {
  final Client client;
  final UnifiedContactGroup group;

  const UnifiedConversationTile({
    required this.client,
    required this.group,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rooms = group.roomIds
        .map(client.getRoomById)
        .whereType<Room>()
        .toList();

    final unreadCount = rooms.fold<int>(
      0,
      (sum, room) => sum + room.notificationCount,
    );

    final lastEvent = rooms
        .map((r) => r.lastEvent)
        .whereType<Event>()
        .fold<Event?>(
          null,
          (latest, event) =>
              latest == null ||
                  event.originServerTs.isAfter(latest.originServerTs)
              ? event
              : latest,
        );

    // Same "most recent activity" concept ChatListItem shows next to a
    // normal room's name (room.latestEventReceivedTime) - taken across all
    // of this group's member rooms since it isn't backed by one Room.
    final latestReceivedTime = rooms
        .map((r) => r.latestEventReceivedTime)
        .fold<DateTime?>(
          null,
          (latest, time) =>
              latest == null || time.isAfter(latest) ? time : latest,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        clipBehavior: Clip.hardEdge,
        child: ListTile(
          minVerticalPadding: 16,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: UnifiedGroupAvatar(client: client, group: group),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  group.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (latestReceivedTime != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4.0),
                  child: Text(
                    latestReceivedTime.localizedTimeShort(context),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: unreadCount > 0 ? FontWeight.bold : null,
                      color: unreadCount > 0
                          ? theme.colorScheme.primary
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: lastEvent == null
              ? null
              : Text(
                  lastEvent.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: unreadCount == 0
              ? null
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    unreadCount.toString(),
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
          onTap: () => context.go('/rooms/unified/${group.id}'),
          onLongPress: () =>
              showUnifiedContactMenu(context, client: client, group: group),
        ),
      ),
    );
  }
}
