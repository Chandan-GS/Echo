import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/desktop/presentation/command_palette.dart';
import 'package:project_echo/features/desktop/presentation/desktop_workspace.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('number keys switch sections and ⌘K opens the palette', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => SettingsCubit()),
          BlocProvider<TodoCubit>(create: (_) => _Empty()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const DesktopWorkspace(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    int showing() =>
        tester.widget<IndexedStack>(find.byType(IndexedStack).first).index!;
    expect(showing(), DesktopSection.today.index);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit2, character: '2');
    await tester.pump();
    expect(showing(), DesktopSection.todo.index);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit4, character: '4');
    await tester.pump();
    expect(showing(), DesktopSection.vault.index);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(find.byType(CommandPalette), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(CommandPalette), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}

class _Empty extends Cubit<TodoState> implements TodoCubit {
  _Empty()
    : super(TodoState(now: DateTime.now(), loaded: true, items: const []));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
