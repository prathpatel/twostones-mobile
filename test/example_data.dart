import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/game/exported_game.dart';
import 'package:lichess_mobile/src/model/game/game.dart';
import 'package:lichess_mobile/src/model/game/game_status.dart';
import 'package:lichess_mobile/src/model/game/player.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/model/user/user.dart';

/// The moves of a short game on a 9×9 board, in the format of the server.
const kExampleMoves = ['ee', 'cc', 'gc', 'cg', 'gg', 'ec', 'dg', 'ch', 'pass', 'pass'];

List<ExportedGame> generateExportedGames({int count = 100, String? username}) {
  return List.generate(count, (index) {
    final id = GameId('game${index.toString().padLeft(4, '0')}');
    final whitePlayer = Player(
      user: username != null && index.isEven
          ? LightUser(id: UserId.fromUserName(username), name: username)
          : username != null
          ? const LightUser(id: UserId('whiteId'), name: 'White')
          : null,
      rating: username != null ? 1500 : null,
    );
    final blackPlayer = Player(
      user: username != null && index.isOdd
          ? LightUser(id: UserId.fromUserName(username), name: username)
          : username != null
          ? const LightUser(id: UserId('blackId'), name: 'Black')
          : null,
      rating: username != null ? 1500 : null,
    );
    final steps = makeSteps(kExampleMoves.take(8));
    return ExportedGame(
      id: id,
      meta: GameMeta(
        createdAt: DateTime(2021, 1, 1),
        rated: true,
        boardSize: 9,
        komi: 7.5,
        perf: Perf.blitz,
        speed: Speed.blitz,
      ),
      source: GameSource.lobby,
      data: LightExportedGame(
        id: id,
        boardSize: 9,
        komi: 7.5,
        lastMoveAt: DateTime(2021, 1, 1),
        createdAt: DateTime(2021, 1, 1),
        perf: Perf.blitz,
        speed: Speed.blitz,
        rated: true,
        status: GameStatus.started,
        white: whitePlayer,
        black: blackPlayer,
        board: steps.last.position.boardString,
        lastMove: steps.last.move?.key(9),
        clock: (initial: const Duration(minutes: 2), increment: const Duration(seconds: 3)),
      ),
      steps: steps,
      status: GameStatus.started,
      white: whitePlayer,
      black: blackPlayer,
      youAre: username != null
          ? index.isEven
                ? Side.white
                : Side.black
          : null,
    );
  });
}

/// The steps of a game on a board of [boardSize] lines with these [moves].
IList<GameStep> makeSteps(Iterable<String> moves, {int boardSize = 9}) =>
    makeGameSteps(boardSize: boardSize, moves: moves);
