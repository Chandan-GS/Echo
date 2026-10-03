import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/desktop/data/desktop_actions.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A reminder coming due while the computer is open: it slides in at the
/// top right with what it's about, and Open, Snooze 10 min, or Done. The
/// phone rings it too; this is so the owner sees it where they're working.
class ReminderBanner extends StatefulWidget {
  /// Shows the to-do list.
  final VoidCallback onOpen;
  const ReminderBanner({super.key, required this.onOpen});

  @override
  State<ReminderBanner> createState() => _ReminderBannerState();
}

class _Due {
  final String key;
  final String title;
  final String body;
  final int? todoId;
  final String? thread;
  const _Due(this.key, this.title, this.body, this.todoId, this.thread);
}

class _ReminderBannerState extends State<ReminderBanner> {
  _Due? _due;
  Timer? _check;
  Timer? _hide;

  /// Reminders already shown, so one shows once.
  final Set<String> _shown = {};

  @override
  void initState() {
    super.initState();
    _check = Timer.periodic(const Duration(seconds: 20), (_) => _look());
    Reminders.changed.addListener(_look);
    _look();
  }

  @override
  void dispose() {
    _check?.cancel();
    _hide?.cancel();
    Reminders.changed.removeListener(_look);
    super.dispose();
  }

  /// Anything that came due in the last two minutes and hasn't shown.
  Future<void> _look() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    Map store;
    try {
      store = jsonDecode(prefs.getString(Reminders.storeKey) ?? '{}') as Map;
    } catch (_) {
      return;
    }
    for (final MapEntry(:key, :value) in store.entries) {
      if (value is! Map || value['at'] is! int) continue;
      final at = DateTime.fromMillisecondsSinceEpoch(value['at'] as int);
      final id = '$key@${value['at']}';
      if (_shown.contains(id) || at.isAfter(now)) continue;
      if (now.difference(at) > const Duration(minutes: 2)) continue;
      _shown.add(id);
      if (!mounted) return;
      setState(
        () => _due = _Due(
          key as String,
          value['title']?.toString() ?? 'Reminder',
          value['body']?.toString() ?? '',
          value['todoId'] as int?,
          value['thread'] as String?,
        ),
      );
      _hide?.cancel();
      _hide = Timer(const Duration(minutes: 1), _dismiss);
      return;
    }
  }

  void _dismiss() {
    if (mounted) setState(() => _due = null);
  }

  Future<void> _snooze(_Due d) async {
    _dismiss();
    await DesktopActions.remind(
      key: d.key,
      at: DateTime.now().add(const Duration(minutes: 10)),
      title: d.title,
      body: d.body,
      todoId: d.todoId,
      thread: d.thread,
    );
  }

  Future<void> _done(_Due d) async {
    _dismiss();
    final todo = context
        .read<TodoCubit>()
        .state
        .items
        .where((i) => i.id == d.todoId)
        .firstOrNull;
    if (todo != null) await DesktopActions.tick(todo, done: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = _due;
    return AnimatedPositioned(
      duration: AppMotion.slow,
      curve: AppMotion.spring,
      top: 16,
      right: d == null ? -420 : 16,
      width: 360,
      child: d == null
          ? const SizedBox.shrink()
          : Material(
              color: c.surface,
              elevation: 18,
              shadowColor: Colors.black45,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Symbols.notifications_active_rounded,
                          size: 18,
                          fill: 1,
                          color: c.primaryGreen,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Echo · now',
                          style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: c.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        InkResponse(
                          onTap: _dismiss,
                          child: Icon(
                            Symbols.close_rounded,
                            size: 18,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      d.title,
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    if (d.body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        d.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 13.5,
                          height: 1.4,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AskPill(
                          label: 'Open',
                          filled: true,
                          onTap: () {
                            _dismiss();
                            widget.onOpen();
                          },
                        ),
                        AskPill(
                          label: 'Snooze 10 min',
                          icon: Symbols.snooze_rounded,
                          onTap: () => _snooze(d),
                        ),
                        if (d.todoId != null)
                          AskPill(
                            label: 'Done',
                            icon: Symbols.check_rounded,
                            onTap: () => _done(d),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
