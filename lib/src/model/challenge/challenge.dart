import 'package:deep_pick/deep_pick.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/model/common/game.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/lobby/game_setup_preferences.dart' show kDefaultBoardSize;
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/utils/json.dart';

part 'challenge.freezed.dart';
part 'challenge.g.dart';

abstract mixin class BaseChallenge() {
  /// Number of lines on each side of the board: 9, 13 or 19.
  int get boardSize;

  /// Number of stones Black starts with, 0 for an even game.
  int get handicap;
  Speed get speed;
  ChallengeTimeControlType get timeControl;
  ({Duration time, Duration increment})? get clock;
  int? get days;
  bool get rated;
  SideChoice get sideChoice;

  TimeIncrement? get timeIncrement =>
      clock != null ? TimeIncrement(clock!.time.inSeconds, clock!.increment.inSeconds) : null;

  Perf get perf => Perf.fromSpeed(
    timeIncrement != null ? Speed.fromTimeIncrement(timeIncrement!) : Speed.correspondence,
  );
}

/// A challenge already created server-side.
@Freezed(fromJson: true, toJson: true)
sealed class const Challenge._() with _$Challenge, BaseChallenge implements BaseChallenge {
  const factory({
    int? socketVersion,
    required ChallengeId id,
    GameFullId? gameFullId,
    required ChallengeStatus status,
    @Default(kDefaultBoardSize) int boardSize,
    @Default(0) int handicap,
    required Speed speed,
    required ChallengeTimeControlType timeControl,
    required bool rated,
    ({Duration time, Duration increment})? clock,
    int? days,
    required SideChoice sideChoice,
    ChallengeUser? challenger,
    ChallengeUser? destUser,
    ChallengeDeclineReason? declineReason,
    ChallengeDirection? direction,
    GameId? rematchOf,
  }) = _Challenge;

  factory fromJson(Map<String, dynamic> json) => _$ChallengeFromJson(json);

  factory fromServerJson(Map<String, dynamic> json) {
    return _challengeFromPick(pick(json).required());
  }

  factory fromPick(RequiredPick pick) => _challengeFromPick(pick);

  /// The description of the challenge.
  String description(AppLocalizations l10n) {
    final time = switch (timeControl) {
      ChallengeTimeControlType.clock => () {
        final minutes = switch (clock!.time.inSeconds) {
          15 => '¼',
          30 => '½',
          45 => '¾',
          90 => '1.5',
          _ => clock!.time.inMinutes,
        };
        return '$minutes+${clock!.increment.inSeconds}';
      }(),
      ChallengeTimeControlType.correspondence => '${l10n.daysPerTurn}: $days',
      ChallengeTimeControlType.unlimited => '∞',
    };

    final board = '$boardSize×$boardSize';
    final handicapStr = handicap > 0 ? ' • H$handicap' : '';

    // the colour the player who receives the challenge would play
    final sideStone = sideChoice == SideChoice.black
        ? '○ '
        : sideChoice == SideChoice.white
        ? '● '
        : '';

    final side = sideChoice == SideChoice.black
        ? l10n.white
        : sideChoice == SideChoice.white
        ? l10n.black
        : l10n.randomColor;

    final mode = rated ? l10n.rated : l10n.casual;

    return '$sideStone$side • $board$handicapStr • $mode • $time';
  }

  bool get isOpenOrRealTime => timeControl == ChallengeTimeControlType.clock || destUser == null;
}

/// A challenge request to play a game with another user.
@freezed
sealed class const ChallengeRequest._()
    with _$ChallengeRequest, BaseChallenge
    implements BaseChallenge {
  const factory({
    // If null, it's an open challenge that anyone (even anonymous users) can accept.
    LightUser? destUser,
    @Default(kDefaultBoardSize) int boardSize,
    @Default(0) int handicap,
    required ChallengeTimeControlType timeControl,
    ({Duration time, Duration increment})? clock,
    int? days,
    required bool rated,
    required SideChoice sideChoice,
  }) = _ChallengeRequest;

  @override
  Speed get speed => Speed.fromTimeIncrement(
    TimeIncrement(
      clock != null ? clock!.time.inSeconds : 0,
      clock != null ? clock!.increment.inSeconds : 0,
    ),
  );

  Map<String, dynamic> get toRequestBody {
    // The fields of the challenge form of the server (`POST /setup/friend`).
    return {
      'size': boardSize.toString(),
      'handicap': handicap.toString(),
      // 1 is a real time game, 2 a correspondence game, 0 a game without time limit
      'timeMode': switch (timeControl) {
        ChallengeTimeControlType.clock => '1',
        ChallengeTimeControlType.correspondence => '2',
        ChallengeTimeControlType.unlimited => '0',
      },
      'time': ((clock?.time.inSeconds ?? 300) / 60).toString(),
      'increment': (clock?.increment.inSeconds ?? 0).toString(),
      'days': (days ?? 2).toString(),
      // handicap games cannot be rated
      'mode': rated && handicap == 0 ? '1' : '0',
      'color': sideChoice.name,
    };
  }

  bool get isOpenOrRealTime => timeControl == ChallengeTimeControlType.clock || destUser == null;
}

/// The user response of a challenge request.
///
/// It can be:
/// - [ChallengeResponseCancelled]: The challenge was cancelled.
/// - [ChallengeResponseAccepted]: The challenge was accepted and a game was created.
/// - [ChallengeResponseDeclined]: The challenge was declined.
sealed class ChallengeResponse();

/// The [ChallengeResponse] when challenge was cancelled.
@freezed
sealed class ChallengeResponseCancelled
    with _$ChallengeResponseCancelled
    implements ChallengeResponse {
  const factory() = _ChallengeResponseCancelled;
}

/// The [ChallengeResponse] when challenge was accepted and a game was created.
@freezed
sealed class ChallengeResponseAccepted
    with _$ChallengeResponseAccepted
    implements ChallengeResponse {
  const factory({required GameFullId gameFullId}) = _ChallengeResponseAccepted;
}

/// The [ChallengeResponse] when challenge was declined.
@freezed
sealed class ChallengeResponseDeclined
    with _$ChallengeResponseDeclined
    implements ChallengeResponse {
  const factory({required Challenge challenge, required ChallengeDeclineReason? declineReason}) =
      _ChallengeResponseDeclined;
}

enum ChallengeDirection() {
  outward,
  inward,
}

enum ChallengeStatus() {
  created,
  offline,
  canceled,
  declined,
  accepted,
}

enum ChallengeTimeControlType() {
  unlimited,
  clock,
  correspondence;

  String label(AppLocalizations l10n) => switch (this) {
    ChallengeTimeControlType.unlimited => l10n.unlimited,
    ChallengeTimeControlType.clock => l10n.clock,
    ChallengeTimeControlType.correspondence => l10n.correspondence,
  };
}

enum ChallengeDeclineReason() {
  generic,
  later,
  tooFast,
  tooSlow,
  timeControl,
  rated,
  casual,
  standard,
  variant,
  noBot,
  onlyBot;

  String label(AppLocalizations l10n) => switch (this) {
    ChallengeDeclineReason.generic => l10n.challengeDeclineGeneric,
    ChallengeDeclineReason.later => l10n.challengeDeclineLater,
    ChallengeDeclineReason.tooFast => l10n.challengeDeclineTooFast,
    ChallengeDeclineReason.tooSlow => l10n.challengeDeclineTooSlow,
    ChallengeDeclineReason.timeControl => l10n.challengeDeclineTimeControl,
    ChallengeDeclineReason.rated => l10n.challengeDeclineRated,
    ChallengeDeclineReason.casual => l10n.challengeDeclineCasual,
    ChallengeDeclineReason.standard => l10n.challengeDeclineStandard,
    ChallengeDeclineReason.variant => l10n.challengeDeclineVariant,
    ChallengeDeclineReason.noBot => l10n.challengeDeclineNoBot,
    ChallengeDeclineReason.onlyBot => l10n.challengeDeclineOnlyBot,
  };
}

typedef ChallengeUser = ({LightUser user, int? rating, bool? provisionalRating, int? lagRating});

extension ChallengeExtension on Pick {
  ChallengeDirection asChallengeDirectionOrThrow() {
    final value = this.required().value;
    if (value is ChallengeDirection) {
      return value;
    }
    if (value is String) {
      switch (value) {
        case 'outward' || 'out':
          return ChallengeDirection.outward;
        case 'inward' || 'in':
          return ChallengeDirection.inward;
        default:
          throw PickException.fromPick(
            this,
            "can't be casted to ChallengeDirection",
            detail: 'invalid string',
          );
      }
    }
    throw PickException.fromPick(this, "can't be casted to ChallengeDirection");
  }

  ChallengeDirection? asChallengeDirectionOrNull() {
    if (value == null) return null;
    try {
      return asChallengeDirectionOrThrow();
    } catch (_) {
      return null;
    }
  }

  ChallengeStatus asChallengeStatusOrThrow() {
    final value = this.required().value;
    if (value is ChallengeStatus) {
      return value;
    }
    if (value is String) {
      switch (value) {
        case 'created':
          return ChallengeStatus.created;
        case 'offline':
          return ChallengeStatus.offline;
        case 'canceled':
          return ChallengeStatus.canceled;
        case 'declined':
          return ChallengeStatus.declined;
        case 'accepted':
          return ChallengeStatus.accepted;
        default:
          throw PickException.fromPick(
            this,
            "can't be casted to ChallengeStatus",
            detail: 'invalid string',
          );
      }
    }
    throw PickException.fromPick(this, "can't be casted to ChallengeStatus");
  }

  ChallengeStatus? asChallengeStatusOrNull() {
    if (value == null) return null;
    try {
      return asChallengeStatusOrThrow();
    } catch (_) {
      return null;
    }
  }

  ChallengeTimeControlType asChallengeTimeControlTypeOrThrow() {
    final value = this.required().value;
    if (value is ChallengeTimeControlType) {
      return value;
    }
    if (value is String) {
      switch (value) {
        case 'unlimited':
          return ChallengeTimeControlType.unlimited;
        case 'clock':
          return ChallengeTimeControlType.clock;
        case 'correspondence':
          return ChallengeTimeControlType.correspondence;
        default:
          throw PickException.fromPick(
            this,
            "can't be casted to ChallengeTimeControlType",
            detail: 'invalid string',
          );
      }
    }
    throw PickException.fromPick(this, "can't be casted to ChallengeTimeControlType");
  }

  ChallengeTimeControlType? asChallengeTimeControlTypeOrNull() {
    if (value == null) return null;
    try {
      return asChallengeTimeControlTypeOrThrow();
    } catch (_) {
      return null;
    }
  }

  SideChoice asSideChoiceOrThrow() {
    final value = this.required().value;
    if (value is SideChoice) {
      return value;
    }
    if (value is String) {
      switch (value) {
        case 'random':
          return SideChoice.random;
        case 'white':
          return SideChoice.white;
        case 'black':
          return SideChoice.black;
        default:
          throw PickException.fromPick(
            this,
            "can't be casted to SideChoice",
            detail: 'invalid string',
          );
      }
    }
    throw PickException.fromPick(this, "can't be casted to SideChoice");
  }

  SideChoice? asSideChoiceOrNull() {
    if (value == null) return null;
    try {
      return asSideChoiceOrThrow();
    } catch (_) {
      return null;
    }
  }

  ChallengeDeclineReason asDeclineReasonOrThrow() {
    final value = this.required().value;
    if (value is ChallengeDeclineReason) {
      return value;
    }
    if (value is String) {
      return ChallengeDeclineReason.values.firstWhere(
        (element) => element.name.toLowerCase() == value,
        orElse: () => throw PickException.fromPick(
          this,
          "can't be casted to ChallengeDeclineReason",
          detail: 'invalid string',
        ),
      );
    }
    throw PickException.fromPick(this, "can't be casted to ChallengeDeclineReason");
  }

  ChallengeDeclineReason? asDeclineReasonOrNull() {
    if (value == null) return null;
    try {
      return asDeclineReasonOrThrow();
    } catch (_) {
      return null;
    }
  }
}

Challenge _challengeFromPick(RequiredPick pick) {
  return Challenge(
    socketVersion: pick('socketVersion').asIntOrNull(),
    id: pick('id').asChallengeIdOrThrow(),
    gameFullId: pick('fullId').asGameFullIdOrNull(),
    status: pick('status').asChallengeStatusOrThrow(),
    boardSize: pick('size').asIntOrNull() ?? kDefaultBoardSize,
    handicap: pick('handicap').asIntOrNull() ?? 0,
    speed: pick('speed').asSpeedOrThrow(),
    timeControl: pick('timeControl', 'type').asChallengeTimeControlTypeOrThrow(),
    clock: pick('timeControl').letOrThrow((clockPick) {
      final time = clockPick('limit').asDurationFromSecondsOrNull();
      final increment = clockPick('increment').asDurationFromSecondsOrNull();
      return time != null && increment != null ? (time: time, increment: increment) : null;
    }),
    days: pick('timeControl', 'daysPerTurn').asIntOrNull(),
    rated: pick('rated').asBoolOrThrow(),
    sideChoice: pick('color').asSideChoiceOrThrow(),
    challenger: pick('challenger').letOrNull((challengerPick) {
      final challengerUser = pick('challenger').asLightUserOrThrow();
      return (
        user: challengerUser,
        rating: challengerPick('rating').asIntOrNull(),
        provisionalRating: challengerPick('provisional').asBoolOrNull(),
        lagRating: challengerPick('lag').asIntOrNull(),
      );
    }),
    destUser: pick('destUser').letOrNull((destPick) {
      final destUser = pick('destUser').asLightUserOrThrow();
      return (
        user: destUser,
        rating: destPick('rating').asIntOrNull(),
        provisionalRating: destPick('provisional').asBoolOrNull(),
        lagRating: destPick('lag').asIntOrNull(),
      );
    }),
    direction: pick('direction').asChallengeDirectionOrNull(),
    declineReason: pick('declineReasonKey').asDeclineReasonOrNull(),
    rematchOf: pick('rematchOf').asGameIdOrNull(),
  );
}
