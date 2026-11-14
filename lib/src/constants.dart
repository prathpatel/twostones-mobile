import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// The TwoStones server. Run against another one with `--dart-define=LICHESS_HOST=localhost:9663`.
const kLichessHost = String.fromEnvironment('LICHESS_HOST', defaultValue: 'twostones.org');

const kLichessWSHost = String.fromEnvironment('LICHESS_WS_HOST', defaultValue: 'ws.twostones.org');

const kLichessWSSecret = String.fromEnvironment(
  'LICHESS_WS_SECRET',
  defaultValue: 'somethingElseInProd',
);

const kLichessCDNHost = String.fromEnvironment(
  'LICHESS_CDN_HOST',
  defaultValue: 'https://twostones.org',
);

const kLichessCustomUriSchemeName = 'org.lichess.mobile';

const kLichessClientId = 'lichess_mobile';

const kSRIStorageKey = 'socket_random_identifier';

// lichess
// https://github.com/lichess-org/lila/blob/4562a83cdb263c3ebf7e148c0f666f0ff92b91c7/modules/rating/src/main/Glicko.scala#L71
const kProvisionalDeviation = 110;
const kClueLessDeviation = 230;

// UI

/// The colour of a wooden Go board, which the colours of the app are derived from.
const kBoardWoodColor = Color(0xFFB98B4E);
const double kCupertinoBarOpacity = 0.8;

const kGoldenRatio = 1.61803398875;

/// Use same box shadows as material widgets with elevation 1.
List<BoxShadow> get boardShadows =>
    defaultTargetPlatform == .iOS ? const <BoxShadow>[] : kElevationToShadow[1]!;

const kMaxClockTextScaleFactor = 1.94;
const kEmptyWidget = SizedBox.shrink();
const kTabletBoardTableSidePadding = 16.0;

/// Horizontal margin around the board on phones in portrait orientation, on screens where the board
/// does not span the whole screen width (analysis, learn, practice...).
///
/// It makes the board smaller, which leaves more vertical space below it.
const kPhoneBoardSideMargin = 12.0;

/// Horizontal margin around the board on phones with a short screen (`isShortVerticalScreen`) in
/// portrait orientation, wider than [kPhoneBoardSideMargin] to leave enough vertical space below
/// the board.
const kShortScreenBoardSideMargin = 32.0;

const kBottomBarHeight = 56.0;
const kMaterialPopupMenuMaxWidth = 500.0;

/// The threshold to detect screens with a small remaining height minus board.
const kSmallHeightMinusBoard = 200;
