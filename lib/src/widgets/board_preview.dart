import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/widgets/board_thumbnail.dart';
import 'package:material_ui/material_ui.dart';

/// A board preview with a description.
class SmallBoardPreview extends StatelessWidget {
  const new({
    required GoPosition this.position,
    required this.description,
    this.padding,
    this.onTap,
  }) : _showLoadingPlaceholder = false;

  const new loading({this.padding})
    : position = null,
      description = const SizedBox.shrink(),
      onTap = null,
      _showLoadingPlaceholder = true;

  /// The stones to show, null for the loading placeholder.
  final GoPosition? position;

  final Widget description;

  final GestureTapCallback? onTap;

  final EdgeInsetsGeometry? padding;

  final bool _showLoadingPlaceholder;

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final boardSize =
            constraints.biggest.shortestSide - (constraints.biggest.shortestSide / 1.518);
        return Padding(
          padding:
              padding ??
              Styles.horizontalBodyPadding.add(const EdgeInsets.symmetric(vertical: 8.0)),
          child: SizedBox(
            height: boardSize,
            child: Row(
              children: [
                if (_showLoadingPlaceholder)
                  Container(
                    width: boardSize,
                    height: boardSize,
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      borderRadius: Styles.boardBorderRadius,
                    ),
                  )
                else
                  StaticGoBoard(size: boardSize, position: position ?? GoPosition.initial(19)),
                const SizedBox(width: 10.0),
                if (_showLoadingPlaceholder)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 16.0,
                              width: double.infinity,
                              decoration: const BoxDecoration(
                                color: Colors.black,
                                borderRadius: Styles.boardBorderRadius,
                              ),
                            ),
                            const SizedBox(height: 4.0),
                            Container(
                              height: 16.0,
                              width: MediaQuery.widthOf(context) / 3,
                              decoration: const BoxDecoration(
                                color: Colors.black,
                                borderRadius: Styles.boardBorderRadius,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          height: 44.0,
                          width: 44.0,
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            borderRadius: Styles.boardBorderRadius,
                          ),
                        ),
                        Container(
                          height: 16.0,
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            borderRadius: Styles.boardBorderRadius,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Expanded(child: description),
              ],
            ),
          ),
        );
      },
    );

    return onTap != null ? InkWell(onTap: onTap, child: content) : content;
  }
}
