import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/echo_segmented.dart';
import 'package:project_echo/core/services/gemini_usage.dart' show grouped;
import 'package:project_echo/core/services/retention_settings.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/settings/presentation/widgets/settings_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How long notifications are kept: 1, 3 or 7 days, whether dismissed ones
/// stay, and clearing what's here.
class HistorySettingsCard extends StatefulWidget {
  const HistorySettingsCard({super.key});

  @override
  State<HistorySettingsCard> createState() => _HistorySettingsCardState();
}

class _HistorySettingsCardState extends State<HistorySettingsCard> {
  static const _options = [1, 3, 7];

  int _days = 7;
  bool _keepSwiped = true;
  int? _count;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final days = await RetentionSettings.days();
    final keepSwiped = await RetentionSettings.keepSwiped();
    // Without the database the row just doesn't say a number.
    int? count;
    try {
      final isar = await IsarDataSource.instance;
      count = await isar.rawDatas.count();
    } catch (e) {
      debugPrint('Couldn\'t count history: $e');
    }
    if (!mounted) return;
    setState(() {
      _days = days;
      _keepSwiped = keepSwiped;
      _count = count;
    });
  }

  String _label(int days) => days == 1 ? '1 day' : '$days days';

  Future<void> _setDays(int days) async {
    if (days == _days) return;
    // Shortening deletes messages at once, so it asks first.
    if (days < _days) {
      final ok = await confirmSettingsAction(
        context,
        title: 'Keep history for ${_label(days)}?',
        body:
            'Notifications older than ${_label(days)} will be deleted from '
            'this phone now. Your to-dos and people stay.',
        confirm: 'Delete older',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _days = days);
    await RetentionSettings.setDays(days);
    await IsarDataSource.deleteOldNotifications();
    await _load();
    if (mounted) settingsToast(context, 'History is kept for ${_label(days)}');
  }

  Future<void> _setKeepSwiped(bool on) async {
    setState(() => _keepSwiped = on);
    await RetentionSettings.setKeepSwiped(on);
    if (!mounted) return;
    settingsToast(
      context,
      on
          ? 'Echo keeps what you swipe away'
          : 'Swiped-away notifications won’t be kept',
    );
  }

  Future<void> _clear() async {
    final count = _count ?? 0;
    final ok = await confirmSettingsAction(
      context,
      title: 'Clear all history?',
      body:
          'This deletes the ${grouped(count)} '
          '${count == 1 ? 'notification' : 'notifications'} Echo has kept on '
          'this phone. Your to-dos, people and settings stay. It can’t be '
          'undone.',
      confirm: 'Clear',
    );
    if (!ok) return;
    final isar = await IsarDataSource.instance;
    await isar.writeTxn(() => isar.rawDatas.clear());
    // The owner's own last lines in each chat are history too.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(ChatContextStore.turnsKey);
    await _load();
    if (mounted) settingsToast(context, 'History cleared');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = _count;
    return SettingsGroup(
      rows: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Keep history for',
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Older notifications are deleted from this phone. To-dos and '
                'people stay.',
                style: GoogleFonts.nunito(
                  fontSize: 12.5,
                  height: 1.4,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              EchoSegmented(
                labels: [for (final d in _options) _label(d)],
                selected: _options.indexOf(_days).clamp(0, _options.length - 1),
                onSelect: (i) => _setDays(_options[i]),
              ),
            ],
          ),
        ),
        SettingsSwitchRow(
          icon: Symbols.swipe_left_rounded,
          title: 'Keep what you swipe away',
          value: 'Find a notification you dismissed by accident',
          on: _keepSwiped,
          onChanged: _setKeepSwiped,
        ),
        SettingsRow(
          icon: Symbols.delete_sweep_rounded,
          title: 'Clear history',
          value: count == null
              ? null
              : count == 0
              ? 'Nothing kept yet'
              : '${grouped(count)} '
                    '${count == 1 ? 'notification' : 'notifications'} on this '
                    'phone',
          danger: true,
          hideChevron: true,
          onTap: count == null || count == 0 ? null : _clear,
        ),
      ],
    );
  }
}
