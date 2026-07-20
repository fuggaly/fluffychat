import 'package:collection/collection.dart';
import 'package:fluffychat/utils/bridge_unification/unified_contact_group.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// Avatar for a unified-contact group. A DM room with no explicit
/// m.room.avatar falls back to the other member's own profile picture
/// (Room.avatar), which needs lazy-loaded member state fetched into
/// memory first (loadHeroUsers()) - same reason normal chat tiles/app
/// bars do this. Member room order isn't guaranteed (came from a Set at
/// group-creation time), and not every bridge/contact has a synced
/// picture (e.g. an SMS-only contact commonly has none), so this loads
/// every member room's hero users in parallel and uses whichever one
/// actually ends up with a usable avatar, not just the first in the list.
class UnifiedGroupAvatar extends StatelessWidget {
  final Client client;
  final UnifiedContactGroup group;
  final double size;

  const UnifiedGroupAvatar({
    required this.client,
    required this.group,
    this.size = Avatar.defaultSize,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final rooms = group.roomIds
        .map(client.getRoomById)
        .whereType<Room>()
        .toList();

    return FutureBuilder(
      future: Future.wait(
        rooms.where((r) => r.avatar == null).map((r) => r.loadHeroUsers()),
      ),
      builder: (context, _) {
        final avatarRoom = rooms.firstWhereOrNull((r) => r.avatar != null);
        return Avatar(
          mxContent: avatarRoom?.avatar,
          name: group.label,
          size: size,
        );
      },
    );
  }
}
