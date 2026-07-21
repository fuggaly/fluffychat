import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat/typing_indicators.dart' show TypingDots;
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'unified_chat.dart';

/// Mirrors [TypingIndicators], but a merged conversation has no single
/// room to watch - it's typing state unioned across every member room, so
/// someone typing on either the WhatsApp or SMS side of a merged contact
/// shows up the same way.
class UnifiedTypingIndicators extends StatelessWidget {
  final UnifiedChatController controller;

  const UnifiedTypingIndicators(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = controller.group;
    if (group == null) return const SizedBox.shrink();

    const avatarSize = Avatar.defaultSize / 2;

    return StreamBuilder<Object>(
      stream: controller.client.onSync.stream.where(
        (syncUpdate) => group.roomIds.any(
          (roomId) =>
              syncUpdate.rooms?.join?[roomId]?.ephemeral?.any(
                (ephemeral) => ephemeral.type == 'm.typing',
              ) ??
              false,
        ),
      ),
      builder: (context, _) {
        final typingUsers = <User>[
          for (final roomId in group.roomIds)
            ...?controller.client.getRoomById(roomId)?.typingUsers,
        ]..removeWhere((u) => u.stateKey == controller.client.userID);

        final mergedEvents = controller.mergedEvents;

        return Container(
          width: double.infinity,
          alignment: Alignment.center,
          child: AnimatedContainer(
            constraints: const BoxConstraints(
              maxWidth: FluffyThemes.maxTimelineWidth,
            ),
            height: typingUsers.isEmpty ? 0 : avatarSize + 8,
            duration: FluffyThemes.animationDuration,
            curve: FluffyThemes.animationCurve,
            alignment:
                mergedEvents.isNotEmpty &&
                    mergedEvents.first.senderId == controller.client.userID
                ? Alignment.topRight
                : Alignment.topLeft,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              children: [
                Container(
                  alignment: Alignment.center,
                  height: avatarSize,
                  width: Avatar.defaultSize,
                  child: Stack(
                    children: [
                      if (typingUsers.isNotEmpty)
                        Avatar(
                          size: avatarSize,
                          mxContent: typingUsers.first.avatarUrl,
                          name: typingUsers.first.calcDisplayname(),
                        ),
                      if (typingUsers.length == 2)
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Avatar(
                            size: avatarSize,
                            mxContent: typingUsers.length == 2
                                ? typingUsers.last.avatarUrl
                                : null,
                            name: typingUsers.length == 2
                                ? typingUsers.last.calcDisplayname()
                                : '+${typingUsers.length - 1}',
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppConfig.borderRadius),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: typingUsers.isEmpty ? null : const TypingDots(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
