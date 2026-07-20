class UnifiedContactGroup {
  final String id;
  final String label;
  final List<String> roomIds;
  final Map<String, String> roomLabels;
  final String? lastUsedRoomId;

  const UnifiedContactGroup({
    required this.id,
    required this.label,
    required this.roomIds,
    required this.roomLabels,
    this.lastUsedRoomId,
  });

  factory UnifiedContactGroup.fromJson(Map<String, Object?> json) =>
      UnifiedContactGroup(
        id: json['id'] as String,
        label: json['label'] as String,
        roomIds: (json['roomIds'] as List).cast<String>(),
        roomLabels: (json['roomLabels'] as Map?)?.cast<String, String>() ?? {},
        lastUsedRoomId: json['lastUsedRoomId'] as String?,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'roomIds': roomIds,
    'roomLabels': roomLabels,
    if (lastUsedRoomId != null) 'lastUsedRoomId': lastUsedRoomId,
  };

  UnifiedContactGroup copyWith({
    String? label,
    List<String>? roomIds,
    Map<String, String>? roomLabels,
    String? lastUsedRoomId,
  }) => UnifiedContactGroup(
    id: id,
    label: label ?? this.label,
    roomIds: roomIds ?? this.roomIds,
    roomLabels: roomLabels ?? this.roomLabels,
    lastUsedRoomId: lastUsedRoomId ?? this.lastUsedRoomId,
  );

  /// The room to default the send-network dropdown to: last used, or
  /// just the first member room if nothing has been sent yet.
  String get defaultRoomId => lastUsedRoomId ?? roomIds.first;
}
