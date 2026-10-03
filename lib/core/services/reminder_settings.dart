import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings → Reminders: how long before a time Echo suggests reminding,
/// and whether it suggests reminders at all.
class ReminderSettings {
  ReminderSettings._();

  static const leads = [
    Duration(minutes: 10),
    Duration(minutes: 20),
    Duration(minutes: 30),
    Duration(hours: 1),
  ];

  static final lead = ValueNotifier<Duration>(const Duration(minutes: 20));
  static final suggest = ValueNotifier<bool>(true);

  static const _leadKey = 'reminder_lead_minutes';
  static const _suggestKey = 'reminder_suggestions';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    lead.value = Duration(minutes: prefs.getInt(_leadKey) ?? 20);
    suggest.value = prefs.getBool(_suggestKey) ?? true;
  }

  static Future<void> setLead(Duration d) async {
    lead.value = d;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_leadKey, d.inMinutes);
  }

  static Future<void> setSuggest(bool on) async {
    suggest.value = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_suggestKey, on);
  }

  /// "20 minutes", "1 hour".
  static String label(Duration d) => d.inMinutes % 60 == 0
      ? '${d.inHours} hour${d.inHours == 1 ? '' : 's'}'
      : '${d.inMinutes} minutes';
}
