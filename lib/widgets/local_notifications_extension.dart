// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/bridge_unification/unified_contacts_service.dart';
import 'package:fluffychat/utils/client_download_content_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/push_helper.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

extension LocalNotificationsExtension on MatrixState {
  static final html.AudioElement _audioPlayer = html.AudioElement()
    ..src = 'assets/assets/sounds/notification.ogg'
    ..load();

  Future<void> showLocalNotification(Event event) async {
    final l10n = L10n.of(context);
    final roomId = event.room.id;
    if (activeRoomIds?.contains(roomId) == true) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        return;
      }
    }

    // See push_helper.dart's own version of this for the full rationale:
    // a merged conversation is several independent Matrix rooms as far as
    // notifications are concerned, so without this a unified contact could
    // notify separately under each underlying room's own "Contact via
    // WhatsApp"/"Contact via SMS" name instead of once under their plain
    // name.
    final unifiedGroup = UnifiedContactsService.groupForRoom(client, roomId);

    final title =
        unifiedGroup?.label ??
        event.room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final body = await event.calcLocalizedBody(
      MatrixLocals(L10n.of(context)),
      withSenderNamePrefix:
          !event.room.isDirectChat ||
          event.room.lastEvent?.senderId == client.userID,
      plaintextBody: true,
      hideReply: true,
      hideEdit: true,
      removeMarkdown: true,
    );
    final avatarUrl =
        event.room.avatar ??
        unifiedGroup?.roomIds
            .map((id) => client.getRoomById(id)?.avatar)
            .whereType<Uri>()
            .firstOrNull;

    const size = 128;
    const thumbnailMethod = ThumbnailMethod.crop;

    if (avatarUrl != null) {
      // Pre-cache so that we can later just set the thumbnail uri as icon:
      try {
        await client.downloadMxcCached(
          avatarUrl,
          width: size,
          height: size,
          thumbnailMethod: thumbnailMethod,
          isThumbnail: true,
          rounded: true,
        );
      } catch (e, s) {
        Logs().d('Unable to pre-download avatar for web notification', e, s);
      }
    }

    if (kIsWeb) {
      final thumbnailUri = await avatarUrl?.getThumbnailUri(
        client,
        width: size,
        height: size,
        method: thumbnailMethod,
      );

      if (AppSettings.webNotificationSound.value) _audioPlayer.play();

      html.Notification(
        title,
        body: body,
        icon: thumbnailUri?.toString(),
        tag: unifiedGroup?.id ?? event.room.id,
      );
      return;
    }

    FlutterLocalNotificationsPlugin().show(
      id: (unifiedGroup?.id ?? event.room.id).hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        linux: LinuxNotificationDetails(
          sound: ThemeLinuxSound('message-new-instant'),
          actions: [
            LinuxNotificationAction(
              key: FluffyChatNotificationActions.markAsRead.name,
              label: l10n.markAsRead,
            ),
            LinuxNotificationAction(
              key: FluffyChatNotificationActions.mute.name,
              label: l10n.mute,
            ),
          ],
        ),
      ),
      payload: FluffyChatPushPayload(
        client.clientName,
        event.room.id,
        event.eventId,
      ).toString(),
    );
  }
}
