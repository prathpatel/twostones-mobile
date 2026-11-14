import 'dart:async';

import 'package:collection/collection.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/challenge/challenge_repository.dart';
import 'package:lichess_mobile/src/model/chat/chat.dart';
import 'package:lichess_mobile/src/model/chat/chat_mixin.dart';
import 'package:lichess_mobile/src/model/clock/game_clock.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/socket.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/game/game.dart';
import 'package:lichess_mobile/src/model/game/game_preferences.dart';
import 'package:lichess_mobile/src/model/game/game_socket_events.dart';
import 'package:lichess_mobile/src/model/game/game_status.dart';
import 'package:lichess_mobile/src/model/game/game_storage.dart';
import 'package:lichess_mobile/src/model/game/playable_game.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/model/go/pick.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/network/socket.dart';
import 'package:lichess_mobile/src/service/account_service.dart';
import 'package:lichess_mobile/src/service/move_feedback.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';
import 'package:lichess_mobile/src/utils/json.dart';
import 'package:lichess_mobile/src/utils/rate_limit.dart';
import 'package:logging/logging.dart';

part 'game_controller.freezed.dart';

/// A provider for [GameController].
final gameControllerProvider = AsyncNotifierProvider.autoDispose
    .family<GameController, GameState, GameFullId>(
      GameController.new,
      name: 'GameControllerProvider',
    );

/// Returns the [PlayableGame] with the preferences of this device: whether ratings are shown, and
/// whether a stone and a resignation must be confirmed.
PlayableGame _withLocalPrefs(PlayableGame game, AccountPrefState prefs, BoardPrefs boardPrefs) {
  return game.copyWith(
    prefs: ServerGamePrefs(
      showRatings: prefs.showRatings == ShowRatings.yes,
      confirmResign: boardPrefs.confirmResign,
      submitMove: boardPrefs.confirmMove,
      zenMode: prefs.zenMode,
    ),
  );
}

/// Plays and follows a game of Go on the server, over the game socket.
///
/// The server is authoritative. A move played here is shown at once, then confirmed by the `move`
/// event of the server, whose board replaces the local one.
class GameController(final GameFullId gameFullId)
    extends AsyncNotifier<GameState>
    with ChatMixin<GameState> {
  final _logger = Logger('GameController');

  StreamSubscription<SocketEvent>? _socketSubscription;

  /// The zen preference as received from the server when the game was loaded.
  /// Used to restore the correct "on" state when toggling zen back on.
  Zen? _initialZenPref;

  /// Tracks moves that were played on the board, sent to the server, possibly
  /// acked, but without a move response from the server yet.
  /// After a delay, it will trigger a reload. This might fix bugs where the
  /// board is in a transient, dirty state, where clocks don't tick, eventually
  /// causing the player to flag.
  /// It will also help with lila-ws restarts.
  Timer? _transientMoveTimer;

  /// Callback to be called when a full reload is needed.
  VoidCallback? _onFullReload;

  final _onFlagThrottler = Throttler(const Duration(milliseconds: 500));

  /// Whether the app was put in background since the previous move was sent.
  bool _wasInBackground = false;

  static Uri socketUri(GameFullId gameFullId) => Uri(path: '/play/$gameFullId/v6');

  SocketPool get _socketPool => ref.read(socketPoolProvider);

  GameClock? _clock;

  late SocketClient _socketClient;

  @protected
  @override
  StringId get chatId => gameFullId.gameId;

  @protected
  @override
  String get chatReportResource => 'game/${gameFullId.gameId}';

  @protected
  @override
  bool get chatIsPublic => false;

  @protected
  @override
  Side? get chatPlayerSide => state.value?.game.youAre;

  @override
  Future<GameState> build() async {
    _socketClient = _openSocket();

    _onFullReload = () {
      _logger.warning('full reload triggered');
      ref.invalidateSelf();
    };

    ref.onDispose(() {
      _socketSubscription?.cancel();
      _transientMoveTimer?.cancel();
      _clock?.dispose();
      _clock = null;
      _onFlagThrottler.cancel();
      _onFullReload = null;
    });

    // The initial 'full' event is awaited through the controller's own subscription, so that
    // cancelling it on dispose always releases the socket client. A `stream.firstWhere` would add a
    // second listener that outlives the controller when the event never arrives (socket unable to
    // connect), keeping the client alive and reconnecting in the background forever.
    final fullEventCompleter = Completer<SocketEvent>();
    _socketSubscription?.cancel();
    _socketSubscription = _socketClient.stream.listen((event) {
      handleSocketEvent(event);
      if (event.topic == 'full' && !fullEventCompleter.isCompleted) {
        fullEventCompleter.complete(event);
      }
    });

    final rawFullEvent = await fullEventCompleter.future;
    final fullEvent = GameFullEvent.fromJson(rawFullEvent.data as Map<String, dynamic>);
    _socketClient.version = fullEvent.socketEventVersion;

    final game = _withLocalPrefs(
      fullEvent.game,
      await ref.read(accountPreferencesProvider.future),
      ref.read(boardPreferencesProvider),
    );

    // Play "dong" sound when this is a new game and we're playing it (not spectating)
    final isMyGame = game.youAre != null;
    if (isMyGame && game.moveCount == 0 && game.status == GameStatus.started) {
      ref.read(soundServiceProvider).play(Sound.dong);
    }

    if (game.clock != null) {
      _clock = GameClock(
        whiteTime: game.clock!.white,
        blackTime: game.clock!.black,
        emergencyThreshold: game.meta.clock?.emergency,
        onEmergency: onClockEmergency,
        onFlag: onFlag,
      );
    }

    if (game.finished) {
      _storeGame(game);
    }

    _initialZenPref = game.prefs?.zenMode;

    final initialState = GameState(
      gameFullId: gameFullId,
      game: game,
      stepCursor: game.steps.length - 1,
      liveClock: _clock != null ? (white: _clock!.whiteTime, black: _clock!.blackTime) : null,
      chatState: await initChat(game.chat),
      chatDisabledViaPrefs: ref.read(gamePreferencesProvider).enableChat == false,
    );

    final activeSide = initialState.activeClockSide;
    if (activeSide != null && game.clock?.running == true) {
      _clock?.startSide(activeSide);
    }

    return initialState;
  }

  @override
  void onForegroundLost() {
    if (_socketClient.isDisposed) {
      assert(false, 'socket client should not be disposed here');
      return;
    }
    if (!state.hasValue || !state.requireValue.game.playable) {
      return;
    }

    _wasInBackground = true;

    // real time games need the socket to stay connected otherwise the server will think the player
    // left; correspondence games can and should close the socket when the app is in background
    // (because the server won't send the push notification update when the player is still
    // connected to the socket)
    if (state.requireValue.game.meta.speed == Speed.correspondence) {
      _socketClient.close();
    }
  }

  @override
  void onFocusRegained() {
    if (_socketClient.isDisposed) {
      assert(false, 'socket client should not be disposed here');
      return;
    }

    if (!state.hasValue) {
      return;
    }

    final currentClient = ref.read(socketPoolProvider).currentClient;
    if (currentClient.route != _socketClient.route) {
      _socketClient = _openSocket();
    } else if (!_socketClient.isConnected) {
      _socketClient.connect();
    }
  }

  /// Called when the player taps a point of the board.
  ///
  /// During play it places a stone when it is the player's turn; in the scoring phase it marks or
  /// unmarks the group on that point as dead.
  void onTapPoint(int point) {
    final curState = state.value;
    if (curState == null) return;
    final game = curState.game;
    if (game.youAre == null || !game.playable) return;

    if (game.inScoringPhase) {
      if (game.lastPosition.board[point] != null) {
        _socketClient.send('scoring-toggle', point);
      }
      return;
    }

    if (curState.isReplaying) {
      cursorAt(game.steps.length - 1);
      return;
    }

    if (!game.isMyTurn) return;

    final move = GoMove.play(point);

    // tapping the stone that waits for a confirmation again takes it back
    if (curState.moveToConfirm == move) {
      cancelMove();
      return;
    }

    final error = game.lastPosition.errorOf(move);
    if (error != null) {
      state = AsyncValue.data(curState.copyWith(moveError: error));
      ref.read(soundServiceProvider).play(Sound.error);
      return;
    }

    if (curState.shouldConfirmMove) {
      state = AsyncValue.data(curState.copyWith(moveToConfirm: move, moveError: null));
      _moveFeedback(game.lastPosition.play(move));
      return;
    }

    _playMove(curState, move);
  }

  /// Passes the turn. Two passes in a row stop play and start the counting.
  void pass() {
    final curState = state.value;
    if (curState == null) return;
    final game = curState.game;
    if (game.youAre == null || !game.playable || !game.isMyTurn || game.inScoringPhase) return;
    _playMove(curState.copyWith(moveToConfirm: null), const GoMove.pass());
  }

  void _playMove(GameState curState, GoMove move) {
    final GoPosition newPosition;
    try {
      newPosition = curState.game.lastPosition.play(move);
    } on GoMoveException catch (e) {
      state = AsyncValue.data(curState.copyWith(moveToConfirm: null, moveError: e.error));
      return;
    }

    state = AsyncValue.data(
      curState.copyWith(
        game: curState.game.copyWith(
          steps: curState.game.steps.add(GameStep(position: newPosition, move: move)),
          koPoint: newPosition.koPoint,
        ),
        stepCursor: curState.game.steps.length,
        moveToConfirm: null,
        moveError: null,
      ),
    );

    _moveFeedback(newPosition);

    _sendMoveToSocket(
      move.key(curState.game.meta.boardSize),
      // same logic as web client
      // we want to send client lag only at the beginning of the game when the clock is not running yet
      withLag: curState.game.clock != null && curState.activeClockSide == null,
    );
  }

  /// Called if the player cancels the move when confirm move preference is enabled
  void cancelMove() {
    final curState = state.requireValue;
    state = AsyncValue.data(curState.copyWith(moveToConfirm: null));
  }

  /// Called if the player confirms the move when confirm move preference is enabled
  void confirmMove() {
    final curState = state.requireValue;
    final moveToConfirm = curState.moveToConfirm;
    if (moveToConfirm == null) {
      assert(false, 'moveToConfirm must not be null on confirm move');
      return;
    }
    ref.read(soundServiceProvider).play(.confirmation);
    _playMove(curState, moveToConfirm);
  }

  void cursorAt(int cursor) {
    if (state.hasValue) {
      final curState = state.requireValue;
      final clamped = cursor.clamp(0, curState.game.steps.length - 1);
      if (curState.stepCursor == clamped) {
        return;
      }
      state = AsyncValue.data(curState.copyWith(stepCursor: clamped, moveToConfirm: null));
      _replayFeedback(curState.game.positionAt(clamped));
      HapticFeedback.lightImpact();
    }
  }

  void cursorForward() {
    if (state.hasValue) {
      final curState = state.requireValue;
      if (curState.stepCursor < curState.game.steps.length - 1) {
        state = AsyncValue.data(curState.copyWith(stepCursor: curState.stepCursor + 1));
        _replayFeedback(curState.game.positionAt(curState.stepCursor + 1));
      }
    }
  }

  void cursorBackward() {
    if (state.hasValue) {
      final curState = state.requireValue;
      if (curState.moveToConfirm != null) {
        state = AsyncValue.data(curState.copyWith(moveToConfirm: null));
      } else if (curState.stepCursor > 0) {
        state = AsyncValue.data(curState.copyWith(stepCursor: curState.stepCursor - 1));
        _replayFeedback(curState.game.positionAt(curState.stepCursor - 1));
      }
    }
  }

  Future<void> toggleBookmark() async {
    if (state.hasValue) {
      final toggledBookmark = !(state.requireValue.game.bookmarked ?? false);
      await ref
          .read(accountServiceProvider)
          .setGameBookmark(gameFullId.gameId, bookmark: toggledBookmark);

      if (!ref.mounted) return;

      state = AsyncValue.data(
        state.requireValue.copyWith(
          game: state.requireValue.game.copyWith(bookmarked: toggledBookmark),
        ),
      );
    }
  }

  void toggleMoveConfirmation() {
    final curState = state.requireValue;
    state = AsyncValue.data(
      curState.copyWith(
        moveConfirmSettingOverride: !curState.shouldConfirmMove,
        moveToConfirm: null,
      ),
    );
  }

  void toggleZenMode() {
    final curState = state.requireValue;
    final curZen = curState.game.prefs?.zenMode ?? Zen.no;
    final initial = _initialZenPref;
    final newZen = curZen == Zen.no
        ? (initial != null && initial != Zen.no ? initial : Zen.gameAuto)
        : Zen.no;
    state = AsyncValue.data(
      curState.copyWith.game(prefs: curState.game.prefs?.copyWith(zenMode: newZen)),
    );
    ref.read(accountPreferencesProvider.notifier).setZen(newZen);
  }

  void onToggleChat(bool isChatEnabled) {
    state = AsyncValue.data(state.requireValue.copyWith(chatDisabledViaPrefs: !isChatEnabled));
    if (isChatEnabled) {
      // if chat is enabled, we need to resync the game data to get the chat messages
      _reloadGame();
    }
  }

  /// Play a sound when the clock is about to run out
  Future<void> onClockEmergency(Side activeSide) async {
    if (activeSide != state.value?.game.youAre) return;
    final shouldPlay = await ref.read(clockSoundProvider.future);
    if (shouldPlay) {
      ref.read(soundServiceProvider).play(Sound.lowTime);
    }
  }

  void onFlag() {
    _onFlagThrottler(() {
      if (state.hasValue) {
        _socketClient.send('flag', state.requireValue.game.sideToMove.name);
      }
    });
  }

  void moreTime() {
    _socketClient.send('moretime', null);
  }

  void abortGame() {
    _socketClient.send('abort', null);
  }

  void resignGame() {
    _socketClient.send('resign', null);
  }

  void forceResign() {
    _socketClient.send('resign-force', null);
  }

  void offerTakeback() {
    _socketClient.send('takeback-yes', null);
  }

  void acceptTakeback() {
    _socketClient.send('takeback-yes', null);
  }

  void cancelOrDeclineTakeback() {
    _socketClient.send('takeback-no', null);
  }

  void proposeOrAcceptRematch() {
    _socketClient.send('rematch-yes', null);
  }

  /// Accepts the count shown in the scoring phase. The game ends once both players accepted it.
  void acceptScore() {
    _socketClient.send('scoring-accept', null);
  }

  /// Leaves the scoring phase and goes back to playing, when the players disagree on the dead
  /// stones.
  void resumePlay() {
    _socketClient.send('scoring-resume', null);
  }

  Future<void> challengeRematch() async {
    final repository = ref.read(challengeRepositoryProvider);
    await repository.rematchOfGame(gameFullId.gameId);
    // The server doesn't return the created challenge, so fetch the outgoing
    // challenges to find it, which allows the user to cancel it later.
    final challenges = await repository.list();
    if (!ref.mounted) return;
    final challenge = challenges.outward.firstWhereOrNull((c) => c.rematchOf == gameFullId.gameId);
    final curState = state.requireValue;
    state = AsyncValue.data(curState.copyWith(correspondenceRematchId: challenge?.id));
  }

  /// Cancels the rematch challenge previously created by [challengeRematch].
  Future<void> cancelRematchChallenge() async {
    final challengeId = state.requireValue.correspondenceRematchId;
    if (challengeId == null) return;
    await ref.read(challengeRepositoryProvider).cancel(challengeId);
    if (!ref.mounted) return;
    state = AsyncValue.data(state.requireValue.copyWith(correspondenceRematchId: null));
  }

  void declineRematch() {
    _socketClient.send('rematch-no', null);
  }

  SocketClient _openSocket() {
    return _socketPool.open(
      socketUri(gameFullId),
      forceReconnect: true,
      onEventGapFailure: () {
        _onFullReload?.call();
      },
    );
  }

  /// Update the internal clock on clock server event
  void _updateClock({
    required Duration white,
    required Duration black,
    required Side? activeSide,
    Duration? lag,
  }) {
    _clock?.setTimes(whiteTime: white, blackTime: black);
    if (activeSide != null) {
      _clock?.startSide(activeSide, delay: lag);
    } else {
      _clock?.stop();
    }
  }

  void _sendMoveToSocket(String moveKey, {required bool withLag}) {
    final moveTime = _clock?.stop();

    final withBlur = _wasInBackground;
    _wasInBackground = false;
    _socketClient.send(
      'move',
      {
        'm': moveKey,
        if (moveTime != null) 's': (moveTime.inMilliseconds * 0.1).round().toRadixString(36),
        if (withBlur) 'b': 1,
      },
      ackable: true,
      withLag: _clock != null && (moveTime == null || withLag),
    );

    _transientMoveTimer?.cancel();
    _transientMoveTimer = Timer(const Duration(seconds: 10), _reloadGame);
  }

  /// Sound and vibration of a stone played in the game.
  void _moveFeedback(GoPosition position) {
    if (position.captured.isNotEmpty) {
      ref.read(moveFeedbackServiceProvider).captureFeedback();
    } else {
      ref.read(moveFeedbackServiceProvider).moveFeedback();
    }
  }

  /// Sound of a stone when going through the moves of the game.
  void _replayFeedback(GoPosition position) {
    if (position.lastMove == null) return;
    ref.read(soundServiceProvider).play(position.captured.isNotEmpty ? Sound.capture : Sound.move);
  }

  /// Reload game
  void _reloadGame() {
    _logger.info('Reloading game data');
    _socketClient.connect();
  }

  @protected
  @override
  void updateChatState(ChatState newState) {
    state = AsyncValue.data(state.requireValue.copyWith(chatState: newState));
  }

  @override
  void handleSocketEvent(SocketEvent event, [bool hasRetried = false]) {
    super.handleSocketEvent(event);
    // If we are unmounting ignore incoming socket traffic
    if (!ref.mounted) return;

    if (!state.hasValue) {
      if (event.version != null) {
        _logger.warning('received $event while game state not yet available');
      }
      return;
    }

    switch (event.topic) {
      // First message sent when the socket is reconnected
      case 'full':
        final fullEvent = GameFullEvent.fromJson(event.data as Map<String, dynamic>);
        _socketClient.version = fullEvent.socketEventVersion;

        // The resync replaces our steps with the server's authoritative ones, so
        // any optimistically-applied move is now either confirmed or gone: clear
        // the pending-move marker.
        _transientMoveTimer?.cancel();

        final curState = state.requireValue;

        final newGame = _withLocalPrefs(
          fullEvent.game,
          ref.read(accountPreferencesProvider).value ?? defaultAccountPreferences,
          ref.read(boardPreferencesProvider),
        );
        final isOpponentOnGame =
            newGame.playerOf(newGame.youAre?.opposite ?? Side.white).onGame ?? false;

        // A pending (unconfirmed) move was chosen for the previous live position. If the server
        // resync changed that position (e.g. a takeback), the move must be dropped.
        final positionChanged =
            newGame.lastPosition.boardString != curState.game.lastPosition.boardString;

        state = AsyncValue.data(
          curState.copyWith(
            game: newGame,
            // Clamp in case a takeback happened to prevent problems with cursorForward()
            stepCursor: curState.isReplaying
                ? curState.stepCursor.clamp(0, newGame.steps.length - 1)
                : newGame.steps.length - 1,
            moveToConfirm: curState.isReplaying || positionChanged ? null : curState.moveToConfirm,
            opponentLeftCountdown: isOpponentOnGame ? null : curState.opponentLeftCountdown,
          ),
        );

        if (newGame.clock != null) {
          _updateClock(
            white: newGame.clock!.white,
            black: newGame.clock!.black,
            activeSide: newGame.clock!.running ? state.requireValue.activeClockSide : null,
          );
        }

      // Server asking for a resync
      case 'resync':
        _onFullReload?.call();

      // Server asking for a reload, or in some cases the reload itself contains
      // another topic message
      case 'reload':
        if (event.data is Map<String, dynamic>) {
          final data = event.data as Map<String, dynamic>;
          if (data['t'] == null) {
            _reloadGame();
            return;
          }
          final reloadEvent = SocketEvent(topic: data['t'] as String, data: data['d']);
          handleSocketEvent(reloadEvent);
        } else {
          _reloadGame();
        }

      // Move event, received after sending a move or receiving a move from the opponent
      case 'move':
        _onMoveEvent(MoveEvent.fromJson(event.data as Map<String, dynamic>));

      // The dead stones or the acceptances of the scoring phase changed
      case 'scoring':
        final scoring = GoScoring.fromServerJson(event.data as Map<String, dynamic>);
        state = AsyncValue.data(state.requireValue.copyWith.game(scoring: scoring));

      // The clocks were set by the server, e.g. after a takeback or when play resumes
      case 'clock':
        final data = pick(event.data).required();
        final white = data('white').asDurationFromSecondsOrNull();
        final black = data('black').asDurationFromSecondsOrNull();
        final curState = state.requireValue;
        if (white != null && black != null && curState.game.clock != null) {
          final newState = curState.copyWith.game.clock!(white: white, black: black);
          state = AsyncValue.data(newState);
          _updateClock(white: white, black: black, activeSide: newState.activeClockSide);
        }

      // End game event
      case 'endData':
        _onEndEvent(GameEndEvent.fromJson(event.data as Map<String, dynamic>));

      case 'clockInc':
        final data = event.data as Map<String, dynamic>;
        final side = pick(data['color']).asSideOrNull();
        final newClock = pick(data['total'])
            .letOrNull((it) => Duration(milliseconds: it.asIntOrThrow() * 10));
        final curState = state.requireValue;

        if (side != null && newClock != null && curState.game.clock != null) {
          _clock?.setTime(side, newClock);

          // sync game clock object even if it's not used to display the clock
          final newState = side == Side.white
              ? curState.copyWith.game.clock!(white: newClock)
              : curState.copyWith.game.clock!(black: newClock);
          state = AsyncValue.data(newState);
        }

      // Crowd event, sent when a player quits or joins the game
      case 'crowd':
        final data = event.data as Map<String, dynamic>;
        final whiteOnGame = data['white'] as bool?;
        final blackOnGame = data['black'] as bool?;
        final curState = state.requireValue;
        final opponent = curState.game.youAre?.opposite;
        GameState newState = curState;
        if (whiteOnGame != null) {
          newState = newState.copyWith.game(white: newState.game.white.setOnGame(whiteOnGame));
          if (opponent == Side.white && whiteOnGame == true) {
            newState = newState.copyWith(opponentLeftCountdown: null);
          }
        }
        if (blackOnGame != null) {
          newState = newState.copyWith.game(black: newState.game.black.setOnGame(blackOnGame));
          if (opponent == Side.black && blackOnGame == true) {
            newState = newState.copyWith(opponentLeftCountdown: null);
          }
        }
        final watcherData = data['watchers'];
        if (watcherData != null && watcherData is Map<String, dynamic>) {
          final nb = watcherData['nb'] as int? ?? 0;
          final users =
              (watcherData['users'] as List<dynamic>?)?.map((e) => e.toString()).toIList() ??
              const IList.empty();
          newState = newState.copyWith(nbWatchers: nb, watcherNames: users);
        }

        state = AsyncValue.data(newState);

      // Gone event, sent when the opponent has quit the game for long enough
      // than we can claim victory
      case 'gone':
        final isGone = event.data as bool;
        GameState newState = state.requireValue;
        final youAre = newState.game.youAre;
        newState = newState.copyWith.game(
          white: youAre == Side.white ? newState.game.white : newState.game.white.setGone(isGone),
          black: youAre == Side.black ? newState.game.black : newState.game.black.setGone(isGone),
        );
        state = AsyncValue.data(newState);

      // Event sent when the opponent has quit the game, to display a countdown
      // before claiming victory is possible
      case 'goneIn':
        final timeLeft = Duration(seconds: event.data as int);
        state = AsyncValue.data(
          state.requireValue.copyWith(opponentLeftCountdown: (timeLeft, DateTime.now())),
        );

      // Event sent when a player adds or cancels a takeback offer
      case 'takebackOffers':
        final data = (event.data as Map<String, dynamic>?) ?? const <String, dynamic>{};
        final white = pick(data['white']).asBoolOrNull();
        final black = pick(data['black']).asBoolOrNull();
        final curState = state.requireValue;
        state = AsyncValue.data(
          curState.copyWith(
            game: curState.game.copyWith(
              white: curState.game.white.copyWith(proposingTakeback: white ?? false),
              black: curState.game.black.copyWith(proposingTakeback: black ?? false),
            ),
          ),
        );

      // Event sent when a player adds or cancels a rematch offer
      case 'rematchOffer':
        final side = pick(event.data).asSideOrNull();
        final curState = state.requireValue;
        state = AsyncValue.data(
          curState.copyWith(
            game: curState.game.copyWith(
              white: curState.game.white.copyWith(
                offeringRematch: side == null ? null : side == Side.white,
              ),
              black: curState.game.black.copyWith(
                offeringRematch: side == null ? null : side == Side.black,
              ),
            ),
          ),
        );

      // Event sent when a rematch is taken. Not used for now, except to prevent
      // sending another rematch offer, which should not happen
      case 'rematchTaken':
        final nextId = pick(event.data).asGameIdOrThrow();
        state = AsyncValue.data(state.requireValue.copyWith.game(rematch: nextId));

      // Event sent after a rematch is taken, to redirect to the new game
      case 'redirect':
        final data = event.data as Map<String, dynamic>;
        final fullId = pick(data['id']).asGameFullIdOrThrow();
        state = AsyncValue.data(state.requireValue.copyWith(redirectGameId: fullId));
    }
  }

  void _onMoveEvent(MoveEvent data) {
    final curState = state.requireValue;
    final game = curState.game;
    final size = game.meta.boardSize;
    // The server counts plies from 1 in an even game (so that Black plays on odd plies) and from 0
    // in a handicap game, and tells where it started.
    final serverMoveCount = data.ply - (game.meta.startedAtTurn ?? 0);

    final confirmsLocalMove =
        serverMoveCount == game.moveCount && game.lastMove?.key(size) == data.move;

    IList<GameStep> steps = game.steps;
    var stepCursor = curState.stepCursor;
    GoMove? moveToConfirm = curState.moveToConfirm;

    if (confirmsLocalMove) {
      _transientMoveTimer?.cancel();
    } else {
      final move = GoMove.fromKey(data.move, size);
      if (move == null || serverMoveCount != game.moveCount + 1) {
        // we missed something: ask the server for the whole game again
        _reloadGame();
        return;
      }
      GoPosition newPosition;
      try {
        newPosition = game.lastPosition.play(move);
      } on GoMoveException {
        _reloadGame();
        return;
      }
      // the server board is authoritative
      if (newPosition.boardString != data.board) {
        newPosition = GoPosition(
          size: newPosition.size,
          board: GoPosition.fromBoardString(data.board, turn: data.nextSide).board,
          turn: data.nextSide,
          blackPrisoners: data.blackPrisoners,
          whitePrisoners: data.whitePrisoners,
          lastMove: move,
          captured: data.captured,
          passes: newPosition.passes,
          seen: newPosition.seen,
        );
      }
      steps = steps.add(GameStep(position: newPosition, move: move));
      // the position changed: a move waiting for confirmation was chosen for the previous one
      moveToConfirm = null;
      if (!curState.isReplaying) {
        stepCursor = steps.length - 1;
        _moveFeedback(newPosition);
      }
    }

    GameState newState = curState.copyWith(
      game: game.copyWith(
        steps: steps,
        winner: data.winner ?? game.winner,
        status: data.status ?? game.status,
        koPoint: data.koPoint,
        // leaving the scoring phase clears its marks; entering it is followed by a scoring event
        scoring: data.scoring ? game.scoring : null,
      ),
      stepCursor: stepCursor,
      moveToConfirm: moveToConfirm,
      moveError: null,
    );

    if (data.clock != null) {
      final lag = newState.game.playable && newState.game.isMyTurn
          // my own clock doesn't need to be compensated for
          ? Duration.zero
          // server will send the lag only if it's more than 10ms
          // default lag of 10ms is also used by web client
          : data.clock?.lag ?? const Duration(milliseconds: 10);

      if (newState.game.clock != null) {
        // we don't rely on these values to display the clock, but let's keep
        // the game object in sync
        newState = newState.copyWith.game.clock!(
          white: data.clock!.white,
          black: data.clock!.black,
        );
      } else if (newState.game.correspondenceClock != null) {
        newState = newState.copyWith.game.correspondenceClock!(
          white: data.clock!.white,
          black: data.clock!.black,
          resetId: DateTime.now().millisecondsSinceEpoch,
        );
      }

      _updateClock(
        white: data.clock!.white,
        black: data.clock!.black,
        lag: lag,
        activeSide: newState.activeClockSide,
      );
    }

    if (newState.game.expiration != null) {
      if (newState.game.moveCount >= 2) {
        newState = newState.copyWith.game(expiration: null);
      } else {
        newState = newState.copyWith.game(
          expiration: (
            idle: newState.game.expiration!.idle,
            timeToMove: curState.game.expiration!.timeToMove,
            movedAt: DateTime.now(),
          ),
        );
      }
    }

    state = AsyncValue.data(newState);
  }

  void _onEndEvent(GameEndEvent endData) {
    // A move may have been applied optimistically to the board but never confirmed by the server
    // because the game ended first — e.g. the player flagged. The transient move timer is still
    // active in that case. Roll the unconfirmed move back so the final position matches the
    // server.
    GameState curState = state.requireValue;
    if (_transientMoveTimer?.isActive == true && curState.game.steps.length > 1) {
      final confirmedSteps = curState.game.steps.removeLast();
      curState = curState.copyWith(
        game: curState.game.copyWith(steps: confirmedSteps),
        stepCursor: curState.stepCursor.clamp(0, confirmedSteps.length - 1),
        moveToConfirm: null,
      );
    }
    _transientMoveTimer?.cancel();

    final score = endData.score;
    final scoring = curState.game.scoring;
    GameState newState = curState.copyWith(
      moveToConfirm: null,
      game: curState.game.copyWith(
        status: endData.status,
        winner: endData.winner,
        boosted: endData.boosted,
        scoring: score != null
            ? (scoring != null ? scoring.copyWith(score: score) : GoScoring(score: score))
            : scoring,
        white: curState.game.white.copyWith(ratingDiff: endData.ratingDiff?.white),
        black: curState.game.black.copyWith(ratingDiff: endData.ratingDiff?.black),
      ),
    );

    if (endData.clock != null && newState.game.clock != null) {
      newState = newState.copyWith.game.clock!(
        white: endData.clock!.white,
        black: endData.clock!.black,
        running: false,
      );
      _updateClock(white: endData.clock!.white, black: endData.clock!.black, activeSide: null);
    } else {
      _clock?.stop();
    }

    if (curState.game.moveCount >= 2) {
      Timer(const Duration(milliseconds: 500), () {
        if (!ref.mounted) return;
        ref.read(soundServiceProvider).play(Sound.dong);
      });
    }

    state = AsyncValue.data(newState);

    _storeGame(newState.game);
  }

  Future<void> _storeGame(PlayableGame game) async {
    if (!game.finished) return;
    try {
      final gameStorage = await ref.read(gameStorageProvider.future);
      final existing = await gameStorage.fetch(gameId: gameFullId.gameId);
      final finishedAt = existing?.data.lastMoveAt ?? DateTime.now();
      await gameStorage.save(game.toExportedGame(finishedAt: finishedAt));
    } catch (e, st) {
      _logger.warning('Could not store the finished game', e, st);
    }
  }
}

typedef LiveGameClock = ({ValueListenable<Duration> white, ValueListenable<Duration> black});

@freezed
sealed class const GameState._() with _$GameState, ChatMixinState {
  const factory({
    @Default(0) int nbWatchers,
    @Default(IList<String>.empty()) IList<String> watcherNames,
    required GameFullId gameFullId,
    required PlayableGame game,
    required int stepCursor,
    required LiveGameClock? liveClock,
    (Duration, DateTime)? opponentLeftCountdown,

    /// Game only setting to override the account preference
    bool? moveConfirmSettingOverride,

    /// Set if confirm move preference is enabled and player chose a point
    GoMove? moveToConfirm,

    /// Why the last point the player tapped cannot be played, until they tap elsewhere.
    GoMoveError? moveError,

    /// Game full id used to redirect to the new game of the rematch
    GameFullId? redirectGameId,

    /// Id of the rematch challenge created when the opponent is offline in a
    /// clockless game (see [GameController.challengeRematch]).
    ChallengeId? correspondenceRematchId,

    ChatState? chatState,

    required bool chatDisabledViaPrefs,
  }) = _GameState;

  /// The [GoPosition] at the current cursor, with the stone waiting for confirmation if any.
  GoPosition get currentPosition {
    final pending = moveToConfirm;
    if (pending != null && !isReplaying) {
      try {
        return game.lastPosition.play(pending);
      } on GoMoveException {
        return game.lastPosition;
      }
    }
    return game.positionAt(stepCursor);
  }

  /// The point where a ko forbids playing in the position shown, if any.
  int? get currentKoPoint {
    if (moveToConfirm != null) return null;
    return isReplaying ? game.positionAt(stepCursor).koPoint : game.koPoint;
  }

  /// Whether the zen mode is active.
  ///
  /// For finished games, only [Zen.yes] keeps zen mode active.
  /// For playable games, zen is active when account pref is [Zen.yes] or [Zen.gameAuto].
  bool get isZenModeActive => game.playable ? isZenModeEnabled : game.prefs?.zenMode == Zen.yes;

  /// Whether zen mode is enabled by account preference
  bool get isZenModeEnabled {
    final prefs = game.prefs;
    if (prefs == null) return false;
    return switch (prefs.zenMode) {
      Zen.no => false,
      Zen.yes => true,
      Zen.gameAuto => true,
    };
  }

  bool get shouldConfirmMove => moveConfirmSettingOverride ?? game.prefs?.submitMove ?? false;

  bool get isReplaying => stepCursor < game.steps.length - 1;
  bool get canGoForward => stepCursor < game.steps.length - 1;
  bool get canGoBackward => stepCursor > 0;

  /// Whether the player may pass now.
  bool get canPass => game.youAre != null && game.playable && game.isMyTurn && !game.inScoringPhase;

  bool get canGetNewOpponent =>
      !game.playable &&
      game.meta.speed != Speed.correspondence &&
      (game.source == GameSource.lobby || game.source == GameSource.pool);

  bool get canShowClaimWinCountdown =>
      !game.isMyTurn &&
      game.resignable &&
      (game.meta.rules == null || !game.meta.rules!.contains(GameRule.noClaimWin));

  bool get canOfferRematch => game.rematch == null && game.rematchable;

  /// Time left to move for the active player if an expiration is set
  Duration? get timeToMove {
    if (!game.playable || game.expiration == null) {
      return null;
    }
    final timeLeft =
        game.expiration!.movedAt.difference(DateTime.now()) + game.expiration!.timeToMove;

    if (timeLeft.isNegative) {
      return Duration.zero;
    }
    return timeLeft;
  }

  /// The side whose clock is running: none before both players made a move, during the scoring
  /// phase, or once the game is over.
  Side? get activeClockSide {
    if (game.clock == null && game.correspondenceClock == null) {
      return null;
    }
    if (game.status == GameStatus.started && game.moveCount >= 2 && !game.inScoringPhase) {
      return game.lastPosition.turn;
    }

    return null;
  }

  GameChatOptions? get chatOptions => chatDisabledViaPrefs || isZenModeActive
      ? null
      : GameChatOptions(
          id: gameFullId,
          opponent: game.youAre != null ? game.playerOf(game.youAre!.opposite).user : null,
        );

  @override
  bool get chatEnabled => chatOptions != null;
}
