import 'dart:async';
import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/game/game_controller.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/socket.dart';
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/go_board.dart';
import 'package:material_ui/material_ui.dart';

import '../../model/game/game_socket_example_data.dart';
import '../../network/fake_websocket_channel.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

final _client = MockClient((request) => mockResponse('', 404));

const _gameFullId = GameFullId('qVChCOTcHSeW');
const _gameId = GameId('qVChCOTc');
final _socketUri = GameController.socketUri(_gameFullId);

/// Board preferences that play a stone as soon as a point is tapped.
final _noConfirmMove = {
  PrefCategory.board.storageKey: jsonEncode(
    BoardPrefs.defaults.copyWith(confirmMove: false).toJson(),
  ),
};

/// Board preferences that ask to confirm a stone before it is played.
final _confirmMove = {PrefCategory.board.storageKey: jsonEncode(BoardPrefs.defaults.toJson())};

/// Opens the game screen and sends the `full` event of the game.
Future<ListenableFakeWebSocketChannelFactory> _loadGame(
  WidgetTester tester, {
  required String fullEvent,
  Map<String, Object>? defaultPreferences,
}) async {
  final socketFactory = ListenableFakeWebSocketChannelFactory(createDefaultFakeWebSocketChannel);
  addTearDown(socketFactory.dispose);
  final app = await makeTestProviderScopeApp(
    tester,
    home: const GameScreen(source: ExistingGameSource(_gameFullId)),
    defaultPreferences: defaultPreferences,
    overrides: {
      lichessClientProvider: lichessClientProvider.overrideWith(
        (ref) => LichessClient(_client, ref),
      ),
      webSocketChannelFactoryProvider: webSocketChannelFactoryProvider.overrideWith(
        (ref) => socketFactory,
      ),
    },
  );
  await tester.pumpWidget(app);
  await tester.pump(kFakeWebSocketConnectionLag);
  sendServerSocketMessages(_socketUri, [fullEvent]);
  await tester.pump();
  return socketFactory;
}

/// The messages the app sends on the game socket, decoded.
List<Map<String, dynamic>> _collect(ListenableFakeWebSocketChannelFactory factory) {
  final sent = <Map<String, dynamic>>[];
  factory.outgoingMessages(_socketUri).listen((message) {
    sent.add(jsonDecode(message as String) as Map<String, dynamic>);
  });
  return sent;
}

void main() {
  group('Loading', () {
    testWidgets('shows the board and the players of the game', (tester) async {
      await _loadGame(
        tester,
        fullEvent: makeFullEvent(
          _gameId,
          const ['ee', 'cc'],
          whiteUserName: 'Peter',
          blackUserName: 'Steven',
          youAre: Side.black,
        ),
      );

      expect(find.byType(GoBoard), findsOneWidget);
      final position = getGoBoardPosition(tester);
      expect(position.size, 9);
      expect(position.board.where((stone) => stone != null).length, 2);
      expect(position.board[GoMove.fromKey('ee', 9)!.point!], Side.black);
      expect(position.board[GoMove.fromKey('cc', 9)!.point!], Side.white);
      expect(find.text('Peter'), findsOneWidget);
      expect(find.text('Steven'), findsOneWidget);
    }, variant: kPlatformVariant);

    testWidgets('a 19×19 handicap game starts with the handicap stones', (tester) async {
      await _loadGame(
        tester,
        fullEvent: makeFullEvent(
          _gameId,
          const [],
          boardSize: 19,
          handicap: 4,
          whiteUserName: 'Peter',
          blackUserName: 'Steven',
          youAre: Side.white,
        ),
      );

      final position = getGoBoardPosition(tester);
      expect(position.size, 19);
      expect(position.board.where((stone) => stone == Side.black).length, 4);
      expect(position.turn, Side.white);
    });
  });

  group('Playing', () {
    testWidgets('tapping a point plays a stone and sends it to the server', (tester) async {
      final factory = await _loadGame(
        tester,
        defaultPreferences: _noConfirmMove,
        fullEvent: makeFullEvent(
          _gameId,
          const [],
          whiteUserName: 'Peter',
          blackUserName: 'Steven',
          youAre: Side.black,
        ),
      );
      final sent = _collect(factory);

      await tapGoPoint(tester, 'E5');
      await tester.pump();

      expect(getGoBoardPosition(tester).board[GoMove.fromKey('ee', 9)!.point!], Side.black);
      final move = sent.singleWhere((message) => message['t'] == 'move');
      expect((move['d'] as Map<String, dynamic>)['m'], 'ee');
    });

    testWidgets('with move confirmation, a stone is sent once confirmed', (tester) async {
      final factory = await _loadGame(
        tester,
        defaultPreferences: _confirmMove,
        fullEvent: makeFullEvent(
          _gameId,
          const [],
          whiteUserName: 'Peter',
          blackUserName: 'Steven',
          youAre: Side.black,
        ),
      );
      final sent = _collect(factory);

      await tapGoPoint(tester, 'C3');
      await tester.pump();
      expect(sent.where((message) => message['t'] == 'move'), isEmpty);
      expect(getGoBoardPosition(tester).board[GoMove.fromKey('cg', 9)!.point!], Side.black);

      await tester.tap(find.byIcon(CupertinoIcons.checkmark_rectangle_fill));
      await tester.pump();
      final move = sent.singleWhere((message) => message['t'] == 'move');
      expect((move['d'] as Map<String, dynamic>)['m'], 'cg');
    });

    testWidgets('a stone cannot be played on an occupied point', (tester) async {
      final factory = await _loadGame(
        tester,
        defaultPreferences: _noConfirmMove,
        fullEvent: makeFullEvent(
          _gameId,
          const ['ee', 'cc'],
          whiteUserName: 'Peter',
          blackUserName: 'Steven',
          youAre: Side.black,
        ),
      );
      final sent = _collect(factory);

      await tapGoPoint(tester, 'C7');
      await tester.pump();

      expect(sent.where((message) => message['t'] == 'move'), isEmpty);
      expect(find.text('There is already a stone on this point.'), findsOneWidget);
    });

    testWidgets("the opponent's move is shown", (tester) async {
      await _loadGame(
        tester,
        fullEvent: makeFullEvent(
          _gameId,
          const ['ee'],
          whiteUserName: 'Peter',
          blackUserName: 'Steven',
          youAre: Side.black,
        ),
      );
      final after = replayGoGame(size: 9, moves: const ['ee', 'gc']).last;
      sendServerSocketMessages(_socketUri, [
        makeMoveEvent(ply: 3, move: 'gc', coord: 'G7', board: after.boardString),
      ]);
      await tester.pump();

      final position = getGoBoardPosition(tester);
      expect(position.board[GoMove.fromKey('gc', 9)!.point!], Side.white);
      expect(position.turn, Side.black);
    });

    testWidgets('passing asks for a confirmation, then sends a pass', (tester) async {
      final factory = await _loadGame(
        tester,
        fullEvent: makeFullEvent(
          _gameId,
          const ['ee', 'cc'],
          whiteUserName: 'Peter',
          blackUserName: 'Steven',
          youAre: Side.black,
        ),
      );
      final sent = _collect(factory);

      await tester.tap(find.widgetWithText(BottomBarButton, 'Pass'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pump();

      final move = sent.singleWhere((message) => message['t'] == 'move');
      expect((move['d'] as Map<String, dynamic>)['m'], 'pass');
    });
  });

  group('Counting', () {
    const scoring = '''
{
  "dead": [],
  "accepted": [],
  "score": {
    "black": 45, "white": 43.5, "komi": 7.5, "result": "B+1.5",
    "territory": {"black": 36, "white": 27}, "stones": {"black": 9, "white": 9},
    "ownership": [[0, 1], [8, 2]]
  }
}''';

    testWidgets('after two passes, the count is shown and can be accepted', (tester) async {
      final factory = await _loadGame(
        tester,
        fullEvent: makeFullEvent(
          _gameId,
          const ['ee', 'cc', 'pass', 'pass'],
          whiteUserName: 'Peter',
          blackUserName: 'Steven',
          youAre: Side.black,
          scoring: scoring,
        ),
      );
      final sent = _collect(factory);

      expect(find.textContaining('B+1.5', findRichText: true), findsOneWidget);
      final board = tester.widget<GoBoard>(find.byType(GoBoard));
      expect(board.territory[0], Side.black);
      expect(board.territory[8], Side.white);

      // tapping a stone marks its group dead
      await tapGoPoint(tester, 'C7');
      expect(sent.any((message) => message['t'] == 'scoring-toggle' && message['d'] == 20), isTrue);

      await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
      await tester.pump();
      expect(sent.any((message) => message['t'] == 'scoring-accept'), isTrue);
    });

    testWidgets('a game finished by counting shows its result', (tester) async {
      await _loadGame(
        tester,
        fullEvent: makeFullEvent(
          _gameId,
          const ['ee', 'cc', 'pass', 'pass'],
          whiteUserName: 'Peter',
          blackUserName: 'Steven',
          youAre: Side.black,
          statusId: 60,
          statusName: 'variantEnd',
          winner: Side.black,
          scoring: scoring,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('B+1.5'), findsOneWidget);
      expect(find.text('Black wins by counting'), findsOneWidget);
    });
  });

  group('Clock', () {
    testWidgets('the clocks of both players are shown', (tester) async {
      await _loadGame(
        tester,
        fullEvent: makeFullEvent(
          _gameId,
          const ['ee', 'cc'],
          whiteUserName: 'Peter',
          blackUserName: 'Steven',
          youAre: Side.black,
          clock: (
            running: true,
            initial: const Duration(minutes: 3),
            increment: const Duration(seconds: 2),
            emerg: const Duration(seconds: 30),
            white: const Duration(minutes: 2, seconds: 58),
            black: const Duration(minutes: 2, seconds: 30),
          ),
        ),
      );

      expect(find.text('2:58', findRichText: true), findsOneWidget);
      expect(find.text('2:30', findRichText: true), findsOneWidget);
      // let the running clock tick out of the test
      await tester.pump(const Duration(seconds: 1));
      unawaited(Future<void>.value());
    });
  });
}
