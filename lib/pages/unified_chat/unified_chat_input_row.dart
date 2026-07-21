import 'package:fluffychat/config/setting_keys.dart';
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

    if (controller.selectMode) {
      // Simplified stand-in for both ChatInputRow's own selectMode row and
      // ChatAppBarTitle's selectMode actions in a normal room - only Edit,
      // Reply and Close, since forwarding to another room, "try again" for
      // a failed send, copy, redact and reply-in-thread weren't part of
      // what a merged conversation was missing.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            tooltip: L10n.of(context).close,
            icon: const Icon(Icons.close),
            onPressed: controller.clearSelectedEvents,
          ),
          Expanded(
            child: Text(
              '${controller.selectedEvents.length} selected',
              style: theme.textTheme.bodyLarge,
            ),
          ),
          if (controller.canReplySelectedEvent)
            IconButton(
              tooltip: L10n.of(context).reply,
              icon: const Icon(Icons.reply_outlined),
              onPressed: () => controller.replyAction(
                replyTo: controller.selectedEvents.first,
              ),
            ),
          if (controller.canEditSelectedEvents)
            IconButton(
              tooltip: L10n.of(context).edit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: controller.editSelectedEventAction,
            ),
          const SizedBox(width: 8),
        ],
      );
    }

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
        Builder(
          builder: (context) {
            final selectedRoomId =
                controller.selectedRoomId ?? group.defaultRoomId;
            final selectedLabel = controller.labelForRoom(selectedRoomId);
            return Container(
              height: height,
              width: 48,
              alignment: Alignment.center,
              // A plain PopupMenuButton, same as the attach button above -
              // gives the same circular hover highlight as every other
              // icon in this row (a bare DropdownButton draws its own
              // rectangular Material highlight instead) and a proper
              // labeled menu instead of an unlabeled row of tiny icons.
              child: PopupMenuButton<String>(
                useRootNavigator: true,
                tooltip: selectedLabel,
                icon: FaIcon(
                  iconForBridgeLabel(selectedLabel),
                  size: 18,
                  color: colorForBridgeLabel(selectedLabel),
                ),
                onSelected: controller.selectRoom,
                itemBuilder: (context) => group.roomIds.map((roomId) {
                  final label = controller.labelForRoom(roomId);
                  return PopupMenuItem(
                    value: roomId,
                    child: ListTile(
                      leading: FaIcon(
                        iconForBridgeLabel(label),
                        color: colorForBridgeLabel(label),
                      ),
                      title: Text(label),
                      contentPadding: const EdgeInsets.all(0),
                    ),
                  );
                }).toList(),
              ),
            );
          },
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: TextField(
              minLines: 1,
              maxLines: 8,
              autofocus: !PlatformInfos.isMobile,
              keyboardType: TextInputType.multiline,
              textInputAction:
                  AppSettings.sendOnEnter.value == true &&
                      PlatformInfos.isMobile
                  ? TextInputAction.send
                  : null,
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
