/// Which bridgev2 provisioning capabilities a bridge type actually
/// implements - confirmed via research against the mautrix-go bridgev2
/// source (whatsapp/gmessages/slack connectors). These are inherent to the
/// bridge software, not user-configurable, unlike the label/base URL.
enum BridgeKind { whatsapp, googleMessages, slack, generic }

extension BridgeKindCapabilities on BridgeKind {
  bool get supportsSearchUsers => switch (this) {
    BridgeKind.whatsapp => true,
    BridgeKind.slack => true,
    BridgeKind.googleMessages => false,
    BridgeKind.generic => false,
  };

  bool get supportsContactsList => switch (this) {
    BridgeKind.whatsapp => true,
    BridgeKind.googleMessages => true,
    BridgeKind.slack => false,
    BridgeKind.generic => false,
  };

  String get displayName => switch (this) {
    BridgeKind.whatsapp => 'WhatsApp',
    BridgeKind.googleMessages => 'Google Messages',
    BridgeKind.slack => 'Slack',
    BridgeKind.generic => 'Bridge',
  };
}

class ConfiguredBridge {
  final String id;
  final BridgeKind kind;
  final String label;
  final String baseUrl;

  const ConfiguredBridge({
    required this.id,
    required this.kind,
    required this.label,
    required this.baseUrl,
  });

  factory ConfiguredBridge.fromJson(Map<String, Object?> json) =>
      ConfiguredBridge(
        id: json['id'] as String,
        kind: BridgeKind.values.byName(json['kind'] as String),
        label: json['label'] as String,
        baseUrl: json['baseUrl'] as String,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'label': label,
    'baseUrl': baseUrl,
  };
}
