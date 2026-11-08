import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/core/services/echo_says.dart';
import 'package:project_echo/core/services/phone_sync_service.dart';
import 'package:project_echo/core/services/widget_refresh_service.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/home/group_summaries.dart';
import 'package:project_echo/features/echo/data/home/home_feed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/reply/reply_sender.dart';
import 'package:project_echo/features/echo/data/waiting/wait_intent.dart';
import 'package:project_echo/features/echo/data/waiting/waiting_store.dart';
import 'package:project_echo/features/echo/presentation/cubit/briefing_cubit.dart';
import 'package:project_echo/features/echo/presentation/screens/daily_briefing_screen.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/echo/presentation/widgets/today/today_glance.dart';
import 'package:project_echo/features/echo/presentation/widgets/today/today_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/today/today_sections.dart';
import 'package:project_echo/features/echo/presentation/widgets/today/waiting_card.dart';
import 'package:project_echo/features/quiet/data/quiet_settings.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:project_echo/features/todo/presentation/cubit/todo_cubit.dart';
import 'package:project_echo/features/vault/data/app_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Today tab: who's waiting on the owner, then the day.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> with WidgetsBindingObserver {
  static const _permissions = MethodChannel('project_echo/permissions');

  /// How many cards show before "N more".
  static const _shown = 3;

  HomeFeed _feed = HomeFeed.empty;
  WaitingFeed _waiting = WaitingFeed.empty;
  Map<String, String> _summaries = const {};
  bool _loaded = false;
  bool _hasAccess = true;
  bool _quietOn = false;
  String? _name;
  DateTime _now = DateTime.now();
  bool _showAll = false;

  /// Keys swiped away this session, so a reload in flight can't bring one
  /// back for a moment.
  final _swiped = <String>{};

  bool _summarising = false;
  bool _greeted = false;
  StreamSubscription<void>? _isarWatch;
  Timer? _reload;
  Timer? _minute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _readOnce();
    TodoStore.changed.addListener(_reloadSoon);
    WaitingStore.changed.addListener(_reloadSoon);
    IsarDataSource.instance
        .then((isar) {
          if (!mounted) return;
          _isarWatch = isar.rawDatas.watchLazy().listen((_) => _reloadSoon());
        })
        .catchError((_) {});
    // Ages and "in 25 min" move on; so does the date, at midnight.
    _minute = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    // Mirror this phone to a computer on the same Wi-Fi while the app is open.
    PhoneSyncService.instance.startPeriodic();
    PhoneSyncService.instance.syncNow();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    TodoStore.changed.removeListener(_reloadSoon);
    WaitingStore.changed.removeListener(_reloadSoon);
    _isarWatch?.cancel();
    _reload?.cancel();
    _minute?.cancel();
    PhoneSyncService.instance.stopPeriodic();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<BriefingCubit>().loadCachedBriefing();
      _load();
      _readOnce();
      WidgetRefreshService.refresh();
      PhoneSyncService.instance.syncNow();
    }
  }

  void _tick() {
    if (!mounted) return;
    final now = DateTime.now();
    final newDay = now.day != _now.day;
    setState(() => _now = now);
    if (newDay || now.minute % 5 == 0) _load();
  }

  /// Several notifications often land together; reload once.
  void _reloadSoon() {
    _reload?.cancel();
    _reload = Timer(const Duration(milliseconds: 700), _load);
  }

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      final entries = await withoutExcludedSources(
        await IsarDataSource.getAllEntries(),
      );
      final turns = await ChatContextStore.loadMyTurns();
      final feed = await HomeFeed.load(now, entries: entries);
      final waiting = await WaitingStore.load(
        now,
        entries: entries,
        turns: turns,
      );
      final summaries = await GroupSummaries.cached();
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _waiting = waiting;
        _summaries = summaries;
        _now = now;
        _loaded = true;
      });
      unawaited(_summarise(feed, now));
      _greet(waiting);
    } catch (e) {
      debugPrint('Today: couldn\'t load: $e');
    }
  }

  Future<void> _readOnce() async {
    final prefs = await SharedPreferences.getInstance();
    var access = true;
    try {
      access =
          await _permissions.invokeMethod<bool>(
            'checkNotificationPermission',
          ) ??
          true;
    } on MissingPluginException {
      access = true;
    } on PlatformException {
      access = true;
    }
    final quiet = await _readQuiet();
    if (!mounted) return;
    setState(() {
      _name = prefs.getString('user_name');
      _hasAccess = access;
      _quietOn = quiet;
    });
  }

  Future<bool> _readQuiet() async {
    try {
      final config = await QuietSettings.load();
      return _quietNow(config, DateTime.now());
    } catch (_) {
      return false;
    }
  }

  /// Whether quiet hours are on right now. A window that runs past midnight
  /// belongs to the day it started on.
  static bool _quietNow(QuietConfig q, DateTime now) {
    if (!q.enabled) return false;
    final minute = now.hour * 60 + now.minute;
    final overnight = q.endMin <= q.startMin;
    if (!overnight) {
      return q.days.contains(now.weekday) &&
          minute >= q.startMin &&
          minute < q.endMin;
    }
    if (minute >= q.startMin) return q.days.contains(now.weekday);
    final yesterday = now.weekday == 1 ? 7 : now.weekday - 1;
    return minute < q.endMin && q.days.contains(yesterday);
  }

  /// Sums up the busy groups that have moved on, one call at a time.
  Future<void> _summarise(HomeFeed feed, DateTime now) async {
    if (_summarising || feed.allGroups.isEmpty) return;
    _summarising = true;
    try {
      final lines = await GroupSummaries.refresh(
        feed.allGroups.take(_summarisedGroups).toList(),
        now,
      );
      if (mounted) setState(() => _summaries = lines);
    } catch (_) {
      // The latest message stands in.
    } finally {
      _summarising = false;
    }
  }

  /// One Gemini call stays small enough to answer quickly.
  static const _summarisedGroups = 8;

  /// Echo says who's waited longest, once, a moment after Today opens.
  void _greet(WaitingFeed feed) {
    if (_greeted || feed.waiting.isEmpty) return;
    final longest = feed.waiting.first;
    if (longest.ageBand == 0) return;
    _greeted = true;
    final name = longest.message.sender;
    final waited = longest.ageBand == 1 ? 'since yesterday' : longest.since;
    final isCall = longest.reason.kind == WaitKind.call;
    Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      EchoSays.instance.say(
        EchoLine(
          '$name’s been waiting $waited. '
          '${isCall ? 'Want to call first?' : 'Want to answer first?'}',
          mood: EchoState.thinking,
          onceKey: 'today-waiting',
          onTap: () => ReplySender.open(longest.message),
        ),
      );
    });
  }

  Future<void> _grantAccess() async {
    try {
      await _permissions.invokeMethod('requestNotificationPermission');
    } on MissingPluginException {
      // Nothing to open on a computer.
    } on PlatformException {
      // Settings couldn't be opened; the card stays.
    }
  }

  void _onHandled(WaitingItem item) {
    setState(() {
      _swiped.add(item.key);
      _waiting = WaitingFeed(
        waiting: [
          for (final w in _waiting.waiting)
            if (w.key != item.key) w,
        ],
        acks: _waiting.acks,
        grey: _waiting.grey,
      );
    });
    unawaited(WaitingStore.markHandled(item, notify: false));
    final name = item.message.sender;
    showTodayToast(
      context,
      '$name handled',
      action: 'Undo',
      onAction: () {
        _swiped.remove(item.key);
        unawaited(WaitingStore.undoHandled(item));
      },
    );
  }

  List<WaitingItem> get _visible => [
    for (final w in _waiting.waiting)
      if (!_swiped.contains(w.key)) w,
  ];

  @override
  Widget build(BuildContext context) {
    final waiting = _visible;
    final bottom = MediaQuery.paddingOf(context).bottom + 16;
    final shown = _showAll ? waiting : waiting.take(_shown).toList();
    final more = waiting.length - _shown;
    final note = !_loaded
        ? null
        : waiting.isEmpty
        ? 'all clear'
        : waiting.length == 1
        ? '1 person'
        : '${waiting.length} people';

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: context.colors.background,
      body: BlocListener<BriefingCubit, BriefingState>(
        listener: (context, state) async {
          if (state is! BriefingReady) return;
          // Read-and-clear the one-shot flag set when the owner reached the
          // app through the notification's "Play" action or a tap on it.
          final prefs = await SharedPreferences.getInstance();
          final autoPlay = prefs.getBool('pending_autoplay') ?? false;
          if (autoPlay) await prefs.remove('pending_autoplay');
          if (!context.mounted) return;
          Navigator.of(context, rootNavigator: true).push(
            bouncyRoute(
              DailyBriefingScreen(
                rawText: state.rawText,
                ttsText: state.ttsText,
                autoPlay: autoPlay,
                todoCubit: context.read<TodoCubit>(),
                onReset: () => context.read<BriefingCubit>().goBack(),
              ),
            ),
          );
        },
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: TodayHeader(
                  now: _now,
                  quietOn: _quietOn,
                  onQuiet: () => context.push('/quiet'),
                ),
              ),
              SliverToBoxAdapter(
                child: FadeSlideIn(
                  child: TodayGlance(
                    now: _now,
                    waiting: waiting.length,
                    name: _name,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(
                  child: TodaySectionHead('Waiting on you', note: note),
                ),
              ),
              if (waiting.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                  sliver: SliverToBoxAdapter(
                    child: !_loaded
                        ? const SizedBox(height: 0)
                        : _hasAccess
                        ? const FadeSlideIn(child: AllClearCard())
                        : NoAccessCard(onGrant: _grantAccess),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverList.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final item = shown[i];
                      return FadeSlideIn(
                        key: ValueKey(item.key),
                        delay: AppMotion.staggerDelay(i),
                        child: WaitingCard(
                          item: item,
                          index: i,
                          onGone: _load,
                          onHandled: () => _onHandled(item),
                        ),
                      );
                    },
                  ),
                ),
              if (more > 0)
                SliverToBoxAdapter(
                  child: WaitingMoreRow(
                    more: more,
                    open: _showAll,
                    onTap: () => setState(() => _showAll = !_showAll),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, bottom),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AcksRow(acks: _waiting.acks),
                      const TodoSection(),
                      OwedSection(owed: _feed.owed),
                      BusyGroupsSection(
                        groups: _feed.allGroups,
                        summaries: _summaries,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
