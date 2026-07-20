import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/utils/bridge_unification/bridge_label.dart';
import 'package:fluffychat/utils/bridge_unification/unified_group_avatar.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import 'unified_chat.dart';

class UnifiedChatView extends StatelessWidget {
  final UnifiedChatController controller;

  const UnifiedChatView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final group = controller.group;

    if (group == null) {
      return Scaffold(
        appBar: AppBar(leading: BackButton(onPressed: context.pop)),
        body: const Center(
          child: Text('This unified contact no longer exists.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            UnifiedGroupAvatar(
              client: controller.client,
              group: group,
              size: 32,
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(group.label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : Column(
              children: [
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final theme = Theme.of(context);
                      // Same fixed 2-color palette ChatController's own
                      // event list uses (see chat_event_list.dart) - kept
                      // identical so bubble styling matches exactly.
                      final colors = [
                        theme.secondaryBubbleColor,
                        theme.bubbleColor,
                      ];
                      final events = controller.mergedEvents;

                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: events.length,
                        itemBuilder: (context, i) {
                          final event = events[i];
                          // Same index convention as chat_event_list.dart:
                          // events are newest-first, so index i+1 is the
                          // older (chronologically "next") neighbour and
                          // i-1 is the newer ("previous") one.
                          final nextEvent = i + 1 < events.length
                              ? events[i + 1]
                              : null;
                          final previousEvent = i > 0 ? events[i - 1] : null;
                          final isMe =
                              event.senderId == controller.client.userID;
                          final label = controller.labelForRoom(event.room.id);
                          final timeline = controller.timelineForEvent(event);

                          final displayDate =
                              nextEvent == null ||
                              !event.originServerTs.sameDay(
                                nextEvent.originServerTs,
                              );

                          if (timeline == null) return const SizedBox.shrink();

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (displayDate)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 8.0,
                                    bottom: 16.0,
                                  ),
                                  child: Center(
                                    child: Material(
                                      borderRadius: BorderRadius.circular(
                                        AppConfig.borderRadius * 2,
                                      ),
                                      color: theme.colorScheme.inverseSurface
                                          .withAlpha(200),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8.0,
                                          vertical: 2.0,
                                        ),
                                        child: Text(
                                          event.originServerTs.localizedDate(
                                            context,
                                          ),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: theme
                                                .colorScheme
                                                .onInverseSurface,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Center(
                                child: ConstrainedBox(
                                  // Message internally caps its own bubble
                                  // at FluffyThemes.maxTimelineWidth and
                                  // centers itself within whatever width
                                  // it's given - on windows wider than that
                                  // cap, that left the network icon (a
                                  // sibling placed at the true row edge)
                                  // stranded far from the visually-centered
                                  // bubble. Capping and centering this
                                  // icon+bubble pair as one unit keeps them
                                  // adjacent while still matching a normal
                                  // room's centered-column look on wide
                                  // windows.
                                  constraints: const BoxConstraints(
                                    maxWidth:
                                        FluffyThemes.maxTimelineWidth + 40,
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisAlignment: isMe
                                        ? MainAxisAlignment.end
                                        : MainAxisAlignment.start,
                                    children: [
                                      if (!isMe) ...[
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 12,
                                            bottom: 8,
                                          ),
                                          child: Tooltip(
                                            message: label,
                                            child: FaIcon(
                                              iconForBridgeLabel(label),
                                              size: 16,
                                              color: colorForBridgeLabel(
                                                label,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                      Expanded(
                                        child: Message(
                                          event,
                                          timeline: timeline,
                                          nextEvent: nextEvent,
                                          previousEvent: previousEvent,
                                          bigEmojis: controller.bigEmojis,
                                          colors: colors,
                                          scrollController:
                                              controller.scrollController,
                                          // Interactive features (reactions,
                                          // editing, threads, swipe-to-reply,
                                          // selection, mentions) aren't wired
                                          // up in the merged view - only
                                          // rendering parity was asked for.
                                          onSelect: (_) {},
                                          onInfoTab: (_) {},
                                          scrollToEventId: (_) {},
                                          onSwipe: () {},
                                          onMention: () {},
                                          onEdit: () {},
                                          enterThread: null,
                                          singleSelected: false,
                                        ),
                                      ),
                                      if (isMe) ...[
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 12,
                                            bottom: 8,
                                          ),
                                          child: Tooltip(
                                            message: label,
                                            child: FaIcon(
                                              iconForBridgeLabel(label),
                                              size: 16,
                                              color: colorForBridgeLabel(
                                                label,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        DropdownButton<String>(
                          value: controller.selectedRoomId,
                          items: group.roomIds.map((roomId) {
                            final label = controller.labelForRoom(roomId);
                            return DropdownMenuItem(
                              value: roomId,
                              child: Tooltip(
                                message: label,
                                child: FaIcon(
                                  iconForBridgeLabel(label),
                                  color: colorForBridgeLabel(label),
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: controller.selectRoom,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: controller.sendController,
                            decoration: const InputDecoration(
                              hintText: 'Send a message...',
                            ),
                            onSubmitted: (_) => controller.send(),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Send (long-press to schedule)',
                          icon: const Icon(Icons.send_outlined),
                          onPressed: controller.send,
                          onLongPress: controller.scheduleSend,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
