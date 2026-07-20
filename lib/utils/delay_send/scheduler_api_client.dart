import 'dart:convert';

import 'package:http/http.dart' as http;

import 'scheduler_config.dart';

class ScheduledMessage {
  final String id;
  final String roomId;
  final String body;
  final DateTime sendAt;
  final String status;
  final int attempts;

  ScheduledMessage({
    required this.id,
    required this.roomId,
    required this.body,
    required this.sendAt,
    required this.status,
    required this.attempts,
  });

  factory ScheduledMessage.fromJson(Map<String, dynamic> json) =>
      ScheduledMessage(
        id: json['id'] as String,
        roomId: json['room_id'] as String,
        body: json['body'] as String,
        sendAt: DateTime.fromMillisecondsSinceEpoch(json['send_at'] as int),
        status: json['status'] as String,
        attempts: json['attempts'] as int,
      );
}

/// Thrown when the scheduler service rejects a request, or isn't reachable.
class SchedulerApiException implements Exception {
  final String message;
  final int? statusCode;

  SchedulerApiException(this.message, {this.statusCode});

  @override
  String toString() => 'SchedulerApiException: $message';
}

/// Thin client for matrix-send-scheduler's HTTP API. Not configured (base
/// URL / bearer token missing) throws SchedulerApiException immediately -
/// callers should check SchedulerConfig.isConfigured() first to show a
/// proper "not set up yet" state instead of a generic error.
class SchedulerApiClient {
  Future<Map<String, String>> _authHeaders() async {
    final token = await SchedulerConfig.getBearerToken();
    if (token == null || token.isEmpty) {
      throw SchedulerApiException(
        'Delay Send is not configured yet (missing scheduler token).',
      );
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<Uri> _uri(String path) async {
    final baseUrl = await SchedulerConfig.getBaseUrl();
    if (baseUrl == null || baseUrl.isEmpty) {
      throw SchedulerApiException(
        'Delay Send is not configured yet (missing scheduler URL).',
      );
    }
    return Uri.parse('$baseUrl$path');
  }

  Future<ScheduledMessage> create({
    required String roomId,
    required String body,
    required DateTime sendAt,
  }) async {
    final res = await http.post(
      await _uri('/scheduled'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'roomId': roomId,
        'body': body,
        'sendAt': sendAt.millisecondsSinceEpoch,
      }),
    );
    if (res.statusCode != 201) {
      throw SchedulerApiException(
        _errorMessage(res),
        statusCode: res.statusCode,
      );
    }
    return ScheduledMessage.fromJson(jsonDecode(res.body));
  }

  Future<List<ScheduledMessage>> listPending() async {
    final res = await http.get(
      await _uri('/scheduled'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) {
      throw SchedulerApiException(
        _errorMessage(res),
        statusCode: res.statusCode,
      );
    }
    final list = jsonDecode(res.body) as List;
    return list
        .map((e) => ScheduledMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ScheduledMessage> update(
    String id, {
    DateTime? sendAt,
    String? body,
  }) async {
    final res = await http.patch(
      await _uri('/scheduled/$id'),
      headers: await _authHeaders(),
      body: jsonEncode({
        if (sendAt != null) 'sendAt': sendAt.millisecondsSinceEpoch,
        if (body != null) 'body': body,
      }),
    );
    if (res.statusCode != 200) {
      throw SchedulerApiException(
        _errorMessage(res),
        statusCode: res.statusCode,
      );
    }
    return ScheduledMessage.fromJson(jsonDecode(res.body));
  }

  Future<void> cancel(String id) async {
    final res = await http.delete(
      await _uri('/scheduled/$id'),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) {
      throw SchedulerApiException(
        _errorMessage(res),
        statusCode: res.statusCode,
      );
    }
  }

  String _errorMessage(http.Response res) {
    try {
      final json = jsonDecode(res.body);
      return (json['error'] as String?) ?? 'Unexpected error (${res.statusCode})';
    } catch (_) {
      return 'Unexpected error (${res.statusCode})';
    }
  }
}
