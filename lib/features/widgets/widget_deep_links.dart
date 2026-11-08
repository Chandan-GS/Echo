import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/core/services/widget_refresh_service.dart';
import 'package:project_echo/features/people/data/people_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opens the screen a home-screen widget was tapped for. Native code leaves
/// the target in prefs (`pending_widget_route`), so a cold start and a tap
/// on a running app go the same way; see MainActivity.handleWidgetLaunchIntent.
class WidgetDeepLinks {
  WidgetDeepLinks._();

  static const _channel = MethodChannel('project_echo/widget');
  static const _pendingKey = 'pending_widget_route';

  static GoRouter? _router;
  static bool _ready = false;

  /// Starts listening. During onboarding there's nowhere to go, so a pending
  /// tap is dropped.
  static void attach(GoRouter router, {required bool isOnboardingFinished}) {
    if (!Platform.isAndroid) return;
    _router = router;
    _ready = isOnboardingFinished;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openRoute') await _drain();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
    WidgetRefreshService.watch();
  }

  static Future<void> _drain() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_pendingKey);
    if (raw == null) return;
    await prefs.remove(_pendingKey);
    if (!_ready) return;
    try {
      _open(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Ignoring a widget link: $e');
    }
  }

  static void _open(Map<String, dynamic> link) {
    final router = _router;
    final route = link['route'] as String?;
    if (router == null || route == null) return;
    final here = router.routerDelegate.currentConfiguration.uri.path;
    switch (route) {
      case '/person':
        final sender = link['sender'] as String? ?? '';
        final source = link['source'] as String? ?? '';
        if (sender.isEmpty) {
          router.go('/echo');
        } else {
          router.push('/person', extra: personKeyFor(sender, source));
        }
      case '/echo':
        if (here != '/echo') router.go('/echo');
      default:
        if (here != route) router.push(route);
    }
  }
}
