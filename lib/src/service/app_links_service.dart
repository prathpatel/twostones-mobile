import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/account/ongoing_games_notifier.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/challenge/challenge_repository.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/model/user/user_repository.dart';
import 'package:lichess_mobile/src/service/challenge_service.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:lichess_mobile/src/view/user/user_or_profile_screen.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/rich_link_text.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

final _logger = Logger('AppLinks');

final appLinksServiceProvider = Provider<AppLinksService>((ref) {
  final service = AppLinksService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

class AppLinksService(final Ref ref, {AppLinks? appLinks}) {
  /// Creates the service. [appLinks] is injectable so tests can supply a fake
  /// in place of the real (singleton, platform-channel backed) [AppLinks].
  this;

  final AppLinks _appLinks = appLinks ?? AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  Future<void> start() async {
    // app_links' uriLinkStream emits the link that cold-started the app as its
    // first event, followed by any links received while the app is running, so a
    // single subscription covers both. (Also calling getInitialLink() would
    // deliver the cold-start link a second time, running its side effects twice.)
    var isColdStart = true;
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      if (isColdStart) {
        isColdStart = false;
        // The cold-start link can arrive before the first frame, so defer until
        // the navigator is ready. Push without a transition — the user launched
        // the app via this link so the target screen should just be there.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_handleUriLogged(uri, animated: false));
        });
      } else {
        // Links received while the app is already running get a normal transition.
        unawaited(_handleUriLogged(uri, animated: true));
      }
    });
  }

  Future<void> _handleUriLogged(Uri uri, {required bool animated}) async {
    try {
      await _handleUri(uri, animated: animated);
    } catch (e, st) {
      _logger.severe('Error handling app link:', e, st);
    }
  }

  Future<void> _handleUri(Uri uri, {required bool animated}) async {
    // File links are handled by the sharing intent logic, so we can ignore them here.
    if (uri.scheme == 'file' || uri.scheme == 'content') {
      return;
    }
    // Shared PGN deeplinks (from the iOS Share Extension) are handled natively by
    // SharePlugin, which reads the PGN from the shared App Group container.
    if (uri.scheme == kLichessCustomUriSchemeName && uri.host == 'shared-pgn') {
      return;
    }
    if (uri.scheme == kLichessCustomUriSchemeName && uri.host == 'open-web') {
      _handleOpenWebLink(uri);
      return;
    }
    final context = ref.read(currentNavigatorKeyProvider).currentContext;
    if (context != null && context.mounted) {
      // For app deep links, we don't want to allow falling back to the browser as it might trigger an infinite loop if the app isn't properly handling the link
      await handleAppLink(context, uri, animated: animated, allowBrowserFallback: false);
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }

  /// Resolves an app link [Uri] to one or more corresponding [Route]s.
  Future<List<Route<dynamic>>?> resolveAppLinkUri(BuildContext context, Uri appLinkUri) async {
    if (appLinkUri.pathSegments.isEmpty) return null;
    _logger.info('Resolving app link: $appLinkUri');
    switch (appLinkUri.pathSegments[0]) {
      case '@':
        if (appLinkUri.pathSegments.length > 2) {
          return null;
        }
        try {
          final user = await ref
              .read(userRepositoryProvider)
              .getUser(UserId.fromUserName(appLinkUri.pathSegments[1]));
          if (!context.mounted) return null;

          return [UserOrProfileScreen.buildRoute(user.lightUser)];
        } catch (e) {
          if (!context.mounted) return null;
          showSnackBar(
            context,
            'Cannot find user ${appLinkUri.pathSegments[1]}',
            type: SnackBarType.error,
          );
          return [];
        }
      // This might be a challenge or a game link. There's currently no API endpoint that resolves
      // both games and challenges at the same time, so check if it's a game link first, and if
      // that fails, we later check if it's a challenge link.
      case 'game':
        final gameRoutes = await _tryResolveGameLink(context, appLinkUri);
        if (gameRoutes != null) return gameRoutes;
      // Legacy /gameid link, which lila still redirects to /game/gameid. It comes after the other
      // cases so that a known route such as /training/white is never taken for a game.
      case _ when _isLegacyGameLink(appLinkUri):
        return await _tryResolveGameLink(
          context,
          appLinkUri.replace(pathSegments: ['game', ...appLinkUri.pathSegments]),
        );
    }

    return null;
  }

  /// Handles an `org.lichess.mobile://open-web?url=...` link (e.g. from the platform widget)
  /// by opening the encoded URL in the platform in-app browser.
  void _handleOpenWebLink(Uri uri) {
    final target = uri.queryParameters['url'];
    if (target != null) {
      final targetUri = Uri.tryParse(target);
      if (targetUri != null) {
        launchUrl(targetUri, mode: LaunchMode.inAppBrowserView);
      }
    }
  }

  Future<bool> _tryResolveChallengeLink(BuildContext context, Uri appLinkUri) async {
    if (appLinkUri.pathSegments.firstOrNull != 'game') return false;
    try {
      final challengeId = ChallengeId(appLinkUri.pathSegments[1]);
      if (!challengeId.isValid) return false;
      final challenge = await ref.read(challengeRepositoryProvider).show(challengeId);
      if (!context.mounted) return false;

      ref.read(challengeServiceProvider).showConfirmDialog(context, challenge, fromLink: true);

      return true;
    } catch (e, st) {
      _logger.info('Not a challenge link:', e, st);
    }
    return false;
  }

  /// Whether [appLinkUri] is a legacy `/gameid` or `/gameid/{color}` game link.
  static bool _isLegacyGameLink(Uri appLinkUri) => switch (appLinkUri.pathSegments) {
    // The length check comes first because the GameId constructor asserts it.
    [final id] || [final id, 'black' || 'white'] => id.length == 8 && GameId(id).isValid,
    _ => false,
  };

  Future<List<Route<dynamic>>?> _tryResolveGameLink(BuildContext context, Uri appLinkUri) async {
    try {
      final gameId = GameId(appLinkUri.pathSegments[1]);
      if (!gameId.isValid) return null;

      final authUser = ref.read(authControllerProvider);
      if (authUser != null) {
        try {
          final ongoingGames = await ref.read(accountRepositoryProvider).getOngoingGames(nb: 3);
          final ongoing = ongoingGames.firstWhereOrNull((g) => g.id == gameId);
          if (ongoing != null) {
            ref.invalidate(ongoingGamesProvider);
            return [
              GameScreen.buildRoute(
                source: ExistingGameSource(ongoing.fullId),
                loadingPosition: (
                  variant: ongoing.variant,
                  fen: ongoing.fen,
                  orientation: ongoing.orientation,
                  lastMove: ongoing.lastMove,
                ),
              ),
            ];
          }
        } catch (e, st) {
          _logger.warning('Failed to fetch ongoing games for $gameId', e, st);
        }
      }

      // TODO(go): open finished games in the game review screen, and other people's games in
      // the spectator screen, once they exist. Until then such links open in the browser.
    } catch (e, st) {
      _logger.info('Not a game link:', e, st);
    }

    return null;
  }

  /// Handles an app link [Uri] by navigating to the corresponding screen(s).
  Future<void> handleAppLink(
    BuildContext context,
    Uri uri, {
    bool animated = true,
    bool allowBrowserFallback = true,
  }) async {
    final routes = await resolveAppLinkUri(context, uri);
    if (!context.mounted) return;

    if (routes != null) {
      final navigator = Navigator.of(context, rootNavigator: true);
      for (final route in routes) {
        _pushDeepLinkRoute(navigator, route, animated: animated);
      }
    } else {
      final isChallengeLink = await _tryResolveChallengeLink(context, uri);
      if (isChallengeLink) return;

      if (allowBrowserFallback) {
        launchUrl(uri);
      } else {
        _logger.warning('Could not resolve app link $uri');
      }
    }
  }

  /// Pushes [route] onto [navigator], replacing the top route instead of
  /// stacking when the top is already the same screen type — preventing
  /// duplicates when the user taps a deep link while already on that screen.
  /// Also applies [_withNoTransition] when [animated] is `false`.
  static Future<void> _pushDeepLinkRoute(
    NavigatorState navigator,
    Route<dynamic> route, {
    required bool animated,
  }) {
    final pushed = animated ? route : _withNoTransition(route);
    Route<dynamic>? top;
    navigator.popUntil((r) {
      top = r;
      return true;
    });
    final topRoute = top;
    if (topRoute is ScreenRoute &&
        pushed is ScreenRoute &&
        topRoute.screen.runtimeType == pushed.screen.runtimeType) {
      return navigator.pushReplacement(pushed);
    }
    return navigator.push(pushed);
  }

  /// Returns a copy of [route] with [Duration.zero] transition so the screen
  /// appears instantly — used when the app is opened via a deep link and a
  /// transition would be jarring.
  static Route<dynamic> _withNoTransition(Route<dynamic> route) {
    if (route is ScreenRoute) {
      return MaterialScreenRoute(
        screen: route.screen,
        settings: route.settings,
        fullscreenDialog: route.fullscreenDialog,
        maintainState: route.maintainState,
        allowSnapshotting: route.allowSnapshotting,
        overrideTransitionDuration: Duration.zero,
      );
    }
    return route;
  }

  static const kLichessLinkifiers = [UrlLinkifier(), EmailLinkifier(), UserTagLinkifier()];

  /// Whether [url] is an http(s) URL whose parsed authority is exactly
  /// [kLichessHost] — a prefix match would accept hosts like `lichess.dev.evil.com`.
  static bool _isFirstPartyUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return false;
    final expected = Uri.parse('${uri.scheme}://$kLichessHost');
    return uri.host == expected.host && uri.port == expected.port;
  }

  /// Handles link clicks in RichLinkText widgets throughout the app.
  Future<void> onLinkifyOpen(BuildContext context, LinkableElement link) async {
    if (link is UrlElement && _isFirstPartyUrl(link.url)) {
      // Handle Lichess links specifically
      final appLinkUri = Uri.parse(link.url);
      await handleAppLink(context, appLinkUri);
    } else if (link.originText.startsWith('@')) {
      final username = link.originText.substring(1);
      Navigator.of(context).push(
        UserOrProfileScreen.buildRoute(
          LightUser(id: UserId.fromUserName(username), name: username),
        ),
      );
    } else {
      launchUrl(Uri.parse(link.url));
    }
  }
}
