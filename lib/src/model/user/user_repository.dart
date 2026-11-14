import 'dart:convert';

import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/game/exported_game.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/model/user/leaderboard.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/network/aggregator.dart';
import 'package:lichess_mobile/src/network/http.dart';

/// A provider for the [UserRepository].
final userRepositoryProvider = Provider<UserRepository>((ref) {
  final client = ref.watch(lichessClientProvider);
  final aggregator = ref.watch(aggregatorProvider);
  return UserRepository(client, aggregator);
}, name: 'UserRepositoryProvider');

typedef UserScreenData = ({
  User user,
  IList<LightExportedGameWithPov> recentGames,
  bool? isOnline,
  bool? isPlayingLive,
  Crosstable? crosstable,
});

class UserRepository(final LichessClient client, final Aggregator aggregator) {
  /// Everything the screen of a user shows.
  ///
  /// The profile is required. What comes with it is fetched at the same time and left out when it
  /// cannot be: the recent games, whether the user is online or playing, and the score against the
  /// logged in user of id [me].
  Future<UserScreenData> getUserScreenData(UserId id, {UserId? me}) async {
    final userFuture = getUser(id, withCanChallenge: true);
    final gamesFuture = client
        .readNdJsonList(
          Uri(path: '/api/mobile/games/user/$id', queryParameters: {'max': '10'}),
          headers: {'Accept': 'application/x-ndjson'},
          mapper: LightExportedGame.fromServerJson,
        )
        .then<IList<LightExportedGame>?>((games) => games)
        .catchError((Object _) => null);
    final statusFuture = getUsersStatuses({id}.lock)
        .then<UserStatus?>((statuses) => statuses.firstOrNull)
        .catchError((Object _) => null);
    final crosstableFuture = me != null && me != id
        ? getCrosstable(me, id).then<Crosstable?>((c) => c).catchError((Object _) => null)
        : Future<Crosstable?>.value();

    final user = await userFuture;
    final games = await gamesFuture;
    final status = await statusFuture;
    return (
      user: user,
      recentGames: (games ?? const IList<LightExportedGame>.empty())
          .map((game) => (game: game, pov: game.white.user?.id == id ? Side.white : Side.black))
          .toIList(),
      isOnline: status?.online,
      isPlayingLive: status?.playing,
      crosstable: await crosstableFuture,
    );
  }

  Future<User> getUser(UserId id, {bool withCanChallenge = false}) {
    return client.readJson(
      Uri(path: '/api/user/$id', queryParameters: withCanChallenge ? {'challenge': 'true'} : null),
      mapper: User.fromServerJson,
    );
  }

  Future<IList<UserStatus>> getUsersStatuses(ISet<UserId> ids) {
    return client.readJsonList(
      Uri(path: '/api/users/status', queryParameters: {'ids': ids.join(',')}),
      mapper: UserStatus.fromJson,
    );
  }

  Future<Crosstable> getCrosstable(UserId id1, UserId id2, {bool matchup = false}) {
    return client.readJson(
      Uri(path: '/api/crosstable/$id1/$id2', queryParameters: {'matchup': matchup.toString()}),
      mapper: Crosstable.fromJson,
    );
  }

  Future<IMap<Perf, LeaderboardUser>> getTop1() {
    return client.readJson(Uri(path: '/api/player/top/1/standard'), mapper: _top1FromJson);
  }

  Future<Leaderboard> getLeaderboard() {
    return client.readJson(Uri(path: '/api/player'), mapper: _leaderboardFromJson);
  }

  Future<IList<LightUser>> autocompleteUser(String term) {
    return client.readJson(
      Uri(
        path: '/api/player/autocomplete',
        queryParameters: {'term': term, 'friend': '1', 'object': '1'},
      ),
      mapper: _autocompleteFromJson,
    );
  }

  /// Whether [username] is an existing lichess account.
  Future<bool> usernameExists(String username) async {
    final term = username.toLowerCase();
    // TODO use a dedicated endpoint if/when it becomes available.
    final body = await client.read(
      Uri(path: '/api/player/autocomplete', queryParameters: {'term': term}),
    );
    final names = jsonDecode(body) as List<dynamic>;

    // Completions are prefix matches, so the name is only known if one comes back verbatim.
    return names.any((name) => name is String && name == term);
  }

  Future<IList<UserRatingHistoryPerf>> getRatingHistory(UserId id) {
    return client.readJsonList(
      Uri(path: '/api/user/$id/rating-history'),
      mapper: _ratingHistoryFromJson,
    );
  }
}

UserRatingHistoryPerf? _ratingHistoryFromJson(Map<String, dynamic> json) =>
    _ratingHistoryFromPick(pick(json).required());

UserRatingHistoryPerf? _ratingHistoryFromPick(RequiredPick pick) {
  final perf = pick('name').asPerfOrNull();

  if (perf == null) {
    return null;
  }

  return UserRatingHistoryPerf(
    perf: perf,
    points: pick('points').asListOrThrow((point) {
      final values = point.asListOrThrow((point) => point.asIntOrThrow());
      return UserRatingHistoryPoint(
        date: DateTime.utc(values[0], values[1] + 1, values[2]),
        elo: values[3],
      );
    }).toIList(),
  );
}

// --
IList<LightUser> _autocompleteFromJson(Map<String, dynamic> json) =>
    _autocompleteFromPick(pick(json).required());

IList<LightUser> _autocompleteFromPick(RequiredPick pick) {
  return pick('result').asListOrThrow((userPick) => userPick.asLightUserOrThrow()).toIList();
}

Leaderboard _leaderboardFromJson(Map<String, dynamic> json) =>
    _leaderBoardFromPick(pick(json).required());

Leaderboard _leaderBoardFromPick(RequiredPick pick) {
  return Leaderboard(
    bullet: pick('bullet').asListOrEmpty(_leaderboardUserFromPick),
    blitz: pick('blitz').asListOrEmpty(_leaderboardUserFromPick),
    rapid: pick('rapid').asListOrEmpty(_leaderboardUserFromPick),
    classical: pick('classical').asListOrEmpty(_leaderboardUserFromPick),
    ultrabullet: pick('ultraBullet').asListOrEmpty(_leaderboardUserFromPick),
  );
}

LeaderboardUser _leaderboardUserFromPick(RequiredPick pick) {
  final prefMap = pick('perfs').asMapOrThrow<String, Map<String, dynamic>>();

  return LeaderboardUser(
    id: pick('id').asUserIdOrThrow(),
    username: pick('username').asStringOrThrow(),
    title: pick('title').asStringOrNull(),
    flair: pick('flair').asStringOrNull(),
    patronColor: pick('patronColor').asIntOrNull(),
    online: pick('online').asBoolOrNull(),
    rating: pick('perfs')
        .letOrThrow((perfsPick) => perfsPick(prefMap.keys.first, 'rating'))
        .asIntOrThrow(),
    progress: pick('perfs')
        .letOrThrow((prefsPick) => prefsPick(prefMap.keys.first, 'progress'))
        .asIntOrThrow(),
  );
}

IMap<Perf, LeaderboardUser> _top1FromJson(Map<String, dynamic> json) {
  final map = pick(json).asMapOrEmpty<String, Map<String, dynamic>>();
  return IMap({
    for (final entry in map.entries)
      if (Perf.nameMap.containsKey(entry.key))
        Perf.nameMap.get(entry.key)!: _top1userFromPick(
          pick(map[entry.key]).required(),
          Perf.nameMap.get(entry.key)!,
        ),
  });
}

LeaderboardUser _top1userFromPick(RequiredPick pick, Perf perf) {
  return LeaderboardUser(
    id: pick('id').asUserIdOrThrow(),
    username: pick('username').asStringOrThrow(),
    title: pick('title').asStringOrNull(),
    flair: pick('flair').asStringOrNull(),
    patronColor: pick('patronColor').asIntOrNull(),
    rating: pick('perfs', perf.name, 'rating').asIntOrThrow(),
    progress: pick('perfs', perf.name, 'progress').asIntOrThrow(),
  );
}
