import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:project_echo/core/services/streak_service.dart';
import 'package:project_echo/features/profile/data/week_card.dart';
import 'package:project_echo/features/profile/data/week_stats.dart';
import 'package:project_echo/features/profile/presentation/widgets/week_card.dart';
import 'package:share_plus/share_plus.dart';

/// Draws the [WeekCard] to a PNG without ever putting it on screen, and
/// hands it to Android's share sheet with a one-line caption.
class WeekCardShare {
  /// Pixels per logical pixel: the 360 × 450 card comes out 1080 × 1350.
  static const pixelRatio = 3.0;

  /// Reads this week's counts and the streak, as Profile shows them.
  /// [week] reuses counts already loaded; [streak] overrides the stored
  /// streak, for the celebration that has just counted it.
  static Future<WeekCardData> load({WeekStats? week, int? streak}) async {
    final now = DateTime.now();
    final service = StreakService();
    return WeekCardData.assemble(
      week: week ?? await WeekStats.load(now),
      heardDates: await service.heardDates(),
      streak: streak ?? (await service.current()).current,
      now: now,
    );
  }

  /// Renders the card and opens the share sheet. [source] names where the
  /// share started (profile or streak) for the anonymous event. If the
  /// card can't be drawn or shared, says so in a snack bar.
  static Future<void> share(
    BuildContext context,
    WeekCardData data, {
    required String source,
  }) async {
    final view = View.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      final png = await render(WeekCard(data: data), WeekCard.size, view);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/echo-week.png');
      await file.writeAsBytes(png, flush: true);
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: data.shareText,
          sharePositionOrigin: origin,
        ),
      );
      if (result.status != ShareResultStatus.dismissed) {
        Analytics.track('week_card_shared', {'source': source});
      }
    } catch (e) {
      debugPrint('Week card share failed: $e');
      messenger?.showSnackBar(
        const SnackBar(content: Text("Couldn't share your week just now")),
      );
    }
  }

  /// Lays [widget] out at [size] in a render tree of its own, outside the
  /// app's, paints it and returns the PNG. Fine for widgets that draw
  /// synchronously (text, paint, gradients); network images wouldn't have
  /// arrived yet.
  static Future<Uint8List> render(
    Widget widget,
    Size size,
    ui.FlutterView view,
  ) async {
    final boundary = RenderRepaintBoundary();
    final renderView = RenderView(
      view: view,
      child: RenderPositionedBox(child: boundary),
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(size),
        physicalConstraints: BoxConstraints.tight(size),
      ),
    );
    final pipeline = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();
    final build = BuildOwner(focusManager: FocusManager());
    final root = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: MediaQuery(
        // The card is a picture, so it's the same at any phone's settings.
        data: MediaQueryData(size: size, textScaler: TextScaler.noScaling),
        child: Directionality(textDirection: TextDirection.ltr, child: widget),
      ),
    ).attachToRenderTree(build);
    build
      ..buildScope(root)
      ..finalizeTree();
    pipeline
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
