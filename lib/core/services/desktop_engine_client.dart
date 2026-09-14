import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The result of a successful QR pairing — everything the phone needs to
/// remember to reach this desktop engine again, plus its name for display.
class PairResult {
  final String host;
  final String desktopName;
  const PairResult({required this.host, required this.desktopName});
}

/// Phone-side client for an optional "Echo Engine" running on a desktop
/// (macOS/Windows) build of this same app — a bigger local model the phone
/// can offload briefing/Ask Echo generation to when it's reachable on the
/// same network. Purely additive: every method fails soft (returns null /
/// emits an error the caller already knows how to fall back from), so a
/// missing or unreachable desktop never blocks the phone's own generation.
///
/// Discovery is a small UDP broadcast ping/pong rather than mDNS/Bonjour —
/// Windows has no built-in mDNS responder, so a fixed-port broadcast works
/// identically on macOS, Windows and Android with zero extra dependencies.
/// See [EchoServerService] (desktop side) for the matching responder.
class DesktopEngineClient {
  DesktopEngineClient._();

  /// UDP port the desktop listens on for discovery pings.
  static const int discoveryPort = 41999;
  static const String _pingMessage = 'ECHO_DISCOVER';

  static final Dio _dio = Dio();

  /// The pairing secret a QR scan handed us, if any. Plain SharedPreferences
  /// (matching the desktop side — see [EchoServerService.pairingToken] for
  /// why the platform keychain isn't used here either).
  static const _tokenKey = 'desktop_engine_token';

  static Future<String?> _cachedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// Parses a scanned QR payload (`{"host","port","token","name"}`), pairs
  /// with that desktop engine over `/pair`, and — on success — persists the
  /// host, token and desktop name so every future request to this engine is
  /// both findable and authenticated. Returns `null` on any failure (bad QR,
  /// unreachable host, token mismatch); the caller shows a plain "couldn't
  /// connect" message rather than a raw exception either way.
  static Future<PairResult?> pairViaQrPayload(String rawQrJson) async {
    try {
      final payload = jsonDecode(rawQrJson) as Map;
      final ip = payload['host'] as String?;
      final port = payload['port'];
      final token = payload['token'] as String?;
      if (ip == null || port is! int || token == null) return null;
      final host = '$ip:$port';

      final prefs = await SharedPreferences.getInstance();
      final myName = (prefs.getString('user_name')?.trim().isNotEmpty ?? false)
          ? "${prefs.getString('user_name')!.trim()}'s Phone"
          : 'My Phone';

      final response = await _dio.post(
        'http://$host/pair',
        data: jsonEncode({'token': token, 'deviceName': myName}),
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final desktopName = (response.data is Map)
          ? (response.data['desktopName'] as String?)
          : null;
      if (response.statusCode != 200 || desktopName == null) return null;

      await prefs.setString(_tokenKey, token);
      await prefs.setString('desktop_engine_host', host);
      await prefs.setString('desktop_engine_name', desktopName);
      return PairResult(host: host, desktopName: desktopName);
    } catch (e) {
      debugPrint('QR pairing failed: $e');
      return null;
    }
  }

  /// Attaches the pairing token (if we have one) to a set of request headers.
  /// A never-paired phone sends no token — harmless, since a desktop that has
  /// never paired with anyone doesn't require one either.
  static Future<Map<String, String>> authHeaders() async {
    final token = await _cachedToken();
    return token == null ? const {} : {'X-Echo-Token': token};
  }

  /// Resolves a reachable "host:port" for the desktop Echo Engine, or `null`
  /// if none is found within the time budget. Tries [cachedHost] first (a
  /// fast health-check, since most of the time the last-known address is
  /// still good) before falling back to a fresh UDP broadcast.
  static Future<String?> discoverHost({
    String? cachedHost,
    Duration cachedTimeout = const Duration(milliseconds: 350),
    Duration broadcastTimeout = const Duration(milliseconds: 900),
  }) async {
    if (cachedHost != null && cachedHost.isNotEmpty) {
      if (await _isReachable(cachedHost, timeout: cachedTimeout)) {
        return cachedHost;
      }
    }
    return _broadcastDiscover(timeout: broadcastTimeout);
  }

  static Future<bool> _isReachable(String host, {required Duration timeout}) async {
    try {
      final response = await _dio.get(
        'http://$host/health',
        options: Options(
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _broadcastDiscover({required Duration timeout}) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.send(
        utf8.encode(_pingMessage),
        InternetAddress('255.255.255.255'),
        discoveryPort,
      );

      final completer = Completer<String?>();
      final sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket!.receive();
        if (datagram == null) return;
        try {
          final payload = jsonDecode(utf8.decode(datagram.data)) as Map;
          final port = payload['port'];
          if (port is int && !completer.isCompleted) {
            completer.complete('${datagram.address.address}:$port');
          }
        } catch (_) {
          // Ignore anything that isn't our expected reply shape.
        }
      });

      final result = await completer.future.timeout(
        timeout,
        onTimeout: () => null,
      );
      await sub.cancel();
      return result;
    } catch (e) {
      debugPrint('Desktop engine discovery failed: $e');
      return null;
    } finally {
      socket?.close();
    }
  }

  /// Streams generated text from the desktop engine's `/briefing` or `/ask`
  /// endpoint. Emits plain text tokens as they arrive (same shape the
  /// callers already feed into their `StreamController<String>` for the
  /// on-device/Gemini paths) and closes normally on completion, or emits an
  /// error the caller can fall back from.
  static Stream<String> generateStream({
    required String host,
    required String endpoint, // 'briefing' | 'ask'
    required String prompt,
  }) {
    final controller = StreamController<String>();

    () async {
      try {
        final response = await _dio.post<ResponseBody>(
          'http://$host/$endpoint',
          data: jsonEncode({'prompt': prompt}),
          options: Options(
            headers: {'Content-Type': 'application/json', ...await authHeaders()},
            responseType: ResponseType.stream,
            sendTimeout: const Duration(seconds: 10),
            // Generation itself can legitimately take a while on a big model;
            // don't cap receive time the way the fast health-check does.
            receiveTimeout: const Duration(minutes: 5),
          ),
        );

        final stream = response.data!.stream;
        await for (final chunk in stream) {
          if (controller.isClosed) break;
          controller.add(utf8.decode(chunk, allowMalformed: true));
        }
        await controller.close();
      } catch (e) {
        controller.addError(e);
        await controller.close();
      }
    }();

    return controller.stream;
  }
}
