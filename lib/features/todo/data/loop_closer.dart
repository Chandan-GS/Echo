import 'package:flutter/foundation.dart';
import 'package:project_echo/features/echo/data/waiting/waiting_store.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';

/// Ticking a to-do closes that person's loop: the message it came from stops
/// waiting on Today and on their People page. Unticking opens it again.
class LoopCloser {
  LoopCloser._();

  /// Best effort: a list that can't reach the waiting feed still ticks.
  static Future<void> closed(TodoItem item, bool done) async {
    if (item.typed) return;
    try {
      final feed = await WaitingStore.load(DateTime.now());
      final key = item.sourceKey.split('#').first;
      if (done) {
        for (final w in feed.waiting) {
          if (sourceKeyOf(w.message) == key) {
            await WaitingStore.markNoReplyNeeded(w);
          }
        }
      } else {
        for (final w in feed.acks) {
          if (sourceKeyOf(w.message) == key) {
            await WaitingStore.markNeedsReply(w);
          }
        }
      }
    } catch (e) {
      debugPrint('Closing a to-do loop failed: $e');
    }
  }
}
