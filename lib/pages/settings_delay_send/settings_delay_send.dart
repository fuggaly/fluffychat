import 'package:fluffychat/utils/delay_send/schedule_send_dialog.dart';
import 'package:fluffychat/utils/delay_send/scheduler_api_client.dart';
import 'package:fluffychat/utils/delay_send/scheduler_config.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';

class SettingsDelaySend extends StatefulWidget {
  const SettingsDelaySend({super.key});

  @override
  State<SettingsDelaySend> createState() => _SettingsDelaySendState();
}

class _SettingsDelaySendState extends State<SettingsDelaySend> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _loading = true;
  bool _loadingPending = false;
  List<ScheduledMessage>? _pending;
  String? _pendingError;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final url = await SchedulerConfig.getBaseUrl();
    final token = await SchedulerConfig.getBearerToken();
    if (!mounted) return;
    setState(() {
      _urlController.text = url ?? '';
      _tokenController.text = token ?? '';
      _loading = false;
    });
    if (url != null && url.isNotEmpty && token != null && token.isNotEmpty) {
      await _loadPending();
    }
  }

  Future<void> _save() async {
    await SchedulerConfig.setBaseUrl(_urlController.text.trim());
    await SchedulerConfig.setBearerToken(_tokenController.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved.')),
    );
  }

  Future<void> _loadPending() async {
    setState(() {
      _loadingPending = true;
      _pendingError = null;
    });
    try {
      final pending = await SchedulerApiClient().listPending();
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _loadingPending = false;
      });
    } on SchedulerApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingError = e.message;
        _loadingPending = false;
      });
    }
  }

  Future<void> _cancelMessage(ScheduledMessage msg) async {
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
      await _loadPending();
    } on SchedulerApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel: ${e.message}')),
      );
    }
  }

  Future<void> _editMessage(ScheduledMessage msg) async {
    final newTime = await showScheduleSendDialog(context);
    if (newTime == null) return;
    try {
      await SchedulerApiClient().update(msg.id, sendAt: newTime);
      await _loadPending();
    } on SchedulerApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reschedule: ${e.message}')),
      );
    }
  }

  String _roomName(BuildContext context, String roomId) {
    final room = Matrix.of(context).client.getRoomById(roomId);
    return room?.getLocalizedDisplayname() ?? roomId;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delay Send')),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Configuration',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Scheduler URL',
                    hintText: 'https://matrix.fuggaly.com/scheduler',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tokenController,
                  decoration: const InputDecoration(labelText: 'Bearer token'),
                  obscureText: true,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ),
                const Divider(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Pending scheduled messages',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_outlined),
                      onPressed: _loadingPending ? null : _loadPending,
                    ),
                  ],
                ),
                if (_loadingPending)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  )
                else if (_pendingError != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Could not load: $_pendingError',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  )
                else if (_pending == null)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Tap refresh to load pending messages.'),
                  )
                else if (_pending!.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nothing scheduled.'),
                  )
                else
                  ..._pending!.map(
                    (msg) => Card(
                      child: ListTile(
                        title: Text(msg.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${_roomName(context, msg.roomId)} • ${msg.sendAt}'
                          '${msg.attempts > 0 ? ' • retrying (attempt ${msg.attempts})' : ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Reschedule',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: msg.attempts > 0
                                  ? null
                                  : () => _editMessage(msg),
                            ),
                            IconButton(
                              tooltip: 'Cancel',
                              icon: const Icon(Icons.close_outlined),
                              onPressed: msg.attempts > 0
                                  ? null
                                  : () => _cancelMessage(msg),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
