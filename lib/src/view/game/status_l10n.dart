import 'package:flutter/widgets.dart';
import 'package:lichess_mobile/src/model/game/game_status.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';

/// How a game stands or ended, in the language of the app.
String gameStatusL10n(
  BuildContext context, {
  required GameStatus status,
  required GoPosition lastPosition,
  Side? winner,
}) {
  final l10n = context.l10n;
  switch (status) {
    case GameStatus.created || GameStatus.started:
      return l10n.playingRightNow;
    case GameStatus.aborted:
      return l10n.gameAborted;
    case GameStatus.resign:
      return winner == Side.black ? l10n.whiteResigned : l10n.blackResigned;
    case GameStatus.timeout:
      return winner == null
          ? lastPosition.turn == Side.white
                ? l10n.whiteLeftTheGame
                : l10n.blackLeftTheGame
          : winner == Side.black
          ? l10n.whiteLeftTheGame
          : l10n.blackLeftTheGame;
    case GameStatus.draw:
      return 'Jigo: both players have the same number of points';
    case GameStatus.outoftime:
      return winner == null
          ? lastPosition.turn == Side.white
                ? l10n.whiteRanOutOfTime
                : l10n.blackRanOutOfTime
          : winner == Side.black
          ? l10n.whiteRanOutOfTime
          : l10n.blackRanOutOfTime;
    case GameStatus.noStart:
      return winner == Side.black ? l10n.whiteDidntMove : l10n.blackDidntMove;
    case GameStatus.cheat:
      return l10n.cheatDetected;
    case GameStatus.variantEnd:
      return winner == null
          ? 'The game was counted'
          : winner == Side.black
          ? 'Black wins by counting'
          : 'White wins by counting';
    case GameStatus.mate ||
        GameStatus.stalemate ||
        GameStatus.insufficientMaterialClaim ||
        GameStatus.unknownFinish ||
        GameStatus.unknown:
      return l10n.finished;
  }
}
