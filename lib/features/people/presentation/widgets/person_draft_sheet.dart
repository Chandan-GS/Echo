import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/person_avatar.dart';
import 'package:project_echo/core/services/engine_gate.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/ask/ask_intents.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/reply/reply_drafter.dart';
import 'package:project_echo/features/echo/data/reply/reply_sender.dart';
import 'package:project_echo/features/people/presentation/widgets/people_parts.dart';

enum PersonDraftKind { wish, hi, message, followUp }

/// What the sheet is writing, and to whom.
class PersonDraft {
  final PersonDraftKind kind;
  final String name;
  final String source;

  /// Where it goes; null means copy and paste (someone only heard in a group).
  final RawData? to;

  /// The line that prompted it, shown above the text.
  final String? context;

  const PersonDraft({
    required this.kind,
    required this.name,
    required this.source,
    this.to,
    this.context,
  });

  String get first => name.trim().split(RegExp(r'\s+')).first;

  /// Three short ways to say it, without any model.
  List<String> get templates => switch (kind) {
    PersonDraftKind.wish => [
      'Happy birthday $first! Hope it’s a lovely one 🎉',
      'Happy birthday! 🎂 Have the best day.',
      'Happiest birthday $first! 🎉',
    ],
    PersonDraftKind.hi => [
      'Hey $first, it’s been a while. How are you?',
      'Hey $first, how’s it going?',
      '$first 👋',
    ],
    PersonDraftKind.message => [
      'Hey $first, how’s it going?',
      'Hi $first! Free for a quick call later?',
      '$first 👋',
    ],
    PersonDraftKind.followUp => [
      'Hey $first, any update on this?',
      'Hi $first, did you get a chance to look at this?',
      'Just checking in on this, $first.',
    ],
  };

  /// What to ask the engine for.
  String get gist => switch (kind) {
    PersonDraftKind.wish => 'Wish them a happy birthday, warmly and briefly.',
    PersonDraftKind.hi =>
      'Say hi and ask how they are. It has been a while since they wrote.',
    PersonDraftKind.message => 'Say hi and ask how they are.',
    PersonDraftKind.followUp =>
      'Gently follow up on this, asking if they got a chance to look at it.',
  };

  String get title => switch (kind) {
    PersonDraftKind.wish => 'Wish $first',
    PersonDraftKind.hi => 'Say hi to $first',
    PersonDraftKind.message => 'Message $first',
    PersonDraftKind.followUp => 'Follow up with $first',
  };
}

/// What the owner's writing engine would say, or null when it couldn't (no
/// engine, or it failed, and the drafter handed the words back unchanged).
Future<String?> writeDraft(RawData to, String gist) async {
  final request = ReplyRequest(to, gist);
  final text = await ReplyDrafter.draft(request);
  if (text.trim().isEmpty || text == localDraft(request)) return null;
  return text;
}

/// The label for a Send button, by the way the reply would leave.
String sendLabel(ReplyRoute route, String source) {
  final app = appLabel(source);
  return switch (route) {
    ReplyRoute.send => pillWith('Send on', app),
    ReplyRoute.write => pillWith('Write in', app),
    ReplyRoute.pick => 'Choose the chat',
    ReplyRoute.copy => pillWith('Copy for', app),
  };
}

/// What the owner sees after a reply left, or the fallback when its action
/// has gone stale: the chat opens with the text ready, or it's on the
/// clipboard.
String outcomeLine(ReplyOutcome outcome, String source, String name) {
  final app = appLabel(source);
  return switch (outcome) {
    ReplyOutcome.sent => 'Sent to $name on $app.',
    ReplyOutcome.written => 'Opened $app with this typed in. Tap send there.',
    ReplyOutcome.picker => 'Pick $name’s chat in $app and tap send.',
    ReplyOutcome.copied => 'Copied. Paste it into $app.',
  };
}

/// Opens the sheet. Resolves with the text sent, or null if it was closed.
Future<String?> showPersonDraftSheet(
  BuildContext context,
  PersonDraft draft,
) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _PersonDraftSheet(draft: draft, snackContext: context),
  );
}

class _PersonDraftSheet extends StatefulWidget {
  final PersonDraft draft;
  final BuildContext snackContext;

  const _PersonDraftSheet({required this.draft, required this.snackContext});

  @override
  State<_PersonDraftSheet> createState() => _PersonDraftSheetState();
}

class _PersonDraftSheetState extends State<_PersonDraftSheet> {
  late final TextEditingController _text;
  ReplyRoute _route = ReplyRoute.send;
  bool _sending = false;
  bool _writing = false;

  PersonDraft get d => widget.draft;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: d.templates.first);
    if (d.to != null) {
      ReplySender.routeFor(d.to!).then((r) {
        if (mounted) setState(() => _route = r);
      });
    } else {
      _route = ReplyRoute.copy;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _write() async {
    if (_writing) return;
    final to = d.to;
    final ready = await EngineGate.ensure(context, reason: 'draft');
    if (!ready || !mounted) return;
    if (to == null) {
      _snack('Echo has no chat with ${d.first} to write for.');
      return;
    }
    setState(() => _writing = true);
    final source = RawData()
      ..source = to.source
      ..sender = to.sender
      ..content = d.context ?? ''
      ..timestamp = to.timestamp
      ..thread = to.thread
      ..threadTitle = to.threadTitle
      ..isGroup = false
      ..addressed = 'direct';
    final written = await writeDraft(source, d.gist);
    if (!mounted) return;
    setState(() {
      _writing = false;
      if (written != null) _text.text = written;
    });
    if (written == null) {
      _snack(
        'Echo couldn’t write this one, so these are short templates.',
      );
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final to = d.to;
    final String message;
    if (to == null) {
      await Clipboard.setData(ClipboardData(text: text));
      message = 'Copied. Paste it into ${appLabel(d.source)}.';
    } else {
      final outcome = await ReplySender.send(to, text);
      message = outcomeLine(outcome, d.source, d.name);
    }
    if (!mounted) return;
    Navigator.of(context).pop(text);
    _snack(message);
  }

  void _snack(String message) {
    if (widget.snackContext.mounted) {
      showPeopleSnack(widget.snackContext, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final templates = d.templates;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.oldStandardTt(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  PersonAvatar(name: d.name, size: 28, source: d.source),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'On ${appLabel(d.source)}, to ${d.first}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              if (d.context != null && d.context!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.dividerColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    d.context!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      height: 1.4,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _text,
                maxLines: 4,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                style: GoogleFonts.nunito(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: c.textPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: c.background,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: c.dividerColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: c.dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: c.primaryGreen, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PeoplePill(
                    label: 'Shorter',
                    icon: Symbols.short_text_rounded,
                    onTap: () => setState(() => _text.text = templates[1]),
                  ),
                  PeoplePill(
                    label: 'Warmer',
                    icon: Symbols.favorite_rounded,
                    onTap: () => setState(() => _text.text = templates[2]),
                  ),
                  PeoplePill(
                    label: _writing ? 'Writing…' : 'Write it for me',
                    icon: Symbols.auto_awesome_rounded,
                    onTap: _writing ? null : _write,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: PeoplePill(
                  label: _sending ? 'Sending…' : sendLabel(_route, d.source),
                  icon: Symbols.send_rounded,
                  filled: true,
                  onTap: _sending ? null : _send,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Goes out from your own ${appLabel(d.source)}. If there’s no '
                'notification from ${d.first} to reply through, Echo opens '
                'the chat with this typed in, and you tap send there.',
                style: GoogleFonts.nunito(
                  fontSize: 12.5,
                  height: 1.45,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
