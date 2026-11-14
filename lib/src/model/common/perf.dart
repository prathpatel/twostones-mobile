import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';

/// Represents a lichess rating perf item
enum Perf(final String title, final String shortTitle) {
  ultraBullet('UltraBullet', 'Ultra'),
  bullet('Bullet', 'Bullet'),
  blitz('Blitz', 'Blitz'),
  rapid('Rapid', 'Rapid'),
  classical('Classical', 'Classical'),
  correspondence('Correspondence', 'Corresp.');

  String label(AppLocalizations l10n) {
    switch (this) {
      case Perf.ultraBullet:
        return l10n.ultraBullet;
      case Perf.bullet:
        return l10n.bullet;
      case Perf.blitz:
        return l10n.blitz;
      case Perf.rapid:
        return l10n.rapid;
      case Perf.classical:
        return l10n.classical;
      case Perf.correspondence:
        return l10n.correspondence;
    }
  }

  String shortLabel(AppLocalizations l10n) {
    switch (this) {
      case Perf.ultraBullet:
        return l10n.mobilePerfShortUltraBullet;
      case Perf.bullet:
        return l10n.mobilePerfShortBullet;
      case Perf.blitz:
        return l10n.mobilePerfShortBlitz;
      case Perf.rapid:
        return l10n.mobilePerfShortRapid;
      case Perf.classical:
        return l10n.mobilePerfShortClassical;
      case Perf.correspondence:
        return l10n.mobilePerfShortCorrespondence;
    }
  }

  /// The rating category of a game: on TwoStones there is one per speed.
  factory fromSpeed(Speed speed) => switch (speed) {
    Speed.ultraBullet => Perf.ultraBullet,
    Speed.bullet => Perf.bullet,
    Speed.blitz => Perf.blitz,
    Speed.rapid => Perf.rapid,
    Speed.classical => Perf.classical,
    Speed.correspondence => Perf.correspondence,
  };

  static final IMap<String, Perf> nameMap = IMap(Perf.values.asNameMap());
}

String _titleKey(String title) => title.toLowerCase().replaceAll(RegExp('[ -_]'), '');

final IMap<String, Perf> _lowerCaseTitleMap = Perf.nameMap.map(
  (key, value) => MapEntry(_titleKey(value.title), value),
);

extension PerfExtension on Pick {
  Perf asPerfOrThrow() {
    final value = required().value;
    if (value is Perf) {
      return value;
    }
    if (value is String) {
      if (Perf.nameMap.containsKey(value)) {
        return Perf.nameMap[value]!;
      }
      // handle lichess api inconsistencies
      final valueKey = _titleKey(value);
      if (_lowerCaseTitleMap.containsKey(valueKey)) {
        return _lowerCaseTitleMap[valueKey]!;
      }
    } else if (value is Map<String, dynamic>) {
      final perf = Perf.nameMap[value['key'] as String];
      if (perf != null) {
        return perf;
      }
    }
    throw PickException.fromPick(this, "can't be casted to Perf");
  }

  Perf? asPerfOrNull() {
    if (value == null) return null;
    try {
      return asPerfOrThrow();
    } catch (_) {
      return null;
    }
  }
}
