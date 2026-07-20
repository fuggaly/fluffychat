import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart' show AddPopupMenuActions;
import 'package:fluffychat/utils/bridge_unification/bridge_label.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../config/themes.dart';
import 'unified_chat.dart';

/// The merged conversation's composer row - mirrors [ChatInputRow]'s
/// layout and styling exactly (attach button, emoji button, text field,
/// send button) so a unified conversation looks like any other room, with
/// one addition: a network-selector dropdown showing which underlying
/// bridge a message will actually send through.
class UnifiedChatInputRow extends StatelessWidget {
  final UnifiedChatController controller;

  static const double height = 56.0;

  const UnifiedChatInputRow(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = controller.group;
    if (group == null) return const SizedBox.shrink();

    final textMessageOnly = controller.sendController.text.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(width: 8),
        AnimatedContainer(
          duration: FluffyThemes.animationDuration,
          curve: FluffyThemes.animationCurve,
          width: textMessageOnly ? 0 : 48,
          height: height,
          alignment: Alignment.center,
          decoration: const BoxDecoration(),
          clipBehavior: Clip.hardEdge,
          child: PopupMenuButton<AddPopupMenuActions>(
            useRootNavigator: true,
            icon: const Icon(Icons.add_circle_outline),
            iconColor: theme.colorScheme.onPrimaryContainer,
            onSelected: controller.onAddPopupMenuButtonSelected,
            itemBuilder: (BuildContext context) => [
              if (PlatformInfos.isMobile)
                PopupMenuItem(
                  value: AddPopupMenuActions.location,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.onPrimaryContainer,
                      foregroundColor: theme.colorScheme.primaryContainer,
                      child: const Icon(Icons.gps_fixed_outlined),
                    ),
                    title: Text(L10n.of(context).shareLocation),
                    contentPadding: const EdgeInsets.all(0),
                  ),
                ),
              PopupMenuItem(
                value: AddPopupMenuActions.poll,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.onPrimaryContainer,
                    foregroundColor: theme.colorScheme.primaryContainer,
                    child: const Icon(Icons.poll_outlined),
                  ),
                  title: Text(L10n.of(context).startPoll),
                  contentPadding: const EdgeInsets.all(0),
                ),
              ),
              PopupMenuDivider(),
              if (PlatformInfos.isMobile) ...[
                PopupMenuItem(
                  value: AddPopupMenuActions.videoCamera,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.onPrimaryContainer,
                      foregroundColor: theme.colorScheme.primaryContainer,
                      child: const Icon(Icons.videocam_outlined),
                    ),
                    title: Text(L10n.of(context).recordAVideo),
                    contentPadding: const EdgeInsets.all(0),
                  ),
                ),
                PopupMenuItem(
                  value: AddPopupMenuActions.photoCamera,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.onPrimaryContainer,
                      foregroundColor: theme.colorScheme.primaryContainer,
                      child: const Icon(Icons.camera_alt_outlined),
                    ),
                    title: Text(L10n.of(context).takeAPhoto),
                    contentPadding: const EdgeInsets.all(0),
                  ),
                ),
                PopupMenuDivider(),
              ],
              PopupMenuItem(
                value: AddPopupMenuActions.image,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.onPrimaryContainer,
                    foregroundColor: theme.colorScheme.primaryContainer,
                    child: const Icon(Icons.photo_outlined),
                  ),
                  title: Text(L10n.of(context).sendImage),
                  contentPadding: const EdgeInsets.all(0),
                ),
              ),
              PopupMenuItem(
                value: AddPopupMenuActions.video,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.onPrimaryContainer,
                    foregroundColor: theme.colorScheme.primaryContainer,
                    child: const Icon(Icons.video_camera_back_outlined),
                  ),
                  title: Text(L10n.of(context).sendVideo),
                  contentPadding: const EdgeInsets.all(0),
                ),
              ),
              PopupMenuItem(
                value: AddPopupMenuActions.file,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.onPrimaryContainer,
                    foregroundColor: theme.colorScheme.primaryContainer,
                    child: const Icon(Icons.attachment_outlined),
                  ),
                  title: Text(L10n.of(context).sendFile),
                  contentPadding: const EdgeInsets.all(0),
                ),
              ),
            ],
          ),
        ),
        Container(
          height: height,
          width: 48,
          alignment: Alignment.center,
          child: IconButton(
            tooltip: L10n.of(context).emojis,
            color: theme.colorScheme.onPrimaryContainer,
            icon: Icon(
              controller.showEmojiPicker
                  ? Icons.keyboard
                  : Icons.add_reaction_outlined,
              key: ValueKey(controller.showEmojiPicker),
            ),
            onPressed: controller.emojiPickerAction,
          ),
        ),
        Container(
          height: height,
          width: 48,
          alignment: Alignment.center,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: controller.selectedRoomId,
              items: group.roomIds.map((roomId) {
                final label = controller.labelForRoom(roomId);
                return DropdownMenuItem(
                  value: roomId,
                  child: Tooltip(
                    message: label,
                    child: FaIcon(
                      iconForBridgeLabel(label),
                      size: 18,
                      color: colorForBridgeLabel(label),
                    ),
                  ),
                );
              }).toList(),
              onChanged: controller.selectRoom,
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: TextField(
              minLines: 1,
              maxLines: 8,
              autofocus: !PlatformInfos.isMobile,
              keyboardType: TextInputType.multiline,
              focusNode: controller.inputFocus,
              controller: controller.sendController,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.only(
                  left: 6.0,
                  right: 6.0,
                  bottom: 6.0,
                  top: 3.0,
                ),
                hintText: 'Send a message...',
                hintMaxLines: 1,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                filled: false,
              ),
              onChanged: (_) => controller.onInputChanged(),
              onSubmitted: (_) => controller.send(),
            ),
          ),
        ),
        Container(
          height: height,
          width: height,
          alignment: Alignment.center,
          child: IconButton(
            key: const Key('unified_send_button'),
            tooltip: '${L10n.of(context).send} (long-press to schedule)',
            onPressed: controller.send,
            onLongPress: controller.scheduleSend,
            style: IconButton.styleFrom(
              backgroundColor: theme.bubbleColor,
              foregroundColor: theme.onBubbleColor,
            ),
            icon: const Icon(Icons.send_outlined),
          ),
        ),
      ],
    );
  }
}
