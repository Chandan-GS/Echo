import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/widgets/person_avatar.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/person_photos.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';

/// Change the picture Echo shows for someone: a photo from the phone, their
/// initials, or back to the one from their notifications. Does nothing on a
/// computer, or for a name that can't be filed (empty, or "Sender · Group").
Future<void> showPersonPhotoSheet(
  BuildContext context, {
  required String name,
  required String? source,
}) async {
  if (!PersonPhotos.supported || source == null) return;
  if (photoKey(name, source) == null) return;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: context.colors.background,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 460),
      curve: Cubic(0.2, 0.9, 0.25, 1),
      reverseDuration: Duration(milliseconds: 240),
      reverseCurve: Curves.easeInCubic,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    builder: (context) => _PhotoSheet(name: name, source: source),
  );
}

class _PhotoSheet extends StatefulWidget {
  final String name;
  final String source;

  const _PhotoSheet({required this.name, required this.source});

  @override
  State<_PhotoSheet> createState() => _PhotoSheetState();
}

class _PhotoSheetState extends State<_PhotoSheet> {
  PersonPhoto _photo = PersonPhoto.none;
  bool _working = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    PersonPhotos.load(widget.name, widget.source).then((photo) {
      if (mounted) setState(() => _photo = photo);
    });
  }

  Future<void> _run(Future<String?> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _problem = null;
    });
    final problem = await action();
    if (!mounted) return;
    if (problem == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _working = false;
        _problem = problem.isEmpty ? null : problem;
      });
    }
  }

  Future<String?> _choose() async {
    final outcome = await PersonPhotos.choose(widget.name, widget.source);
    return switch (outcome) {
      PickOutcome.ok => null,
      PickOutcome.cancel || PickOutcome.busy => '',
      PickOutcome.unreadable => "Couldn't read that photo. Try another one.",
      PickOutcome.unavailable => "This phone doesn't have a photo picker.",
    };
  }

  Future<String?> _useInitials() async =>
      await PersonPhotos.useInitials(widget.name, widget.source)
      ? null
      : "Couldn't change that. Try again.";

  Future<String?> _reset() async =>
      await PersonPhotos.reset(widget.name, widget.source)
      ? null
      : "Couldn't change that. Try again.";

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final showReset = _photo.choice != PhotoChoice.auto && _photo.hasDp;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: c.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                PersonAvatar(
                  name: widget.name,
                  size: 52,
                  source: widget.source,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.oldStandardTt(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Their picture stays on this phone.',
                        style: GoogleFonts.nunito(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Option(
              icon: Symbols.add_photo_alternate_rounded,
              title: 'Choose a photo',
              onTap: () => _run(_choose),
            ),
            const SizedBox(height: 8),
            _Option(
              icon: Symbols.face_rounded,
              title: 'Use initials',
              selected: _photo.choice == PhotoChoice.initials,
              onTap: () => _run(_useInitials),
            ),
            if (showReset) ...[
              const SizedBox(height: 8),
              _Option(
                icon: Symbols.undo_rounded,
                title: 'Reset to their DP',
                onTap: () => _run(_reset),
              ),
            ],
            AnimatedSize(
              duration: AppMotion.fast,
              curve: AppMotion.standard,
              alignment: Alignment.topCenter,
              child: _problem == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _problem!,
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _Option({
    required this.icon,
    required this.title,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressFeedback(
      scale: 0.98,
      haptic: false,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        decoration: BoxDecoration(
          color: selected
              ? Color.lerp(
                  c.surface,
                  context.selectionFill,
                  context.isDarkMode ? 0.12 : 0.3,
                )
              : c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? c.primaryGreen
                : c.dividerColor.withValues(alpha: 0.7),
            width: 1.5,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, size: 22, color: c.textSecondary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.nunito(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Symbols.check_rounded,
                      size: 20,
                      color: c.primaryGreen,
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
