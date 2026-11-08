import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/engine_gate.dart';

void main() {
  group('resolveWritingEngine', () {
    WritingEngine? resolve({
      bool prefer = false,
      String? host,
      bool offline = true,
      String key = '',
      bool model = false,
    }) => resolveWritingEngine(
      preferComputer: prefer,
      computerHost: host,
      offlineEngine: offline,
      geminiKey: key,
      modelOnPhone: model,
    );

    test('nothing set means the sheet is needed', () {
      expect(resolve(), isNull);
    });

    test('the defaults count as nothing set until the model is on disk', () {
      expect(resolve(offline: true, model: false), isNull);
      expect(resolve(offline: true, model: true), WritingEngine.phone);
    });

    test('Gemini needs both the setting and a key', () {
      expect(resolve(offline: false, key: 'AIza123'), WritingEngine.gemini);
      expect(resolve(offline: true, key: 'AIza123'), isNull);
      expect(resolve(offline: false, key: '   '), isNull);
    });

    test('a key that is off leaves the phone model in charge', () {
      expect(
        resolve(offline: true, key: 'AIza123', model: true),
        WritingEngine.phone,
      );
    });

    test('a paired computer comes first, and needs an address', () {
      expect(
        resolve(prefer: true, host: '1.2.3.4:1', model: true),
        WritingEngine.computer,
      );
      expect(resolve(prefer: true), isNull);
      expect(resolve(prefer: false, host: '1.2.3.4:1'), isNull);
    });
  });

  group('download failures', () {
    test('a full disk is reported as no space', () {
      expect(
        classifyDownloadError(
          const FileSystemException('write', 'x', OSError('No space left', 28)),
        ),
        DownloadProblem.noSpace,
      );
    });

    test('network errors are reported as offline', () {
      expect(
        classifyDownloadError(const SocketException('gone')),
        DownloadProblem.offline,
      );
      expect(
        classifyDownloadError(
          DioException(
            requestOptions: RequestOptions(),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
        DownloadProblem.offline,
      );
      expect(
        classifyDownloadError(
          DioException(
            requestOptions: RequestOptions(),
            error: const SocketException('reset'),
          ),
        ),
        DownloadProblem.offline,
      );
    });

    test('anything else is a plain failure', () {
      expect(classifyDownloadError(Exception('x')), DownloadProblem.failed);
    });
  });

  group('resuming', () {
    test('keeps the partial only when the server honoured the range', () {
      expect(resumeOffset(kept: 500, statusCode: 206), 500);
      expect(resumeOffset(kept: 500, statusCode: 200), 0);
    });

    test('reads the whole size from Content-Range', () {
      expect(totalFromContentRange('bytes 100-899/900'), 900);
      expect(totalFromContentRange('bytes 100-899/*'), isNull);
      expect(totalFromContentRange(null), isNull);
    });
  });

  group('networkKindOf', () {
    test('Wi-Fi interfaces win over mobile ones', () {
      expect(networkKindOf(['wlan0', 'rmnet_data0']), NetworkKind.wifi);
    });

    test('recognises the common cellular names', () {
      expect(networkKindOf(['rmnet_data1']), NetworkKind.mobile);
      expect(networkKindOf(['ccmni0']), NetworkKind.mobile);
      expect(networkKindOf(['v4-rmnet_data0']), NetworkKind.mobile);
    });

    test('nothing recognised is unknown, not a block', () {
      expect(networkKindOf(['tun0']), NetworkKind.unknown);
      expect(networkKindOf(const []), NetworkKind.unknown);
    });
  });
}
