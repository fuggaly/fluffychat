import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/utils/bridge_unification/bridge_label.dart';
import 'package:fluffychat/utils/bridge_unification/unified_group_avatar.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import 'unified_chat.dart';
import 'unified_chat_emoji_picker.dart';
import 'unified_chat_input_row.dart';

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
                        itemCount: events.length + 1,
                        itemBuilder: (context, i) {
                          // Footer (reversed list, so this renders at the
                          // visual top): mirrors chat_event_list.dart's
                          // "load more history" row. Being built at all
                          // means the user has scrolled close to it, so
                          // that alone triggers the same auto-load a
                          // normal room does.
                          if (i == events.length) {
                            if (!controller.canRequestHistory) {
                              return const SizedBox.shrink();
                            }
                            WidgetsBinding.instance.addPostFrameCallback(
                              controller.requestHistory,
                            );
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8.0,
                                ),
                                child: TextButton.icon(
                                  onPressed: controller.isRequestingHistory
                                      ? null
                                      : controller.requestHistory,
                                  icon: controller.isRequestingHistory
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator
                                              .adaptive(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.arrow_upward_outlined),
                                  label: Text(L10n.of(context).loadMore),
                                ),
                              ),
                            );
                          }

                          final event = events[i];
                          // Same index convention as chat_event_list.dart:
                          // events are newest-first, so index i+1 is the
                          // older (chronologically "next") neighbour and
                          // i-1 is the newer ("previous") one.
                          final nextEvent = i + 1 < events.length
                              ? events[i + 1]
                              : null;
                          final previousEvent = i > 0 ? events[i - 1] : null;
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
                              Message(
                                event,
                                timeline: timeline,
                                nextEvent: nextEvent,
                                previousEvent: previousEvent,
                                bigEmojis: controller.bigEmojis,
                                colors: colors,
                                scrollController: controller.scrollController,
                                // The real per-room sender displayname for
                                // a bridge ghost is literally "Contact via
                                // WhatsApp"/"Contact via SMS" - show the
                                // group's own already-deduped contact name
                                // instead, and force it visible (Message
                                // normally renders it transparent-but-still
                                // -laid-out in a direct chat).
                                senderNameOverride: group.label,
                                // Placed right before the timestamp inside
                                // Message's own metadata row rather than as
                                // a sibling alongside the bubble, so it
                                // never drifts away from the bubble on wide
                                // windows and still shows even on messages
                                // where the timestamp itself is suppressed
                                // (consecutive same-sender messages sent
                                // within the same time bucket).
                                networkIcon: Tooltip(
                                  message: label,
                                  child: FaIcon(
                                    iconForBridgeLabel(label),
                                    size: 12,
                                    color: colorForBridgeLabel(label),
                                  ),
                                ),
                                // Interactive features (reactions, editing,
                                // threads, swipe-to-reply, selection,
                                // mentions) aren't wired up in the merged
                                // view - only rendering parity was asked
                                // for.
                                onSelect: (_) {},
                                onInfoTab: (_) {},
                                scrollToEventId: (_) {},
                                onSwipe: () {},
                                onMention: () {},
                                onEdit: () {},
                                enterThread: null,
                                singleSelected: false,
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Builder(
                    builder: (context) {
                      final theme = Theme.of(context);
                      // Same pill-shaped, centered, width-capped composer
                      // chat_view.dart wraps ChatInputRow/ChatEmojiPicker
                      // in, so a merged conversation's input area matches
                      // a normal room's exactly.
                      final bottomSheetPadding = FluffyThemes.isColumnMode(
                        context,
                      )
                          ? 16.0
                          : 8.0;
                      return Align(
                        alignment: Alignment.center,
                        child: Container(
                          margin: EdgeInsets.all(bottomSheetPadding),
                          constraints: const BoxConstraints(
                            maxWidth: FluffyThemes.maxTimelineWidth,
                          ),
                          child: Material(
                            clipBehavior: Clip.hardEdge,
                            color: theme.colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                UnifiedChatInputRow(controller),
                                UnifiedChatEmojiPicker(controller),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
