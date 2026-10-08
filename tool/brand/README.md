# Echo's icons and splash

Every app icon is drawn from one page, `echo_icons.html`, using the mascot's own drawing (the same as `EchoMascot` in the app, as ported for the website): Echo's pearl body fills the icon edge to edge, looking up, so whatever shape a launcher crops, it's him.

## Redrawing the icons

```bash
node tool/brand/render.mjs ../echo-landing-page   # the website's folder is optional
```

It opens the page in headless Chrome (set `CHROME` if it isn't at the usual macOS path) and writes:

| Where | What |
|:--|:--|
| `android/app/src/main/res/drawable-*dpi/` | the adaptive icon's layers: `ic_launcher_background` (his body), `ic_launcher_foreground` (his eyes), `ic_launcher_monochrome` (his silhouette, for Android 13+ themed icons); and `ic_notification`, the white status-bar icon |
| `android/app/src/main/res/mipmap-*dpi/ic_launcher.png` | the whole icon, for anything that can't use the adaptive one |
| `ios/…/AppIcon.appiconset/`, `macos/…/AppIcon.appiconset/` | every size, square |
| `windows/runner/resources/app_icon.ico` | 16 to 256 px in one file |
| `assets/logo.png` | the desktop sidebar's logo |
| `store_assets/` | the Play Store icon (512 px) and the 1024 px original |
| `docs/logo.png` | the README's logo: Echo round, on a transparent ground |
| the website's `public/` | `logo.png` and the two favicons (bump their `?v=` in its `app/layout.tsx`) |

Open `echo_icons.html` in a browser to see them all.

## The splash

The phone's splash shows Echo asleep, exactly as the app's first frame draws him (`lib/core/presentation/launch_echo.dart`), so the hand-over to the app can't be seen: first time, the welcome screen carries on from it; after that, he wakes and fades into Home (`launch_wake.dart`). Its image is drawn by Flutter itself:

```bash
SPLASH_RES=android/app/src/main/res flutter test test/render/splash_render_test.dart
```

Draw it again after changing anything in `LaunchEcho` or how the mascot looks asleep.
