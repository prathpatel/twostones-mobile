import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/game/game.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/network/socket.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/lichess_assets.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:lichess_mobile/src/view/account/rating_pref_aware.dart';
import 'package:lichess_mobile/src/view/user/user_or_profile_screen.dart';
import 'package:lichess_mobile/src/widgets/buttons.dart';
import 'package:lichess_mobile/src/widgets/clock.dart';
import 'package:lichess_mobile/src/widgets/network_image.dart';
import 'package:lichess_mobile/src/widgets/user.dart';
import 'package:material_ui/material_ui.dart';

/// A widget to display player information above/below the board: the colour of the player's
/// stones, their name and rating, and the stones they captured.
class const GamePlayer({
  required final BaseGame game,
  required final Side side,
  final Uri? socketUri,
  final double? matchupScore,
  final Widget? clock,

  /// Number of stones this player captured.
  final int? prisoners,

  /// The points of this player in the count, shown once the game is being counted or is over.
  final double? points,

  /// if confirm move preference is enabled, used to display confirmation buttons
  final ({VoidCallback confirm, VoidCallback cancel})? confirmMoveCallbacks,

  /// When the opponent has left the game, used to display the claim-win countdown
  /// and, once the opponent has been gone long enough, the claim choices.
  final ({
    (Duration, DateTime) countdown,
    bool canClaim,
    VoidCallback onClaimWin,
  })?
  opponentLeftCallbacks,

  /// Time left for the player to move at the start of the game.
  final Duration? timeToMove,
  final bool shouldLinkToUserProfile = true,
  final bool mePlaying = false,
  final bool canGoForward = false,
  final bool zenMode = false,
  final ClockPosition clockPosition = ClockPosition.right,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final playerFontSize = isShortVerticalScreen(context) ? 15.0 : 16.0;

    final player = game.playerOf(side);

    final playerWidget = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!zenMode)
          Row(
            mainAxisAlignment: clockPosition == ClockPosition.right
                ? MainAxisAlignment.start
                : MainAxisAlignment.end,
            children: [
              if (matchupScore != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: ColorScheme.of(context).primaryContainer,
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Text(
                    _scoreDisplay(matchupScore!),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: ColorScheme.of(context).onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
              ],
              _StoneIcon(side: side, size: playerFontSize),
              const SizedBox(width: 6),
              if (player.user != null) ...[
                Consumer(
                  builder: (context, ref, _) {
                    bool isPlayerConnected = player.onGame == true;
                    if (mePlaying && socketUri != null) {
                      final ping = ref.watch(socketPingProvider(socketUri));
                      if (ping.rating == 0) {
                        isPlayerConnected = false;
                      }
                    }
                    return ConnectedIcon(
                      isConnected: isPlayerConnected,
                      shouldShowIsOnGameLabels: true,
                      size: DefaultTextStyle.of(context).style.fontSize,
                    );
                  },
                ),
              ],
              const SizedBox(width: 5),
              if (player.user?.isPatron == true) ...[
                PatronIcon(size: playerFontSize, color: player.user?.patronColor),
                const SizedBox(width: 5),
              ],
              if (player.user?.title != null) ...[
                Text(
                  player.user!.title!,
                  style: TextStyle(
                    fontSize: playerFontSize,
                    fontWeight: player.user?.title == 'BOT' ? null : FontWeight.bold,
                    color: player.user?.title == 'BOT'
                        ? context.lichessColors.fancy
                        : context.lichessColors.brag,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Tooltip(
                  message: player.displayName(context.l10n),
                  child: Text(
                    player.displayName(context.l10n),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: playerFontSize, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              if (player.user?.flair != null) ...[
                const SizedBox(width: 5),
                HttpNetworkImageWidget(
                  lichessFlairSrc(player.user!.flair!),
                  errorBuilder: (_, _, _) => kEmptyWidget,
                  width: 16,
                  height: 16,
                ),
              ],
              if (player.rating != null)
                RatingPrefAware(
                  isActiveGameOfCurrentUser: game.me != null && !game.finished && !game.aborted,
                  child: Text.rich(
                    TextSpan(
                      text: ' ${player.rating}${player.provisional == true ? '?' : ''}',
                      children: [
                        if (player.ratingDiff != null)
                          TextSpan(
                            text: ' ${player.ratingDiff! > 0 ? '+' : ''}${player.ratingDiff}',
                            style: TextStyle(
                              color: player.ratingDiff! > 0
                                  ? context.lichessColors.green
                                  : player.ratingDiff! == 0
                                  ? textShade(context, Styles.subtitleOpacity)
                                  : context.lichessColors.red,
                            ),
                          ),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: textShade(context, 0.7)),
                  ),
                ),
            ],
          ),
        if (timeToMove != null)
          MoveExpiration(timeToMove: timeToMove!, mePlaying: mePlaying)
        else
          Text(
            [
              if (points != null) '${_formatPoints(points!)} points',
              if (prisoners != null) '$prisoners captured',
            ].join(' • '),
            style: TextStyle(fontSize: 13, color: textShade(context, 0.7)),
          ),
      ],
    );

    // When the opponent has left, the countdown / claim choices take the whole
    // table width (the clock is hidden) to leave enough room for the buttons.
    if (opponentLeftCallbacks != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: OpponentLeftCountdown(
          countdown: opponentLeftCallbacks!.countdown,
          canClaim: opponentLeftCallbacks!.canClaim,
          onClaimWin: opponentLeftCallbacks!.onClaimWin,
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (clock != null && clockPosition == ClockPosition.left) Flexible(flex: 3, child: clock!),
        if (mePlaying && confirmMoveCallbacks != null && canGoForward == false)
          Expanded(
            flex: 7,
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: ConfirmMove(
                onConfirm: confirmMoveCallbacks!.confirm,
                onCancel: confirmMoveCallbacks!.cancel,
              ),
            ),
          )
        else
          Expanded(
            flex: 7,
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: shouldLinkToUserProfile
                  ? GestureDetector(
                      onTap: player.user != null
                          ? () =>
                                Navigator.of(context)
                                    .push(UserOrProfileScreen.buildRoute(player.user!))
                          : null,
                      child: playerWidget,
                    )
                  : playerWidget,
            ),
          ),
        if (clock != null && clockPosition == ClockPosition.right) Flexible(flex: 3, child: clock!),
      ],
    );
  }
}

String _formatPoints(double points) =>
    points == points.roundToDouble() ? points.toStringAsFixed(0) : points.toStringAsFixed(1);

/// A small stone of the colour the player plays.
class const _StoneIcon({required final Side side, required final double size})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: side == Side.black ? context.l10n.black : context.l10n.white,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: .circle,
          color: side == Side.black ? const Color(0xFF1B1B1B) : const Color(0xFFF2F2F2),
          border: Border.all(color: textShade(context, 0.5) ?? const Color(0xFF808080), width: 0.8),
        ),
      ),
    );
  }
}

class const ConfirmMove({
  required final VoidCallback onConfirm,
  required final VoidCallback onCancel,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SemanticIconButton(
          icon: const Icon(CupertinoIcons.xmark_rectangle_fill),
          color: context.lichessColors.red,
          iconSize: 35,
          semanticsLabel: context.l10n.cancel,
          padding: const EdgeInsets.all(10),
          onPressed: onCancel,
        ),
        Flexible(
          child: Text(
            context.l10n.confirmMove,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            textAlign: TextAlign.center,
          ),
        ),
        SemanticIconButton(
          icon: const Icon(CupertinoIcons.checkmark_rectangle_fill),
          color: context.lichessColors.green,
          iconSize: 35,
          semanticsLabel: context.l10n.accept,
          padding: const EdgeInsets.all(10),
          onPressed: onConfirm,
        ),
      ],
    );
  }
}

/// Shown in the player table when the opponent has left the game.
///
/// While the claim threshold has not been reached, displays a live countdown.
/// Once [canClaim] is true, displays the two claim choices inline (so there is
/// no dialog to dismiss). The player clock is hidden to leave enough room.
class const OpponentLeftCountdown({
  required final (Duration, DateTime) countdown,
  required final bool canClaim,
  required final VoidCallback onClaimWin,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (!canClaim) {
      return CountdownClockBuilder(
        timeLeft: countdown.$1,
        clockUpdatedAt: countdown.$2,
        active: true,
        builder: (context, duration) => Text(
          context.l10n.opponentLeftCounter(duration.inSeconds),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    return Column(
      mainAxisSize: .max,
      mainAxisAlignment: .center,
      children: [
        // The buttons are the priority: they keep their full size and stay
        // visible even when vertical space is constrained.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Flexible(
              child: OpacityButton(
                semanticsLabel: context.l10n.forceResignation,
                onPressed: onClaimWin,
                child: Text(
                  context.l10n.forceResignation,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ColorScheme.of(context).secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _scoreDisplay(double score) {
  final integerPart = score.truncate();
  final decimalPart = score - integerPart;

  return integerPart == 0 && decimalPart == 0.5
      ? '½'
      : '$integerPart${decimalPart == 0.5 ? '½' : ''}';
}

class const MoveExpiration({
  required final Duration timeToMove,
  required final bool mePlaying,
  super.key,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<MoveExpiration> createState() => _MoveExpirationState();
}

class _MoveExpirationState() extends ConsumerState<MoveExpiration> {
  static const _period = Duration(milliseconds: 1000);
  Timer? _timer;
  Duration timeLeft = Duration.zero;
  bool playedEmergencySound = false;

  Timer startTimer() {
    return Timer.periodic(_period, (timer) {
      setState(() {
        timeLeft = timeLeft - _period;
        if (timeLeft <= Duration.zero) {
          timer.cancel();
        }
      });
    });
  }

  @override
  void initState() {
    super.initState();
    timeLeft = widget.timeToMove;
    _timer = startTimer();
  }

  @override
  void didUpdateWidget(covariant MoveExpiration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeToMove != widget.timeToMove) {
      _timer?.cancel();
      timeLeft = widget.timeToMove;
      _timer = startTimer();
    }
  }

  @override
  void dispose() {
    super.dispose();
    _timer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final secs = timeLeft.inSeconds.remainder(60);
    final emerg = timeLeft <= const Duration(seconds: 8);

    if (emerg && widget.mePlaying && !playedEmergencySound) {
      ref.read(soundServiceProvider).play(Sound.lowTime);
      setState(() {
        playedEmergencySound = true;
      });
    }

    return secs <= 20
        ? Text(
            context.l10n.nbSecondsToPlayTheFirstMove(secs),
            style: TextStyle(color: widget.mePlaying && emerg ? context.lichessColors.red : null),
          )
        : const Text('');
  }
}
