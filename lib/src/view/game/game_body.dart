import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/account/ongoing_games_notifier.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/game/game_controller.dart';
import 'package:lichess_mobile/src/model/game/game_preferences.dart';
import 'package:lichess_mobile/src/model/game/playable_game.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/user/user_repository_providers.dart';
import 'package:lichess_mobile/src/utils/focus_detector.dart';
import 'package:lichess_mobile/src/utils/immersive_mode.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/chat/chat_screen.dart';
import 'package:lichess_mobile/src/view/game/correspondence_clock_widget.dart';
import 'package:lichess_mobile/src/view/game/game_loading_board.dart';
import 'package:lichess_mobile/src/view/game/game_player.dart';
import 'package:lichess_mobile/src/view/game/game_result_dialog.dart';
import 'package:lichess_mobile/src/view/game/game_review_screen.dart';
import 'package:lichess_mobile/src/view/game/game_settings.dart';
import 'package:lichess_mobile/src/widgets/adaptive_action_sheet.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/buttons.dart';
import 'package:lichess_mobile/src/widgets/clock.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/game_layout.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
import 'package:lichess_mobile/src/widgets/yes_no_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Delay before the game end dialog is shown after a (non-bullet) game finishes.
const kGameEndDialogDelay = Duration(milliseconds: 400);

/// Game body for the [GameScreen].
///
/// This widget is responsible for displaying the board, the clocks, the players,
/// and the bottom bar.
///
/// It also listens to the game state and shows dialogs when necessary.
///
/// Handles the immersive mode through focus detection, and the pop scope to
/// prevent the user from going back to the previous screen.
class const GameBody({
  required final GameFullId gameId,

  /// The position to show while the game loads, when the screen it is opened from knows it.
  final GoPosition? loadingPosition,

  /// [GlobalKey] for the white clock.
  ///
  /// This parameter is mandatory because the clock state needs to be preserved
  /// when the orientation changes on tablet.
  required final GlobalKey whiteClockKey,

  /// [GlobalKey] for the black clock.
  ///
  /// This parameter is mandatory because the clock state needs to be preserved
  /// when the orientation changes on tablet.
  required final GlobalKey blackClockKey,

  /// Callback to load a new game. Used when the game is finished and the user
  /// wants to play a rematch, or when switching through correspondence games.
  required final void Function(GameFullId id) onLoadGameCallback,

  /// Callback to load a new opponent.
  required final void Function(PlayableGame game) onNewOpponentCallback,

  /// [GlobalKey] for the board.
  ///
  /// Used to set gestures exclusion on android.
  required final GlobalKey boardKey,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrlProvider = gameControllerProvider(gameId);

    ref.listen(
      ctrlProvider,
      (prev, state) => _stateListener(prev, state, context: context, ref: ref),
    );

    // Only watch the coarse async phase here so a move (which changes the
    // GameState value but not the phase) does NOT rebuild the whole body.
    switch (ref.watch(ctrlProvider.select(_gamePhaseOf))) {
      case _GamePhase.error:
        final state = ref.read(ctrlProvider);
        debugPrint(
          'SEVERE: [GameBody] could not load game data; ${state.error}\n${state.stackTrace}',
        );
        return const LoadGameError('Sorry, we could not load the game. Please try again later.');
      case _GamePhase.data:
        return _PlayableGameBoard(
          gameId: gameId,
          whiteClockKey: whiteClockKey,
          blackClockKey: blackClockKey,
          boardKey: boardKey,
          onLoadGameCallback: onLoadGameCallback,
          onNewOpponentCallback: onNewOpponentCallback,
        );
      case _GamePhase.refreshing:
        final value = ref.read(ctrlProvider).requireValue;
        return StandaloneGameLoadingContent(
          loadingPosition: value.currentPosition,
          userActionsBar: _GameBottomBar(
            id: gameId,
            onLoadGameCallback: onLoadGameCallback,
            onNewOpponentCallback: onNewOpponentCallback,
          ),
        );
      case _GamePhase.loading:
        return StandaloneGameLoadingContent(
          loadingPosition: loadingPosition,
          userActionsBar: _GameBottomBar(
            id: gameId,
            onLoadGameCallback: onLoadGameCallback,
            onNewOpponentCallback: onNewOpponentCallback,
          ),
        );
    }
  }

  void _stateListener(
    AsyncValue<GameState>? prev,
    AsyncValue<GameState> state, {
    required BuildContext context,
    required WidgetRef ref,
  }) {
    if (state.hasValue) {
      if (!state.requireValue.game.playable) {
        WakelockPlus.disable();
      }
      if (prev?.value?.isZenModeActive == true && state.requireValue.isZenModeActive == false) {
        if (context.mounted) {
          // when Zen mode is disabled, reload chat data
          ref
              .read(gameControllerProvider(gameId).notifier)
              .onToggleChat(state.requireValue.chatOptions != null);
        }
      }

      final game = state.requireValue.game;

      // If the game is no longer playable, show the game end dialog.
      // We want to show it only once, whether the game is already finished on
      // first load or not.
      if ((prev?.hasValue != true || prev!.requireValue.game.playable == true) &&
          game.playable == false) {
        Timer(
          // already finished or bullet: show the dialog immediately
          (prev?.hasValue != true && game.playable == false) ||
                  (game.meta.speed == Speed.bullet || game.meta.speed == Speed.ultraBullet)
              ? Duration.zero
              : kGameEndDialogDelay,
          () {
            if (context.mounted) {
              showAdaptiveDialog<void>(
                context: context,
                builder: (_) => GameResultDialog(
                  id: gameId,
                  onNewOpponentCallback: onNewOpponentCallback,
                  onReviewCallback: () => Navigator.of(context).push(
                    GameReviewScreen.buildRoute(
                      gameId: gameId.gameId,
                      orientation: game.youAre ?? Side.black,
                    ),
                  ),
                ),
                barrierDismissible: true,
              );
            }
          },
        );
      }
    }

    if (prev?.hasValue == true && state.hasValue) {
      if (state.requireValue.redirectGameId != null) {
        // Be sure to pop any dialogs and sheets that might be on top of the game screen: the
        // dialogs are on the root navigator, the sheets on the game screen's.
        Navigator.of(context, rootNavigator: true).popUntil((route) => route is! PopupRoute);
        Navigator.of(context).popUntil((route) => route is! PopupRoute);
        onLoadGameCallback(state.requireValue.redirectGameId!);
      }
    }
  }
}

/// Coarse rendering phase for the [GameBody], derived from the controller's
/// [AsyncValue]. Used so that per-move state changes (which stay in the [data]
/// phase) do not rebuild the whole body.
enum _GamePhase() {
  loading,
  data,
  refreshing,
  error,
}

_GamePhase _gamePhaseOf(AsyncValue<GameState> state) => switch (state) {
  AsyncError() => _GamePhase.error,
  AsyncData(isRefreshing: true) => _GamePhase.refreshing,
  AsyncData() => _GamePhase.data,
  _ => _GamePhase.loading,
};

/// What the board of a game shows, taken from its [GameState].
typedef _BoardData = ({
  GoPosition position,
  int? koPoint,
  ISet<int> deadStones,
  IMap<int, Side> territory,
  bool canTap,
  IList<String> moves,
  int cursor,
  GoMoveError? moveError,
});

_BoardData? _boardDataOf(AsyncValue<GameState> state) {
  final s = state.value;
  if (s == null) return null;
  final game = s.game;
  final scoring = game.scoring;
  // The count is drawn on the last position only: earlier ones did not have these stones.
  final showCount = scoring != null && !s.isReplaying && (game.inScoringPhase || game.finished);
  return (
    position: s.currentPosition,
    koPoint: s.currentKoPoint,
    deadStones: showCount ? scoring.dead : const ISet<int>.empty(),
    territory: showCount ? scoring.score.ownership : const IMap<int, Side>.empty(),
    canTap: game.youAre != null && game.playable,
    moves: game.steps.skip(1).map((step) => step.move!.coord(game.meta.boardSize)).toIList(),
    cursor: s.stepCursor,
    moveError: s.moveError,
  );
}

String _moveErrorMessage(GoMoveError error) => switch (error) {
  GoMoveError.offBoard => 'This point is not on the board.',
  GoMoveError.occupied => 'There is already a stone on this point.',
  GoMoveError.suicide => 'A stone here would have no liberty and capture nothing.',
  GoMoveError.ko => 'Ko: this move would repeat an earlier position. Play elsewhere first.',
};

/// The board, the two players and the bottom bar of a loaded game.
class const _PlayableGameBoard({
  required final GameFullId gameId,
  required final GlobalKey whiteClockKey,
  required final GlobalKey blackClockKey,
  required final GlobalKey boardKey,
  required final void Function(GameFullId id) onLoadGameCallback,
  required final void Function(PlayableGame game) onNewOpponentCallback,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrlProvider = gameControllerProvider(gameId);
    final board = ref.watch(ctrlProvider.select(_boardDataOf));
    final shell = ref.watch(
      ctrlProvider.select((s) {
        final state = s.value;
        if (state == null) return null;
        return (
          youAre: state.game.youAre,
          zen: state.isZenModeActive,
          playable: state.game.playable,
        );
      }),
    );
    if (board == null || shell == null) return const SizedBox.shrink();

    // A Go board is not turned around: the player sits at the bottom, whatever their colour. A
    // spectator sees Black at the bottom, as in a game record.
    final bottomSide = shell.youAre ?? Side.black;
    final topSide = bottomSide.opposite;

    return FocusDetector(
      onFocusRegained: () {
        if (context.mounted) {
          ref.read(ctrlProvider.notifier).onFocusRegained();
        }
      },
      onForegroundLost: () {
        if (context.mounted) {
          ref.read(ctrlProvider.notifier).onForegroundLost();
        }
      },
      child: WakelockWidget(
        shouldEnableOnFocusGained: () => shell.playable,
        child: GameLayout(
          boardKey: boardKey,
          position: board.position,
          koPoint: board.koPoint,
          deadStones: board.deadStones,
          territory: board.territory,
          onTapPoint: board.canTap ? ref.read(ctrlProvider.notifier).onTapPoint : null,
          errorMessage: board.moveError != null ? _moveErrorMessage(board.moveError!) : null,
          topTable: _GamePlayerTable(
            gameId: gameId,
            side: topSide,
            clockKey: topSide == Side.white ? whiteClockKey : blackClockKey,
          ),
          // During the counting, the count and its buttons take the place under the board, close to
          // the stones the player taps.
          bottomTable: Column(
            mainAxisAlignment: .spaceEvenly,
            children: [
              _ScoringPanel(id: gameId),
              _GamePlayerTable(
                gameId: gameId,
                side: bottomSide,
                clockKey: bottomSide == Side.white ? whiteClockKey : blackClockKey,
                // The claim-win countdown is the user's action, so it is shown in the bottom table
                // only.
                showOpponentLeftCountdown: true,
              ),
            ],
          ),
          moves: board.moves.unlockView,
          currentMoveIndex: board.cursor,
          onSelectMove: (moveIndex) => ref.read(ctrlProvider.notifier).cursorAt(moveIndex),
          zenMode: shell.zen,
          userActionsBar: _GameBottomBar(
            id: gameId,
            onLoadGameCallback: onLoadGameCallback,
            onNewOpponentCallback: onNewOpponentCallback,
          ),
        ),
      ),
    );
  }
}

/// A self-watching player table (clock, name, captured stones) for one [side].
///
/// Lives inside the [_PlayableGameBoard] shell and rebuilds independently on the
/// state it actually needs, so it does not force the shell or board to rebuild.
class const _GamePlayerTable({
  required final GameFullId gameId,
  required final Side side,
  required final GlobalKey clockKey,

  /// Whether this table displays the claim-win countdown when the opponent has left. Only the
  /// bottom table (the user's) sets this.
  final bool showOpponentLeftCountdown = false,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrlProvider = gameControllerProvider(gameId);

    // Narrow watch: only the slice this table renders. In particular it excludes
    // spectator-count and other unrelated state churn so a spectator joining/leaving
    // does not rebuild the player tables. [liveClock]'s notifiers are stable across
    // emissions, so it doesn't trigger spurious rebuilds either.
    final data = ref.watch(
      ctrlProvider.select((s) {
        final state = s.value;
        if (state == null) return null;
        return (
          game: state.game,
          gameFullId: state.gameFullId,
          prisoners: state.currentPosition.prisoners(side),
          timeToMove: state.timeToMove,
          canGoForward: state.canGoForward,
          isZenModeActive: state.isZenModeActive,
          moveToConfirm: state.moveToConfirm,
          liveClock: state.liveClock,
          activeClockSide: state.activeClockSide,
          // Only computed for the bottom table, so the top table stays stable.
          canShowClaimWinCountdown: showOpponentLeftCountdown && state.canShowClaimWinCountdown,
          canClaimWin: showOpponentLeftCountdown && state.game.canClaimWin,
          opponentLeftCountdown: showOpponentLeftCountdown ? state.opponentLeftCountdown : null,
        );
      }),
    );
    if (data == null) return const SizedBox.shrink();

    final boardPrefs = ref.watch(boardPreferencesProvider);
    final clockTenths =
        ref.watch(clockTenthsProvider).value ?? defaultAccountPreferences.clockTenths;

    final game = data.game;
    final mePlaying = game.youAre == side;

    final matchupData = game.white.user != null && game.black.user != null
        ? ref
              .watch(
                crosstableProvider((
                  userId1: game.white.user!.id,
                  userId2: game.black.user!.id,
                  matchup: true,
                )),
              )
              .value
              ?.matchup
        : null;

    final sideUser = side == Side.white ? game.white.user : game.black.user;

    final showOpponentLeft = data.canShowClaimWinCountdown && data.opponentLeftCountdown != null;

    final scoring = game.scoring;
    final showPoints = scoring != null && (game.inScoringPhase || game.finished);

    return GamePlayer(
      game: game,
      side: side,
      socketUri: GameController.socketUri(data.gameFullId),
      matchupScore: matchupData?.users[sideUser!.id],
      prisoners: data.prisoners,
      points: showPoints ? scoring.score.pointsOf(side) : null,
      timeToMove: game.sideToMove == side ? data.timeToMove : null,
      mePlaying: mePlaying,
      canGoForward: data.canGoForward,
      zenMode: data.isZenModeActive,
      clockPosition: boardPrefs.clockPosition,
      confirmMoveCallbacks: mePlaying && data.moveToConfirm != null
          ? (
              confirm: () {
                ref.read(ctrlProvider.notifier).confirmMove();
              },
              cancel: () {
                ref.read(ctrlProvider.notifier).cancelMove();
              },
            )
          : null,
      opponentLeftCallbacks: showOpponentLeft
          ? (
              countdown: data.opponentLeftCountdown!,
              canClaim: data.canClaimWin,
              onClaimWin: () {
                ref.read(ctrlProvider.notifier).forceResign();
              },
            )
          : null,
      clock: data.liveClock != null
          ? RepaintBoundary(
              child: ValueListenableBuilder(
                key: clockKey,
                valueListenable: side == Side.white ? data.liveClock!.white : data.liveClock!.black,
                builder: (context, value, _) {
                  return Clock(
                    key: ValueKey('${side.name}-clock'),
                    timeLeft: value,
                    active: data.activeClockSide == side,
                    emergencyThreshold: game.meta.clock?.emergency,
                    clockTenths: clockTenths,
                  );
                },
              ),
            )
          : game.correspondenceClock != null && game.moveCount >= 2
          ? CorrespondenceClock(
              duration: side == Side.white
                  ? game.correspondenceClock!.white
                  : game.correspondenceClock!.black,
              active: data.activeClockSide == side,
              resetId: game.correspondenceClock!.resetId,
              onFlag: () => ref.read(ctrlProvider.notifier).onFlag(),
            )
          : null,
    );
  }
}

/// The count of the game and what to do about it, shown above the bottom bar once both players
/// passed.
///
/// The players tap groups on the board to mark them dead, then both accept the count; a player
/// who disagrees resumes play.
class const _ScoringPanel({required final GameFullId id}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(
      gameControllerProvider(id).select((s) {
        final state = s.value;
        if (state == null || !state.game.inScoringPhase) return null;
        final game = state.game;
        return (
          result: game.scoring?.score.result,
          isPlayer: game.youAre != null,
          accepted: game.hasAcceptedScore,
          opponentAccepted:
              game.youAre != null && game.scoring?.accepted.contains(game.youAre!.opposite) == true,
        );
      }),
    );
    if (data == null) return const SizedBox.shrink();

    final colorScheme = ColorScheme.of(context);
    final notifier = ref.read(gameControllerProvider(id).notifier);

    return Material(
      color: colorScheme.secondaryContainer,
      borderRadius: const BorderRadius.all(Radius.circular(8.0)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        child: Row(
          spacing: 8.0,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: data.result != null ? '${data.result}  ' : '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                      text: !data.isPlayer
                          ? 'The players are agreeing on the dead stones.'
                          : data.accepted
                          ? 'Waiting for your opponent to accept.'
                          : data.opponentAccepted
                          ? 'Your opponent accepted this count.'
                          : 'Tap a group to mark it dead or alive.',
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: colorScheme.onSecondaryContainer),
              ),
            ),
            if (data.isPlayer) ...[
              TextButton(onPressed: notifier.resumePlay, child: const Text('Resume')),
              FilledButton(
                onPressed: data.accepted ? null : notifier.acceptScore,
                child: Text(context.l10n.accept),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class const _GameBottomBar({
  required final GameFullId id,
  required final void Function(GameFullId id) onLoadGameCallback,
  required final void Function(PlayableGame game) onNewOpponentCallback,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ongoingGames = ref.watch(ongoingGamesProvider);
    final gamePrefs = ref.watch(gamePreferencesProvider);
    final boardPreferences = ref.watch(boardPreferencesProvider);
    final kidModeAsync = ref.watch(kidModeProvider);

    // Narrow watch: only the discrete flags this bar renders, so the heavy
    // menu/resign/chat buttons do not rebuild on every move (the per-move
    // prev/next state is isolated in [_MoveNavButton]).
    final data = ref.watch(
      gameControllerProvider(id).select((s) {
        final gameState = s.value;
        if (gameState == null) return null;
        final game = gameState.game;
        return (
          playable: game.playable,
          finished: game.finished,
          resignable: game.resignable,
          canPass: gameState.canPass,
          inScoringPhase: game.inScoringPhase,
          proposingTakeback: game.opponent?.proposingTakeback == true,
          isCorrespondence: game.meta.speed == Speed.correspondence,
          chatOptions: gameState.chatOptions,
          chatAvailable: gameState.chatState != null,
        );
      }),
    );

    if (data == null) return const BottomBar.empty(cupertinoGlass: true);

    final canShowChat =
        gamePrefs.enableChat == true &&
        data.chatOptions != null &&
        data.chatAvailable &&
        kidModeAsync.value == false;
    final showNextGame = data.playable && data.isCorrespondence && !data.proposingTakeback;

    return BottomBar(
      cupertinoGlass: true,
      children: [
        BottomBarButton(
          label: context.l10n.menu,
          onTap: () {
            _showGameMenu(context, ref);
          },
          icon: Icons.menu,
        ),
        BottomBarGroup(
          children: [
            if (data.playable && data.proposingTakeback)
              BottomBarButton(
                label: context.l10n.yourOpponentProposesATakeback,
                highlighted: true,
                onTap: () {
                  showAdaptiveDialog<void>(
                    context: context,
                    builder: (context) => _GameNegotiationDialog(
                      title: Text(context.l10n.yourOpponentProposesATakeback),
                      onAccept: () {
                        ref.read(gameControllerProvider(id).notifier).acceptTakeback();
                      },
                      onDecline: () {
                        ref.read(gameControllerProvider(id).notifier).cancelOrDeclineTakeback();
                      },
                    ),
                    barrierDismissible: true,
                  );
                },
                icon: CupertinoIcons.arrowshape_turn_up_left,
              )
            else if (data.finished)
              BottomBarButton(
                label: context.l10n.mobileShowResult,
                onTap: () {
                  showAdaptiveDialog<void>(
                    context: context,
                    builder: (_) => GameResultDialog(
                      id: id,
                      onNewOpponentCallback: onNewOpponentCallback,
                      onReviewCallback: () {
                        final game = ref.read(gameControllerProvider(id)).requireValue.game;
                        Navigator.of(context).push(
                          GameReviewScreen.buildRoute(
                            gameId: id.gameId,
                            orientation: game.youAre ?? Side.black,
                          ),
                        );
                      },
                    ),
                    barrierDismissible: true,
                  );
                },
                icon: Icons.info_outline,
              )
            else if (!data.inScoringPhase)
              BottomBarButton(
                label: 'Pass',
                showLabel: true,
                onTap: data.canPass
                    ? () => _showConfirmDialog(
                        context,
                        description: const Text(
                          'Pass your turn? When both players pass, the game is counted.',
                        ),
                        onConfirm: () {
                          ref.read(gameControllerProvider(id).notifier).pass();
                        },
                      )
                    : null,
                icon: Icons.redo,
              ),
            if (canShowChat) ChatBottomBarButton(options: data.chatOptions!),
            if (showNextGame)
              BottomBarButton(
                label: 'Go to the next game',
                icon: Icons.skip_next,
                onTap: ongoingGames.maybeWhen(
                  data: (games) {
                    final gamesWithMyTurn = games.where((g) => g.isMyTurn).toList();
                    if (gamesWithMyTurn.isEmpty) return null;
                    final currentIndex = gamesWithMyTurn.indexWhere((g) => g.fullId == id);
                    // If the current game is the only one where it's my turn, disable.
                    if (currentIndex != -1 && gamesWithMyTurn.length == 1) return null;
                    final nextIndex = (currentIndex + 1) % gamesWithMyTurn.length;
                    return () => onLoadGameCallback(gamesWithMyTurn[nextIndex].fullId);
                  },
                  orElse: () => null,
                ),
              )
            else if (data.playable)
              BottomBarButton(
                label: context.l10n.resign,
                onTap: data.resignable
                    ? boardPreferences.confirmResign
                          ? () => _showConfirmDialog(
                              context,
                              description: Text(context.l10n.resignTheGame),
                              onConfirm: () {
                                ref.read(gameControllerProvider(id).notifier).resignGame();
                              },
                            )
                          : () {
                              ref.read(gameControllerProvider(id).notifier).resignGame();
                            }
                    : null,
                icon: Icons.flag_outlined,
              ),
          ],
        ),
        BottomBarGroup(
          children: [
            _MoveNavButton(id: id, forward: false),
            _MoveNavButton(id: id, forward: true),
          ],
        ),
      ],
    );
  }

  Future<void> _showGameMenu(BuildContext context, WidgetRef ref) {
    final gameState = ref.read(gameControllerProvider(id)).requireValue;
    final boardPreferences = ref.read(boardPreferencesProvider);
    return showAdaptiveActionSheet(
      context: context,
      actions: [
        BottomSheetAction(
          makeLabel: (context) => Text(context.l10n.settingsSettings),
          onPressed: () => showAdaptiveBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => GameSettings(id: id),
          ),
        ),
        if (gameState.game.abortable)
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.abortGame),
            onPressed: () {
              ref.read(gameControllerProvider(id).notifier).abortGame();
            },
          ),
        if (gameState.game.meta.clock != null && gameState.game.canGiveTime)
          BottomSheetAction(
            makeLabel: (context) => Text(
              context.l10n.giveNbSeconds(gameState.game.meta.clock!.moreTime?.inSeconds ?? 15),
            ),
            onPressed: () {
              ref.read(gameControllerProvider(id).notifier).moreTime();
            },
          ),
        if (gameState.game.canTakeback)
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.takeback),
            onPressed: () {
              ref.read(gameControllerProvider(id).notifier).offerTakeback();
            },
          ),
        if (gameState.game.me?.proposingTakeback == true)
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.mobileCancelTakebackOffer),
            isDestructiveAction: true,
            onPressed: () {
              ref.read(gameControllerProvider(id).notifier).cancelOrDeclineTakeback();
            },
          ),
        if (gameState.game.resignable)
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.resign),
            onPressed: boardPreferences.confirmResign
                ? () => _showConfirmDialog(
                    context,
                    description: Text(context.l10n.resignTheGame),
                    onConfirm: () {
                      ref.read(gameControllerProvider(id).notifier).resignGame();
                    },
                  )
                : () {
                    ref.read(gameControllerProvider(id).notifier).resignGame();
                  },
          ),
        if (gameState.game.canClaimWin)
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.forceResignation),
            dismissOnPress: true,
            onPressed: () {
              ref.read(gameControllerProvider(id).notifier).forceResign();
            },
          ),
        if (gameState.game.me?.offeringRematch == true)
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.cancelRematchOffer),
            dismissOnPress: true,
            isDestructiveAction: true,
            onPressed: () {
              ref.read(gameControllerProvider(id).notifier).declineRematch();
            },
          )
        else if (gameState.correspondenceRematchId != null)
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.cancelRematchOffer),
            dismissOnPress: true,
            isDestructiveAction: true,
            onPressed: () async {
              // dismissOnPress unmounts this context before the request
              // completes, so capture the snackbar presenter now.
              final snackBar = SnackBarPresenter.of(context);
              try {
                await ref.read(gameControllerProvider(id).notifier).cancelRematchChallenge();
              } catch (_) {
                snackBar.show('Could not cancel the rematch challenge');
              }
            },
          )
        else if (gameState.canOfferRematch && gameState.game.opponent?.onGame == true)
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.rematch),
            dismissOnPress: true,
            onPressed: () {
              ref.read(gameControllerProvider(id).notifier).proposeOrAcceptRematch();
            },
          )
        // Offline opponent in a clockless game: persistent challenge, not a socket offer.
        else if (gameState.canOfferRematch &&
            gameState.game.clock == null &&
            gameState.game.me?.user != null &&
            gameState.game.opponent?.user != null)
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.rematch),
            dismissOnPress: true,
            onPressed: () async {
              // dismissOnPress unmounts this context before the request
              // completes, so capture the snackbar presenter now.
              final snackBar = SnackBarPresenter.of(context);
              try {
                await ref.read(gameControllerProvider(id).notifier).challengeRematch();
              } catch (_) {
                snackBar.show('Could not send the rematch challenge');
              }
            },
          ),
        if (gameState.canGetNewOpponent)
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.newOpponent),
            onPressed: () => onNewOpponentCallback(gameState.game),
          ),
        if (gameState.game.finished)
          BottomSheetAction(
            makeLabel: (context) => const Text('Review the game'),
            onPressed: () {
              Navigator.of(context).push(
                GameReviewScreen.buildRoute(
                  gameId: gameState.game.id,
                  orientation: gameState.game.youAre ?? Side.black,
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _showConfirmDialog(
    BuildContext context, {
    required Widget description,
    required VoidCallback onConfirm,
  }) async {
    final result = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => YesNoDialog(
        title: Text(context.l10n.mobileAreYouSure),
        content: description,
        onYes: () {
          return Navigator.of(context).pop(true);
        },
        onNo: () => Navigator.of(context).pop(false),
      ),
    );
    if (result == true) {
      onConfirm();
    }
  }
}

/// A single self-watching move-navigation button (previous or next) for the
/// game bottom bar.
///
/// Isolated from [_GameBottomBar] so that the per-move changes it depends on
/// (cursor position, blink hint) repaint only this button instead of rebuilding
/// the whole bar on every move.
class const _MoveNavButton({required final GameFullId id, required final bool forward})
    extends ConsumerWidget {
  void _move(WidgetRef ref) {
    final notifier = ref.read(gameControllerProvider(id).notifier);
    if (forward) {
      notifier.cursorForward();
    } else {
      notifier.cursorBackward();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!forward) {
      final canGoBackward = ref.watch(
        gameControllerProvider(id).select((s) => s.value?.canGoBackward ?? false),
      );
      return RepeatButton(
        onLongPress: canGoBackward ? () => _move(ref) : null,
        child: BottomBarButton(
          onTap: canGoBackward ? () => _move(ref) : null,
          label: 'Previous',
          icon: CupertinoIcons.chevron_back,
          showTooltip: false,
        ),
      );
    }

    final (canGoForward, blink) = ref.watch(
      gameControllerProvider(id).select((s) {
        final state = s.value;
        if (state == null) return (false, false);
        return (
          state.canGoForward,
          state.game.playable &&
              state.stepCursor != state.game.steps.length - 1 &&
              state.game.sideToMove == state.game.youAre,
        );
      }),
    );
    return RepeatButton(
      onLongPress: canGoForward ? () => _move(ref) : null,
      child: BottomBarButton(
        onTap: canGoForward ? () => _move(ref) : null,
        label: context.l10n.next,
        icon: CupertinoIcons.chevron_forward,
        showTooltip: false,
        blink: blink,
      ),
    );
  }
}

class const _GameNegotiationDialog({
  required final Widget title,
  required final VoidCallback onAccept,
  required final VoidCallback onDecline,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    void decline() {
      Navigator.of(context).pop();
      onDecline();
    }

    void accept() {
      Navigator.of(context).pop();
      onAccept();
    }

    return PlatformAlertDialog(
      content: title,
      actions: [
        PlatformDialogAction(onPressed: accept, child: Text(context.l10n.accept)),
        PlatformDialogAction(onPressed: decline, child: Text(context.l10n.decline)),
      ],
    );
  }
}
