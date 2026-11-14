import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/widgets/go_board.dart';

Future<void> pumpBoard(
  WidgetTester tester, {
  required GoPosition position,
  ValueChanged<int>? onTapPoint,
  bool showCoordinates = true,
  ISet<int> deadStones = const ISet.empty(),
  IMap<int, Side> territory = const IMap.empty(),
  int? koPoint,
}) => tester.pumpWidget(
  Directionality(
    textDirection: .ltr,
    child: Align(
      alignment: .topLeft,
      child: GoBoard(
        size: 380,
        position: position,
        onTapPoint: onTapPoint,
        showCoordinates: showCoordinates,
        deadStones: deadStones,
        territory: territory,
        koPoint: koPoint,
      ),
    ),
  ),
);

void main() {
  group('GoBoardGeometry', () {
    for (final boardSize in kGoBoardSizes) {
      for (final showCoordinates in [true, false]) {
        test('finds every point of a $boardSize×$boardSize board '
            '(coordinates: $showCoordinates)', () {
          final geometry = GoBoardGeometry(
            size: 380,
            boardSize: boardSize,
            showCoordinates: showCoordinates,
          );
          for (var point = 0; point < boardSize * boardSize; point++) {
            final offset = geometry.offsetOf(point);
            expect(geometry.pointAt(offset), point);
            expect(geometry.pointAt(offset + Offset(geometry.cell * 0.4, 0)), point);
            expect(offset.dx, inInclusiveRange(geometry.cell / 2, 380 - geometry.cell / 2));
            expect(offset.dy, inInclusiveRange(geometry.cell / 2, 380 - geometry.cell / 2));
          }
        });
      }
    }

    test('ignores positions outside the grid', () {
      const geometry = GoBoardGeometry(size: 380, boardSize: 9, showCoordinates: true);
      expect(geometry.pointAt(Offset.zero), isNull);
      expect(geometry.pointAt(const Offset(379, 379)), isNull);
      expect(geometry.pointAt(const Offset(190, 1)), isNull);
    });
  });

  group('GoBoard', () {
    testWidgets('reports the point that was tapped', (tester) async {
      final taps = <int>[];
      await pumpBoard(tester, position: GoPosition.initial(9), onTapPoint: taps.add);
      const geometry = GoBoardGeometry(size: 380, boardSize: 9, showCoordinates: true);

      await tester.tapAt(geometry.offsetOf(0));
      await tester.tapAt(geometry.offsetOf(40));
      await tester.tapAt(geometry.offsetOf(80));
      await tester.tapAt(const Offset(2, 2));

      expect(taps, [0, 40, 80]);
    });

    testWidgets('ignores taps without a callback', (tester) async {
      await pumpBoard(tester, position: GoPosition.initial(19, handicap: 9));
      await tester.tapAt(const Offset(190, 190));
      expect(tester.takeException(), isNull);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('paints stones, the last move and the counting marks', (tester) async {
      final position = replayGoGame(size: 9, moves: ['ee', 'cg', 'gc', 'pass']).last;
      await pumpBoard(
        tester,
        position: position.play(GoMove.fromKey('cc', 9)!),
        showCoordinates: false,
        deadStones: {GoMove.fromKey('cg', 9)!.point!}.lock,
        territory: {0: Side.black, 80: Side.white}.lock,
        koPoint: 10,
      );
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Go board, 9 by 9'), findsOneWidget);
    });
  });
}
