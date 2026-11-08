import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';

/// Pieces Today's sections and sheets share.

/// A section's title in the masthead serif, with a link or note at the right.
class TodaySectionHead extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final String? note;

  /// Sits before the link: To-do's small +.
  final Widget? extra;

  const TodaySectionHead(
    this.title, {
    super.key,
    this.action,
    this.onAction,
    this.note,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 30, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.oldStandardTt(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.1,
                color: c.textPrimary,
              ),
            ),
          ),
          ?extra,
          if (action != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  action!,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: c.primaryGreen,
                  ),
                ),
              ),
            )
          else if (note != null)
            Text(
              note!,
              style: GoogleFonts.nunito(fontSize: 13, color: c.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// How the age of a wait is coloured: green, amber, rust.
({Color bg, Color fg}) ageColors(BuildContext context, int age) {
  final dark = context.isDarkMode;
  return switch (age) {
    0 =>
      dark
          ? (bg: const Color(0xFF6EBC76), fg: const Color(0xFF16301B))
          : (bg: const Color(0xFFD1E6D3), fg: const Color(0xFF16301B)),
    1 =>
      dark
          ? (bg: const Color(0xFF4A3E22), fg: const Color(0xFFE6C77A))
          : (bg: const Color(0xFFFDE49B), fg: const Color(0xFF6B5210)),
    _ =>
      dark
          ? (bg: const Color(0xFF4A2A24), fg: const Color(0xFFF0A08E))
          : (bg: const Color(0xFFFBDCD4), fg: const Color(0xFFA3402D)),
  };
}

/// A small rounded label: an age, or how a held reply stands.
class AgeTag extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;

  const AgeTag({
    super.key,
    required this.text,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.nunito(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        height: 1.2,
        color: foreground,
      ),
    ),
  );
}

/// A hairline dashed outline, as Flutter has no dashed border of its own.
class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const DashedBorderPainter({required this.color, required this.radius});

  static const _dash = 5.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          Radius.circular(radius),
        ),
      );
    for (final metric in outline.computeMetrics()) {
      var at = 0.0;
      while (at < metric.length) {
        canvas.drawPath(metric.extractPath(at, at + _dash), paint);
        at += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

/// Opens one of Today's sheets over the dock.
Future<T?> showTodaySheet<T>(BuildContext context, WidgetBuilder builder) {
  final c = context.colors;
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: c.surface,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 460),
      curve: Cubic(0.2, 0.9, 0.25, 1),
      reverseDuration: Duration(milliseconds: 240),
      reverseCurve: Curves.easeInCubic,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: builder,
  );
}

/// A sheet's scrollable body: the grab bar, then [children], clear of the
/// keyboard and the system bar.
class TodaySheetBody extends StatelessWidget {
  final List<Widget> children;
  const TodaySheetBody({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          media.viewInsets.bottom + media.padding.bottom + 26,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                decoration: BoxDecoration(
                  color: context.colors.dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A short message above the dock.
void showTodayToast(
  BuildContext context,
  String message, {
  String? action,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final dock = MediaQuery.paddingOf(context).bottom;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(20, 0, 20, dock),
        content: Text(message),
        persist: false,
        action: action == null
            ? null
            : SnackBarAction(label: action, onPressed: onAction ?? () {}),
      ),
    );
}

/// The sheets' heading: "Why Neha is here".
TextStyle todaySheetTitle(BuildContext context) => GoogleFonts.oldStandardTt(
  fontSize: 26,
  fontWeight: FontWeight.w700,
  height: 1.15,
  color: context.colors.textPrimary,
);

/// The sheets' line under the heading.
TextStyle todaySheetSub(BuildContext context) => GoogleFonts.nunito(
  fontSize: 14,
  fontWeight: FontWeight.w600,
  height: 1.4,
  color: context.colors.textSecondary,
);

/// A quiet box quoting the message being talked about.
class QuoteBox extends StatelessWidget {
  final String who;
  final String text;
  const QuoteBox({super.key, required this.who, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$who: ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(text: '“$text”'),
          ],
        ),
        style: GoogleFonts.nunito(
          fontSize: 14,
          height: 1.45,
          color: c.textPrimary,
        ),
      ),
    );
  }
}
