import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/desktop/presentation/desktop_workspace.dart';
import 'package:project_echo/features/echo/data/home/home_feed.dart';

/// One thing ⌘K can do.
class _Command {
  final String group;
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback run;
  const _Command(this.group, this.icon, this.label, this.hint, this.run);
}

/// ⌘K: anything, from anywhere. Reply to someone waiting, add a to-do,
/// catch up on a busy group, go to a section — or type a question and Echo
/// answers it.
class CommandPalette extends StatefulWidget {
  final HomeFeed feed;
  final VoidCallback onClose;
  final ValueChanged<DesktopSection> onGo;
  final ValueChanged<String> onAsk;
  final VoidCallback onAddTodo;

  const CommandPalette({
    super.key,
    required this.feed,
    required this.onClose,
    required this.onGo,
    required this.onAsk,
    required this.onAddTodo,
  });

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  int _at = 0;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() => _at = 0));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<_Command> get _all {
    final w = widget;
    String who(e) => e.isGroup && (e.threadTitle?.isNotEmpty ?? false)
        ? '${e.sender} in ${e.threadTitle}'
        : e.sender;
    return [
      for (final e in w.feed.needsYou)
        _Command(
          'Waiting on you',
          Symbols.reply_rounded,
          'Reply to ${who(e)}',
          'Today',
          () => w.onGo(DesktopSection.today),
        ),
      _Command(
        'Actions',
        Symbols.checklist_rounded,
        'Add a to-do…',
        '⌘N',
        w.onAddTodo,
      ),
      for (final g in w.feed.busyGroups)
        _Command(
          'Actions',
          Symbols.forum_rounded,
          'Catch me up on ${g.name}',
          'Ask',
          () => w.onAsk('Catch me up on ${g.name}'),
        ),
      _Command(
        'Actions',
        Symbols.wb_sunny_rounded,
        'What needs me today?',
        'Ask',
        () => w.onAsk('What needs me today?'),
      ),
      for (final (s, icon, label, key) in [
        (DesktopSection.today, Symbols.wb_sunny_rounded, 'Today', '1'),
        (DesktopSection.todo, Symbols.checklist_rounded, 'To-do', '2'),
        (DesktopSection.ask, Symbols.forum_rounded, 'Ask Echo', '3'),
        (DesktopSection.vault, Symbols.inbox_rounded, 'Vault', '4'),
        (
          DesktopSection.profile,
          Symbols.settings_rounded,
          'Profile and settings',
          '',
        ),
      ])
        _Command('Go to', icon, label, key, () => w.onGo(s)),
    ];
  }

  /// What matches what's typed; a question (or nothing matching) is asked.
  List<_Command> get _shown {
    final q = _query.text.trim();
    final lower = q.toLowerCase();
    final matches = q.isEmpty
        ? _all
        : _all.where((c) => c.label.toLowerCase().contains(lower)).toList();
    if (q.isNotEmpty &&
        (matches.isEmpty || q.endsWith('?') || q.split(' ').length > 3)) {
      return [
        _Command(
          'Ask Echo',
          Symbols.forum_rounded,
          'Ask “$q”',
          '↵',
          () => widget.onAsk(q),
        ),
        ...matches,
      ];
    }
    return matches;
  }

  void _run(_Command c) {
    widget.onClose();
    c.run();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final shown = _shown;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        setState(() => _at = (_at + 1).clamp(0, shown.length - 1));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        setState(() => _at = (_at - 1).clamp(0, shown.length - 1));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        if (shown.isNotEmpty) _run(shown[_at.clamp(0, shown.length - 1)]);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        widget.onClose();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = _shown;
    String? group;
    return Align(
      alignment: const Alignment(0, -0.55),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        elevation: 24,
        shadowColor: Colors.black54,
        child: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Focus(
                onKeyEvent: _onKey,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 14, 6),
                  child: Row(
                    children: [
                      Icon(Symbols.search_rounded, color: c.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _query,
                          focusNode: _focus,
                          cursorColor: c.primaryGreen,
                          style: GoogleFonts.nunito(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            hintText: 'Ask Echo, or do something…',
                            hintStyle: GoogleFonts.nunito(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: c.textSecondary.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                      const KeyCap('esc'),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: c.dividerColor),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(8),
                  children: [
                    for (final (i, cmd) in shown.indexed) ...[
                      if (cmd.group != group) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                          child: Text(
                            (group = cmd.group).toUpperCase(),
                            style: GoogleFonts.nunito(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.3,
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ],
                      _Row(
                        command: cmd,
                        selected: i == _at,
                        onHover: () => setState(() => _at = i),
                        onTap: () => _run(cmd),
                      ),
                    ],
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Nothing here. Press ↵ to ask Echo.',
                          style: GoogleFonts.nunito(color: c.textSecondary),
                        ),
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: c.dividerColor),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    for (final hint in [
                      '↑↓ to move',
                      '↵ to run',
                      'Typing a question asks Echo',
                    ])
                      Text(
                        hint,
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final _Command command;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  const _Row({
    required this.command,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? context.selectionFill : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                command.icon,
                size: 20,
                color: selected ? context.onSelection : c.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  command.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected ? context.onSelection : c.textPrimary,
                  ),
                ),
              ),
              Text(
                command.hint,
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? context.onSelection : c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
