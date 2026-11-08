import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/widgets/echo_app_bar.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/services/desktop_engine_client.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/profile/data/paired_computers.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';

/// Echo on your computer: each paired computer by name, the switch for using
/// it, Unpair, and Pair another. Local Wi-Fi only.
class DesktopScreen extends StatefulWidget {
  const DesktopScreen({super.key});

  @override
  State<DesktopScreen> createState() => _DesktopScreenState();
}

enum _Reach { unknown, checking, here, away }

class _DesktopScreenState extends State<DesktopScreen> {
  List<PairedComputer>? _computers;
  final Map<String, _Reach> _reach = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final computers = await PairedComputers.load();
    if (!mounted) return;
    setState(() => _computers = computers);
    final inUse = context.read<SettingsCubit>().state.desktopEngineHost;
    for (final c in computers) {
      if (c.host == inUse) _check(c);
    }
  }

  Future<void> _check(PairedComputer computer) async {
    setState(() => _reach[computer.host] = _Reach.checking);
    final found = await DesktopEngineClient.discoverHost(
      cachedHost: computer.host,
    );
    if (!mounted) return;
    setState(
      () => _reach[computer.host] = found == computer.host
          ? _Reach.here
          : _Reach.away,
    );
  }

  Future<void> _setUsing(PairedComputer computer, bool on) async {
    final cubit = context.read<SettingsCubit>();
    if (!on) return cubit.setPreferDesktopEngine(false);
    await PairedComputers.use(computer);
    await cubit.pairedWithDesktop(host: computer.host, name: computer.name);
  }

  Future<void> _unpair(PairedComputer computer) async {
    final cubit = context.read<SettingsCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => _UnpairDialog(name: computer.name),
    );
    if (sure != true) return;
    final wasInUse = await PairedComputers.forget(computer);
    if (wasInUse) {
      await cubit.setPreferDesktopEngine(false);
      await cubit.setDesktopEngineHost(null);
    }
    await _load();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${computer.name} unpaired')));
  }

  Future<void> _pair() async {
    await context.push('/scan-desktop');
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final computers = _computers;
    var n = 0;
    Widget enter(Widget child) =>
        FadeSlideIn(delay: AppMotion.staggerDelay(n++), child: child);
    return Scaffold(
      backgroundColor: c.background,
      appBar: const EchoAppBar(title: 'Your computer'),
      body: computers == null
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : BlocBuilder<SettingsCubit, SettingsState>(
              builder: (context, settings) => ListView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  24,
                  4,
                  24,
                  MediaQuery.paddingOf(context).bottom + 32,
                ),
                children: [
                  enter(
                    Text(
                      'See Today and People on a big screen, and let your '
                      'computer do the heavy writing. Everything stays on '
                      'your Wi-Fi.',
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        height: 1.45,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (computers.isEmpty)
                    enter(const _NoComputer())
                  else
                    for (final computer in computers)
                      enter(
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ComputerCard(
                            computer: computer,
                            reach: _reach[computer.host] ?? _Reach.unknown,
                            using:
                                settings.preferDesktopEngine &&
                                settings.desktopEngineHost == computer.host,
                            onUsing: (on) => _setUsing(computer, on),
                            onCheck: () => _check(computer),
                            onUnpair: () => _unpair(computer),
                          ),
                        ),
                      ),
                  const SizedBox(height: 4),
                  enter(
                    EchoButton(
                      text: computers.isEmpty
                          ? 'Pair a computer'
                          : 'Pair another computer',
                      icon: Symbols.qr_code_scanner_rounded,
                      onPressed: _pair,
                    ),
                  ),
                  enter(
                    Padding(
                      padding: const EdgeInsets.only(top: 28, bottom: 12),
                      child: Text(
                        'What it does',
                        style: GoogleFonts.oldStandardTt(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  enter(const _WhatItDoes()),
                ],
              ),
            ),
    );
  }
}

class _NoComputer extends StatelessWidget {
  const _NoComputer();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AskCard(
      child: Column(
        children: [
          Icon(Symbols.computer_rounded, size: 40, color: c.textSecondary),
          const SizedBox(height: 10),
          Text(
            'No computer paired. Open Echo on your Mac or PC, go to Settings, '
            'and show the pairing code.',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 14.5,
              height: 1.45,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComputerCard extends StatelessWidget {
  final PairedComputer computer;
  final _Reach reach;
  final bool using;
  final ValueChanged<bool> onUsing;
  final VoidCallback onCheck;
  final VoidCallback onUnpair;

  const _ComputerCard({
    required this.computer,
    required this.reach,
    required this.using,
    required this.onUsing,
    required this.onCheck,
    required this.onUnpair,
  });

  String get _status => switch (reach) {
    _Reach.checking => 'Looking for it…',
    _Reach.here => 'On the same Wi-Fi',
    _Reach.away => 'Not on this Wi-Fi right now',
    _Reach.unknown => 'Paired',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AskCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.selectionFill,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Symbols.laptop_mac_rounded,
                  size: 24,
                  color: context.onSelection,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      computer.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: reach == _Reach.here
                                ? c.primaryGreen
                                : c.textSecondary.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _status,
                            style: GoogleFonts.nunito(
                              fontSize: 13,
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Use it for drafts and Ask',
                      style: GoogleFonts.nunito(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      'Sharper answers from its bigger model. Your phone '
                      'still works on its own.',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        height: 1.35,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: using,
                activeTrackColor: c.primaryGreen,
                onChanged: onUsing,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AskPill(
                label: 'Check again',
                icon: Symbols.refresh_rounded,
                onTap: reach == _Reach.checking ? null : onCheck,
              ),
              AskPill(
                label: 'Unpair',
                icon: Symbols.link_off_rounded,
                onTap: onUnpair,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UnpairDialog extends StatelessWidget {
  final String name;
  const _UnpairDialog({required this.name});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Unpair $name?',
        style: GoogleFonts.nunito(
          fontWeight: FontWeight.w700,
          color: c.textPrimary,
        ),
      ),
      content: Text(
        'It stops showing your Today and People, and Echo forgets its pairing '
        'code. You can pair again any time.',
        style: GoogleFonts.nunito(
          fontSize: 14,
          height: 1.45,
          color: c.textPrimary,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: GoogleFonts.nunito(
              fontWeight: FontWeight.w800,
              color: c.textSecondary,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            'Unpair',
            style: GoogleFonts.nunito(
              fontWeight: FontWeight.w800,
              color: const Color(0xFFC0503B),
            ),
          ),
        ),
      ],
    );
  }
}

class _WhatItDoes extends StatelessWidget {
  const _WhatItDoes();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget row(
      IconData icon,
      String title,
      String note, {
      bool first = false,
    }) => Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(
                top: BorderSide(color: c.dividerColor.withValues(alpha: 0.6)),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: c.textPrimary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  note,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    height: 1.35,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return AskCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Column(
        children: [
          row(
            Symbols.dashboard_rounded,
            'Today and People, side by side',
            'Reply from the keyboard; it sends from your phone.',
            first: true,
          ),
          row(
            Symbols.edit_note_rounded,
            'Drafts and Ask on a bigger model',
            'It runs on your computer, with nothing sent to the cloud.',
          ),
          row(
            Symbols.lock_rounded,
            'Local only',
            'The two talk over your Wi-Fi. No account, no relay.',
          ),
        ],
      ),
    );
  }
}
