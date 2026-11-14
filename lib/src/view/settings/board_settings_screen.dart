import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:lichess_mobile/src/utils/system.dart';
import 'package:lichess_mobile/src/widgets/adaptive_choice_picker.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:material_ui/material_ui.dart';

/// The settings of the Go board and of the game screen.
class const BoardSettingsScreen({super.key}) extends ConsumerStatefulWidget {
  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const BoardSettingsScreen());
  }

  @override
  ConsumerState<BoardSettingsScreen> createState() => _BoardSettingsScreenState();
}

class _BoardSettingsScreenState() extends ConsumerState<BoardSettingsScreen> {
  bool isLoading = false;

  Future<void> _setAccountPref(Future<void> Function(AccountPreferences preferences) save) async {
    setState(() {
      isLoading = true;
    });
    try {
      final authUser = ref.read(authControllerProvider);
      await save(ref.read(accountPreferencesProvider.notifier));
      if (authUser != null && mounted) {
        showSnackBar(
          context,
          context.l10n.mobileSettingsPreferencesSaved,
          type: SnackBarType.success,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final accountPrefsAsync = ref.watch(accountPreferencesProvider);
    final accountPrefs = accountPrefsAsync.value ?? defaultAccountPreferences;
    final authUser = ref.watch(authControllerProvider);
    final isOnline = ref.watch(isDeviceOnlineProvider);
    // We only allow changing account preferences if the user is logged out (prefs are local in that
    // case) or if the user is logged in and online (prefs are stored on the server in that case).
    final accountPrefsEnabled =
        accountPrefsAsync.hasValue && !isLoading && (authUser == null || isOnline);
    final androidVersion = ref.watch(androidVersionProvider).value;
    final boardNotifier = ref.read(boardPreferencesProvider.notifier);

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: Text(context.l10n.mobileBoardSettings),
        actions: [if (isLoading) const PlatformAppBarLoadingIndicator()],
      ),
      body: ListView(
        children: [
          ListSection(
            header: SettingsSectionTitle(context.l10n.preferencesDisplay),
            hasLeading: false,
            children: [
              SwitchSettingTile(
                title: Text(context.l10n.preferencesBoardCoordinates),
                value: boardPrefs.coordinates,
                onChanged: (_) => boardNotifier.toggleCoordinates(),
              ),
              SwitchSettingTile(
                title: const Text('Mark the last stone played'),
                value: boardPrefs.boardHighlights,
                onChanged: (_) => boardNotifier.toggleBoardHighlights(),
              ),
              SwitchSettingTile(
                title: Text(context.l10n.preferencesMoveListWhilePlaying),
                value: boardPrefs.moveListDisplay,
                onChanged: (_) => boardNotifier.toggleMoveListDisplay(),
              ),
              SettingsListTile(
                enabled: accountPrefsEnabled,
                settingsLabel: Text(context.l10n.preferencesZenMode),
                settingsValue: accountPrefs.zenMode.label(context.l10n),
                onTap: accountPrefsEnabled
                    ? () {
                        showChoicePicker(
                          context,
                          choices: Zen.values,
                          selectedItem: accountPrefs.zenMode,
                          labelBuilder: (t) => Text(t.label(context.l10n)),
                          onSelectedItemChanged: (Zen? value) {
                            _setAccountPref((prefs) => prefs.setZen(value ?? accountPrefs.zenMode));
                          },
                        );
                      }
                    : null,
              ),
              SettingsListTile(
                settingsLabel: Text(context.l10n.mobileSettingsClockPosition),
                settingsValue: boardPrefs.clockPosition.label(context.l10n),
                onTap: () {
                  showChoicePicker(
                    context,
                    choices: ClockPosition.values,
                    selectedItem: boardPrefs.clockPosition,
                    labelBuilder: (t) => Text(t.label(context.l10n)),
                    onSelectedItemChanged: (ClockPosition? value) =>
                        boardNotifier.setClockPosition(value ?? boardPrefs.clockPosition),
                  );
                },
              ),
              if (isTabletOrLarger(context))
                SettingsListTile(
                  settingsLabel: const Text('Board position in landscape'),
                  settingsValue: boardPrefs.landscapeBoardPosition.label(context.l10n),
                  onTap: () {
                    showChoicePicker(
                      context,
                      choices: LandscapeBoardPosition.values,
                      selectedItem: boardPrefs.landscapeBoardPosition,
                      labelBuilder: (t) => Text(t.label(context.l10n)),
                      onSelectedItemChanged: (LandscapeBoardPosition? value) => boardNotifier
                          .setLandscapeBoardPosition(value ?? boardPrefs.landscapeBoardPosition),
                    );
                  },
                ),
            ],
          ),
          ListSection(
            header: SettingsSectionTitle(context.l10n.preferencesGameBehavior),
            hasLeading: false,
            children: [
              SwitchSettingTile(
                title: Text(context.l10n.preferencesMoveConfirmation),
                subtitle: const Text(
                  'Tap a point to place a stone, then confirm it. A stone cannot be taken back.',
                  maxLines: 5,
                ),
                value: boardPrefs.confirmMove,
                onChanged: (_) => boardNotifier.toggleConfirmMove(),
              ),
              SwitchSettingTile(
                title: const Text('Confirm resignation'),
                value: boardPrefs.confirmResign,
                onChanged: (_) => boardNotifier.toggleConfirmResign(),
              ),
              SwitchSettingTile(
                title: const Text('Vibrate when a stone is played'),
                value: boardPrefs.hapticFeedback,
                onChanged: (_) => boardNotifier.toggleHapticFeedback(),
              ),
              if (androidVersion != null && androidVersion.sdkInt >= 29)
                SwitchSettingTile(
                  title: Text(context.l10n.mobileSettingsImmersiveMode),
                  subtitle: Text(context.l10n.mobileSettingsImmersiveModeSubtitle, maxLines: 5),
                  value: boardPrefs.immersiveModeWhilePlaying ?? false,
                  onChanged: (_) => boardNotifier.toggleImmersiveModeWhilePlaying(),
                ),
              // takebacks are always enabled for anonymous players, so hide the setting.
              if (authUser != null)
                SettingsListTile(
                  enabled: accountPrefsEnabled,
                  settingsLabel: Text(context.l10n.preferencesTakebacksWithOpponentApproval),
                  settingsValue: accountPrefs.takeback.label(context.l10n),
                  onTap: accountPrefsEnabled
                      ? () {
                          showChoicePicker(
                            context,
                            choices: Takeback.values,
                            selectedItem: accountPrefs.takeback,
                            labelBuilder: (t) => Text(t.label(context.l10n)),
                            onSelectedItemChanged: (Takeback? value) {
                              _setAccountPref(
                                (prefs) => prefs.setTakeback(value ?? accountPrefs.takeback),
                              );
                            },
                          );
                        }
                      : null,
                ),
              if (authUser != null)
                SettingsListTile(
                  enabled: accountPrefsEnabled,
                  settingsLabel: Text(context.l10n.preferencesGiveMoreTime),
                  settingsValue: accountPrefs.moretime.label(context.l10n),
                  onTap: accountPrefsEnabled
                      ? () {
                          showChoicePicker(
                            context,
                            choices: Moretime.values,
                            selectedItem: accountPrefs.moretime,
                            labelBuilder: (t) => Text(t.label(context.l10n)),
                            onSelectedItemChanged: (Moretime? value) {
                              _setAccountPref(
                                (prefs) => prefs.setMoretime(value ?? accountPrefs.moretime),
                              );
                            },
                          );
                        }
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
