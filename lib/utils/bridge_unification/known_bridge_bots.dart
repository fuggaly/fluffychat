import 'package:matrix/matrix.dart';

/// The bridge bots' own admin/management-room accounts, per `autobot.mjs`'s
/// WHATSAPP_BOT/GMESSAGES_BOT/SLACK_BOT constants - distinct from per-chat
/// "ghost" users (e.g. `@whatsapp_<phone>:...`), these are the bots' own
/// fixed identities. A DM with one of these is a bridge admin/management
/// room, not a conversation with a contact, and shouldn't clutter the chat
/// list the same way autobot.mjs's own IGNORE_SENDERS/IGNORE_ROOMS treat
/// them server-side.
const knownBridgeBotMxids = {
  '@whatsappbot:matrix.fuggaly.com',
  '@gmessagesbot:matrix.fuggaly.com',
  '@slackbot:matrix.fuggaly.com',
};

bool isBridgeManagementRoom(Room room) {
  if (!room.isDirectChat) return false;
  final partnerId = room.directChatMatrixID;
  return partnerId != null && knownBridgeBotMxids.contains(partnerId);
}
