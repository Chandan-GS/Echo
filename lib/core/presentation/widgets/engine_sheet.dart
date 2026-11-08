import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/desktop_engine_client.dart';
import 'package:project_echo/core/services/engine_gate.dart';
import 'package:project_echo/core/services/gemini_service.dart';
import 'package:project_echo/core/services/model_download_service.dart';
import 'package:project_echo/core/services/offline_model_repository.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/screens/cloud_consent_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum _Pick { phone, computer, gemini }

/// "How should Echo write?", asked the first time something needs it. Pops
/// true when an engine is ready, false for search-only or a download left
/// running, null when dismissed.
Future<bool?> showEngineSheet(BuildContext context, {required String reason}) {
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 460),
      curve: Cubic(0.2, 0.9, 0.25, 1),
      reverseDuration: Duration(milliseconds: 240),
      reverseCurve: Curves.easeInCubic,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    builder: (context) => _EngineSheet(reason: reason),
  );
}

class _EngineSheet extends StatefulWidget {
  final String reason;
  const _EngineSheet({required this.reason});

  @override
  State<_EngineSheet> createState() => _EngineSheetState();
}

class _EngineSheetState extends State<_EngineSheet> {
  final _key = TextEditingController();
  final _keyFocus = FocusNode();

  var _pick = _Pick.phone;
  var _keptBytes = 0;
  String? _computerName;
  String? _computerHost;

  /// Asked once before a big download on mobile data.
  var _mobileOk = false;

  var _busy = false;
  String? _notice;
  var _closing = false;

  ModelDownloadService get _service => ModelDownloadService.instance;
  EngineDownload get _download => EngineDownload.instance;

  bool get _downloading =>
      _download.running ||
      _service.state.value.phase == ModelDownloadPhase.downloading;

  @override
  void initState() {
    super.initState();
    _service.state.addListener(_onProgress);
    _download.state.addListener(_onProgress);
    _load();
  }

  @override
  void dispose() {
    _service.state.removeListener(_onProgress);
    _download.state.removeListener(_onProgress);
    _key.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  void _onProgress() {
    if (!mounted) return;
    setState(() {});
    if (_service.state.value.phase == ModelDownloadPhase.done &&
        _pick == _Pick.phone) {
      _finish('Echo will write on this phone. Nothing leaves it.');
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final kept = await _download.keptBytes();
    if (!mounted) return;
    setState(() {
      _keptBytes = kept;
      _computerHost = prefs.getString('desktop_engine_host');
      final name = prefs.getString('desktop_engine_name')?.trim();
      final token = prefs.getString('desktop_engine_token');
      final paired =
          (_computerHost?.isNotEmpty ?? false) &&
          ((name?.isNotEmpty ?? false) || (token?.isNotEmpty ?? false));
      _computerName = paired
          ? ((name?.isNotEmpty ?? false) ? name : 'your computer')
          : null;
      // A download that stopped while the sheet was closed.
      _notice = _problemMessage(_download.state.value.problem);
    });
  }

  void _choose(_Pick pick) {
    if (_downloading || _busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pick = pick;
      _notice = null;
    });
    if (pick == _Pick.gemini) {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted) _keyFocus.requestFocus();
      });
    }
  }

  void _finish(String message) {
    if (!mounted || _closing) return;
    _closing = true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    EngineGate.setSearchOnly(false);
    Navigator.of(context).pop(true);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _go() async {
    if (_downloading || _busy) return;
    HapticFeedback.lightImpact();
    switch (_pick) {
      case _Pick.phone:
        await _usePhone();
      case _Pick.computer:
        await _useComputer();
      case _Pick.gemini:
        await _useGemini();
    }
  }

  Future<void> _usePhone() async {
    final settings = context.read<SettingsCubit>();
    if (await createOfflineModelRepository().isModelDownloaded()) {
      await settings.setAiEngine(isOffline: true);
      _finish('Echo will write on this phone. Nothing leaves it.');
      return;
    }
    if (await currentNetworkKind() == NetworkKind.mobile && !_mobileOk) {
      if (!mounted) return;
      setState(() {
        _mobileOk = true;
        _notice =
            "You're on mobile data, and this is a ${_sizeLabel()} download. "
            'Tap again to use it anyway, or connect to Wi-Fi.';
      });
      return;
    }
    if (!mounted) return;
    setState(() => _notice = null);
    // Set now, so a download left to finish in the background counts.
    await settings.setAiEngine(isOffline: true);
    await EngineGate.setSearchOnly(false);
    final finished = await _download.start();
    if (finished) return _finish('Echo will write on this phone. Nothing leaves it.');
    if (!mounted) return;
    final kept = await _download.keptBytes();
    if (!mounted) return;
    setState(() {
      _keptBytes = kept;
      _notice = _problemMessage(_download.state.value.problem);
    });
  }

  String? _problemMessage(DownloadProblem? problem) => switch (problem) {
    null => null,
    DownloadProblem.offline =>
      "Can't reach the download. Check your connection and try again. "
          'It will pick up where it stopped.',
    DownloadProblem.noSpace =>
      "Your phone is out of space. Free up ${_spaceNeeded()} and try again.",
    DownloadProblem.failed =>
      'The download stopped. Try again and it will pick up where it left off.',
  };

  String _spaceNeeded() {
    final s = _download.state.value;
    final left = s.total > s.received ? s.total - s.received : 0;
    return left > 0 ? 'about ${_mb(left)} MB' : 'some space';
  }

  Future<void> _useComputer() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    final settings = context.read<SettingsCubit>();
    final host = await DesktopEngineClient.discoverHost(
      cachedHost: _computerHost,
    );
    if (!mounted) return;
    if (host == null) {
      setState(() {
        _busy = false;
        _notice =
            "Can't reach ${_computerName ?? 'your computer'} right now. Make "
            "sure it's awake and on the same Wi-Fi.";
      });
      return;
    }
    await settings.setDesktopEngineHost(host);
    await settings.setPreferDesktopEngine(true);
    _finish('Echo will write on ${_computerName ?? 'your computer'}.');
  }

  Future<void> _useGemini() async {
    final key = _key.text.trim();
    if (key.isEmpty) {
      setState(() => _notice = 'Paste your Gemini API key first.');
      _keyFocus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    final valid = await GeminiService.instance.validateKey(key);
    if (!mounted) return;
    if (!valid) {
      final online = await _canReachGoogle();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice = online
            ? "That key didn't work. Check it and try again."
            : "Can't check the key without a connection. Try again when "
                  "you're back online.";
      });
      return;
    }
    // Nothing is switched on until they've read what gets sent.
    final agreed = await Navigator.of(context, rootNavigator: true).push<bool>(
      bouncyRoute(const CloudConsentPage(alreadyOn: false)),
    );
    if (!mounted) return;
    if (agreed != true) {
      setState(() => _busy = false);
      return;
    }
    final settings = context.read<SettingsCubit>();
    await settings.setGeminiApiKey(key);
    await settings.setAiEngine(isOffline: false);
    _finish('Key works. Echo will use Gemini.');
  }

  static Future<bool> _canReachGoogle() async {
    try {
      final found = await InternetAddress.lookup(
        'generativelanguage.googleapis.com',
      ).timeout(const Duration(seconds: 3));
      return found.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Search-only. A running download keeps going in the background.
  void _skip() {
    HapticFeedback.selectionClick();
    final running = _downloading;
    if (!running) EngineGate.setSearchOnly(true);
    Navigator.of(context).pop(false);
  }

  void _cancelDownload() {
    _download.cancel();
    setState(() => _notice = null);
  }

  Future<void> _paste() async {
    final clip = await Clipboard.getData('text/plain');
    final text = clip?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    setState(() => _key.text = text);
  }

  Future<void> _getKey() async {
    final url = Uri.parse('https://aistudio.google.com/app/apikey');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// "0.9 GB", from the model's real size label.
  String _sizeLabel() => offlineModelSizeLabel().replaceAll('~', '');

  static String _mb(int bytes) => (bytes / (1024 * 1024)).round().toString();

  String get _goLabel {
    if (_busy) {
      return _pick == _Pick.gemini ? 'Checking your key…' : 'Connecting…';
    }
    if (_downloading) return 'Downloading…';
    return switch (_pick) {
      _Pick.computer => 'Use ${_computerName ?? 'my computer'}',
      _Pick.gemini => 'Use Gemini',
      _Pick.phone =>
        _download.state.value.problem != null
            ? 'Try again'
            : _keptBytes > 0
            ? 'Resume download'
            : _mobileOk && _notice != null
            ? 'Download on mobile data'
            : 'Download and continue',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final draft = widget.reason == 'draft';
    final bottom =
        MediaQuery.viewInsetsOf(context).bottom +
        MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.dividerColor,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'How should Echo write?',
                style: GoogleFonts.oldStandardTt(
                  fontSize: 28,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                draft
                    ? 'Drafting replies needs a small language model. You '
                          'choose once, and can change it in Settings.'
                    : 'Answering in sentences needs a small language model. '
                          'You choose once, and can change it in Settings.',
                style: GoogleFonts.nunito(
                  fontSize: 14.5,
                  height: 1.5,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              _choices(c),
              if (_downloading) _progress(c),
              AnimatedSize(
                duration: AppMotion.fast,
                curve: AppMotion.emphasized,
                alignment: Alignment.topCenter,
                child: _notice == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(
                          _notice!,
                          style: GoogleFonts.nunito(
                            fontSize: 13.5,
                            height: 1.45,
                            fontWeight: FontWeight.w700,
                            color: context.warmAccent,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 20),
              EchoButton(
                text: _goLabel,
                onPressed: _downloading || _busy ? null : _go,
              ),
              const SizedBox(height: 6),
              if (_downloading)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: TextButton(
                        onPressed: _skip,
                        style: TextButton.styleFrom(
                          foregroundColor: c.textSecondary,
                        ),
                        child: Text(
                          'Keep going in the background',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (_download.running)
                      TextButton(
                        onPressed: _cancelDownload,
                        style: TextButton.styleFrom(
                          foregroundColor: c.textSecondary,
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                )
              else
                TextButton(
                  onPressed: _busy ? null : _skip,
                  style: TextButton.styleFrom(
                    foregroundColor: c.textSecondary,
                  ),
                  child: Text(
                    'Skip for now. Echo will just search.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choices(AppColors c) {
    final choices = [
      _Choice(
        icon: Symbols.smartphone_rounded,
        title: 'On this phone',
        body:
            'A ${_sizeLabel()} download. Works offline, and nothing leaves '
            'your phone.',
        selected: _pick == _Pick.phone,
        onTap: () => _choose(_Pick.phone),
      ),
      if (_computerName != null)
        _Choice(
          icon: Symbols.laptop_mac_rounded,
          title: 'On ${_computerName!}',
          body:
              'Uses the bigger model on your paired computer, over your '
              "Wi-Fi. Only while it's awake.",
          selected: _pick == _Pick.computer,
          onTap: () => _choose(_Pick.computer),
        ),
      _Choice(
        icon: Symbols.cloud_rounded,
        title: 'Gemini, with your own key',
        body: 'Quickest, with no download. Questions go to Google.',
        selected: _pick == _Pick.gemini,
        onTap: () => _choose(_Pick.gemini),
        more: _keyEntry(c),
      ),
    ];
    // While downloading, only the choice in progress stays.
    final shown = _downloading
        ? [choices.firstWhere((ch) => ch.selected, orElse: () => choices.first)]
        : choices;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: ColoredBox(
        color: c.background,
        child: Column(
          children: [
            for (final (i, choice) in shown.indexed) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 68),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: c.dividerColor.withValues(alpha: 0.6),
                  ),
                ),
              choice,
            ],
          ],
        ),
      ),
    );
  }

  Widget _progress(AppColors c) {
    final status = _service.state.value;
    final mine = _download.state.value;
    final detail = mine.total > 0
        ? '${_mb(mine.received)} of ${_mb(mine.total)} MB'
        : '${(status.progress * 100).round()}%';
    final style = GoogleFonts.nunito(
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      color: c.textPrimary,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Downloading', style: style),
              Text(
                detail,
                style: style.copyWith(
                  color: c.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: status.progress > 0 ? status.progress : null,
              minHeight: 6,
              backgroundColor: c.dividerColor,
              color: c.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _keyEntry(AppColors c) {
    final link = GoogleFonts.nunito(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      color: c.primaryGreen,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _key,
          focusNode: _keyFocus,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          cursorColor: c.primaryGreen,
          style: GoogleFonts.nunito(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Paste your Gemini API key',
            hintStyle: GoogleFonts.nunito(
              fontSize: 14,
              color: c.textSecondary,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: c.dividerColor, width: 1.5),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: c.primaryGreen, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            GestureDetector(
              onTap: _paste,
              child: Text('Paste', style: link),
            ),
            GestureDetector(
              onTap: _getKey,
              child: Text('Get a key', style: link),
            ),
            GestureDetector(
              onTap: () =>
                  Navigator.of(context, rootNavigator: true).push<bool>(
                    bouncyRoute(const CloudConsentPage(alreadyOn: true)),
                  ),
              child: Text('What gets sent', style: link),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          "Only your question and the few messages it needs go to Google. "
          "One-time codes are taken out first, and nothing is ever sent from apps you've switched off.",
          style: GoogleFonts.nunito(
            fontSize: 12.5,
            height: 1.5,
            color: c.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// One row of the choice list: an icon disc, what it is, and a radio.
class _Choice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool selected;
  final VoidCallback onTap;

  /// Shown under the text while this choice is selected.
  final Widget? more;

  const _Choice({
    required this.icon,
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
    this.more,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressFeedback(
      scale: 0.99,
      child: Material(
        color: selected
            ? Color.lerp(c.background, context.selectionFill, 0.4)!
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: AppMotion.fast,
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected ? c.primaryGreen : c.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 21,
                    color: selected ? c.textInverse : c.textPrimary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.nunito(
                          fontSize: 15.5,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        body,
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          height: 1.45,
                          color: c.textSecondary,
                        ),
                      ),
                      if (selected && more != null) ...[
                        const SizedBox(height: 12),
                        more!,
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: 2,
                        color: selected
                            ? c.primaryGreen
                            : c.textSecondary.withValues(alpha: 0.55),
                      ),
                    ),
                    child: AnimatedScale(
                      scale: selected ? 1 : 0,
                      duration: AppMotion.medium,
                      curve: AppMotion.spring,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: c.primaryGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
