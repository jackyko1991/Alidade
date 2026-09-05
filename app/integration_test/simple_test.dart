import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alidade/main.dart';
import 'package:alidade/src/rust/api/solver.dart' as solver;
import 'package:alidade/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await RustLib.init();
    final dbBytes = await rootBundle.load('assets/db/alidade_135mm.bin');
    solver.loadDatabase(bytes: dbBytes.buffer.asUint8List());
  });

  testWidgets('Database loads and the solve screen renders', (
    WidgetTester tester,
  ) async {
    expect(solver.isDatabaseLoaded(), isTrue);

    await tester.pumpWidget(const AlidadeApp());
    expect(find.text('Import from gallery'), findsOneWidget);
  });
}
