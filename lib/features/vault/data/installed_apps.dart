import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:project_echo/core/services/source_packages.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An app on the phone with a launcher icon.
class InstalledApp {
  final String package;
  final String label;

  /// Android's ApplicationInfo.category; -1 when the app doesn't set one.
  final int category;

  const InstalledApp({
    required this.package,
    required this.label,
    required this.category,
  });

  /// Games, music, video and photo apps: off by default in onboarding.
  bool get quietByDefault => category >= 0 && category <= 3;
}

/// The phone's apps, from Android (see AppIcons.kt / MainActivity.kt).
class InstalledApps {
  InstalledApps._();

  static const _channel = MethodChannel('project_echo/app_icons');

  /// Every launcher app, A–Z. Also saves package → name so categories from
  /// before packages were recorded can be matched to their app later.
  static Future<List<InstalledApp>> load() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _channel.invokeListMethod<Map>('installedApps') ?? [];
      final apps =
          raw
              .map(
                (m) => InstalledApp(
                  package: m['package'] as String,
                  label: m['label'] as String,
                  category: m['category'] as int? ?? -1,
                ),
              )
              .toList()
            ..sort(
              (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
            );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        SourcePackages.labelsKey,
        jsonEncode({for (final a in apps) a.package: a.label}),
      );
      return apps;
    } catch (_) {
      return const [];
    }
  }

  /// Apps with a notification in the shade right now, busiest first. Empty
  /// until notification access is granted.
  static Future<List<String>> activePackages() async {
    if (!Platform.isAndroid) return const [];
    try {
      return await _channel.invokeListMethod<String>('activePackages') ?? [];
    } catch (_) {
      return const [];
    }
  }
}
