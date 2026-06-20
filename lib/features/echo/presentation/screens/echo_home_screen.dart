import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/cubit/briefing_cubit.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/echo/presentation/screens/daily_briefing_screen.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';

class EchoHomeScreen extends StatelessWidget {
  const EchoHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => BriefingCubit(),
      child: const _EchoView(),
    );
  }
}

class _EchoView extends StatefulWidget {
  const _EchoView();

  @override
  State<_EchoView> createState() => _EchoViewState();
}

class _EchoViewState extends State<_EchoView> {
  final FlutterTts _tts = FlutterTts();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _setupTts();
  }

  Future<void> _setupTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    try {
      final voices = await _tts.getVoices;
      for (var voice in voices) {
        final name = voice['name'].toString().toLowerCase();
        final locale = voice['locale'].toString().toLowerCase();
        if ((locale.contains('en-gb')) &&
            (name.contains('male') ||
                name.contains('daniel') ||
                name.contains('network'))) {
          await _tts.setVoice({
            "name": voice["name"],
            "locale": voice["locale"],
          });
          break;
        }
      }
    } catch (_) {}

    _tts.setStartHandler(() => setState(() => _isPlaying = true));
    _tts.setCompletionHandler(() => setState(() => _isPlaying = false));
    _tts.setCancelHandler(() => setState(() => _isPlaying = false));
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  void _togglePlayback(String ttsText) async {
    if (_isPlaying) {
      await _tts.stop();
    } else {
      await _tts.speak(ttsText);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: BlocBuilder<BriefingCubit, BriefingState>(
        builder: (context, state) {
          if (state is BriefingInitial) {
            return _InitialView(
              onGenerate: () =>
                  context.read<BriefingCubit>().generateBriefing(),
            );
          }

          if (state is BriefingCached) {
            return _CachedView(
              onPlay: () => context.read<BriefingCubit>().playCachedBriefing(
                state.rawText,
              ),
              onRegenerate: () =>
                  context.read<BriefingCubit>().generateBriefing(),
            );
          }

          if (state is BriefingGenerating) {
            return _GeneratingView(partial: state.partial);
          }

          if (state is BriefingError) {
            return _ErrorView(
              message: state.message,
              onRetry: () => context.read<BriefingCubit>().generateBriefing(),
            );
          }

          if (state is BriefingReady) {
            return DailyBriefingScreen(
              rawText: state.rawText,
              ttsText: state.ttsText,
              isPlaying: _isPlaying,
              onTogglePlay: () => _togglePlayback(state.ttsText),
              onReset: () {
                _tts.stop();
                context.read<BriefingCubit>().goBack();
              },
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Initial State — no briefing yet
// ---------------------------------------------------------------------------
class _InitialView extends StatelessWidget {
  final VoidCallback onGenerate;
  const _InitialView({required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    return _HomeShell(
      actions: [
        _CompactButton(
          icon: Icons.auto_awesome_rounded,
          label: 'Generate Briefing',
          isPrimary: true,
          onTap: onGenerate,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cached State — briefing exists for today
// ---------------------------------------------------------------------------
class _CachedView extends StatelessWidget {
  final VoidCallback onPlay;
  final VoidCallback onRegenerate;
  const _CachedView({required this.onPlay, required this.onRegenerate});

  @override
  Widget build(BuildContext context) {
    return _HomeShell(
      actions: [
        _CompactButton(
          icon: Icons.play_arrow_rounded,
          label: "Play Today's Briefing",
          isPrimary: true,
          onTap: onPlay,
        ),
        _CompactButton(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Ask',
          isPrimary: false,
          onTap: () {}, // static for now
        ),
        _CompactButton(
          icon: Icons.auto_awesome_rounded,
          label: 'Generate',
          isPrimary: false,
          onTap: onRegenerate,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared shell (header + signal card + list + action list)
// ---------------------------------------------------------------------------
class _HomeShell extends StatelessWidget {
  final List<Widget> actions;
  const _HomeShell({required this.actions});

  @override
  Widget build(BuildContext context) {
    final today = _formattedDate();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text(
              today.toUpperCase(),
              style: GoogleFonts.nunito(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.8,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your morning\nbriefing',
              style: GoogleFonts.oldStandardTt(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 20),

            FutureBuilder<List<RawData>>(
              future: IsarDataSource.getAllEntries(),
              builder: (context, snapshot) {
                final count = snapshot.data?.length ?? 0;
                return _SignalCard(signalCount: count);
              },
            ),
            const SizedBox(height: 20),

            Text(
              'CAPTURED SIGNALS',
              style: GoogleFonts.nunito(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: AppTheme.textSecondary.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: FutureBuilder<List<RawData>>(
                future: IsarDataSource.getAllEntries(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final items = snapshot.data ?? [];
                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        'No signals captured yet',
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    );
                  }

                  return ShaderMask(
                    shaderCallback: (Rect rect) {
                      return const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.purple,
                          Colors.transparent,
                          Colors.transparent,
                          Colors.purple,
                        ],
                        stops: [0.0, 0.05, 0.95, 1.0],
                      ).createShader(rect);
                    },
                    blendMode: BlendMode.dstOut,
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        return _NotificationCard(notification: items[index]);
                      },
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: actions,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  static String _formattedDate() {
    final now = DateTime.now();
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }
}

// ---------------------------------------------------------------------------
// Reusable compact action button
// ---------------------------------------------------------------------------
class _CompactButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isPrimary;
  final VoidCallback onTap;

  const _CompactButton({
    required this.icon,
    required this.label,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isPrimary ? AppTheme.textPrimary : Colors.white,
      borderRadius: BorderRadius.circular(24),

      shadowColor: isPrimary
          ? AppTheme.textPrimary.withValues(alpha: 0.3)
          : Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isPrimary ? Colors.white : AppTheme.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isPrimary ? Colors.white : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  final int signalCount;
  const _SignalCard({required this.signalCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.inbox_outlined,
            color: AppTheme.primaryGreen,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$signalCount signals ',
                        style: GoogleFonts.oldStandardTt(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                      TextSpan(
                        text: 'captured today',
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final RawData notification;

  const _NotificationCard({required this.notification});

  @override
  Widget build(BuildContext context) {
    final timeStr = _formatTimestamp(notification.timestamp);
    final icon = _getSourceIcon(notification.source);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top line: source icon, source name, timestamp
                Row(
                  children: [
                    Icon(icon, size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      notification.source.toUpperCase(),
                      style: GoogleFonts.nunito(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      timeStr,
                      style: GoogleFonts.nunito(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Sender
                Text(
                  notification.sender,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                // Content
                Text(
                  notification.content,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    height: 1.3,
                    color: AppTheme.textPrimary.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatTimestamp(DateTime dateTime) {
    final hour = dateTime.hour > 12
        ? dateTime.hour - 12
        : (dateTime.hour == 0 ? 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  static IconData _getSourceIcon(String source) {
    switch (source.toLowerCase()) {
      case 'slack':
        return Icons.chat_bubble_outline_rounded;
      case 'sms':
        return Icons.sms_outlined;
      case 'whatsapp':
        return Icons.message_outlined;
      case 'calendar':
        return Icons.calendar_today_outlined;
      case 'gmail':
        return Icons.mail_outline_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }
}

// ---------------------------------------------------------------------------
// Generating State — live streaming preview
// ---------------------------------------------------------------------------
class _GeneratingView extends StatelessWidget {
  final String partial;
  const _GeneratingView({required this.partial});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'COMPOSING',
              style: GoogleFonts.nunito(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Echo is thinking...',
              style: GoogleFonts.oldStandardTt(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 32),
            // Streaming text preview
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: partial.isEmpty
                      ? const _ThinkingDots()
                      : Text(
                          partial,
                          style: GoogleFonts.nunito(
                            fontSize: 17,
                            height: 1.6,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const LinearProgressIndicator(
              backgroundColor: Color(0xFFE8E4DE),
              valueColor: AlwaysStoppedAnimation(AppTheme.primaryGreen),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = ((_ctrl.value * 3) - i).clamp(0.0, 1.0);
          final opacity =
              0.25 + 0.75 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppTheme.textSecondary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DailyBriefingScreen is now used for Player State
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Error State
// ---------------------------------------------------------------------------
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                    color: AppTheme.textPrimary,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, color: AppTheme.textPrimary),
                label: Text(
                  'Retry',
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
