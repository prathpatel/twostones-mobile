import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/challenge/challenge.dart';
import 'package:lichess_mobile/src/model/challenge/challenge_repository.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/model/lobby/game_seek.dart';
import 'package:lichess_mobile/src/model/lobby/lobby_numbers.dart';
import 'package:lichess_mobile/src/model/settings/brightness.dart';
import 'package:lichess_mobile/src/styles/icon_extensions.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/utils/share.dart';
import 'package:lichess_mobile/src/utils/string.dart';
import 'package:lichess_mobile/src/view/account/rating_pref_aware.dart';
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:lichess_mobile/src/view/user/pick_player_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/game_layout.dart';
import 'package:lichess_mobile/src/widgets/shimmer.dart';
import 'package:lichess_mobile/src/widgets/user.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

class const LobbyScreenLoadingContent(
  final GameSeek seek,
  final Future<void> Function() cancelGameCreation,
) extends StatefulWidget {
  @override
  State<LobbyScreenLoadingContent> createState() => _LobbyScreenLoadingContentState();
}

class _LobbyScreenLoadingContentState() extends State<LobbyScreenLoadingContent> {
  Future<void>? _cancelGameCreationFuture;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GameLayout(
        position: GoPosition.initial(widget.seek.boardSize),
        moves: const [],
        boardOverlay: _BoardOverlayCard(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.mobileWaitingForOpponentToJoin),
              const SizedBox(height: 26.0),
              _GameParamsDisplay.seek(widget.seek),
              //Do not show rating range if the default values (-500, +500) are used
              if (widget.seek.ratingRange != null &&
                  !(widget.seek.ratingRange!.$1 + 1000 == widget.seek.ratingRange!.$2)) ...[
                const SizedBox(height: 8.0),
                RatingPrefAware(
                  child: Text(
                    '${widget.seek.ratingRange!.$1}-${widget.seek.ratingRange!.$2}',
                    style: TextTheme.of(context).titleMedium,
                  ),
                ),
              ],
              const SizedBox(height: 16.0),
              const _LobbyNumbers(),
            ],
          ),
        ),
        userActionsBar: BottomBar(
          cupertinoGlass: true,
          children: [
            FutureBuilder(
              future: _cancelGameCreationFuture,
              builder: (context, snapshot) {
                return BottomBarButton(
                  onTap: snapshot.connectionState == ConnectionState.waiting
                      ? null
                      : () async {
                          setState(() {
                            _cancelGameCreationFuture = widget.cancelGameCreation();
                          });
                          try {
                            await _cancelGameCreationFuture;
                          } catch (_) {
                            if (context.mounted) {
                              showSnackBar(
                                context,
                                'Error cancelling game creation',
                                type: SnackBarType.error,
                              );
                            }
                          }
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                  label: context.l10n.cancel,
                  showLabel: true,
                  icon: CupertinoIcons.xmark,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class const UserChallengeLoadingContent(
  final ChallengeRequest challenge,
  final Future<void> Function() cancelChallenge,
) extends StatefulWidget {
  @override
  State<UserChallengeLoadingContent> createState() => _UserChallengeLoadingContentState();
}

class _UserChallengeLoadingContentState() extends State<UserChallengeLoadingContent> {
  Future<void>? _cancelChallengeFuture;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GameLayout(
        position: GoPosition.initial(
          widget.challenge.boardSize,
          handicap: widget.challenge.handicap,
        ),
        moves: const [],
        boardOverlay: _BoardOverlayCard(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.waitingForOpponent),
              const SizedBox(height: 16.0),
              UserFullNameWidget(
                user: widget.challenge.destUser,
                style: TextTheme.of(context).titleLarge,
              ),
              const SizedBox(height: 16.0),
              _GameParamsDisplay.challengeRequest(widget.challenge),
            ],
          ),
        ),
        userActionsBar: BottomBar(
          cupertinoGlass: true,
          children: [
            FutureBuilder(
              future: _cancelChallengeFuture,
              builder: (context, snapshot) {
                return BottomBarButton(
                  onTap: snapshot.connectionState == ConnectionState.waiting
                      ? null
                      : () async {
                          setState(() {
                            _cancelChallengeFuture = widget.cancelChallenge();
                          });
                          try {
                            await _cancelChallengeFuture;
                          } catch (_) {
                            if (context.mounted) {
                              showSnackBar(
                                context,
                                'Error cancelling challenge',
                                type: SnackBarType.error,
                              );
                            }
                          }
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                  label: context.l10n.cancel,
                  showLabel: true,
                  icon: CupertinoIcons.xmark,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class const OpenChallengeLoadingContent({
  required final ChallengeId id,
  required final ChallengeRequest challengeRequest,
  required final Future<void> Function() cancelChallenge,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<OpenChallengeLoadingContent> createState() => _OpenChallengeLoadingContentState();
}

class _OpenChallengeLoadingContentState() extends ConsumerState<OpenChallengeLoadingContent> {
  Future<void>? _cancelChallengeFuture;

  @override
  Widget build(BuildContext context) {
    final challengeLink = 'https://$kLichessHost/game/${widget.id}';
    final authUser = ref.watch(authControllerProvider);

    final qrColor = ref.watch(currentBrightnessProvider) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Column(
      children: [
        Expanded(
          child: SafeArea(
            child: GameLayout(
              position: GoPosition.initial(
                widget.challengeRequest.boardSize,
                handicap: widget.challengeRequest.handicap,
              ),
              moves: const [],
              boardOverlay: _BoardOverlayCard(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 20.0,
                  children: [
                    _GameParamsDisplay.challengeRequest(widget.challengeRequest),
                    Text(context.l10n.toInviteSomeoneToPlayGiveThisUrl),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: GestureDetector(
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(text: challengeLink));
                          if (!context.mounted) return;
                          showSnackBar(context, context.l10n.mobileCopied);
                        },
                        child: Text.rich(
                          TextSpan(
                            children: [
                              const WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Icon(Icons.copy),
                              ),
                              TextSpan(text: ' $challengeLink'),
                            ],
                          ),
                          style: TextTheme.of(context).bodyMedium
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),

                    Text(context.l10n.theFirstPersonToComeOnThisUrlWillPlayWithYou),

                    if (authUser != null)
                      FilledButton.tonalIcon(
                        onPressed: () => Navigator.of(context).push(
                          PickPlayerScreen.buildRoute(
                            title: Text(context.l10n.challengeAFriend),
                            onUserTap: (user) async {
                              // Capture everything that needs BuildContext before the async gap.
                              final navigator = Navigator.of(context);
                              final directedChallengeReq = widget.challengeRequest.copyWith(
                                destUser: user,
                              );
                              final directedChallengeRoute =
                                  widget.challengeRequest.timeControl ==
                                      ChallengeTimeControlType.clock
                                  ? GameScreen.buildRoute(
                                      source: UserChallengeSource(directedChallengeReq),
                                    )
                                  : null;

                              try {
                                await widget.cancelChallenge();
                              } catch (e) {
                                debugPrint('Error cancelling open challenge: $e');
                              }

                              if (!context.mounted) return;

                              if (directedChallengeRoute != null) {
                                // Invalidate the provider so the new GameScreen creates a
                                // fresh challenge even if the same UserChallengeSource was
                                // used in a previous game (Freezed equality shares providers).
                                ref.invalidate(
                                  gameScreenLoaderProvider(
                                    UserChallengeSource(directedChallengeReq),
                                  ),
                                );
                                // Use pushAndRemoveUntil to clear any old GameScreen from
                                // the stack without removing unrelated routes.
                                navigator.pushAndRemoveUntilHidingTabBar(
                                  directedChallengeRoute,
                                  (route) => route is! ScreenRoute || route.screen is! GameScreen,
                                );
                              } else {
                                await ref
                                    .read(challengeRepositoryProvider)
                                    .create(directedChallengeReq);
                                if (!context.mounted) return;
                                showSnackBar(
                                  context,
                                  context.l10n.mobileChallengeCreated.replaceAll('\\n', '\n'),
                                );
                                // Back to the screen below the game
                                Navigator.of(context).popUntilTabBarShown();
                              }
                            },
                          ),
                        ),
                        label: Text(context.l10n.challengeInviteLichessUser.replaceAll(':', '')),
                        icon: const Icon(Icons.person_search),
                      ),

                    Container(
                      padding: const EdgeInsets.all(4.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: QrImageView(
                        data: challengeLink,
                        eyeStyle: QrEyeStyle(color: qrColor, eyeShape: QrEyeShape.square),
                        dataModuleStyle: QrDataModuleStyle(
                          color: qrColor,
                          dataModuleShape: QrDataModuleShape.square,
                        ),
                        version: QrVersions.auto,
                        size: 120.0,
                        padding: const EdgeInsets.all(12.0),
                      ),
                    ),

                    Text(context.l10n.orLetYourOpponentScanQrCode),
                  ],
                ),
              ),
            ),
          ),
        ),
        BottomBar(
          cupertinoGlass: true,
          children: [
            Builder(
              builder: (context) => BottomBarButton(
                label: context.l10n.mobileShareChallengeUrl,
                onTap: () => launchShareDialog(context, ShareParams(text: challengeLink)),
                showLabel: true,
                icon: Icons.share,
              ),
            ),
            FutureBuilder(
              future: _cancelChallengeFuture,
              builder: (context, snapshot) {
                return BottomBarButton(
                  onTap: snapshot.connectionState == ConnectionState.waiting
                      ? null
                      : () async {
                          setState(() {
                            _cancelChallengeFuture = widget.cancelChallenge();
                          });
                          try {
                            await _cancelChallengeFuture;
                          } catch (_) {
                            if (context.mounted) {
                              showSnackBar(
                                context,
                                'Error cancelling challenge',
                                type: SnackBarType.error,
                              );
                            }
                          }
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                  label: context.l10n.cancel,
                  showLabel: true,
                  icon: CupertinoIcons.xmark,
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _GameParamsDisplay extends StatelessWidget {
  const new({
    required this.perf,
    required this.timeIncrement,
    required this.days,
    required this.boardSize,
  }) : handicap = 0;

  new seek(GameSeek seek)
    : perf = seek.perf,
      timeIncrement = seek.timeIncrement,
      days = seek.days,
      boardSize = seek.boardSize,
      handicap = 0;

  new challengeRequest(ChallengeRequest challenge)
    : perf = challenge.perf,
      timeIncrement = challenge.timeIncrement,
      days = challenge.days,
      boardSize = challenge.boardSize,
      handicap = challenge.handicap;

  final Perf perf;
  final int boardSize;
  final int handicap;
  final TimeIncrement? timeIncrement;
  final int? days;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(perf.icon, color: DefaultTextStyle.of(context).style.color),
        const SizedBox(width: 8.0),
        Text(
          [
            '$boardSize×$boardSize',
            if (handicap > 0) 'H$handicap',
            timeIncrement?.display ??
                (days != null ? '${context.l10n.daysPerTurn}: $days' : context.l10n.unlimited),
          ].join(' • '),
          style: TextTheme.of(context).titleLarge,
        ),
      ],
    );
  }
}

/// The screen of a game that is being loaded: the position it was opened from, if known, between
/// two placeholders for the players.
class const StandaloneGameLoadingContent({
  final GoPosition? loadingPosition,
  final Widget? userActionsBar,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: SafeArea(
        child: GameLayout(
          position: loadingPosition ?? GoPosition.initial(19),
          topTable: const LoadingPlayerWidget(),
          bottomTable: const LoadingPlayerWidget(),
          moves: const [],
          userActionsBar: userActionsBar,
        ),
      ),
    );
  }
}

/// A widget that shows a loading indicator for a player.
///
/// Must be wrapped in a [Shimmer] widget.
class const LoadingPlayerWidget({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      isLoading: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            flex: 6,
            child: SizedBox(
              height: 24.0,
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10.0),
                ),
              ),
            ),
          ),
          const Spacer(),
          Flexible(
            flex: 2,
            child: SizedBox(
              height: 38.0,
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(5.0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class const LoadGameError(final String errorMessage, {final bool showBottomBar = true})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SafeArea(
            child: GameLayout.empty(errorMessage: errorMessage),
          ),
        ),
        BottomBar(
          cupertinoGlass: true,
          children: [
            if (showBottomBar)
              BottomBarButton(
                onTap: () => Navigator.of(context).pop(),
                label: context.l10n.cancel,
                icon: CupertinoIcons.xmark,
                showLabel: true,
              ),
          ],
        ),
      ],
    );
  }
}

/// A board that shows a message that a challenge has been declined.
class const ChallengeDeclinedBoard({
  required final String declineReason,
  required final Challenge challenge,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final textColor = DefaultTextStyle.of(context).style.color;

    return Column(
      children: [
        Expanded(
          child: SafeArea(
            child: GameLayout(
              position: GoPosition.initial(challenge.boardSize, handicap: challenge.handicap),
              moves: const [],
              boardOverlay: _BoardOverlayCard(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n.challengeChallengeDeclined,
                      style: TextTheme.of(context).titleMedium,
                    ),
                    const SizedBox(height: 8.0),
                    Divider(height: 26.0, thickness: 0.0, color: textColor),
                    Text(declineReason, style: const TextStyle(fontStyle: FontStyle.italic)),
                    Divider(height: 26.0, thickness: 0.0, color: textColor),
                    if (challenge.destUser != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(' — '),
                            Flexible(
                              fit: FlexFit.loose,
                              child: UserFullNameWidget(user: challenge.destUser?.user),
                            ),
                            if (challenge.destUser?.lagRating != null) ...[
                              const SizedBox(width: 6.0),
                              LagIndicator(lagRating: challenge.destUser!.lagRating!, size: 13.0),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        BottomBar(
          cupertinoGlass: true,
          children: [
            BottomBarButton(
              onTap: () => Navigator.of(context).pop(),
              label: context.l10n.cancel,
              icon: CupertinoIcons.xmark,
              showLabel: true,
            ),
          ],
        ),
      ],
    );
  }
}

class const _LobbyNumbers() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lobbyNumbers = ref.watch(lobbyNumbersProvider);

    if (lobbyNumbers == null) {
      return Column(
        children: [
          Text(context.l10n.nbPlayers(0).replaceAll('0', '...')),
          const SizedBox(height: 8.0),
          Text(context.l10n.nbGamesInPlay(0).replaceAll('0', '...')),
        ],
      );
    } else {
      final (:nbPlayers, :nbGames) = lobbyNumbers;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(context.l10n.nbPlayers(nbPlayers).localizeNumbers()),
          const SizedBox(height: 8.0),
          Text(context.l10n.nbGamesInPlay(nbGames).localizeNumbers()),
        ],
      );
    }
  }
}

class const _BoardOverlayCard({final EdgeInsetsGeometry? padding, required final Widget child})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).dialogTheme.backgroundColor,
      elevation: 2.0,
      child: Padding(padding: padding ?? const EdgeInsets.all(30.0), child: child),
    );
  }
}
