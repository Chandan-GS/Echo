import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/services/echo_server_service.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/desktop/presentation/ask/desktop_ask_screen.dart';
import 'package:project_echo/features/desktop/presentation/command_palette.dart';
import 'package:project_echo/features/desktop/presentation/desktop_sidebar.dart';
import 'package:project_echo/features/desktop/presentation/reminder_banner.dart';
import 'package:project_echo/features/desktop/presentation/today/desktop_today_screen.dart';
import 'package:project_echo/features/desktop/presentation/todo/desktop_todo_board.dart';
import 'package:project_echo/features/desktop/presentation/vault/desktop_vault_table.dart';
import 'package:project_echo/features/echo/data/home/home_feed.dart';
import 'package:project_echo/features/settings/presentation/screens/settings_screen.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';

/// The sections of the desktop app, in sidebar order.
enum DesktopSection { today, todo, ask, vault, profile }

/// Echo on a computer: a workspace for getting through what came in, not
/// the phone made bigger. A sidebar, the section showing, ⌘K for anything,
/// keyboard shortcuts, and reminders as they come due. Everything it changes
/// it changes through the phone (see DesktopActions).
class DesktopWorkspace extends StatefulWidget {
  /// Opens on Ask Echo with this question.
  final String? initialQuestion;
  const DesktopWorkspace({super.key, this.initialQuestion});

  @override
  State<DesktopWorkspace> createState() => _DesktopWorkspaceState();
}

class _DesktopWorkspaceState extends State<DesktopWorkspace> {
  DesktopSection _section = DesktopSection.today;
  bool _palette = false;
  bool _shortcuts = false;

  /// A scope, not a plain node: when the section being left lets go of the
  /// keyboard (IndexedStack takes focus from what it hides), focus falls
  /// back to here rather than to the page above, so the shortcuts still
  /// work.
  final _focus = FocusScopeNode(debugLabel: 'desktop workspace');
  final _todoKey = GlobalKey<DesktopTodoBoardState>();
  final _askKey = GlobalKey<DesktopAskScreenState>();
  final _vaultKey = GlobalKey<DesktopVaultTableState>();

  /// The question Ask opens with, when it's opened from elsewhere first.
  String? _firstQuestion;

  /// Who's waiting, for the sidebar's count and the palette's replies.
  HomeFeed _feed = HomeFeed.empty;

  @override
  void initState() {
    super.initState();
    final question = widget.initialQuestion;
    if (question != null) {
      _firstQuestion = question;
      _section = DesktopSection.ask;
    }
    _loadFeed();
    EchoServerService.instance.syncTick.addListener(_loadFeed);
  }

  @override
  void dispose() {
    EchoServerService.instance.syncTick.removeListener(_loadFeed);
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadFeed() async {
    try {
      final feed = await HomeFeed.load(DateTime.now());
      if (mounted) setState(() => _feed = feed);
    } catch (_) {}
  }

  void _go(DesktopSection s) {
    setState(() {
      _section = s;
      _palette = false;
      _shortcuts = false;
    });
  }

  /// Opens Ask and asks [question].
  void _ask(String question) {
    final ask = _askKey.currentState;
    if (ask == null) {
      _firstQuestion = question;
    } else {
      ask.ask(question);
    }
    _go(DesktopSection.ask);
  }

  void _addTodo() {
    _go(DesktopSection.todo);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _todoKey.currentState?.focusAdd(),
    );
  }

  /// Shortcuts that work anywhere: ⌘K, ⌘N, ⌘F, ?, 1–4 and Esc. Typing in a
  /// field keeps its own keys; screens handle their own (J, K, R, E…).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final meta =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final key = event.logicalKey;
    if (meta && key == LogicalKeyboardKey.keyK) {
      setState(() {
        _palette = !_palette;
        _shortcuts = false;
      });
      return KeyEventResult.handled;
    }
    if (meta && key == LogicalKeyboardKey.keyN) {
      _addTodo();
      return KeyEventResult.handled;
    }
    if (meta && key == LogicalKeyboardKey.keyF) {
      _go(DesktopSection.vault);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _vaultKey.currentState?.focusSearch(),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && (_palette || _shortcuts)) {
      setState(() {
        _palette = false;
        _shortcuts = false;
      });
      return KeyEventResult.handled;
    }
    if (_typing || meta || _palette) return KeyEventResult.ignored;
    if (event.character == '?') {
      setState(() => _shortcuts = !_shortcuts);
      return KeyEventResult.handled;
    }
    final section = switch (event.character) {
      '1' => DesktopSection.today,
      '2' => DesktopSection.todo,
      '3' => DesktopSection.ask,
      '4' => DesktopSection.vault,
      _ => null,
    };
    if (section != null) {
      _go(section);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Whether a text field has the keyboard.
  bool get _typing {
    final focused = FocusManager.instance.primaryFocus?.context?.widget;
    return focused is EditableText;
  }

  @override
  Widget build(BuildContext context) {
    final todo = context.select(
      (TodoCubit c) => c.state.today.where((i) => !i.done).length,
    );
    final sections = [
      DesktopTodayScreen(onAsk: _ask),
      DesktopTodoBoard(key: _todoKey),
      DesktopAskScreen(key: _askKey, initialQuestion: _firstQuestion),
      DesktopVaultTable(key: _vaultKey, onAsk: _ask),
      const SettingsScreen(),
    ];
    return FocusScope(
      node: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: Stack(
          children: [
            Row(
              children: [
                DesktopSidebar(
                  section: _section,
                  waiting: _feed.needsYou.length,
                  todoLeft: todo,
                  onSelect: _go,
                  onPalette: () => setState(() => _palette = true),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _section.index,
                    children: [
                      for (final (i, s) in sections.indexed)
                        // Each keeps its place while another shows; a
                        // section only lays out once it's been opened.
                        TickerMode(enabled: i == _section.index, child: s),
                    ],
                  ),
                ),
              ],
            ),
            ReminderBanner(onOpen: () => _go(DesktopSection.todo)),
            if (_palette || _shortcuts)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _palette = false;
                    _shortcuts = false;
                  }),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.35),
                  ),
                ),
              ),
            if (_palette)
              CommandPalette(
                feed: _feed,
                onClose: () => setState(() => _palette = false),
                onGo: _go,
                onAsk: _ask,
                onAddTodo: _addTodo,
              ),
            if (_shortcuts) const _ShortcutSheet(),
          ],
        ),
      ),
    );
  }
}

/// "?": every shortcut, in one card.
class _ShortcutSheet extends StatelessWidget {
  const _ShortcutSheet();

  static const _keys = [
    ('Ask or do anything', '⌘K'),
    ('Next / previous', 'J / K'),
    ('Reply', 'R'),
    ('Send the reply', '⌘↵'),
    ('Remind me', 'H'),
    ('Add to To-do', 'T'),
    ('Mark handled', 'E'),
    ('New to-do', '⌘N'),
    ('Search the Vault', '⌘F'),
    ('Today / To-do / Ask / Vault', '1 – 4'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Container(
        width: 560,
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.dividerColor),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 60,
              offset: Offset(0, 24),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Keyboard',
              style: GoogleFonts.oldStandardTt(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              runSpacing: 10,
              children: [
                for (final (what, key) in _keys)
                  SizedBox(
                    width: 256,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            what,
                            style: GoogleFonts.nunito(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        KeyCap(key),
                        const SizedBox(width: 24),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A key on the keyboard, as text: "⌘K".
class KeyCap extends StatelessWidget {
  final String label;
  final bool onDark;
  const KeyCap(this.label, {super.key, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: onDark ? const Color(0xFF3A3B3A) : c.dividerColor,
        ),
        color: onDark ? null : Color.lerp(c.background, c.surface, 0.4),
      ),
      child: Text(
        label,
        style: GoogleFonts.nunito(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: onDark ? const Color(0xFF8F918C) : c.textSecondary,
        ),
      ),
    );
  }
}
