import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:lichess_mobile/src/utils/color_palette.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:lichess_mobile/src/view/settings/background_theme_choice_screen.dart';
import 'package:lichess_mobile/src/view/settings/color_scheme_debug_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_choice_picker.dart';
import 'package:lichess_mobile/src/widgets/board_thumbnail.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:material_ui/material_ui.dart';

class const ThemeSettingsScreen({super.key}) extends ConsumerWidget {
  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const ThemeSettingsScreen());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlatformScaffold(
      appBar: PlatformAppBar(title: Text(context.l10n.mobileTheme)),
      body: const _Body(),
    );
  }
}

class const _Body() extends ConsumerStatefulWidget {
  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState() extends ConsumerState<_Body> {
  /// Whether the user has selected a custom background, even if none is set yet.
  bool customBackgroundSelected = false;

  /// Opens the custom background selection screen.
  ///
  /// Only an actual background color or image makes the background custom, so any transient
  /// selection is discarded when the user comes back without having picked one.
  Future<void> pickCustomBackground() async {
    await Navigator.of(context).push(BackgroundChoiceScreen.buildRoute());
    if (mounted) {
      setState(() {
        customBackgroundSelected = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final generalPrefs = ref.watch(generalPreferencesProvider);

    final bool isCustomBackground = generalPrefs.isForcedDarkMode || customBackgroundSelected;
    final BackgroundColor? backgroundColor = generalPrefs.backgroundColor?.$1;

    final boardSize = isTabletOrLarger(context) ? 350.0 : 200.0;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: StaticGoBoard(
              size: boardSize,
              position: replayGoGame(size: 9, moves: const ['ee', 'ec', 'ce', 'cc', 'gc']).last,
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                ListSection(
                  hasLeading: true,
                  children: [
                    if (getSystemCorePalettes() != null)
                      SwitchSettingTile(
                        leading: const Icon(Icons.colorize_outlined),
                        title: Text(context.l10n.mobileSystemColors),
                        value: generalPrefs.systemColors,
                        onChanged: (value) {
                          ref.read(generalPreferencesProvider.notifier).toggleSystemColors();
                        },
                      ),
                    SettingsListTile(
                      icon: const Icon(Icons.brightness_medium_outlined),
                      settingsLabel: Text(context.l10n.background),
                      settingsValue: isCustomBackground
                          ? backgroundColor?.label ??
                                (generalPrefs.backgroundImage != null
                                    ? context.l10n.backgroundImage
                                    : context.l10n.mobileCustomizeButton)
                          : generalPrefs.themeMode.title(context.l10n),
                      trailing: backgroundColor != null
                          ? _ColorCircle(color: backgroundColor.darker)
                          : null,
                      onTap: () async {
                        // The picker outlives this screen when switching away from a custom
                        // background, so the labels must not depend on this context.
                        final l10n = context.l10n;
                        bool newlyCustom = false;
                        await showChoicePicker<BackgroundThemeMode?>(
                          context,
                          // A null choice means a custom background.
                          choices: const [...BackgroundThemeMode.values, null],
                          selectedItem: isCustomBackground ? null : generalPrefs.themeMode,
                          labelBuilder: (t) => Text(t?.title(l10n) ?? l10n.mobileCustomizeButton),
                          onSelectedItemChanged: (BackgroundThemeMode? value) {
                            newlyCustom = value == null && !isCustomBackground;
                            if (mounted) {
                              setState(() {
                                customBackgroundSelected = value == null;
                              });
                            }
                            if (value != null) {
                              final notifier = ref.read(generalPreferencesProvider.notifier);
                              if (generalPrefs.isForcedDarkMode) {
                                // Preferences are only applied to the state once they are
                                // written, so the two updates must be sequenced, or the second
                                // one would overwrite the first with a stale state.
                                notifier
                                    .setBackground(backgroundColor: null, backgroundImage: null)
                                    .then((_) => notifier.setBackgroundThemeMode(value));
                              } else {
                                notifier.setBackgroundThemeMode(value);
                              }
                            }
                          },
                        );
                        // Let the user pick their background right away.
                        if (newlyCustom && context.mounted) {
                          await pickCustomBackground();
                        }
                      },
                    ),
                    if (isCustomBackground)
                      ListTile(
                        leading: const Icon(Icons.wallpaper),
                        title: Text(context.l10n.mobileChooseCustomBackground),
                        trailing: Theme.of(context).platform == TargetPlatform.iOS
                            ? const CupertinoListTileChevron()
                            : null,
                        onTap: pickCustomBackground,
                      ),
                    if (kDebugMode)
                      ListTile(
                        leading: const Icon(Icons.palette_outlined),
                        title: const Text('Color scheme (debug)'),
                        onTap: () =>
                            Navigator.of(context).push(ColorSchemeDebugScreen.buildRoute()),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A small circle filled with [color], to preview a color setting.
class const _ColorCircle({required final Color color}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20.0,
      height: 20.0,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: ColorScheme.of(context).outlineVariant),
      ),
    );
  }
}
