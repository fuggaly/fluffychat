import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/pages/unified_chat/unified_chat_view.dart';
import 'package:fluffychat/utils/bridge_unification/bridge_label.dart';
import 'package:fluffychat/utils/bridge_unification/unified_contact_group.dart';
import 'package:fluffychat/utils/bridge_unification/unified_contacts_service.dart';
import 'package:fluffychat/utils/delay_send/schedule_send_dialog.dart';
import 'package:fluffychat/utils/delay_send/scheduler_api_client.dart';
import 'package:fluffychat/utils/delay_send/scheduler_config.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

/// A merged view of a unified-contact group's member rooms, presented as
/// one conversation. Composes one [Timeline] per member room (rather than
/// a deeper chat-view rewrite) and merges their events by timestamp.
class UnifiedChat extends StatefulWidget {
  final String groupId;

  const UnifiedChat({required this.groupId, super.key});

  @override
  State<UnifiedChat> createState() => UnifiedChatController();
}

class UnifiedChatController extends State<UnifiedChat> {
  final Map<String, Timeline> timelines = {};
  final TextEditingController sendController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  bool loading = true;
  String? selectedRoomId;
  bool _timelinesRequested = false;

  // Same computation ChatController itself uses (large-emoji-only
  // messages render bigger) - reused as-is so message rendering styling
  // matches a normal room exactly, per the point of reusing the real
  // Message widget here at all.
  late final Set<String> bigEmojis = defaultEmojiSet.fold(
    <String>{},
    (emojis, category) => {...emojis, ...category.emoji.map((e) => e.emoji)},
  );

  Client get client => Matrix.of(context).client;

  /// The Timeline a merged event's own bridge room belongs to - Message
  /// needs this (e.g. to resolve edits via getDisplayEvent), and since
  /// events here come from N different rooms' timelines, it can't just be
  /// one fixed timeline like a normal single-room chat view.
  Timeline? timelineForEvent(Event event) => timelines[event.room.id];

  UnifiedContactGroup? get group =>
      UnifiedContactsService.groupById(client, widget.groupId);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_timelinesRequested) {
      _timelinesRequested = true;
      _loadTimelines();
    }
  }

  Future<void> _loadTimelines() async {
    final currentGroup = group;
    if (currentGroup == null) {
      setState(() => loading = false);
      return;
    }

    selectedRoomId = currentGroup.defaultRoomId;

    for (final roomId in currentGroup.roomIds) {
      final room = client.getRoomById(roomId);
      if (room == null) continue;
      timelines[roomId] = await room.getTimeline(
        onUpdate: () {
          if (mounted) setState(() {});
        },
      );
    }

    if (!mounted) return;
    setState(() => loading = false);
  }

  /// All message events from every member room's timeline, newest first.
  List<Event> get mergedEvents {
    final events = <Event>[
      for (final timeline in timelines.values)
        ...timeline.events.where((e) => e.type == EventTypes.Message),
    ];
    events.sort((a, b) => b.originServerTs.compareTo(a.originServerTs));
    return events;
  }

  static const int _loadHistoryCount = 100;

  /// Whether any member room's timeline still has older history to load -
  /// scrolling to the top should keep working until every one of them says
  /// no.
  bool get canRequestHistory =>
      timelines.values.any((timeline) => timeline.canRequestHistory);

  bool get isRequestingHistory =>
      timelines.values.any((timeline) => timeline.isRequestingHistory);

  /// Pages back every member room's timeline in parallel. A single merged
  /// ListView has no per-room "top" to hit, so unlike a normal room this
  /// can't request history from just one Timeline - otherwise a room that
  /// happens to have less history than its sibling would silently stop
  /// contributing older messages to the merge while the other kept going.
  Future<void> requestHistory([_]) async {
    await Future.wait([
      for (final timeline in timelines.values)
        if (timeline.canRequestHistory)
          timeline.requestHistory(historyCount: _loadHistoryCount),
    ]);
  }

  String labelForRoom(String roomId) =>
      effectiveRoomLabel(client.getRoomById(roomId), group?.roomLabels[roomId]);

  void selectRoom(String? roomId) {
    if (roomId == null) return;
    setState(() => selectedRoomId = roomId);
  }

  Future<void> send() async {
    final currentGroup = group;
    final roomId = selectedRoomId;
    if (currentGroup == null || roomId == null) return;
    if (sendController.text.trim().isEmpty) return;

    final room = client.getRoomById(roomId);
    if (room == null) return;

    final body = sendController.text;
    sendController.clear();
    setState(() {});

    // ignore: unawaited_futures
    room.sendTextEvent(body);
    await UnifiedContactsService.setLastUsedRoom(
      client,
      currentGroup.id,
      roomId,
    );
  }

  Future<void> scheduleSend() async {
    final currentGroup = group;
    final roomId = selectedRoomId;
    if (currentGroup == null || roomId == null) return;
    if (sendController.text.trim().isEmpty) return;

    final configured = await SchedulerConfig.isConfigured();
    if (!mounted) return;

    if (!configured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Delay Send is not set up yet - configure it in Chat settings first.',
          ),
        ),
      );
      return;
    }

    final sendAt = await showScheduleSendDialog(context);
    if (sendAt == null || !mounted) return;

    final body = sendController.text;

    try {
      await SchedulerApiClient().create(
        roomId: roomId,
        body: body,
        sendAt: sendAt,
      );
    } on SchedulerApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not schedule message: ${e.message}')),
      );
      return;
    }

    await UnifiedContactsService.setLastUsedRoom(
      client,
      currentGroup.id,
      roomId,
    );
    if (!mounted) return;
    sendController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Message scheduled for $sendAt via ${labelForRoom(roomId)}',
        ),
      ),
    );
    setState(() {});
  }

  @override
  void dispose() {
    sendController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UnifiedChatView(this);
}
