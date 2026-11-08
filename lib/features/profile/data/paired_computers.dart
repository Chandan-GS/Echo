import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A computer this phone has paired with.
class PairedComputer {
  final String host;
  final String name;
  final String? token;

  const PairedComputer({required this.host, required this.name, this.token});

  Map<String, dynamic> toJson() => {'host': host, 'name': name, 'token': token};

  static PairedComputer? fromJson(Object? j) {
    if (j is! Map || j['host'] is! String) return null;
    return PairedComputer(
      host: j['host'] as String,
      name: (j['name'] as String?) ?? PairedComputers.unnamed,
      token: j['token'] as String?,
    );
  }
}

/// The computers this phone knows. Pairing itself only remembers the latest
/// one (`desktop_engine_*`, see DesktopEngineClient), so that one is folded
/// into this list each time it's read, and picking another puts it back.
class PairedComputers {
  PairedComputers._();

  static const key = 'paired_computers_v1';
  static const unnamed = 'Your computer';

  static const _host = 'desktop_engine_host';
  static const _name = 'desktop_engine_name';
  static const _token = 'desktop_engine_token';

  /// [list] with the current pairing folded in. A computer that moved to a
  /// new address on the Wi-Fi is the same computer, so it replaces its entry.
  /// Pure, for tests.
  static List<PairedComputer> merged(
    List<PairedComputer> list, {
    required String? host,
    required String? name,
    required String? token,
  }) {
    if (host == null || host.isEmpty) return list;
    final existing = list.where((c) => c.host == host).firstOrNull;
    final current = PairedComputer(
      host: host,
      name: name ?? existing?.name ?? unnamed,
      token: token ?? existing?.token,
    );
    final named = current.name != unnamed;
    return [
      for (final c in list)
        if (c.host != host && !(named && c.name == current.name)) c,
      current,
    ];
  }

  static List<PairedComputer> decode(String? raw) {
    try {
      return [
        for (final j in jsonDecode(raw ?? '[]') as List)
          ?PairedComputer.fromJson(j),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(
    SharedPreferences prefs,
    List<PairedComputer> list,
  ) => prefs.setString(key, jsonEncode([for (final c in list) c.toJson()]));

  static Future<List<PairedComputer>> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final list = merged(
      decode(prefs.getString(key)),
      host: prefs.getString(_host),
      name: prefs.getString(_name),
      token: prefs.getString(_token),
    );
    await _save(prefs, list);
    return list;
  }

  /// Makes [computer] the one drafts and Ask go to.
  static Future<void> use(PairedComputer computer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_host, computer.host);
    await prefs.setString(_name, computer.name);
    if (computer.token case final token?) {
      await prefs.setString(_token, token);
    } else {
      await prefs.remove(_token);
    }
  }

  /// Forgets [computer]. Returns true if it was the one in use, whose pairing
  /// details are then cleared as well.
  static Future<bool> forget(PairedComputer computer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await _save(prefs, [
      for (final c in decode(prefs.getString(key)))
        if (c.host != computer.host) c,
    ]);
    if (prefs.getString(_host) != computer.host) return false;
    await prefs.remove(_host);
    await prefs.remove(_name);
    await prefs.remove(_token);
    return true;
  }
}
