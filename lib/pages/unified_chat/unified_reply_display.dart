import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/reply_content.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'unified_chat.dart';

/// Mirrors [ReplyDisplay], but there's no single fixed timeline to hand
/// [ReplyContent] - the event being replied to/edited could belong to any
/// of the group's member rooms, so its own Timeline is looked up per-event
/// via [UnifiedChatController.timelineForEvent].
class UnifiedReplyDisplay extends StatelessWidget {
  final UnifiedChatController controller;

  const UnifiedReplyDisplay(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final replyEvent = controller.replyEvent;
    final editEvent = controller.editEvent;

    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      height: editEvent != null || replyEvent != null ? 56 : 0,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(color: theme.colorScheme.onInverseSurface),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: L10n.of(context).close,
            icon: const Icon(Icons.close),
            onPressed: controller.cancelReplyEventAction,
          ),
          Expanded(
            child: replyEvent != null
                ? ReplyContent(
                    replyEvent,
                    timeline: controller.timelineForEvent(replyEvent),
                  )
                : _EditContent(
                    editEvent?.getDisplayEvent(
                      controller.timelineForEvent(editEvent)!,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EditContent extends StatelessWidget {
  final Event? event;

  const _EditContent(this.event);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = this.event;
    if (event == null) {
      return const SizedBox.shrink();
    }
    return Row(
      children: <Widget>[
        Icon(Icons.edit, color: theme.colorScheme.primary),
        Container(width: 15.0),
        Text(
          event
              .calcLocalizedBodyFallback(
                MatrixLocals(L10n.of(context)),
                withSenderNamePrefix: false,
                hideReply: true,
              )
              .trim()
              .replaceAll('\n', ' '),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(color: theme.textTheme.bodyMedium!.color),
        ),
      ],
    );
  }
}
