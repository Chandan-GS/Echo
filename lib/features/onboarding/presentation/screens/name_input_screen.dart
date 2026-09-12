import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/onboarding_scaffold.dart';

class NameInputScreen extends StatefulWidget {
  const NameInputScreen({super.key});

  @override
  State<NameInputScreen> createState() => _NameInputScreenState();
}

class _NameInputScreenState extends State<NameInputScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _isButtonEnabled = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onTextChanged);
    _restoreName();
  }

  Future<void> _restoreName() async {
    // Prefill if the user already typed a name and navigated back.
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('user_name') ?? '';
    if (existing.isNotEmpty && mounted) {
      _nameController.text = existing;
      setState(() => _isButtonEnabled = true);
    }
  }

  void _onTextChanged() {
    final enabled = _nameController.text.trim().isNotEmpty;
    if (enabled != _isButtonEnabled) {
      setState(() => _isButtonEnabled = enabled);
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_onTextChanged);
    _nameController.dispose();
    super.dispose();
  }

  void _submit(OnBoardingCubit cubit) {
    if (_isButtonEnabled) {
      cubit.saveUserNameAndContinue(_nameController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnBoardingCubit>();
    final colors = context.colors;

    return OnboardingStepBody(
      title: 'What should Echo call you?',
      subtitle: 'Your name, “Boss”, whatever fits. Echo greets you by it.',
      footer: EchoButton(
        text: 'Continue',
        showArrow: true,
        onPressed: _isButtonEnabled ? () => _submit(cubit) : null,
      ),
      child: TextField(
        controller: _nameController,
        autofocus: true,
        style: GoogleFonts.oldStandardTt(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
        cursorColor: colors.primaryGreen,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: 'Your name…',
          hintStyle: GoogleFonts.oldStandardTt(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: colors.textSecondary.withValues(alpha: 0.3),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: colors.dividerColor.withValues(alpha: 0.6),
              width: 2,
            ),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: colors.primaryGreen, width: 2),
          ),
        ),
        onSubmitted: (_) => _submit(cubit),
      ),
    );
  }
}
