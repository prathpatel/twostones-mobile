import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/styles/icon_extensions.dart';
import 'package:lichess_mobile/src/styles/lichess_icons.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/account/rating_pref_aware.dart';
import 'package:lichess_mobile/src/widgets/rating.dart';
import 'package:material_ui/material_ui.dart';

/// A widget that displays the performance cards of a user.
class const PerfCards({
  required final User user,
  required final bool isMe,
  final EdgeInsetsGeometry? padding,
  super.key,
}) extends StatelessWidget {
  static const BorderRadius _kCardBorderRadius = BorderRadius.all(Radius.circular(6.0));

  @override
  Widget build(BuildContext context) {
    final List<Perf> userPerfs = Perf.values
        .where((element) {
          final p = user.perfs[element];
          return p != null && p.numberOfGamesOrRuns > 0 && p.ratingDeviation < kClueLessDeviation;
        })
        .toList(growable: false);

    userPerfs.sort(
      (p1, p2) =>
          user.perfs[p2]!.numberOfGamesOrRuns.compareTo(user.perfs[p1]!.numberOfGamesOrRuns),
    );

    if (userPerfs.isEmpty) {
      return const SizedBox.shrink();
    }

    final resolvedPadding = (padding ?? Styles.bodySectionPadding).resolve(
      Directionality.of(context),
    );

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.4,
      child: RatingPrefAware(
        child: Padding(
          padding: EdgeInsets.only(top: resolvedPadding.top, bottom: resolvedPadding.bottom),
          child: SizedBox(
            height: 106,
            child: ListView.separated(
              padding: EdgeInsets.only(
                left: resolvedPadding.left,
                right: resolvedPadding.right,
                top: 3.0,
                bottom: 3.0,
              ),
              scrollDirection: Axis.horizontal,
              itemCount: userPerfs.length,
              itemBuilder: (_, index) {
                // Uses the build context: theme reads on the item builder context are not updated
                // when the theme changes.
                final perf = userPerfs[index];
                final userPerf = user.perfs[perf]!;
                return SizedBox(
                  height: 100,
                  width: 100,
                  child: Card(
                    shape: const RoundedRectangleBorder(borderRadius: _kCardBorderRadius),
                    child: SizedBox(
                      child: Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Text(
                              perf.shortLabel(context.l10n),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Icon(perf.icon, color: perfIconColor(context)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                RatingWidget(
                                  rating: userPerf.rating,
                                  deviation: userPerf.ratingDeviation,
                                  provisional: userPerf.provisional,
                                  style: Styles.bold,
                                ),
                                const SizedBox(width: 3),
                                if (userPerf.progression != 0) ...[
                                  Icon(
                                    userPerf.progression > 0
                                        ? LichessIcons.arrow_full_upperright
                                        : LichessIcons.arrow_full_lowerright,
                                    color: userPerf.progression > 0
                                        ? context.lichessColors.green
                                        : context.lichessColors.red,
                                    size: 12,
                                  ),
                                  Flexible(
                                    child: Text(
                                      userPerf.progression.abs().toString(),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: userPerf.progression > 0
                                            ? context.lichessColors.green
                                            : context.lichessColors.red,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
              separatorBuilder: (context, index) => const SizedBox(width: 10),
            ),
          ),
        ),
      ),
    );
  }
}
