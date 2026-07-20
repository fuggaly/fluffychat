import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/delay_send/scheduler_api_client.dart';
import 'package:flutter/material.dart';

import 'chat.dart';

/// Shows this room's own Delay Send queue as faded "ghost" bubbles above
/// the composer, so a message written for later doesn't get forgotten (or
/// duplicated) mid-conversation - each one can be sent immediately, edited
/// and sent immediately, or cancelled right from here instead of needing
/// to go find it in Delay Send settings.
class PendingScheduledMessages extends StatelessWidget {
  final ChatController controller;

  const PendingScheduledMessages(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: controller.pendingScheduledMessages
          .map((msg) => _PendingScheduledMessage(controller: controller, msg: msg))
          .toList(),
    );
  }
}

class _PendingScheduledMessage extends StatelessWidget {
  final ChatController controller;
  final ScheduledMessage msg;

  const _PendingScheduledMessage({required this.controller, required this.msg});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4.0, bottom: 2.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'Scheduled for ${msg.sendAt.localizedTime(context)}'
                  '${msg.attempts > 0 ? ' • retrying' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: FluffyThemes.maxTimelineWidth * 0.66,
            ),
            child: Opacity(
              opacity: 0.55,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 8.0,
                ),
                decoration: BoxDecoration(
                  color: theme.bubbleColor,
                  borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: Text(
                  msg.body,
                  style: TextStyle(
                    color: theme.onBubbleColor,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: msg.attempts > 0
                    ? null
                    : () => controller.sendScheduledMessageNow(msg),
                child: const Text('Send now'),
              ),
              TextButton(
                onPressed: msg.attempts > 0
                    ? null
                    : () => controller.editAndSendScheduledMessageNow(msg),
                child: const Text('Edit & send'),
              ),
              TextButton(
                onPressed: msg.attempts > 0
                    ? null
                    : () => controller.cancelScheduledMessage(msg),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
