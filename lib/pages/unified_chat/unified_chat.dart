import 'package:fluffychat/pages/unified_chat/unified_chat_view.dart';
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
  bool loading = true;
  String? selectedRoomId;
  bool _timelinesRequested = false;

  Client get client => Matrix.of(context).client;

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
      timelines[roomId] = await room.getTimeline(onUpdate: () {
        if (mounted) setState(() {});
      });
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

  String labelForRoom(String roomId) =>
      group?.roomLabels[roomId] ?? client.getRoomById(roomId)?.getLocalizedDisplayname() ?? roomId;

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
    await UnifiedContactsService.setLastUsedRoom(client, currentGroup.id, roomId);
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
      await SchedulerApiClient().create(roomId: roomId, body: body, sendAt: sendAt);
    } on SchedulerApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not schedule message: ${e.message}')),
      );
      return;
    }

    await UnifiedContactsService.setLastUsedRoom(client, currentGroup.id, roomId);
    if (!mounted) return;
    sendController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Message scheduled for $sendAt via ${labelForRoom(roomId)}')),
    );
    setState(() {});
  }

  @override
  void dispose() {
    sendController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UnifiedChatView(this);
}
