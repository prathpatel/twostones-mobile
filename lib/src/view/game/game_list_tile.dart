import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/game/exported_game.dart';
import 'package:lichess_mobile/src/model/game/game_status.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/service/game_share_service.dart';
import 'package:lichess_mobile/src/styles/icon_extensions.dart';
import 'package:lichess_mobile/src/styles/lichess_colors.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:lichess_mobile/src/utils/share.dart';
import 'package:lichess_mobile/src/view/game/game_common_widgets.dart';
import 'package:lichess_mobile/src/view/game/game_review_screen.dart';
import 'package:lichess_mobile/src/view/game/status_l10n.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/board_thumbnail.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/user.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

DateFormat get _dateFormatter => DateFormat.yMMMd();

/// The board size and handicap of a game, as shown in lists: `19×19`, `9×9 H3`.
String gameBoardLabel(LightExportedGame game) =>
    '${game.boardSize}×${game.boardSize}${game.handicap > 0 ? ' H${game.handicap}' : ''}';

/// The colour and the text that show how a game went for the player of [pov].
({Color? color, String text}) gameResultMark(
  BuildContext context,
  LightExportedGame game, {
  required Side pov,
  required int? ratingDiff,
}) {
  final isAborted = game.status == GameStatus.aborted || game.status == GameStatus.noStart;
  final color = isAborted
      ? LichessColors.grey
      : game.winner == null
      ? textShade(context, Styles.subtitleOpacity)
      : game.winner == pov
      ? context.lichessColors.green
      : context.lichessColors.red;

  // The rating change when there is one, else the result of the game record, else a symbol.
  final text = ratingDiff != null && !isAborted
      ? ratingDiff > 0
            ? '+$ratingDiff'
            : ratingDiff == 0
            ? '±0'
            : '$ratingDiff'
      : isAborted
      ? '✕'
      : game.result ??
            (game.winner == null
                ? '='
                : game.winner == pov
                ? '▲'
                : '▼');
  return (color: color, text: text);
}

/// A list tile for a game in a game list.
class const GameListTile({
  required final LightExportedGameWithPov item,
  final EdgeInsetsGeometry? padding,
  final Future<void> Function(BuildContext context)? onPressedBookmark,

  /// Whether to show only the time of day the game started instead of its date, in a list grouped
  /// by day.
  final bool timeOnly = false,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:game, pov: youAre) = item;
    final me = youAre == Side.white ? game.white : game.black;
    final opponent = youAre == Side.white ? game.black : game.white;

    final date = timeOnly
        ? formatTimeOfDay(context, game.createdAt)
        : relativeDate(context.l10n, game.createdAt, shortDate: false);

    final showRatings = switch (ref.watch(showRatingsPrefProvider)) {
      AsyncData(:final value) => value != ShowRatings.no,
      _ => false,
    };
    final result = gameResultMark(
      context,
      game,
      pov: youAre,
      ratingDiff: showRatings ? me.ratingDiff : null,
    );

    return ListTile(
      contentPadding: padding,
      onTap: () => openGameScreen(
        context,
        game: item.game,
        orientation: item.pov,
        lastMoveAt: game.lastMoveAt,
      ),
      onLongPress: () {
        showAdaptiveBottomSheet<void>(
          context: context,
          useRootNavigator: true,
          isScrollControlled: true,
          builder: (context) =>
              GameContextMenu(game: game, mySide: youAre, onPressedBookmark: onPressedBookmark),
        );
      },
      leading: Icon(game.perf.icon, color: perfIconColor(context)),
      title: UserFullNameWidget.player(
        user: opponent.user,
        name: opponent.name,
        aiLevel: opponent.aiLevel,
        rating: opponent.rating,
        provisional: opponent.provisional,
      ),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '${gameBoardLabel(game)} • $date'),
            const TextSpan(text: '  '),
            TextSpan(
              text: result.text,
              style: TextStyle(color: result.color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tile for a game in a game list, with its last position on a small board.
class const GameListDetailTile({
  required final LightExportedGameWithPov item,
  final Future<void> Function(BuildContext context)? onPressedBookmark,

  /// Whether to show only the time of day the game started instead of its date, in a list grouped
  /// by day.
  final bool timeOnly = false,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:game, pov: youAre) = item;
    final me = youAre == Side.white ? game.white : game.black;
    final opponent = youAre == Side.white ? game.black : game.white;
    final isTablet = isTabletOrLarger(context);
    final subtitleFontSize = isTablet ? 16.0 : 12.0;

    final showRatings = switch (ref.watch(showRatingsPrefProvider)) {
      AsyncData(:final value) => value != ShowRatings.no,
      _ => false,
    };
    final result = gameResultMark(
      context,
      game,
      pov: youAre,
      ratingDiff: showRatings ? me.ratingDiff : null,
    );

    return InkWell(
      onLongPress: () {
        showAdaptiveBottomSheet<void>(
          context: context,
          useRootNavigator: true,
          isScrollControlled: true,
          builder: (context) =>
              GameContextMenu(game: game, mySide: youAre, onPressedBookmark: onPressedBookmark),
        );
      },
      onTap: () => openGameScreen(
        context,
        game: item.game,
        orientation: item.pov,
        lastMoveAt: game.lastMoveAt,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final boardSize = constraints.maxWidth / 3;
            return Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                BoardThumbnail(size: boardSize, position: game.lastPosition),
                Expanded(
                  // As high as the board, or higher if the text needs it (e.g. in a narrow card).
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: boardSize),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                (timeOnly
                                        ? formatTimeOfDay(context, game.createdAt)
                                        : relativeDate(context.l10n, game.createdAt))
                                    .toUpperCase(),
                                style: TextStyle(
                                  color: textShade(context, 0.5),
                                  fontSize: subtitleFontSize,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Icon(
                                game.perf.icon,
                                size: subtitleFontSize + 3,
                                color: textShade(context, 0.7),
                              ),
                            ],
                          ),
                          UserFullNameWidget.player(
                            user: opponent.user,
                            name: opponent.name,
                            aiLevel: opponent.aiLevel,
                            rating: opponent.rating,
                            provisional: opponent.provisional,
                            style: TextStyle(
                              fontSize: isTablet ? 22.0 : 16.0,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${gameBoardLabel(game)} • ${game.clockDisplay(context.l10n)} • '
                            '${game.rated ? context.l10n.rated : context.l10n.casual}',
                            style: TextStyle(
                              fontSize: subtitleFontSize,
                              color: textShade(context, Styles.subtitleOpacity),
                            ),
                          ),
                          Text(
                            result.text,
                            style: TextStyle(
                              color: result.color,
                              fontWeight: FontWeight.w600,
                              fontSize: isTablet ? 20.0 : 15.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class const GameContextMenu({
  required final LightExportedGame game,
  required final Side mySide,
  required final Future<void> Function(BuildContext context)? onPressedBookmark,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(isLoggedInProvider);

    return BottomSheetScrollableContainer(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0)
              .add(const EdgeInsets.only(bottom: 4.0)),
          child: Text(
            context.l10n.resVsX(
              game.black.fullName(context.l10n),
              game.white.fullName(context.l10n),
            ),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.5),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return IntrinsicHeight(
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    BoardThumbnail(
                      size: constraints.maxWidth - (constraints.maxWidth / 1.618),
                      position: game.lastPosition,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${gameBoardLabel(game)} • ${game.clockDisplay(context.l10n)} • '
                                  '${game.rated ? context.l10n.rated : context.l10n.casual}',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                Text(
                                  '${_dateFormatter.format(game.createdAt)} ${formatTimeOfDay(context, game.createdAt)}',
                                  style: TextStyle(
                                    color: textShade(context, Styles.subtitleOpacity),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              [
                                ?game.result,
                                gameStatusL10n(
                                  context,
                                  status: game.status,
                                  lastPosition: game.lastPosition,
                                  winner: game.winner,
                                ),
                              ].join(' • '),
                              style: TextStyle(
                                color: game.winner == null
                                    ? textShade(context, Styles.subtitleOpacity)
                                    : game.winner == mySide
                                    ? context.lichessColors.green
                                    : context.lichessColors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        ListSection(
          children: [
            BottomSheetContextMenuAction(
              icon: Icons.history,
              onPressed: () {
                Navigator.of(context)
                    .push(GameReviewScreen.buildRoute(orientation: mySide, gameId: game.id));
              },
              child: const Text('Review the game'),
            ),
            if (isLoggedIn && onPressedBookmark != null)
              BottomSheetContextMenuAction(
                onPressed: () => onPressedBookmark?.call(context),
                icon: game.isBookmarked
                    ? Icons.bookmark_remove_outlined
                    : Icons.bookmark_add_outlined,
                closeOnPressed: true,
                child: Text(
                  game.isBookmarked
                      ? context.l10n.mobileRemoveBookmark
                      : context.l10n.bookmarkThisGame,
                ),
              ),
            BottomSheetContextMenuAction(
              onPressed: () {
                launchShareDialog(
                  context,
                  ShareParams(uri: lichessGameUri(game.id, orientation: mySide)),
                );
              },
              icon: Theme.of(context).platform == TargetPlatform.iOS
                  ? Icons.ios_share
                  : Icons.share,
              child: Text(context.l10n.mobileShareGameURL),
            ),
            BottomSheetContextMenuAction(
              icon: Icons.text_snippet,
              child: const Text('Game record (SGF)'),
              onPressed: () async {
                try {
                  final sgf = await ref.read(gameShareServiceProvider).sgf(game.id);
                  if (context.mounted) {
                    launchShareDialog(context, ShareParams(text: sgf));
                  }
                } catch (e) {
                  if (context.mounted) {
                    showSnackBar(
                      context,
                      'Failed to get the game record',
                      type: SnackBarType.error,
                    );
                  }
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
