import 'package:fluffychat/pages/settings_unified_contacts/room_picker_dialog.dart';
import 'package:fluffychat/utils/bridge_unification/bridge_group_suggestions.dart';
import 'package:fluffychat/utils/bridge_unification/bridge_label.dart';
import 'package:fluffychat/utils/bridge_unification/unified_contact_group.dart';
import 'package:fluffychat/utils/bridge_unification/unified_contacts_service.dart';
import 'package:fluffychat/utils/show_scaffold_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

class SettingsUnifiedContacts extends StatefulWidget {
  const SettingsUnifiedContacts({super.key});

  @override
  State<SettingsUnifiedContacts> createState() =>
      _SettingsUnifiedContactsState();
}

class _SettingsUnifiedContactsState extends State<SettingsUnifiedContacts> {
  // Suggestions are recomputed fresh every build (nothing persisted), so a
  // dismissed one is only remembered for this screen visit - re-opening
  // this page later will offer it again. Acceptable: the phone-matching
  // heuristic is narrow enough that repeat false positives should be rare,
  // and dismissing is a single tap either way.
  final Set<String> _dismissedSuggestionKeys = {};

  String _suggestionKey(SuggestedGroup suggestion) =>
      (suggestion.roomIds.toList()..sort()).join(',');

  String _roomDisplayName(Client client, String roomId) {
    final room = client.getRoomById(roomId);
    if (room == null) return roomId;
    return stripViaSuffix(room.getLocalizedDisplayname());
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
      initialText: firstRoom == null
          ? null
          : stripViaSuffix(firstRoom.getLocalizedDisplayname()),
    );
    if (label == null || label.trim().isEmpty) return;

    final roomLabels = <String, String>{};
    for (final roomId in selectedRoomIds) {
      final room = client.getRoomById(roomId);
      if (room == null) continue;
      roomLabels[roomId] =
          bridgeLabelForRoom(room) ??
          stripViaSuffix(room.getLocalizedDisplayname());
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

  Future<void> _mergeSuggestion(SuggestedGroup suggestion) async {
    final client = Matrix.of(context).client;
    final roomLabels = <String, String>{};
    for (final roomId in suggestion.roomIds) {
      final room = client.getRoomById(roomId);
      if (room == null) continue;
      roomLabels[roomId] =
          bridgeLabelForRoom(room) ??
          stripViaSuffix(room.getLocalizedDisplayname());
    }
    await UnifiedContactsService.createGroup(
      client,
      label: suggestion.suggestedLabel,
      roomIds: suggestion.roomIds,
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
    final suggestions = findSuggestedGroupings(client)
        .where((s) => !_dismissedSuggestionKeys.contains(_suggestionKey(s)))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Unified Contacts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createGroup,
        icon: const Icon(Icons.merge_outlined),
        label: const Text('Merge rooms'),
      ),
      body: groups.isEmpty && suggestions.isEmpty
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
              children: [
                if (suggestions.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Text(
                      'Suggested - same phone number seen on two networks',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  ...suggestions.map(
                    (suggestion) => Card(
                      child: ListTile(
                        title: Text(suggestion.suggestedLabel),
                        subtitle: Text(
                          suggestion.roomIds
                              .map(
                                (id) => effectiveRoomLabel(
                                  client.getRoomById(id),
                                  null,
                                ),
                              )
                              .join(' + '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Dismiss',
                              icon: const Icon(Icons.close_outlined),
                              onPressed: () => setState(
                                () => _dismissedSuggestionKeys.add(
                                  _suggestionKey(suggestion),
                                ),
                              ),
                            ),
                            FilledButton.tonal(
                              onPressed: () => _mergeSuggestion(suggestion),
                              child: const Text('Merge'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 32),
                ],
                ...groups.map(
                  (group) => Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          title: Text(group.label),
                          subtitle: const Text(
                            'Tap a room below to open it individually (not merged)',
                          ),
                          trailing: IconButton(
                            tooltip: 'Un-merge',
                            icon: const Icon(Icons.close_outlined),
                            onPressed: () => _deleteGroup(group),
                          ),
                        ),
                        ...group.roomIds.map((id) {
                          final label = effectiveRoomLabel(
                            client.getRoomById(id),
                            group.roomLabels[id],
                          );
                          return ListTile(
                            dense: true,
                            leading: FaIcon(
                              iconForBridgeLabel(label),
                              color: colorForBridgeLabel(label),
                            ),
                            title: Text(label),
                            subtitle: Text(_roomDisplayName(client, id)),
                            trailing: const Icon(Icons.chevron_right_outlined),
                            onTap: () => context.go('/rooms/$id'),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
