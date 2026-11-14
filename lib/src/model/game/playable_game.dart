import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/chat/chat_message.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/game/exported_game.dart';
import 'package:lichess_mobile/src/model/game/game.dart';
import 'package:lichess_mobile/src/model/game/game_status.dart';
import 'package:lichess_mobile/src/model/game/player.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/model/go/pick.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/utils/json.dart';

part 'playable_game.freezed.dart';

/// A game that can be played or watched.
///
/// The [youAre] field is null if the game is being watched as a spectator, and
/// represents the side that the current player is playing as otherwise.
///
/// Typically used for a game in progress, or a finished game that is owned by
/// the current logged in player.
///
/// See also:
/// - [ExportedGame] for a game that is finished and not owned by the current user.
@freezed
sealed class const PlayableGame._() with BaseGame, _$PlayableGame, ServerGame implements ServerGame {
  @Assert('steps.isNotEmpty')
  factory({
    required GameId id,
    required GameMeta meta,
    required GameSource source,
    required IList<GameStep> steps,
    required GameStatus status,
    Side? winner,
    required Player white,
    required Player black,
    required bool moretimeable,
    required bool takebackable,
    IList<Duration>? clocks,

    /// The side that the current player is playing as. This is null if viewing
    /// the game as a spectator.
    Side? youAre,
    bool? bookmarked,
    ServerGamePrefs? prefs,
    PlayableClockData? clock,
    CorrespondenceClockData? correspondenceClock,
    bool? boosted,

    /// The dead stones and the count, once both players passed.
    GoScoring? scoring,

    /// A point where playing is forbidden by a ko, as told by the server.
    int? koPoint,
    ({Duration idle, Duration timeToMove, DateTime movedAt})? expiration,
    ChatData? chat,

    /// The game id of the next game if a rematch has been accepted.
    GameId? rematch,
  }) = _PlayableGame;

  /// Creates a playable game from the JSON the TwoStones server sends for a game page.
  ///
  /// It is the data of the `full` event of the player game socket (`/play/:gameFullId/v6`) and of
  /// the watcher game socket (`/watch/:gameId/:side/v6`): the game, the two players as `player`
  /// and `opponent`, and the clock.
  factory fromServerJson(Map<String, dynamic> json) {
    return _playableGameFromPick(pick(json).required());
  }

  Side get sideToMove => lastPosition.turn;

  Duration? clockOf(Side side) {
    return clock != null
        ? side == Side.white
              ? clock!.white
              : clock!.black
        : null;
  }

  bool get hasAI => white.isAI || black.isAI;

  /// Whether it is the current player's turn.
  bool get isMyTurn => sideToMove == youAre;

  bool get abortable =>
      playable && moveCount < 2 && (meta.rules == null || !meta.rules!.contains(GameRule.noAbort));
  bool get resignable => playable && !abortable;
  bool get rematchable =>
      (meta.rules == null || !meta.rules!.contains(GameRule.noRematch)) &&
      (finished ||
          (aborted && (!meta.rated || !{GameSource.lobby, GameSource.pool}.contains(source)))) &&
      boosted != true;
  bool get canTakeback =>
      takebackable &&
      playable &&
      !inScoringPhase &&
      moveCount >= 2 &&
      !(me?.proposingTakeback == true) &&
      !(opponent?.proposingTakeback == true);
  bool get canGiveTime => moretimeable && playable && clock != null;

  bool get canClaimWin =>
      opponent?.isGone == true &&
      playable &&
      youAre != null &&
      !isMyTurn &&
      resignable &&
      (meta.rules == null || !meta.rules!.contains(GameRule.noClaimWin));

  /// Whether the current player accepted the count of the scoring phase.
  bool get hasAcceptedScore => youAre != null && scoring?.accepted.contains(youAre) == true;

  ExportedGame toExportedGame({required DateTime finishedAt}) {
    return ExportedGame(
      id: id,
      meta: meta,
      source: source,
      data: LightExportedGame(
        id: id,
        boardSize: meta.boardSize,
        komi: meta.komi,
        handicap: meta.handicap,
        lastMoveAt: finishedAt,
        board: lastPosition.boardString,
        lastMove: lastMove?.key(meta.boardSize),
        createdAt: meta.createdAt,
        perf: meta.perf,
        speed: meta.speed,
        rated: meta.rated,
        winner: winner,
        status: status,
        white: white,
        black: black,
        result: resultString,
        clock: meta.clock != null
            ? (initial: meta.clock!.initial, increment: meta.clock!.increment)
            : null,
        daysPerTurn: meta.daysPerTurn,
      ),
      steps: steps,
      status: status,
      winner: winner,
      white: white,
      black: black,
      youAre: youAre,
      clocks: clocks,
      scoring: scoring,
    );
  }
}

@freezed
sealed class const PlayableClockData._() with _$PlayableClockData {
  const factory({
    required bool running,
    required Duration white,
    required Duration black,

    /// The network lag of the clock.
    ///
    /// Will be sent along with move events.
    required Duration? lag,

    /// The time when the clock event was received.
    required DateTime at,
  }) = _PlayableClockData;

  Duration forSide(Side side) => side == Side.white ? white : black;
}

PlayableGame _playableGameFromPick(RequiredPick pick) {
  final game = pick('game').required();
  final go = game('go').required();
  final meta = _playableGameMetaFromPick(pick);

  final moves = go('moves').asStringOrNull() ?? '';
  var steps = makeGameSteps(
    boardSize: meta.boardSize,
    handicap: meta.handicap,
    moves: moves.split(' ').where((move) => move.isNotEmpty),
  );
  // The server is authoritative: should the local replay disagree with its board, show its board.
  final serverBoard = go('board').asStringOrNull();
  if (serverBoard != null && serverBoard != steps.last.position.boardString) {
    final turn = pick('game', 'player').asSideOrNull() ?? steps.last.position.turn;
    steps = steps.add(
      GameStep(
        position: GoPosition.fromBoardString(serverBoard, turn: turn),
        move: steps.last.move,
      ),
    );
  }

  final playerPick = pick('player').required();
  final opponentPick = pick('opponent').required();
  final playerSide = playerPick('color').asSideOrThrow();
  final isSpectator = playerPick('spectator').asBoolOrFalse();
  final player = _playerFromPick(playerPick);
  final opponent = _playerFromPick(opponentPick);

  return PlayableGame(
    id: game('id').asGameIdOrThrow(),
    meta: meta,
    source: game('source').letOrNull(
          (pick) => GameSource.nameMap[pick.asStringOrThrow()] ?? GameSource.unknown,
        ) ??
        GameSource.unknown,
    steps: steps,
    white: playerSide == Side.white ? player : opponent,
    black: playerSide == Side.black ? player : opponent,
    clock: pick('clock').letOrNull(_playableClockDataFromPick),
    correspondenceClock: pick('correspondence').letOrNull(_correspondenceClockDataFromPick),
    status: game('status').asGameStatusOrThrow(),
    winner: game('winner').asSideOrNull(),
    boosted: game('boosted').asBoolOrNull(),
    scoring: go('scoring').letOrNull(GoScoring.fromPick),
    koPoint: go('ko').asIntOrNull(),
    moretimeable: pick('moretimeable').asBoolOrFalse(),
    takebackable: pick('takebackable').asBoolOrFalse(),
    youAre: isSpectator ? null : playerSide,
    prefs: pick('pref').letOrNull(_gamePrefsFromPick),
    bookmarked: pick('bookmarked').asBoolOrNull(),
    expiration: pick('expiration').letOrNull((it) {
      final idle = it('idleMillis').asDurationFromMilliSecondsOrThrow();
      return (
        idle: idle,
        timeToMove: it('millisToMove').asDurationFromMilliSecondsOrThrow(),
        movedAt: DateTime.now().subtract(idle),
      );
    }),
    chat: pick('chat').letOrNull((p) => chatDataFromPick(p)),
    rematch: game('rematch').asGameIdOrNull(),
  );
}

GameMeta _playableGameMetaFromPick(RequiredPick pick) {
  final handicap = pick('game', 'go', 'handicap').asIntOrNull() ?? 0;
  return GameMeta(
    createdAt:
        pick('game', 'createdAt').asDateTimeFromMillisecondsOrNull() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    rated: pick('game', 'rated').asBoolOrThrow(),
    speed: pick('game', 'speed').asSpeedOrThrow(),
    perf: pick('game', 'perf').asPerfOrNull() ?? Perf.fromSpeed(pick('game', 'speed').asSpeedOrThrow()),
    boardSize: pick('game', 'go', 'size').asIntOrThrow(),
    komi: pick('game', 'go', 'komi').asDoubleOrNull() ?? defaultKomi(handicap: handicap),
    handicap: handicap,
    clock: pick('clock').letOrNull((cPick) {
      final initial = cPick('initial').asDurationFromSecondsOrThrow();
      return (
        initial: initial,
        increment: cPick('increment').asDurationFromSecondsOrThrow(),
        emergency:
            cPick('emerg').asDurationFromSecondsOrNull() ??
            const Duration(seconds: 1) *
                (initial < const Duration(minutes: 1)
                    ? (initial.inSeconds * 0.2).clamp(2, 60)
                    : (initial.inSeconds * 0.125).clamp(10, 60)),
        moreTime: cPick('moretime').asDurationFromSecondsOrNull(),
      );
    }),
    daysPerTurn: pick('correspondence').letOrNull((ccPick) => ccPick('daysPerTurn').asIntOrThrow()),
    startedAtTurn: pick('game', 'startedAtTurn').asIntOrNull(),
    rules: pick('game', 'rules').letOrNull(
      (it) =>
          ISet(it.asListOrThrow((e) => GameRule.nameMap[e.asStringOrThrow()] ?? GameRule.unknown)),
    ),
  );
}

ServerGamePrefs _gamePrefsFromPick(RequiredPick pick) {
  return ServerGamePrefs(
    // The server leaves the ratings out of the players when they are hidden.
    showRatings: pick('showRatings').asBoolOrNull() ?? true,
    confirmResign: pick('confirmResign').asBoolOrFalse(),
    submitMove: pick('submitMove').asBoolOrFalse(),
    zenMode: Zen.fromInt(pick('zen').asIntOrNull() ?? 0),
  );
}

Player _playerFromPick(RequiredPick pick) {
  return Player(
    user: pick('user').asLightUserOrNull(),
    name: pick('name').asStringOrNull(),
    rating: pick('rating').asIntOrNull(),
    provisional: pick('provisional').asBoolOrNull(),
    ratingDiff: pick('ratingDiff').asIntOrNull(),
    aiLevel: pick('ai').asIntOrNull() ?? pick('aiLevel').asIntOrNull(),
    aiEngine: pick('aiEngine').asStringOrNull(),
    onGame: pick('onGame').asBoolOrNull(),
    // `isGone` is false, true, or the number of seconds before the win can be claimed
    isGone: pick('isGone').letOrNull((it) => it.value == true),
    offeringRematch: pick('offeringRematch').asBoolOrNull(),
    proposingTakeback: pick('proposingTakeback').asBoolOrNull(),
  );
}

PlayableClockData _playableClockDataFromPick(RequiredPick pick) {
  return PlayableClockData(
    running: pick('running').asBoolOrThrow(),
    white: pick('white').asDurationFromSecondsOrThrow(),
    black: pick('black').asDurationFromSecondsOrThrow(),
    lag: pick('lag').letOrNull((it) => Duration(milliseconds: it.asIntOrThrow() * 10)),
    at: DateTime.now(),
  );
}

CorrespondenceClockData _correspondenceClockDataFromPick(RequiredPick pick) {
  return CorrespondenceClockData(
    white: pick('white').asDurationFromSecondsOrThrow(),
    black: pick('black').asDurationFromSecondsOrThrow(),
    resetId: DateTime.now().millisecondsSinceEpoch,
  );
}
