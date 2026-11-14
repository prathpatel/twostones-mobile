import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/utils/focus_detector.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:material_ui/material_ui.dart';

Future<bool>? _isSupportedFuture;
bool? _debugIsSupported;

/// Whether system gestures can be excluded: navigation gestures start with Android 10 (API 29).
Future<bool> _isGesturesExclusionSupported() => _debugIsSupported != null
    ? Future.value(_debugIsSupported)
    : _isSupportedFuture ??= _checkGesturesExclusionSupport();

/// Overrides whether system gestures can be excluded, or resets it to the device check if null.
@visibleForTesting
void debugSetGesturesExclusionSupported(bool? isSupported) {
  _debugIsSupported = isSupported;
}

Future<bool> _checkGesturesExclusionSupport() async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return false;
  }
  try {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    return androidInfo.version.sdkInt >= 29;
  } catch (_) {
    return false;
  }
}

/// A widget that sets immersive mode on android 10+ while [enabled] is true and the widget is
/// focused.
///
/// Android limits the exclusion of navigation gestures to 200dp of height per edge of the screen,
/// except in immersive mode, so the boards below this widget ([AndroidBoardGesturesExclusion])
/// exclude their whole edge columns while it is set.
///
/// This widget will keep the initial [MediaQueryData.viewPadding] whether immersive mode is set or
/// not. This works in conjunction with the [SafeArea.maintainBottomViewPadding] property. This is
/// the responsibility of the parent widget to set the [SafeArea] with the correct value.
class const AndroidImmersiveModeWidget({
  required final Widget child,

  /// Whether to set immersive mode, e.g. while a game is being played.
  required final bool enabled,
  super.key,
}) extends StatefulWidget {
  @override
  State<AndroidImmersiveModeWidget> createState() => _AndroidImmersiveModeWidgetState();
}

class _AndroidImmersiveModeWidgetState() extends State<AndroidImmersiveModeWidget> {
  EdgeInsets? initialViewPadding;

  bool _isSupported = false;
  bool _isFocused = false;
  bool _isImmersiveMode = false;

  @override
  void initState() {
    super.initState();
    _isGesturesExclusionSupported().then((supported) {
      if (supported && mounted) {
        setState(() {
          _isSupported = true;
          _updateImmersiveMode();
        });
      }
    });
  }

  @override
  void didUpdateWidget(AndroidImmersiveModeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateImmersiveMode();
  }

  @override
  void dispose() {
    if (_isImmersiveMode) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  /// Sets or removes immersive mode, depending on the current state.
  ///
  /// The boards below get the new state from the [_ImmersiveModeScope] when this widget is rebuilt.
  void _updateImmersiveMode() {
    final shouldSet = _isSupported && _isFocused && widget.enabled && !isTabletOrLarger(context);
    if (shouldSet == _isImmersiveMode) {
      return;
    }
    _isImmersiveMode = shouldSet;
    SystemChrome.setEnabledSystemUIMode(
      shouldSet ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  void _setFocused(bool isFocused) {
    if (!mounted) return;
    setState(() {
      _isFocused = isFocused;
      _updateImmersiveMode();
    });
  }

  @override
  Widget build(BuildContext context) {
    initialViewPadding ??= MediaQuery.viewPaddingOf(context);

    return MediaQuery(
      // Always set the view padding to the initial value to avoid an UI shift when immersive mode
      // is enabled.
      data: MediaQuery.of(context).copyWith(viewPadding: initialViewPadding),
      child: FocusDetector(
        onFocusGained: () => _setFocused(true),
        onFocusLost: () => _setFocused(false),
        child: _ImmersiveModeScope(isImmersiveMode: _isImmersiveMode, child: widget.child),
      ),
    );
  }
}

class const _ImmersiveModeScope({required final bool isImmersiveMode, required super.child})
    extends InheritedWidget {
  @override
  bool updateShouldNotify(_ImmersiveModeScope oldWidget) =>
      isImmersiveMode != oldWidget.isImmersiveMode;
}
