import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/network/aggregator.dart';
import 'package:lichess_mobile/src/network/http.dart';

import '../test_container.dart';
import 'fake_http_client_factory.dart';
import 'http_test.dart';

void main() {
  setUp(() {
    FakeClient.reset();
  });

  Future<Aggregator> fakeClientAggregator() async {
    final container = await makeContainer(
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
          return FakeHttpClientFactory(() => FakeClient());
        }),
      },
    );
    return await container.read(aggregatorProvider);
  }

  final String aggrInterval = '${kAggregationInterval.inMilliseconds}ms';

  group('Aggregator', () {
    test(
      'if only one request is made within $aggrInterval, it will make an atomic request',
      () async {
        final aggregator = await fakeClientAggregator();
        final uri = Uri(path: '/api/test');

        final response = await aggregator.readJson(uri, atomicMapper: (data) => data);

        final requests = FakeClient.verifyRequests();
        expect(requests.length, 1);
        expect(requests.first.url.path, uri.path);
        expect(response, isNotNull);
      },
    );

    test(
      'non supported uris will not aggregate and make atomic request after $aggrInterval',
      () async {
        final aggregator = await fakeClientAggregator();

        final uri1 = Uri(path: '/api/test1');
        final uri2 = Uri(path: '/api/test2');

        fakeAsync((async) {
          aggregator.readJson(uri1, atomicMapper: (data) => data);
          aggregator.readJson(uri2, atomicMapper: (data) => data);

          async.elapse(kAggregationInterval);

          // Check that the requests were made separately
          final requests = FakeClient.verifyRequests();
          expect(requests.length, 2);
        });
      },
    );

    test('requests of the home screen are made separately', () async {
      final aggregator = await fakeClientAggregator();

      fakeAsync((async) {
        aggregator.readJson(Uri(path: '/api/account'), atomicMapper: (data) => data);
        aggregator.readJson(Uri(path: '/api/account/playing'), atomicMapper: (data) => data);
        aggregator.readJson(Uri(path: '/api/challenge'), atomicMapper: (data) => data);
        aggregator.readJson(Uri(path: '/inbox/unread-count'), atomicMapper: (data) => data);

        async.elapse(kAggregationInterval);

        final requests = FakeClient.verifyRequests();
        expect(requests.map((r) => r.url.path), [
          '/api/account',
          '/api/account/playing',
          '/api/challenge',
          '/inbox/unread-count',
        ]);
      });
    });
  });
}
