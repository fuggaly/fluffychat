# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal fork of [FluffyChat](https://github.com/krille-chan/fluffychat)
(`upstream` remote) for a single self-hosted Matrix homeserver
(`matrix.fuggaly.com` - see `~/dev/CLAUDE.md` for the server-deployment
conventions shared across this user's projects). `origin` points at
`fuggaly/fluffychat` on GitHub, worked on via the `custom` branch.

On top of upstream FluffyChat, this fork adds three custom features, each
backed by a small dedicated Node service deployed alongside the homeserver
(not part of this repo):

- **Delay Send** - schedule a message to send later; a ghost bubble shows
  above the composer until it fires.
- **Bridge Unification** - merge a contact's separate bridged rooms (e.g.
  WhatsApp + SMS) into one conversation view.
- **Cross-Bridge Contact Search** - search the real address book (not each
  bridge's own, frequently incomplete, contact list) when starting a new
  chat.

## Commands

- Analyze: `dart analyze`
- Format: `dart format lib/`
- Build Linux: `flutter build linux --release` (needs Rust installed
  first - `flutter_vodozemac`'s native build uses cargokit)
- Build Android: `flutter build apk --release`
- Run: `flutter run`
- Integration tests: `./scripts/prepare_integration_test.sh` then
  `flutter test integration_test/mobile_test.dart` (needs Docker)

`fvm` manages the Flutter SDK version for this project - if `flutter`/
`dart` aren't on `PATH` in a fresh shell, it's exported from
`$HOME/fvm/default/bin` in `~/.zshrc`, not a global install.

## Manual testing

`MANUAL_TESTING.md` (repo root, gitignored/untracked - a personal working
checklist, not part of the repo history) tracks what's actually been
verified for each custom feature and what's still outstanding. Check it
before assuming something works, or is untested, or was already fixed.

## Architecture: the three custom features

### Delay Send (`lib/utils/delay_send/`)

- `scheduler_config.dart` - `SchedulerConfig`: base URL (`SharedPreferences`)
  + bearer token (`FlutterSecureStorage`) for the external scheduler
  service.
- `scheduler_api_client.dart` - `SchedulerApiClient`/`SchedulerApiException`,
  talks to the sibling `matrix-send-scheduler` repo (deployed at
  `https://matrix.fuggaly.com/scheduler`).
- `schedule_send_dialog.dart` - the send-time picker dialog.
- `lib/pages/settings_delay_send/` - settings screen to configure URL/token.
- Pending scheduled messages render as faded ghost bubbles above the
  composer in both a normal room (`ChatController`) and a merged
  conversation (`UnifiedChatController`) - in the merged case, each ghost
  resolves back to its own correct underlying room rather than whichever
  network happens to be selected in the dropdown.

### Bridge Unification (`lib/utils/bridge_unification/`, `lib/pages/unified_chat/`)

- `unified_contact_group.dart` - `UnifiedContactGroup` model (id, label,
  roomIds, roomLabels, lastUsedRoomId).
- `unified_contacts_service.dart` - `UnifiedContactsService`. Groups are
  stored in the user's own Matrix account_data, so they sync across
  devices/clients for free - no separate backend needed for group
  membership itself (only for auto-suggesting new groups, see below).
  Key methods: `createGroup`/`deleteGroup`/`groupForRoom`/`groupById`/
  `getGroups`/`isMuted`/`toggleMuted`/`setLastUsedRoom`/
  `removeRoomFromItsGroup`.
- `bridge_label.dart` - `bridgeLabelForRoom`/`effectiveRoomLabel`/
  `stripViaSuffix`/`iconForBridgeLabel`/`colorForBridgeLabel`.
  **Gotcha**: mautrix bridges set a room's `m.bridge` state event with a
  non-empty, bridge-specific `state_key` (e.g.
  `matrix.fuggaly.com/whatsapp`), not the default empty string -
  `room.getState('m.bridge')` (which defaults to state_key `''`) always
  misses it silently. Use `room.states['m.bridge']?.values.firstOrNull`
  instead (a portal room only ever has one bridge, so taking whichever
  state_key is present is safe).
- `known_bridge_bots.dart` - hardcoded bridge bot/relay-ghost mxids to
  exclude when picking "the other party" in a room. Mirrors a similar
  exclusion list kept server-side in the `autobot`/`contacts-sync`
  projects - maintained manually in both places, not shared code.
- `unified_contact_actions.dart` - the mute/un-merge action sheet
  (long-press a unified conversation's tile, or the in-chat app bar menu).
  Deliberately called "un-merge," not "leave" - it only dissolves the
  group, never touches the underlying rooms' membership.
- `lib/pages/unified_chat/` - the merged conversation view itself
  (`UnifiedChatController`/`UnifiedChatView`). Composes one `Timeline` per
  member room and merges events by timestamp, rather than being a from
  -scratch chat view - reuses the real `Message` widget so styling/behavior
  matches a normal room exactly. Message actions (react/reply/edit/mention/
  scroll-to-event) resolve back to the event's *own* underlying
  room/timeline, not whichever network happens to be selected in the
  composer's dropdown at the time.
  - Route registered in `lib/config/routes.dart` under
    `/rooms/unified/:groupid` - **must** pass an explicit
    `key: ValueKey('unified_chat_$groupId')` on the `UnifiedChat` widget.
    go_router's own `pageKey` is derived from the route's path *pattern*,
    not the resolved `groupid`, so without this, switching between two
    different unified conversations reuses the same `State` object (stale
    `timelines`/`selectedRoomId`) while only the app bar re-renders
    correctly from the new `widget.groupId` - same bug class `ChatPage`
    already guards against via its own
    `Key('chat_page_${roomId}_$eventId')`.
  - The message list must stay wrapped in `SelectionArea` (matching
    `chat_event_list.dart`'s normal-room equivalent), or message text
    renders fine but can't be selected/copied at all - `SelectionArea` is
    what makes the plain `Text` widgets underneath selectable; it's not
    something each message opts into itself.
- **Auto-suggested groupings** are computed server-side, not on-device:
  `matrix-bridge-relay`'s `GET /suggested_groupings`, called via
  `BridgeProvisioningClient.suggestedGroupings()` (lives under
  `bridge_search/`, not `bridge_unification/`, since it reuses the same
  relay client/auth as Cross-Bridge Contact Search below). "Calculate
  once, read many" - every device just reads the cached result; the only
  work done on-device is filtering to rooms this device actually has
  joined and isn't already grouped (`lib/pages/settings_unified_contacts/`).
  An earlier client-side heuristic approach (phone-number/same-display-name
  matching) was tried first and deliberately abandoned - unreliable,
  especially for bridges (like Google Messages) whose ghost mxids don't
  embed a phone number the way WhatsApp's do.

### Cross-Bridge Contact Search (`lib/utils/bridge_search/`, `lib/pages/bridge_search/`)

- `bridge_relay_config.dart` - `BridgeRelayConfig`: base URL + bearer token
  for `matrix-bridge-relay` (base URL is `https://matrix.fuggaly.com/bridge-relay`
  - note the hyphen; HAProxy routes on the exact prefix, not an
  underscore).
- `bridge_provisioning_client.dart` - `BridgeProvisioningClient`, wraps the
  relay's HTTP API: `searchAddressBook`, `contacts`, `searchUsers`,
  `resolveIdentifier`, `createDm`, `syncContacts`, `suggestedGroupings`.
- `configured_bridge.dart` - `BridgeKind` enum (whatsapp/googleMessages/
  slack/generic): which bridgev2 provisioning capabilities a bridge type
  actually implements, confirmed against the real mautrix-go bridge
  source - inherent to the bridge software, not user-configurable.
- `address_book_contact.dart` - model for a contact result from the
  relay's own compiled address book (sourced from the sibling
  `contacts-sync` project), independent of any one bridge's own
  (frequently incomplete) contact list.
- `lib/pages/settings_bridge_relay/` - settings screen to configure the
  relay URL/token.
- The relay holds `@bridgehub`'s Matrix access token server-side, never
  exposed to this app - a completely separate trust boundary from the
  app user's own session, since bridge sessions live under `@bridgehub`,
  not the app user's own account. See the sibling `matrix-bridge-relay`
  repo's own docs for the full rationale.

## Known gotchas

- **No in-app way to view your own Matrix access token** (unlike Element
  Web's Settings > Help & About > Access Token) - true of upstream
  FluffyChat too, not something this fork removed. Get one via a fresh
  `POST /_matrix/client/v3/login` if a one-off API call needs it.
- **`client.startDirectChat(mxid)` auto-decides encryption** based on
  whether the *target account* has already published E2EE device keys -
  there's no toggle in this app's new-chat flow to override that. If a
  service/bot account already has keys published (e.g. from an earlier
  interactive login), every new DM with it will silently be encrypted,
  with no in-app way to opt out - and encryption can never be turned back
  off once set (a Matrix protocol property, not a client limitation). If
  you need an unencrypted room with such an account, it has to be created
  via a raw `POST /createRoom` call with no `m.room.encryption` initial
  state, not through this app's UI.

## External services this fork depends on

All deployed to `server.fuggaly.com` per `~/dev/CLAUDE.md`'s conventions -
see each project's own `CLAUDE.md` for details:

- **`matrix-send-scheduler`** - Delay Send's backend.
- **`matrix-bridge-relay`** - Cross-Bridge Contact Search's backend, and
  Bridge Unification's auto-suggest backend; holds `@bridgehub`'s access
  token server-side.
- **`autobot`** - a separate, independent service (never called by this
  app directly) that manages when the account owner gets invited into
  newly-bridged conversations based on per-contact availability rules,
  automatically evicts him from rooms once that access lapses, and
  handles a "check" DM command for retrieving recent messages while away
  from normal devices. Mentioned here only because it shares the same
  `@bridgehub` identity and homeserver - see `~/dev/autobot/CLAUDE.md`.
