import 'dart:math' as math;

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/binding/binding.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/game/game.dart';
import 'package:lichess_mobile/src/model/game/playable_game.dart';
import 'package:lichess_mobile/src/model/lobby/game_setup_preferences.dart';
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';
import 'package:lichess_mobile/src/model/user/user.dart';

part 'game_seek.freezed.dart';
part 'game_seek.g.dart';

/// A seek is a request to play a game with a specific board size, time control and rating range.
@Freezed(fromJson: true, toJson: true)
sealed class const GameSeek._() with _$GameSeek {
  @Assert(
    'ratingDelta == null || ratingRange == null',
    'Rating delta and rating range cannot be used together',
  )
  @Assert('clock != null || days != null', 'Either clock or days must be set')
  const factory({
    (Duration time, Duration increment)? clock,
    int? days,
    required bool rated,

    /// Number of lines on each side of the board: 9, 13 or 19.
    @Default(kDefaultBoardSize) int boardSize,

    /// Rating range
    (int, int)? ratingRange,

    /// Rating delta to apply to the user's current rating.
    (int, int)? ratingDelta,
  }) = _GameSeek;

  /// Construct a fast pairing game seek from a predefined time control.
  factory fastPairing(TimeIncrement setup, AuthUser? authUser, {required int boardSize}) {
    return GameSeek(
      boardSize: boardSize,
      clock: (Duration(seconds: setup.time), Duration(seconds: setup.increment)),
      rated: authUser != null,
    );
  }

  /// Construct a game seek from saved [GameSetupPrefs], using all the custom params.
  factory custom(GameSetupPrefs setup, User? account) {
    return GameSeek(
      clock: (
        Duration(seconds: setup.timeIncrement.time),
        Duration(seconds: setup.timeIncrement.increment),
      ),
      rated: account != null && setup.customRated,
      boardSize: setup.boardSize,
      ratingRange: account != null ? setup.realTimeRatingRange(account) : null,
    );
  }

  /// Construct a correspondence seek from saved [GameSetupPrefs].
  factory correspondence(GameSetupPrefs setup, User? account) {
    return GameSeek(
      days: setup.customDaysPerTurn,
      rated: account != null && setup.customRated,
      boardSize: setup.boardSize,
      ratingRange: account != null ? setup.correspondenceRatingRange(account) : null,
    );
  }

  /// Construct a game seek from a playable game to find a new opponent, using
  /// the same board size, time control and rated status.
  factory newOpponentFromGame(PlayableGame game, GameSetupPrefs setup) {
    return GameSeek(
      clock: game.meta.clock != null
          ? (game.meta.clock!.initial, game.meta.clock!.increment)
          : null,
      rated: game.meta.rated,
      boardSize: game.meta.boardSize,
      ratingDelta: game.source == GameSource.lobby ? setup.customRatingDelta : null,
    );
  }

  /// Returns a copy of this seek with the rating range set to the user's
  /// current rating +/- the rating delta.
  GameSeek withRatingRangeOf(User user) {
    if (ratingDelta == null) return this;
    final userPerf = user.perfs[perf];
    if (userPerf == null) return this;
    if (userPerf.provisional == true) return this;
    final min = math.max(0, userPerf.rating + ratingDelta!.$1);
    final max = userPerf.rating + ratingDelta!.$2;
    final range = (min, max);
    return copyWith(ratingRange: range, ratingDelta: null);
  }

  TimeIncrement? get timeIncrement =>
      clock != null ? TimeIncrement(clock!.$1.inSeconds, clock!.$2.inSeconds) : null;

  Perf get perf => Perf.fromSpeed(
    timeIncrement != null ? Speed.fromTimeIncrement(timeIncrement!) : Speed.correspondence,
  );

  /// The fields of the lobby form of the server (`POST /setup/hook/:sri`).
  Map<String, String> get requestBody => {
    'size': boardSize.toString(),
    // 1 is a real time game, 2 a correspondence game
    'timeMode': clock != null ? '1' : '2',
    'time': ((clock?.$1.inSeconds ?? 300) / 60).toString(),
    'increment': (clock?.$2.inSeconds ?? 0).toString(),
    'days': (days ?? 2).toString(),
    'mode': rated ? '1' : '0',
    if (ratingRange != null) 'ratingRange': '${ratingRange!.$1}-${ratingRange!.$2}',
  };

  factory fromJson(Map<String, dynamic> json) => _$GameSeekFromJson(json);
}

/// The response to a game seek request.
///
/// It can be either a [GameSeekCreated] or a [GameSeekCancelled].
sealed class GameSeekResponse();

/// A game has been created from the seek.
@freezed
sealed class GameSeekCreated with _$GameSeekCreated implements GameSeekResponse {
  const factory({required GameFullId fullId}) = _GameSeekCreated;
}

/// A game seek has been cancelled.
@freezed
sealed class GameSeekCancelled with _$GameSeekCancelled implements GameSeekResponse {
  const factory() = _GameSeekCancelled;
}

@Freezed(fromJson: true, toJson: true)
sealed class const RecentGameSeekPrefs._() with _$RecentGameSeekPrefs implements Serializable {
  const factory({required IList<GameSeek> seeks}) = _RecentGameSeekPrefs;

  factory fromJson(Map<String, dynamic> json) => _$RecentGameSeekPrefsFromJson(json);

  static const empty = RecentGameSeekPrefs(seeks: IListConst([]));

  RecentGameSeekPrefs copyWithAdded(GameSeek newRequest) {
    final updated = [newRequest, ...seeks.where((r) => r != newRequest)];
    return copyWith(seeks: IList(updated.take(3).toList()));
  }
}

/// A provider that manages recent game seeks preferences.
final recentGameSeekProvider = NotifierProvider<RecentGameSeek, RecentGameSeekPrefs>(
  RecentGameSeek.new,
  name: 'RecentGameSeekProvider',
);

class RecentGameSeek()
    extends Notifier<RecentGameSeekPrefs>
    with PreferencesStorage<RecentGameSeekPrefs> {
  @override
  @protected
  final prefCategory = PrefCategory.gameSeeks;

  @override
  RecentGameSeekPrefs fromJson(Map<String, dynamic> json) {
    return RecentGameSeekPrefs.fromJson(json);
  }

  @override
  @protected
  RecentGameSeekPrefs get defaults => RecentGameSeekPrefs.empty;

  @override
  RecentGameSeekPrefs build() {
    return fetch();
  }

  Future<void> addSeek(GameSeek seek) async {
    final updated = state.copyWithAdded(seek);
    await save(updated);
  }

  Future<void> clearRequests() async {
    await LichessBinding.instance.sharedPreferences.remove(prefCategory.storageKey);
    if (!ref.mounted) return;
    state = RecentGameSeekPrefs.empty;
  }
}
