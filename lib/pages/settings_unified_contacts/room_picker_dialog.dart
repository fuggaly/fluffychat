import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/bridge_unification/unified_contacts_service.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// Multi-select room picker for creating a unified-contact group. Excludes
/// rooms already in another group (one group per room, to avoid ambiguous
/// send-routing).
class RoomPickerDialog extends StatefulWidget {
  const RoomPickerDialog({super.key});

  @override
  State<RoomPickerDialog> createState() => _RoomPickerDialogState();
}

class _RoomPickerDialogState extends State<RoomPickerDialog> {
  final TextEditingController _filterController = TextEditingController();
  final Set<String> _selectedRoomIds = {};

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final rooms = client.rooms
        .where(
          (room) =>
              room.canSendDefaultMessages &&
              !room.isSpace &&
              room.membership == Membership.join &&
              UnifiedContactsService.groupForRoom(client, room.id) == null,
        )
        .toList();
    final filter = _filterController.text.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(
        leading: Center(child: CloseButton(onPressed: context.pop)),
        title: const Text('Select 2+ rooms to merge'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            toolbarHeight: 72,
            scrolledUnderElevation: 0,
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false,
            title: TextField(
              controller: _filterController,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                filled: true,
                fillColor: theme.colorScheme.secondaryContainer,
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(99),
                ),
                contentPadding: EdgeInsets.zero,
                hintText: L10n.of(context).search,
                floatingLabelBehavior: FloatingLabelBehavior.never,
                prefixIcon: const Icon(Icons.search_outlined),
              ),
            ),
          ),
          SliverList.builder(
            itemCount: rooms.length,
            itemBuilder: (context, i) {
              final room = rooms[i];
              final displayname = room.getLocalizedDisplayname(
                MatrixLocals(L10n.of(context)),
              );
              final selected = _selectedRoomIds.contains(room.id);
              final filterOut = !displayname.toLowerCase().contains(filter);
              if (!selected && filterOut) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: CheckboxListTile.adaptive(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                  ),
                  controlAffinity: ListTileControlAffinity.trailing,
                  secondary: Avatar(
                    mxContent: room.avatar,
                    name: displayname,
                    size: Avatar.defaultSize * 0.75,
                  ),
                  title: Text(
                    displayname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  value: selected,
                  onChanged: (_) => setState(() {
                    if (selected) {
                      _selectedRoomIds.remove(room.id);
                    } else {
                      _selectedRoomIds.add(room.id);
                    }
                  }),
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: _selectedRoomIds.length < 2
            ? const SizedBox.shrink()
            : Material(
                elevation: 8,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton(
                      onPressed: () => context.pop(_selectedRoomIds),
                      child: Text('Merge ${_selectedRoomIds.length} rooms'),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
