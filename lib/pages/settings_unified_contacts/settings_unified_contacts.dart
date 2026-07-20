import 'package:fluffychat/pages/settings_unified_contacts/room_picker_dialog.dart';
import 'package:fluffychat/utils/bridge_unification/bridge_label.dart';
import 'package:fluffychat/utils/bridge_unification/unified_contact_group.dart';
import 'package:fluffychat/utils/bridge_unification/unified_contacts_service.dart';
import 'package:fluffychat/utils/show_scaffold_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class SettingsUnifiedContacts extends StatefulWidget {
  const SettingsUnifiedContacts({super.key});

  @override
  State<SettingsUnifiedContacts> createState() =>
      _SettingsUnifiedContactsState();
}

class _SettingsUnifiedContactsState extends State<SettingsUnifiedContacts> {
  String _roomDisplayName(Client client, String roomId) {
    final room = client.getRoomById(roomId);
    if (room == null) return roomId;
    return room.getLocalizedDisplayname();
  }

  Future<void> _createGroup() async {
    final client = Matrix.of(context).client;

    final selectedRoomIds = await showScaffoldDialog<Set<String>>(
      context: context,
      builder: (context) => const RoomPickerDialog(),
    );
    if (selectedRoomIds == null || selectedRoomIds.length < 2) return;
    if (!mounted) return;

    final firstRoom = client.getRoomById(selectedRoomIds.first);
    final label = await showTextInputDialog(
      context: context,
      title: 'Name this unified contact',
      hintText: 'e.g. a person\'s name',
      initialText: firstRoom?.getLocalizedDisplayname(),
    );
    if (label == null || label.trim().isEmpty) return;

    final roomLabels = <String, String>{};
    for (final roomId in selectedRoomIds) {
      final room = client.getRoomById(roomId);
      if (room == null) continue;
      roomLabels[roomId] =
          bridgeLabelForRoom(room) ?? room.getLocalizedDisplayname();
    }

    await UnifiedContactsService.createGroup(
      client,
      label: label.trim(),
      roomIds: selectedRoomIds.toList(),
      roomLabels: roomLabels,
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _deleteGroup(UnifiedContactGroup group) async {
    final confirmed = await showOkCancelAlertDialog(
      context: context,
      title: 'Un-merge "${group.label}"?',
      message:
          'This only stops treating these rooms as one conversation - it does not leave or delete any room.',
      okLabel: 'Un-merge',
      isDestructive: true,
    );
    if (confirmed != OkCancelResult.ok || !mounted) return;
    await UnifiedContactsService.deleteGroup(
      Matrix.of(context).client,
      group.id,
    );
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final groups = UnifiedContactsService.getGroups(client);

    return Scaffold(
      appBar: AppBar(title: const Text('Unified Contacts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createGroup,
        icon: const Icon(Icons.merge_outlined),
        label: const Text('Merge rooms'),
      ),
      body: groups.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No unified contacts yet. Merge two or more rooms (e.g. someone\'s WhatsApp + Google Messages rooms) into one conversation.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: groups
                  .map(
                    (group) => Card(
                      child: ListTile(
                        title: Text(group.label),
                        subtitle: Text(
                          group.roomIds
                              .map(
                                (id) =>
                                    group.roomLabels[id] ??
                                    _roomDisplayName(client, id),
                              )
                              .join(' • '),
                        ),
                        trailing: IconButton(
                          tooltip: 'Un-merge',
                          icon: const Icon(Icons.close_outlined),
                          onPressed: () => _deleteGroup(group),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}
