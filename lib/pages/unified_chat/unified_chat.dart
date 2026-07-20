import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/pages/chat/chat.dart' show AddPopupMenuActions;
import 'package:fluffychat/pages/chat/send_file_dialog.dart';
import 'package:fluffychat/pages/chat/send_location_dialog.dart';
import 'package:fluffychat/pages/chat/start_poll_bottom_sheet.dart';
import 'package:fluffychat/pages/unified_chat/unified_chat_view.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/bridge_unification/bridge_label.dart';
import 'package:fluffychat/utils/bridge_unification/unified_contact_group.dart';
import 'package:fluffychat/utils/bridge_unification/unified_contacts_service.dart';
import 'package:fluffychat/utils/delay_send/schedule_send_dialog.dart';
import 'package:fluffychat/utils/delay_send/scheduler_api_client.dart';
import 'package:fluffychat/utils/delay_send/scheduler_config.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  final FocusNode inputFocus = FocusNode();
  bool loading = true;
  String? selectedRoomId;
  bool _timelinesRequested = false;

  /// Triggers a rebuild as the composer text changes, so the attach
  /// button's hide-while-typing animation (see UnifiedChatInputRow)
  /// reacts the same way ChatInputRow's does.
  void onInputChanged() => setState(() {});

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

  /// The room currently picked in the network dropdown - attachments,
  /// location, polls and emoji/stickers all target this room, same as a
  /// normal room's composer targets its one room.
  Room? get selectedRoom {
    final roomId = selectedRoomId;
    if (roomId == null) return null;
    return client.getRoomById(roomId);
  }

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

  bool showEmojiPicker = false;

  void emojiPickerAction() =>
      setState(() => showEmojiPicker = !showEmojiPicker);

  void hideEmojiPicker() => setState(() => showEmojiPicker = false);

  void onEmojiSelected(_, Emoji? emoji) {
    if (emoji == null) return;
    final text = sendController.text;
    final selection = sendController.selection;
    final newText = text.isEmpty
        ? emoji.emoji
        : text.replaceRange(selection.start, selection.end, emoji.emoji);
    sendController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.baseOffset + emoji.emoji.length,
      ),
    );
  }

  void emojiPickerBackspace() {
    sendController
      ..text = sendController.text.characters.skipLast(1).toString()
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: sendController.text.length),
      );
  }

  Future<void> sendFileAction({FileType type = FileType.any}) async {
    final room = selectedRoom;
    if (room == null) return;
    final files = await selectFiles(context, allowMultiple: true, type: type);
    if (files.isEmpty) return;
    if (!mounted) return;
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        outerContext: context,
        threadRootEventId: null,
        threadLastEventId: null,
      ),
    );
  }

  Future<void> openCameraAction() async {
    final room = selectedRoom;
    if (room == null) return;
    final file = await ImagePicker().pickImage(source: ImageSource.camera);
    if (file == null || !mounted) return;
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: [file],
        room: room,
        outerContext: context,
        threadRootEventId: null,
        threadLastEventId: null,
      ),
    );
  }

  Future<void> openVideoCameraAction() async {
    final room = selectedRoom;
    if (room == null) return;
    final file = await ImagePicker().pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 1),
    );
    if (file == null || !mounted) return;
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: [file],
        room: room,
        outerContext: context,
        threadRootEventId: null,
        threadLastEventId: null,
      ),
    );
  }

  Future<void> sendLocationAction() async {
    final room = selectedRoom;
    if (room == null) return;
    await showAdaptiveDialog(
      context: context,
      builder: (c) => SendLocationDialog(room: room),
    );
  }

  void onAddPopupMenuButtonSelected(AddPopupMenuActions choice) {
    switch (choice) {
      case AddPopupMenuActions.image:
        sendFileAction(type: FileType.image);
        return;
      case AddPopupMenuActions.video:
        sendFileAction(type: FileType.video);
        return;
      case AddPopupMenuActions.file:
        sendFileAction();
        return;
      case AddPopupMenuActions.poll:
        final room = selectedRoom;
        if (room == null) return;
        showAdaptiveBottomSheet(
          context: context,
          builder: (context) => StartPollBottomSheet(room: room),
        );
        return;
      case AddPopupMenuActions.photoCamera:
        openCameraAction();
        return;
      case AddPopupMenuActions.videoCamera:
        openVideoCameraAction();
        return;
      case AddPopupMenuActions.location:
        sendLocationAction();
        return;
    }
  }

  @override
  void dispose() {
    sendController.dispose();
    scrollController.dispose();
    inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UnifiedChatView(this);
}
