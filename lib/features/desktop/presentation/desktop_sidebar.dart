import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/echo_server_service.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/desktop/presentation/desktop_workspace.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The sidebar keeps the app's dark palette whatever the theme, like any
/// app's rail: it's chrome, not content.
class _Rail {
  static const background = Color(0xFF141514);
  static const ink = Color(0xFFE9E9E6);
  static const muted = Color(0xFF8F918C);
  static const hover = Color(0xFF1F211F);
  static const selected = Color(0xFF243326);
  static const green = Color(0xFF6EBC76);
  static const onGreen = Color(0xFFA9D9AE);
}

/// Echo, "Ask or do anything ⌘K", the sections with what's waiting in each,
/// and how the phone and engine are doing.
class DesktopSidebar extends StatelessWidget {
  final DesktopSection section;

  /// Chats waiting on the owner today, and to-dos left today.
  final int waiting;
  final int todoLeft;
  final ValueChanged<DesktopSection> onSelect;
  final VoidCallback onPalette;

  const DesktopSidebar({
    super.key,
    required this.section,
    required this.waiting,
    required this.todoLeft,
    required this.onSelect,
    required this.onPalette,
  });

  @override
  Widget build(BuildContext context) {
    Widget item(DesktopSection s, IconData icon, String label, [int? count]) =>
        _Item(
          icon: icon,
          label: label,
          count: count,
          selected: section == s,
          onTap: () => onSelect(s),
        );
    return Container(
      width: 232,
      color: _Rail.background,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.asset(
                      'assets/app_icon_source.png',
                      width: 26,
                      height: 26,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Echo',
                    style: GoogleFonts.oldStandardTt(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color: _Rail.ink,
                    ),
                  ),
                ],
              ),
            ),
            PressFeedback(
              scale: 0.98,
              haptic: false,
              child: Material(
                color: _Rail.hover,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onPalette,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Symbols.search_rounded,
                          size: 19,
                          color: _Rail.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ask or do anything',
                            style: GoogleFonts.nunito(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _Rail.muted,
                            ),
                          ),
                        ),
                        const KeyCap('⌘K', onDark: true),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            item(
              DesktopSection.today,
              Symbols.wb_sunny_rounded,
              'Today',
              waiting,
            ),
            item(
              DesktopSection.todo,
              Symbols.checklist_rounded,
              'To-do',
              todoLeft,
            ),
            item(DesktopSection.ask, Symbols.forum_rounded, 'Ask Echo'),
            item(DesktopSection.vault, Symbols.inbox_rounded, 'Vault'),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
              child: Text(
                'YOU',
                style: GoogleFonts.nunito(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: _Rail.muted,
                ),
              ),
            ),
            item(DesktopSection.profile, Symbols.person_rounded, 'Profile'),
            const Spacer(),
            const _PhoneStatus(),
            const SizedBox(height: 8),
            const _EngineStatus(),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _Item({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: PressFeedback(
        scale: 0.98,
        haptic: false,
        child: Material(
          color: selected ? _Rail.selected : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            hoverColor: _Rail.hover,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 21,
                    fill: selected ? 1 : 0,
                    color: selected ? _Rail.green : _Rail.muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _Rail.ink,
                      ),
                    ),
                  ),
                  if ((count ?? 0) > 0)
                    Text(
                      '$count',
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? _Rail.onGreen : _Rail.muted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Your phone · synced 2 min ago", from the last snapshot it sent.
class _PhoneStatus extends StatefulWidget {
  const _PhoneStatus();

  @override
  State<_PhoneStatus> createState() => _PhoneStatusState();
}

class _PhoneStatusState extends State<_PhoneStatus> {
  DateTime? _last;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _read();
    EchoServerService.instance.syncTick.addListener(_read);
    // "2 min ago" moves on by itself.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _read());
  }

  @override
  void dispose() {
    EchoServerService.instance.syncTick.removeListener(_read);
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(EchoServerService.lastPhoneSyncKey);
    if (mounted) {
      setState(
        () =>
            _last = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _last;
    final ago = last == null ? null : DateTime.now().difference(last);
    // The phone sends every 25 seconds while Echo is open on it.
    final live = ago != null && ago < const Duration(minutes: 2);
    final line = last == null
        ? 'Not connected yet. Pair it from Profile → This computer.'
        : ago!.inMinutes < 1
        ? 'Synced just now · replies go through it'
        : ago.inMinutes < 60
        ? 'Synced ${ago.inMinutes} min ago · replies go through it'
        : 'Last synced ${ago.inHours} h ago. Open Echo on your phone.';
    return _StatusCard(
      dot: live ? _Rail.green : _Rail.muted,
      title: 'Your phone',
      line: line,
    );
  }
}

class _EngineStatus extends StatelessWidget {
  const _EngineStatus();

  @override
  Widget build(BuildContext context) {
    final on = context.select(
      (SettingsCubit s) => s.state.runDesktopEngineHere,
    );
    return _StatusCard(
      icon: Symbols.memory_rounded,
      dot: on ? _Rail.green : _Rail.muted,
      title: 'Echo Engine',
      line: on ? 'Running here for your phone' : 'Off',
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData? icon;
  final Color dot;
  final String title;
  final String line;

  const _StatusCard({
    this.icon,
    required this.dot,
    required this.title,
    required this.line,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _Rail.hover,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: icon != null
                ? Icon(icon, size: 17, color: dot)
                : Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _Rail.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  line,
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: _Rail.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
