import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';

/// How a reply leaves Echo, best first (see ReplyActions.kt).
enum ReplyRoute {
  /// Echo sends it, through the chat notification's own Reply button.
  send,

  /// Echo writes it into exactly that chat; the owner taps send there.
  write,

  /// Echo writes it into the app's "send to" list; the owner picks the chat.
  pick,

  /// Echo copies it and opens the chat; the owner pastes it.
  copy,
}

/// What happened when a reply went out.
enum ReplyOutcome { sent, written, picker, copied }

/// Answers a chat message.
class ReplySender {
  ReplySender._();

  static const _channel = MethodChannel('project_echo/reply');

  /// How a reply to [to] would go right now, for labelling the button.
  static Future<ReplyRoute> routeFor(RawData to) async {
    final thread = to.thread;
    return thread == null ? ReplyRoute.pick : _route(thread);
  }

  static Future<ReplyRoute> _route(String thread) async =>
      switch (await _call<String>('route', {'thread': thread})) {
        'send' => ReplyRoute.send,
        'write' => ReplyRoute.write,
        'copy' => ReplyRoute.copy,
        _ => ReplyRoute.pick,
      };

  static Future<ReplyOutcome> send(RawData to, String text) async {
    final thread = to.thread;
    if (thread != null &&
        await _call<bool>('send', {'thread': thread, 'text': text}) == true) {
      await ChatContextStore.recordMyTurn(thread, DateTime.now(), text);
      return ReplyOutcome.sent;
    }
    // A WhatsApp chat seen before Echo kept chat ids is found through the
    // WhatsApp entries in the owner's contacts, so access is asked for on
    // this tap, the first time it would help.
    if (thread != null &&
        isWhatsApp(packageOfThread(thread) ?? '') &&
        !to.isGroup &&
        await _route(thread) == ReplyRoute.pick &&
        !(await Permission.contacts.status).isPermanentlyDenied) {
      await Permission.contacts.request();
    }
    // Copied too, in case the chat app drops the text it was given.
    await Clipboard.setData(ClipboardData(text: text));
    final written = thread == null
        ? null
        : await _call<String>('write', {'thread': thread, 'text': text});
    return switch (written) {
      'written' => ReplyOutcome.written,
      'picker' => ReplyOutcome.picker,
      _ => ReplyOutcome.copied,
    };
  }

  /// Opens the chat [entry] came from; or, when that's not possible, its
  /// app. False when neither can be opened.
  static Future<bool> open(RawData entry) async {
    final thread = entry.thread;
    if (thread != null &&
        await _call<bool>('openChat', {'thread': thread}) == true) {
      return true;
    }
    final app = packageOfThread(thread);
    return app != null &&
        await _call<bool>('openApp', {'package': app}) == true;
  }

  static Future<T?> _call<T>(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null; // desktop builds
    }
  }
}

/// "com.whatsapp" from a thread id like "com.whatsapp:1f3a…".
String? packageOfThread(String? thread) {
  if (thread == null) return null;
  final i = thread.lastIndexOf(':');
  return i <= 0 ? null : thread.substring(0, i);
}

bool isWhatsApp(String package) =>
    package == 'com.whatsapp' || package == 'com.whatsapp.w4b';
