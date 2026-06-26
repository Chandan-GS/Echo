import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';

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
  }

  void _onTextChanged() {
    final text = _nameController.text.trim();
    setState(() {
      _isButtonEnabled = text.isNotEmpty;
    });
  }

  @override
  void dispose() {
    _nameController.removeListener(_onTextChanged);
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnBoardingCubit>();

    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: context.colors.textPrimary,
          ),
          onPressed: () {
            cubit.goBackToAiMode();
          },
        ),
      ),
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                'What should Echo\ncall you?',
                style: GoogleFonts.oldStandardTt(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                  height: 1.15,
                ),
              ),

              const SizedBox(height: 12),

              // Subtitle/Humorous hint
              Text(
                'Type your name below. Or "Sir", "Boss" if you are feeling like royalty.',
                style: GoogleFonts.nunito(
                  fontSize: 16,
                  color: context.colors.textSecondary,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 40),

              // Custom text input
              TextField(
                controller: _nameController,
                autofocus: true,
                style: GoogleFonts.nunito(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary,
                ),
                cursorColor: context.colors.primaryGreen,
                decoration: InputDecoration(
                  hintText: 'Your name...',
                  hintStyle: TextStyle(
                    color: context.colors.textSecondary.withValues(alpha: 0.3),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 4,
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: context.colors.dividerColor.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  focusedBorder:
                      BorderSide.none !=
                          BorderSide
                              .none // just standard UnderlineInputBorder
                      ? UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: context.colors.primaryGreen,
                            width: 2,
                          ),
                        )
                      : null,
                ),
                textCapitalization: TextCapitalization.words,
                onSubmitted: (_) {
                  if (_isButtonEnabled) {
                    cubit.saveUserNameAndFinish(_nameController.text);
                  }
                },
              ),

              const Spacer(),

              // Action Button
              EchoButton(
                text: 'Finish Setup',
                onPressed: _isButtonEnabled
                    ? () {
                        cubit.saveUserNameAndFinish(_nameController.text);
                      }
                    : null,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
