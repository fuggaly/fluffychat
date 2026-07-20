import 'package:fluffychat/utils/bridge_unification/bridge_label.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
        body: const Center(child: Text('This unified contact no longer exists.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: Text(group.label),
      ),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: controller.mergedEvents.length,
                    itemBuilder: (context, i) {
                      final event = controller.mergedEvents[i];
                      final client = Matrix.of(context).client;
                      final isMe = event.senderId == client.userID;
                      final label = controller.labelForRoom(event.room.id);

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisAlignment: isMe
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (!isMe) ...[
                              Tooltip(
                                message: label,
                                child: Icon(
                                  iconForBridgeLabel(label),
                                  size: 16,
                                  color: colorForBridgeLabel(label),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isMe
                                          ? Theme.of(context).colorScheme.primaryContainer
                                          : Theme.of(context).colorScheme.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(event.body),
                                  ),
                                  Text(
                                    DateFormat.Hm().format(event.originServerTs),
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: label,
                                child: Icon(
                                  iconForBridgeLabel(label),
                                  size: 16,
                                  color: colorForBridgeLabel(label),
                                ),
                              ),
                            ],
                          ],
                        ),
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
                                child: Icon(
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
