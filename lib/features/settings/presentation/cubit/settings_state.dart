import 'package:flutter/material.dart';

class SettingsState {
  final ThemeMode themeMode;
  final double speechRate;
  final bool isOfflineEngine;
  final String geminiApiKey;
  final List<String> briefingTimes;

  const SettingsState({
    required this.themeMode,
    required this.speechRate,
    required this.isOfflineEngine,
    this.geminiApiKey = '',
    this.briefingTimes = const ['07:00'],
  });

  factory SettingsState.initial() {
    return const SettingsState(
      themeMode: ThemeMode.system,
      speechRate: 0.5,
      isOfflineEngine: true,
      geminiApiKey: '',
      briefingTimes: const ['07:00'],
    );
  }

  SettingsState copyWith({
    ThemeMode? themeMode,
    double? speechRate,
    bool? isOfflineEngine,
    String? geminiApiKey,
    List<String>? briefingTimes,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      speechRate: speechRate ?? this.speechRate,
      isOfflineEngine: isOfflineEngine ?? this.isOfflineEngine,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      briefingTimes: briefingTimes ?? this.briefingTimes,
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
      briefingTimes.hashCode;
}
