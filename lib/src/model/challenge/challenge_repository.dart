import 'dart:async';

import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/challenge/challenge.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/network/aggregator.dart';
import 'package:lichess_mobile/src/network/http.dart';

/// A provider for [ChallengeRepository].
final challengeRepositoryProvider = Provider<ChallengeRepository>((Ref ref) {
  return ChallengeRepository(ref.watch(lichessClientProvider), ref.watch(aggregatorProvider));
}, name: 'ChallengeRepositoryProvider');

typedef ChallengesList = ({IList<Challenge> inward, IList<Challenge> outward});

class const ChallengeRepository(final LichessClient client, final Aggregator aggregator) {
  Future<ChallengesList> list() {
    final uri = Uri(path: '/api/challenge');
    return aggregator.readJson(
      uri,
      atomicMapper: (json) {
        final listPick = pick(json).required();
        final inward = listPick('in').asListOrEmpty(Challenge.fromPick);
        final outward = listPick('out').asListOrEmpty(Challenge.fromPick);

        return (inward: inward.lock, outward: outward.lock);
      },
    );
  }

  Future<Challenge> show(ChallengeId id) {
    final uri = Uri(path: '/api/challenge/$id/show');
    return client.readJson(uri, mapper: Challenge.fromServerJson);
  }

  Future<Challenge> create(ChallengeRequest challengeReq) {
    final uri = Uri(
      path: '/setup/friend',
      queryParameters: {if (challengeReq.destUser != null) 'user': challengeReq.destUser!.id.value},
    );
    // The server answers with the challenge and the version of its socket. An open challenge
    // (without a destination user) is accepted by whoever opens its link: the side of its creator
    // is already in the request body.
    return client.postReadJson(
      uri,
      headers: {'Accept': 'application/json'},
      body: challengeReq.toRequestBody,
      mapper: (json) => Challenge.fromServerJson({
        ...json['challenge'] as Map<String, dynamic>,
        'socketVersion': json['socketVersion'],
      }),
    );
  }

  Future<void> accept(ChallengeId id, {Side? side}) async {
    final uri = Uri(
      path: '/challenge/$id/accept',
      queryParameters: {if (side != null) 'color': side.name},
    );
    await client.postRead(uri, headers: {'Accept': 'application/json'});
  }

  Future<void> decline(ChallengeId id, {ChallengeDeclineReason? reason}) async {
    final uri = Uri(path: '/challenge/$id/decline');
    await client.postRead(uri, body: reason != null ? {'reason': reason.name} : null);
  }

  Future<void> cancel(ChallengeId id) async {
    final uri = Uri(path: '/challenge/$id/cancel');
    await client.postRead(uri);
  }

  Future<void> rematchOfGame(GameId id) async {
    // don't add an /api/ prefix here; it's a web route, not an API endpoint
    await client.postRead(Uri(path: '/challenge/rematch-of/$id'));
  }
}
