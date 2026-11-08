import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/cubit/ask_ai_cubit.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/people/presentation/widgets/people_parts.dart'
    show appLabel;

/// Echo with nothing to write with: the messages that matched, as they are,
/// and a way to get them in sentences instead.
class SearchResults extends StatelessWidget {
  final ChatMessage message;
  final void Function(RawData source)? onOpen;
  final VoidCallback? onWrite;

  const SearchResults({
    super.key,
    required this.message,
    this.onOpen,
    this.onWrite,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final matches = message.ragSources;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.text.isNotEmpty)
          Text(
            message.text,
            style: GoogleFonts.nunito(
              fontSize: 16,
              height: 1.5,
              color: c.textPrimary,
            ),
          )
        else ...[
          Text(
            matches.length == 1
                ? '1 matching message'
                : '${matches.length} matching messages',
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          for (final e in matches)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MatchCard(entry: e, onOpen: onOpen),
            ),
        ],
        if (onWrite != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: PressFeedback(
              child: TextButton(
                onPressed: onWrite,
                style: TextButton.styleFrom(
                  foregroundColor: c.primaryGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Get a written answer instead',
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MatchCard extends StatelessWidget {
  final RawData entry;
  final void Function(RawData source)? onOpen;
  const _MatchCard({required this.entry, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = GoogleFonts.nunito(fontSize: 12.5, color: c.textSecondary);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen == null ? null : () => onOpen!(entry),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SourceBadge(entry, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      appLabel(entry.source),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    matchTimeLabel(entry.timestamp, DateTime.now()),
                    style: small,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                entry.who.isEmpty ? entry.source : entry.who,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                entry.content,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  height: 1.4,
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

/// When a matched message arrived: a clock time today, otherwise the day.
String matchTimeLabel(DateTime t, DateTime now) {
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(t.year, t.month, t.day)).inDays;
  if (days <= 0) return clockLabel(t);
  if (days == 1) return 'Yesterday';
  const week = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (days < 7) return week[t.weekday - 1];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${t.day} ${months[t.month - 1]}';
}

/// In place of something Echo can't write yet, and the way to set that up.
class EngineGateCard extends StatelessWidget {
  final String reason;
  final VoidCallback? onChoose;

  /// A reply: an empty draft to type into, no engine needed.
  final VoidCallback? onWriteMyself;

  const EngineGateCard({
    super.key,
    required this.reason,
    this.onChoose,
    this.onWriteMyself,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final action = GoogleFonts.nunito(
      fontSize: 13.5,
      fontWeight: FontWeight.w800,
      color: c.primaryGreen,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Symbols.edit_note_rounded,
              size: 20,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reason == 'draft'
                      ? 'Choose how Echo writes, and it will draft this.'
                      : 'Choose how Echo writes, and it will answer this.',
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
                  ),
                ),
                if (onChoose != null || onWriteMyself != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 18,
                    children: [
                      if (onChoose != null)
                        InkWell(
                          onTap: onChoose,
                          child: Text('Choose', style: action),
                        ),
                      if (onWriteMyself != null)
                        InkWell(
                          onTap: onWriteMyself,
                          child: Text(
                            'Write it myself',
                            style: action.copyWith(color: c.textSecondary),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
