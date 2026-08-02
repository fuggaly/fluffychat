import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart' show AddPopupMenuActions;
import 'package:fluffychat/pages/chat/event_info_dialog.dart';
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
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

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
  // AutoScrollController (not plain ScrollController) so scrollToEventId
  // below can jump straight to a specific message, same mechanism a
  // normal room's chat_event_list.dart uses via AutoScrollTag.
  final AutoScrollController scrollController = AutoScrollController();
  late final FocusNode inputFocus;
  bool loading = true;
  String? selectedRoomId;
  bool _timelinesRequested = false;

  @override
  void initState() {
    super.initState();
    // Enter-to-send is implemented via a custom key handler on the
    // TextField's own FocusNode, not TextField.textInputAction (that only
    // affects mobile virtual keyboards) - a plain FocusNode() here meant
    // Enter always just inserted a newline regardless of the Send on
    // Enter setting. Mirrors ChatController's own _customEnterKeyHandling,
    // minus the arrow-up-to-edit-last-message and escape-to-cancel-edit
    // shortcuts, which depend on reply/edit state this composer doesn't
    // have.
    inputFocus = FocusNode(onKeyEvent: _customEnterKeyHandling);
  }

  KeyEventResult _customEnterKeyHandling(FocusNode node, KeyEvent evt) {
    if (!HardwareKeyboard.instance.isShiftPressed &&
        evt.logicalKey.keyLabel == 'Enter' &&
        AppSettings.sendOnEnter.value) {
      if (evt is KeyDownEvent) {
        send();
      }
      return KeyEventResult.handled;
    } else if (evt.logicalKey.keyLabel == 'Enter' && evt is KeyDownEvent) {
      final currentLineNum =
          sendController.text
              .substring(0, sendController.selection.baseOffset)
              .split('\n')
              .length -
          1;
      final currentLine = sendController.text.split('\n')[currentLineNum];

      for (final pattern in [
        '- [ ] ',
        '- [x] ',
        '* [ ] ',
        '* [x] ',
        '- ',
        '* ',
        '+ ',
      ]) {
        if (currentLine.startsWith(pattern)) {
          if (currentLine == pattern) {
            return KeyEventResult.ignored;
          }
          sendController.text += '\n$pattern';
          return KeyEventResult.handled;
        }
      }

      return KeyEventResult.ignored;
    } else {
      return KeyEventResult.ignored;
    }
  }

  Timer? _typingCoolDown;
  Timer? _typingTimeout;
  bool _currentlyTyping = false;

  /// Triggers a rebuild as the composer text changes (so the attach
  /// button's hide-while-typing animation - see UnifiedChatInputRow -
  /// reacts the same way ChatInputRow's does), and mirrors
  /// ChatController.onInputBarChanged's debounced room.setTyping() calls
  /// so the other party sees a typing indicator too, not just this app
  /// showing theirs.
  void onInputChanged() {
    setState(() {});
    final room = selectedRoom;
    if (room == null || !AppSettings.sendTypingNotifications.value) return;

    _typingCoolDown?.cancel();
    _typingCoolDown = Timer(const Duration(seconds: 2), () {
      _typingCoolDown = null;
      _currentlyTyping = false;
      room.setTyping(false);
    });
    _typingTimeout ??= Timer(const Duration(seconds: 30), () {
      _typingTimeout = null;
      _currentlyTyping = false;
    });
    if (!_currentlyTyping) {
      _currentlyTyping = true;
      room.setTyping(true, timeout: const Duration(seconds: 30).inMilliseconds);
    }
  }

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
      try {
        // A member room can revert to Membership.invite behind this
        // group's back - e.g. autobot's Room Evaluation evicting then
        // later re-inviting the human once a contact's availability
        // window reopens (see autobot.mjs) - and since member rooms are
        // deliberately hidden from the main room list in favour of this
        // merged view, there's no other UI path where the user would ever
        // see or accept that pending re-invite. An invited-but-not-joined
        // room has no accessible timeline at all (confirmed live - even
        // an explicit requestHistory() below comes back with zero
        // events), so silently accept it here, the same way a normal
        // room auto-joins on tap (see ChatListController.onChatTap) -
        // the user already consented to this room being part of the
        // conversation by keeping it in the group.
        if (room.membership == Membership.invite) {
          final waitForRoom = client.waitForRoomInSync(roomId, join: true);
          await room.join();
          await waitForRoom;
        }
        final timeline = await room.getTimeline(
          onUpdate: () {
            if (!mounted) return;
            setState(() {});
            _markRoomRead(roomId);
          },
        );
        // A member room is never opened directly (hidden from the room
        // list in favour of this merged view), so nothing else ever
        // triggers the usual scroll-driven history request a normal
        // ChatController relies on. If nothing's cached locally yet
        // (getTimeline() can legitimately come back empty), fetch some
        // history explicitly - otherwise _markRoomRead's own
        // events.isEmpty guard silently no-ops forever, since no live
        // event may ever arrive to retry it via onUpdate, leaving this
        // room's unread count stuck no matter how long the merged view
        // stays open.
        if (timeline.events.isEmpty) {
          await timeline.requestHistory();
        }
        timelines[roomId] = timeline;
      } catch (e, s) {
        // One member room failing to load its timeline (network hiccup,
        // a bridge-puppeted room rejecting something) shouldn't abort the
        // rest - each room here is independent, unlike a normal chat's
        // single timeline. Without this, every room after the failing one
        // in the group never gets a Timeline (or a read-marker call)
        // for the rest of this screen's life.
        Logs().w('UnifiedChat: failed to load timeline for $roomId', e, s);
      }
    }

    if (!mounted) return;
    setState(() => loading = false);
    // Opening this conversation is itself "reading" every member room, the
    // same way opening a normal room does - ChatController does this via
    // its own updateView()/setReadMarker() calls, but nothing analogous
    // existed here, so unread counts and read receipts on the underlying
    // bridge rooms never advanced no matter how long the merged view
    // stayed open.
    for (final roomId in timelines.keys) {
      _markRoomRead(roomId);
    }
    await _loadPendingScheduledMessages();
  }

  void _markRoomRead(String roomId) {
    final timeline = timelines[roomId];
    if (timeline == null || timeline.events.isEmpty) return;
    // ignore: unawaited_futures
    timeline
        .setReadMarker(public: AppSettings.sendPublicReadReceipts.value)
        .catchError(
          (e, s) => Logs().w('UnifiedChat: failed to mark $roomId read', e, s),
        );
  }

  List<ScheduledMessage> pendingScheduledMessages = [];

  /// Same idea as ChatController's own version, but a scheduled message
  /// could target any of this group's member rooms (not just whichever
  /// one is currently selected in the network dropdown), so this filters
  /// against the whole group instead of a single room id.
  Future<void> _loadPendingScheduledMessages() async {
    final currentGroup = group;
    if (currentGroup == null) return;
    if (!await SchedulerConfig.isConfigured()) return;
    try {
      final all = await SchedulerApiClient().listPending();
      if (!mounted) return;
      setState(() {
        pendingScheduledMessages =
            all.where((m) => currentGroup.roomIds.contains(m.roomId)).toList()
              ..sort((a, b) => a.sendAt.compareTo(b.sendAt));
      });
    } on SchedulerApiException {
      // Ignored - see ChatController's own version for rationale.
    }
  }

  Future<void> sendScheduledMessageNow(ScheduledMessage msg) async {
    final room = client.getRoomById(msg.roomId);
    if (room == null) return;
    try {
      await SchedulerApiClient().cancel(msg.id);
    } on SchedulerApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send now: ${e.message}')),
      );
      return;
    }
    // ignore: unawaited_futures
    room.sendTextEvent(msg.body);
    await _loadPendingScheduledMessages();
  }

  Future<void> editAndSendScheduledMessageNow(ScheduledMessage msg) async {
    final room = client.getRoomById(msg.roomId);
    if (room == null) return;
    final newBody = await showTextInputDialog(
      context: context,
      title: 'Edit message',
      initialText: msg.body,
      minLines: 1,
      maxLines: 8,
      okLabel: L10n.of(context).send,
      cancelLabel: L10n.of(context).cancel,
    );
    if (newBody == null || newBody.trim().isEmpty || !mounted) return;
    try {
      await SchedulerApiClient().cancel(msg.id);
    } on SchedulerApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send now: ${e.message}')),
      );
      return;
    }
    // ignore: unawaited_futures
    room.sendTextEvent(newBody);
    await _loadPendingScheduledMessages();
  }

  Future<void> cancelScheduledMessage(ScheduledMessage msg) async {
    final confirmed = await showOkCancelAlertDialog(
      context: context,
      title: 'Cancel scheduled message?',
      message: msg.body,
      okLabel: 'Cancel it',
      cancelLabel: 'Keep it',
      isDestructive: true,
    );
    if (confirmed != OkCancelResult.ok) return;
    try {
      await SchedulerApiClient().cancel(msg.id);
    } on SchedulerApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not cancel: ${e.message}')));
      return;
    }
    await _loadPendingScheduledMessages();
  }

  // --- Selection, reply, edit, mention, info, scroll-to-event ---
  //
  // Mirrors ChatController's own versions. Deliberately not implemented
  // here: forwarding a selected message to another room, "try again" for
  // a failed send, and Matrix threads - none of the bridges this app
  // talks to originate threaded messages (mautrix bridges don't create
  // m.thread relations from a WhatsApp/SMS/Slack reply), so a whole
  // secondary thread-pane view would have no real messages to ever show.

  final Set<Event> selectedEvents = {};

  bool get selectMode => selectedEvents.isNotEmpty;

  Event? replyEvent;
  Event? editEvent;
  String pendingText = '';
  String? scrollToEventIdMarker;

  void onSelectMessage(Event event) {
    if (event.redacted) return;
    setState(() {
      if (selectedEvents.contains(event)) {
        selectedEvents.remove(event);
      } else {
        selectedEvents.add(event);
      }
    });
  }

  void clearSelectedEvents() => setState(() {
    selectedEvents.clear();
    showEmojiPicker = false;
  });

  void clearSingleSelectedEvent() {
    if (selectedEvents.length <= 1) clearSelectedEvents();
  }

  void showEventInfo(Event event) => event.showInfoDialog(context);

  void replyAction({Event? replyTo}) {
    setState(() {
      replyEvent = replyTo ?? selectedEvents.first;
      // A reply's inReplyTo relation only makes sense sent through the
      // same room the original message is in - force the network
      // dropdown to match rather than risk sending it through whichever
      // other network happened to be selected.
      selectedRoomId = replyEvent!.room.id;
      selectedEvents.clear();
    });
    inputFocus.requestFocus();
  }

  void cancelReplyEventAction() => setState(() {
    if (editEvent != null) {
      sendController.text = pendingText;
      pendingText = '';
    }
    replyEvent = null;
    editEvent = null;
  });

  bool get canEditSelectedEvents {
    if (selectedEvents.length != 1 || !selectedEvents.first.status.isSent) {
      return false;
    }
    return selectedEvents.first.senderId == client.userID;
  }

  bool get canReplySelectedEvent =>
      selectedEvents.length == 1 && selectedEvents.first.status.isSent;

  void editSelectedEventAction() =>
      _startEditingEvent(selectedEvents.first, clearSelection: true);

  void _startEditingEvent(Event event, {bool clearSelection = false}) {
    final timeline = timelineForEvent(event);
    if (timeline == null) return;
    setState(() {
      pendingText = sendController.text;
      editEvent = event;
      // Same reasoning as replyAction - an edit must go out through the
      // room the original message actually lives in.
      selectedRoomId = event.room.id;
      sendController.text = event
          .getDisplayEvent(timeline)
          .calcLocalizedBodyFallback(
            MatrixLocals(L10n.of(context)),
            withSenderNamePrefix: false,
            hideReply: true,
          );
      if (clearSelection) selectedEvents.clear();
    });
    inputFocus.requestFocus();
  }

  void onMention(Event event) {
    sendController.text += '${event.senderFromMemoryOrFallback.mention} ';
  }

  /// Same idea as ChatController's own version, but there's no single
  /// timeline to fall back to loading more context from - a reply
  /// pointing at a message that isn't currently loaded in its own room's
  /// Timeline just can't be jumped to here (a normal room can fetch
  /// context around an arbitrary event id; this view only ever holds
  /// whatever's already paged into each member room's Timeline).
  Future<void> scrollToEventId(
    String eventId, {
    bool highlightEvent = true,
  }) async {
    final events = mergedEvents;
    final index = events.indexWhere((e) => e.eventId == eventId);
    if (index == -1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'That message is further back than what\'s currently loaded - scroll up to load more history first.',
          ),
        ),
      );
      return;
    }
    if (highlightEvent) setState(() => scrollToEventIdMarker = eventId);
    // No +1 offset here unlike ChatController's own version - that one
    // accounts for chat_event_list.dart's footer sitting at item index 0;
    // this view's "load more" footer sits at the far end of the index
    // range instead (index == events.length), so a merged event's index
    // maps directly onto its ListView item index.
    await scrollController.scrollToIndex(
      index,
      duration: FluffyThemes.animationDuration,
      preferPosition: AutoScrollPosition.middle,
    );
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
    final reply = replyEvent;
    final edit = editEvent;

    // ignore: unawaited_futures
    room.sendTextEvent(body, inReplyTo: reply, editEventId: edit?.eventId);
    setState(() {
      sendController.text = pendingText;
      pendingText = '';
      replyEvent = null;
      editEvent = null;
    });
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
    await _loadPendingScheduledMessages();
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
    // Not explicitly clearing typing state here (unlike ChatController,
    // which can since it keeps its own client/room references as plain
    // fields) - selectedRoom depends on Matrix.of(context), which isn't
    // safe to call during dispose. The 30s server-side timeout passed to
    // setTyping above already bounds how long a stale indicator can show.
    _typingCoolDown?.cancel();
    _typingTimeout?.cancel();
    sendController.dispose();
    scrollController.dispose();
    inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UnifiedChatView(this);
}
