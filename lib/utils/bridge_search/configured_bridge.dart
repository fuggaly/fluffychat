/// Which bridgev2 provisioning capabilities a bridge type actually
/// implements - confirmed via research against the mautrix-go bridgev2
/// source (whatsapp/gmessages/slack connectors). These are inherent to the
/// bridge software, not user-configurable, unlike the label.
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

  /// Whether resolve_identifier/create_dm accepts a raw phone number as
  /// the identifier for this bridge (confirmed via each connector's own
  /// source - both parse a bare phone number directly when there's no
  /// existing ghost). Slack identifiers are workspace-specific user IDs,
  /// not phone numbers, so address-book phone matches don't apply there.
  bool get usesPhoneIdentifiers => switch (this) {
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

/// [id] must match a key in matrix-bridge-relay's own `bridges.json` on
/// the server - the app talks only to the relay, which knows each
/// bridge's actual base URL and handles auth as @bridgehub itself.
class ConfiguredBridge {
  final String id;
  final BridgeKind kind;
  final String label;

  const ConfiguredBridge({
    required this.id,
    required this.kind,
    required this.label,
  });

  factory ConfiguredBridge.fromJson(Map<String, Object?> json) =>
      ConfiguredBridge(
        id: json['id'] as String,
        kind: BridgeKind.values.byName(json['kind'] as String),
        label: json['label'] as String,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'label': label,
  };
}
