import 'dart:math' as math;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'bert_tokenizer.dart';

class TfliteEmbeddingService {
  static TfliteEmbeddingService? _instance;
  final BertTokenizer _tokenizer = BertTokenizer();
  Interpreter? _interpreter;
  bool _initialized = false;

  TfliteEmbeddingService._();

  static TfliteEmbeddingService get instance {
    _instance ??= TfliteEmbeddingService._();
    return _instance!;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    await _tokenizer.initialize();

    final options = InterpreterOptions()..threads = 2;
    _interpreter = await Interpreter.fromAsset(
      'assets/ai refs/all-MiniLM-L6-v2-quant.tflite',
      options: options,
    );
    _initialized = true;
  }

  Future<List<double>> getEmbedding(String text) async {
    await initialize();

    const int sequenceLength = 256;
    final tokenIds = _tokenizer.tokenizeAndEncode(text, maxLen: sequenceLength);

    // Prepare inputs
    final inputIds = List<int>.filled(sequenceLength, 0);
    final attentionMask = List<int>.filled(sequenceLength, 0);

    for (int i = 0; i < tokenIds.length; i++) {
      inputIds[i] = tokenIds[i];
      attentionMask[i] = 1;
    }

    final List<List<int>> inputIdsBatch = [inputIds];
    final List<List<int>> attentionMaskBatch = [attentionMask];

    final inputTensors = _interpreter!.getInputTensors();
    final inputs = <Object>[];

    // Determine input matching dynamically based on signature size
    if (inputTensors.length == 3) {
      final tokenTypeIds = List<int>.filled(sequenceLength, 0);
      final List<List<int>> tokenTypeIdsBatch = [tokenTypeIds];
      inputs.add(inputIdsBatch);
      inputs.add(attentionMaskBatch);
      inputs.add(tokenTypeIdsBatch);
    } else {
      inputs.add(inputIdsBatch);
      inputs.add(attentionMaskBatch);
    }

    final outputTensor = _interpreter!.getOutputTensors().first;
    final outputShape = outputTensor.shape;
    List<double> rawVector;

    if (outputShape.length == 3) {
      // Shape [1, seqLength, embDim] (needs mean pooling)
      final int batchSize = outputShape[0];
      final int seqLen = outputShape[1];
      final int embDim = outputShape[2];

      final outputBuffer = List<List<List<double>>>.generate(
        batchSize,
        (_) => List<List<double>>.generate(
          seqLen,
          (_) => List<double>.filled(embDim, 0.0),
        ),
      );

      _interpreter!.runForMultipleInputs(inputs, {0: outputBuffer});

      final tokenEmbeddings = outputBuffer.first;
      rawVector = List<double>.filled(embDim, 0.0);
      int validTokensCount = 0;

      for (int i = 0; i < seqLen; i++) {
        if (i < tokenIds.length) {
          validTokensCount++;
          for (int d = 0; d < embDim; d++) {
            rawVector[d] += tokenEmbeddings[i][d];
          }
        }
      }

      if (validTokensCount > 0) {
        for (int d = 0; d < embDim; d++) {
          rawVector[d] /= validTokensCount;
        }
      }
    } else {
      // Shape [1, embDim] (pooled sentence embedding)
      final outputBuffer = List<List<double>>.generate(
        outputShape[0],
        (_) => List<double>.filled(outputShape[1], 0.0),
      );

      _interpreter!.runForMultipleInputs(inputs, {0: outputBuffer});
      rawVector = outputBuffer.first;
    }

    return _l2Normalize(rawVector);
  }

  List<double> _l2Normalize(List<double> vector) {
    double sumOfSquares = 0.0;
    for (final val in vector) {
      sumOfSquares += val * val;
    }
    final norm = math.sqrt(sumOfSquares);
    if (norm == 0.0) return vector;

    return vector.map((val) => val / norm).toList();
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _initialized = false;
  }
}
