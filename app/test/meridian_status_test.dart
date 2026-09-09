// MeridianStatusLine's own location-fetching, gated behind
// ObserverLocationService/geolocator, isn't mockable from here without a
// platform-channel test harness; what IS verified is the shape that
// matters for correctness under test (and, not coincidentally, under a
// real device with location denied/unavailable): no target -> nothing
// rendered, a target -> some non-empty status eventually appears rather
// than the widget crashing or hanging forever.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alidade/meridian_status.dart';
import 'package:alidade/sky_target.dart';

const _vega = SkyTarget(
  id: 'HR 7001',
  displayName: 'Vega',
  kind: TargetKind.star,
  typeLabel: 'Star',
  raDeg: 279.23473,
  decDeg: 38.78369,
);

Future<void> _pump(WidgetTester tester, SkyTarget? target) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: MeridianStatusLine(target: target)),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('renders nothing when no target is chosen', (tester) async {
    await _pump(tester, null);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('renders some status text once a target is chosen', (
    tester,
  ) async {
    await _pump(tester, _vega);
    // Whatever the location result under test (a missing platform-channel
    // implementation is expected and handled the same way a real denial
    // is), some single line of feedback is shown - never a blank gap and
    // never an uncaught exception.
    expect(tester.takeException(), isNull);
    expect(find.byType(Text), findsOneWidget);
    final text = tester.widget<Text>(find.byType(Text)).data ?? '';
    expect(text, isNotEmpty);
  });
}
