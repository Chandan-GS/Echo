import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/services/desktop_engine_client.dart';
import 'package:project_echo/core/services/echo_server_service.dart';
import 'package:project_echo/core/services/offline_model_repository.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';

/// Phone-first, computer-optional connection controls — and, crucially, each
/// platform shows only the half that makes sense for it, so the two toggles
/// can't be confused:
///
///  • Phone: "Use my computer" — discover a computer on the Wi-Fi and offload
///    to it (+ mirror this phone's data there).
///  • Computer (macOS/Windows): "Run Echo Engine here" — serve this machine as
///    the engine for the phone. Never shows the phone's "use a computer" toggle
///    (a computer serving itself has nothing to reach out to).
///
/// Deliberately name-free: nobody needs to see "Connected to Chandan's
/// MacBook" — just whether it's connected, and (when it isn't) plain,
/// step-by-step instructions for how to get there.
class DesktopEngineSection extends StatefulWidget {
  const DesktopEngineSection({super.key});

  @override
  State<DesktopEngineSection> createState() => _DesktopEngineSectionState();
}

class _DesktopEngineSectionState extends State<DesktopEngineSection> {
  bool _checking = false;

  bool get _isDesktop => Platform.isMacOS || Platform.isWindows;

  Future<void> _checkNow(SettingsState state) async {
    setState(() => _checking = true);
    final host = await DesktopEngineClient.discoverHost(
      cachedHost: state.desktopEngineHost,
    );
    if (!mounted) return;
    setState(() => _checking = false);
    await context.read<SettingsCubit>().setDesktopEngineHost(host);
  }

  @override
  Widget build(BuildContext context) {
    // Computer: only the "run engine here" control.
    if (_isDesktop) return const _RunHereSection();

    // Phone: only the "use my computer" control.
    final colors = context.colors;
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) => _UseComputerCard(
        colors: colors,
        state: state,
        checking: _checking,
        onToggle: (v) {
          context.read<SettingsCubit>().setPreferDesktopEngine(v);
          if (v) _checkNow(state);
        },
        onCheckNow: () => _checkNow(state),
      ),
    );
  }
}

/// Phone-side card: opt in to using a computer on the same Wi-Fi. One clear
/// status line, and — only when not connected — one primary action (find it
/// automatically) plus a plain-language fallback (scan its QR code).
class _UseComputerCard extends StatelessWidget {
  final AppColors colors;
  final SettingsState state;
  final bool checking;
  final ValueChanged<bool> onToggle;
  final VoidCallback onCheckNow;

  const _UseComputerCard({
    required this.colors,
    required this.state,
    required this.checking,
    required this.onToggle,
    required this.onCheckNow,
  });

  @override
  Widget build(BuildContext context) {
    final connected = state.desktopEngineHost != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.laptop_mac_rounded, size: 20, color: colors.primaryGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Use my computer',
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Switch(
                value: state.preferDesktopEngine,
                activeTrackColor: colors.primaryGreen,
                onChanged: onToggle,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Offload briefings and Ask Echo to a computer running Echo on the '
            'same Wi-Fi for sharper results. Your phone still works on its own '
            'whenever the computer isn\'t reachable.',
            style: GoogleFonts.nunito(fontSize: 13, color: colors.textSecondary),
          ),
          if (state.preferDesktopEngine) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  connected ? Icons.check_circle_rounded : Icons.wifi_find_rounded,
                  size: 16,
                  color: connected ? colors.primaryGreen : colors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  checking
                      ? 'Looking for your computer…'
                      : connected
                          ? 'Connected to your computer'
                          : 'Not connected yet',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            if (!connected && !checking) ...[
              const SizedBox(height: 10),
              Text(
                'Open Echo on your computer and turn on "Run Echo Engine on this '
                'computer" in its Settings — then make sure both devices are on '
                'the same Wi-Fi.',
                style: GoogleFonts.nunito(fontSize: 12.5, color: colors.textSecondary),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCheckNow,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.textPrimary,
                        side: BorderSide(color: colors.dividerColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: Text(
                        'Find my computer',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/scan-desktop'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.primaryGreen,
                        side: BorderSide(color: colors.primaryGreen.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 15),
                      label: Text(
                        'Scan QR code',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (connected) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: checking ? null : onCheckNow,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: Text(
                    'Check again',
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Computer-side card: serve this machine as the engine. Runs on the on-device
/// Qwen model — no separate multi-GB download to manage. The QR code itself
/// stays out of sight until "Connect a phone" is tapped, instead of always
/// occupying space on the Settings screen.
class _RunHereSection extends StatelessWidget {
  const _RunHereSection();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final running = state.runDesktopEngineHere;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.dns_rounded, size: 20, color: colors.primaryGreen),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Run Echo Engine on this computer',
                      style: GoogleFonts.nunito(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Switch(
                    value: running,
                    activeTrackColor: colors.primaryGreen,
                    onChanged: (v) =>
                        context.read<SettingsCubit>().setRunDesktopEngineHere(v),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Let your phone offload briefings and Ask Echo to this computer '
                'over Wi-Fi, and mirror the phone’s notifications here. Uses the '
                'same ${offlineModelDisplayName()} model set up above in AI Engine.',
                style: GoogleFonts.nunito(fontSize: 13, color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: running ? colors.primaryGreen : colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    running ? 'Running — serving on this Wi-Fi' : 'Off',
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (running) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ValueListenableBuilder<List<PairedDevice>>(
                        valueListenable: EchoServerService.instance.pairedDevices,
                        builder: (context, devices, _) {
                          final count = devices.length;
                          return Text(
                            count == 0
                                ? 'No phones connected yet'
                                : '$count phone${count == 1 ? '' : 's'} connected',
                            style: GoogleFonts.nunito(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: colors.textSecondary,
                            ),
                          );
                        },
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => const _ConnectPhoneDialog(),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.primaryGreen,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      icon: const Icon(Icons.add_link_rounded, size: 16),
                      label: Text(
                        'Connect a phone',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A numbered instruction line — "1. Do this", "2. Then this" — used inside
/// [_ConnectPhoneDialog] so the steps read at a glance instead of as one
/// dense paragraph.
class _Step extends StatelessWidget {
  final String number;
  final String text;
  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.lightGreenBackground,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: GoogleFonts.nunito(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: colors.primaryGreen,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                text,
                style: GoogleFonts.nunito(
                  fontSize: 13.5,
                  color: colors.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The QR code lives here — revealed only when the user explicitly asks to
/// connect a phone, not sitting permanently on the Settings screen.
class _ConnectPhoneDialog extends StatefulWidget {
  const _ConnectPhoneDialog();

  @override
  State<_ConnectPhoneDialog> createState() => _ConnectPhoneDialogState();
}

class _ConnectPhoneDialogState extends State<_ConnectPhoneDialog> {
  late final Future<String?> _qrPayload = _build();

  Future<String?> _build() async {
    final service = EchoServerService.instance;
    final ip = await service.localLanIp();
    if (ip == null) return null;
    final token = await service.pairingToken();
    final name = await service.systemName();
    return jsonEncode({
      'host': ip,
      'port': EchoServerService.httpPort,
      'token': token,
      'name': name,
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Connect your phone',
                      style: GoogleFonts.oldStandardTt(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: colors.textSecondary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    iconSize: 20,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _Step(
                number: '1',
                text: 'Open Echo on your phone and go to Settings → Use my computer.',
              ),
              const _Step(
                number: '2',
                text: 'Turn it on — your phone finds this computer automatically '
                    'as long as both are on the same Wi-Fi.',
              ),
              const SizedBox(height: 4),
              Divider(color: colors.dividerColor),
              const SizedBox(height: 10),
              Text(
                "Not finding it automatically? Scan this from your phone's "
                '"Scan QR code" option instead:',
                style: GoogleFonts.nunito(fontSize: 12.5, color: colors.textSecondary),
              ),
              const SizedBox(height: 14),
              Center(
                child: FutureBuilder<String?>(
                  future: _qrPayload,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox(
                        width: 180,
                        height: 180,
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final payload = snapshot.data;
                    if (payload == null) {
                      return SizedBox(
                        width: 180,
                        height: 180,
                        child: Center(
                          child: Text(
                            "Couldn't find this computer's network address.",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.nunito(
                              fontSize: 12.5,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      );
                    }
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(data: payload, size: 180),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
