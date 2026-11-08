import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/widgets/person_avatar.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/reminders.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/people/data/people_store.dart';
import 'package:project_echo/features/people/data/person_detail.dart';
import 'package:project_echo/features/people/data/person_tally.dart';
import 'package:project_echo/features/people/presentation/widgets/people_parts.dart';
import 'package:project_echo/features/people/presentation/widgets/person_draft_sheet.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';

/// Birthdays, who's gone quieter than usual, open loops both ways and
/// everyone Echo has heard from. Search filters all of it as you type.
class PeopleScreen extends StatefulWidget {
  /// Replaces reading the feed, for tests.
  @visibleForTesting
  final Future<PeopleFeed> Function(DateTime now)? loader;

  const PeopleScreen({super.key, this.loader});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  PeopleFeed _feed = PeopleFeed.empty;
  bool _loaded = false;
  bool _listening = true;
  int _loadId = 0;
  Timer? _soon;
  Timer? _midnight;
  StreamSubscription<void>? _watch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _search.addListener(_onSearch);
    PeopleStore.changed.addListener(_reloadSoon);
    TodoStore.changed.addListener(_reloadSoon);
    _load();
    _watchMessages();
    _checkAccess();
    _armMidnight();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PeopleStore.changed.removeListener(_reloadSoon);
    TodoStore.changed.removeListener(_reloadSoon);
    _soon?.cancel();
    _midnight?.cancel();
    _watch?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reloadSoon();
      _checkAccess();
      _armMidnight();
    }
  }

  void _onSearch() => setState(() {});

  void _reloadSoon() {
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 700), _load);
  }

  /// New messages can change everything here, but not faster than a reload
  /// is worth it.
  Future<void> _watchMessages() async {
    try {
      final isar = await IsarDataSource.instance;
      if (!mounted) return;
      _watch = isar.rawDatas.watchLazy().listen((_) => _reloadSoon());
    } catch (_) {}
  }

  /// Today's birthdays and this week's drift change at midnight.
  void _armMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 2);
    _midnight = Timer(next.difference(now), () {
      _load();
      _armMidnight();
    });
  }

  Future<void> _load() async {
    final id = ++_loadId;
    final feed = await (widget.loader ?? PeopleStore.load)(DateTime.now());
    if (!mounted || id != _loadId) return;
    setState(() {
      _feed = feed;
      _loaded = true;
    });
    final showing = [for (final p in feed.drifting) p.key];
    if (showing.isNotEmpty) {
      unawaited(PeopleStore.markDriftShown(showing, DateTime.now()));
    }
  }

  static const _permissions = MethodChannel('project_echo/permissions');

  Future<void> _checkAccess() async {
    bool on;
    try {
      on =
          await _permissions.invokeMethod<bool>(
            'checkNotificationPermission',
          ) ??
          true;
    } catch (_) {
      on = true; // desktop, or a platform that doesn't ask
    }
    if (mounted && on != _listening) setState(() => _listening = on);
  }

  Future<void> _requestAccess() async {
    try {
      await _permissions.invokeMethod<void>('requestNotificationPermission');
    } catch (_) {}
  }

  void _open(String key) {
    FocusManager.instance.primaryFocus?.unfocus();
    context.push('/person', extra: key);
  }

  bool _matches(PersonSummary p, String q) =>
      q.isEmpty || p.searchText.contains(q);

  Future<void> _notNow(PersonSummary p) async {
    final messenger = ScaffoldMessenger.of(context);
    final dock = MediaQuery.paddingOf(context).bottom;
    await PeopleStore.driftNotNow(p.key, DateTime.now());
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(20, 0, 20, dock),
        content: Text(
          'Okay. Echo won’t bring up ${firstNameOf(p.name)} this week.',
        ),
      ),
    );
  }

  Future<void> _sayHi(PersonSummary p) async {
    final detail = await PersonDetailStore.load(p.key, DateTime.now());
    if (!mounted) return;
    final sent = await showPersonDraftSheet(
      context,
      PersonDraft(
        kind: PersonDraftKind.hi,
        name: p.name,
        source: p.source,
        to: detail.replyTo,
      ),
    );
    if (sent != null) {
      await PeopleStore.driftNotNow(p.key, DateTime.now());
    }
  }

  Future<void> _wish(PersonSummary p) async {
    final detail = await PersonDetailStore.load(p.key, DateTime.now());
    if (!mounted) return;
    final note = p.birthday;
    final sent = await showPersonDraftSheet(
      context,
      PersonDraft(
        kind: PersonDraftKind.wish,
        name: p.name,
        source: p.source,
        to: detail.replyTo,
        context: note == null ? null : 'Wished in ${note.groups.join(' and ')}.',
      ),
    );
    if (sent != null) await PeopleStore.markWished(p.key, DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _search.text.trim().toLowerCase();
    final birthdays = _feed.birthdays.where((p) => _matches(p, q)).toList();
    final drifting = _feed.drifting.where((p) => _matches(p, q)).toList();
    final loops = _feed.loops.where((p) => _matches(p, q)).toList();
    final everyone = _feed.everyone.where((p) => _matches(p, q)).toList();
    final total = _feed.everyone.length;
    final nothing =
        birthdays.isEmpty &&
        drifting.isEmpty &&
        loops.isEmpty &&
        everyone.isEmpty;
    final noOneYet = _loaded && total == 0 && _feed.birthdays.isEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              sliver: SliverToBoxAdapter(
                child: FadeSlideIn(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'People',
                        style: GoogleFonts.oldStandardTt(
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Who’s been in touch, and what’s still open.',
                        style: GoogleFonts.nunito(
                          fontSize: 14.5,
                          height: 1.4,
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!noOneYet) _SearchField(controller: _search),
                    ],
                  ),
                ),
              ),
            ),
            if (noOneYet)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _NoOneYet(
                  listening: _listening,
                  onTurnOn: _requestAccess,
                  onHears: () => context.push('/you/hears'),
                ),
              )
            else ...[
              if (birthdays.isNotEmpty)
                _padded(
                  Column(
                    children: [
                      for (final p in birthdays)
                        Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: _BirthdayCard(
                            person: p,
                            query: q,
                            onOpen: () => _open(p.key),
                            onWish: () => _wish(p),
                          ),
                        ),
                    ],
                  ),
                ),
              if (drifting.isNotEmpty)
                _padded(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const PeopleSection(
                        'Gone quiet',
                        note: 'fewer messages than usual',
                      ),
                      for (final (i, p) in drifting.indexed)
                        Padding(
                          padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                          child: _DriftCard(
                            key: ValueKey(p.key),
                            person: p,
                            query: q,
                            onOpen: () => _open(p.key),
                            onMessage: () => _sayHi(p),
                            onNotNow: () => _notNow(p),
                          ),
                        ),
                    ],
                  ),
                ),
              if (loops.isNotEmpty)
                _padded(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const PeopleSection('Open loops', note: 'both ways'),
                      AskCard(
                        padding: EdgeInsets.zero,
                        child: Material(
                          type: MaterialType.transparency,
                          clipBehavior: Clip.antiAlias,
                          borderRadius: BorderRadius.circular(24),
                          child: Column(
                            children: [
                              for (final (i, p) in loops.indexed)
                                _LoopRow(
                                  person: p,
                                  first: i == 0,
                                  query: q,
                                  onTap: () => _open(p.key),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (everyone.isNotEmpty)
                _padded(
                  PeopleSection(
                    q.isEmpty ? 'Recently' : 'Everyone',
                    note: q.isEmpty
                        ? '$total ${total == 1 ? 'person' : 'people'}'
                        : '${everyone.length} of $total',
                  ),
                ),
              if (everyone.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: DecoratedSliver(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: c.dividerColor.withValues(alpha: 0.5),
                      ),
                    ),
                    sliver: SliverList.builder(
                      itemCount: everyone.length,
                      itemBuilder: (context, i) => _EveryoneRow(
                        key: ValueKey(everyone[i].key),
                        person: everyone[i],
                        first: i == 0,
                        query: q,
                        onTap: () => _open(everyone[i].key),
                      ),
                    ),
                  ),
                ),
              if (nothing && _loaded)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _NoMatch(query: _search.text.trim()),
                ),
            ],
            SliverToBoxAdapter(
              child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 28),
            ),
          ],
        ),
      ),
    );
  }

  Widget _padded(Widget child) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    sliver: SliverToBoxAdapter(child: child),
  );
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;

  const _SearchField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, _) => Container(
        height: 50,
        padding: const EdgeInsets.only(left: 16, right: 6),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Symbols.search_rounded, size: 21, color: c.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                style: GoogleFonts.nunito(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
                cursorColor: c.primaryGreen,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search people',
                  hintStyle: GoogleFonts.nunito(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w500,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ),
            AnimatedOpacity(
              duration: AppMotion.fast,
              opacity: value.text.isEmpty ? 0 : 1,
              child: IconButton(
                onPressed: value.text.isEmpty
                    ? null
                    : () => controller.clear(),
                icon: Icon(
                  Symbols.close_rounded,
                  size: 20,
                  color: c.textSecondary,
                ),
                tooltip: 'Clear',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The page with no one on it yet: nothing heard, for one of two reasons.
class _NoOneYet extends StatelessWidget {
  final bool listening;
  final VoidCallback onTurnOn;
  final VoidCallback onHears;

  const _NoOneYet({
    required this.listening,
    required this.onTurnOn,
    required this.onHears,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const EchoMascot(
            state: EchoState.idle,
            size: 84,
            showRings: false,
            glow: false,
          ),
          const SizedBox(height: 16),
          Text(
            listening ? 'No one yet' : 'Echo can’t hear your chats',
            textAlign: TextAlign.center,
            style: GoogleFonts.oldStandardTt(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            listening
                ? 'People show up here once their messages reach this phone '
                      'through the apps Echo hears.'
                : 'Turn on notification access and the people who write to '
                      'you will show up here.',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 14,
              height: 1.45,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          listening
              ? PeoplePill(
                  label: 'Apps Echo hears',
                  icon: Symbols.apps_rounded,
                  onTap: onHears,
                )
              : PeoplePill(
                  label: 'Turn on access',
                  icon: Symbols.notifications_active_rounded,
                  filled: true,
                  onTap: onTurnOn,
                ),
        ],
      ),
    );
  }
}

class _NoMatch extends StatelessWidget {
  final String query;

  const _NoMatch({required this.query});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 40),
      child: Column(
        children: [
          const EchoMascot(
            state: EchoState.idle,
            size: 84,
            showRings: false,
            glow: false,
          ),
          const SizedBox(height: 12),
          Text(
            'No one called “$query”',
            textAlign: TextAlign.center,
            style: GoogleFonts.oldStandardTt(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Echo only knows people whose messages reached this phone '
            'through the apps it hears.',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 13.5,
              height: 1.45,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BirthdayCard extends StatefulWidget {
  final PersonSummary person;
  final String query;
  final VoidCallback onOpen;
  final VoidCallback onWish;

  const _BirthdayCard({
    required this.person,
    required this.query,
    required this.onOpen,
    required this.onWish,
  });

  @override
  State<_BirthdayCard> createState() => _BirthdayCardState();
}

class _BirthdayCardState extends State<_BirthdayCard> {
  bool _reminding = false;

  String get _key =>
      'birthday:${widget.person.key}@${DateTime.now().year}';

  @override
  void initState() {
    super.initState();
    Reminders.setFor(_key).then((at) {
      if (mounted && at != null) setState(() => _reminding = true);
    });
  }

  Future<void> _toggleRemind() async {
    final now = DateTime.now();
    final at = nextNine(now);
    if (at == null) return;
    final first = firstNameOf(widget.person.name);
    final on = await toggleReminder(
      key: _key,
      at: at,
      title: 'Wish $first',
      body: 'It’s $first’s birthday today.',
    );
    if (!mounted) return;
    setState(() => _reminding = on);
    showPeopleSnack(
      context,
      on ? 'Reminder set for ${_ampm(at)}.' : 'Reminder removed.',
    );
  }

  static String _ampm(DateTime at) => at.hour < 12 ? '9 AM' : '9 PM';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.person;
    final note = p.birthday!;
    final first = firstNameOf(p.name);
    final wished = note.wishedAt;
    final nine = nextNine(DateTime.now());
    final wishers = note.wishers;
    final shown = wishers.take(2).map(firstNameOf).join(', ');
    final others = wishers.length - 2;
    final bg = Color.alphaBlend(
      c.primaryGreen.withValues(alpha: 0.13),
      c.surface,
    );
    return FadeSlideIn(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.primaryGreen.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onOpen,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PersonAvatar(name: p.name, size: 48, source: p.source),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Today',
                          style: GoogleFonts.nunito(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: c.primaryGreen,
                          ),
                        ),
                        Text(
                          'It’s $first’s birthday',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.oldStandardTt(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          wished == null
                              ? 'Wished in ${note.groups.join(' and ')}. '
                                    'You haven’t yet.'
                              : 'Wished in ${note.groups.join(' and ')}, and '
                                    'by you.',
                          style: GoogleFonts.nunito(
                            fontSize: 13.5,
                            height: 1.4,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              others > 0
                  ? '$shown and $others ${others == 1 ? 'other' : 'others'} wished $first'
                  : '$shown wished $first',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.nunito(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            if (wished != null)
              Row(
                children: [
                  Icon(
                    Symbols.check_circle_rounded,
                    fill: 1,
                    size: 19,
                    color: c.primaryGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You wished $first',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: c.primaryGreen,
                      ),
                    ),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PeoplePill(
                    label: pillWith('Wish', first),
                    icon: Symbols.cake_rounded,
                    filled: true,
                    onTap: widget.onWish,
                  ),
                  if (nine != null || _reminding)
                    PeoplePill(
                      label: _reminding
                          ? 'Reminding at ${_ampm(nine ?? DateTime.now())}'
                          : 'Remind me at ${_ampm(nine!)}',
                      icon: _reminding
                          ? Symbols.notifications_active_rounded
                          : Symbols.alarm_rounded,
                      set: _reminding,
                      onTap: _toggleRemind,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DriftCard extends StatefulWidget {
  final PersonSummary person;
  final String query;
  final VoidCallback onOpen;
  final VoidCallback onMessage;
  final VoidCallback onNotNow;

  const _DriftCard({
    super.key,
    required this.person,
    required this.query,
    required this.onOpen,
    required this.onMessage,
    required this.onNotNow,
  });

  @override
  State<_DriftCard> createState() => _DriftCardState();
}

class _DriftCardState extends State<_DriftCard> {
  bool _leaving = false;

  void _notNow() {
    setState(() => _leaving = true);
    Future<void>.delayed(AppMotion.medium, widget.onNotNow);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.person;
    final drift = p.drift!;
    final first = firstNameOf(p.name);
    return AnimatedOpacity(
      duration: AppMotion.fast,
      opacity: _leaving ? 0 : 1,
      child: AnimatedSize(
        duration: AppMotion.medium,
        curve: AppMotion.standard,
        alignment: Alignment.topCenter,
        child: _leaving
            ? const SizedBox(width: double.infinity)
            : AskCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onOpen,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PersonAvatar(
                            name: p.name,
                            size: 44,
                            source: p.source,
                            ring: (age: 1, progress: drift.progress),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                HighlightedName(
                                  p.name,
                                  query: widget.query,
                                  style: GoogleFonts.nunito(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                    color: c.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  drift.line,
                                  style: GoogleFonts.nunito(
                                    fontSize: 13,
                                    height: 1.4,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          WeekBars(bars: drift.bars, low: drift.low),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        PeoplePill(
                          label: pillWith('Message', first),
                          icon: Symbols.chat_bubble_rounded,
                          filled: true,
                          onTap: widget.onMessage,
                        ),
                        PeoplePill(label: 'Not now', onTap: _notNow),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _LoopRow extends StatelessWidget {
  final PersonSummary person;
  final bool first;
  final String query;
  final VoidCallback onTap;

  const _LoopRow({
    required this.person,
    required this.first,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final loops = person.loops;
    final owe = loops.owe.length;
    final owes = loops.owes.length;
    return PeopleRow(
      first: first,
      onTap: onTap,
      child: Row(
        children: [
          PersonAvatar(
            name: person.name,
            size: 40,
            source: person.source,
            ring: owe == 0
                ? null
                : (
                    age: loops.oweAge,
                    progress: loops.oweProgress == 0 ? 0.3 : loops.oweProgress,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HighlightedName(
                  person.name,
                  query: query,
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (owe > 0) AgeTag('You owe $owe', age: loops.oweAge),
                    if (owes > 0) AgeTag('Owes you $owes'),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  loops.bits,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const RowChevron(),
        ],
      ),
    );
  }
}

class _EveryoneRow extends StatelessWidget {
  final PersonSummary person;
  final bool first;
  final String query;
  final VoidCallback onTap;

  const _EveryoneRow({
    super.key,
    required this.person,
    required this.first,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    return PressFeedback(
      scale: 0.985,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: first
              ? null
              : BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: c.dividerColor.withValues(alpha: 0.6),
                    ),
                  ),
                ),
          child: Row(
            children: [
              PersonAvatar(
                name: person.name,
                size: 40,
                source: person.source,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HighlightedName(
                      person.name,
                      query: query,
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      '${person.rhythm} · ${appNames(person.sources)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AppIcons(person.sources),
                  const SizedBox(height: 5),
                  Text(
                    lastShort(person.lastAt, now),
                    maxLines: 1,
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
