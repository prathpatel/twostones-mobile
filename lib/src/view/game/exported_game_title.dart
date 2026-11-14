import 'package:intl/intl.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/game/game.dart';
import 'package:lichess_mobile/src/styles/icon_extensions.dart';
import 'package:lichess_mobile/src/utils/l10n.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/shimmer.dart';
import 'package:material_ui/material_ui.dart';

/// App bar title for a standalone game (an existing/archived game), derived from
/// its [GameMeta].
///
/// Shows the icon of the game's speed, the board size, the time control and rated/casual mode,
/// and optionally the date of the last move.
class const ExportedGameTitle({
  required final GameMeta meta,

  /// The date of the last move played in the game. When set, the title shows the
  /// relative date and a tooltip with the full date.
  final DateTime? lastMoveAt,
  super.key,
}) extends StatelessWidget {
  static DateFormat get _tooltipFormatter => DateFormat.yMMMMd().add_jm();

  @override
  Widget build(BuildContext context) {
    final time = meta.clock != null
        ? TimeIncrement(meta.clock!.initial.inSeconds, meta.clock!.increment.inSeconds).display
        : meta.daysPerTurn != null
        ? context.l10n.nbDays(meta.daysPerTurn!)
        : meta.perf.label(context.l10n);

    final board = '${meta.boardSize}×${meta.boardSize}';
    final handicap = meta.handicap > 0 ? ' H${meta.handicap}' : '';
    final mode = meta.rated ? ' • ${context.l10n.rated}' : ' • ${context.l10n.casual}';

    final subtitle = lastMoveAt != null
        ? relativeDate(context.l10n, lastMoveAt!, shortDate: false)
        : null;

    final titleRow = Row(
      mainAxisSize: .min,
      children: [
        Icon(meta.perf.icon, color: DefaultTextStyle.of(context).style.color),
        const SizedBox(width: 8.0),
        Flexible(
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [
              AppBarTitleText(
                '$board$handicap • $time$mode',
                maxLines: 1,
                minFontSize: 13.0,
                maxFontSize: 16.0,
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    // tighten the gap with the title above
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );

    return lastMoveAt != null
        ? Tooltip(message: _tooltipFormatter.format(lastMoveAt!), child: titleRow)
        : titleRow;
  }
}

/// Shimmer placeholder shown in the app bar while the game data backing a
/// [ExportedGameTitle] is still loading.
class const ExportedGameTitleLoading({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ShimmerLoading(
        isLoading: true,
        child: SizedBox(
          height: 34.0,
          width: 150.0,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(10.0),
            ),
          ),
        ),
      ),
    );
  }
}
