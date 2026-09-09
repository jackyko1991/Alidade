// Basic smoke test: the solve screen renders its core controls.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alidade/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SolveScreen shows the import and solve controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlidadeApp());
    await tester.pumpAndSettle();

    expect(find.text('Import from gallery'), findsOneWidget);
    expect(find.text('Solve'), findsOneWidget);
    expect(find.text('No image selected'), findsOneWidget);
  });

  testWidgets('SolveScreen shows the optional target control, unselected', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlidadeApp());
    await tester.pumpAndSettle();

    // The picker's own behaviour is covered by target_picker_test.dart;
    // this just guards that the pre-solve row exists and reads as clearly
    // optional, and hasn't pushed the core controls above out of the
    // pumped frame (widget tests don't scroll on their own).
    expect(find.text('Target (optional)'), findsOneWidget);
    expect(find.text('None — solve blind'), findsOneWidget);
    expect(find.text('Import from gallery'), findsOneWidget);
    expect(find.text('Solve'), findsOneWidget);
  });

  testWidgets('the target overlay toggle is absent before any solve', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlidadeApp());
    await tester.pumpAndSettle();

    // Exact match, not a substring - 'Target (optional)' must not make
    // this pass by accident.
    expect(find.text('Target', findRichText: false), findsNothing);
  });

  testWidgets('Solve stays disabled with no image, regardless of target', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AlidadeApp());
    await tester.pumpAndSettle();

    // No target-related term appears in Solve's enable condition (see
    // _solve's onPressed in main.dart) - with no image selected, Solve is
    // disabled from the very first frame, the same as with no target.
    final solveButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Solve'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(solveButton.onPressed, isNull);
  });
}
