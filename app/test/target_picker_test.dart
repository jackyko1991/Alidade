// Widget-level behaviour of the target picker, against a small fixed
// TargetCatalog.debugWithTargets(...) fixture rather than the real bundled
// assets (target_search_test.dart already covers the real catalog). Finds
// by visible text only, matching the rest of this app's tests — there are
// no Keys anywhere in this codebase (see widget_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alidade/night_mode.dart';
import 'package:alidade/sky_target.dart';
import 'package:alidade/target_catalog.dart';
import 'package:alidade/target_picker.dart';

const _vega = SkyTarget(
  id: 'HR 7001',
  displayName: 'Vega',
  kind: TargetKind.star,
  typeLabel: 'Star',
  constellation: 'Lyr',
  magnitude: 0.0,
  raDeg: 279.23473,
  decDeg: 38.78369,
);

const _m27 = SkyTarget(
  id: 'M27',
  displayName: 'Dumbbell Nebula',
  kind: TargetKind.messier,
  typeLabel: 'Planetary Nebula',
  constellation: 'Vul',
  magnitude: 7.4,
  raDeg: 299.90105,
  decDeg: 22.72083,
);

const _ngcNoMag = SkyTarget(
  id: 'NGC 1',
  displayName: 'NGC 1',
  kind: TargetKind.ngc,
  typeLabel: 'Galaxy',
  constellation: 'Peg',
  raDeg: 1.85,
  decDeg: 27.71,
);

TargetCatalog _fixtureCatalog() =>
    TargetCatalog.debugWithTargets(const [_vega, _m27, _ngcNoMag]);

// The unfiltered result list always leads with the 9 solar-system bodies
// (see TargetCatalog.search's empty-query path), so a fixture target can
// land below the fold of the test's default viewport in a lazily-built
// ListView - scroll to it rather than assume it's already rendered.
Future<void> _scrollToText(WidgetTester tester, String text) =>
    tester.scrollUntilVisible(
      find.text(text),
      200,
      // Not find.byType(Scrollable) alone - the search TextField's own
      // EditableText also has one (for horizontal text scrolling), so that
      // finder matches two widgets. Narrow to the one inside the ListView.
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );

Future<void> _pumpPicker(WidgetTester tester, {TargetCatalog? catalog}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showTargetPicker(
                context,
                catalog: catalog ?? _fixtureCatalog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => NightMode.enabled.value = false);

  testWidgets('lists results with name, magnitude and a secondary line', (
    tester,
  ) async {
    await _pumpPicker(tester);
    await _scrollToText(tester, 'Vega');
    expect(find.text('Vega'), findsOneWidget);
    expect(find.text('0.0'), findsOneWidget);
    expect(find.text('HR 7001 · Star · Lyr'), findsOneWidget);
  });

  testWidgets('a target with no magnitude shows an em dash', (tester) async {
    await _pumpPicker(tester);
    await _scrollToText(tester, '—');
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('typing filters the list', (tester) async {
    await _pumpPicker(tester);
    await tester.enterText(find.byType(TextField), 'veg');
    await tester.pump(const Duration(milliseconds: 200)); // clear the debounce
    expect(find.text('Vega'), findsOneWidget);
    expect(find.text('Dumbbell Nebula'), findsNothing);
  });

  testWidgets('the clear button restores the unfiltered list', (tester) async {
    await _pumpPicker(tester);
    await tester.enterText(find.byType(TextField), 'veg');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Dumbbell Nebula'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump(const Duration(milliseconds: 200));
    await _scrollToText(tester, 'Dumbbell Nebula');
    expect(find.text('Dumbbell Nebula'), findsOneWidget);
  });

  testWidgets('changing category filters by it', (tester) async {
    await _pumpPicker(tester);
    await _scrollToText(tester, 'Vega');
    expect(find.text('Vega'), findsOneWidget);
    await _scrollToText(tester, 'Dumbbell Nebula');
    expect(find.text('Dumbbell Nebula'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deep sky').last);
    await tester.pumpAndSettle();

    expect(find.text('Dumbbell Nebula'), findsOneWidget);
    expect(find.text('Vega'), findsNothing);
  });

  testWidgets('tapping a row pops the page with that target', (tester) async {
    SkyTarget? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  popped = await showTargetPicker(
                    context,
                    catalog: _fixtureCatalog(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await _scrollToText(tester, 'Vega');
    await tester.tap(find.text('Vega'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.id, 'HR 7001');
  });

  testWidgets('backing out pops null', (tester) async {
    SkyTarget? popped = _m27; // sentinel to prove it gets overwritten with null
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  popped = await showTargetPicker(
                    context,
                    catalog: _fixtureCatalog(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(popped, isNull);
  });

  testWidgets('night mode renders titles in red and subtitles dim', (
    tester,
  ) async {
    NightMode.enabled.value = true;
    await _pumpPicker(tester);
    await _scrollToText(tester, 'Vega');

    final title = tester.widget<Text>(find.text('Vega'));
    expect(title.style?.color, nightModeColor);
    final subtitle = tester.widget<Text>(find.text('HR 7001 · Star · Lyr'));
    expect(subtitle.style?.color, dimNightModeColor);
  });
}
