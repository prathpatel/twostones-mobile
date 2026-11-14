import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/game/game_storage.dart';

import '../../example_data.dart';
import '../../test_container.dart';

void main() {
  group('GameStorage', () {
    test('save and fetch data', () async {
      final container = await makeContainer();
      final storage = await container.read(gameStorageProvider.future);
      final game = generateExportedGames(count: 1, username: 'whiteId').single;

      await storage.save(game);
      final fetched = await storage.fetch(gameId: game.id);
      expect(fetched, equals(game));
      expect(fetched!.lastPosition.boardString, game.lastPosition.boardString);
    });

    test('paginate games', () async {
      final container = await makeContainer();
      final storage = await container.read(gameStorageProvider.future);

      for (final game in generateExportedGames(username: 'whiteId')) {
        await storage.save(game);
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      const userId = UserId('whiteid');
      final page1 = await storage.page(userId: userId, max: 10);
      expect(page1.length, 10);
      expect(page1.first.game.id, const GameId('game0099'));
      expect(page1.last.game.id, const GameId('game0090'));

      final page2 = await storage.page(userId: userId, max: 10, until: page1.last.lastModified);
      expect(page2.length, 10);
      expect(page2.last.game.id, const GameId('game0080'));
    });
  });
}
