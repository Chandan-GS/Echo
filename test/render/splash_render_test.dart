// Draws the phone's splash image from the app's own first frame, so the
// splash hands over without a seam (see LaunchEcho). Skipped unless asked:
// SPLASH_RES=android/app/src/main/res flutter test test/render/splash_render_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/presentation/launch_echo.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';

/// Android's densities: folder, and pixels per dp.
const _densities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

void main() {
  final res = Platform.environment['SPLASH_RES'];

  testWidgets(
    'the splash: Echo asleep, as the app first draws him',
    (tester) async {
      const box = LaunchEcho.splashBox;
      const size = LaunchEcho.mascotSize;
      tester.view.physicalSize = const Size(box, box);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();

      // As the welcome screen and the wake-up over Home first draw him.
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: const ColoredBox(
            color: LaunchEcho.ground,
            child: Center(
              child: SizedBox(
                width: size,
                height: size,
                child: Opacity(
                  opacity: LaunchEcho.asleep,
                  child: EchoMascot(
                    state: EchoState.sleeping,
                    size: size,
                    showRings: false,
                    glow: false,
                    zzz: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      for (final MapEntry(key: folder, value: ratio) in _densities.entries) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: ratio);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$res/drawable-$folder/splash_echo.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
    },
    skip: res == null,
  );
}
