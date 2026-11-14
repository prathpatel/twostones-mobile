import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/game/exported_game.dart';
import 'package:lichess_mobile/src/model/game/game.dart';
import 'package:lichess_mobile/src/model/game/game_status.dart';
import 'package:lichess_mobile/src/model/game/player.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/view/game/game_list_tile.dart';
import 'package:lichess_mobile/src/widgets/board_thumbnail.dart';
import 'package:material_ui/material_ui.dart';

import '../../test_provider_scope.dart';

LightExportedGame makeGame({String? result, Side? winner = Side.white, int handicap = 0}) {
  return LightExportedGame(
    id: const GameId('qVChCOTc'),
    source: GameSource.lobby,
    rated: false,
    speed: Speed.classical,
    perf: Perf.classical,
    createdAt: DateTime(2021, 1, 1),
    lastMoveAt: DateTime(2021, 1, 1),
    status: GameStatus.variantEnd,
    white: const Player(
      user: LightUser(id: UserId('white'), name: 'White'),
    ),
    black: const Player(
      user: LightUser(id: UserId('black'), name: 'Black'),
    ),
    boardSize: 13,
    komi: 7.5,
    handicap: handicap,
    board: replayGoGame(size: 13, moves: const ['dd', 'jj']).last.boardString,
    lastMove: 'jj',
    result: result,
    winner: winner,
  );
}

void main() {
  group('GameListTile', () {
    testWidgets('shows the opponent, the board size and the result', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: GameListTile(item: (game: makeGame(result: 'W+3.5'), pov: Side.white)),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.text('Black'), findsOneWidget);
      expect(find.textContaining('13×13'), findsOneWidget);
      expect(find.textContaining('W+3.5'), findsOneWidget);
    });

    testWidgets('a handicap game shows its handicap', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(body: GameListTile(item: (game: makeGame(handicap: 3), pov: Side.black))),
      );
      await tester.pumpWidget(app);

      expect(find.textContaining('13×13 H3'), findsOneWidget);
      // no record of the result: a symbol shows that the player lost
      expect(find.textContaining('▼'), findsOneWidget);
    });
  });

  group('GameListDetailTile', () {
    testWidgets('shows the last position on a small board', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: GameListDetailTile(item: (game: makeGame(result: 'W+R'), pov: Side.black)),
        ),
      );
      await tester.pumpWidget(app);

      final thumbnail = tester.widget<BoardThumbnail>(find.byType(BoardThumbnail));
      expect(thumbnail.position?.size, 13);
      expect(thumbnail.position?.board.where((stone) => stone != null).length, 2);
      expect(find.text('W+R'), findsOneWidget);
    });
  });
}
