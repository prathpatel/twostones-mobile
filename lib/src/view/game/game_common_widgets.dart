import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/game/exported_game.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/service/game_share_service.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/share.dart';
import 'package:lichess_mobile/src/view/game/game_review_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/platform_context_menu_button.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

/// Opens a game screen for the given [LightExportedGame].
///
/// Will open [GameScreen] if the game belongs to the current user (its [GameFullId] is known),
/// otherwise [GameReviewScreen].
void openGameScreen(
  BuildContext context, {
  required LightExportedGame game,
  required Side orientation,
  DateTime? lastMoveAt,
}) {
  Navigator.of(context).pushHidingTabBar(
    game.fullId != null
        ? GameScreen.buildRoute(
            source: ExistingGameSource(game.fullId!),
            loadingPosition: game.lastPosition,
            lastMoveAt: lastMoveAt,
          )
        : GameReviewScreen.buildRoute(orientation: orientation, gameId: game.id),
  );
}

/// Makes the game sharing actions of a "Share & export" submenu.
///
/// The game URL can always be shared; the SGF record is only available once the game is
/// [finished].
List<ContextMenuAction> makeFinishedGameShareMenuActions(
  BuildContext context,
  WidgetRef ref, {
  required GameId gameId,
  required Side orientation,
  required bool finished,
}) {
  return [
    ContextMenuAction(
      label: context.l10n.mobileShareGameURL,
      onPressed: () {
        launchShareDialog(
          context,
          ShareParams(uri: lichessGameUri(gameId, orientation: orientation)),
        );
      },
    ),
    if (finished)
      ContextMenuAction(
        label: 'Game record (SGF)',
        onPressed: () async {
          try {
            final sgf = await ref.read(gameShareServiceProvider).sgf(gameId);
            if (context.mounted) {
              launchShareDialog(context, ShareParams(text: sgf));
            }
          } catch (e) {
            if (context.mounted) {
              showSnackBar(context, 'Failed to get the game record', type: SnackBarType.error);
            }
          }
        },
      ),
  ];
}
