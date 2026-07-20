import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/delay_send/scheduler_api_client.dart';
import 'package:flutter/material.dart';

/// Shows a room's own Delay Send queue as faded "ghost" bubbles above the
/// composer, so a message written for later doesn't get forgotten (or
/// duplicated) mid-conversation - each one can be sent immediately, edited
/// and sent immediately, or cancelled right from here instead of needing
/// to go find it in Delay Send settings.
///
/// Takes plain callbacks rather than a ChatController so both a normal
/// room's chat view and the unified/merged conversation view (which has
/// its own controller and needs to resolve each message's actual
/// underlying bridge room, not just "the" room) can reuse it as-is.
class PendingScheduledMessages extends StatelessWidget {
  final List<ScheduledMessage> messages;
  final void Function(ScheduledMessage) onSendNow;
  final void Function(ScheduledMessage) onEditAndSendNow;
  final void Function(ScheduledMessage) onCancel;

  const PendingScheduledMessages({
    required this.messages,
    required this.onSendNow,
    required this.onEditAndSendNow,
    required this.onCancel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: messages
          .map(
            (msg) => _PendingScheduledMessage(
              msg: msg,
              onSendNow: onSendNow,
              onEditAndSendNow: onEditAndSendNow,
              onCancel: onCancel,
            ),
          )
          .toList(),
    );
  }
}

class _PendingScheduledMessage extends StatelessWidget {
  final ScheduledMessage msg;
  final void Function(ScheduledMessage) onSendNow;
  final void Function(ScheduledMessage) onEditAndSendNow;
  final void Function(ScheduledMessage) onCancel;

  const _PendingScheduledMessage({
    required this.msg,
    required this.onSendNow,
    required this.onEditAndSendNow,
    required this.onCancel,
  });

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
                onPressed: msg.attempts > 0 ? null : () => onSendNow(msg),
                child: const Text('Send now'),
              ),
              TextButton(
                onPressed: msg.attempts > 0
                    ? null
                    : () => onEditAndSendNow(msg),
                child: const Text('Edit & send'),
              ),
              TextButton(
                onPressed: msg.attempts > 0 ? null : () => onCancel(msg),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
