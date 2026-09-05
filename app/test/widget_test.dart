// Basic smoke test: the solve screen renders its core controls.

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
}
