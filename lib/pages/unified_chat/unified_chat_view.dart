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
                        child: Column(
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isMe)
                                  Text(
                                    event.senderFromMemoryOrFallback
                                        .calcDisplayname(),
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                if (!isMe) const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    label,
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
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
                          items: group.roomIds
                              .map(
                                (roomId) => DropdownMenuItem(
                                  value: roomId,
                                  child: Text(controller.labelForRoom(roomId)),
                                ),
                              )
                              .toList(),
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
