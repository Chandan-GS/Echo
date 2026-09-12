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
}
