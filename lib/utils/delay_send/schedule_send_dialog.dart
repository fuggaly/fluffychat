import 'package:flutter/material.dart';

/// Shows a date then time picker, returns the combined DateTime, or null
/// if the user cancelled at any point or picked a time in the past.
Future<DateTime?> showScheduleSendDialog(BuildContext context) async {
  final now = DateTime.now();

  final date = await showDatePicker(
    context: context,
    initialDate: now,
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
    helpText: 'Schedule send',
  );
  if (date == null || !context.mounted) return null;

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 5))),
    helpText: 'Schedule send time',
  );
  if (time == null) return null;

  final combined = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );

  if (combined.isBefore(DateTime.now())) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That time has already passed.')),
      );
    }
    return null;
  }

  return combined;
}
