import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/presentation/widgets/echo_app_bar.dart';
import 'package:project_echo/core/services/voice/echo_voice.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/demo/demo_mode.dart';
import 'package:project_echo/features/echo/data/ask/for_you.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/reply/reply_sender.dart';
import 'package:project_echo/features/echo/presentation/cubit/ask_ai_cubit.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/action_cards.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/answer_view.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_input_bar.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/for_you_view.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';

class AskAiScreen extends StatelessWidget {
  /// True when rendered as a persistent desktop sidebar tab (inside
  /// [DesktopAskScreen], sitting alongside the sidebar) rather than pushed as a
  /// full-screen phone route. Embedded mode drops the [EchoAppBar] — there's
  /// nothing to "back" out of, the sidebar itself is the navigation.
  final bool embedded;

  /// Asked as soon as the screen opens (from the nav dock's question bar).
  final String? initialQuestion;

  /// A message to draft a reply to as soon as the screen opens (Home's
  /// Reply).
  final RawData? replyTo;

  /// Made by whoever shows the chat when something beside it needs the same
  /// conversation (the desktop sources pane), and closed by them; otherwise
  /// the screen makes its own.
  final AskAiCubit? cubit;

  /// Desktop: a citation hovered or clicked in the answer at [message] (its
  /// place in the chat), and the one to light to match a picked source.
  final void Function(int message, int number)? onCite;
  final (int message, int number)? litCite;

  const AskAiScreen({
    super.key,
    this.embedded = false,
    this.initialQuestion,
    this.replyTo,
    this.cubit,
    this.onCite,
    this.litCite,
  });

  @override
  Widget build(BuildContext context) {
    final view = _AskAiView(
      embedded: embedded,
      initialQuestion: initialQuestion,
      replyTo: replyTo,
      onCite: onCite,
      litCite: litCite,
    );
    return cubit != null
        ? BlocProvider.value(value: cubit!, child: view)
        : BlocProvider(create: (context) => AskAiCubit(), child: view);
  }
}

class _AskAiView extends StatefulWidget {
  final bool embedded;
  final String? initialQuestion;
  final RawData? replyTo;
  final void Function(int message, int number)? onCite;
  final (int message, int number)? litCite;

  const _AskAiView({
    required this.embedded,
    this.initialQuestion,
    this.replyTo,
    this.onCite,
    this.litCite,
  });

  @override
  State<_AskAiView> createState() => _AskAiViewState();
}

class _AskAiViewState extends State<_AskAiView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  /// Dictation relies on speech_to_text, whose macOS/Windows backend crashes
  /// on entry, so desktop is typing only.
  static bool get _desktop => Platform.isMacOS || Platform.isWindows;

  String? _name;
  ForYou? _forYou;

  @override
  void initState() {
    super.initState();
    _load();
    if (!_desktop) EchoVoice.instance.warmUp();
    final replyTo = widget.replyTo;
    if (replyTo != null) context.read<AskAiCubit>().draftReply(replyTo);
    final question = widget.initialQuestion?.trim();
    if (question != null && question.isNotEmpty) {
      // A beat's pause in the filming build, so the empty chat is seen first.
      Future<void>.delayed(Duration(milliseconds: kEchoDemo ? 1200 : 0), () {
        if (mounted) context.read<AskAiCubit>().sendMessage(question);
      });
    }
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name')?.trim();
    final forYou = kEchoDemo || _desktop ? null : await ForYou.load(now);
    await ForYou.markLooked(now);
    if (!mounted) return;
    setState(() {
      _name = (name?.isNotEmpty ?? false) ? name : null;
      _forYou = forYou;
    });
  }

  @override
  void dispose() {
    EchoVoice.instance.stop();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _focus.unfocus();
    context.read<AskAiCubit>().sendMessage(text);
  }

  void _ask(String question) =>
      context.read<AskAiCubit>().sendMessage(question);

  void _openSource(RawData source) async {
    if (await ReplySender.open(source) || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("That app can't be opened from here.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: widget.embedded ? null : const EchoAppBar(title: 'Ask Echo'),
      body: BlocConsumer<AskAiCubit, AskAiState>(
        listenWhen: (previous, current) =>
            current is AskAiMessageReceived &&
            (previous is! AskAiMessageReceived ||
                previous.messages.length != current.messages.length ||
                current.messages.last.isGenerating),
        listener: (context, state) => _scrollToBottom(),
        builder: (context, state) {
          final received = state is AskAiMessageReceived ? state : null;
          final messages = received?.messages ?? const <ChatMessage>[];
          final busy =
              (received?.isSearching ?? false) ||
              messages.any((m) => m.isGenerating);
          final side = widget.embedded ? 4.0 : 20.0;

          final chat = Stack(
            children: [
              Positioned.fill(
                child: messages.isEmpty
                    ? _opening(side)
                    : ListView.builder(
                        controller: _scroll,
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(side, side, side, 170),
                        itemCount: messages.length,
                        itemBuilder: (context, i) => _Entrance(
                          key: ValueKey('msg_$i'),
                          fromRight: messages[i].isUser,
                          child: Padding(
                            padding: EdgeInsets.only(
                              bottom: _desktop ? 14 : 24,
                            ),
                            child: _message(
                              messages,
                              i,
                              i == messages.length - 1
                                  ? received?.progress
                                  : null,
                            ),
                          ),
                        ),
                      ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      widget.embedded ? 4 : 16,
                      0,
                      widget.embedded ? 4 : 16,
                      16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Chips(chips: busy ? const [] : _chips(messages)),
                        AskInputBar(
                          controller: _input,
                          focusNode: _focus,
                          enabled: !busy,
                          hint: messages.isEmpty
                              ? 'Ask Echo anything…'
                              : 'Ask a follow-up…',
                          onSend: _send,
                          dictation: !_desktop,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );

          if (!_desktop) return chat;
          // Desktop: a comfortable, centered conversation column instead of
          // the chat stretching edge to edge across a much wider window.
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: chat,
            ),
          );
        },
      ),
    );
  }

  Widget _message(List<ChatMessage> messages, int i, AskProgress? progress) {
    final cubit = context.read<AskAiCubit>();
    final m = messages[i];
    if (m.isUser) return _UserBubble(m.text);
    // Once Echo has said something newer, an earlier answer keeps its words
    // but lets go of its cards and buttons, so the conversation reads cleanly.
    final earlier = messages.skip(i + 1).any((n) => !n.isUser);
    return switch (m.kind) {
      MessageKind.text => EchoTurn(
        message: m,
        progress: progress,
        earlier: earlier,
        onAdd: m.addable ? () => cubit.addFromAnswer(i) : null,
        onOpenSource: _openSource,
        onCite: widget.onCite == null ? null : (n) => widget.onCite!(i, n),
        litCite: widget.litCite?.$1 == i ? widget.litCite!.$2 : null,
      ),
      MessageKind.notice => _NoticeBubble(m.text),
      MessageKind.added => AddedCard(
        message: m,
        onUndo: () => cubit.undoAdded(i),
      ),
      MessageKind.draft => DraftCard(
        draft: m.draft!,
        onSend: () => cubit.sendDraft(i),
        onEdit: (text) => cubit.editDraft(i, text),
        onQuickReply: (emoji) => cubit.quickReply(i, emoji),
      ),
    };
  }

  /// Suggestions above the input: openers before anything is asked, then
  /// replies to the people the last answer mentions.
  List<(String, VoidCallback)> _chips(List<ChatMessage> messages) {
    if (messages.isEmpty) {
      final group = _forYou?.busiestGroup;
      return [
        ('What needs me today?', () => _ask('What needs me today?')),
        group != null
            ? ('Catch me up on $group', () => _ask('Catch me up on $group'))
            : ("What's on tomorrow?", () => _ask("What's on tomorrow?")),
      ];
    }
    final last = messages.last;
    if (last.isUser || last.kind != MessageKind.text) return const [];
    final cubit = context.read<AskAiCubit>();
    final seen = <String>{};
    String who(RawData e) =>
        e.sender.isEmpty ? e.threadTitle ?? e.source : e.sender;
    return [
      // Chats that want the owner: offer to answer them.
      for (final e in last.cited)
        if (e.thread != null &&
            Addressed.parse(e.addressed) != null &&
            seen.add(e.thread ?? who(e)))
          ('Draft a reply to ${who(e)}', () => cubit.draftReply(e)),
      // Anyone else the answer drew on: ask more about them.
      for (final e in last.cited)
        if (seen.add(e.thread ?? who(e)))
          (
            'What else did ${who(e)} say?',
            () => _ask('What else did ${who(e)} say?'),
          ),
    ].take(2).toList();
  }

  /// The phone opens on what's new for the owner, even when that's
  /// nothing; desktop, which hears no notifications itself, on a welcome.
  Widget _opening(double side) {
    if (_desktop || kEchoDemo) {
      return _EmptyState(name: _name, embedded: widget.embedded);
    }
    final forYou = _forYou;
    if (forYou == null) return const SizedBox.shrink();
    final cubit = context.read<AskAiCubit>();
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(side, 8, side, 170),
      child: ForYouView(
        forYou: forYou,
        name: _name,
        now: DateTime.now(),
        onReply: (e) => cubit.draftReply(e),
        onAdd: (e) => cubit.addEntries([e]),
        onChatter: () => _ask('Catch me up on my group chats'),
      ),
    );
  }
}

/// How Ask Echo greets when there's nothing new for the owner.
class _EmptyState extends StatelessWidget {
  final String? name;
  final bool embedded;
  const _EmptyState({required this.name, required this.embedded});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              embedded ? 8 : 24,
              0,
              embedded ? 8 : 24,
              170,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const EchoMascot(
                  state: EchoState.idle,
                  size: 120,
                  showRings: false,
                  glow: false,
                ),
                const SizedBox(height: 18),
                Text(
                  name != null ? 'How can I help, $name?' : 'How can I help?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.oldStandardTt(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Ask about your schedule, messages, or anything in your local vault.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(
                    fontSize: 14.5,
                    color: context.colors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Messages grow in from their own side, as they always have.
class _Entrance extends StatelessWidget {
  final bool fromRight;
  final Widget child;
  const _Entrance({super.key, required this.fromRight, required this.child});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 400),
    curve: Curves.easeOutBack,
    builder: (context, value, child) => Transform.scale(
      scale: value,
      alignment: fromRight ? Alignment.bottomRight : Alignment.bottomLeft,
      child: child,
    ),
    child: child,
  );
}

class _UserBubble extends StatelessWidget {
  final String text;
  const _UserBubble(this.text);

  static bool get _desktop => Platform.isMacOS || Platform.isWindows;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: _desktop ? 15 : 20,
          vertical: _desktop ? 9 : 14,
        ),
        decoration: BoxDecoration(
          color: context.colors.buttonDark,
          borderRadius: BorderRadius.circular(
            _desktop ? 18 : 24,
          ).copyWith(bottomRight: const Radius.circular(8)),
        ),
        child: Text(
          text,
          style: GoogleFonts.nunito(
            color: context.colors.surface,
            fontSize: _desktop ? 14 : 16,
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

/// A limit or error notice: plain words on amber, not an answer.
class _NoticeBubble extends StatelessWidget {
  final String text;
  const _NoticeBubble(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: context.colors.amberBackground,
          borderRadius: BorderRadius.circular(
            20,
          ).copyWith(bottomLeft: const Radius.circular(6)),
        ),
        child: Text(
          text,
          style: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.45,
            color: context.colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Suggestions above the input, as the nav dock shows them.
class _Chips extends StatelessWidget {
  final List<(String, VoidCallback)> chips;
  const _Chips({required this.chips});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: chips.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: chips.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final (label, onTap) = chips[i];
                    return PressFeedback(
                      child: Material(
                        color: colors.surface,
                        shape: StadiumBorder(
                          side: BorderSide(
                            color: colors.dividerColor.withValues(alpha: 0.8),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: onTap,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Center(
                              child: ConstrainedBox(
                                // A long group name ends in "…" rather than
                                // running off the screen.
                                constraints: const BoxConstraints(
                                  maxWidth: 240,
                                ),
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.nunito(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}
