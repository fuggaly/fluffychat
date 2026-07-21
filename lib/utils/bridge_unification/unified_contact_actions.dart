import 'package:fluffychat/utils/bridge_unification/unified_contact_group.dart';
import 'package:fluffychat/utils/bridge_unification/unified_contacts_service.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

enum _UnifiedContactMenuAction { toggleMute, ungroup }

/// Shared mute/un-merge menu for a unified contact - used both from the
/// room list (long-press on UnifiedConversationTile) and from within the
/// merged conversation itself (an app bar action), so both get the exact
/// same actions and wording from one implementation.
///
/// "Un-merge" deliberately isn't called "leave" even though it plays the
/// same role a normal room's leave action does - unlike leaving a real
/// room, it only dissolves the grouping (deleteGroup), it never touches
/// membership in the underlying rooms themselves.
///
/// [onUngrouped] runs after a successful un-merge so the caller can react
/// (e.g. navigate away from a chat view whose route just became invalid).
/// The room list doesn't need to pass one - it already rebuilds on the
/// resulting account_data sync.
Future<void> showUnifiedContactMenu(
  BuildContext context, {
  required Client client,
  required UnifiedContactGroup group,
  VoidCallback? onUngrouped,
}) async {
  final muted = UnifiedContactsService.isMuted(client, group);
  final action = await showModalActionPopup<_UnifiedContactMenuAction>(
    context: context,
    title: group.label,
    actions: [
      AdaptiveModalAction(
        value: _UnifiedContactMenuAction.toggleMute,
        label: muted ? 'Unmute' : 'Mute',
        icon: Icon(
          muted ? Icons.notifications_off : Icons.notifications_off_outlined,
        ),
      ),
      AdaptiveModalAction(
        value: _UnifiedContactMenuAction.ungroup,
        label: 'Un-merge',
        icon: const Icon(Icons.link_off),
        isDestructive: true,
      ),
    ],
  );
  if (action == null) return;

  switch (action) {
    case _UnifiedContactMenuAction.toggleMute:
      await UnifiedContactsService.toggleMuted(client, group);
    case _UnifiedContactMenuAction.ungroup:
      if (!context.mounted) return;
      final confirmed = await showOkCancelAlertDialog(
        context: context,
        title: 'Un-merge "${group.label}"?',
        message:
            'This only stops treating these rooms as one conversation - it does not leave or delete any room.',
        okLabel: 'Un-merge',
        isDestructive: true,
      );
      if (confirmed != OkCancelResult.ok) return;
      await UnifiedContactsService.deleteGroup(client, group.id);
      onUngrouped?.call();
  }
}
