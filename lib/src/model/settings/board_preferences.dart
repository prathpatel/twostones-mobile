import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';

part 'board_preferences.freezed.dart';
part 'board_preferences.g.dart';

final boardPreferencesProvider = NotifierProvider<BoardPreferences, BoardPrefs>(
  BoardPreferences.new,
  name: 'BoardPreferencesProvider',
);

class BoardPreferences() extends Notifier<BoardPrefs> with PreferencesStorage<BoardPrefs> {
  @override
  @protected
  PrefCategory get prefCategory => PrefCategory.board;

  @override
  @protected
  BoardPrefs get defaults => BoardPrefs.defaults;

  @override
  BoardPrefs fromJson(Map<String, dynamic> json) => BoardPrefs.fromJson(json);

  @override
  BoardPrefs build() {
    return fetch();
  }

  Future<void> toggleConfirmResign() async {
    await save(state.copyWith(confirmResign: !state.confirmResign));
  }

  Future<void> toggleConfirmMove() async {
    await save(state.copyWith(confirmMove: !state.confirmMove));
  }

  Future<void> toggleHapticFeedback() {
    return save(state.copyWith(hapticFeedback: !state.hapticFeedback));
  }

  Future<void> toggleImmersiveModeWhilePlaying() {
    return save(
      state.copyWith(immersiveModeWhilePlaying: !(state.immersiveModeWhilePlaying ?? false)),
    );
  }

  Future<void> toggleBoardHighlights() {
    return save(state.copyWith(boardHighlights: !state.boardHighlights));
  }

  Future<void> toggleCoordinates() {
    return save(state.copyWith(coordinates: !state.coordinates));
  }

  Future<void> setClockPosition(ClockPosition clockPosition) {
    return save(state.copyWith(clockPosition: clockPosition));
  }

  Future<void> setLandscapeBoardPosition(LandscapeBoardPosition landscapeBoardPosition) {
    return save(state.copyWith(landscapeBoardPosition: landscapeBoardPosition));
  }

  Future<void> toggleMoveListDisplay() {
    return save(state.copyWith(moveListDisplay: !state.moveListDisplay));
  }
}

/// How the Go board looks and behaves, on this device.
@Freezed(fromJson: true, toJson: true)
sealed class const BoardPrefs._() with _$BoardPrefs implements Serializable {
  const factory({
    bool? immersiveModeWhilePlaying,
    required bool hapticFeedback,

    /// Whether to mark the last stone played.
    required bool boardHighlights,

    /// Whether to print the column letters and row numbers around the board.
    required bool coordinates,
    @JsonKey(defaultValue: ClockPosition.right, unknownEnumValue: ClockPosition.right)
    required ClockPosition clockPosition,
    @JsonKey(
      defaultValue: LandscapeBoardPosition.left,
      unknownEnumValue: LandscapeBoardPosition.left,
    )
    required LandscapeBoardPosition landscapeBoardPosition,
    @JsonKey(defaultValue: true) required bool moveListDisplay,
    @JsonKey(defaultValue: true) required bool confirmResign,

    /// Whether a stone must be confirmed before it is played: a finger easily lands on the wrong
    /// point of a 19×19 board, and a stone cannot be taken back.
    @JsonKey(defaultValue: true) required bool confirmMove,
  }) = _BoardPrefs;

  static const defaults = BoardPrefs(
    immersiveModeWhilePlaying: false,
    hapticFeedback: true,
    boardHighlights: true,
    coordinates: true,
    clockPosition: ClockPosition.right,
    landscapeBoardPosition: LandscapeBoardPosition.left,
    moveListDisplay: true,
    confirmResign: true,
    confirmMove: true,
  );

  factory fromJson(Map<String, dynamic> json) {
    return _$BoardPrefsFromJson(json);
  }
}

enum ClockPosition() {
  left,
  right;

  String label(AppLocalizations l10n) => switch (this) {
    ClockPosition.left => l10n.mobilePositionLeft,
    ClockPosition.right => l10n.mobilePositionRight,
  };
}

enum LandscapeBoardPosition() {
  left,
  right;

  String label(AppLocalizations l10n) => switch (this) {
    LandscapeBoardPosition.left => l10n.mobilePositionLeft,
    LandscapeBoardPosition.right => l10n.mobilePositionRight,
  };
}
