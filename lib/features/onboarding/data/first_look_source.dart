import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/services/notification_ingest.dart';
import 'package:project_echo/features/onboarding/data/first_look.dart';
import 'package:project_echo/features/vault/data/app_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gathers what the first look is read from, on the phone, the moment
/// notification access is granted.
///
/// The listener reads the shade when Android connects it, a moment after
/// access is turned on: chats, and the first time only, everything else
/// there (see EchoNotificationListenerService.takeFirstLook). That arrives
/// through the native buffer, so this drains it until nothing more comes
/// (or a few seconds pass), and brings in today's and tomorrow's calendar,
/// which the app couldn't read at startup, before access was given.
class FirstLookSource {
  FirstLookSource._();

  /// Longest the owner waits for the shade to be caught up.
  static const _patience = Duration(seconds: 4);

  static Future<FirstLook> load() async {
    final started = DateTime.now();
    try {
      await NotificationIngest.syncCalendar();
      final isar = await IsarDataSource.instance;
      var last = -1;
      while (true) {
        await NotificationIngest.drainBuffer();
        final count = await isar.rawDatas.count();
        if (count == last || DateTime.now().difference(started) > _patience) {
          break;
        }
        last = count;
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    } catch (e) {
      // Whatever was saved still makes a first look.
      debugPrint('First look: catching up failed (${e.runtimeType})');
    }

    final prefs = await SharedPreferences.getInstance();
    final times = prefs.getStringList('briefing_times');
    List<RawData> entries;
    try {
      entries = await IsarDataSource.getAllEntries();
    } catch (_) {
      entries = const [];
    }
    return buildFirstLook(
      entries: entries,
      now: DateTime.now(),
      name: prefs.getString('user_name'),
      myTurns: await ChatContextStore.loadMyTurns(),
      aliases: Map<String, String>.from(
        jsonDecode(prefs.getString('vault_category_aliases') ?? '{}'),
      ),
      excluded: await loadExcludedSources(),
      briefingTime: times == null || times.isEmpty ? '07:00' : times.first,
    );
  }
}
