import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/presentation/widgets/nav_dock.dart';
import 'package:project_echo/core/services/echo_says.dart';
import 'package:project_echo/core/services/gemini_usage.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/presentation/cubit/briefing_cubit.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_dizzy.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/echo/presentation/widgets/home_glance.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Echo's speech bubble: as wide as the nav dock, resting on top of it, with
/// a curved tail pointing down at Echo. It grows out of him, then his words
/// appear one by one, as if he's saying them.
class EchoBubble extends StatefulWidget {
  const EchoBubble({super.key});

  @override
  State<EchoBubble> createState() => _EchoBubbleState();
}

class _EchoBubbleState extends State<EchoBubble> with TickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
    reverseDuration: const Duration(milliseconds: 260),
  );
  late final AnimationController _words = AnimationController(vsync: this);
  EchoLine? _line;

  // Word timing, as in the mock: the first word 350 ms in, then one every
  // 90 ms, each fading in over 250 ms.
  static const _firstWordMs = 350;
  static const _perWordMs = 90;
  static const _fadeMs = 250;

  @override
  void initState() {
    super.initState();
    EchoSays.instance.current.addListener(_onLine);
    _onLine();
  }

  void _onLine() {
    final line = EchoSays.instance.current.value;
    if (line != null) {
      final words = line.text.split(' ').length;
      setState(() => _line = line);
      _grow.forward(from: _grow.value > 0.5 ? 0.6 : 0);
      _words.duration = Duration(
        milliseconds: _firstWordMs + (words - 1) * _perWordMs + _fadeMs,
      );
      _words.forward(from: 0);
    } else {
      _grow.reverse();
    }
  }

  @override
  void dispose() {
    EchoSays.instance.current.removeListener(_onLine);
    _grow.dispose();
    _words.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = _line;
    if (line == null) return const SizedBox.shrink();
    final dark = context.isDarkMode;
    const ink = Color(0xFF1E1E1E);
    final style = GoogleFonts.nunito(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.38,
      color: ink,
    );
    final words = line.text.split(' ');
    final total = _words.duration?.inMilliseconds ?? 1;

    return AnimatedBuilder(
      animation: Listenable.merge([_grow, _words]),
      builder: (context, _) {
        final grow = _grow.status == AnimationStatus.reverse
            ? Curves.easeIn.transform(_grow.value)
            : const Cubic(0.2, 1.4, 0.35, 1).transform(_grow.value);
        final ms = _words.value * total;
        return IgnorePointer(
          ignoring: _grow.value < 0.5,
          child: Opacity(
            opacity: (_grow.value / 0.35).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.12 + 0.88 * grow,
              // Grows out of Echo, at the tail's tip.
              alignment: Alignment.bottomRight,
              origin: const Offset(-_echoFromRight, 0),
              child: GestureDetector(
                onTap: () {
                  line.onTap?.call();
                  EchoSays.instance.hide();
                },
                child: CustomPaint(
                  painter: _SpeechBubblePainter(
                    fill: dark ? const Color(0xFFEFEFEF) : Colors.white,
                    lifted: !dark,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 13, 16, 13 + _tail),
                    child: SizedBox(
                      width: double.infinity,
                      child: Text.rich(
                        TextSpan(
                          style: style,
                          children: [
                            for (var i = 0; i < words.length; i++)
                              TextSpan(
                                text: i == 0 ? words[i] : ' ${words[i]}',
                                style: TextStyle(
                                  color: ink.withValues(
                                    alpha:
                                        ((ms - _firstWordMs - i * _perWordMs) /
                                                _fadeMs)
                                            .clamp(0.0, 1.0),
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
            ),
          ),
        );
      },
    );
  }
}

/// Echo's centre, from the dock's right edge.
const double _echoFromRight = kNavDockHeight / 2;

/// How far the tail reaches below the bubble.
const double _tail = 15;

/// A classic speech bubble: a soft rounded body and one curved tail whose tip
/// sits over Echo, drawn as one outline so the shadow and edge run round both.
class _SpeechBubblePainter extends CustomPainter {
  final Color fill;

  /// A soft shadow and hairline edge, for the light theme.
  final bool lifted;

  const _SpeechBubblePainter({required this.fill, required this.lifted});

  Path _outline(Size size) {
    final body = Rect.fromLTWH(0, 0, size.width, size.height - _tail);
    // The tail: 26 wide and 18 tall, tip at (22, 18), its top 3 px inside
    // the body; its tip lands over Echo's centre.
    final tip = Offset(size.width - _echoFromRight, size.height);
    final o = Offset(tip.dx - 22, body.bottom - 3);
    Offset at(double x, double y) => o + Offset(x, y);
    final tail = Path()
      ..moveTo(at(0, 0).dx, at(0, 0).dy)
      ..cubicTo(
        at(10, 2).dx,
        at(10, 2).dy,
        at(18, 6).dx,
        at(18, 6).dy,
        at(22, 18).dx,
        at(22, 18).dy,
      )
      ..cubicTo(
        at(24, 10).dx,
        at(24, 10).dy,
        at(24, 4).dx,
        at(24, 4).dy,
        at(26, 0).dx,
        at(26, 0).dy,
      )
      ..close();
    return Path.combine(
      PathOperation.union,
      Path()
        ..addRRect(RRect.fromRectAndRadius(body, const Radius.circular(22))),
      tail,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _outline(size);
    if (lifted) {
      canvas.drawPath(
        path.shift(const Offset(0, 10)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
      );
    }
    canvas.drawPath(path, Paint()..color = fill);
    if (lifted) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.05)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpeechBubblePainter old) =>
      old.fill != fill || old.lifted != lifted;
}

/// Watches for the moments Echo speaks up, and for a shake of the phone.
/// Sits invisibly in the phone shell, below the app's cubits.
class EchoSaysHost extends StatefulWidget {
  /// Opens Home, for the lines that point there.
  final VoidCallback onOpenHome;
  const EchoSaysHost({super.key, required this.onOpenHome});

  @override
  State<EchoSaysHost> createState() => _EchoSaysHostState();
}

class _EchoSaysHostState extends State<EchoSaysHost>
    with WidgetsBindingObserver {
  final _shake = ShakeDetector();
  StreamSubscription<UserAccelerometerEvent>? _motion;
  Timer? _tick;
  DateTime? _pausedAt;
  EchoLine? _writing;
  EchoLine? _listing;
  bool? _allDone;

  static const _awayKey = 'echo_says_paused_at';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GeminiUsage.instance.snapshot.addListener(_onUsage);
    _start();
    // Give the first frame a moment before Echo says anything.
    Future<void>.delayed(const Duration(seconds: 2), _onOpen);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GeminiUsage.instance.snapshot.removeListener(_onUsage);
    _stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
      _onOpen();
    } else if (state == AppLifecycleState.paused) {
      _stop();
      _pausedAt = DateTime.now();
      SharedPreferences.getInstance().then(
        (p) => p.setString(_awayKey, _pausedAt!.toIso8601String()),
      );
    }
  }

  // ── Listening only while the app is open ──────────────────────────────

  void _start() {
    _motion ??= userAccelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(_onMotion, onError: (_) {});
    _tick ??= Timer.periodic(const Duration(minutes: 1), (_) => _comingUp());
  }

  void _stop() {
    _motion?.cancel();
    _motion = null;
    _tick?.cancel();
    _tick = null;
  }

  // ── The shake ─────────────────────────────────────────────────────────

  void _onMotion(UserAccelerometerEvent e) {
    final strength = _shake.add(e.x, e.y, e.z, DateTime.now());
    if (strength == null || !mounted) return;
    if (MediaQuery.of(context).disableAnimations) return;
    EchoDizzy.instance.trigger(dizzyPowerFor(strength));
    HapticFeedback.mediumImpact();
    EchoSays.instance.say(
      const EchoLine(
        'Whoa… the room’s spinning.',
        ambient: false,
        hold: Duration(seconds: 4),
      ),
    );
  }

  // ── Opening the app ───────────────────────────────────────────────────

  Future<void> _onOpen() async {
    if (!mounted) return;
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    if (now.hour >= 23 || now.hour < 4) {
      await EchoSays.instance.say(
        const EchoLine(
          'It’s late. I’ll keep listening. See you in the morning.',
          mood: EchoState.sleeping,
          onceKey: 'late',
        ),
      );
      return;
    }

    final today = now.toIso8601String().split('T').first;
    if (now.hour >= 5 &&
        now.hour < 12 &&
        prefs.getString('cached_briefing_date') == today) {
      final shown = await EchoSays.instance.say(
        EchoLine(
          'Morning! Your briefing is ready. Two minutes and you’re caught up.',
          mood: EchoState.happy,
          onceKey: 'morning',
          onTap: widget.onOpenHome,
        ),
      );
      if (shown) return;
    }

    // Back after a while: how much came in meanwhile.
    final away =
        _pausedAt ?? DateTime.tryParse(prefs.getString(_awayKey) ?? '');
    if (away != null && now.difference(away) >= const Duration(minutes: 30)) {
      final entries = await IsarDataSource.getAllEntries();
      final fresh = entries.where((e) => e.timestamp.isAfter(away)).length;
      if (fresh >= 3) {
        final shown = await EchoSays.instance.say(
          EchoLine('$fresh new while you were away.'),
        );
        if (shown) return;
      }
    }
    _comingUp();
  }

  // ── Something with a time is coming up ────────────────────────────────

  void _comingUp() {
    if (!mounted) return;
    final todo = context.read<TodoCubit>().state;
    if (!todo.loaded) return;
    final now = DateTime.now();
    for (final stop in dayStops([...todo.today, ...todo.tomorrow], now)) {
      final minutes = stop.at.difference(now).inMinutes;
      if (stop.item.done || minutes < 1) continue;
      if (minutes > 30) break;
      EchoSays.instance.say(
        EchoLine(
          '${stop.item.title} in $minutes ${minutes == 1 ? 'minute' : 'minutes'}.',
          onceKey: 'soon:${stop.item.id}:${stop.at.toIso8601String()}',
        ),
      );
      break;
    }
  }

  // ── Gemini running low, or out ────────────────────────────────────────

  void _onUsage() {
    final usage = GeminiUsage.instance.snapshot.value;
    if (usage == null) return;
    if (usage.blockedBy == GeminiLimitKind.perDay) {
      EchoSays.instance.say(
        EchoLine(
          'I’m out of Gemini for today. Back at ${clockTime(usage.resetsAt)}.',
          mood: EchoState.sleeping,
          onceKey: 'gemini-out',
          ambient: false,
        ),
      );
    } else if (usage.isLow && (usage.left ?? 0) > 0) {
      final left = usage.left!;
      EchoSays.instance.say(
        EchoLine(
          'I’ve got $left Gemini ${left == 1 ? 'request' : 'requests'} left today.',
          onceKey: 'gemini-low',
        ),
      );
    }
  }

  // ── What Echo is doing ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<BriefingCubit, BriefingState>(
          listenWhen: (a, b) =>
              (a is BriefingGenerating) != (b is BriefingGenerating),
          listener: (context, state) {
            if (state is BriefingGenerating) {
              _writing = const EchoLine(
                'Reading your day and writing your briefing…',
                mood: EchoState.focused,
                ambient: false,
                hold: Duration(minutes: 3),
              );
              EchoSays.instance.say(_writing!);
            } else if (_writing != null) {
              EchoSays.instance.hide(_writing);
              _writing = null;
            }
          },
        ),
        BlocListener<TodoCubit, TodoState>(
          listener: (context, state) {
            final writing = state.phase == TodoPhase.writing;
            if (writing && _listing == null) {
              _listing = const EchoLine(
                'Turning your briefing into a list…',
                mood: EchoState.focused,
                ambient: false,
                hold: Duration(minutes: 2),
              );
              EchoSays.instance.say(_listing!);
            } else if (!writing && _listing != null) {
              EchoSays.instance.hide(_listing);
              _listing = null;
            }
            if (!state.loaded) return;
            final done = state.today.isNotEmpty && state.allDoneToday;
            if (_allDone == false && done) {
              EchoSays.instance.say(
                const EchoLine(
                  'That’s everything for today. Nicely done.',
                  mood: EchoState.happy,
                  onceKey: 'all-done',
                  ambient: false,
                ),
              );
            }
            _allDone = done;
          },
        ),
      ],
      child: const SizedBox.shrink(),
    );
  }
}
