import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/widgets/go_board.dart';
import 'package:material_ui/material_ui.dart';

/// A small, non interactive Go board with rounded corners, to show a position in a list.
class const StaticGoBoard({
  required final double size,
  required final GoPosition position,
  final bool shadow = true,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: Styles.boardBorderRadius,
        boxShadow: shadow ? boardShadows : null,
      ),
      child: ClipRRect(
        borderRadius: Styles.boardBorderRadius,
        child: GoBoard(size: size, position: position, showCoordinates: false),
      ),
    );
  }
}

/// A board thumbnail widget
class BoardThumbnail extends StatefulWidget {
  const new({
    required this.size,
    required GoPosition this.position,
    this.header,
    this.footer,
    this.onTap,
  });

  /// A thumbnail with an empty board, shown while the position loads.
  const new loading({required this.size, this.header, this.footer}) : position = null, onTap = null;

  /// Size of the board.
  final double size;

  /// The stones to show. An empty 19×19 board is shown when null.
  final GoPosition? position;

  /// Show a header above the board. Typically a [Text] widget.
  final Widget? header;

  /// Show a footer above the board. Typically a [Text] widget.
  final Widget? footer;

  final GestureTapCallback? onTap;

  @override
  State<BoardThumbnail> createState() => _BoardThumbnailState();
}

class _BoardThumbnailState() extends State<BoardThumbnail> {
  double scale = 1.0;

  void _onTapDown() {
    if (widget.onTap == null) return;
    setState(() => scale = 0.98);
  }

  void _onTapCancel() {
    if (widget.onTap == null) return;
    setState(() => scale = 1.00);
  }

  @override
  Widget build(BuildContext context) {
    final board = StaticGoBoard(
      size: widget.size,
      position: widget.position ?? GoPosition.initial(19),
    );

    final maybeTappableBoard = widget.onTap != null
        ? GestureDetector(
            onTap: widget.onTap,
            onTapDown: (_) => _onTapDown(),
            onTapCancel: _onTapCancel,
            onTapUp: (_) => _onTapCancel(),
            child: AnimatedScale(
              scale: scale,
              duration: const Duration(milliseconds: 100),
              child: board,
            ),
          )
        : board;

    return widget.header != null || widget.footer != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [?widget.header, maybeTappableBoard, ?widget.footer],
          )
        : maybeTappableBoard;
  }
}
