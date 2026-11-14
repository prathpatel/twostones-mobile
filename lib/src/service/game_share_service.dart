import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/network/http.dart';

/// A provider for [GameShareService].
final gameShareServiceProvider = Provider<GameShareService>((Ref ref) {
  return GameShareService(ref);
}, name: 'GameShareServiceProvider');

class GameShareService(final Ref _ref) {
  /// Fetches the record of a game in SGF, the file format every Go program reads.
  Future<String> sgf(GameId id) async {
    final resp = await _ref.withClient(
      (client) => client.get(Uri(path: '/game/export/$id')).timeout(const Duration(seconds: 5)),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to get SGF');
    }
    return utf8.decode(resp.bodyBytes);
  }
}
