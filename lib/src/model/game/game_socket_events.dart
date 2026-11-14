import 'package:clock/clock.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/game/game.dart';
import 'package:lichess_mobile/src/model/game/game_status.dart';
import 'package:lichess_mobile/src/model/game/playable_game.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/model/go/pick.dart';
import 'package:lichess_mobile/src/utils/json.dart';

part 'game_socket_events.freezed.dart';

/// The whole game, sent by the server when the game socket connects.
@freezed
sealed class GameFullEvent with _$GameFullEvent {
  const factory({required PlayableGame game, required int socketEventVersion}) = _GameFullEvent;

  factory fromJson(Map<String, dynamic> json) {
    return GameFullEvent(
      game: PlayableGame.fromServerJson(json),
      // The version of the game events is given with the player, as on the website.
      socketEventVersion:
          pick(json, 'socket').asIntOrNull() ?? pick(json, 'player', 'version').asIntOrNull() ?? 0,
    );
  }
}

/// A stone was played, or a player passed.
@freezed
sealed class const MoveEvent._() with _$MoveEvent {
  const factory({
    /// The number of moves played once this one is: an even ply means White plays next.
    required int ply,

    /// The move in SGF coordinates (`pd`), or `pass`.
    required String move,

    /// The stones after the move, as the server writes a board.
    required String board,
    required int blackPrisoners,
    required int whitePrisoners,
    @Default(IListConst<int>([])) IList<int> captured,
    int? koPoint,

    /// Whether both players passed, which starts the counting.
    @Default(false) bool scoring,
    GameStatus? status,
    Side? winner,
    ({Duration white, Duration black, Duration? lag, DateTime at})? clock,
  }) = _MoveEvent;

  factory fromJson(Map<String, dynamic> json) => _socketMoveEventFromPick(pick(json).required());

  /// The side that plays after this move.
  Side get nextSide => ply.isEven ? Side.white : Side.black;
}

MoveEvent _socketMoveEventFromPick(RequiredPick pick) {
  return MoveEvent(
    ply: pick('ply').asIntOrThrow(),
    move: pick('move').asStringOrThrow(),
    board: pick('board').asStringOrThrow(),
    blackPrisoners: pick('prisoners', 'black').asIntOrNull() ?? 0,
    whitePrisoners: pick('prisoners', 'white').asIntOrNull() ?? 0,
    captured: IList(pick('captured').asListOrEmpty((point) => point.asIntOrThrow())),
    koPoint: pick('ko').asIntOrNull(),
    scoring: pick('scoring').asBoolOrFalse(),
    status: pick('status').asGameStatusOrNull(),
    winner: pick('winner').asSideOrNull(),
    clock: pick('clock').letOrNull(
      (it) => (
        at: clock.now(),
        white: it('white').asDurationFromSecondsOrThrow(),
        black: it('black').asDurationFromSecondsOrThrow(),
        lag: it('lag').letOrNull((it) => Duration(milliseconds: it.asIntOrThrow() * 10)),
      ),
    ),
  );
}

@freezed
sealed class const GameEndEvent._() with _$GameEndEvent {
  const factory({
    required GameStatus status,
    Side? winner,
    ({int white, int black})? ratingDiff,
    bool? boosted,
    ({Duration white, Duration black})? clock,

    /// The count, when the game was finished by counting.
    GoScore? score,
  }) = _GameEndEvent;

  factory fromJson(Map<String, dynamic> json) => _gameEndEventFromPick(pick(json).required());
}

GameEndEvent _gameEndEventFromPick(RequiredPick pick) {
  return GameEndEvent(
    status: pick('status').asGameStatusOrThrow(),
    winner: pick('winner').asSideOrNull(),
    ratingDiff: pick('ratingDiff')
        .letOrNull((it) => (white: it('white').asIntOrThrow(), black: it('black').asIntOrThrow())),
    boosted: pick('boosted').asBoolOrNull(),
    clock: pick('clock').letOrNull(
      (it) => (
        white: Duration(milliseconds: it('wc').asIntOrThrow() * 10),
        black: Duration(milliseconds: it('bc').asIntOrThrow() * 10),
      ),
    ),
    score: pick('score').letOrNull(GoScore.fromPick),
  );
}
