import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/go/go.dart';

/// The move on the point printed as [coord] (`"E5"`) on a board of this [size].
GoMove at(String coord, {int size = 9}) {
  const columns = 'ABCDEFGHJKLMNOPQRST';
  final x = columns.indexOf(coord[0]);
  final y = size - int.parse(coord.substring(1));
  return GoMove.play(y * size + x);
}

GoPosition playAll(List<String> coords, {int size = 9}) => coords.fold(
  GoPosition.initial(size),
  (position, coord) => position.play(coord == 'pass' ? const GoMove.pass() : at(coord, size: size)),
);

GoPosition fromRows(List<String> rows, {required Side turn}) =>
    GoPosition.fromBoardString(rows.join(), turn: turn);

void main() {
  group('GoMove', () {
    test('reads and writes the server format', () {
      expect(GoMove.fromKey('pd', 19), const GoMove.play(3 * 19 + 15));
      expect(GoMove.fromKey('pd', 19)!.key(19), 'pd');
      expect(GoMove.fromKey('pd', 19)!.coord(19), 'Q16');
      expect(GoMove.fromKey('pass', 9), const GoMove.pass());
      expect(const GoMove.pass().key(9), 'pass');
      expect(const GoMove.pass().coord(9), 'pass');
    });

    test('rejects what is not a move on the board', () {
      expect(GoMove.fromKey('pd', 9), isNull);
      expect(GoMove.fromKey('a', 9), isNull);
      expect(GoMove.fromKey('a1', 9), isNull);
      expect(GoMove.fromKey('', 9), isNull);
    });

    test('numbers points from the top left corner and skips the letter I', () {
      expect(at('A9').point, 0);
      expect(at('J1').point, 80);
      expect(const GoMove.play(0).coord(9), 'A9');
      expect(const GoMove.play(80).coord(9), 'J1');
      expect(at('C3', size: 19).coord(19), 'C3');
    });
  });

  group('GoPosition', () {
    test('black moves first and sides alternate', () {
      final start = GoPosition.initial(9);
      expect(start.turn, Side.black);
      expect(start.play(at('E5')).turn, Side.white);
      expect(start.play(at('E5')).board[at('E5').point!], Side.black);
    });

    test('cannot play on an occupied point', () {
      final position = playAll(['E5']);
      expect(position.errorOf(at('E5')), GoMoveError.occupied);
      expect(() => position.play(at('E5')), throwsA(isA<GoMoveException>()));
    });

    test('cannot play off the board', () {
      expect(GoPosition.initial(9).errorOf(const GoMove.play(81)), GoMoveError.offBoard);
    });

    test('captures a single stone', () {
      // the white stone on E5 is surrounded by Black
      final position = playAll(['D5', 'E5', 'F5', 'A1', 'E4', 'A2', 'E6']);
      expect(position.board[at('E5').point!], isNull);
      expect(position.prisoners(Side.black), 1);
      expect(position.prisoners(Side.white), 0);
      expect(position.captured, [at('E5').point]);
    });

    test('captures a whole group', () {
      final position = fromRows([
        '.bb......',
        'bww......',
        '.bb......',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
      ], turn: Side.black);
      final next = position.play(at('D8'));
      expect(next.captured.toSet(), {at('B8').point, at('C8').point});
      expect(next.prisoners(Side.black), 2);
    });

    test('suicide is illegal', () {
      final position = playAll(['D5', 'A1', 'F5', 'A2', 'E4', 'A3', 'E6']);
      expect(position.turn, Side.white);
      expect(position.errorOf(at('E5')), GoMoveError.suicide);
    });

    test('capturing is not suicide', () {
      // White plays on a point without liberties, and captures two black stones
      final position = fromRows([
        '.bw......',
        'bw.......',
        'w........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
      ], turn: Side.white);
      final next = position.play(at('A9'));
      expect(next.captured.length, 2);
      expect(next.prisoners(Side.white), 2);
    });

    test('a ko cannot be retaken immediately', () {
      final position = fromRows([
        '.bw......',
        'b.bw.....',
        '.bw......',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
      ], turn: Side.white);
      // White captures the black stone on C8 by playing B8
      final afterCapture = position.play(at('B8'));
      expect(afterCapture.captured, [at('C8').point]);
      // Black retaking on C8 would repeat the previous position
      expect(afterCapture.errorOf(at('C8')), GoMoveError.ko);
      expect(afterCapture.koPoint, at('C8').point);
      // after an exchange elsewhere, Black may retake
      final afterThreat = afterCapture.play(at('H2')).play(at('H3'));
      expect(afterThreat.koPoint, isNull);
      expect(afterThreat.isLegal(at('C8')), isTrue);
    });

    test('two passes stop play', () {
      final position = playAll(['E5', 'pass', 'pass']);
      expect(position.bothPassed, isTrue);
      expect(position.turn, Side.white);
      expect(playAll(['E5', 'pass']).bothPassed, isFalse);
      expect(playAll(['pass', 'E5', 'pass']).bothPassed, isFalse);
    });

    test('handicap places black stones and White moves first', () {
      final position = GoPosition.initial(19, handicap: 4);
      expect(position.board.where((stone) => stone == Side.black).length, 4);
      expect(position.turn, Side.white);
      expect(position.board[at('Q16', size: 19).point!], Side.black);
      expect(position.board[at('D4', size: 19).point!], Side.black);
    });

    test('handicap is capped by the board size', () {
      expect(goHandicapPoints(9, 9).length, 5);
      expect(goHandicapPoints(13, 9).length, 9);
      expect(goHandicapPoints(19, 1), isEmpty);
    });

    test('reads and writes the board as the server sends it', () {
      final board = '.bw${'.' * 78}';
      final position = GoPosition.fromBoardString(board, turn: Side.black);
      expect(position.size, 9);
      expect(position.board[1], Side.black);
      expect(position.board[2], Side.white);
      expect(position.boardString, board);
      expect(() => GoPosition.fromBoardString('...', turn: Side.black), throwsFormatException);
    });

    test('knows the liberties of a group', () {
      final position = playAll(['A9', 'E5', 'B9']);
      expect(position.group(at('A9').point!).stones.toSet(), {at('A9').point, at('B9').point});
      expect(position.group(at('A9').point!).liberties, 3);
      expect(position.group(at('E5').point!).liberties, 4);
    });
  });

  group('goStarPoints', () {
    test('marks five points on 9×9 and nine on larger boards', () {
      expect(goStarPoints(9).length, 5);
      expect(goStarPoints(13).length, 9);
      expect(goStarPoints(19).length, 9);
      expect(goStarPoints(19), contains(at('K10', size: 19).point));
      expect(goStarPoints(9), contains(at('C7').point));
    });
  });

  group('replayGoGame', () {
    test('returns every position of the game', () {
      final positions = replayGoGame(size: 9, moves: ['ee', 'cg', 'pass', 'gc']);
      expect(positions.length, 5);
      expect(positions.last.lastMove, GoMove.fromKey('gc', 9));
      expect(positions.last.turn, Side.black);
      expect(positions[3].lastMove, const GoMove.pass());
    });

    test('stops at the first illegal move', () {
      final positions = replayGoGame(size: 9, moves: ['ee', 'ee', 'cg']);
      expect(positions.length, 2);
    });

    test('starts from the handicap stones', () {
      final positions = replayGoGame(size: 9, handicap: 2, moves: const IList.empty());
      expect(positions.single.turn, Side.white);
    });
  });
}
