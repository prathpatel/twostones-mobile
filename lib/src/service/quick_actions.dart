import 'dart:io';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/localizations.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/lobby/game_seek.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quick_actions/quick_actions.dart';

/// Provider for the [QuickActionService].
final quickActionServiceProvider = Provider<QuickActionService>((Ref ref) {
  final service = QuickActionService(ref);
  ref.listen<RecentGameSeekPrefs>(recentGameSeekProvider, (previous, next) {
    if (previous?.seeks == next.seeks) return;
    service.setQuickActions(next.seeks);
  });
  return service;
});

class QuickActionService(final Ref ref) {
  AppLocalizations get l10n => ref.read(localizationsProvider).strings;

  final QuickActions quickActions = const QuickActions();

  void start() {
    final recentSeeks = ref.read(recentGameSeekProvider).seeks;
    quickActions.initialize((String shortcutType) {
      final context = ref.read(currentNavigatorKeyProvider).currentContext;
      if (context == null || !context.mounted) return;

      if (shortcutType.startsWith('recent_seek_')) {
        final index = int.tryParse(shortcutType.split('_').last);
        if (index != null) {
          Navigator.of(
            context,
            rootNavigator: true,
          ).push(GameScreen.buildRoute(source: LobbySource(recentSeeks[index])));
        }
      }
    });
    setQuickActions(recentSeeks);
  }

  void setQuickActions(IList<GameSeek> recentSeeks) {
    quickActions.setShortcutItems(<ShortcutItem>[
      ...recentSeeks.asMap().entries.map((entry) {
        final index = entry.key;
        final seek = entry.value;

        final time = seek.clock != null ? seek.clock!.$1.inMinutes.toString() : '-';
        final increment = seek.clock != null ? seek.clock!.$2.inSeconds.toString() : '0';
        final rated = seek.rated ? l10n.ratedTournament : l10n.casualTournament;

        final variant = (seek.variant == Variant.standard)
            ? ''
            : (seek.variant != null && seek.timeIncrement != null)
            ? ' • ${Perf.fromVariantAndSpeed(seek.variant!, Speed.fromTimeIncrement(seek.timeIncrement!)).shortLabel(l10n)}'
            : '';

        return ShortcutItem(
          type: 'recent_seek_$index',
          localizedTitle: '$time+$increment $rated$variant',
          localizedSubtitle: l10n.recentGames,
          icon: Platform.isIOS ? 'PlusIcon' : 'add_icon',
        );
      }),
    ]);
  }
}
