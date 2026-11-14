import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/model/go/pick.dart';
import 'package:lichess_mobile/src/model/user/user.dart';

part 'ongoing_game.freezed.dart';

@freezed
sealed class const OngoingGame._() with _$OngoingGame {
  factory({
    required GameId id,
    required GameFullId fullId,
    required Side orientation,

    /// Number of lines on each side of the board.
    required int boardSize,

    /// The stones on the board, as the server writes a board: one character per point.
    required String board,
    required Perf perf,
    required Speed speed,
    LightUser? opponent,
    required bool isMyTurn,
    int? opponentRating,
    int? opponentAiLevel,

    /// The last move in SGF coordinates, or `pass`.
    String? lastMove,
    int? secondsLeft,
  }) = _OngoingGame;

  bool get isRealTime => speed != Speed.correspondence;

  /// The position to show in a preview of the game.
  GoPosition get position {
    final key = lastMove;
    final stones = board.length == boardSize * boardSize
        ? GoPosition.fromBoardString(board, turn: Side.black).board
        : GoPosition.initial(boardSize).board;
    return GoPosition(
      size: boardSize,
      board: stones,
      turn: isMyTurn ? orientation : orientation.opposite,
      lastMove: key != null ? GoMove.fromKey(key, boardSize) : null,
    );
  }

  factory fromServerJson(Map<String, dynamic> json) {
    return _ongoingGameFromPick(pick(json).required());
  }
}

IList<OngoingGame> ongoingGamesFromServerJson(Map<String, dynamic> json) {
  final list = json['nowPlaying'];
  if (list is! List<dynamic>) {
    throw Exception('Could not read json object as {nowPlaying: []}');
  }
  return list.map((e) => OngoingGame.fromServerJson(e as Map<String, dynamic>)).toIList();
}

OngoingGame _ongoingGameFromPick(RequiredPick pick) {
  return OngoingGame(
    id: GameId(pick('gameId').asStringOrThrow()),
    fullId: GameFullId(pick('fullId').asStringOrThrow()),
    orientation: pick('color').asSideOrThrow(),
    boardSize: pick('size').asIntOrThrow(),
    board: pick('board').asStringOrThrow(),
    lastMove: pick('lastMove').asStringOrNull(),
    perf: pick('perf').asPerfOrThrow(),
    speed: pick('speed').asSpeedOrThrow(),
    opponent: pick('opponent').asLightUserOrNull(),
    opponentRating: pick('opponent', 'rating').asIntOrNull(),
    opponentAiLevel: pick('opponent', 'ai').asIntOrNull() ?? pick('opponent', 'aiLevel').asIntOrNull(),
    secondsLeft: pick('secondsLeft').asIntOrNull(),
    isMyTurn: pick('isMyTurn').asBoolOrThrow(),
  );
}
