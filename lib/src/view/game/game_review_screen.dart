import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_ui/material_ui.dart';

/// Shows a finished game move by move.
///
/// This replaces the chess analysis board of Lichess Mobile, which every "open this finished
/// game" action used to lead to.
// TODO(go): load the game and replay it on a GoBoard. For now the screen only says that the
// review is not available, so that the actions leading here keep a destination.
class const GameReviewScreen({
  required final GameId gameId,
  required final Side orientation,
  final int? initialMoveCursor,
  super.key,
}) extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(title: Text('Game $gameId')),
      body: const Center(
        child: Padding(
          padding: Styles.bodyPadding,
          child: Text('Reviewing finished games is not available yet.', textAlign: .center),
        ),
      ),
    );
  }
}
