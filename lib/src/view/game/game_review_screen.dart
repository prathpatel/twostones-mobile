import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/game/exported_game.dart';
import 'package:lichess_mobile/src/model/game/game_repository.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/utils/share.dart';
import 'package:lichess_mobile/src/view/game/game_player.dart';
import 'package:lichess_mobile/src/view/game/status_l10n.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/buttons.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/game_layout.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

final _reviewedGameProvider = FutureProvider.autoDispose.family<ExportedGame, GameId>(
  (ref, id) => ref.read(gameRepositoryProvider).getGame(id),
  name: 'ReviewedGameProvider',
);

/// Shows a finished game move by move, with the count of the game on its last position.
class const GameReviewScreen({
  required final GameId gameId,
  required final Side orientation,
  final int? initialMoveCursor,
  super.key,
}) extends ConsumerStatefulWidget {
  static Route<dynamic> buildRoute({
    required GameId gameId,
    required Side orientation,
    int? initialMoveCursor,
  }) => buildScreenRoute(
    screen: GameReviewScreen(
      gameId: gameId,
      orientation: orientation,
      initialMoveCursor: initialMoveCursor,
    ),
  );

  @override
  ConsumerState<GameReviewScreen> createState() => _GameReviewScreenState();
}

class _GameReviewScreenState() extends ConsumerState<GameReviewScreen> {
  /// The index of the shown step, null until the game is loaded (then the last step, or
  /// [GameReviewScreen.initialMoveCursor]).
  int? _cursor;

  int _cursorOf(ExportedGame game) => (_cursor ?? widget.initialMoveCursor ?? game.steps.length - 1)
      .clamp(0, game.steps.length - 1);

  void _goTo(ExportedGame game, int cursor) {
    setState(() {
      _cursor = cursor.clamp(0, game.steps.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final gameAsync = ref.watch(_reviewedGameProvider(widget.gameId));

    return PlatformScaffold(
      extendBodyBehindAppBar: false,
      appBar: PlatformAppBar(
        title: Text(switch (gameAsync) {
          AsyncData(:final value) => '${value.meta.boardSize}×${value.meta.boardSize}',
          _ => '',
        }),
        actions: [
          SemanticIconButton(
            icon: const PlatformShareIcon(),
            semanticsLabel: context.l10n.mobileShareGameURL,
            onPressed: () =>
                launchShareDialog(context, ShareParams(uri: lichessUri('/${widget.gameId}'))),
          ),
        ],
      ),
      body: switch (gameAsync) {
        AsyncData(:final value) => _ReviewBody(
          game: value,
          cursor: _cursorOf(value),
          onGoTo: (cursor) => _goTo(value, cursor),
        ),
        AsyncError() => FullScreenRetryRequest(
          onRetry: () => ref.invalidate(_reviewedGameProvider(widget.gameId)),
        ),
        _ => const Center(child: CircularProgressIndicator.adaptive()),
      },
    );
  }
}

class const _ReviewBody({
  required final ExportedGame game,
  required final int cursor,
  required final ValueChanged<int> onGoTo,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final steps = game.steps;
    final step = steps[cursor];
    final isLast = cursor == steps.length - 1;
    final scoring = game.scoring;
    // The count belongs to the last position: earlier ones did not have these stones.
    final showCount = isLast && scoring != null;
    // A Go board is not turned around: Black, who plays first, is at the bottom as in a record,
    // unless the user played White.
    final bottomSide = game.youAre ?? Side.black;

    final result = isLast
        ? [
            if (game.data.result != null) game.data.result!,
            gameStatusL10n(
              context,
              status: game.status,
              lastPosition: step.position,
              winner: game.winner,
            ),
          ].join(' · ')
        : null;

    GamePlayer playerOf(Side side) => GamePlayer(
      game: game,
      side: side,
      prisoners: step.position.prisoners(side),
      points: showCount ? scoring.score.pointsOf(side) : null,
    );

    return GameLayout(
      position: step.position,
      deadStones: showCount ? scoring.dead : const ISet<int>.empty(),
      territory: showCount ? scoring.score.ownership : const IMap<int, Side>.empty(),
      topTable: playerOf(bottomSide.opposite),
      bottomTable: Column(
        mainAxisAlignment: .spaceEvenly,
        children: [
          if (result != null)
            Padding(
              padding: Styles.horizontalBodyPadding,
              child: Text(result, style: Styles.bold, textAlign: .center),
            ),
          playerOf(bottomSide),
        ],
      ),
      moves: steps.skip(1).map((s) => s.move!.coord(game.meta.boardSize)).toList(),
      currentMoveIndex: cursor,
      onSelectMove: onGoTo,
      userActionsBar: BottomBar(
        cupertinoGlass: true,
        children: [
          BottomBarGroup(
            children: [
              BottomBarButton(
                label: 'First move',
                icon: CupertinoIcons.backward_end,
                onTap: cursor > 0 ? () => onGoTo(0) : null,
              ),
              RepeatButton(
                onLongPress: cursor > 0 ? () => onGoTo(cursor - 1) : null,
                child: BottomBarButton(
                  label: 'Previous',
                  icon: CupertinoIcons.chevron_back,
                  showTooltip: false,
                  onTap: cursor > 0 ? () => onGoTo(cursor - 1) : null,
                ),
              ),
              RepeatButton(
                onLongPress: !isLast ? () => onGoTo(cursor + 1) : null,
                child: BottomBarButton(
                  label: context.l10n.next,
                  icon: CupertinoIcons.chevron_forward,
                  showTooltip: false,
                  onTap: !isLast ? () => onGoTo(cursor + 1) : null,
                ),
              ),
              BottomBarButton(
                label: 'Last move',
                icon: CupertinoIcons.forward_end,
                onTap: !isLast ? () => onGoTo(steps.length - 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
