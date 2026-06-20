import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_litert_lm/flutter_litert_lm.dart';
import 'package:path_provider/path_provider.dart';

class EchoHomeScreen extends StatefulWidget {
  const EchoHomeScreen({super.key});

  @override
  State<EchoHomeScreen> createState() => _EchoHomeScreenState();
}

class _EchoHomeScreenState extends State<EchoHomeScreen> {
  LiteLmEngine? _engine;
  LiteLmConversation? _conversation;
  bool _isInitializing = true;
  bool _isGenerating = false;

  final TextEditingController _promptController = TextEditingController();
  final List<String> _messages = [];

  @override
  void initState() {
    super.initState();
    _initModel();
  }

  Future<void> _initModel() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelPath = "${dir.path}/deepseek_r1_1_5b.litertlm";

      if (!await File(modelPath).exists()) {
        setState(() {
          _messages.add(
            "System: Model file not found. Please restart onboarding.",
          );
          _isInitializing = false;
        });
        return;
      }

      String activeBackend = 'CPU';
      try {
        _engine = await LiteLmEngine.create(
          LiteLmEngineConfig(modelPath: modelPath, backend: LiteLmBackend.gpu),
        );
        activeBackend = 'GPU';
      } catch (e) {
        debugPrint('GPU initialization failed: $e. Falling back to CPU.');
        _engine = await LiteLmEngine.create(
          LiteLmEngineConfig(modelPath: modelPath, backend: LiteLmBackend.cpu),
        );
      }

      _conversation = await _engine!.createConversation(
        const LiteLmConversationConfig(
          systemInstruction: 'You are a helpful assistant. Be concise.',
          samplerConfig: LiteLmSamplerConfig(
            temperature: 0.7,
            topK: 40,
            topP: 0.95,
          ),
        ),
      );

      setState(() {
        _messages.add(
          "System: Model initialized ($activeBackend). Ready to chat!",
        );
        _isInitializing = false;
      });
    } catch (e) {
      setState(() {
        _messages.add("System Error: $e");
        _isInitializing = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _promptController.text.trim();
    if (text.isEmpty || _isGenerating || _conversation == null) return;

    _promptController.clear();
    setState(() {
      _messages.add("User: $text");
      _messages.add("Echo: ...");
      _isGenerating = true;
    });

    final stopwatch = Stopwatch()..start();
    double ttft = 0.0;
    int tokenEstimate = 0;

    try {
      final buffer = StringBuffer();
      await for (final delta in _conversation!.sendMessageStream(text)) {
        if (ttft == 0.0) {
          ttft = stopwatch.elapsedMilliseconds / 1000.0;
        }
        buffer.write(delta.text);
        tokenEstimate++;

        setState(() {
          _messages.last = "Echo: $buffer";
        });
      }

      stopwatch.stop();
      final totalTime = stopwatch.elapsedMilliseconds / 1000.0;
      final tps = tokenEstimate / (totalTime > 0 ? totalTime : 1);

      debugPrint(
        "⏱️ Stats: TTFT=${ttft.toStringAsFixed(2)}s | Time=${totalTime.toStringAsFixed(2)}s | Speed=~${tps.toStringAsFixed(1)} tok/s",
      );
    } catch (e) {
      setState(() {
        _messages.last = "Echo Error: $e";
      });
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  @override
  void dispose() {
    _conversation?.dispose();
    _engine?.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Echo Chat (DeepSeek)')),
      body: SafeArea(
        child: Column(
          children: [
            if (_isInitializing)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: LinearProgressIndicator(),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(_messages[index]),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promptController,
                      decoration: const InputDecoration(
                        hintText: 'Ask something...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _isGenerating ? null : _sendMessage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
