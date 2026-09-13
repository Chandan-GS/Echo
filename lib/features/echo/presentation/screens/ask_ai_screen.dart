import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/services/echo_tts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/presentation/widgets/echo_app_bar.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/cubit/ask_ai_cubit.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:project_echo/features/echo/presentation/widgets/siri_waveform_visualizer.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AskAiScreen extends StatelessWidget {
  const AskAiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AskAiCubit(),
      child: const _AskAiView(),
    );
  }
}

class _AskAiView extends StatefulWidget {
  const _AskAiView();

  @override
  State<_AskAiView> createState() => _AskAiViewState();
}

enum AudioState { initializing, listening, processing, speaking, idle }

class _AskAiViewState extends State<_AskAiView> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Audio State
  bool _isAudioMode = false;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  AudioState _audioState = AudioState.idle;
  String _userTranscription = '';

  // TTS Streaming variables
  int _spokenLength = 0;
  bool _isSpeaking = false;
  final List<String> _ttsQueue = [];

  @override
  void initState() {
    super.initState();
    _initAudio();
    _loadUserName();
  }

  String? _userName;
  Future<void> _loadUserName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) setState(() => _userName = prefs.getString('user_name'));
    } catch (_) {}
  }

  Future<void> _initAudio() async {
    // Apply the voice + rate the user chose during onboarding (or in settings).
    await EchoTts.applyVoicePreferences(_flutterTts);
    await _flutterTts.setVolume(1.0);

    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
      _speakNextInQueue();
    });
  }

  Future<bool> _initSpeech() async {
    if (_speech.isAvailable) return true;
    return await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (_audioState == AudioState.listening &&
              _userTranscription.isNotEmpty) {
            _submitTranscription();
          } else if (_audioState == AudioState.listening &&
              _userTranscription.isEmpty) {
            setState(() {
              _audioState = AudioState.idle;
            });
          }
        }
      },
      onError: (errorNotification) {
        setState(() {
          _audioState = AudioState.idle;
        });
      },
    );
  }

  void _startListening() async {
    setState(() {
      _isAudioMode = true;
    });
    bool available = await _initSpeech();
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Microphone permission is required to use this feature.',
            ),
          ),
        );
        setState(() {
          _isAudioMode = false;
        });
      }
      return;
    }

    setState(() {
      _audioState = AudioState.listening;
      _userTranscription = '';
      _spokenLength = 0;
      _ttsQueue.clear();
      _isSpeaking = false;
    });
    _flutterTts.stop();

    _speech.listen(
      onResult: (result) {
        setState(() {
          _userTranscription = result.recognizedWords;
          if (result.finalResult) {
            _submitTranscription();
          }
        });
      },
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 4),
        cancelOnError: true,
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  void _submitTranscription() {
    if (_userTranscription.trim().isEmpty) return;
    if (_audioState != AudioState.listening) return;

    _speech.stop();
    setState(() {
      _audioState = AudioState.processing;
    });
    context.read<AskAiCubit>().sendMessage(_userTranscription);
  }

  void _speakNextInQueue() async {
    if (_ttsQueue.isNotEmpty && !_isSpeaking) {
      _isSpeaking = true;
      String textToSpeak = _ttsQueue.removeAt(0).replaceAll('*', '');
      await _flutterTts.speak(textToSpeak);
    } else if (_ttsQueue.isEmpty &&
        !_isSpeaking &&
        _audioState == AudioState.speaking) {
      setState(() {
        _audioState = AudioState.idle;
      });
    }
  }

  void _handleAiStateChange(AskAiMessageReceived state) {
    if (state.messages.isEmpty) return;
    if (!_isAudioMode) return;

    final lastMsg = state.messages.last;

    if (lastMsg.sender == 'echo') {
      if (state.isSearching) {
        if (_audioState != AudioState.processing) {
          setState(() => _audioState = AudioState.processing);
        }
      } else {
        if (_audioState != AudioState.speaking) {
          setState(() => _audioState = AudioState.speaking);
        }

        String currentText = lastMsg.text;
        if (currentText.length > _spokenLength) {
          String newText = currentText.substring(_spokenLength);

          final sentenceRegex = RegExp(r'[^.!?]+[.!?]+');
          Iterable<Match> matches = sentenceRegex.allMatches(newText);

          int lastMatchEnd = 0;
          for (Match match in matches) {
            _ttsQueue.add(match.group(0)!.trim());
            lastMatchEnd = match.end;
          }

          _spokenLength += lastMatchEnd;
          _speakNextInQueue();
        }

        if (!lastMsg.isGenerating) {
          if (_spokenLength < currentText.length) {
            String remainingText = currentText.substring(_spokenLength).trim();
            if (remainingText.isNotEmpty) {
              _ttsQueue.add(remainingText);
              _spokenLength = currentText.length;
              _speakNextInQueue();
            }
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _speech.cancel();
    _flutterTts.stop();
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: const EchoAppBar(title: 'Ask Echo'),
      body: BlocConsumer<AskAiCubit, AskAiState>(
        listener: (context, state) {
          if (state is AskAiMessageReceived) {
            _scrollToBottom();
            _handleAiStateChange(state);
          }
        },
        builder: (context, state) {
          List<ChatMessage> messages = [];
          bool isSearching = false;

          if (state is AskAiMessageReceived) {
            messages = state.messages;
            isSearching = state.isSearching;
          }

          final isDisabled = messages.any((m) => m.isGenerating) || isSearching;

          return Stack(
            children: [
              Positioned.fill(
                child: messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(
                          left: 20,
                          right: 20,
                          top: 20,
                          bottom: 120, // space for input field
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          return _AnimatedMessage(
                            key: ValueKey('msg_$index'),
                            message: messages[index],
                          );
                        },
                      ),
              ),
              Positioned(
                bottom: 20,
                left: 16,
                right: 16,
                child: SafeArea(
                  top: false,
                  child: _buildInputArea(context, isDisabled),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static const _suggestions = [
    "What's on my schedule today?",
    'Any messages from work I missed?',
    'Summarize my notifications',
  ];

  Widget _buildEmptyState() {
    final name = (_userName?.trim().isNotEmpty ?? false) ? _userName!.trim() : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 118),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const EchoMascot(state: EchoState.idle, size: 158),
                  const SizedBox(height: 4),
                  Text(
                    name != null ? 'How can I help, $name?' : 'How can I help?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.oldStandardTt(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Ask about your schedule, messages, or anything in your local vault.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunito(
                      fontSize: 14.5,
                      color: context.colors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 26),
                  for (final s in _suggestions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SuggestionChip(
                        text: s,
                        onTap: () =>
                            context.read<AskAiCubit>().sendMessage(s),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _toggleAudioMode() {
    if (_isAudioMode) {
      _speech.stop();
      _flutterTts.stop();
      context.read<AskAiCubit>().cancelInference();
      setState(() {
        _isAudioMode = false;
        _audioState = AudioState.idle;
      });
    } else {
      _startListening();
    }
  }

  void _onWaveTap() {
    if (_audioState == AudioState.idle) {
      _startListening();
    } else if (_audioState == AudioState.listening) {
      _submitTranscription();
    } else if (_audioState == AudioState.speaking ||
        _audioState == AudioState.processing) {
      _flutterTts.stop();
      context.read<AskAiCubit>().cancelInference();
      setState(() {
        _audioState = AudioState.idle;
      });
    }
  }

  String _getTranscribedText() {
    if (_audioState == AudioState.listening && _userTranscription.isNotEmpty) {
      return _userTranscription;
    }
    switch (_audioState) {
      case AudioState.initializing:
        return 'Initializing...';
      case AudioState.listening:
        return 'Listening...';
      case AudioState.processing:
        return 'Thinking...';
      case AudioState.speaking:
        return 'Speaking...';
      case AudioState.idle:
        return 'Tap to speak...';
    }
  }

  Widget _buildInputArea(BuildContext context, bool isDisabled) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: _isAudioMode ? Colors.transparent : context.colors.surface,
        borderRadius: BorderRadius.circular(34),
        boxShadow: _isAudioMode
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: _isAudioMode
                    ? _buildAudioContent()
                    : _buildTextContent(isDisabled),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: isDisabled && !_isAudioMode ? null : _toggleAudioMode,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _isAudioMode ? 100 : 48,
                height: _isAudioMode ? 100 : 48,
                decoration: BoxDecoration(
                  color: context.colors.background,
                  shape: BoxShape.circle,
                ),
                child: _isAudioMode
                    ? Icon(Icons.close_rounded, size: 22)
                    : Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: SvgPicture.asset(
                          colorFilter: ColorFilter.mode(
                            context.colors.textPrimary,
                            BlendMode.srcIn,
                          ),
                          "assets/icons/audio_wave.svg",
                          height: 22,
                          width: 22,
                        ),
                      ),
              ),
            ),
            if (!_isAudioMode) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: isDisabled ? null : () => _sendInput(context),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isDisabled
                        ? context.colors.dividerColor
                        : context.colors.buttonDark,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    color: isDisabled
                        ? context.colors.textInverse.withValues(alpha: 0.7)
                        : context.colors.textInverse,
                    size: 22,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAudioContent() {
    return GestureDetector(
      onTap: _onWaveTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        alignment: Alignment.center,
        height: 100, // Fixed height to prevent jumping when wave appears
        child: Row(
          key: const ValueKey('audio_content'),
          children: [
            const SizedBox(width: 16),
            Expanded(
              child:
                  _audioState == AudioState.speaking ||
                      _audioState == AudioState.listening
                  ? SizedBox(
                      height: 100,
                      child: SiriWaveformVisualizer(
                        isPlaying: true,
                        amplitude: 1.0,
                        onTap: _onWaveTap,
                        height: 100,
                      ),
                    )
                  : Text(
                      _getTranscribedText(),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary.withValues(
                          alpha: 0.5,
                        ), // Darker text for transparent background
                      ),
                    ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildTextContent(bool isDisabled) {
    return TextField(
      key: const ValueKey('text_content'),
      controller: _inputController,
      enabled: !isDisabled,
      focusNode: _focusNode,
      minLines: 1,
      maxLines: 5,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.send,
      style: GoogleFonts.nunito(
        fontSize: 16,
        color: context.colors.textPrimary,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: 'Type your question...',
        hintStyle: GoogleFonts.nunito(
          color: context.colors.textSecondary.withValues(alpha: 0.5),
          fontSize: 16,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: InputBorder.none,
      ),
      onSubmitted: (val) {
        if (!isDisabled) _sendInput(context);
      },
    );
  }

  void _sendInput(BuildContext context) {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _inputController.clear();
    _focusNode.unfocus();
    context.read<AskAiCubit>().sendMessage(text);
  }
}

/// A tappable starter prompt on the empty Ask Echo screen.
class _SuggestionChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _SuggestionChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.colors.dividerColor.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: context.colors.primaryGreen,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: GoogleFonts.nunito(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedMessage extends StatelessWidget {
  final ChatMessage message;

  const _AnimatedMessage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.sender == 'user';
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          alignment: isUser ? Alignment.bottomRight : Alignment.bottomLeft,
          child: child,
        );
      },
      child: _MessageContent(message: message),
    );
  }
}

class _MessageContent extends StatelessWidget {
  final ChatMessage message;

  const _MessageContent({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.sender == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: isUser ? _buildUserMessage(context) : _buildAiMessage(context),
      ),
    );
  }

  Widget _buildUserMessage(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.buttonDark,
        borderRadius: BorderRadius.circular(
          24,
        ).copyWith(bottomRight: const Radius.circular(8)),
      ),
      child: Text(
        message.text,
        style: GoogleFonts.nunito(
          color: context.colors.surface,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildAiMessage(BuildContext context) {
    final generating = message.text.isEmpty && message.isGenerating;

    // Only the thinking state carries the mascot.
    if (generating) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const EchoMascot(state: EchoState.thinking, size: 42),
          const SizedBox(width: 8),
          _thinkingBubble(context),
        ],
      );
    }

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.82,
      ),
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(
          20,
        ).copyWith(bottomLeft: const Radius.circular(6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEditorialText(message.text, context),
          if (message.ragSources.isNotEmpty) ...[
            const SizedBox(height: 12),
            RagSourcesWidget(sources: message.ragSources),
          ],
        ],
      ),
    );
  }

  Widget _thinkingBubble(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: context.selectionFill,
        borderRadius: BorderRadius.circular(
          18,
        ).copyWith(bottomLeft: const Radius.circular(6)),
      ),
      child: Text(
        'Echo is thinking…',
        style: GoogleFonts.nunito(
          fontSize: 13.5,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w700,
          color: context.onSelection,
        ),
      ),
    );
  }

  Widget _buildEditorialText(String text, BuildContext context) {
    final List<TextSpan> spans = [];
    final RegExp regExp = RegExp(r'\*\*(.*?)\*\*');
    int lastIndex = 0;

    for (final match in regExp.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(
          TextSpan(
            text: text.substring(lastIndex, match.start),
            style: GoogleFonts.nunito(
              color: context.colors.textPrimary,
              fontSize: 15.5,
              height: 1.5,
            ),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: GoogleFonts.nunito(
            color: context.colors.primaryGreen,
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            height: 1.5,
          ),
        ),
      );
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(lastIndex),
          style: GoogleFonts.oldStandardTt(
            color: context.colors.textPrimary,
            fontSize: 18,
            height: 1.5,
          ),
        ),
      );
    }

    return RichText(text: TextSpan(children: spans));
  }
}

class _TypingDotAnimation extends StatefulWidget {
  const _TypingDotAnimation();

  @override
  State<_TypingDotAnimation> createState() => _TypingDotAnimationState();
}

class _TypingDotAnimationState extends State<_TypingDotAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final offset = math.sin(
            (_ctrl.value * 2 * math.pi) - (i * math.pi / 2),
          );
          final scale = 0.5 + 0.5 * (offset + 1) / 2;
          return Padding(
            padding: const EdgeInsets.only(right: 4.0),
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: context.colors.textSecondary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class RagSourcesWidget extends StatefulWidget {
  final List<RawData> sources;
  const RagSourcesWidget({super.key, required this.sources});

  @override
  State<RagSourcesWidget> createState() => RagSourcesWidgetState();
}

class RagSourcesWidgetState extends State<RagSourcesWidget> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(_expanded ? 16 : 24),
        border: Border.all(color: context.colors.dividerColor, width: 1),
        boxShadow: _expanded
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _expanded = !_expanded;
              });
            },
            borderRadius: BorderRadius.circular(_expanded ? 16 : 24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 14,
                    color: context.colors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.sources.length} local notifications used',
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: _expanded
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14).copyWith(top: 0),
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: widget.sources.map((src) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 10.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: context.colors.background,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _getSourceIcon(src.source),
                                    size: 12,
                                    color: context.colors.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        src.sender,
                                        style: GoogleFonts.nunito(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: context.colors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        src.content,
                                        style: GoogleFonts.nunito(
                                          fontSize: 12,
                                          color: context.colors.textSecondary,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  IconData _getSourceIcon(String source) {
    switch (source.toLowerCase()) {
      case 'slack':
        return Icons.chat_bubble_outline_rounded;
      case 'sms':
        return Icons.sms_outlined;
      case 'whatsapp':
        return Icons.message_outlined;
      case 'calendar':
        return Icons.calendar_today_outlined;
      case 'gmail':
      case 'email':
        return Icons.mail_outline_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }
}
