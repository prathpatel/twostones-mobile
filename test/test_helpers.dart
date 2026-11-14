import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lichess_mobile/src/model/go/go.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/go_board.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' show GlassScrollEdgeEffect;
import 'package:material_ui/material_ui.dart';

const double _kTestScreenWidth = 390.0;
const double _kTestScreenHeight = 844.0;

const kTestSurfaces = [
  // https://www.browserstack.com/guide/common-screen-resolutions
  // phones
  Size(360, 800),
  Size(390, 844),
  Size(393, 873),
  Size(412, 915),
  Size(414, 896),
  Size(360, 780),
  // tablets
  Size(600, 1024),
  Size(810, 1080),
  Size(820, 1180),
  Size(1280, 800),
  Size(800, 1280),
  Size(601, 962),
  // folded motorola
  Size(564.7, 482.6),
  // pixel fold unfolded
  Size(701.0, 841.1),
  Size(841.1, 701.0),
];

/// iPhone 14 screen size.
const kTestSurfaceSize = Size(_kTestScreenWidth, _kTestScreenHeight);

const kPlatformVariant = TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS});

/// Checks that the bottom bar of a screen with an analysis layout floats over its tab view on iOS,
/// with thick glass buttons over the blurred bottom edge of the tab view.
///
/// Returns the bottom padding that the tab views must apply: the bar height on iOS, else 0.
double expectBottomBarOverTabView(WidgetTester tester) {
  final barRect = tester.getRect(find.byType(BottomBar));
  final tabViewBottom = tester.getBottomLeft(find.byType(TabBarView)).dy;
  final bottomEdgeEffect = find.byWidgetPredicate(
    (widget) => widget is GlassScrollEdgeEffect && widget.fadeBottom,
  );
  final thickGlassBar = find.ancestor(
    of: find.byType(BottomBar),
    matching: find.byType(ThickBottomBarGlass),
  );
  if (debugDefaultTargetPlatformOverride == TargetPlatform.iOS) {
    expect(tabViewBottom, greaterThan(barRect.top));
    expect(bottomEdgeEffect, findsOneWidget);
    expect(thickGlassBar, findsOneWidget);
    return barRect.height;
  } else {
    expect(tabViewBottom, barRect.top);
    expect(bottomEdgeEffect, findsNothing);
    expect(thickGlassBar, findsNothing);
    return 0.0;
  }
}

/// Mocks a surface with a given size.
class const TestSurface({required final Widget child, required final Size size, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: SizedBox(width: size.width, height: size.height, child: child),
    );
  }
}

/// Mocks an http response
Future<http.Response> mockResponse(
  String body,
  int code, {
  Map<String, String> headers = const {},
}) => Future.value(http.Response(body, code, headers: headers));

Future<void> meetsTapTargetGuideline(WidgetTester tester) async {
  if (debugDefaultTargetPlatformOverride == TargetPlatform.iOS) {
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  } else {
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  }
}

/// The asset names of every [Image] currently rendered.
Iterable<String> imageAssetNames(WidgetTester tester) => tester
    .widgetList<Image>(find.byType(Image))
    .map((image) => image.image)
    .whereType<AssetImage>()
    .map((provider) => provider.assetName);

/// The position shown on the [GoBoard] of the screen.
GoPosition getGoBoardPosition(WidgetTester tester) =>
    tester.widget<GoBoard>(find.byType(GoBoard)).position;

/// Taps the point of the [GoBoard] printed as [coord] (`"E5"`).
Future<void> tapGoPoint(WidgetTester tester, String coord) async {
  final board = tester.widget<GoBoard>(find.byType(GoBoard));
  final size = board.position.size;
  const columns = 'ABCDEFGHJKLMNOPQRST';
  final point = (size - int.parse(coord.substring(1))) * size + columns.indexOf(coord[0]);
  final geometry = GoBoardGeometry(
    size: board.size,
    boardSize: size,
    showCoordinates: board.showCoordinates,
  );
  await tester.tapAt(tester.getTopLeft(find.byType(GoBoard)) + geometry.offsetOf(point));
  await tester.pump();
}

void mockClipboard(String text) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (methodCall) async {
      if (methodCall.method == 'Clipboard.getData') {
        return {'text': text};
      }
      return null;
    },
  );
}

/// Finds widgets by their tooltip message.
///
/// [CommonFinders.byTooltip] cannot be used, because it only matches the [Tooltip] widget of the
/// Flutter material library, whereas the app renders the one of the `material_ui` package.
Finder findByTooltip(String message, {bool skipOffstage = true}) => find.byWidgetPredicate(
  (widget) => widget is Tooltip && widget.message == message,
  description: 'tooltip "$message"',
  skipOffstage: skipOffstage,
);
