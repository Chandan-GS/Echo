import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/services/engine_gate.dart';
import 'package:project_echo/core/services/model_download_service.dart';
import 'package:project_echo/core/services/offline_model_repository.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/settings/data/writing_pack.dart';
import 'package:project_echo/features/settings/presentation/widgets/settings_kit.dart';

const writingPackIntro =
    'Echo works without it. The pack writes drafts, answers Ask Echo in full '
    'sentences and reads briefings aloud, all on this phone.';

/// Settings → Writing pack: the real on-device model, its download, and
/// removing it. Echo's core needs none of this.
class WritingPackPage extends StatefulWidget {
  const WritingPackPage({super.key});

  @override
  State<WritingPackPage> createState() => _WritingPackPageState();
}

class _WritingPackPageState extends State<WritingPackPage> {
  bool _checking = true;
  bool _wifiOnly = true;
  int _kept = 0;
  String? _notice;

  EngineDownload get _download => EngineDownload.instance;

  @override
  void initState() {
    super.initState();
    _download.state.addListener(_onDownload);
    _load();
  }

  @override
  void dispose() {
    _download.state.removeListener(_onDownload);
    super.dispose();
  }

  Future<void> _load() async {
    final wifiOnly = await WritingPack.wifiOnly();
    await WritingPack.refresh();
    final kept = await _download.keptBytes();
    if (!mounted) return;
    setState(() {
      _wifiOnly = wifiOnly;
      _kept = kept;
      _checking = false;
    });
  }

  /// Once a download stops, what it kept is worth saying.
  void _onDownload() {
    if (!_download.state.value.downloading) _refreshKept();
  }

  Future<void> _refreshKept() async {
    final kept = await _download.keptBytes();
    if (mounted) setState(() => _kept = kept);
  }

  Future<void> _start() async {
    setState(() => _notice = null);
    if (_wifiOnly && await currentNetworkKind() == NetworkKind.mobile) {
      if (!mounted) return;
      setState(() {
        _notice =
            'You’re on mobile data. Connect to Wi-Fi, or turn off “Download '
            'on Wi-Fi only”.';
      });
      return;
    }
    await _download.start();
  }

  void _cancel() {
    _download.cancel();
    settingsToast(context, 'Stopped. It picks up from here next time');
  }

  Future<void> _discard() async {
    await WritingPack.discardPartial();
    await _refreshKept();
  }

  Future<void> _setWifiOnly(bool on) async {
    setState(() {
      _wifiOnly = on;
      _notice = null;
    });
    await WritingPack.setWifiOnly(on);
    if (!mounted) return;
    settingsToast(
      context,
      on ? 'Downloads wait for Wi-Fi' : 'Downloads can use mobile data',
    );
  }

  /// Why the last download stopped, if it did.
  String? _problem(ModelDownloadState download) =>
      switch (_download.state.value.problem) {
        DownloadProblem.offline =>
          'Can’t reach the download. Check your connection and try again.',
        DownloadProblem.noSpace =>
          'Your phone is out of space. Free some up and try again.',
        DownloadProblem.failed => 'The download stopped. Try again.',
        null =>
          download.phase == ModelDownloadPhase.error
              ? 'The download didn’t finish. Check your connection and try '
                    'again.'
              : null,
      };

  Future<void> _remove(WritingPackStatus pack) async {
    final freed = pack.size ?? offlineModelSizeLabel();
    final ok = await confirmSettingsAction(
      context,
      title: 'Remove the writing pack?',
      body:
          'This frees $freed. Echo keeps working: waiting, to-dos and History '
          'don’t need it. Drafts go back to your own words until you download '
          'it again.',
      confirm: 'Remove',
    );
    if (!ok) return;
    await WritingPack.remove();
    if (mounted) settingsToast(context, 'Writing pack removed');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Symbols.memory_rounded, size: 24, color: c.primaryGreen),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Writing pack',
                      style: GoogleFonts.nunito(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${offlineModelDisplayName()}. Runs offline, no API cost, '
                'nothing leaves your phone.',
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  height: 1.45,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _tag(context, offlineModelSizeLabel()),
                  _tag(context, 'On this phone'),
                ],
              ),
              const SizedBox(height: 14),
              ListenableBuilder(
                listenable: Listenable.merge([
                  ModelDownloadService.instance.state,
                  _download.state,
                  WritingPack.status,
                ]),
                builder: (context, _) => AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _body(
                    context,
                    ModelDownloadService.instance.state.value,
                    WritingPack.status.value,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SettingsSwitchCard(
          icon: Symbols.wifi_rounded,
          title: 'Download on Wi-Fi only',
          value: 'Won’t start on mobile data',
          on: _wifiOnly,
          onChanged: _setWifiOnly,
        ),
        const SettingsSubLabel('Without the pack'),
        SettingsGroup(
          rows: const [
            _PackRow(
              icon: Symbols.check_circle_rounded,
              filled: true,
              title: 'Everything that keeps people from waiting',
              body: 'Who’s waiting, to-dos, money and dates in groups, History, '
                  'quiet hours.',
            ),
            _PackRow(
              icon: Symbols.short_text_rounded,
              title: 'Holding replies, not written drafts',
              body: 'Quick notes like “On it, give me 10 min” instead of a '
                  'written draft.',
            ),
            _PackRow(
              icon: Symbols.format_list_bulleted_rounded,
              title: 'Ask Echo finds, doesn’t write',
              body: 'It shows the messages that answer you, without a summary.',
            ),
          ],
        ),
      ],
    );
  }

  Widget _tag(BuildContext context, String text) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: c.dividerColor),
      ),
      child: Text(
        text,
        style: GoogleFonts.nunito(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: c.textSecondary,
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ModelDownloadState download,
    WritingPackStatus pack,
  ) {
    final c = context.colors;
    final small = GoogleFonts.nunito(fontSize: 12.5, color: c.textSecondary);
    if (_checking && download.phase != ModelDownloadPhase.downloading) {
      return const SizedBox(key: ValueKey('checking'), height: 50);
    }
    if (download.phase == ModelDownloadPhase.downloading) {
      final pct = (download.progress * 100).toInt();
      return Column(
        key: const ValueKey('downloading'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Downloading the pack…',
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
              ),
              Text(
                '$pct%',
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: c.primaryGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: download.progress,
              minHeight: 10,
              backgroundColor: c.dividerColor,
              color: c.primaryGreen,
            ),
          ),
          if (_download.running)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(child: Text(_amounts(), style: small)),
                  TextButton(
                    onPressed: _cancel,
                    child: Text(
                      'Cancel',
                      style: small.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    if (pack.ready) {
      return Row(
        key: const ValueKey('ready'),
        children: [
          Icon(
            Symbols.check_circle_rounded,
            fill: 1,
            size: 20,
            color: c.primaryGreen,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${pack.size ?? offlineModelSizeLabel()} · Ready',
              style: GoogleFonts.nunito(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => _remove(pack),
            icon: Icon(
              Symbols.delete_rounded,
              size: 17,
              color: context.warmAccent,
            ),
            label: Text(
              'Remove',
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: context.warmAccent,
              ),
            ),
            style: TextButton.styleFrom(
              backgroundColor: context.warmAccent.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            ),
          ),
        ],
      );
    }
    return Column(
      key: const ValueKey('download'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_notice ?? _problem(download) case final message?) ...[
          Text(
            message,
            style: GoogleFonts.nunito(
              fontSize: 13,
              height: 1.4,
              color: context.warmAccent,
            ),
          ),
          const SizedBox(height: 10),
        ],
        ElevatedButton.icon(
          onPressed: _start,
          icon: const Icon(Symbols.download_rounded, size: 20),
          label: Text(
            _kept > 0
                ? 'Continue download (${packSizeLabel(_kept)} kept)'
                : 'Download (${offlineModelSizeLabel()})',
            style: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: c.primaryGreen,
            foregroundColor: c.textInverse,
            minimumSize: const Size.fromHeight(50),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        if (_kept > 0)
          TextButton(
            onPressed: _discard,
            child: Text(
              'Discard what’s kept',
              style: small.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  /// "340 MB of 910 MB".
  String _amounts() {
    final s = _download.state.value;
    return s.total > 0
        ? '${packSizeLabel(s.received)} of ${packSizeLabel(s.total)}'
        : 'Starting…';
  }
}

class _PackRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool filled;

  const _PackRow({
    required this.icon,
    required this.title,
    required this.body,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 22,
            fill: filled ? 1 : 0,
            color: filled ? c.primaryGreen : c.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.nunito(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    height: 1.45,
                    color: c.textSecondary,
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
