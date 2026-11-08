import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/profile/data/week_stats.dart';

/// The four figures on the shared picture, built from counts alone so a name
/// or a message can't get onto it.
List<(String, String)> weekCardFigures(WeekStats week, int streak) => [
  ('${week.peopleAnswered}', 'people answered within a day'),
  ('${week.todosDone}/${week.todosDue}', 'to-dos done'),
  ('${week.held}', 'held in quiet hours'),
  ('$streak ${streak == 1 ? 'day' : 'days'}', 'streak'),
];

/// "Share your week": a picture with only numbers and Echo on it.
Future<void> showShareWeekSheet(
  BuildContext context, {
  required WeekStats week,
  required int streak,
  required String range,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: context.colors.background,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
  ),
  builder: (_) => _ShareWeekSheet(week: week, streak: streak, range: range),
);

class _ShareWeekSheet extends StatefulWidget {
  final WeekStats week;
  final int streak;
  final String range;
  const _ShareWeekSheet({
    required this.week,
    required this.streak,
    required this.range,
  });

  @override
  State<_ShareWeekSheet> createState() => _ShareWeekSheetState();
}

class _ShareWeekSheetState extends State<_ShareWeekSheet> {
  static const _channel = MethodChannel('project_echo/reply');

  final _card = GlobalKey();
  bool _busy = false;

  /// Said here, because a snackbar would sit behind this sheet.
  String? _failed;

  Future<Uint8List?> _png() async {
    final boundary =
        _card.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    if (boundary.debugNeedsPaint) await WidgetsBinding.instance.endOfFrame;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  Future<void> _send(String method, String failed) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = null;
    });
    var ok = false;
    try {
      final png = await _png();
      if (png != null && Platform.isAndroid) {
        ok = await _channel.invokeMethod<bool>(method, {'png': png}) ?? false;
      }
    } catch (e) {
      debugPrint('Sharing the week failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _failed = failed;
    });
    if (!ok || method != 'saveCard') return;
    final messenger = ScaffoldMessenger.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(20, 0, 20, bottom + 72),
          content: const Text('Saved to your photos'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Share your week',
              style: GoogleFonts.oldStandardTt(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'A picture of your week. Only numbers, no names or messages.',
              style: GoogleFonts.nunito(
                fontSize: 14.5,
                height: 1.4,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.15,
                  child: RepaintBoundary(
                    key: _card,
                    child: _WeekCard(
                      figures: weekCardFigures(widget.week, widget.streak),
                      range: widget.range,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _failed ?? 'Saved as an image. Nothing from your chats is in it.',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 12.5,
                height: 1.4,
                color: _failed == null ? c.textSecondary : context.warmAccent,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _Action(
                    label: 'Save',
                    icon: Symbols.download_rounded,
                    onTap: _busy
                        ? null
                        : () => _send(
                            'saveCard',
                            'Couldn’t save the picture. Try Share instead.',
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Action(
                    label: 'Share',
                    icon: Symbols.ios_share_rounded,
                    filled: true,
                    onTap: _busy
                        ? null
                        : () => _send(
                            'shareCard',
                            'Couldn’t open the share sheet.',
                          ),
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

class _Action extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;
  const _Action({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = filled ? c.textInverse : c.textPrimary;
    return Material(
      color: filled ? c.buttonDark : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: filled ? BorderSide.none : BorderSide(color: c.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The picture itself: green in both themes, so it looks the same once it's
/// left the phone.
class _WeekCard extends StatelessWidget {
  final List<(String, String)> figures;
  final String range;
  const _WeekCard({required this.figures, required this.range});

  @override
  Widget build(BuildContext context) {
    Widget figure((String, String) f) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          f.$1,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.oldStandardTt(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            height: 1,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          f.$2,
          style: GoogleFonts.nunito(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.3,
            color: Colors.white.withValues(alpha: 0.82),
          ),
        ),
      ],
    );
    final foot = GoogleFonts.nunito(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: Colors.white.withValues(alpha: 0.85),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF49884F), Color(0xFF2A4F2E)],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned(
              right: -12,
              top: -14,
              child: EchoMascot(state: EchoState.happy, size: 62, isDark: true),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MY WEEK WITH ECHO',
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 56),
                  child: Text(
                    range,
                    style: GoogleFonts.oldStandardTt(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < figures.length; i += 2) ...[
                  if (i > 0) const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: figure(figures[i])),
                      const SizedBox(width: 14),
                      Expanded(child: figure(figures[i + 1])),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.22),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Echo', style: foot),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Nobody left hanging',
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: foot,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
