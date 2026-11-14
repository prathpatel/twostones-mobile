import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/view/user/user_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../model/auth/fake_auth_storage.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

MockClient _makeClient(String userResponse) => MockClient((request) {
  if (request.url.path == '/api/user/$testUserId') {
    return mockResponse(userResponse, 200);
  }
  if (request.url.path == '/api/mobile/games/user/$testUserId') {
    return mockResponse(recentGamesResponse, 200);
  }
  if (request.url.path == '/api/users/status') {
    return mockResponse('[{"id": "$testUserId", "name": "$testUserName", "online": true}]', 200);
  }
  return mockResponse('', 404);
});

final client = _makeClient(userResponse);

final clientCannotChallenge = _makeClient(userResponseCannotChallenge);

void main() {
  group('UserScreen', () {
    testWidgets('should see the profile and recent games', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const UserScreen(user: testUser),
        overrides: {
          lichessClientProvider: lichessClientProvider.overrideWith(
            (ref) => LichessClient(client, ref),
          ),
        },
      );

      await tester.pumpWidget(app);

      // wait for user request
      await tester.pump(const Duration(milliseconds: 50));

      // full name at the top
      expect(find.text('John Doe'), findsOneWidget);

      // wait for recent games
      await tester.pump(const Duration(milliseconds: 50));

      // below the profile and rating cards
      await tester.scrollUntilVisible(
        find.text('Recent games').hitTestable(),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Recent games'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('opponent').hitTestable(),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('opponent'), findsOneWidget);
    }, variant: kPlatformVariant);

    testWidgets('Challenge action is hidden when canChallenge is null (own profile case)', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const UserScreen(user: testUser),
        authUser: fakeAuthUser,
        overrides: {
          lichessClientProvider: lichessClientProvider.overrideWith(
            (ref) => LichessClient(client, ref),
          ),
        },
      );

      await tester.pumpWidget(app);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Challenge'), findsNothing);
    });

    testWidgets(
      'Challenge action is visible but shows a toast when the user does not accept challenges',
      (WidgetTester tester) async {
        final app = await makeTestProviderScopeApp(
          tester,
          home: const UserScreen(user: testUser),
          authUser: fakeAuthUser,
          overrides: {
            lichessClientProvider: lichessClientProvider.overrideWith(
              (ref) => LichessClient(clientCannotChallenge, ref),
            ),
          },
        );

        await tester.pumpWidget(app);
        await tester.pump(const Duration(milliseconds: 100));

        // Button stays visible (web parity) so the reason can be explained.
        await tester.scrollUntilVisible(
          find.text('Challenge').hitTestable(),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Challenge'), findsOneWidget);

        await tester.tap(find.text('Challenge'));
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text('$testUserName does not accept challenges.'),
          ),
          findsOneWidget,
        );
      },
    );
  });
}

const testUserName = 'FakeUserName';
const testUserId = UserId('fakeusername');
const testUser = LightUser(id: testUserId, name: testUserName);
const _userJson =
    '''
"id": "$testUserId",
"username": "$testUserName",
"createdAt": 1290415680000,
"seenAt": 1290415680000,
"profile": {"realName": "John Doe", "bio": "I play Go."},
"perfs": {
  "blitz": {"games": 12, "rating": 1720, "rd": 60, "prog": 12},
  "rapid": {"games": 30, "rating": 1810, "rd": 50, "prog": -4}
},
"count": {"all": 42, "rated": 40, "win": 22, "loss": 20, "draw": 0, "bookmark": 0, "playing": 0, "me": 0}
''';

const userResponse = '{$_userJson}';

const userResponseCannotChallenge = '{$_userJson, "canChallenge": false}';

const recentGamesResponse =
    '''
{"id": "Qa7FJNk2", "rated": true, "speed": "blitz", "perf": "blitz", "size": 19, "handicap": 0, "komi": 7.5, "createdAt": 1756425600000, "lastMoveAt": 1756426600000, "status": "resign", "winner": "black", "players": {"black": {"user": {"id": "$testUserId", "name": "$testUserName"}, "rating": 1720}, "white": {"user": {"id": "opponent", "name": "opponent"}, "rating": 1700}}, "clock": {"initial": 300, "increment": 3, "totalTime": 420}}
''';
