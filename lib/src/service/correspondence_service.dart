import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/notifications/notifications.dart';
import 'package:lichess_mobile/src/service/notification_service.dart';
import 'package:lichess_mobile/src/tab_navigation.dart' show currentNavigatorKeyProvider;
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';

/// A provider for [CorrespondenceService].
final correspondenceServiceProvider = Provider<CorrespondenceService>((Ref ref) {
  final service = CorrespondenceService(ref: ref);
  ref.onDispose(() => service.dispose());
  return service;
}, name: 'CorrespondenceServiceProvider');

/// Opens a correspondence game when the player taps the notification of a move played in it.
class CorrespondenceService({required final Ref ref}) {
  StreamSubscription<ParsedLocalNotification>? _notificationResponseSubscription;

  void start() {
    _notificationResponseSubscription = NotificationService.responseStream.listen((data) {
      final (_, notification) = data;
      switch (notification) {
        case CorresGameUpdateNotification(:final fullId):
          _onNotificationResponse(fullId);
        case _:
          break;
      }
    });
  }

  void dispose() {
    _notificationResponseSubscription?.cancel();
  }

  /// Handles a notification response that caused the app to open.
  Future<void> _onNotificationResponse(GameFullId fullId) async {
    final context = ref.read(currentNavigatorKeyProvider).currentContext;
    if (context == null || !context.mounted) return;

    final rootNavState = Navigator.of(context, rootNavigator: true);
    if (rootNavState.canPop()) {
      rootNavState.popUntil((route) => route.isFirst);
    }

    Navigator.of(
      context,
      rootNavigator: true,
    ).push(GameScreen.buildRoute(source: ExistingGameSource(fullId)));
  }
}
