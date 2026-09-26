import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:project_echo/features/todo/presentation/widgets/drafting_skeleton.dart';

/// The end of the briefing transcript: an offer to turn the briefing into a
/// to-do list (or bring an existing list up to date). The briefing itself
/// never makes a list; this is the only way in besides the home card.
///
/// While Echo writes, the button gives way to drafting rows; then it returns
/// home, where the list arrives.
class BriefingListPrompt extends StatefulWidget {
  const BriefingListPrompt({super.key});

  @override
  State<BriefingListPrompt> createState() => _BriefingListPromptState();
}

class _BriefingListPromptState extends State<BriefingListPrompt> {
  bool _working = false;
  bool _upToDate = false;

  Future<void> _run(TodoState s) async {
    HapticFeedback.lightImpact();
    final cubit = context.read<TodoCubit>();
    final navigator = Navigator.of(context, rootNavigator: true);

    if (s.hasList && s.pendingNew == 0) {
      setState(() => _upToDate = true);
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      if (mounted) setState(() => _upToDate = false);
      return;
    }

    setState(() => _working = true);
    await (s.hasList ? cubit.update(reveal: false) : cubit.make(reveal: false));
    if (mounted) navigator.pop();
    // Let the route finish sliding away so the list arrives on screen.
    await Future<void>.delayed(
      AppMotion.slow + const Duration(milliseconds: 80),
    );
    cubit.revealHeld();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BlocBuilder<TodoCubit, TodoState>(
      builder: (context, s) {
        final Widget content;
        if (_working) {
          content = Column(
            key: const ValueKey('working'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _note(
                context,
                s.hasList
                    ? 'Adding ${s.pendingNew} new notification${s.pendingNew == 1 ? '' : 's'} to your list…'
                    : 'Writing your list…',
                green: true,
              ),
              const SizedBox(height: 14),
              DraftingSkeleton(rows: s.hasList ? 2 : 4, writing: true),
            ],
          );
        } else if (_upToDate) {
          content = _note(
            context,
            'Your list is already up to date.',
            green: true,
            key: const ValueKey('uptodate'),
          );
        } else {
          content = Column(
            key: const ValueKey('offer'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _note(
                context,
                s.hasList
                    ? 'Something new since your list?'
                    : 'Want this as a checklist?',
              ),
              const SizedBox(height: 10),
              _OfferButton(
                title: s.hasList ? 'Update my to-do list' : 'Make a to-do list',
                subtitle: s.hasList
                    ? 'Only new notifications. Nothing on your list is removed.'
                    : 'Today and tomorrow, from this briefing',
                onTap: () => _run(s),
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).pop(),
                  style: TextButton.styleFrom(foregroundColor: c.textSecondary),
                  child: Text(
                    'Back to home',
                    style: GoogleFonts.nunito(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return Container(
          margin: const EdgeInsets.only(top: 28),
          padding: const EdgeInsets.only(top: 22),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: c.dividerColor.withValues(alpha: 0.7)),
            ),
          ),
          child: AnimatedSwitcher(
            duration: AppMotion.medium,
            switchInCurve: AppMotion.emphasized,
            child: content,
          ),
        );
      },
    );
  }

  Widget _note(
    BuildContext context,
    String text, {
    bool green = false,
    Key? key,
  }) => Text(
    text,
    key: key,
    style: GoogleFonts.nunito(
      fontSize: 14,
      fontWeight: green ? FontWeight.w700 : FontWeight.w400,
      color: green ? context.colors.primaryGreen : context.colors.textSecondary,
    ),
  );
}

/// Same shape and weight as the home screen's primary action card.
class _OfferButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _OfferButton({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = context.colors.textInverse;
    return Material(
      color: context.colors.textPrimary,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.nunito(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: fg,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: fg.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Icon(Icons.checklist_rounded, color: fg, size: 30),
            ],
          ),
        ),
      ),
    );
  }
}
