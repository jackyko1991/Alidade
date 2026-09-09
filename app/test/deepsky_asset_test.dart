// Guards the *generator scripts'* output (build_openngc.py, build_wds.py)
// rather than any Dart code: a bad regeneration - a mistranscribed column
// offset, a broken dedup pass - should fail here in CI, not surface as a
// wrong marker or a missing search result at runtime.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('deepsky.json (OpenNGC + Messier + Caldwell)', () {
    late List<dynamic> rows;

    setUpAll(() async {
      final raw = await rootBundle.loadString('assets/deepsky.json');
      rows = jsonDecode(raw) as List<dynamic>;
    });

    test('has a substantial number of rows', () {
      // OpenNGC proper (minus dropped duplicate/nonexistent/double-star
      // rows) is on the order of 12,000-13,000 objects.
      expect(rows.length, greaterThan(10000));
    });

    test('every row decodes with exactly 8 positional fields', () {
      for (final row in rows) {
        expect(row, isA<List<dynamic>>());
        expect((row as List<dynamic>).length, 8, reason: '$row');
      }
    });

    test('every coordinate is in range', () {
      for (final row in rows) {
        final list = row as List<dynamic>;
        final raDeg = (list[5] as num).toDouble();
        final decDeg = (list[6] as num).toDouble();
        expect(raDeg, inInclusiveRange(0, 360), reason: '${list[0]}');
        expect(decDeg, inInclusiveRange(-90, 90), reason: '${list[0]}');
      }
    });

    test('all 110 Messier objects are present exactly once', () {
      final messierIds = rows
          .map((r) => (r as List<dynamic>)[0] as String)
          .where((id) => RegExp(r'^M\d+$').hasMatch(id))
          .toList();
      final numbers = messierIds
          .map((id) => int.parse(id.substring(1)))
          .toSet();
      expect(messierIds.length, 110, reason: 'duplicates: $messierIds');
      expect(numbers, Set.from(List.generate(110, (i) => i + 1)));
    });

    test('all 109 Caldwell objects are present exactly once', () {
      final caldwellIds = rows
          .map((r) => (r as List<dynamic>)[0] as String)
          .where((id) => RegExp(r'^C\d+$').hasMatch(id))
          .toList();
      final numbers = caldwellIds
          .map((id) => int.parse(id.substring(1)))
          .toSet();
      expect(caldwellIds.length, 109, reason: 'duplicates: $caldwellIds');
      expect(numbers, Set.from(List.generate(109, (i) => i + 1)));
    });

    test('no two rows share an id - the actual dedup guarantee', () {
      // Deliberately NOT asserting alias uniqueness here: real astronomical
      // cross-designations legitimately overlap (e.g. two close galaxies
      // sharing one IRAS source name), so a shared alias is real-world data
      // noise, not a dedup failure. Id uniqueness is the load-bearing
      // invariant - it's what the search index and the picker's result
      // list actually key off.
      final ids = rows.map((r) => (r as List<dynamic>)[0] as String).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('at least 85% of rows carry a magnitude', () {
      final withMag = rows.where((r) => (r as List<dynamic>)[4] != null).length;
      expect(withMag / rows.length, greaterThanOrEqualTo(0.85));
    });
  });

  group('double_stars.json (Washington Double Star Catalog)', () {
    late List<dynamic> rows;

    setUpAll(() async {
      final raw = await rootBundle.loadString('assets/double_stars.json');
      rows = jsonDecode(raw) as List<dynamic>;
    });

    test('lands in the intended few-hundred-pair range', () {
      expect(rows.length, inInclusiveRange(150, 500));
    });

    test('every row has a plausible magnitude, separation and coordinate', () {
      for (final row in rows) {
        final map = row as Map<String, dynamic>;
        expect((map['mag'] as num).toDouble(), lessThanOrEqualTo(6.5));
        expect((map['mag2'] as num).toDouble(), lessThanOrEqualTo(9.5));
        if (map['sep'] != null) {
          expect((map['sep'] as num).toDouble(), inInclusiveRange(0, 300));
        }
        expect((map['ra_deg'] as num).toDouble(), inInclusiveRange(0, 360));
        expect((map['dec_deg'] as num).toDouble(), inInclusiveRange(-90, 90));
      }
    });

    test('every named pair the generator curated by hand is present', () {
      final names = rows
          .map((r) => (r as Map<String, dynamic>)['name'])
          .whereType<String>()
          .toSet();
      expect(
        names,
        containsAll(<String>[
          'Albireo',
          'Mizar',
          'Almach',
          'Castor',
          'Cor Caroli',
          'Rasalgethi',
        ]),
      );
    });

    test('no two rows share an id', () {
      final ids = rows
          .map((r) => (r as Map<String, dynamic>)['id'] as String)
          .toList();
      expect(ids.toSet().length, ids.length);
    });
  });
}
