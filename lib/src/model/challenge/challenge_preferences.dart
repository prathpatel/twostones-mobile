import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/challenge/challenge.dart';
import 'package:lichess_mobile/src/model/common/game.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/lobby/game_setup_preferences.dart' show kDefaultBoardSize;
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';
import 'package:lichess_mobile/src/model/user/user.dart';

part 'challenge_preferences.freezed.dart';
part 'challenge_preferences.g.dart';

final challengePreferencesProvider = NotifierProvider<ChallengePreferences, ChallengePrefs>(
  ChallengePreferences.new,
  name: 'ChallengePreferencesProvider',
);

class ChallengePreferences()
    extends Notifier<ChallengePrefs>
    with SessionPreferencesStorage<ChallengePrefs> {
  @override
  @protected
  PrefCategory get prefCategory => PrefCategory.challenge;

  @override
  ChallengePrefs defaults({LightUser? user}) => ChallengePrefs.defaults;

  @override
  ChallengePrefs fromJson(Map<String, dynamic> json) => ChallengePrefs.fromJson(json);

  @override
  ChallengePrefs build() {
    return fetch();
  }

  Future<void> setBoardSize(int boardSize) {
    return save(state.copyWith(boardSize: boardSize));
  }

  Future<void> setHandicap(int handicap) {
    return save(state.copyWith(handicap: handicap));
  }

  Future<void> setTimeControl(ChallengeTimeControlType timeControl) {
    return save(state.copyWith(timeControl: timeControl));
  }

  Future<void> setClock(Duration time, Duration increment) {
    return save(state.copyWith(clock: (time: time, increment: increment)));
  }

  Future<void> setDays(int days) {
    return save(state.copyWith(days: days));
  }

  Future<void> setSideChoice(SideChoice sideChoice) {
    return save(state.copyWith(sideChoice: sideChoice));
  }

  Future<void> setRated(bool rated) {
    return save(state.copyWith(rated: rated));
  }
}

@Freezed(fromJson: true, toJson: true)
sealed class const ChallengePrefs._() with _$ChallengePrefs implements Serializable {
  const factory({
    @Default(kDefaultBoardSize) int boardSize,
    @Default(0) int handicap,
    required ChallengeTimeControlType timeControl,
    required ({Duration time, Duration increment}) clock,
    required int days,
    required bool rated,
    required SideChoice sideChoice,
  }) = _ChallengePrefs;

  static const defaults = ChallengePrefs(
    timeControl: ChallengeTimeControlType.clock,
    clock: (time: Duration(minutes: 10), increment: Duration.zero),
    days: 3,
    rated: true,
    sideChoice: SideChoice.random,
  );

  Speed get speed => timeControl == ChallengeTimeControlType.clock
      ? Speed.fromTimeIncrement(TimeIncrement(clock.time.inSeconds, clock.increment.inSeconds))
      : Speed.correspondence;

  /// Handicap games and games without a time limit cannot be rated.
  bool get isRatedAllowed => handicap == 0 && timeControl != ChallengeTimeControlType.unlimited;

  ChallengeRequest makeRequest(User? challengingUser, LightUser? destUser) {
    return ChallengeRequest(
      destUser: destUser,
      boardSize: boardSize,
      handicap: handicap,
      timeControl: timeControl,
      clock: timeControl == ChallengeTimeControlType.clock ? clock : null,
      days: timeControl == ChallengeTimeControlType.correspondence ? days : null,
      // Anonymous users cannot create rated challenges.
      rated: challengingUser != null && isRatedAllowed && rated,
      sideChoice: sideChoice,
    );
  }

  factory fromJson(Map<String, dynamic> json) {
    try {
      return _$ChallengePrefsFromJson(json);
    } catch (_) {
      return ChallengePrefs.defaults;
    }
  }
}
