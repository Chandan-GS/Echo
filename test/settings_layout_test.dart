import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/screens/briefing_settings_page.dart';
import 'package:project_echo/features/settings/presentation/screens/cloud_consent_page.dart';
import 'package:project_echo/features/settings/presentation/screens/cloud_engine_page.dart';
import 'package:project_echo/features/settings/presentation/screens/evening_wrap_page.dart';
import 'package:project_echo/features/settings/presentation/screens/phone_settings_screen.dart';
import 'package:project_echo/features/settings/presentation/screens/writing_pack_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Narrow phone, large text, both themes: nothing may overflow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pages = <String, Widget>{
    'hub': const PhoneSettingsScreen(),
    'evening wrap': const SettingsPage(
      title: 'Evening wrap',
      child: EveningWrapPage(),
    ),
    'briefing': const SettingsPage(
      title: 'Morning briefing',
      child: BriefingSettingsPage(),
    ),
    'writing pack': const SettingsPage(
      title: 'Writing pack',
      child: WritingPackPage(),
    ),
    'cloud': const SettingsPage(title: 'Cloud', child: CloudEnginePage()),
    'consent': const CloudConsentPage(alreadyOn: false),
  };

  for (final dark in [false, true]) {
    for (final MapEntry(key: name, value: page) in pages.entries) {
      testWidgets('$name fits at 320dp, ${dark ? 'dark' : 'light'}', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({
          'is_offline_engine': false,
          'gemini_api_key': '',
        });
        PackageInfo.setMockInitialValues(
          appName: 'Echo',
          packageName: 'echo',
          version: '1.0.0',
          buildNumber: '6',
          buildSignature: '',
        );
        // Tall, so every lazily built row is laid out.
        tester.view.physicalSize = const Size(320, 6000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          BlocProvider(
            create: (_) => SettingsCubit(),
            child: MaterialApp(
              theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
              home: page,
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
