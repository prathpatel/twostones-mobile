import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/styles/icon_extensions.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/play/correspondence_challenges_screen.dart';
import 'package:lichess_mobile/src/view/play/create_challenge_bottom_sheet.dart';
import 'package:lichess_mobile/src/view/play/create_game_widget.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:material_ui/material_ui.dart';

class const PlayMenu({
  /// The navigator where the screens are pushed, by default the navigator of the menu.
  ///
  /// In a sheet on the root navigator, the navigator of the screen that presents it, so that the
  /// screens are pushed in the current tab and hide the tab bar there.
  final NavigatorState? navigator,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionStatus = ref.watch(lichessConnectionStatusProvider);
    final navigator = this.navigator ?? Navigator.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: CreateGameWidget(navigator: navigator),
        ),
        _Section(
          children: [
            ListTile(
              enabled: connectionStatus == LichessConnectionStatus.online,
              onTap: () {
                // Pops the play bottom sheet
                Navigator.of(context).popUntil((route) => route is! PopupRoute);
                showAdaptiveBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useRootNavigator: true,
                  builder: (_) => CreateChallengeBottomSheet(navigator: navigator),
                );
              },
              leading: const Icon(Icons.person),
              title: Text(context.l10n.challengeAFriend),
            ),
            ListTile(
              enabled: connectionStatus == LichessConnectionStatus.online,
              onTap: () {
                // Pops the play bottom sheet
                Navigator.of(context).popUntil((route) => route is! PopupRoute);
                navigator.pushHidingTabBar(CorrespondenceChallengesScreen.buildRoute());
              },
              leading: Icon(Perf.correspondence.icon),
              title: Text(context.l10n.correspondence),
            ),
          ],
        ),
      ],
    );
  }
}

class const _Section({required final List<Widget> children}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListSection(hasLeading: true, materialFilledCard: true, children: children);
  }
}
