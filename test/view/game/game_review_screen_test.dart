import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/view/game/game_review_screen.dart';
import 'package:lichess_mobile/src/widgets/go_board.dart';

import '../../network/fake_http_client_factory.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

/// A 9×9 game won by counting, as `/api/mobile/game/:id` sends it.
const _gameResponse = '''
{
  "id": "Qa7FJNk2", "rated": true, "speed": "blitz", "perf": "blitz",
  "size": 9, "handicap": 0, "komi": 7.5,
  "createdAt": 1756425600000, "lastMoveAt": 1756426600000,
  "status": "variantEnd", "winner": "black", "result": "B+1.5",
  "players": {
    "black": {"user": {"id": "steven", "name": "Steven"}, "rating": 1500},
    "white": {"user": {"id": "peter", "name": "Peter"}, "rating": 1500}
  },
  "clock": {"initial": 180, "increment": 2, "totalTime": 260},
  "moves": "ee cc pass pass",
  "scoring": {
    "dead": [],
    "accepted": ["black", "white"],
    "score": {
      "black": 45, "white": 43.5, "komi": 7.5, "result": "B+1.5",
      "territory": {"black": 36, "white": 27}, "stones": {"black": 1, "white": 1},
      "ownership": [[0, 1], [8, 2]]
    }
  }
}
''';

void main() {
  Future<void> openReview(WidgetTester tester) async {
    final client = MockClient((request) {
      if (request.url.path == '/api/mobile/game/Qa7FJNk2') {
        return mockResponse(_gameResponse, 200);
      }
      return mockResponse('', 404);
    });
    final app = await makeTestProviderScopeApp(
      tester,
      home: const GameReviewScreen(gameId: GameId('Qa7FJNk2'), orientation: Side.black),
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(() => client),
        ),
      },
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the last position of the game with its count and result', (tester) async {
    await openReview(tester);

    final board = tester.widget<GoBoard>(find.byType(GoBoard));
    expect(board.position.board.where((stone) => stone != null).length, 2);
    expect(board.territory[0], Side.black);
    expect(board.territory[8], Side.white);
    expect(find.text('Steven'), findsOneWidget);
    expect(find.text('Peter'), findsOneWidget);
    expect(find.textContaining('B+1.5'), findsOneWidget);
  });

  testWidgets('the buttons replay the game from its first move', (tester) async {
    await openReview(tester);

    await tester.tap(find.byIcon(CupertinoIcons.backward_end));
    await tester.pump();
    var board = tester.widget<GoBoard>(find.byType(GoBoard));
    expect(board.position.board.every((stone) => stone == null), isTrue);
    expect(board.territory.isEmpty, isTrue);

    await tester.tap(find.byIcon(CupertinoIcons.chevron_forward));
    await tester.pump();
    board = tester.widget<GoBoard>(find.byType(GoBoard));
    expect(board.position.board[GoMove.fromKey('ee', 9)!.point!], Side.black);
    expect(board.position.board.where((stone) => stone != null).length, 1);

    await tester.tap(find.byIcon(CupertinoIcons.forward_end));
    await tester.pump();
    board = tester.widget<GoBoard>(find.byType(GoBoard));
    expect(board.position.board.where((stone) => stone != null).length, 2);
  });
}
