import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/routes/app_router.dart';

void main() {
  final router = createRouter(true);

  const routes = [
    '/echo',
    '/people',
    '/history',
    '/profile',
    '/echo/chat',
    '/todo',
    '/vault',
    '/groups',
    '/person',
    '/group',
    '/briefing',
    '/quiet',
    '/digest',
    '/you/hears',
    '/you/streak',
    '/you/widgets',
    '/you/desktop',
    '/settings',
  ];

  for (final path in routes) {
    test('$path resolves', () {
      expect(router.configuration.findMatch(Uri.parse(path)).isError, isFalse);
    });
  }
}
