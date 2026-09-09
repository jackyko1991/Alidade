import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alidade/star_overlay.dart';
import 'package:alidade/wcs.dart';

// A minimal valid 1x1 black PNG, built offline rather than via dart:ui at
// test time - the software test binding's rasterizer isn't guaranteed to
// be available, and this only needs to be *decodable*, not a real photo.
final _tinyPngBytes = Uint8List.fromList([
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  2,
  0,
  0,
  0,
  144,
  119,
  83,
  222,
  0,
  0,
  0,
  12,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  96,
  96,
  96,
  0,
  0,
  0,
  4,
  0,
  1,
  246,
  23,
  56,
  85,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
]);

void main() {
  group('starVertices', () {
    test('alternates outer and inner radii, starting straight up', () {
      const center = Offset(100, 100);
      const outer = 20.0;
      const inner = outer * 0.381966;
      final points = starVertices(center, outer, inner);

      expect(points, hasLength(10));
      expect((points[0] - center).dy, closeTo(-outer, 1e-9));
      expect((points[0] - center).dx, closeTo(0, 1e-9));

      for (var i = 0; i < points.length; i++) {
        final expectedRadius = i.isEven ? outer : inner;
        expect((points[i] - center).distance, closeTo(expectedRadius, 1e-9));
      }
    });
  });

  group('_StarPainter (via StarOverlayImage) paints without throwing', () {
    Future<void> pumpWithTarget(
      WidgetTester tester,
      TargetMarker? target,
    ) async {
      final bytes = _tinyPngBytes;
      await tester.pumpWidget(
        MaterialApp(
          home: StarOverlayImage(
            imageBytes: bytes,
            matchedX: const [],
            matchedY: const [],
            target: target,
          ),
        ),
      );
      // Not pumpAndSettle(): the widget shows a CircularProgressIndicator
      // until the async image decode completes, and that spinner's
      // repeating animation never "settles" - a few explicit pumps let
      // the decode's microtasks/futures resolve instead.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('in-frame target', (tester) async {
      await pumpWithTarget(
        tester,
        const TargetMarker(
          name: 'M31',
          status: SkyProjectionStatus.inFrame,
          position: Offset(2, 2),
          direction: Offset(1, 0),
          separationDeg: 0.1,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('off-frame target', (tester) async {
      await pumpWithTarget(
        tester,
        const TargetMarker(
          name: 'M31',
          status: SkyProjectionStatus.offFrame,
          position: Offset(50, 50),
          direction: Offset(0.6, 0.8),
          separationDeg: 12.4,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('behind-camera target with a direction', (tester) async {
      await pumpWithTarget(
        tester,
        TargetMarker(
          name: 'M31',
          status: SkyProjectionStatus.behindCamera,
          position: null,
          direction: Offset(1, 0) / math.sqrt(1),
          separationDeg: 100,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'exactly antipodal target (zero direction) draws nothing extra',
      (tester) async {
        await pumpWithTarget(
          tester,
          const TargetMarker(
            name: 'M31',
            status: SkyProjectionStatus.behindCamera,
            position: null,
            direction: Offset.zero,
            separationDeg: 180,
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('no target at all', (tester) async {
      await pumpWithTarget(tester, null);
      expect(tester.takeException(), isNull);
    });
  });
}
