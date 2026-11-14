import 'dart:convert';

import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:intl/intl.dart';
import 'package:lichess_mobile/l10n/l10n.dart' show AppLocalizations;
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/game/game_status.dart';
import 'package:lichess_mobile/src/model/game/player.dart';
import 'package:lichess_mobile/src/model/go/go.dart';

part 'game.freezed.dart';
part 'game.g.dart';

final _sgfDateFormat = DateFormat('yyyy-MM-dd');

/// Clamps negative durations to zero, so that lag compensation cannot produce a negative move
/// time.
Duration _atLeastZero(Duration duration) => duration < Duration.zero ? Duration.zero : duration;

/// The time spent on each move, in ply order, given the clock left after each one.
///
/// The time spent on a move is the clock the player had left after their previous move, plus the
/// increment, minus the clock they have left after this one. Each side's first move is reported as
/// [Duration.zero], since the clock is not running before it.
///
/// Returns an empty list when there are no clocks to derive them from (correspondence and
/// unclocked games).
IList<Duration> moveTimesFromClocks(IList<Duration>? clocks, Duration increment) {
  if (clocks == null || clocks.isEmpty) {
    return const IListConst<Duration>([]);
  }
  return IList([
    for (var i = 0; i < clocks.length; i++)
      if (i < 2) Duration.zero else _atLeastZero(clocks[i - 2] + increment - clocks[i]),
  ]);
}

/// Common interface for all games.
abstract mixin class BaseGame() {
  StringId get id;

  GameMeta get meta;

  /// Game steps, cannot be empty: the first one is the position before the first move.
  IList<GameStep> get steps;

  IList<Duration>? get clocks;

  GameStatus get status;

  /// The count of the game, once both players passed or once it is finished by counting.
  GoScoring? get scoring;

  /// The time control of the game, [TimeIncrement.infinite] if it is played without a clock.
  TimeIncrement get timeIncrement {
    final clock = meta.clock;
    return clock != null
        ? TimeIncrement.fromDurations(clock.initial, clock.increment)
        : const TimeIncrement.infinite();
  }

  /// Whether the game is properly finished (not aborted).
  bool get finished => status.value >= GameStatus.mate.value;
  bool get aborted => status == GameStatus.aborted;

  /// Whether the game is still playable (not finished or aborted).
  bool get playable => status.value < GameStatus.aborted.value && status.value != -1;

  /// This field is null if the game is being watched as a spectator, and
  /// represents the side that the current player is playing as otherwise.
  Side? get youAre;

  Side? get winner;

  Player get white;
  Player get black;

  /// Player of the playing point of view. Null if spectating.
  Player? get me => youAre == null
      ? null
      : youAre == Side.white
      ? white
      : black;

  /// Opponent from the playing point of view. Null if spectating.
  Player? get opponent => youAre == null
      ? null
      : youAre == Side.white
      ? black
      : white;

  GoPosition get initialPosition => steps.first.position;

  GoPosition get lastPosition => steps.last.position;

  GoMove? get lastMove => steps.last.move;

  /// Number of moves played, passes included.
  int get moveCount => steps.length - 1;

  /// The moves in the format of the server: SGF coordinates, or `pass`.
  IList<String> get moveKeys =>
      steps.skip(1).map((step) => step.move!.key(meta.boardSize)).toIList();

  GameStep stepAt(int cursor) => steps[cursor];

  GoPosition positionAt(int cursor) => steps[cursor].position;

  Duration? archivedClockOf(Side side, int cursor) {
    return side == Side.white ? steps[cursor].archivedWhiteClock : steps[cursor].archivedBlackClock;
  }

  /// Both players passed and the game is not over: the players agree on the dead stones.
  bool get inScoringPhase => playable && lastPosition.bothPassed;

  /// The result as written in a game record: `B+3.5`, `W+R` (resignation), `B+T` (time), `0` for
  /// a jigo, or null when the game is not finished.
  String? get resultString {
    if (!finished) return null;
    final winner = this.winner;
    if (winner == null) return status == GameStatus.draw ? '0' : null;
    final letter = winner == Side.black ? 'B' : 'W';
    return switch (status) {
      GameStatus.variantEnd => scoring?.score.result ?? '$letter+',
      GameStatus.resign => '$letter+R',
      GameStatus.outoftime || GameStatus.timeout || GameStatus.noStart => '$letter+T',
      _ => '$letter+',
    };
  }

  String shareTitle(AppLocalizations l10n) =>
      '${meta.boardSize}×${meta.boardSize} • ${l10n.resVsX(black.fullName(l10n), white.fullName(l10n))}';

  /// Returns the side of the player with the given id, or null if the player is not in the game.
  Side? playerSideOf(UserId id) {
    if (white.user?.id == id) {
      return Side.white;
    } else if (black.user?.id == id) {
      return Side.black;
    } else {
      return null;
    }
  }

  Player playerOf(Side side) {
    return side == Side.white ? white : black;
  }

  /// The time spent on each move, in ply order, derived from [clocks].
  IList<Duration> get moveTimes =>
      moveTimesFromClocks(clocks, meta.clock?.increment ?? Duration.zero);

  /// The game record in SGF, the file format every Go program reads.
  String makeSgf() {
    String escape(String text) => text.replaceAll(r'\', r'\\').replaceAll(']', r'\]');
    String name(Player player) =>
        player.user?.name ??
        player.name ??
        (player.aiLevel != null ? 'KataGo level ${player.aiLevel}' : 'Anonymous');
    final size = meta.boardSize;
    final buffer = StringBuffer('(;GM[1]FF[4]CA[UTF-8]AP[TwoStones]')
      ..write('SZ[$size]')
      ..write('KM[${meta.komi}]')
      ..write('RU[Chinese]')
      ..write('DT[${_sgfDateFormat.format(meta.createdAt)}]')
      ..write('PB[${escape(name(black))}]')
      ..write('PW[${escape(name(white))}]');
    if (black.rating != null) buffer.write('BR[${black.rating}]');
    if (white.rating != null) buffer.write('WR[${white.rating}]');
    final clock = meta.clock;
    if (clock != null) {
      buffer.write('TM[${clock.initial.inSeconds}]');
      if (clock.increment > Duration.zero) {
        buffer.write('OT[${clock.increment.inSeconds} fischer]');
      }
    }
    final result = resultString;
    if (result != null) buffer.write('RE[$result]');
    if (meta.handicap > 0) {
      buffer.write('HA[${meta.handicap}]AB');
      for (final point in goHandicapPoints(size, meta.handicap)) {
        buffer.write('[${GoMove.play(point).key(size)}]');
      }
    }
    for (final step in steps.skip(1)) {
      final move = step.move!;
      final letter = step.position.turn == Side.white ? 'B' : 'W';
      buffer.write(';$letter[${move.isPass ? '' : move.key(size)}]');
    }
    buffer.write(')');
    return buffer.toString();
  }
}

/// Common interface for playable and exported games from the server.
abstract mixin class ServerGame() implements BaseGame {
  @override
  GameId get id;
}

enum GameSource() {
  lobby,
  friend,
  ai,
  api,
  pool,
  unknown;

  static final nameMap = IMap(GameSource.values.asNameMap());
}

enum GameRule() {
  noAbort,
  noRematch,
  noClaimWin,
  unknown;

  static final nameMap = IMap(GameRule.values.asNameMap());
}

@freezed
sealed class const ServerGamePrefs._() with _$ServerGamePrefs {
  const factory({
    required bool showRatings,
    required bool confirmResign,
    required bool submitMove,
    required Zen zenMode,
  }) = _ServerGamePrefs;
}

/// The komi the server gives a game: 7.5 points, or half a point in a handicap game.
double defaultKomi({required int handicap}) => handicap > 0 ? 0.5 : 7.5;

@Freezed(fromJson: true, toJson: true)
sealed class const GameMeta._() with _$GameMeta {
  @Assert('!(clock != null && daysPerTurn != null)')
  const factory({
    required DateTime createdAt,
    required bool rated,

    /// Number of lines on each side of the board: 9, 13 or 19.
    required int boardSize,

    /// Points given to White to make up for playing second.
    required double komi,

    /// Number of stones Black starts with, 0 for an even game.
    @Default(0) int handicap,
    required Speed speed,
    required Perf perf,
    ({
      Duration initial,
      Duration increment,

      /// Remaining time threshold to switch the clock to "emergency" mode.
      Duration? emergency,

      /// Time added to the clock by the "add more time" button.
      Duration? moreTime,
    })?
    clock,
    int? daysPerTurn,
    int? startedAtTurn,
    ISet<GameRule>? rules,
  }) = _GameMeta;

  factory fromJson(Map<String, dynamic> json) => _$GameMetaFromJson(json);
}

/// The [GameMeta.clock] of a game played with [timeIncrement], null if it has no time control.
({Duration initial, Duration increment, Duration? emergency, Duration? moreTime})? clockMetaOf(
  TimeIncrement timeIncrement,
) => timeIncrement.isInfinite
    ? null
    : (
        initial: Duration(seconds: timeIncrement.time),
        increment: Duration(seconds: timeIncrement.increment),
        emergency: null,
        moreTime: null,
      );

@Freezed(fromJson: true, toJson: true)
sealed class const CorrespondenceClockData._() with _$CorrespondenceClockData {
  const factory({
    required Duration white,
    required Duration black,
    // Opaque token that the CorrespondenceClock widget uses to detect a new
    // server-authoritative reading and reset its displayed time. Excluded from
    // JSON so that serialized games always deserialize to resetId == 0.
    @JsonKey(includeFromJson: false, includeToJson: false) @Default(0) int resetId,
  }) = _CorrespondenceClockData;

  factory fromJson(Map<String, dynamic> json) => _$CorrespondenceClockDataFromJson(json);

  Duration forSide(Side side) => side == Side.white ? white : black;
}

/// The count of a game with area (Chinese) rules: stones on the board plus surrounded territory,
/// plus [komi] for White.
@Freezed(fromJson: true, toJson: true)
sealed class const GoScore._() with _$GoScore {
  const factory({
    required double black,
    required double white,
    required double komi,

    /// The result as written in a game record, `B+3.5` or `W+0.5`.
    required String result,
    required int blackTerritory,
    required int whiteTerritory,
    required int blackStones,
    required int whiteStones,

    /// The empty or dead points that count for Black.
    @Default(ISetConst<int>({})) ISet<int> blackArea,

    /// The empty or dead points that count for White.
    @Default(ISetConst<int>({})) ISet<int> whiteArea,
  }) = _GoScore;

  factory fromJson(Map<String, dynamic> json) => _$GoScoreFromJson(json);

  /// Reads the score as the server sends it.
  factory fromServerJson(Map<String, dynamic> json) => GoScore.fromPick(pick(json).required());

  factory fromPick(RequiredPick pick) {
    final ownership = pick('ownership')
        .asListOrEmpty((entry) => entry.asListOrThrow((value) => value.asIntOrThrow()));
    return GoScore(
      black: pick('black').asDoubleOrThrow(),
      white: pick('white').asDoubleOrThrow(),
      komi: pick('komi').asDoubleOrThrow(),
      result: pick('result').asStringOrThrow(),
      blackTerritory: pick('territory', 'black').asIntOrThrow(),
      whiteTerritory: pick('territory', 'white').asIntOrThrow(),
      blackStones: pick('stones', 'black').asIntOrThrow(),
      whiteStones: pick('stones', 'white').asIntOrThrow(),
      blackArea: ISet(ownership.where((pair) => pair[1] == 1).map((pair) => pair[0])),
      whiteArea: ISet(ownership.where((pair) => pair[1] != 1).map((pair) => pair[0])),
    );
  }

  /// The side each empty or dead point counts for.
  IMap<int, Side> get ownership => IMap({
    for (final point in blackArea) point: Side.black,
    for (final point in whiteArea) point: Side.white,
  });

  double pointsOf(Side side) => side == Side.black ? black : white;
}

/// The state of the counting phase: the stones marked dead, who accepted the count, and the count.
@Freezed(fromJson: true, toJson: true)
sealed class const GoScoring._() with _$GoScoring {
  const factory({
    @Default(ISetConst<int>({})) ISet<int> dead,
    @Default(ISetConst<Side>({})) ISet<Side> accepted,
    required GoScore score,
  }) = _GoScoring;

  factory fromJson(Map<String, dynamic> json) => _$GoScoringFromJson(json);

  factory fromServerJson(Map<String, dynamic> json) => GoScoring.fromPick(pick(json).required());

  factory fromPick(RequiredPick pick) => GoScoring(
    dead: ISet(pick('dead').asListOrEmpty((point) => point.asIntOrThrow())),
    accepted: ISet(
      pick('accepted').asListOrEmpty((side) => Side.fromName(side.asStringOrThrow())!),
    ),
    score: pick('score').letOrThrow(GoScore.fromPick),
  );
}

/// A position of a game, and the move that led to it.
@immutable
class const GameStep({
  required final GoPosition position,

  /// The move that led to [position], null for the first step of a game.
  final GoMove? move,

  /// The remaining white clock time at this step. Only available when the game is finished.
  final Duration? archivedWhiteClock,

  /// The remaining black clock time at this step. Only available when the game is finished.
  final Duration? archivedBlackClock,
});

/// The steps of a game played with [moves] on a board of [boardSize] lines.
///
/// [clocks] holds the time left to the player after each move, when known.
IList<GameStep> makeGameSteps({
  required int boardSize,
  int handicap = 0,
  required Iterable<String> moves,
  IList<Duration>? clocks,
  Duration? initialClock,
}) {
  final positions = replayGoGame(size: boardSize, handicap: handicap, moves: moves);
  Duration? white = initialClock;
  Duration? black = initialClock;
  final steps = <GameStep>[];
  for (final (index, position) in positions.indexed) {
    if (index > 0) {
      final clock = clocks != null && index - 1 < clocks.length ? clocks[index - 1] : null;
      if (clock != null) {
        // the side to play in this position is not the one that just moved
        if (position.turn == Side.white) {
          black = clock;
        } else {
          white = clock;
        }
      }
    }
    steps.add(
      GameStep(
        position: position,
        move: position.lastMove,
        archivedWhiteClock: clocks != null ? white : null,
        archivedBlackClock: clocks != null ? black : null,
      ),
    );
  }
  return steps.lock;
}

/// Converts a list of [GameStep]s to JSON, for local storage.
String stepsToJson(IList<GameStep> steps) {
  final first = steps.first.position;
  return jsonEncode({
    'size': first.size,
    'initial': first.boardString,
    'turn': first.turn.name,
    'moves': [for (final step in steps.skip(1)) step.move!.key(first.size)],
    'wc': [for (final step in steps) step.archivedWhiteClock?.inMilliseconds],
    'bc': [for (final step in steps) step.archivedBlackClock?.inMilliseconds],
  });
}

/// Converts the JSON written by [stepsToJson] back to a list of [GameStep]s.
IList<GameStep> stepsFromJson(String json) {
  final data = jsonDecode(json) as Map<String, dynamic>;
  final size = data['size'] as int;
  final whiteClocks = (data['wc'] as List<dynamic>?)?.cast<int?>();
  final blackClocks = (data['bc'] as List<dynamic>?)?.cast<int?>();
  Duration? clockAt(List<int?>? clocks, int index) {
    final millis = clocks != null && index < clocks.length ? clocks[index] : null;
    return millis != null ? Duration(milliseconds: millis) : null;
  }

  var position = GoPosition.fromBoardString(
    data['initial'] as String,
    turn: Side.fromName(data['turn'] as String)!,
  );
  final steps = [
    GameStep(
      position: position,
      archivedWhiteClock: clockAt(whiteClocks, 0),
      archivedBlackClock: clockAt(blackClocks, 0),
    ),
  ];
  for (final key in (data['moves'] as List<dynamic>).cast<String>()) {
    final move = GoMove.fromKey(key, size);
    if (move == null) break;
    try {
      position = position.play(move);
    } on GoMoveException {
      break;
    }
    steps.add(
      GameStep(
        position: position,
        move: move,
        archivedWhiteClock: clockAt(whiteClocks, steps.length),
        archivedBlackClock: clockAt(blackClocks, steps.length),
      ),
    );
  }
  return steps.lock;
}
