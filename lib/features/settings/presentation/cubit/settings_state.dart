import 'package:flutter/material.dart';

class SettingsState {
  final ThemeMode themeMode;
  final double speechRate;
  final bool isOfflineEngine;
  final String geminiApiKey;
  final List<String> briefingTimes;

  /// Phone-first, computer-optional: when true, the phone prefers offloading
  /// briefing/Ask Echo generation to a discovered desktop Echo Engine on the
  /// same network, falling back to [isOfflineEngine] ? on-device : Gemini
  /// whenever no desktop engine is reachable. Purely additive — does not
  /// change the meaning of the existing on-device/Gemini choice.
  final bool preferDesktopEngine;

  /// Last-known reachable desktop engine address (e.g. "192.168.1.12:8790"),
  /// cached after discovery so we don't have to re-broadcast every time. Also
  /// settable manually as a fallback if UDP broadcast discovery is blocked.
  final String? desktopEngineHost;

  /// The desktop's human-readable system name, learned during QR pairing
  /// (e.g. "Chandan's MacBook Pro"). Null for a plain broadcast-discovered
  /// connection that was never paired — the UI falls back to showing the
  /// raw host in that case.
  final String? desktopEngineName;

  /// The desktop-side counterpart of [preferDesktopEngine]: whether THIS
  /// machine (when running the macOS/Windows build) should run the Echo
  /// Engine service for other devices to reach. Meaningless on a phone build,
  /// but kept as a plain setting rather than platform-conditional storage so
  /// it round-trips normally through the same prefs/Cubit machinery.
  final bool runDesktopEngineHere;

  const SettingsState({
    required this.themeMode,
    required this.speechRate,
    required this.isOfflineEngine,
    this.geminiApiKey = '',
    this.briefingTimes = const ['07:00'],
    this.preferDesktopEngine = false,
    this.desktopEngineHost,
    this.desktopEngineName,
    this.runDesktopEngineHere = false,
  });

  factory SettingsState.initial() {
    return const SettingsState(
      themeMode: ThemeMode.system,
      speechRate: 0.5,
      isOfflineEngine: true,
      geminiApiKey: '',
      briefingTimes: ['07:00'],
      preferDesktopEngine: false,
      desktopEngineHost: null,
      desktopEngineName: null,
      runDesktopEngineHere: false,
    );
  }

  SettingsState copyWith({
    ThemeMode? themeMode,
    double? speechRate,
    bool? isOfflineEngine,
    String? geminiApiKey,
    List<String>? briefingTimes,
    bool? preferDesktopEngine,
    String? desktopEngineHost,
    String? desktopEngineName,
    bool? runDesktopEngineHere,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      speechRate: speechRate ?? this.speechRate,
      isOfflineEngine: isOfflineEngine ?? this.isOfflineEngine,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      briefingTimes: briefingTimes ?? this.briefingTimes,
      preferDesktopEngine: preferDesktopEngine ?? this.preferDesktopEngine,
      desktopEngineHost: desktopEngineHost ?? this.desktopEngineHost,
      desktopEngineName: desktopEngineName ?? this.desktopEngineName,
      runDesktopEngineHere: runDesktopEngineHere ?? this.runDesktopEngineHere,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SettingsState &&
        other.themeMode == themeMode &&
        other.speechRate == speechRate &&
        other.isOfflineEngine == isOfflineEngine &&
        other.geminiApiKey == geminiApiKey &&
        other.preferDesktopEngine == preferDesktopEngine &&
        other.desktopEngineHost == desktopEngineHost &&
        other.desktopEngineName == desktopEngineName &&
        other.runDesktopEngineHere == runDesktopEngineHere &&
        _listEquals(other.briefingTimes, briefingTimes);
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      themeMode.hashCode ^
      speechRate.hashCode ^
      isOfflineEngine.hashCode ^
      geminiApiKey.hashCode ^
      briefingTimes.hashCode ^
      preferDesktopEngine.hashCode ^
      desktopEngineHost.hashCode ^
      desktopEngineName.hashCode ^
      runDesktopEngineHere.hashCode;
}
