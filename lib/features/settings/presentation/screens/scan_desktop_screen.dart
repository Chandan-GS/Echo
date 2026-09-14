import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:project_echo/core/services/desktop_engine_client.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';

/// Full-screen QR scanner for pairing this phone with a desktop Echo Engine —
/// the camera-side counterpart of the QR the desktop shows in its own
/// Settings. A successful scan calls [DesktopEngineClient.pairViaQrPayload],
/// which both authenticates this phone and hands back the desktop's name.
class ScanDesktopScreen extends StatefulWidget {
  const ScanDesktopScreen({super.key});

  @override
  State<ScanDesktopScreen> createState() => _ScanDesktopScreenState();
}

class _ScanDesktopScreenState extends State<ScanDesktopScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  // Guards against firing pairViaQrPayload multiple times for the same
  // QR frame while the first attempt is still in flight.
  bool _handling = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;

    setState(() {
      _handling = true;
      _error = null;
    });

    final result = await DesktopEngineClient.pairViaQrPayload(raw);
    if (!mounted) return;

    if (result == null) {
      setState(() {
        _handling = false;
        _error = "Couldn't connect — make sure your phone and computer are "
            "on the same Wi-Fi and try again.";
      });
      return;
    }

    await context.read<SettingsCubit>().pairedWithDesktop(
          host: result.host,
          name: result.desktopName,
        );
    if (!mounted) return;
    context.pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Connected to ${result.desktopName}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // Dimmed frame overlay — a plain guide rectangle, not a true
          // cutout, to keep this simple.
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _error != null ? Colors.redAccent : Colors.white,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    _handling
                        ? 'Connecting…'
                        : 'Point your camera at the QR code shown on your '
                            "computer's Settings screen",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        color: Colors.redAccent.shade100,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
