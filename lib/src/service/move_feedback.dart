import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';

/// A provider for [MoveFeedbackService].
final moveFeedbackServiceProvider = Provider<MoveFeedbackService>((Ref ref) {
  final soundService = ref.watch(soundServiceProvider);
  return MoveFeedbackService(soundService, ref);
}, name: 'MoveFeedbackServiceProvider');

/// The sound and the vibration of a stone being played.
class MoveFeedbackService(final SoundService _soundService, final Ref _ref) {
  /// A stone was played, or a player passed.
  void moveFeedback() {
    _soundService.play(Sound.move);
    _haptic();
  }

  /// A stone was played and took stones off the board.
  void captureFeedback() {
    _soundService.play(Sound.capture);
    _haptic();
  }

  void _haptic() {
    if (_ref.read(boardPreferencesProvider).hapticFeedback) {
      HapticFeedback.lightImpact();
    }
  }
}
