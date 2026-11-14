import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/game/game.dart';
import 'package:lichess_mobile/src/model/game/game_status.dart';
import 'package:lichess_mobile/src/model/game/player.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/model/go/pick.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/utils/json.dart';

part 'exported_game.freezed.dart';
part 'exported_game.g.dart';

typedef ClockData = ({Duration initial, Duration increment});

/// A game fetched from the game API of the server, with all its moves.
///
/// This usually represents a game that is finished and can be viewed by anyone, or accessed
/// offline.
///
/// See [PlayableGame] for a game owned by the current user and that can be played unless finished.
@Freezed(fromJson: true, toJson: true)
sealed class const ExportedGame._()
    with BaseGame, _$ExportedGame, ServerGame
    implements ServerGame {
  @Assert('steps.isNotEmpty')
  factory({
    required GameId id,
    required GameMeta meta,
    required LightExportedGame data,
    @JsonKey(fromJson: stepsFromJson, toJson: stepsToJson) required IList<GameStep> steps,
    required GameStatus status,
    @JsonKey(defaultValue: GameSource.unknown, unknownEnumValue: GameSource.unknown)
    required GameSource source,
    Side? winner,

    /// The point of view of the current player or null if spectating.
    Side? youAre,
    required Player white,
    required Player black,
    IList<Duration>? clocks,

    /// The dead stones and the count, for a game that was finished by counting.
    GoScoring? scoring,
  }) = _ExportedGame;

  /// Creates an exported game from the server's JSON.
  ///
  /// Currently, those endpoints are supported:
  /// - GET /api/mobile/game/:id
  factory fromServerJson(Map<String, dynamic> json, {bool withBookmarked = false}) {
    return _exportedGameFromPick(pick(json).required(), withBookmarked: withBookmarked);
  }

  /// Create an exported game from a local storage JSON.
  factory fromJson(Map<String, dynamic> json) => _$ExportedGameFromJson(json);
}

/// A [LightExportedGame] associated with a point of view of a player.
typedef LightExportedGameWithPov = ({LightExportedGame game, Side pov});

/// A game exported from the API, with less data than [ExportedGame]: its last position, not its
/// moves.
///
/// This is commonly used to display a list of games.
/// Server endpoints that return this data:
/// - GET /api/mobile/games/user/:userId
/// - GET /api/mobile/games/bookmarks
/// - POST /api/mobile/games/ids
@Freezed(fromJson: true, toJson: true)
sealed class const LightExportedGame._() with _$LightExportedGame {
  const factory({
    required GameId id,

    /// If the full game id is available, it means this is a game owned by the
    /// current logged in user.
    GameFullId? fullId,
    required bool rated,
    required Speed speed,
    required Perf perf,
    required DateTime createdAt,
    required DateTime lastMoveAt,
    required GameStatus status,
    required Player white,
    required Player black,

    /// Number of lines on each side of the board: 9, 13 or 19.
    required int boardSize,
    required double komi,
    @Default(0) int handicap,
    GameSource? source,

    /// The stones of the last position, as the server writes a board: one character per point.
    String? board,

    /// The last move, in SGF coordinates or `pass`.
    String? lastMove,

    /// The result as written in a game record, e.g. `B+3.5` or `W+R`.
    String? result,
    Side? winner,
    ClockData? clock,
    int? daysPerTurn,
    bool? bookmarked,
  }) = _ExportedGameData;

  factory fromServerJson(
    Map<String, dynamic> json, {

    /// Whether to ask the server if the game is bookmarked
    bool withBookmarked = false,

    /// Whether it is already known that the game is bookmarked
    bool isBookmarked = false,
  }) {
    return _lightExportedGameFromPick(
      pick(json).required(),
      withBookmarked: withBookmarked,
      isBookmarked: isBookmarked,
    );
  }

  factory fromPick(RequiredPick pick, {bool withBookmarked = false, bool isBookmarked = false}) {
    return _lightExportedGameFromPick(
      pick,
      withBookmarked: withBookmarked,
      isBookmarked: isBookmarked,
    );
  }

  factory fromJson(Map<String, dynamic> json) => _$LightExportedGameFromJson(json);

  bool get isBookmarked => bookmarked == true;

  /// The last position of the game, or an empty board when the server did not send it.
  GoPosition get lastPosition {
    final board = this.board;
    final key = lastMove;
    final move = key != null ? GoMove.fromKey(key, boardSize) : null;
    final position = board != null && board.length == boardSize * boardSize
        ? GoPosition.fromBoardString(board, turn: Side.black)
        : GoPosition.initial(boardSize, handicap: handicap);
    return GoPosition(
      size: position.size,
      board: position.board,
      turn: position.turn,
      lastMove: move,
    );
  }

  String clockDisplay(AppLocalizations l10n) {
    return daysPerTurn != null
        ? l10n.nbDays(daysPerTurn!)
        : TimeIncrement(clock?.initial.inSeconds ?? 0, clock?.increment.inSeconds ?? 0).display;
  }
}

ExportedGame _exportedGameFromPick(RequiredPick pick, {bool withBookmarked = false}) {
  final data = _lightExportedGameFromPick(pick, withBookmarked: withBookmarked);
  final clocks = pick('clocks')
      .asListOrNull<Duration>((p0) => Duration(milliseconds: p0.asIntOrThrow() * 10))
      ?.lock;
  final moves = pick('moves').asStringOrNull() ?? '';

  return ExportedGame(
    id: data.id,
    meta: GameMeta(
      createdAt: data.createdAt,
      boardSize: data.boardSize,
      komi: data.komi,
      handicap: data.handicap,
      speed: data.speed,
      perf: data.perf,
      rated: data.rated,
      clock: data.clock != null
          ? (
              initial: data.clock!.initial,
              increment: data.clock!.increment,
              emergency: null,
              moreTime: null,
            )
          : null,
      daysPerTurn: data.daysPerTurn,
    ),
    source: data.source ?? GameSource.unknown,
    data: data,
    status: data.status,
    winner: data.winner,
    white: data.white,
    black: data.black,
    steps: makeGameSteps(
      boardSize: data.boardSize,
      handicap: data.handicap,
      moves: moves.split(' ').where((move) => move.isNotEmpty),
      clocks: clocks,
      initialClock: data.clock?.initial,
    ),
    clocks: clocks,
    scoring: pick('scoring').letOrNull(GoScoring.fromPick),
  );
}

LightExportedGame _lightExportedGameFromPick(
  RequiredPick pick, {
  bool withBookmarked = false,
  bool isBookmarked = false,
}) {
  final handicap = pick('handicap').asIntOrNull() ?? 0;
  final speed = pick('speed').asSpeedOrThrow();
  return LightExportedGame(
    id: pick('id').asGameIdOrThrow(),
    fullId: pick('fullId').asGameFullIdOrNull(),
    source: pick('source')
        .letOrNull((pick) => GameSource.nameMap[pick.asStringOrThrow()] ?? GameSource.unknown),
    rated: pick('rated').asBoolOrThrow(),
    speed: speed,
    perf: pick('perf').asPerfOrNull() ?? Perf.fromSpeed(speed),
    createdAt: pick('createdAt').asDateTimeFromMillisecondsOrThrow(),
    lastMoveAt: pick('lastMoveAt').asDateTimeFromMillisecondsOrThrow(),
    status: pick('status').asGameStatusOrThrow(),
    white: pick('players', 'white').letOrThrow(_playerFromPick),
    black: pick('players', 'black').letOrThrow(_playerFromPick),
    winner: pick('winner').asSideOrNull(),
    boardSize: pick('size').asIntOrThrow(),
    komi: pick('komi').asDoubleOrNull() ?? defaultKomi(handicap: handicap),
    handicap: handicap,
    board: pick('board').asStringOrNull(),
    lastMove: pick('lastMove').asStringOrNull(),
    result: pick('result').asStringOrNull(),
    clock: pick('clock').letOrNull(_clockDataFromPick),
    daysPerTurn: pick('daysPerTurn').asIntOrNull(),
    bookmarked: isBookmarked
        ? true
        : withBookmarked
        ? pick('bookmarked').asBoolOrFalse()
        : null,
  );
}

ClockData _clockDataFromPick(RequiredPick pick) {
  return (
    initial: pick('initial').asDurationFromSecondsOrThrow(),
    increment: pick('increment').asDurationFromSecondsOrThrow(),
  );
}

Player _playerFromPick(RequiredPick pick) {
  return Player(
    user: pick('user').asLightUserOrNull(),
    name: pick('name').asStringOrNull(),
    rating: pick('rating').asIntOrNull(),
    provisional: pick('provisional').asBoolOrNull(),
    ratingDiff: pick('ratingDiff').asIntOrNull(),
    aiLevel: pick('aiLevel').asIntOrNull(),
    aiEngine: pick('aiEngine').asStringOrNull(),
  );
}
