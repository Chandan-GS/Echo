import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_state.dart';
import 'package:project_echo/core/services/schedule_service.dart';

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit() : super(SettingsState.initial()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load theme — clamp against corrupted/out-of-range persisted values so
      // ThemeMode.values[...] can't throw a RangeError and abort loading.
      final themeIndex = prefs.getInt('theme_mode') ?? 0;
      final themeMode = ThemeMode
          .values[themeIndex.clamp(0, ThemeMode.values.length - 1)];

      // Load speech rate
      final speechRate = prefs.getDouble('speech_rate') ?? 0.5;

      // Load AI engine
      final isOfflineEngine = prefs.getBool('is_offline_engine') ?? true;
      final geminiApiKey = prefs.getString('gemini_api_key') ?? '';
      final briefingTimes = prefs.getStringList('briefing_times') ?? ['07:00'];

      emit(
        state.copyWith(
          themeMode: themeMode,
          speechRate: speechRate,
          isOfflineEngine: isOfflineEngine,
          geminiApiKey: geminiApiKey,
          briefingTimes: briefingTimes,
        ),
      );
    } catch (e) {
      debugPrint('Failed to load settings, keeping defaults: $e');
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
    emit(state.copyWith(themeMode: mode));
  }

  Future<void> setSpeechRate(double rate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('speech_rate', rate);
    emit(state.copyWith(speechRate: rate));
  }

  Future<void> setAiEngine({required bool isOffline}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_offline_engine', isOffline);
    emit(state.copyWith(isOfflineEngine: isOffline));
  }

  Future<void> setGeminiApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', apiKey);
    emit(state.copyWith(geminiApiKey: apiKey));
  }

  Future<void> addBriefingTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    final times = List<String>.from(state.briefingTimes);
    if (!times.contains(time)) {
      times.add(time);
      times.sort();
      await prefs.setStringList('briefing_times', times);
      await ScheduleService.updateSchedules(times);
      emit(state.copyWith(briefingTimes: times));
    }
  }

  /// Replaces the entire briefing schedule (used by onboarding personalization
  /// to set a single chosen time rather than appending to the default).
  Future<void> setBriefingTimes(List<String> times) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = List<String>.from(times)..sort();
    await prefs.setStringList('briefing_times', sorted);
    await ScheduleService.updateSchedules(sorted);
    emit(state.copyWith(briefingTimes: sorted));
  }

  Future<void> removeBriefingTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    final times = List<String>.from(state.briefingTimes);
    if (times.remove(time)) {
      await prefs.setStringList('briefing_times', times);
      await ScheduleService.updateSchedules(times);
      emit(state.copyWith(briefingTimes: times));
    }
  }
}
