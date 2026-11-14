import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/go/go.dart';

typedef FullEventTestClock = ({
  bool running,
  Duration initial,
  Duration increment,
  Duration? emerg,
  Duration white,
  Duration black,
});

typedef FullEventTestCorrespondenceClock = ({Duration white, Duration black, int daysPerTurn});

/// The `full` event the TwoStones server sends when a game socket connects: the JSON of its
/// game page (`round.JsonView.playerJson` or `watcherJson`).
///
/// [moves] are in the server format, SGF coordinates or `pass`. The board sent is the one these
/// moves lead to.
String makeFullEvent(
  GameId id,
  List<String> moves, {
  required String whiteUserName,
  required String blackUserName,
  int boardSize = 9,
  int handicap = 0,
  int socketVersion = 0,

  /// The side of the player, null for a spectator.
  Side? youAre,
  int statusId = 20,
  String statusName = 'started',
  Side? winner,
  bool aiOpponent = false,
  String? scoring,
  FullEventTestClock? clock = const (
    running: false,
    initial: Duration(minutes: 3),
    increment: Duration(seconds: 2),
    emerg: Duration(seconds: 30),
    white: Duration(minutes: 3),
    black: Duration(minutes: 3),
  ),
  FullEventTestCorrespondenceClock? correspondenceClock,

  /// Whether the opponent of [youAre] is connected to the game.
  bool opponentOnGame = true,
}) {
  final positions = replayGoGame(size: boardSize, handicap: handicap, moves: moves);
  final last = positions.last;
  final speed = clock != null
      ? Speed.fromTimeIncrement(TimeIncrement.fromDurations(clock.initial, clock.increment)).name
      : 'correspondence';
  // the server counts plies from 1 in an even game
  final startedAtTurn = handicap > 0 ? 0 : 1;
  final turns = startedAtTurn + moves.length;
  final pov = youAre ?? Side.black;

  String playerJson(Side side) {
    final name = side == Side.white ? whiteUserName : blackUserName;
    final isAi = aiOpponent && side != pov;
    return '''
      "color": "${side.name}",
      ${isAi ? '"ai": 3, "aiEngine": "KataGo",' : '"user": {"name": "$name", "id": "${name.toLowerCase()}"}, "rating": 1500,'}
      "prisoners": ${last.prisoners(side)},
      "onGame": ${side == pov || opponentOnGame}
''';
  }

  final clockStr = clock != null
      ? '''
    "clock": {
      "running": ${clock.running},
      "initial": ${clock.initial.inSeconds},
      "increment": ${clock.increment.inSeconds},
      "white": ${(clock.white.inMilliseconds / 1000).toStringAsFixed(2)},
      "black": ${(clock.black.inMilliseconds / 1000).toStringAsFixed(2)},
      "emerg": ${clock.emerg?.inSeconds ?? 30},
      "moretime": 15
    },
'''
      : '';

  final correspondenceClockStr = correspondenceClock != null
      ? '''
    "correspondence": {
      "daysPerTurn": ${correspondenceClock.daysPerTurn},
      "white": ${(correspondenceClock.white.inMilliseconds / 1000).toStringAsFixed(2)},
      "black": ${(correspondenceClock.black.inMilliseconds / 1000).toStringAsFixed(2)}
    },
'''
      : '';

  return '''
{
  "t": "full",
  "d": {
    "game": {
      "id": "$id",
      "speed": "$speed",
      "perf": "$speed",
      "rated": false,
      "source": "lobby",
      "createdAt": 1685698678928,
      ${startedAtTurn > 0 ? '"startedAtTurn": $startedAtTurn,' : ''}
      "go": {
        "size": $boardSize,
        "komi": ${handicap > 0 ? 0.5 : 7.5},
        "board": "${last.boardString}",
        "moves": "${moves.join(' ')}",
        "prisoners": {"black": ${last.prisoners(Side.black)}, "white": ${last.prisoners(Side.white)}}
        ${handicap > 0 ? ', "handicap": $handicap' : ''}
        ${moves.isNotEmpty ? ', "lastMove": "${moves.last}"' : ''}
        ${scoring != null ? ', "scoring": $scoring' : ''}
      },
      "turns": $turns,
      "status": {"id": $statusId, "name": "$statusName"},
      ${winner != null ? '"winner": "${winner.name}",' : ''}
      "player": "${last.turn.name}"
    },
    "player": {
      ${playerJson(pov)},
      ${youAre == null ? '"spectator": true,' : '"id": "abcd",'}
      "version": $socketVersion
    },
    "opponent": {
      ${playerJson(pov.opposite)}
    },
    $clockStr
    $correspondenceClockStr
    "pref": {"coords": 1, "replay": 2, "clockTenths": 1, "confirmResign": true, "submitMove": false},
    "takebackable": true,
    "moretimeable": true,
    "chat": {
      "lines": [
        {"u": "Zidrox", "t": "Good luck", "f": "people.man-singer"}
      ]
    }
  }
}
''';
}

/// A `move` event of the server, for the move [move] that was played as ply [ply], leading to
/// [board].
String makeMoveEvent({
  required int ply,

  /// The version of the socket event: one more than that of the event before.
  int version = 1,
  required String move,
  required String coord,
  required String board,
  int blackPrisoners = 0,
  int whitePrisoners = 0,
  bool scoring = false,
  ({Duration white, Duration black})? clock,
}) =>
    '''
{
  "t": "move",
  "v": $version,
  "d": {
    "move": "$move",
    "coord": "$coord",
    "board": "$board",
    "ply": $ply,
    "prisoners": {"black": $blackPrisoners, "white": $whitePrisoners}
    ${scoring ? ', "scoring": true' : ''}
    ${clock != null ? ', "clock": {"white": ${clock.white.inMilliseconds / 1000}, "black": ${clock.black.inMilliseconds / 1000}}' : ''}
  }
}
''';
