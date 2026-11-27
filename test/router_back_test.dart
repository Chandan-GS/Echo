import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/core/presentation/widgets/router_back.dart';

/// A shell like Echo's (MainScaffold): tabs drawn by the shell, routes only
/// marking which.
GoRouter _router() => GoRouter(
  initialLocation: '/echo',
  routes: [
    GoRoute(
      path: '/over',
      builder: (_, _) => const Scaffold(body: Text('over')),
    ),
    ShellRoute(
      builder: (context, state, child) {
        final home = state.uri.path == '/echo';
        return RouterBack(
          onBack: home ? null : () => context.go('/echo'),
          child: Stack(
            children: [
              // As MainScaffold mounts it: the shell Navigator, muted.
              Offstage(
                child: NotificationListener<NavigationNotification>(
                  onNotification: (_) => true,
                  child: child,
                ),
              ),
              Text(state.uri.path),
            ],
          ),
        );
      },
      routes: [
        for (final p in ['/echo', '/todo'])
          GoRoute(path: p, builder: (_, _) => const SizedBox()),
      ],
    ),
  ],
);

void main() {
  late List<String> systemCalls;
  // What Android was last told: whether Flutter handles back (true) or
  // Android should close the app on it (false).
  bool? frameworkHandlesBack;

  setUp(() {
    systemCalls = [];
    frameworkHandlesBack = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          systemCalls.add(call.method);
          if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
            frameworkHandlesBack = call.arguments as bool;
          }
          return null;
        });
  });

  Future<GoRouter> pump(WidgetTester tester) async {
    // WidgetsApp only reports to Android once the app is running.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  bool quit() => systemCalls.contains('SystemNavigator.pop');

  testWidgets('back on another tab goes Home instead of quitting', (
    tester,
  ) async {
    final router = await pump(tester);
    router.go('/todo');
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('/echo'), findsOneWidget);
    expect(quit(), isFalse);
  });

  testWidgets('Android hands back to Flutter only off Home', (tester) async {
    final router = await pump(tester);
    expect(frameworkHandlesBack, isNot(true));

    router.go('/todo');
    await tester.pumpAndSettle();
    expect(frameworkHandlesBack, isTrue);

    router.go('/echo');
    await tester.pumpAndSettle();
    expect(frameworkHandlesBack, isFalse);
  });

  testWidgets('back on Home leaves the app', (tester) async {
    await pump(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(quit(), isTrue);
  });

  testWidgets('a screen pushed over the tabs closes first', (tester) async {
    final router = await pump(tester);
    router.go('/todo');
    await tester.pumpAndSettle();
    router.push('/over');
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('over'), findsNothing);
    expect(find.text('/todo'), findsOneWidget);
    expect(quit(), isFalse);
  });
}
