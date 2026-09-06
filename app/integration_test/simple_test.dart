import 'package:flutter_test/flutter_test.dart';
import 'package:alidade/db_manager.dart';
import 'package:alidade/db_manifest.dart';
import 'package:alidade/main.dart';
import 'package:alidade/src/rust/api/solver.dart' as solver;
import 'package:alidade/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await RustLib.init();
    // No bucket is bundled as an app asset any more (fov16 used to be a
    // special-cased exception) — fetch it the same way the app itself
    // would for a 135mm-class lens, via a real download.
    final bucket = dbBuckets.firstWhere((b) => b.id == 'fov16');
    if (!await DbManager.isDownloaded(bucket)) {
      await DbManager.download(bucket);
    }
    final bytes = await DbManager.readBytes(bucket);
    solver.loadDatabase(bytes: bytes);
  });

  testWidgets('Database loads and the solve screen renders', (
    WidgetTester tester,
  ) async {
    expect(solver.isDatabaseLoaded(), isTrue);

    await tester.pumpWidget(const AlidadeApp());
    expect(find.text('Import from gallery'), findsOneWidget);
  });
}
