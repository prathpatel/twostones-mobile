/// The rules of Go as played on TwoStones: captures, suicide and positional superko.
///
/// The server is authoritative. This library replays games, shows them move by move and stops the
/// app from sending moves the server would refuse. It mirrors the server's `goban` module and the
/// website's `ui/round/src/goban.ts`.
library;

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

/// One of the two players, and the colour of their stones.
enum Side() {
  black,
  white;

  Side get opposite => this == black ? white : black;

  /// The letter used for this side's stones in a board string sent by the server.
  String get stoneLetter => this == black ? 'b' : 'w';

  static Side? fromName(String? name) => switch (name) {
    'black' => black,
    'white' => white,
    _ => null,
  };
}

const _sgfLetters = 'abcdefghijklmnopqrs';

/// Column letters as printed on a board: the letter I is skipped.
const _humanColumns = 'ABCDEFGHJKLMNOPQRST';

/// The board sizes the server offers.
const kGoBoardSizes = [9, 13, 19];

/// A move: a stone placed on a point, or a pass.
///
/// Points are numbered row by row from the top left corner, so point `0` is A19 on a 19×19 board
/// and the last point is T1.
@immutable
class GoMove {
  /// A stone played on [point].
  const new play(int this.point);

  /// A pass.
  const new pass() : point = null;

  /// The index of the point played, or `null` for a pass.
  final int? point;

  bool get isPass => point == null;

  /// Parses a move as sent by the server: SGF coordinates (`"pd"`) or `"pass"`.
  ///
  /// Returns `null` if [key] is not a move on a board of this [size].
  static GoMove? fromKey(String key, int size) {
    if (key == 'pass') return const GoMove.pass();
    if (key.length != 2) return null;
    final x = _sgfLetters.indexOf(key[0]);
    final y = _sgfLetters.indexOf(key[1]);
    if (x < 0 || y < 0 || x >= size || y >= size) return null;
    return GoMove.play(y * size + x);
  }

  /// The move as sent to the server: SGF coordinates (`"pd"`) or `"pass"`.
  String key(int size) {
    final p = point;
    if (p == null) return 'pass';
    return _sgfLetters[p % size] + _sgfLetters[p ~/ size];
  }

  /// The move as printed on a board (`"Q16"`), or `"pass"`.
  String coord(int size) {
    final p = point;
    if (p == null) return 'pass';
    return '${_humanColumns[p % size]}${size - p ~/ size}';
  }

  @override
  bool operator ==(Object other) => other is GoMove && other.point == point;

  @override
  int get hashCode => point.hashCode;

  @override
  String toString() => point == null ? 'GoMove.pass' : 'GoMove.play($point)';
}

/// Why a move cannot be played.
enum GoMoveError() {
  offBoard,
  occupied,

  /// The stone would have no liberty and would capture nothing.
  suicide,

  /// The move would bring back a previous position of the whole board (positional superko).
  ko,
}

/// Thrown by [GoPosition.play] when the move is illegal.
class const GoMoveException(final GoMoveError error) implements Exception {
  @override
  String toString() => 'GoMoveException(${error.name})';
}

/// A group of connected stones of one colour.
typedef GoGroup = ({IList<int> stones, int liberties});

/// The points next to [point] on a board of this [size].
List<int> goNeighbours(int point, int size) {
  final x = point % size;
  return [
    if (x > 0) point - 1,
    if (x < size - 1) point + 1,
    if (point >= size) point - size,
    if (point < size * size - size) point + size,
  ];
}

/// The points marked with a dot on a board of this [size].
IList<int> goStarPoints(int size) {
  final edge = size < 13 ? 2 : 3;
  final far = size - 1 - edge;
  final mid = size ~/ 2;
  int p(int x, int y) => y * size + x;
  final corners = [p(edge, edge), p(far, edge), p(edge, far), p(far, far)];
  if (size.isEven) return corners.lock;
  if (size < 13) return [p(mid, mid), ...corners].lock;
  return [...corners, p(mid, edge), p(edge, mid), p(far, mid), p(mid, far), p(mid, mid)].lock;
}

/// Where the handicap stones go, in the same order as the server places them.
IList<int> goHandicapPoints(int size, int handicap) {
  final edge = size < 13 ? 2 : 3;
  final far = size - 1 - edge;
  final mid = size ~/ 2;
  int p(int x, int y) => y * size + x;
  final tr = p(far, edge);
  final bl = p(edge, far);
  final br = p(far, far);
  final tl = p(edge, edge);
  final center = p(mid, mid);
  final left = p(edge, mid);
  final right = p(far, mid);
  final top = p(mid, edge);
  final bottom = p(mid, far);
  final h = handicap > (size == 9 ? 5 : 9) ? (size == 9 ? 5 : 9) : handicap;
  return switch (h) {
    < 2 => const IList<int>.empty(),
    2 => [tr, bl].lock,
    3 => [tr, bl, br].lock,
    4 => [tr, bl, br, tl].lock,
    5 => [tr, bl, br, tl, center].lock,
    6 => [tr, bl, br, tl, left, right].lock,
    7 => [tr, bl, br, tl, left, right, center].lock,
    8 => [tr, bl, br, tl, left, right, top, bottom].lock,
    _ => [tr, bl, br, tl, left, right, top, bottom, center].lock,
  };
}

/// The stones on a board, and who plays next.
@immutable
class const GoPosition({
  /// Number of points on each side of the board.
  required final int size,

  /// The stone on each point, row by row from the top left corner.
  required final IList<Side?> board,

  /// The side to play.
  required final Side turn,

  /// Stones captured by Black.
  final int blackPrisoners = 0,

  /// Stones captured by White.
  final int whitePrisoners = 0,

  /// The move that led to this position.
  final GoMove? lastMove,

  /// The points of the stones the last move captured.
  final IList<int> captured = const IList.empty(),

  /// Number of consecutive passes that led to this position.
  final int passes = 0,

  /// The boards of the earlier positions of the game, which may not be repeated.
  final ISet<String> seen = const ISet.empty(),
}) {
  /// The position before the first move: an empty board, or the handicap stones.
  ///
  /// Black plays first in an even game, White in a handicap game.
  factory initial(int size, {int handicap = 0}) {
    final stones = goHandicapPoints(size, handicap);
    final board = List<Side?>.filled(size * size, null);
    for (final point in stones) {
      board[point] = Side.black;
    }
    return GoPosition(
      size: size,
      board: board.lock,
      turn: stones.isEmpty ? Side.black : Side.white,
    );
  }

  /// A position from a board string sent by the server: one character per point, `.` for an
  /// empty point, `b` and `w` for stones.
  ///
  /// Throws a [FormatException] if [board] is not a square board.
  factory fromBoardString(String board, {required Side turn}) {
    final size = kGoBoardSizes.firstWhere(
      (s) => s * s == board.length,
      orElse: () => throw FormatException('Not a Go board: ${board.length} points'),
    );
    return GoPosition(
      size: size,
      board: [
        for (final char in board.split(''))
          switch (char) {
            'b' => Side.black,
            'w' => Side.white,
            '.' => null,
            _ => throw FormatException('Unknown point "$char" in a Go board'),
          },
      ].lock,
      turn: turn,
    );
  }

  /// Stones captured by [side].
  int prisoners(Side side) => side == Side.black ? blackPrisoners : whitePrisoners;

  /// Both players passed in a row: play stops and the dead stones are agreed upon.
  bool get bothPassed => passes >= 2;

  /// The board as the server writes it: `.` for an empty point, `b` and `w` for stones.
  String get boardString => board.map((stone) => stone?.stoneLetter ?? '.').join();

  /// The group of the stone on [point].
  ///
  /// Throws a [StateError] if the point is empty.
  GoGroup group(int point) {
    if (board[point] == null) throw StateError('No stone on point $point');
    return _group(board.unlockView, point, size);
  }

  /// Why [move] cannot be played here, or `null` if it is legal.
  GoMoveError? errorOf(GoMove move) {
    try {
      play(move);
      return null;
    } on GoMoveException catch (e) {
      return e.error;
    }
  }

  bool isLegal(GoMove move) => errorOf(move) == null;

  /// The position after [move].
  ///
  /// Throws a [GoMoveException] if the move is illegal.
  GoPosition play(GoMove move) {
    final point = move.point;
    if (point == null) {
      return GoPosition(
        size: size,
        board: board,
        turn: turn.opposite,
        blackPrisoners: blackPrisoners,
        whitePrisoners: whitePrisoners,
        lastMove: move,
        passes: passes + 1,
        seen: seen,
      );
    }
    if (point < 0 || point >= board.length) throw const GoMoveException(.offBoard);
    if (board[point] != null) throw const GoMoveException(.occupied);

    final next = board.toList();
    next[point] = turn;
    final taken = <int>[];
    for (final neighbour in goNeighbours(point, size)) {
      if (next[neighbour] == turn.opposite) {
        final group = _group(next, neighbour, size);
        if (group.liberties == 0) {
          for (final stone in group.stones) {
            next[stone] = null;
            taken.add(stone);
          }
        }
      }
    }
    if (taken.isEmpty && _group(next, point, size).liberties == 0) {
      throw const GoMoveException(.suicide);
    }

    final previous = boardString;
    final nextBoard = next.lock;
    final result = GoPosition(
      size: size,
      board: nextBoard,
      turn: turn.opposite,
      blackPrisoners: blackPrisoners + (turn == Side.black ? taken.length : 0),
      whitePrisoners: whitePrisoners + (turn == Side.white ? taken.length : 0),
      lastMove: move,
      captured: taken.lock,
      seen: seen.add(previous),
    );
    final hash = result.boardString;
    if (hash == previous || seen.contains(hash)) throw const GoMoveException(.ko);
    return result;
  }

  /// The point where playing is forbidden by a simple ko, if there is one: the single stone just
  /// captured, when taking back the capturing stone would repeat the previous position.
  int? get koPoint {
    if (captured.length != 1) return null;
    final point = captured.first;
    return errorOf(GoMove.play(point)) == GoMoveError.ko ? point : null;
  }
}

GoGroup _group(List<Side?> board, int point, int size) {
  final side = board[point];
  final stones = [point];
  final visited = {point};
  final liberties = <int>{};
  for (var i = 0; i < stones.length; i++) {
    for (final neighbour in goNeighbours(stones[i], size)) {
      final stone = board[neighbour];
      if (stone == null) {
        liberties.add(neighbour);
      } else if (stone == side && visited.add(neighbour)) {
        stones.add(neighbour);
      }
    }
  }
  return (stones: stones.lock, liberties: liberties.length);
}

/// Every position of a game, starting with the initial one.
///
/// [moves] are in the server's format, see [GoMove.fromKey]. Replay stops at the first move that
/// is unknown or illegal, so the result always has at least one position.
IList<GoPosition> replayGoGame({
  required int size,
  int handicap = 0,
  required Iterable<String> moves,
}) {
  final positions = [GoPosition.initial(size, handicap: handicap)];
  for (final key in moves) {
    final move = GoMove.fromKey(key, size);
    if (move == null) break;
    try {
      positions.add(positions.last.play(move));
    } on GoMoveException {
      break;
    }
  }
  return positions.lock;
}
