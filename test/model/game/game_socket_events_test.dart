import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/game/game_socket_events.dart';
import 'package:lichess_mobile/src/model/game/game_status.dart';
import 'package:lichess_mobile/src/model/go/go.dart';

import 'game_socket_example_data.dart';

Map<String, dynamic> _data(String event) =>
    (jsonDecode(event) as Map<String, dynamic>)['d'] as Map<String, dynamic>;

void main() {
  group('GameFullEvent', () {
    test('reads the game page of the server', () {
      final event = GameFullEvent.fromJson(
        _data(
          makeFullEvent(
            const GameId('nV3DaALy'),
            const ['ee', 'cc', 'gc'],
            whiteUserName: 'Peter',
            blackUserName: 'Steven',
            youAre: Side.white,
            socketVersion: 7,
          ),
        ),
      );
      final game = event.game;

      expect(event.socketEventVersion, 7);
      expect(game.id, const GameId('nV3DaALy'));
      expect(game.meta.boardSize, 9);
      expect(game.meta.komi, 7.5);
      expect(game.meta.handicap, 0);
      expect(game.meta.speed, Speed.blitz);
      expect(game.meta.perf, Perf.blitz);
      expect(game.status, GameStatus.started);
      expect(game.youAre, Side.white);
      expect(game.white.user?.name, 'Peter');
      expect(game.black.user?.name, 'Steven');
      expect(game.moveCount, 3);
      expect(game.lastPosition.turn, Side.white);
      expect(game.isMyTurn, isTrue);
      expect(game.lastMove, GoMove.fromKey('gc', 9));
      expect(game.clock?.white, const Duration(minutes: 3));
    });

    test('a spectator has no side', () {
      final game = GameFullEvent.fromJson(
        _data(
          makeFullEvent(
            const GameId('nV3DaALy'),
            const [],
            whiteUserName: 'Peter',
            blackUserName: 'Steven',
          ),
        ),
      ).game;
      expect(game.youAre, isNull);
    });

    test('reads a handicap game and the computer opponent', () {
      final game = GameFullEvent.fromJson(
        _data(
          makeFullEvent(
            const GameId('nV3DaALy'),
            const ['jj'],
            boardSize: 19,
            handicap: 2,
            whiteUserName: 'Peter',
            blackUserName: 'Steven',
            youAre: Side.black,
            aiOpponent: true,
          ),
        ),
      ).game;
      expect(game.meta.handicap, 2);
      expect(game.meta.komi, 0.5);
      expect(game.lastPosition.board.where((stone) => stone == Side.black).length, 2);
      expect(game.lastPosition.board.where((stone) => stone == Side.white).length, 1);
      expect(game.white.aiLevel, 3);
      expect(game.white.aiEngine, 'KataGo');
    });

    test('reads the counting phase', () {
      final game = GameFullEvent.fromJson(
        _data(
          makeFullEvent(
            const GameId('nV3DaALy'),
            const ['ee', 'cc', 'pass', 'pass'],
            whiteUserName: 'Peter',
            blackUserName: 'Steven',
            youAre: Side.black,
            scoring: '''
{"dead": [20], "accepted": ["white"], "score": {"black": 45, "white": 43.5, "komi": 7.5,
"result": "B+1.5", "territory": {"black": 36, "white": 27}, "stones": {"black": 9, "white": 9},
"ownership": [[0, 1], [8, 2]]}}''',
          ),
        ),
      ).game;
      expect(game.inScoringPhase, isTrue);
      expect(game.scoring?.dead.toSet(), {20});
      expect(game.scoring?.accepted.toSet(), {Side.white});
      expect(game.scoring?.score.result, 'B+1.5');
      expect(game.scoring?.score.ownership[0], Side.black);
      expect(game.scoring?.score.ownership[8], Side.white);
      expect(game.hasAcceptedScore, isFalse);
    });
  });

  group('MoveEvent', () {
    test('reads a move and the board after it', () {
      final event = MoveEvent.fromJson(
        _data(makeMoveEvent(ply: 2, move: 'cc', coord: 'C7', board: '.' * 81, whitePrisoners: 1)),
      );
      expect(event.ply, 2);
      expect(event.move, 'cc');
      expect(event.whitePrisoners, 1);
      expect(event.nextSide, Side.white);
      expect(event.scoring, isFalse);
    });
  });

  group('GameEndEvent', () {
    test('reads the result and the score', () {
      final event = GameEndEvent.fromJson({
        'status': {'id': 60, 'name': 'variantEnd'},
        'winner': 'black',
        'ratingDiff': {'white': -8, 'black': 8},
        'score': {
          'black': 45,
          'white': 43.5,
          'komi': 7.5,
          'result': 'B+1.5',
          'territory': {'black': 36, 'white': 27},
          'stones': {'black': 9, 'white': 9},
          'ownership': <List<int>>[],
        },
      });
      expect(event.status, GameStatus.variantEnd);
      expect(event.winner, Side.black);
      expect(event.ratingDiff, (white: -8, black: 8));
      expect(event.score?.result, 'B+1.5');
    });
  });
}
