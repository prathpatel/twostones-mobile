import 'package:fast_immutable_collections/fast_immutable_collections.dart';
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

ExportedGame _game({
  List<String> moves = const ['ee', 'cc', 'gc'],
  GameStatus status = GameStatus.started,
  Side? winner,
  GoScoring? scoring,
  int handicap = 0,
}) {
  const white = Player(
    user: LightUser(id: UserId('peter'), name: 'Peter'),
    rating: 1600,
  );
  const black = Player(
    user: LightUser(id: UserId('steven'), name: 'Steven'),
    rating: 1500,
  );
  final data = LightExportedGame(
    id: const GameId('abcdefgh'),
    rated: true,
    speed: Speed.blitz,
    perf: Perf.blitz,
    createdAt: DateTime(2026, 11, 14),
    lastMoveAt: DateTime(2026, 11, 14),
    status: status,
    white: white,
    black: black,
    boardSize: 9,
    komi: handicap > 0 ? 0.5 : 7.5,
    handicap: handicap,
  );
  return ExportedGame(
    id: data.id,
    meta: GameMeta(
      createdAt: data.createdAt,
      rated: true,
      boardSize: 9,
      komi: data.komi,
      handicap: handicap,
      speed: Speed.blitz,
      perf: Perf.blitz,
      clock: (
        initial: const Duration(minutes: 3),
        increment: const Duration(seconds: 5),
        emergency: null,
        moreTime: null,
      ),
    ),
    data: data,
    steps: makeGameSteps(boardSize: 9, handicap: handicap, moves: moves),
    status: status,
    source: GameSource.lobby,
    winner: winner,
    white: white,
    black: black,
    scoring: scoring,
  );
}

void main() {
  group('BaseGame', () {
    test('replays the moves', () {
      final game = _game();
      expect(game.moveCount, 3);
      expect(game.moveKeys.toList(), ['ee', 'cc', 'gc']);
      expect(game.lastPosition.turn, Side.white);
      expect(game.lastMove, GoMove.fromKey('gc', 9));
    });

    test('knows when both players passed', () {
      expect(_game(moves: ['ee', 'pass', 'pass']).inScoringPhase, isTrue);
      expect(_game(moves: ['ee', 'pass']).inScoringPhase, isFalse);
      expect(
        _game(moves: ['ee', 'pass', 'pass'], status: GameStatus.variantEnd).inScoringPhase,
        isFalse,
      );
    });

    test('writes the result as in a game record', () {
      expect(_game().resultString, isNull);
      expect(_game(status: GameStatus.resign, winner: Side.white).resultString, 'W+R');
      expect(_game(status: GameStatus.outoftime, winner: Side.black).resultString, 'B+T');
      expect(_game(status: GameStatus.draw).resultString, '0');
      expect(
        _game(
          status: GameStatus.variantEnd,
          winner: Side.black,
          scoring: const GoScoring(
            score: GoScore(
              black: 45,
              white: 43.5,
              komi: 7.5,
              result: 'B+1.5',
              blackTerritory: 36,
              whiteTerritory: 27,
              blackStones: 9,
              whiteStones: 9,
            ),
          ),
        ).resultString,
        'B+1.5',
      );
    });

    test('makes an SGF record', () {
      final sgf = _game(status: GameStatus.resign, winner: Side.black).makeSgf();
      expect(sgf, startsWith('(;GM[1]FF[4]'));
      expect(sgf, contains('SZ[9]'));
      expect(sgf, contains('KM[7.5]'));
      expect(sgf, contains('PB[Steven]'));
      expect(sgf, contains('PW[Peter]'));
      expect(sgf, contains('RE[B+R]'));
      expect(sgf, contains(';B[ee];W[cc];B[gc])'));
    });

    test('writes the handicap stones and passes in the SGF record', () {
      final sgf = _game(moves: ['cc', 'pass'], handicap: 2).makeSgf();
      expect(sgf, contains('HA[2]AB[gc][cg]'));
      expect(sgf, contains(';W[cc];B[])'));
    });
  });

  group('game steps', () {
    test('survive a storage round trip', () {
      final steps = _game(moves: ['ee', 'cc', 'pass']).steps;
      final restored = stepsFromJson(stepsToJson(steps));
      expect(restored.length, steps.length);
      expect(restored.last.position.boardString, steps.last.position.boardString);
      expect(restored.last.move, const GoMove.pass());
    });

    test('carry the clock of each player', () {
      final steps = makeGameSteps(
        boardSize: 9,
        moves: const ['ee', 'cc', 'gc'],
        initialClock: const Duration(minutes: 3),
        clocks: const [
          Duration(minutes: 3, seconds: 4),
          Duration(minutes: 2, seconds: 50),
          Duration(minutes: 2, seconds: 59),
        ].lock,
      );
      expect(steps[1].archivedBlackClock, const Duration(minutes: 3, seconds: 4));
      expect(steps[1].archivedWhiteClock, const Duration(minutes: 3));
      expect(steps[2].archivedWhiteClock, const Duration(minutes: 2, seconds: 50));
      expect(steps[3].archivedBlackClock, const Duration(minutes: 2, seconds: 59));
    });
  });

  group('moveTimesFromClocks', () {
    test('each side spends zero on its first move, then adds the increment', () {
      final times = moveTimesFromClocks(
        const [
          Duration(seconds: 180),
          Duration(seconds: 180),
          Duration(seconds: 170),
          Duration(seconds: 160),
        ].lock,
        const Duration(seconds: 5),
      );
      expect(times.toList(), [
        Duration.zero,
        Duration.zero,
        const Duration(seconds: 15),
        const Duration(seconds: 25),
      ]);
    });
  });
}
