import 'dart:math' as math;

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/widgets.dart';
import 'package:lichess_mobile/src/model/go/go.dart';

/// The colours a [GoBoard] is painted with.
@immutable
class const GoBoardColors({
  /// The wood of the board.
  final Color background = const Color(0xFFDDB06D),

  /// The grid lines and the star points.
  final Color line = const Color(0xFF3B2B14),

  /// The letters and numbers around the grid.
  final Color coordinates = const Color(0xFF5A4424),
  final Color blackStone = const Color(0xFF1B1B1B),
  final Color blackStoneHighlight = const Color(0xFF5C5C5C),
  final Color whiteStone = const Color(0xFFE6E6E6),
  final Color whiteStoneHighlight = const Color(0xFFFFFFFF),
  final Color stoneShadow = const Color(0x66000000),
}) {
  @override
  bool operator ==(Object other) =>
      other is GoBoardColors &&
      other.background == background &&
      other.line == line &&
      other.coordinates == coordinates &&
      other.blackStone == blackStone &&
      other.blackStoneHighlight == blackStoneHighlight &&
      other.whiteStone == whiteStone &&
      other.whiteStoneHighlight == whiteStoneHighlight &&
      other.stoneShadow == stoneShadow;

  @override
  int get hashCode => Object.hash(
    background,
    line,
    coordinates,
    blackStone,
    blackStoneHighlight,
    whiteStone,
    whiteStoneHighlight,
    stoneShadow,
  );
}

/// A Go board: the grid, the stones, and the marks of the counting phase.
///
/// The board is a square of [size] logical pixels. It only displays what it is given: the game
/// screen decides which moves are legal and what a tap means.
class const GoBoard({
  /// The width and height of the board, in logical pixels.
  required final double size,

  /// The stones to show.
  required final GoPosition position,

  /// Called with the index of the point that was tapped. The board ignores taps when it is null.
  final ValueChanged<int>? onTapPoint,

  /// Whether to print the column letters and row numbers around the grid.
  final bool showCoordinates = true,

  /// Whether to mark the stone of [GoPosition.lastMove].
  final bool showLastMove = true,

  /// A point where playing is forbidden by a ko, marked with a small square.
  final int? koPoint,

  /// Stones marked dead during the counting phase, drawn faded.
  final ISet<int> deadStones = const ISet.empty(),

  /// The side each point counts for during the counting phase, drawn as a small square.
  final IMap<int, Side> territory = const IMap.empty(),
  final GoBoardColors colors = const GoBoardColors(),
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final geometry = GoBoardGeometry(
      size: size,
      boardSize: position.size,
      showCoordinates: showCoordinates,
    );
    final onTap = onTapPoint;
    final board = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: _GoBoardPainter(
          geometry: geometry,
          position: position,
          showLastMove: showLastMove,
          koPoint: koPoint,
          deadStones: deadStones,
          territory: territory,
          colors: colors,
          textDirection: Directionality.of(context),
        ),
      ),
    );
    return Semantics(
      label: 'Go board, ${position.size} by ${position.size}',
      child: SizedBox.square(
        dimension: size,
        child: onTap == null
            ? board
            : GestureDetector(
                behavior: .opaque,
                onTapUp: (details) {
                  final point = geometry.pointAt(details.localPosition);
                  if (point != null) onTap(point);
                },
                child: board,
              ),
      ),
    );
  }
}

/// Where the lines of a board fall inside the square it is painted in.
@immutable
class const GoBoardGeometry({
  /// The width and height of the board, in logical pixels.
  required final double size,

  /// Number of lines on each side of the board.
  required final int boardSize,
  required final bool showCoordinates,
}) {
  /// The space between the edge of the board and its first line.
  ///
  /// Half a cell lets the stones of the first line fit; coordinates need a little more.
  double get margin => cell * (showCoordinates ? 0.95 : 0.6);

  /// The distance between two lines.
  double get cell => size / (boardSize - 1 + (showCoordinates ? 1.9 : 1.2));

  /// The centre of [point].
  Offset offsetOf(int point) =>
      Offset(margin + (point % boardSize) * cell, margin + (point ~/ boardSize) * cell);

  /// The point closest to [position], or null if it is outside the grid by more than half a cell.
  int? pointAt(Offset position) {
    final x = ((position.dx - margin) / cell).round();
    final y = ((position.dy - margin) / cell).round();
    if (x < 0 || y < 0 || x >= boardSize || y >= boardSize) return null;
    return y * boardSize + x;
  }
}

const _columnLetters = 'ABCDEFGHJKLMNOPQRST';

class const _GoBoardPainter({
  required final GoBoardGeometry geometry,
  required final GoPosition position,
  required final bool showLastMove,
  required final int? koPoint,
  required final ISet<int> deadStones,
  required final IMap<int, Side> territory,
  required final GoBoardColors colors,
  required final TextDirection textDirection,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final boardSize = geometry.boardSize;
    final cell = geometry.cell;
    final margin = geometry.margin;
    final last = margin + (boardSize - 1) * cell;

    canvas.drawRect(Offset.zero & size, Paint()..color = colors.background);

    final linePaint = Paint()
      ..color = colors.line
      ..strokeWidth = math.max(0.6, cell / 28)
      ..strokeCap = .square;
    for (var i = 0; i < boardSize; i++) {
      final at = margin + i * cell;
      canvas.drawLine(Offset(margin, at), Offset(last, at), linePaint);
      canvas.drawLine(Offset(at, margin), Offset(at, last), linePaint);
    }

    final starPaint = Paint()..color = colors.line;
    for (final point in goStarPoints(boardSize)) {
      canvas.drawCircle(geometry.offsetOf(point), math.max(1.5, cell * 0.11), starPaint);
    }

    if (geometry.showCoordinates) _paintCoordinates(canvas);

    final radius = cell * 0.47;
    for (var point = 0; point < position.board.length; point++) {
      final stone = position.board[point];
      if (stone == null) continue;
      _paintStone(
        canvas,
        geometry.offsetOf(point),
        radius,
        stone,
        dead: deadStones.contains(point),
      );
    }

    final lastPoint = position.lastMove?.point;
    if (showLastMove && lastPoint != null && position.board[lastPoint] != null) {
      canvas.drawCircle(
        geometry.offsetOf(lastPoint),
        radius * 0.5,
        Paint()
          ..style = .stroke
          ..strokeWidth = math.max(1.2, radius * 0.16)
          ..color = position.board[lastPoint] == Side.black ? colors.whiteStone : colors.blackStone,
      );
    }

    final ko = koPoint;
    if (ko != null && position.board[ko] == null) {
      canvas.drawRect(
        Rect.fromCenter(center: geometry.offsetOf(ko), width: radius * 0.9, height: radius * 0.9),
        Paint()
          ..style = .stroke
          ..strokeWidth = math.max(1, radius * 0.14)
          ..color = colors.line,
      );
    }

    for (final MapEntry(key: point, value: side) in territory.entries) {
      final paint = Paint()..color = side == Side.black ? colors.blackStone : colors.whiteStone;
      final square = Rect.fromCenter(
        center: geometry.offsetOf(point),
        width: radius * 0.7,
        height: radius * 0.7,
      );
      canvas.drawRect(square, paint);
      canvas.drawRect(
        square,
        Paint()
          ..style = .stroke
          ..strokeWidth = math.max(0.5, radius * 0.06)
          ..color = colors.line.withValues(alpha: 0.5),
      );
    }
  }

  void _paintStone(Canvas canvas, Offset center, double radius, Side side, {required bool dead}) {
    final alpha = dead ? 0.4 : 1.0;
    if (!dead) {
      canvas.drawCircle(
        center + Offset(radius * 0.06, radius * 0.1),
        radius,
        Paint()
          ..color = colors.stoneShadow
          ..maskFilter = MaskFilter.blur(.normal, radius * 0.12),
      );
    }
    final base = side == Side.black ? colors.blackStone : colors.whiteStone;
    final highlight = side == Side.black ? colors.blackStoneHighlight : colors.whiteStoneHighlight;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 0.9,
          colors: [
            highlight.withValues(alpha: alpha),
            base.withValues(alpha: alpha),
          ],
        ).createShader(rect),
    );
    if (side == Side.white) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = .stroke
          ..strokeWidth = math.max(0.5, radius * 0.05)
          ..color = colors.line.withValues(alpha: 0.35 * alpha),
      );
    }
  }

  void _paintCoordinates(Canvas canvas) {
    final boardSize = geometry.boardSize;
    final cell = geometry.cell;
    final margin = geometry.margin;
    final style = TextStyle(
      color: colors.coordinates,
      fontSize: math.max(6.0, cell * 0.36),
      fontWeight: .w600,
      height: 1,
    );
    final lastLine = margin + (boardSize - 1) * cell;
    final outside = margin * 0.58;
    for (var i = 0; i < boardSize; i++) {
      final at = margin + i * cell;
      _paintLabel(canvas, _columnLetters[i], Offset(at, margin - outside), style);
      _paintLabel(canvas, _columnLetters[i], Offset(at, lastLine + outside), style);
      _paintLabel(canvas, '${boardSize - i}', Offset(margin - outside, at), style);
      _paintLabel(canvas, '${boardSize - i}', Offset(lastLine + outside, at), style);
    }
  }

  void _paintLabel(Canvas canvas, String text, Offset center, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
    painter.dispose();
  }

  @override
  bool shouldRepaint(_GoBoardPainter oldDelegate) =>
      oldDelegate.position != position ||
      oldDelegate.geometry.size != geometry.size ||
      oldDelegate.geometry.showCoordinates != geometry.showCoordinates ||
      oldDelegate.showLastMove != showLastMove ||
      oldDelegate.koPoint != koPoint ||
      oldDelegate.deadStones != deadStones ||
      oldDelegate.territory != territory ||
      oldDelegate.colors != colors;
}
