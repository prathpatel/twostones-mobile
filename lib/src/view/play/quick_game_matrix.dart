import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/model/lobby/game_seek.dart';
import 'package:lichess_mobile/src/model/lobby/game_setup_preferences.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:lichess_mobile/src/view/play/play_bottom_sheet.dart';
import 'package:lichess_mobile/src/view/play/playban.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/platform_segmented_control.dart';
import 'package:material_ui/material_ui.dart';

const _kMatrixSpacing = 8.0;

class const QuickGameMatrix({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playban = ref.watch(accountProvider).value?.playban;
    final brightness = Theme.of(context).brightness;
    final logoColor = brightness == Brightness.light
        ? const Color(0x0F000000)
        : const Color(0x80FFFFFF);
    final scaffoldOpacity = Theme.of(context).scaffoldBackgroundColor.a;

    if (playban != null) {
      return PlaybanMessage(playban: playban);
    }

    final boardSize = ref.watch(gameSetupPreferencesProvider.select((prefs) => prefs.boardSize));
    final choices = TimeIncrement.quickPairings[boardSize] ?? TimeIncrement.quickPairings[19]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.quickPairing, style: Styles.sectionTitle),
        const SizedBox(height: 6.0),
        SizedBox(
          width: double.infinity,
          child: PlatformSegmentedControl<int>(
            segments: [for (final size in kGoBoardSizes) (size, '$size×$size')],
            selected: boardSize,
            onChanged: (size) => ref.read(gameSetupPreferencesProvider.notifier).setBoardSize(size),
          ),
        ),
        const SizedBox(height: _kMatrixSpacing),
        Container(
          decoration: scaffoldOpacity != 0
              ? BoxDecoration(
                  image: DecorationImage(
                    colorFilter: ColorFilter.mode(logoColor, BlendMode.modulate),
                    image: const AssetImage('assets/images/logo-transp.webp'),
                    fit: BoxFit.contain,
                  ),
                )
              : null,
          child: Column(
            children: [
              _SectionChoices(choices: choices, boardSize: boardSize),
              const SizedBox(height: _kMatrixSpacing),
              _SectionChoices(choices: const [], boardSize: boardSize, showCustom: true),
            ],
          ),
        ),
      ],
    );
  }
}

class const _SectionChoices({
  required final List<TimeIncrement> choices,
  required final int boardSize,
  final bool showCustom = false,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUser = ref.watch(authControllerProvider);
    final connectionStatus = ref.watch(lichessConnectionStatusProvider);
    final choiceWidgets = choices
        .mapIndexed((index, choice) {
          return [
            Expanded(
              child: _ChoiceChip(
                key: ValueKey(choice),
                title: Text(
                  choice.display,
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 20.0),
                ),
                subtitle: Text(
                  choice.speed.label(context.l10n),
                  style: const TextStyle(fontSize: 14.0),
                ),
                speed: choice.speed,
                onTap: connectionStatus == LichessConnectionStatus.online
                    ? () {
                        Navigator.of(context).pushHidingTabBar(
                          GameScreen.buildRoute(
                            source: LobbySource(
                              GameSeek.fastPairing(choice, authUser, boardSize: boardSize),
                            ),
                          ),
                        );
                      }
                    : null,
              ),
            ),
            if (index < choices.length - 1) const SizedBox(width: _kMatrixSpacing),
          ];
        })
        .flattened
        .toList();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...choiceWidgets,
          if (showCustom) ...[
            if (choices.isNotEmpty) const SizedBox(width: _kMatrixSpacing),
            Expanded(
              child: _ChoiceChip(
                title: Text(context.l10n.custom, textAlign: TextAlign.center),
                onTap: connectionStatus == LichessConnectionStatus.online
                    ? () {
                        showAdaptiveBottomSheet<void>(
                          context: context,
                          useRootNavigator: true,
                          isScrollControlled: true,
                          builder: (_) => PlayBottomSheet(navigator: Navigator.of(context)),
                        );
                      }
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class const _ChoiceChip({
  required final Widget title,
  final Widget? subtitle,
  final Speed? speed,
  required final void Function()? onTap,
  super.key,
}) extends StatelessWidget {
  static const BorderRadius _kBorderRadius = BorderRadius.all(Radius.circular(6.0));

  @override
  Widget build(BuildContext context) {
    final scaffoldOpacity = Theme.of(context).scaffoldBackgroundColor.a;
    final bgColor = Theme.of(context).brightness == Brightness.dark
        ? scaffoldOpacity > 0
              ? Colors.white10
              : ColorScheme.of(context).surfaceContainerLow
        // Translucent, so that the logo behind the tiles shows through.
        : Theme.of(context).cardTheme.color?.withValues(alpha: 0.65) ??
              ColorScheme.of(context).surfaceContainerHighest.withValues(alpha: 0.65);

    return Opacity(
      opacity: onTap != null ? 1.0 : 0.5,
      child: Container(
        decoration: BoxDecoration(color: bgColor, borderRadius: _kBorderRadius),
        child: InkWell(
          borderRadius: _kBorderRadius,
          onTap: onTap,
          splashColor: Theme.of(context).primaryColor.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: Theme.of(context).textTheme.labelMedium?.color?.withValues(alpha: 0.8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [title, ?subtitle],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
