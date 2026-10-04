import 'package:flutter/widgets.dart';

/// Echo as the phone's splash screen shows him: asleep, dimmed, centred on
/// the welcome screen's ground. The welcome screen (and, for someone who has
/// set up already, the wake-up over Home) starts from exactly this frame, so
/// the splash hands over without a visible seam.
///
/// The splash images (android/app/src/main/res/drawable-*/splash_echo.png)
/// are drawn from this frame by test/render/splash_render_test.dart; change
/// anything here and draw them again.
abstract final class LaunchEcho {
  /// The ground behind him, here and in the splash.
  static const ground = Color(0xFF0D0D0D);

  /// How wide his orb is, in logical pixels. Android 12+ shows a splash icon
  /// at 288 dp and keeps what's inside a 192 dp circle; this sits well within.
  static const orbDiameter = 160.0;

  /// The [EchoMascot] size that draws an orb [orbDiameter] wide (without
  /// rings, its orb's radius is 56/180 of its size).
  static const mascotSize = orbDiameter * 180 / 112;

  /// How bright he is while asleep.
  static const asleep = 0.55;

  /// The splash icon's square, in logical pixels.
  static const splashBox = 288.0;

  /// Where the splash centres him, in this view's coordinates: the middle of
  /// the whole screen. The same as the view's middle when the app draws edge
  /// to edge; lower when the view stops above a navigation bar (older
  /// Android with buttons), which the splash doesn't.
  static double centerY(BuildContext context, double viewHeight) {
    final display = View.of(context).display;
    final screen = display.size.height / display.devicePixelRatio;
    final middle = screen > 0 ? screen / 2 : viewHeight / 2;
    return middle.clamp(0, viewHeight);
  }
}
