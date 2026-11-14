import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/lobby/correspondence_seek.dart';
import 'package:lichess_mobile/src/model/lobby/game_seek.dart';
import 'package:lichess_mobile/src/network/http.dart';

final correspondenceSeeksProvider =
    AsyncNotifierProvider.autoDispose<CorrespondenceSeeks, IList<CorrespondenceSeek>>(
      CorrespondenceSeeks.new,
      name: 'CorrespondenceSeeksProvider',
    );

class CorrespondenceSeeks() extends AsyncNotifier<IList<CorrespondenceSeek>> {
  @override
  Future<IList<CorrespondenceSeek>> build() {
    return ref.withClient((client) => LobbyRepository(client).getCorrespondenceSeeks());
  }

  /// Fetches the seeks again, bypassing the HTTP cache, while the current list stays available.
  ///
  /// Use it when the list is known to have changed, or when the user asks for a refresh.
  Future<void> reload() async {
    final result = await AsyncValue.guard(
      () => ref.withClient(
        (client) => LobbyRepository(client).getCorrespondenceSeeks(bypassCache: true),
      ),
    );
    if (ref.mounted) {
      state = result;
    }
  }
}

class LobbyRepository(final LichessClient client) {
  /// Puts a seek in the lobby of the server, for the lobby socket of id [sri].
  ///
  /// When an opponent takes it, the lobby socket receives a `redirect` event with the game.
  Future<void> createSeek(GameSeek seek, {required String sri}) async {
    final uri = Uri(path: '/setup/hook/$sri');
    await client.postRead(uri, body: seek.requestBody);
  }

  /// Fetches the current correspondence seeks.
  ///
  /// The server sends this response with a `Cache-Control` max-age, so the platform HTTP cache
  /// serves a stale list right after a seek is created or removed. With [bypassCache], a unique
  /// query parameter bypasses it.
  Future<IList<CorrespondenceSeek>> getCorrespondenceSeeks({bool bypassCache = false}) {
    return client.readJsonList(
      Uri(
        path: '/lobby/seeks',
        queryParameters: bypassCache
            ? {'_': DateTime.now().millisecondsSinceEpoch.toString()}
            : null,
      ),
      headers: {'Accept': 'application/vnd.lichess.v5+json'},
      mapper: CorrespondenceSeek.fromServerJson,
    );
  }
}
