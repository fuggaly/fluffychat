import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat_emoji_picker.dart' show NoRecent;
import 'package:fluffychat/pages/chat/sticker_picker_dialog.dart';
import 'package:fluffychat/pages/chat/trust_user_key_dialog.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'unified_chat.dart';

/// Mirrors [ChatEmojiPicker] - same emoji/stickers tabs, styling and
/// animated reveal - but targets whichever underlying room is currently
/// selected in the network dropdown rather than a single fixed room.
class UnifiedChatEmojiPicker extends StatelessWidget {
  final UnifiedChatController controller;

  const UnifiedChatEmojiPicker(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = controller.selectedRoom;
    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      height: controller.showEmojiPicker
          ? MediaQuery.sizeOf(context).height / 2
          : 0,
      child: !controller.showEmojiPicker || room == null
          ? null
          : DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    tabs: [
                      Tab(text: L10n.of(context).emojis),
                      Tab(text: L10n.of(context).stickers),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        EmojiPicker(
                          onEmojiSelected: controller.onEmojiSelected,
                          onBackspacePressed: controller.emojiPickerBackspace,
                          config: Config(
                            locale: Localizations.localeOf(context),
                            emojiViewConfig: EmojiViewConfig(
                              noRecents: const NoRecent(),
                              backgroundColor:
                                  theme.colorScheme.onInverseSurface,
                            ),
                            bottomActionBarConfig: const BottomActionBarConfig(
                              enabled: false,
                            ),
                            categoryViewConfig: CategoryViewConfig(
                              backspaceColor: theme.colorScheme.primary,
                              iconColor: theme.colorScheme.primary.withAlpha(
                                128,
                              ),
                              iconColorSelected: theme.colorScheme.primary,
                              indicatorColor: theme.colorScheme.primary,
                              backgroundColor: theme.colorScheme.surface,
                            ),
                            skinToneConfig: SkinToneConfig(
                              dialogBackgroundColor: Color.lerp(
                                theme.colorScheme.surface,
                                theme.colorScheme.primaryContainer,
                                0.75,
                              )!,
                              indicatorColor: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        StickerPickerDialog(
                          room: room,
                          onSelected: (sticker) async {
                            final proceed = await showTrustUserInRoomDialog(
                              context,
                              room,
                            );
                            if (!proceed) return;
                            room.sendEvent({
                              'body': sticker.body,
                              'info': sticker.info ?? {},
                              'url': sticker.url.toString(),
                            }, type: EventTypes.Sticker);
                            controller.hideEmojiPicker();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
