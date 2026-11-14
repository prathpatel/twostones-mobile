import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/game/exported_game.dart';
import 'package:lichess_mobile/src/model/game/game_filter.dart';
import 'package:lichess_mobile/src/model/game/game_storage.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/network/aggregator.dart';
import 'package:lichess_mobile/src/network/http.dart';

/// A provider for the [GameRepository].
final gameRepositoryProvider = Provider<GameRepository>((ref) {
  final client = ref.watch(lichessClientProvider);
  final aggregator = ref.watch(aggregatorProvider);
  final gameStorage = ref.watch(gameStorageProvider.future);
  return GameRepository(client, aggregator, gameStorage);
}, name: 'GameRepositoryProvider');

class const GameRepository(
  final LichessClient client,
  final Aggregator aggregator,
  final Future<GameStorage> storage,
) {
  /// Fetches a game from lichess API, or from local storage if there is no connectivity.
  Future<ExportedGame> getGame(GameId id, {bool withBookmarked = false}) async {
    try {
      return await client.readJson(
        Uri(
          path: '/api/mobile/game/$id',
          queryParameters: {if (withBookmarked) 'withBookmarked': '1'},
        ),
        headers: {'Accept': 'application/json'},
        mapper: (json) => ExportedGame.fromServerJson(json, withBookmarked: withBookmarked),
      );
    } on ServerException {
      rethrow;
      // Catches other exceptions like no connectivity
    } on Exception {
      final storedGame = await (await storage).fetch(gameId: id);
      if (storedGame != null) {
        return storedGame;
      }
      throw Exception('Game $id cannot be found in local storage.');
    }
  }

  Future<IList<LightExportedGameWithPov>> getUserGames(
    UserId userId, {
    int max = 20,
    DateTime? until,
    GameFilterState filter = const GameFilterState(),
    bool withBookmarked = false,
  }) {
    return aggregator
        .readNdJsonList(
          Uri(
            path: '/api/mobile/games/user/$userId',
            queryParameters: {
              'max': max.toString(),
              if (until != null) 'until': until.millisecondsSinceEpoch.toString(),
              if (filter.perfs.isNotEmpty)
                'perfType': filter.perfs.map((perf) => perf.name).join(','),
              if (filter.side != null) 'color': filter.side!.name,
              if (filter.opponent != null) 'vs': filter.opponent!.id.value,
              if (withBookmarked) 'withBookmarked': 'true',
            },
          ),
          headers: {'Accept': 'application/x-ndjson'},
          mapper: (json) => LightExportedGame.fromServerJson(json, withBookmarked: withBookmarked),
        )
        .then(
          (value) => value
              .map(
                (e) => (
                  game: e,
                  // we know here user is not null for at least one of the players
                  pov: e.white.user?.id == userId ? Side.white : Side.black,
                ),
              )
              .toIList(),
        );
  }

  Future<IList<LightExportedGameWithPov>> getBookmarkedGames(
    AuthUser authUser, {
    int max = 20,
    DateTime? until,
  }) {
    return client
        .readNdJsonList(
          Uri(
            path: '/api/mobile/games/bookmarks',
            queryParameters: {
              'max': max.toString(),
              if (until != null) 'until': until.millisecondsSinceEpoch.toString(),
            },
          ),
          headers: {'Accept': 'application/x-ndjson'},
          mapper: (json) => LightExportedGame.fromServerJson(json, isBookmarked: true),
        )
        .then(
          (value) => value
              .map(
                (e) => (
                  game: e,
                  // we know here user is not null for at least one of the players
                  pov: e.white.user?.id == authUser.user.id ? Side.white : Side.black,
                ),
              )
              .toIList(),
        );
  }

  Future<IList<LightExportedGame>> getGamesByIds(ISet<GameId> ids) {
    return client.postReadNdJsonList(
      Uri(path: '/api/mobile/games/ids'),
      headers: {'Accept': 'application/x-ndjson'},
      body: ids.join(','),
      mapper: LightExportedGame.fromServerJson,
    );
  }
}
