import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/desktop/presentation/ask/sources_pane.dart';
import 'package:project_echo/features/echo/presentation/cubit/ask_ai_cubit.dart';
import 'package:project_echo/features/echo/presentation/screens/ask_ai_screen.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';

/// Ask Echo on a computer: the phone's conversation on the left, and beside
/// it the messages the answer came from, in full. Pointing at a number in
/// the answer lights its message; picking a message lights its number.
class DesktopAskScreen extends StatefulWidget {
  /// Asked as soon as the screen opens.
  final String? initialQuestion;

  const DesktopAskScreen({super.key, this.initialQuestion});

  @override
  State<DesktopAskScreen> createState() => DesktopAskScreenState();
}

class DesktopAskScreenState extends State<DesktopAskScreen> {
  var _cubit = AskAiCubit();

  /// The answer the owner last pointed into; null follows the latest.
  int? _picked;

  /// The citation lit in both the answer and the pane: (answer, number).
  (int, int)? _lit;

  @override
  void initState() {
    super.initState();
    final question = widget.initialQuestion;
    if (question != null) ask(question);
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  /// Asks [question] in the conversation that's open (from ⌘K or another
  /// section).
  void ask(String question) {
    final q = question.trim();
    if (q.isNotEmpty) _cubit.sendMessage(q);
  }

  /// A clean page: the old conversation goes, with anything still running.
  void _newQuestion() {
    _cubit.close();
    setState(() {
      _cubit = AskAiCubit();
      _picked = null;
      _lit = null;
    });
  }

  void _cite(int message, int number) {
    if (_lit == (message, number)) return;
    setState(() {
      _picked = message;
      _lit = (message, number);
    });
  }

  /// Where Echo's newest answer is in [messages].
  static int? _latestAnswer(List<ChatMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (!m.isUser && m.kind == MessageKind.text) return i;
    }
    return null;
  }

  static List<ChatMessage> _messages(AskAiState state) =>
      state is AskAiMessageReceived ? state.messages : const [];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(onNewQuestion: _newQuestion),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(36, 16, 36, 6),
                    child: AskAiScreen(
                      // A new cubit is a new conversation: start the chat
                      // over too, scroll and input included.
                      key: ObjectKey(_cubit),
                      embedded: true,
                      cubit: _cubit,
                      onCite: _cite,
                      litCite: _lit,
                    ),
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: BlocConsumer<AskAiCubit, AskAiState>(
                    bloc: _cubit,
                    // A new answer takes the pane over from an earlier one.
                    listenWhen: (previous, current) =>
                        _latestAnswer(_messages(previous)) !=
                        _latestAnswer(_messages(current)),
                    listener: (context, state) => setState(() {
                      _picked = null;
                      _lit = null;
                    }),
                    builder: (context, state) {
                      final messages = _messages(state);
                      final shown =
                          _picked != null && _picked! < messages.length
                          ? _picked
                          : _latestAnswer(messages);
                      final asked = shown != null && shown > 0
                          ? messages[shown - 1]
                          : null;
                      return SourcesPane(
                        answer: shown == null ? null : messages[shown],
                        question: asked != null && asked.isUser
                            ? asked.text
                            : null,
                        lit: shown != null && _lit?.$1 == shown
                            ? _lit!.$2
                            : null,
                        onPick: (n) => _cite(shown!, n),
                        onReply: (entry) => _cubit.draftReply(entry),
                        onOpen: (_) =>
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Opens on your phone'),
                              ),
                            ),
                      );
                    },
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

class _Header extends StatelessWidget {
  final VoidCallback onNewQuestion;
  const _Header({required this.onNewQuestion});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ask Echo',
                  style: GoogleFonts.oldStandardTt(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Answers cite the messages they come from. Click a number '
                  'to see it.',
                  style: GoogleFonts.nunito(
                    fontSize: 14.5,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          AskPill(
            label: 'New question',
            icon: Symbols.add_rounded,
            onTap: onNewQuestion,
          ),
        ],
      ),
    );
  }
}
