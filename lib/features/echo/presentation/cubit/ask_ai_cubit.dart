import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/services/analytics_service.dart';
import 'package:project_echo/core/services/engine_gate.dart';
import 'package:project_echo/core/services/gemini_service.dart';
import 'package:project_echo/core/services/writing_engine.dart';
import 'package:project_echo/demo/demo_mode.dart';
import 'package:project_echo/features/echo/data/ask/ask_intents.dart';
import 'package:project_echo/features/echo/data/ask/ask_retrieval.dart';
import 'package:project_echo/features/echo/data/ask/citations.dart';
import 'package:project_echo/features/echo/data/ask/conversation_memory.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/datasources/briefing_prompt.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/datasources/tflite_embedding_service.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/temporal_relevance.dart';
import 'package:project_echo/features/echo/data/reply/reply_drafter.dart';
import 'package:project_echo/features/echo/data/reply/reply_sender.dart';
import 'package:project_echo/features/todo/data/todo_generator.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:project_echo/features/vault/data/app_access.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/services/phone_actions.dart';
import 'package:project_echo/features/echo/data/services/notification_ingest.dart';
import 'package:project_echo/features/desktop/data/desktop_actions.dart';

part 'ask_ai_state.dart';

class AskAiCubit extends Cubit<AskAiState> {
  final List<ChatMessage> _messages = [];
  WritingCancel? _activeWrite;
  final TodoGenerator _todos;

  /// Set by the phone's Ask screen, so asking can open the engine sheet. Left
  /// unset (desktop, tests), Echo just writes.
  Future<bool> Function(String reason)? _ensureEngine;
  Future<bool> Function(String reason)? _chooseEngine;

  AskAiCubit({TodoGenerator? todos})
    : _todos = todos ?? TodoGenerator(),
      super(AskAiInitial());

  void attachEngineGate({
    required Future<bool> Function(String reason) ensure,
    required Future<bool> Function(String reason) choose,
  }) {
    _ensureEngine = ensure;
    _chooseEngine = choose;
  }

  void detachEngineGate() {
    _ensureEngine = null;
    _chooseEngine = null;
  }

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  void _emit({
    bool searching = false,
    AskProgress? progress,
    String? awaitingEngine,
  }) {
    if (isClosed) return;
    emit(
      AskAiMessageReceived(
        messages: List.from(_messages),
        isSearching: searching,
        progress: progress,
        awaitingEngine: awaitingEngine,
      ),
    );
  }

  /// Whether Echo can write for [reason], asking the owner first if nothing
  /// is set yet. Without a gate attached it can.
  Future<bool> _canWrite(String reason) async {
    final ensure = _ensureEngine;
    if (ensure == null) return true;
    if (await EngineGate.current() != null) return true;
    if (await EngineGate.willAsk(reason)) {
      _emit(searching: true, awaitingEngine: reason);
    }
    return ensure(reason);
  }

  /// The filming build: a scripted answer, found and streamed in the same
  /// rhythm as a real one.
  Future<void> _demoAnswer(String question) async {
    final draft = await DemoAsk.draft(question);
    if (draft != null) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (isClosed) return;
      final (to, text) = draft;
      _messages.add(
        ChatMessage(
          sender: 'echo',
          text: '',
          kind: MessageKind.draft,
          draft: ReplyDraft(
            to: to,
            text: '',
            route: ReplyRoute.send,
            status: DraftStatus.writing,
          ),
        ),
      );
      final index = _messages.length - 1;
      _emit();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      if (isClosed) return;
      _updateDraft(
        index,
        (d) => d.copyWith(text: text, status: DraftStatus.ready),
      );
      return;
    }
    final (answer, sources) = await DemoAsk.answer(question);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (isClosed) return;
    _messages.add(
      ChatMessage(
        sender: 'echo',
        text: '',
        isGenerating: true,
        ragSources: sources,
      ),
    );
    final index = _messages.length - 1;
    _emit();
    var shown = '';
    for (final word in answer.split(' ')) {
      await Future<void>.delayed(const Duration(milliseconds: 45));
      if (isClosed) return;
      shown = shown.isEmpty ? word : '$shown $word';
      _messages[index] = _messages[index].copyWith(text: shown);
      _emit();
    }
    _messages[index] = _messages[index].copyWith(isGenerating: false);
    _emit();
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    Analytics.track('ask_echo_used');

    cancelInference();

    _messages.add(ChatMessage(sender: 'user', text: text));
    _emit(searching: true);

    if (kEchoDemo) return _demoAnswer(text);

    await _answer(text);
  }

  /// Answers [text], whose question is already in the chat.
  Future<void> _answer(String text) async {
    // Index of the echo placeholder for THIS request. Captured once so that
    // streaming callbacks always write to their own message even if the list
    // grows from a later request (appends never shift earlier indices).
    int? echoIndex;

    try {
      // Notifications missed while the app was closed count too. Saving them
      // is quick; their embeddings may still be on the way, and until then
      // they're found by their words, sender and time.
      await NotificationIngest.whenCaughtUp();
      // Blocked categories and apps switched off in Apps Echo hears aren't
      // context, though they stay in the Vault.
      final allNotifications = await withoutExcludedSources(
        await IsarDataSource.getAllEntries(),
      );

      // "Add them to my list", "tell Rahul I'll bring it": things to do, not
      // questions to answer.
      final intent = parseIntent(text, replyCandidates(allNotifications));
      if (await _act(intent)) return;

      // Asked here, once it's clear this is a question to answer.
      final canWrite = await _canWrite('ask');
      _emit(searching: true);

      final now = DateTime.now();
      final smallTalk = isSmallTalk(text);
      // Small talk isn't looked up, so there's nothing to report reading.
      final reading = smallTalk ? null : allNotifications.length;
      _emit(searching: true, progress: _progress(reading));

      // Run on-device RAG using all-MiniLM model. The TensorFlow Lite native
      // library isn't bundled on desktop (macOS/Windows), and notifications
      // synced from the phone carry no embeddings anyway, so on desktop we skip
      // embeddings entirely and fall back to keyword + time retrieval.
      List<double>? queryEmbedding;
      if (!smallTalk && !(Platform.isMacOS || Platform.isWindows)) {
        try {
          queryEmbedding = await TfliteEmbeddingService.instance.getEmbedding(
            text,
          );
        } catch (e) {
          debugPrint('Embedding unavailable — keyword-only retrieval: $e');
        }
      }

      // Today's conversation. A follow-up ("and Neha?", "when is it?") is
      // spotted locally, then retrieval leans towards the previous topic and
      // the prompt gets the last couple of exchanges — nothing otherwise.
      final memory = await ConversationMemory.load(now);
      final previous = memory.last;
      final followUp =
          !smallTalk && memory.isFollowUp(text, queryEmbedding, now);

      final ranked = smallTalk
          ? const <RankedNotification>[]
          : rankForQuestion(
              question: text,
              now: now,
              entries: allNotifications,
              questionEmbedding: followUp
                  ? blendEmbeddings(queryEmbedding, previous!.embedding)
                  : queryEmbedding,
              carriedIds: followUp
                  ? previous!.sourceIds.toSet()
                  : const <int>{},
            );
      var ragSources = ranked.map((r) => r.entry).toList();

      // A follow-up that matches nothing new ("what time was that?") is still
      // about the previous answer's notifications.
      if (ragSources.isEmpty && followUp) {
        final ids = previous!.sourceIds.toSet();
        ragSources = allNotifications.where((e) => ids.contains(e.id)).toList();
      }

      // Nothing to write with: show what matched, as it is.
      if (!canWrite) {
        await _showSearch(
          text,
          ragSources,
          checked: allNotifications.length,
          smallTalk: smallTalk,
          allNotifications: allNotifications,
        );
        return;
      }

      // No real match on an actual lookup question: don't hand a small local
      // model an empty context and hope it improvises sensibly — on thin
      // context, the 1.5B model reliably degenerates into paraphrasing its own
      // system instruction back at the user instead of answering. Answer
      // directly instead of invoking generation at all.
      // Casual small talk ("hi", "thanks") never needed notification context
      // in the first place, so it still goes to the model normally.
      if (ragSources.isEmpty && !smallTalk) {
        final name =
            (await SharedPreferences.getInstance()).getString('user_name') ??
            'sir';
        final fallback = _noMatchFallback(name, allNotifications);
        _messages.add(ChatMessage(sender: 'echo', text: fallback));
        _emit();
        await memory.add(
          ConversationTurn(
            question: text,
            answer: fallback,
            sourceIds: const [],
            embedding: queryEmbedding,
            at: now,
          ),
        );
        return;
      }

      // Numbered, so the answer can point at what it used ("… by 4 PM [2]").
      final myTurns = await ChatContextStore.loadMyTurns();
      String line(RawData e) => formatEntry(
        e,
        myTurns: myTurns,
        content: _clip(
          rewriteRelativeDays(e.content, e.timestamp, now),
          _maxContentChars,
        ),
        when: askTimeLabel(e, now, withArrival: isArrivalQuestion(text)),
      );
      final contextString = ragSources.isEmpty
          ? 'No notifications needed — this is just a casual message.'
          : [
              for (var i = 0; i < ragSources.length; i++)
                '${i + 1}. ${line(ragSources[i])}',
            ].join('\n');
      final history = followUp ? memory.historyForPrompt() : null;

      _messages.add(
        ChatMessage(
          sender: 'echo',
          text: '',
          isGenerating: true,
          ragSources: ragSources,
          checked: allNotifications.length,
        ),
      );
      echoIndex = _messages.length - 1;
      _emit(progress: _progress(reading, ragSources.length));

      final prefs = await SharedPreferences.getInstance();
      final userName = prefs.getString('user_name') ?? 'Sir';
      final answer = StringBuffer();
      await for (final delta in _generate(
        prefs: prefs,
        question: text,
        context: contextString,
        userName: userName,
        history: history,
        now: now,
      )) {
        if (isClosed) return;
        answer.write(delta);
        _messages[echoIndex] = _messages[echoIndex].copyWith(
          text: answer.toString(),
        );
        _emit(progress: _progress(reading, ragSources.length));
      }
      final finished = _messages[echoIndex].copyWith(
        text: withoutChatTokens(answer.toString()),
      );
      _messages[echoIndex] = finished.copyWith(
        isGenerating: false,
        addable: finished.todos > 0 && await _notOnList(finished.about),
      );
      _emit();

      // Remember the exchange (small talk carries no topic worth following).
      final spoken = plainAnswer(_messages[echoIndex].text);
      if (!smallTalk && spoken.isNotEmpty) {
        await memory.add(
          ConversationTurn(
            question: text,
            answer: spoken,
            sourceIds: ragSources.map((e) => e.id).toList(),
            embedding: queryEmbedding,
            at: now,
          ),
        );
      }
    } catch (e) {
      // Remove this request's own placeholder if it never received any text,
      // identified by its captured index rather than "the last message".
      if (echoIndex != null &&
          echoIndex < _messages.length &&
          _messages[echoIndex].text.isEmpty) {
        _messages.removeAt(echoIndex);
      }
      _messages.add(
        ChatMessage(
          sender: 'echo',
          text: e is GeminiFailure
              ? e.message
              : 'Sorry, I encountered an error running inference: $e',
          kind: e is GeminiFailure ? MessageKind.notice : MessageKind.text,
        ),
      );
      _emit();
    }
  }

  /// The answer as it streams in, piece by piece, from whichever engine is
  /// in use: a paired desktop, Gemini, or the on-device model.
  Stream<String> _generate({
    required SharedPreferences prefs,
    required String question,
    required String context,
    required String userName,
    required String? history,
    required DateTime now,
  }) async* {
    final route = await currentWritingRoute(prefs);
    if (route is NoWritingRoute) {
      yield route.computerWanted
          ? "I can't reach your computer right now. Make sure it's awake and "
                "on the same Wi-Fi, then ask again."
          : "The on-device model isn't installed. Download it in Settings, "
                'or switch to the cloud engine to use Ask Echo without it.';
      return;
    }
    yield* writeWith(
      route,
      WritingPrompt(
        system: getAskAiSystemInstruction(userName, now: now),
        user: buildAskAiUserMessage(question, context, history: history),
      ),
      maxTokens: 500,
      temperature: 0.3,
      cancel: _activeWrite = WritingCancel(),
    );
  }

  static AskProgress? _progress(int? reading, [int? found]) =>
      reading == null ? null : AskProgress(reading, found);

  // ── Doing things ─────────────────────────────────────────────────────────

  /// Carries out [intent], if it asks for anything. True when handled.
  Future<bool> _act(AskIntent intent) async {
    final reply = intent.reply;
    final answer = _lastAnswerIndex();
    final adding = intent.addToList && answer != null;
    if (!adding && reply == null) return false;
    if (adding) await addFromAnswer(answer);
    if (reply != null) await draftReply(reply.to, gist: reply.gist);
    return true;
  }

  /// The latest answer that drew on notifications, which "add them" means.
  int? _lastAnswerIndex() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (!m.isUser &&
          (m.kind == MessageKind.text || m.kind == MessageKind.search) &&
          m.ragSources.isNotEmpty) {
        return i;
      }
    }
    return null;
  }

  /// Whether any of [entries] isn't on the to-do list yet.
  Future<bool> _notOnList(List<RawData> entries) async {
    final (items, _) = await TodoStore().load();
    final keys = {for (final i in items) i.sourceKey};
    return entries.any((e) => !keys.contains(sourceKeyOf(e)));
  }

  /// "Add these to my list" under answer [index].
  Future<void> addFromAnswer(int index) async {
    final m = _messages[index];
    _messages[index] = m.copyWith(addable: false);
    await addEntries(m.about);
  }

  /// Puts [entries] on the to-do list, then says what went on.
  Future<void> addEntries(List<RawData> entries) async {
    if (entries.isEmpty) return;
    final now = DateTime.now();
    final added = await _todos.addFrom(entries, now);
    _messages.add(
      ChatMessage(
        sender: 'echo',
        text: addedLine(added, now),
        kind: MessageKind.added,
        added: added,
      ),
    );
    _emit();
  }

  Future<void> undoAdded(int index) async {
    final m = _messages[index];
    if (m.kind != MessageKind.added || m.undone) return;
    await TodoStore().remove({for (final i in m.added) i.id});
    _messages[index] = m.copyWith(undone: true);
    _emit();
  }

  /// Drafts a reply to [to]: from the owner's own words ([gist]) when given,
  /// otherwise a suggestion, which needs an engine.
  Future<void> draftReply(RawData to, {String? gist}) async {
    if (gist == null && !await _canWrite('draft')) {
      _messages.add(
        ChatMessage(
          sender: 'echo',
          text: '',
          kind: MessageKind.gate,
          replyTo: to,
        ),
      );
      _emit();
      return;
    }
    _emit();
    await _writeDraft(to, gist: gist);
  }

  /// Under a gate card: choose an engine, then draft the reply it was for.
  Future<void> chooseEngineForDraft(int index) async {
    final to = _messages[index].replyTo;
    final choose = _chooseEngine;
    if (to == null || choose == null) return;
    if (!await choose('draft')) return;
    _messages.removeAt(index);
    _emit();
    await _writeDraft(to);
  }

  /// Under a gate card: an empty draft to type into, no engine needed.
  Future<void> writeDraftMyself(int index) async {
    final to = _messages[index].replyTo;
    if (to == null) return;
    _messages.removeAt(index);
    _emit();
    await _writeDraft(to);
  }

  Future<void> _writeDraft(RawData to, {String? gist}) async {
    final route = await ReplySender.routeFor(to);
    _messages.add(
      ChatMessage(
        sender: 'echo',
        text: '',
        kind: MessageKind.draft,
        draft: ReplyDraft(
          to: to,
          text: '',
          route: route,
          status: DraftStatus.writing,
        ),
      ),
    );
    final index = _messages.length - 1;
    _emit();
    final text = await ReplyDrafter.draft(ReplyRequest(to, gist));
    _updateDraft(
      index,
      (d) => d.copyWith(text: text, status: DraftStatus.ready),
    );
  }

  void editDraft(int index, String text) =>
      _updateDraft(index, (d) => d.copyWith(text: text));

  void dismissDraft(int index) =>
      _updateDraft(index, (d) => d.copyWith(status: DraftStatus.dismissed));

  /// Sends [emoji] instead of the drafted words.
  Future<void> quickReply(int index, String emoji) async {
    editDraft(index, emoji);
    await sendDraft(index);
  }

  Future<void> sendDraft(int index) async {
    final draft = _messages[index].draft;
    if (draft == null || !draft.open || draft.text.trim().isEmpty) return;
    _updateDraft(index, (d) => d.copyWith(status: DraftStatus.sending));
    // A computer can't reach the chat app; the phone sends it.
    if ((Platform.isMacOS || Platform.isWindows) && !kEchoDemo) {
      return _sendThroughPhone(index, draft);
    }
    final outcome = await ReplySender.send(draft.to, draft.text.trim());
    _updateDraft(
      index,
      (d) => d.copyWith(
        doneAt: DateTime.now(),
        status: switch (outcome) {
          ReplyOutcome.sent => DraftStatus.sent,
          ReplyOutcome.written => DraftStatus.written,
          ReplyOutcome.picker => DraftStatus.picker,
          ReplyOutcome.copied => DraftStatus.copied,
        },
      ),
    );
  }

  /// Hands the reply to the phone (see DesktopActions) and follows it: the
  /// phone sends it, or shows it ready to send with a tap.
  Future<void> _sendThroughPhone(int index, ReplyDraft draft) async {
    final id = await DesktopActions.reply(draft.to, draft.text.trim());
    final started = DateTime.now();
    final done = Completer<void>();
    Future<void> check() async {
      final action = await DesktopActions.state(id);
      final status = switch (action?.state) {
        ActionState.done =>
          action!.outcome == 'sent' ? DraftStatus.sent : DraftStatus.onPhone,
        ActionState.failed => DraftStatus.failed,
        _ =>
          DateTime.now().difference(started) > const Duration(seconds: 40)
              ? DraftStatus.waitingForPhone
              : DraftStatus.sending,
      };
      if (isClosed) return;
      _updateDraft(
        index,
        (d) => d.copyWith(
          status: status,
          doneAt: status == DraftStatus.sent ? DateTime.now() : null,
        ),
      );
      if (status != DraftStatus.sending &&
          status != DraftStatus.waitingForPhone &&
          !done.isCompleted) {
        done.complete();
      }
    }

    PhoneActions.changed.addListener(check);
    // Also notices the 40 seconds passing when nothing changes.
    final tick = Timer.periodic(const Duration(seconds: 10), (_) => check());
    await done.future.timeout(const Duration(minutes: 10), onTimeout: () {});
    tick.cancel();
    PhoneActions.changed.removeListener(check);
  }

  void _updateDraft(int index, ReplyDraft Function(ReplyDraft) change) {
    final draft = _messages[index].draft;
    if (draft == null) return;
    _messages[index] = _messages[index].copyWith(draft: change(draft));
    _emit();
  }

  // ── Search-only ──────────────────────────────────────────────────────────

  /// Shows the messages that matched, for when nothing can write sentences.
  Future<void> _showSearch(
    String question,
    List<RawData> matches, {
    required int checked,
    required bool smallTalk,
    required List<RawData> allNotifications,
  }) async {
    var note = '';
    if (matches.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('user_name') ?? 'sir';
      note = smallTalk
          ? "I can search your messages, but chatting back needs a way to write."
          : _noMatchFallback(name, allNotifications);
    }
    _messages.add(
      ChatMessage(
        sender: 'echo',
        text: note,
        kind: MessageKind.search,
        ragSources: matches,
        checked: checked,
        question: question,
      ),
    );
    _emit();
  }

  /// "Get a written answer instead": choose an engine if needed, then answer
  /// the same question in sentences.
  Future<void> writeAnswer(int index) async {
    final m = _messages[index];
    final question = m.question;
    final choose = _chooseEngine;
    if (question.isEmpty || choose == null) return;
    if (await EngineGate.current() == null && !await choose('ask')) return;
    if (isClosed) return;
    _messages[index] = m.copyWith(question: '');
    _emit(searching: true);
    await _answer(question);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// A dead-end "I don't know" helps no one — point $name at what's actually
  /// in the vault instead, so a miss still leaves them with something useful
  /// to ask next.
  String _noMatchFallback(String name, List<RawData> allNotifications) {
    if (allNotifications.isEmpty) {
      return "I haven't captured any notifications yet, $name — once some "
          "come in, ask me anything about them.";
    }

    final counts = <String, int>{};
    for (final n in allNotifications) {
      final source = n.source.trim();
      final label = source.isEmpty
          ? 'Unknown'
          : '${source[0].toUpperCase()}${source.substring(1).toLowerCase()}';
      counts[label] = (counts[label] ?? 0) + 1;
    }
    final topSources = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final mentioned = topSources
        .take(2)
        .map((e) => '${e.value} from ${e.key}')
        .join(' and ');

    return "I don't see anything about that in your notifications, $name — "
        "but I do have $mentioned if that's useful instead.";
  }

  static const _maxContentChars = 280;

  static String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max).trimRight()}…';

  void cancelInference() {
    _activeWrite?.cancel();
    _activeWrite = null;
  }

  @override
  Future<void> close() async {
    cancelInference();
    return super.close();
  }
}

/// What Echo says after adding to-dos: which day's list they went on.
String addedLine(List<TodoItem> added, DateTime now) {
  if (added.isEmpty) return "There's nothing new to add from those.";
  final list = switch (addedTo(added, now)) {
    'today' => "today's list",
    'tomorrow' => "tomorrow's list",
    _ => 'your list',
  };
  return added.length == 1 ? "Done. It's on $list." : "Done. They're on $list.";
}

/// The list [added] went on, as a card heading says it: "today",
/// "tomorrow", or "your list" when they're on different days.
String addedTo(List<TodoItem> added, DateTime now) {
  final days = added.map((i) => startOfDay(i.day)).toSet();
  if (days.length != 1) return 'your list';
  return switch (days.single.difference(startOfDay(now)).inDays) {
    0 => 'today',
    1 => 'tomorrow',
    _ => 'your list',
  };
}
