import 'dart:convert';
import 'package:flutter/services.dart';

class BertTokenizer {
  final Map<String, int> _vocab = {};
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    final vocabContent = await rootBundle.loadString('assets/vocab.txt');
    final lines = const LineSplitter().convert(vocabContent);
    for (int i = 0; i < lines.length; i++) {
      _vocab[lines[i].trim()] = i;
    }
    _initialized = true;
  }

  List<int> tokenizeAndEncode(String text, {int maxLen = 256}) {
    if (!_initialized) {
      throw StateError("BertTokenizer has not been initialized. Call initialize() first.");
    }

    final normalizedText = text.toLowerCase();
    final words = _basicTokenize(normalizedText);

    final List<int> ids = [];
    ids.add(_vocab['[CLS]'] ?? 101); // [CLS] token

    for (final word in words) {
      final wordPieces = _wordPieceTokenize(word);
      for (final piece in wordPieces) {
        final id = _vocab[piece];
        if (id != null) {
          ids.add(id);
        } else {
          ids.add(_vocab['[UNK]'] ?? 100);
        }
      }
    }

    // Truncate if exceeds maxLen - 1 (leave room for [SEP])
    if (ids.length > maxLen - 1) {
      ids.removeRange(maxLen - 1, ids.length);
    }

    ids.add(_vocab['[SEP]'] ?? 102); // [SEP] token

    return ids;
  }

  List<String> _basicTokenize(String text) {
    final List<String> result = [];
    final tempWord = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (_isPunctuation(char)) {
        if (tempWord.isNotEmpty) {
          result.add(tempWord.toString());
          tempWord.clear();
        }
        result.add(char);
      } else if (char.trim().isEmpty) {
        if (tempWord.isNotEmpty) {
          result.add(tempWord.toString());
          tempWord.clear();
        }
      } else {
        tempWord.write(char);
      }
    }

    if (tempWord.isNotEmpty) {
      result.add(tempWord.toString());
    }

    return result;
  }

  bool _isPunctuation(String char) {
    final code = char.codeUnitAt(0);
    if ((code >= 33 && code <= 47) ||
        (code >= 58 && code <= 64) ||
        (code >= 91 && code <= 96) ||
        (code >= 123 && code <= 126)) {
      return true;
    }
    return char != ' ' && RegExp(r'[\p{P}]', unicode: true).hasMatch(char);
  }

  List<String> _wordPieceTokenize(String word) {
    final List<String> subTokens = [];
    int start = 0;

    while (start < word.length) {
      int end = word.length;
      String? curSubstr;

      while (start < end) {
        String substr = word.substring(start, end);
        if (start > 0) {
          substr = '##$substr';
        }
        if (_vocab.containsKey(substr)) {
          curSubstr = substr;
          break;
        }
        end--;
      }

      if (curSubstr == null) {
        subTokens.add('[UNK]');
        break;
      }

      subTokens.add(curSubstr);
      start = end;
    }

    return subTokens;
  }
}
