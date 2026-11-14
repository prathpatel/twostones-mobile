import 'package:collection/collection.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:lichess_mobile/src/widgets/go_board.dart';
import 'package:lichess_mobile/src/widgets/move_list.dart';
import 'package:material_ui/material_ui.dart';

/// Layout for game screens that adapts to screen size and aspect ratio
///
/// On portrait mode, the board will be displayed in the middle of the screen,
/// with the table spaces on top and bottom.
/// On landscape mode, the board will be displayed on the left side of the screen,
/// with the table spaces on the right side.
///
/// An optional move list can be displayed above the top table space.
///
/// An optional overlay or error message can be displayed on top of the board.
class const GameLayout({
  /// The stones to show on the board.
  required final GoPosition position,

  /// Called with the index of the point that was tapped. Taps are ignored when it is null.
  final ValueChanged<int>? onTapPoint,

  /// A point where playing is forbidden by a ko.
  final int? koPoint,

  /// Stones marked dead during the counting phase.
  final ISet<int> deadStones = const ISet.empty(),

  /// The side each point counts for during the counting phase.
  final IMap<int, Side> territory = const IMap.empty(),

  /// Widget that will appear at the top of the board.
  final Widget topTable = const SizedBox.shrink(),

  /// Widget that will appear at the bottom of the board.
  final Widget bottomTable = const SizedBox.shrink(),

  /// Optional list of moves that will be displayed on top of the board.
  final List<String>? moves,

  /// Index of the current move in the [moves] list.
  final int currentMoveIndex = 0,

  /// Callback that will be called when a move is selected from the [moves] list.
  final void Function(int moveIndex)? onSelectMove,

  /// Optional widget that will be displayed on top of the board.
  final Widget? boardOverlay,

  /// Optional error message that will be displayed on top of the board.
  final String? errorMessage,

  /// [GlobalKey] for the board.
  ///
  /// Used to set gestures exclusion on android.
  final GlobalKey? boardKey,

  /// If true, the move list will be hidden
  final bool zenMode = false,

  /// Optional widget that contains various user actions, usually a `BottomBar`.
  /// Displayed below the board, or below the move list if landscape mode is used.
  final Widget? userActionsBar,
  super.key,
}) extends ConsumerWidget {
  /// Creates a game layout with an empty board of [boardSize] lines (useful for loading).
  new empty({int boardSize = 19, String? errorMessage, Key? key})
    : this(position: GoPosition.initial(boardSize), errorMessage: errorMessage, key: key);

  Widget _moveList(MoveListType type) => MoveList(
    type: type,
    slicedMoves: moves!.asMap().entries.slices(2),
    currentMoveIndex: currentMoveIndex,
    onSelectMove: onSelectMove,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardPrefs = ref.watch(boardPreferencesProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final orientation = constraints.maxWidth > constraints.maxHeight
            ? Orientation.landscape
            : Orientation.portrait;
        final isTablet = isTabletOrLarger(context);

        Widget board(double size) => _Board(
          key: boardKey,
          size: size,
          position: position,
          onTapPoint: onTapPoint,
          koPoint: koPoint,
          deadStones: deadStones,
          territory: territory,
          showCoordinates: boardPrefs.coordinates,
          showLastMove: boardPrefs.boardHighlights,
          rounded: isTablet,
          overlay: boardOverlay,
          errorMessage: errorMessage,
        );

        if (orientation == Orientation.landscape) {
          final defaultBoardSize =
              constraints.biggest.shortestSide - (kTabletBoardTableSidePadding * 2);
          final sideWidth = constraints.biggest.longestSide - defaultBoardSize;
          final boardSize = sideWidth >= 250
              ? defaultBoardSize
              : constraints.biggest.longestSide / kGoldenRatio - (kTabletBoardTableSidePadding * 2);

          return Padding(
            padding: const EdgeInsets.all(kTabletBoardTableSidePadding),
            child: Row(
              textDirection: switch (boardPrefs.landscapeBoardPosition) {
                .left => TextDirection.ltr,
                .right => TextDirection.rtl,
              },
              mainAxisSize: MainAxisSize.max,
              children: [
                board(boardSize),
                const SizedBox(width: 16.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      topTable,
                      if (boardPrefs.moveListDisplay && !zenMode && moves != null)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16.0),
                            child: _moveList(MoveListType.stacked),
                          ),
                        )
                      else
                        const Spacer(),
                      if (userActionsBar != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: userActionsBar,
                        ),
                      bottomTable,
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          final defaultBoardSize = constraints.biggest.shortestSide;
          final maxHeight = constraints.maxHeight;

          final isShortScreen = isShortVerticalScreen(context);

          double effectiveBoardSize = isTablet
              ? defaultBoardSize - kTabletBoardTableSidePadding * 2
              : defaultBoardSize;

          // Reserve vertical space for the top and bottom tables and the user actions bar.
          final maxAllowedBoardSize = maxHeight - 180.0;
          if (effectiveBoardSize > maxAllowedBoardSize) {
            effectiveBoardSize = maxAllowedBoardSize;
          }

          if (isShortScreen) {
            effectiveBoardSize -= 16;
          }

          return Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (boardPrefs.moveListDisplay && moves != null && !isShortScreen)
                if (zenMode)
                  // display empty move list to keep the layout consistent in zen mode
                  const MoveList(type: MoveListType.inline, slicedMoves: [], currentMoveIndex: 0)
                else
                  _moveList(MoveListType.inline),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? kTabletBoardTableSidePadding : 12.0,
                  ),
                  child: topTable,
                ),
              ),
              Padding(
                padding: isTablet
                    ? const EdgeInsets.symmetric(horizontal: kTabletBoardTableSidePadding)
                    : EdgeInsets.zero,
                child: board(effectiveBoardSize),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? kTabletBoardTableSidePadding : 12.0,
                  ),
                  child: bottomTable,
                ),
              ),
              ?userActionsBar,
            ],
          );
        }
      },
    );
  }
}

/// The board of a [GameLayout], with what is shown above it: an overlay or an error message.
class const _Board({
  required final double size,
  required final GoPosition position,
  required final ValueChanged<int>? onTapPoint,
  required final int? koPoint,
  required final ISet<int> deadStones,
  required final IMap<int, Side> territory,
  required final bool showCoordinates,
  required final bool showLastMove,
  required final bool rounded,
  required final Widget? overlay,
  required final String? errorMessage,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final board = GoBoard(
      size: size,
      position: position,
      onTapPoint: onTapPoint,
      koPoint: koPoint,
      deadStones: deadStones,
      territory: territory,
      showCoordinates: showCoordinates,
      showLastMove: showLastMove,
    );
    final error = errorMessage;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: .center,
        children: [
          if (rounded)
            DecoratedBox(
              decoration: BoxDecoration(boxShadow: boardShadows),
              child: ClipRRect(borderRadius: Styles.boardBorderRadius, child: board),
            )
          else
            board,
          ?overlay,
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ColorScheme.of(context).errorContainer,
                  borderRadius: const BorderRadius.all(Radius.circular(8.0)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                  child: Text(
                    error,
                    textAlign: .center,
                    style: TextStyle(color: ColorScheme.of(context).onErrorContainer),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
