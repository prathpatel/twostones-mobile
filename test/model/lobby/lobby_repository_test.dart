import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/lobby/correspondence_seek.dart';
import 'package:lichess_mobile/src/model/lobby/lobby_repository.dart';
import 'package:lichess_mobile/src/network/http.dart';

import '../../test_container.dart';
import '../../test_helpers.dart';

void main() {
  final mockClient = MockClient((request) {
    if (request.url.path == '/lobby/seeks') {
      return mockResponse(seeksResponse, 200);
    }
    return mockResponse('', 404);
  });

  group('LobbyRepository.getCorrespondenceSeeks', () {
    test('read json', () async {
      final container = await lichessClientContainer(mockClient);
      final client = container.read(lichessClientProvider);
      final repo = LobbyRepository(client);

      final data = await repo.getCorrespondenceSeeks();

      expect(data, isA<IList<CorrespondenceSeek>>());
      expect(data.length, 2);
      expect(data[0].id, const GameId('OIBZi6bn'));
      expect(data[0].boardSize, 19);
      expect(data[1].rated, isTrue);
    });
  });
}

const seeksResponse = '''
[
  {"id": "OIBZi6bn", "username": "veloce", "rating": 1500, "size": 19, "perf": {"key": "correspondence"}, "mode": 0, "days": 3, "provisional": true},
  {"id": "48DixX1Z", "username": "chabrot", "rating": 1620, "size": 9, "perf": {"key": "correspondence"}, "mode": 1, "days": 5}
]
''';
