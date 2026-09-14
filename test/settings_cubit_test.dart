import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsCubit theme loading', () {
    test('clamps an out-of-range persisted theme index instead of crashing',
        () async {
      // A corrupted/forward-incompatible index (>= ThemeMode.values.length)
      // must not throw a RangeError while loading.
      SharedPreferences.setMockInitialValues({
        'theme_mode': 99,
        'speech_rate': 0.9,
      });
      final cubit = SettingsCubit();
      await cubit.stream.firstWhere((s) => s.speechRate == 0.9);
      expect(cubit.state.themeMode, ThemeMode.values.last);
      await cubit.close();
    });

    test('clamps a negative persisted theme index to the first value',
        () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': -5,
        'speech_rate': 0.9,
      });
      final cubit = SettingsCubit();
      await cubit.stream.firstWhere((s) => s.speechRate == 0.9);
      expect(cubit.state.themeMode, ThemeMode.values.first);
      await cubit.close();
    });

    test('loads a valid persisted theme index unchanged', () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 1,
        'speech_rate': 0.9,
      });
      final cubit = SettingsCubit();
      await cubit.stream.firstWhere((s) => s.speechRate == 0.9);
      expect(cubit.state.themeMode, ThemeMode.values[1]);
      await cubit.close();
    });
  });

  group('Desktop Echo Engine settings', () {
    test('default to off/unset when nothing is persisted', () async {
      SharedPreferences.setMockInitialValues({});
      final cubit = SettingsCubit();
      // _loadSettings' emitted state equals SettingsState.initial() here, so
      // Cubit's built-in "skip if unchanged" means the stream may never emit
      // — just give the async load a moment to run, then assert directly.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.preferDesktopEngine, isFalse);
      expect(cubit.state.desktopEngineHost, isNull);
      expect(cubit.state.runDesktopEngineHere, isFalse);
      await cubit.close();
    });

    test('setPreferDesktopEngine persists and round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final cubit = SettingsCubit();
      await cubit.setPreferDesktopEngine(true);
      expect(cubit.state.preferDesktopEngine, isTrue);
      await cubit.close();

      // A fresh cubit reading the same (mocked) prefs store should see it.
      final reloaded = SettingsCubit();
      await reloaded.stream.firstWhere(
        (s) => s.preferDesktopEngine == true,
      );
      expect(reloaded.state.preferDesktopEngine, isTrue);
      await reloaded.close();
    });

    test('setDesktopEngineHost sets then explicitly clears the host',
        () async {
      SharedPreferences.setMockInitialValues({});
      final cubit = SettingsCubit();
      await cubit.setDesktopEngineHost('192.168.1.12:8790');
      expect(cubit.state.desktopEngineHost, '192.168.1.12:8790');

      // Passing null must actually clear it, not be ignored as a no-op —
      // this is the case copyWith's `??` pattern can't express directly.
      await cubit.setDesktopEngineHost(null);
      expect(cubit.state.desktopEngineHost, isNull);
      await cubit.close();
    });

    test('setRunDesktopEngineHere(false) persists without touching the model',
        () async {
      SharedPreferences.setMockInitialValues({
        'run_desktop_engine_here': true,
      });
      final cubit = SettingsCubit();
      await cubit.setRunDesktopEngineHere(false);
      expect(cubit.state.runDesktopEngineHere, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('run_desktop_engine_here'), isFalse);
      await cubit.close();
    });
  });
}
