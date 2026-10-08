// Draws Today to PNGs for a look by eye; skipped unless RENDER_OUT is set:
// RENDER_OUT=/some/dir flutter test test/render/today_render_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/desktop/presentation/desktop_sidebar.dart';
import 'package:project_echo/features/desktop/presentation/desktop_workspace.dart';
import 'package:project_echo/features/desktop/presentation/today/today_detail.dart';
import 'package:project_echo/features/desktop/presentation/today/today_list.dart';
import 'package:project_echo/features/desktop/presentation/today/today_logic.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await loader.load();
}

RawData _msg(String who, String text, int h, int m, String thread) => RawData()
  ..source = 'WhatsApp'
  ..sender = who
  ..content = text
  ..timestamp = DateTime(2026, 10, 3, h, m)
  ..thread = thread
  ..addressed = 'direct';

void main() {
  final out = Platform.environment['RENDER_OUT'];

  setUpAll(() async {
    if (out == null) return;
    await _font('Nunito', ['assets/fonts/Nunito-VariableFont_wght.ttf']);
    await _font('OldStandardTT', [
      'assets/fonts/OldStandardTT-Regular.ttf',
      'assets/fonts/OldStandardTT-Bold.ttf',
    ]);
    await _font('packages/material_symbols_icons/MaterialSymbolsRounded', [
      '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/'
          'material_symbols_icons-4.2960.0/lib/fonts/MaterialSymbolsRounded.ttf',
    ]);
  });

  for (final dark in [false, true]) {
    testWidgets('today ${dark ? 'dark' : 'light'}', skip: out == null, (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1146, 750);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime(2026, 10, 3, 23, 20);
      final entries = [
        _msg('+91 99451 28999', 'wt do u think?', 23, 3, 'a'),
        _msg(
          'PROXMAQ Mahesh',
          'Enter bid amount 430 in Bridge app',
          19,
          39,
          'b',
        ),
        _msg('Mohith JSS', 'Or we could meet mam on monday', 19, 6, 'c'),
        _msg('Amma', 'Can you send the file by 5:40 tonight?', 17, 6, 'd'),
        _msg('Amma', 'What time are we meeting?', 13, 58, 'e'),
      ];
      final items = [for (final e in entries) TriageItem.waiting(e)];
      final picked = items[2];
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: BlocProvider(
            create: (_) => SettingsCubit(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
              home: Builder(
                builder: (context) => Material(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DesktopSidebar(
                        section: DesktopSection.today,
                        waiting: items.length,
                        todoLeft: 2,
                        onSelect: (_) {},
                        onPalette: () {},
                      ),
                      SizedBox(
                        width: 340,
                        child: TodayList(
                          items: items,
                          selected: picked.id,
                          handled: const {},
                          summaries: const {},
                          onSelect: (_) {},
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        color: Theme.of(context).dividerColor,
                      ),
                      Expanded(
                        child: TodayDetail(
                          item: picked,
                          lines: const [],
                          now: now,
                          marked: false,
                          reply: null,
                          remindAt: now.add(const Duration(hours: 10)),
                          reminding: null,
                          onList: false,
                          summary: null,
                          replyFocus: FocusNode(),
                          actions: TodayActions(
                            send: (_) {},
                            remind: () {},
                            addToList: () {},
                            handle: () {},
                            catchUp: () {},
                            leaveReply: () {},
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '$out/today_${dark ? 'dark' : 'light'}.png',
        ).writeAsBytesSync(png!.buffer.asUint8List());
      });
    });
  }
}
