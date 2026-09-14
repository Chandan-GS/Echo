import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_state.dart';
import 'package:project_echo/core/services/schedule_service.dart';
import 'package:project_echo/core/services/echo_server_service.dart';

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
      final preferDesktopEngine =
          prefs.getBool('prefer_desktop_engine') ?? false;
      final desktopEngineHost = prefs.getString('desktop_engine_host');
      final desktopEngineName = prefs.getString('desktop_engine_name');
      final runDesktopEngineHere =
          prefs.getBool('run_desktop_engine_here') ?? false;

      emit(
        state.copyWith(
          themeMode: themeMode,
          speechRate: speechRate,
          isOfflineEngine: isOfflineEngine,
          geminiApiKey: geminiApiKey,
          briefingTimes: briefingTimes,
          preferDesktopEngine: preferDesktopEngine,
          desktopEngineHost: desktopEngineHost,
          desktopEngineName: desktopEngineName,
          runDesktopEngineHere: runDesktopEngineHere,
        ),
      );

      // Persist across restarts: if this computer was left serving as the
      // engine, actually start it on launch — otherwise the toggle reads "on"
      // while nothing is listening, and the phone can't find it.
      if (runDesktopEngineHere && (Platform.isMacOS || Platform.isWindows)) {
        await EchoServerService.instance.start();
      }
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

  Future<void> setPreferDesktopEngine(bool prefer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('prefer_desktop_engine', prefer);
    emit(state.copyWith(preferDesktopEngine: prefer));
  }

  /// Pass `null` to clear a manually-entered host and fall back to
  /// auto-discovery. (Built directly rather than via `copyWith`, since that
  /// helper's `??` pattern can't express "explicitly clear this field".) A
  /// plain broadcast-discovered host carries no known name — that's only
  /// learned through QR pairing (see [pairedWithDesktop]) — so it's cleared
  /// here too rather than leaving a stale name attached to a new address.
  Future<void> setDesktopEngineHost(String? host) async {
    final prefs = await SharedPreferences.getInstance();
    if (host == null || host.isEmpty) {
      await prefs.remove('desktop_engine_host');
      await prefs.remove('desktop_engine_name');
    } else {
      await prefs.setString('desktop_engine_host', host);
    }
    emit(
      SettingsState(
        themeMode: state.themeMode,
        speechRate: state.speechRate,
        isOfflineEngine: state.isOfflineEngine,
        geminiApiKey: state.geminiApiKey,
        briefingTimes: state.briefingTimes,
        preferDesktopEngine: state.preferDesktopEngine,
        desktopEngineHost: (host == null || host.isEmpty) ? null : host,
        desktopEngineName: (host == null || host.isEmpty) ? null : state.desktopEngineName,
        runDesktopEngineHere: state.runDesktopEngineHere,
      ),
    );
  }

  /// Called right after a successful QR pairing — records both the desktop's
  /// address and its friendly name, and opts this phone into using it (the
  /// whole point of scanning was to connect).
  Future<void> pairedWithDesktop({
    required String host,
    required String name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('prefer_desktop_engine', true);
    // Host + name themselves are already persisted by
    // DesktopEngineClient.pairViaQrPayload — this just reflects them into
    // the live Cubit state so the UI updates immediately.
    emit(
      state.copyWith(
        preferDesktopEngine: true,
        desktopEngineHost: host,
        desktopEngineName: name,
      ),
    );
  }

  /// Toggles the desktop Echo Engine service on this machine. The server
  /// starts (and becomes discoverable on the LAN) regardless of model state —
  /// a phone can connect immediately. Generation resolves the offline model
  /// fresh on every request, so it works the moment a download completes,
  /// even if that happens after the server was already running.
  Future<void> setRunDesktopEngineHere(bool run) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('run_desktop_engine_here', run);
    emit(state.copyWith(runDesktopEngineHere: run));

    if (run) {
      await EchoServerService.instance.start();
    } else {
      await EchoServerService.instance.stop();
    }
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
