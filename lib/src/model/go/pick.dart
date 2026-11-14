import 'package:deep_pick/deep_pick.dart';
import 'package:lichess_mobile/src/model/go/go.dart';

extension GoPickExtension on Pick {
  Side asSideOrThrow() {
    final value = required().value;
    if (value is Side) return value;
    if (value is String) {
      final side = Side.fromName(value);
      if (side != null) return side;
    }
    throw PickException.fromPick(this, "can't be casted to Side");
  }

  Side? asSideOrNull() {
    if (value == null) return null;
    try {
      return asSideOrThrow();
    } catch (_) {
      return null;
    }
  }
}
