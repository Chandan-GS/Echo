import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/presentation/widgets/echo_segmented.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';

class AppearanceSegmentedControl extends StatelessWidget {
  const AppearanceSegmentedControl({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) => EchoSegmented(
        labels: const ['System', 'Light', 'Dark'],
        selected: state.themeMode.index,
        onSelect: (i) =>
            context.read<SettingsCubit>().setThemeMode(ThemeMode.values[i]),
      ),
    );
  }
}
