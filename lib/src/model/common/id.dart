import 'package:deep_pick/deep_pick.dart';

extension type const StringId(String value) {
  new fromJson(dynamic json) : this(json as String);
  String toJson() => value;

  int get length => value.length;
  bool startsWith(String prefix) => value.startsWith(prefix);
}

extension type const IntId(int value);

final _gameOrChallengeIdRegex = RegExp(r'''^[\w-]{8}$''');

extension type const GameAnyId._(String value) implements StringId {
  new(this.value) : assert(value.length == 8 || value.length == 12);
  GameId get gameId => GameId(value.substring(0, 8));
  bool get isFullId => value.length == 12;
  bool get isGameId => value.length == 8;
  GameFullId? get gameFullId => isFullId ? GameFullId(value) : null;

  new fromJson(dynamic json) : this(json as String);
}

extension type const GameId._(String value) implements StringId, GameAnyId {
  const new(this.value) : assert(value.length == 8);

  bool get isValid => _gameOrChallengeIdRegex.hasMatch(value);

  new fromJson(dynamic json) : this(json as String);
}

extension type const GameFullId._(String value) implements StringId, GameAnyId {
  const new(this.value) : assert(value.length == 12);

  new fromJson(dynamic json) : this(json as String);
}

extension type const UserId(String value) implements StringId {
  new fromUserName(String userName) : this(userName.toLowerCase());
  new fromJson(dynamic json) : this(json as String);
}

extension type const ChallengeId(String value) implements StringId {
  new fromJson(dynamic json) : this(json as String);

  bool get isValid => _gameOrChallengeIdRegex.hasMatch(value);
}

extension IDPick on Pick {
  StringId asStringIdOrThrow() {
    final value = required().value;
    if (value is String) {
      return StringId(value);
    }
    throw PickException.fromPick(this, "can't be casted to StringId");
  }

  StringId? asStringIdOrNull() {
    if (value == null) return null;
    try {
      return asStringIdOrThrow();
    } catch (_) {
      return null;
    }
  }

  UserId asUserIdOrThrow() {
    final value = required().value;
    if (value is String) {
      return UserId(value);
    }
    throw PickException.fromPick(this, "can't be casted to UserId");
  }

  UserId? asUserIdOrNull() {
    if (value == null) return null;
    try {
      return asUserIdOrThrow();
    } catch (_) {
      return null;
    }
  }

  GameId asGameIdOrThrow() {
    final value = required().value;
    if (value is String) {
      return GameId(value);
    }
    throw PickException.fromPick(this, "can't be casted to GameId");
  }

  GameId? asGameIdOrNull() {
    if (value == null) return null;
    try {
      return asGameIdOrThrow();
    } catch (_) {
      return null;
    }
  }

  GameFullId asGameFullIdOrThrow() {
    final value = required().value;
    if (value is String) {
      return GameFullId(value);
    }
    throw PickException.fromPick(this, "can't be casted to GameId");
  }

  GameFullId? asGameFullIdOrNull() {
    if (value == null) return null;
    try {
      return asGameFullIdOrThrow();
    } catch (_) {
      return null;
    }
  }

  ChallengeId asChallengeIdOrThrow() {
    final value = required().value;
    if (value is String) {
      return ChallengeId(value);
    }
    throw PickException.fromPick(this, "can't be casted to ChallengeId");
  }

  ChallengeId? asChallengeIdOrNull() {
    if (value == null) return null;
    try {
      return asChallengeIdOrThrow();
    } catch (_) {
      return null;
    }
  }
}
