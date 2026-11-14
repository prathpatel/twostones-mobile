import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/challenge/challenge.dart';
import 'package:lichess_mobile/src/model/challenge/challenge_repository.dart';
import 'package:lichess_mobile/src/model/common/game.dart';
import 'package:lichess_mobile/src/model/common/id.dart';

import '../../test_container.dart';
import '../../test_helpers.dart';

void main() {
  group('ChallengeRepository', () {
    test('list', () async {
      final mockClient = MockClient((request) {
        if (request.url.path == '/api/challenge') {
          return mockResponse(challengesList, 200);
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);
      final repo = container.read(challengeRepositoryProvider);
      final result = await repo.list();

      expect(result.inward, isA<IList<Challenge>>());
      expect(result.outward, isA<IList<Challenge>>());
      expect(result.inward.length, 1);
      expect(result.outward.length, 1);
    });

    test('show', () async {
      final mockClient = MockClient((request) {
        if (request.url.path == '/api/challenge/H9fIRZUk/show') {
          return mockResponse(challenge, 200);
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);
      final repo = container.read(challengeRepositoryProvider);
      final result = await repo.show(const ChallengeId('H9fIRZUk'));

      expect(result, isA<Challenge>());
    });

    test('create open challenge', () async {
      final mockClient = MockClient((request) {
        if (request.url.path == '/setup/friend' &&
            request.headers['Accept'] == 'application/json') {
          expect(request.url.queryParameters.containsKey('user'), isFalse);
          return mockResponse('{"challenge": $challenge, "socketVersion": 3}', 200);
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);
      final repo = container.read(challengeRepositoryProvider);
      final result = await repo.create(
        const ChallengeRequest(
          destUser: null,
          boardSize: 19,
          timeControl: ChallengeTimeControlType.clock,
          rated: false,
          sideChoice: SideChoice.black,
        ),
      );

      expect(result.id, const ChallengeId('H9fIRZUk'));
      expect(result.socketVersion, 3);
    });
  });
}

const challengesList = '''
{"in": [ { "socketVersion": 0, "id": "H9fIRZUk", "url": "https://twostones.org/H9fIRZUk", "status": "created", "challenger": { "id": "bot1", "name": "Bot1", "rating": 1500, "title": "BOT", "provisional": true, "online": true, "lag": 4 }, "destUser": { "id": "bobby", "name": "Bobby", "rating": 1635, "title": "GM", "provisional": true, "online": true, "lag": 4 }, "size": 19, "handicap": 0, "rated": true, "speed": "rapid", "timeControl": { "type": "clock", "limit": 600, "increment": 0, "show": "10+0" }, "color": "random", "finalColor": "black", "perf": { "icon": "", "name": "Rapid" }, "direction": "out" } ], "out": [ { "socketVersion": 0, "id": "H9fIRZUk", "url": "https://twostones.org/H9fIRZUk", "status": "created", "challenger": { "id": "bot1", "name": "Bot1", "rating": 1500, "title": "BOT", "provisional": true, "online": true, "lag": 4 }, "destUser": { "id": "bobby", "name": "Bobby", "rating": 1635, "title": "GM", "provisional": true, "online": true, "lag": 4 }, "size": 19, "handicap": 0, "rated": true, "speed": "rapid", "timeControl": { "type": "clock", "limit": 600, "increment": 0, "show": "10+0" }, "color": "random", "finalColor": "black", "perf": { "icon": "", "name": "Rapid" }, "direction": "out" } ] }
''';

const challenge = '''
{ "socketVersion": 0, "id": "H9fIRZUk", "url": "https://twostones.org/H9fIRZUk", "status": "created", "challenger": { "id": "bot1", "name": "Bot1", "rating": 1500, "title": "BOT", "provisional": true, "online": true, "lag": 4 }, "destUser": { "id": "bobby", "name": "Bobby", "rating": 1635, "title": "GM", "provisional": true, "online": true, "lag": 4 }, "size": 19, "handicap": 0, "rated": true, "speed": "rapid", "timeControl": { "type": "clock", "limit": 600, "increment": 0, "show": "10+0" }, "color": "random", "finalColor": "black", "perf": { "icon": "", "name": "Rapid" }, "direction": "out" }
''';
