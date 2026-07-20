import 'package:fluffychat/utils/bridge_search/bridge_relay_config.dart';
import 'package:flutter/material.dart';

class SettingsBridgeRelay extends StatefulWidget {
  const SettingsBridgeRelay({super.key});

  @override
  State<SettingsBridgeRelay> createState() => _SettingsBridgeRelayState();
}

class _SettingsBridgeRelayState extends State<SettingsBridgeRelay> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final url = await BridgeRelayConfig.getBaseUrl();
    final token = await BridgeRelayConfig.getBearerToken();
    if (!mounted) return;
    setState(() {
      _urlController.text = url ?? '';
      _tokenController.text = token ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    await BridgeRelayConfig.setBaseUrl(_urlController.text.trim());
    await BridgeRelayConfig.setBearerToken(_tokenController.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved.')),
    );
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
      appBar: AppBar(title: const Text('Bridge Search')),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Cross-bridge contact search is relayed through '
                  'matrix-bridge-relay (WhatsApp/Google Messages sessions '
                  'on this homeserver run under @bridgehub, not your own '
                  'account, so the app can\'t talk to the bridges directly).',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Relay URL',
                    hintText: 'https://matrix.fuggaly.com/bridge-relay',
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
              ],
            ),
    );
  }
}
