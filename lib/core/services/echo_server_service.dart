import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fllama/fllama.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'desktop_engine_client.dart';
import 'streak_service.dart';
import 'offline_model_repository.dart';
import 'system_info_service.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';

/// A phone that has paired with this computer's engine via QR — kept only for
/// display in Settings ("Paired devices").
class PairedDevice {
  final String name;
  final DateTime pairedAt;
  const PairedDevice({required this.name, required this.pairedAt});

  Map<String, dynamic> toJson() =>
      {'name': name, 'pairedAt': pairedAt.toIso8601String()};

  static PairedDevice fromJson(Map<String, dynamic> m) => PairedDevice(
        name: (m['name'] ?? '').toString(),
        pairedAt: DateTime.tryParse((m['pairedAt'] ?? '').toString()) ??
            DateTime.now(),
      );
}

/// The desktop half of the optional "Echo Engine": a larger local model
/// (bigger than the phone's on-device Qwen2.5 1.5B) that a phone on the same
/// network can offload briefing/Ask Echo generation to. Off by default —
/// only meaningful on macOS/Windows builds, and only starts when the user
/// opts in from Settings.
///
/// Deliberately "dumb": the phone builds the exact same prompt it would use
/// locally (see briefing_prompt.dart) and sends the finished prompt string;
/// this server just runs inference on it and streams the raw text back. No
/// prompt-construction logic is duplicated here.
class EchoServerService {
  EchoServerService._();
  static final EchoServerService instance = EchoServerService._();

  static const int httpPort = 8790;

  HttpServer? _httpServer;
  RawDatagramSocket? _discoverySocket;

  /// Bumped each time a phone snapshot is received via `/sync`, so the desktop
  /// mirror (Today/Vault) can listen and reload. A plain counter is enough —
  /// listeners just need "something changed."
  final ValueNotifier<int> syncTick = ValueNotifier<int>(0);

  /// Phones that have paired via QR, for display in Settings. Empty until the
  /// first pairing; loaded from disk in [start].
  final ValueNotifier<List<PairedDevice>> pairedDevices =
      ValueNotifier<List<PairedDevice>>(const []);

  static const _tokenKey = 'engine_pairing_token';
  static const _hasPairedKey = 'engine_has_paired';
  static const _pairedDevicesKey = 'paired_devices';

  bool get isRunning => _httpServer != null;

  /// The secret a phone must present (header `X-Echo-Token`) once this
  /// computer has ever paired with anyone. Generated once and persisted in
  /// SharedPreferences — the platform keychain would be the stronger home
  /// for it, but `flutter_secure_storage` needs a real signing team on
  /// macOS (its Keychain entitlement can't validate under this project's
  /// ad-hoc signing), and this token's job is only to gate other devices on
  /// the LAN, not to defend against someone with local disk access to this
  /// machine — the same tier as this app's other stored secrets (e.g. the
  /// Gemini API key in `settings_cubit.dart`).
  Future<String> pairingToken() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_tokenKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final token =
        List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
    await prefs.setString(_tokenKey, token);
    return token;
  }

  /// A human-readable name for this computer, for the QR payload and the
  /// "Paired devices" list. Prefers the actual macOS "Computer Name" (the
  /// one in System Settings → General → Sharing, e.g. "Chandan's MacBook
  /// Pro") via a native call — `Platform.localHostname` only returns the bare
  /// network hostname, which can be a short, unrelated-looking string with
  /// no connection to how the user actually named their machine.
  Future<String> systemName() async {
    final computerName = await SystemInfoService.computerName();
    if (computerName != null) return computerName;

    var name = Platform.localHostname;
    if (name.endsWith('.local')) name = name.substring(0, name.length - 6);
    name = name.replaceAll('-', ' ').replaceAll('_', ' ').trim();
    return name.isEmpty ? 'This computer' : name;
  }

  /// This machine's own LAN-facing IPv4 address, for encoding into the QR
  /// payload (UDP discovery instead learns the caller's own vantage point of
  /// this address from the reply's source, which doesn't help a QR image
  /// that has to embed the address up front).
  Future<String?> localLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          // Link-local (169.254.x.x) addresses aren't reachable from another
          // device in the normal case — skip them in favor of a real LAN IP.
          if (addr.address.startsWith('169.254.')) continue;
          return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<PairedDevice>> _loadPairedDevices(SharedPreferences prefs) async {
    final raw = prefs.getString(_pairedDevicesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((m) => PairedDevice.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _savePairedDevices(
    SharedPreferences prefs,
    List<PairedDevice> devices,
  ) async {
    await prefs.setString(
      _pairedDevicesKey,
      jsonEncode(devices.map((d) => d.toJson()).toList()),
    );
  }

  /// Rejects requests to the sensitive routes once this computer has ever
  /// paired with a phone — before that first pairing, the LAN stays as open
  /// as it's always been, so nobody who never touches QR pairing sees any
  /// behavior change. `/health` and `/pair` are always reachable: `/health`
  /// is just a reachability probe, and `/pair` is how trust gets established
  /// in the first place.
  FutureOr<Response> Function(Request) _authMiddleware(
    FutureOr<Response> Function(Request) innerHandler,
  ) {
    return (request) async {
      final path = request.requestedUri.path;
      if (path == '/health' || path == '/pair') return innerHandler(request);

      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_hasPairedKey) ?? false)) return innerHandler(request);

      final expected = await pairingToken();
      final provided = request.headers['x-echo-token'];
      if (provided != expected) {
        return Response(
          401,
          body: jsonEncode({'status': 'unauthorized'}),
          headers: _jsonHeaders,
        );
      }
      return innerHandler(request);
    };
  }

  Future<Response> _handlePair(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString()) as Map;
      final incomingToken = body['token'];
      final deviceName = (body['deviceName'] as String?)?.trim();
      final expected = await pairingToken();

      if (incomingToken != expected || deviceName == null || deviceName.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'status': 'error', 'message': 'invalid pairing request'}),
          headers: _jsonHeaders,
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hasPairedKey, true);

      final devices = await _loadPairedDevices(prefs);
      devices.removeWhere((d) => d.name == deviceName);
      devices.add(PairedDevice(name: deviceName, pairedAt: DateTime.now()));
      await _savePairedDevices(prefs, devices);
      pairedDevices.value = devices;

      return Response.ok(
        jsonEncode({'status': 'ok', 'desktopName': await systemName()}),
        headers: _jsonHeaders,
      );
    } catch (e) {
      debugPrint('Echo Engine pairing failed: $e');
      return Response.internalServerError(
        body: jsonEncode({'status': 'error'}),
        headers: _jsonHeaders,
      );
    }
  }

  /// Starts the HTTP server + UDP discovery responder. The server is
  /// discoverable and answers `/health` even before a model is downloaded, so
  /// a phone can connect immediately. The model path is deliberately NOT
  /// captured here — it used to be, which meant a model finishing its
  /// download *after* this server had already started left the server stuck
  /// thinking no model existed until the next restart. `/briefing` and `/ask`
  /// now resolve the model fresh on every request instead.
  Future<void> start() async {
    if (isRunning) return;

    final prefs = await SharedPreferences.getInstance();
    pairedDevices.value = await _loadPairedDevices(prefs);

    final router = Router()
      ..get('/health', _handleHealth)
      ..post('/briefing', (r) => _handleGenerate(r, _briefingSampling))
      ..post('/ask', (r) => _handleGenerate(r, _askSampling))
      ..post('/sync', _handleSync)
      ..post('/pair', _handlePair);

    final handler = Pipeline()
        .addMiddleware(_authMiddleware)
        .addHandler(router.call);

    _httpServer = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      httpPort,
    );
    debugPrint('Echo Engine listening on ${_httpServer!.address.address}:$httpPort');

    await _startDiscoveryResponder();
  }

  Future<void> stop() async {
    _discoverySocket?.close();
    _discoverySocket = null;
    await _httpServer?.close(force: true);
    _httpServer = null;
  }

  Response _handleHealth(Request request) =>
      Response.ok(jsonEncode({'status': 'ok'}), headers: _jsonHeaders);

  /// Receives a full snapshot from the phone and mirrors it locally so this
  /// computer's Today/Vault reflect the phone's real data. The phone is the
  /// source of truth: notifications replace the local set wholesale, and the
  /// cached briefing + streak overwrite ours. Best-effort — a malformed field
  /// is skipped rather than failing the whole sync.
  Future<Response> _handleSync(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString()) as Map;

      final rawNotifications = body['notifications'];
      if (rawNotifications is List) {
        final entries = rawNotifications
            .whereType<Map>()
            .map((m) => RawData.fromSyncMap(m.cast<String, dynamic>()))
            .toList();
        await IsarDataSource.replaceAllFromSync(entries);
      }

      final prefs = await SharedPreferences.getInstance();

      final briefing = body['briefing'];
      if (briefing is Map) {
        final date = briefing['date'];
        final text = briefing['text'];
        if (date is String && text is String) {
          await prefs.setString('cached_briefing_date', date);
          await prefs.setString('cached_briefing_text', text);
        }
      }

      final streak = body['streak'];
      if (streak is Map) {
        await StreakService().importSnapshot(streak.cast<String, dynamic>());
      }

      syncTick.value++;
      return Response.ok(jsonEncode({'status': 'ok'}), headers: _jsonHeaders);
    } catch (e) {
      debugPrint('Echo Engine sync failed: $e');
      return Response.internalServerError(
        body: jsonEncode({'status': 'error'}),
        headers: _jsonHeaders,
      );
    }
  }

  // Sampling settings deliberately mirror the phone's own on-device calls
  // exactly (briefing_cubit.dart / ask_ai_cubit.dart) — the engine is meant to
  // be "dumb": same weights, same prompt, same sampling, so a synced offload
  // reads identically regardless of which device actually generated it. Ask
  // Echo in particular runs much cooler and shorter than the briefing (0.3 vs
  // 0.6 temperature, 500 vs 4000 tokens) — on thin RAG context, using the
  // briefing's hotter/longer settings for /ask let a small model ramble into
  // incoherent, self-referential tangents instead of a clipped answer.
  static const _briefingSampling = (
    temperature: 0.6,
    maxTokens: 4000,
    contextSize: 16384,
  );
  static const _askSampling = (
    temperature: 0.3,
    maxTokens: 500,
    contextSize: 16384,
  );

  Response _handleGenerate(
    Request request,
    ({double temperature, int maxTokens, int contextSize}) sampling,
  ) {
    final controller = StreamController<List<int>>();

    () async {
      try {
        final body = jsonDecode(await request.readAsString()) as Map;
        final prompt = body['prompt'] as String? ?? '';
        if (prompt.isEmpty) {
          await controller.close();
          return;
        }

        final modelPath = await createOfflineModelRepository().downloadedPathOrNull();
        if (modelPath == null) {
          await controller.close();
          return;
        }

        final done = Completer<void>();
        String lastOutput = '';
        await fllamaInference(
          FllamaInferenceRequest(
            contextSize: sampling.contextSize,
            input: prompt,
            maxTokens: sampling.maxTokens,
            modelPath: modelPath,
            numGpuLayers: 99,
            numThreads: Platform.numberOfProcessors,
            temperature: sampling.temperature,
            penaltyFrequency: 0.0,
            penaltyRepeat: 1.1,
            topP: 0.9,
          ),
          (cumulative, openaiJson, isDone) {
            if (cumulative.length > lastOutput.length) {
              final token = cumulative.substring(lastOutput.length);
              lastOutput = cumulative;
              if (token.isNotEmpty && !controller.isClosed) {
                controller.add(utf8.encode(token));
              }
            }
            if (isDone == true && !done.isCompleted) done.complete();
          },
        );
        await done.future;
      } catch (e) {
        debugPrint('Echo Engine generation failed: $e');
      } finally {
        if (!controller.isClosed) await controller.close();
      }
    }();

    return Response.ok(
      controller.stream,
      headers: {'content-type': 'text/plain; charset=utf-8'},
    );
  }

  Future<void> _startDiscoveryResponder() async {
    _discoverySocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      DesktopEngineClient.discoveryPort,
    );
    _discoverySocket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _discoverySocket!.receive();
      if (datagram == null) return;
      final message = utf8.decode(datagram.data, allowMalformed: true);
      if (message != 'ECHO_DISCOVER') return;
      _discoverySocket!.send(
        utf8.encode(jsonEncode({'port': httpPort})),
        datagram.address,
        datagram.port,
      );
    });
  }

  static const _jsonHeaders = {'content-type': 'application/json'};
}
