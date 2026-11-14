import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/lobby/game_seek.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/socket.dart';
import 'package:lichess_mobile/src/service/create_game_service.dart';

import '../model/auth/fake_auth_storage.dart';
import '../network/fake_http_client_factory.dart';
import '../network/fake_websocket_channel.dart';
import '../test_container.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const seek = GameSeek(clock: (Duration(minutes: 5), Duration.zero), rated: false);

  group('cancelSeek', () {
    test('is a no-op when there is no active lobby seek', () async {
      final deleteRequests = <http.Request>[];
      final mockClient = MockClient((request) async {
        if (request.method == 'DELETE') deleteRequests.add(request);
        return http.Response('', 200);
      });

      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
        },
      );

      await container.read(createGameServiceProvider).cancelSeek();

      expect(deleteRequests, isEmpty);
    });

    test('cancels the active seek on the lobby socket', () async {
      final requests = <http.Request>[];
      final mockClient = MockClient((request) async {
        requests.add(request);
        return http.Response('', 200);
      });
      final socketFactory = ListenableFakeWebSocketChannelFactory(
        createDefaultFakeWebSocketChannel,
      );
      addTearDown(socketFactory.dispose);
      final sent = <String>[];
      socketFactory
          .outgoingMessages(Uri(path: '/lobby/socket/v5'))
          .listen((message) => sent.add(message as String));

      final container = await makeContainer(
        authUser: fakeAuthUser,
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
          webSocketChannelFactoryProvider: webSocketChannelFactoryProvider.overrideWith(
            (ref) => socketFactory,
          ),
        },
      );

      // keep the service alive while the seek is pending
      container.listen(createGameServiceProvider, (_, _) {});
      final service = container.read(createGameServiceProvider);
      final response = service.newLobbyGame(seek);
      await Future<void>.delayed(kFakeWebSocketConnectionLag * 4);

      expect(requests.map((request) => request.url.path), contains(startsWith('/setup/hook/')));

      await service.cancelSeek();
      await Future<void>.delayed(kFakeWebSocketConnectionLag * 2);

      expect(await response, isA<GameSeekCancelled>());
      expect(sent, contains('{"t":"cancel"}'));
      expect(requests.where((request) => request.method == 'DELETE'), isEmpty);
    });
  });
}
