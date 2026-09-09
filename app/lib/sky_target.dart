/// One row in the pre-solve target picker, whatever catalog it came from.
/// Coordinates are always geocentric J2000 equatorial degrees, so a target
/// can be handed straight to `SolvedWcs.project`/`projectUnclipped` (see
/// wcs.dart) or compared with a solve result without any frame conversion.
///
/// Deliberately separate from `NamedObject`/`NamedStar` (object_names.dart,
/// star_names.dart): those exist for reverse lookup (solved position ->
/// name), are gated by the user's chosen label style, and must keep
/// `ObjectNameCatalog.nearestTo` behaving exactly as it does today. This is
/// forward lookup (typed text -> position) across several unrelated source
/// catalogs, including two (planets, the Moon) that move.
library;

enum TargetKind {
  sun,
  moon,
  planet,
  messier,
  caldwell,
  ngc,
  ic,
  doubleStar,
  star,
}

class SkyTarget {
  const SkyTarget({
    required this.id,
    required this.displayName,
    required this.kind,
    required this.typeLabel,
    required this.raDeg,
    required this.decDeg,
    this.magnitude,
    this.constellation,
    this.aliases = const <String>[],
    this.separationArcsec,
    this.componentMagnitude,
    this.isDynamic = false,
  });

  /// Primary catalog id, e.g. "M31", "NGC 7000", "Jupiter", "HR 7001".
  final String id;

  /// Best display label: a popular nickname where one exists ("Andromeda
  /// Galaxy"), else the same as [id].
  final String displayName;

  final TargetKind kind;

  /// Human-readable type, e.g. "Galaxy", "Planetary Nebula", "Planet",
  /// "Double Star".
  final String typeLabel;

  /// Geocentric J2000 equatorial coordinates, degrees.
  final double raDeg;
  final double decDeg;

  /// Apparent visual magnitude, or null for the ~15% of deep-sky objects
  /// OpenNGC has no photometry for.
  final double? magnitude;

  /// IAU 3-letter abbreviation, e.g. "And". Null for the Sun/Moon/planets
  /// (their constellation changes with the date) and where the source
  /// catalog didn't supply one.
  final String? constellation;

  /// Alternate designations this target is also searchable by (e.g. "M31"
  /// carries "NGC 224" as an alias). Not shown in the UI.
  final List<String> aliases;

  /// [doubleStar] only: the pair's separation.
  final double? separationArcsec;

  /// [doubleStar] only: the secondary component's magnitude ([magnitude]
  /// is the primary's).
  final double? componentMagnitude;

  /// True for the Sun, Moon and planets: their position (and this target's
  /// [raDeg]/[decDeg]) depends on when the catalog was loaded, unlike every
  /// other fixed-catalog target.
  final bool isDynamic;

  /// The picker's secondary line, e.g. "M31 - Galaxy - And" or
  /// "Albireo - Double Star - 34.3\"".
  String get subtitle {
    final parts = <String>[id, typeLabel];
    if (kind == TargetKind.doubleStar && separationArcsec != null) {
      parts.add('${separationArcsec!.toStringAsFixed(1)}"');
    } else if (constellation != null) {
      parts.add(constellation!);
    }
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'kind': kind.name,
    'typeLabel': typeLabel,
    'raDeg': raDeg,
    'decDeg': decDeg,
    if (magnitude != null) 'magnitude': magnitude,
    if (constellation != null) 'constellation': constellation,
    if (aliases.isNotEmpty) 'aliases': aliases,
    if (separationArcsec != null) 'separationArcsec': separationArcsec,
    if (componentMagnitude != null) 'componentMagnitude': componentMagnitude,
    if (isDynamic) 'isDynamic': isDynamic,
  };

  factory SkyTarget.fromJson(Map<String, dynamic> json) => SkyTarget(
    id: json['id'] as String,
    displayName: json['displayName'] as String,
    kind: TargetKind.values.firstWhere((k) => k.name == json['kind']),
    typeLabel: json['typeLabel'] as String,
    raDeg: (json['raDeg'] as num).toDouble(),
    decDeg: (json['decDeg'] as num).toDouble(),
    magnitude: (json['magnitude'] as num?)?.toDouble(),
    constellation: json['constellation'] as String?,
    aliases: (json['aliases'] as List<dynamic>?)?.cast<String>() ?? const [],
    separationArcsec: (json['separationArcsec'] as num?)?.toDouble(),
    componentMagnitude: (json['componentMagnitude'] as num?)?.toDouble(),
    isDynamic: json['isDynamic'] as bool? ?? false,
  );

  /// Decodes one row of `assets/deepsky.json` (build_openngc.py's output):
  /// `[id, name|null, type, constellation|null, mag|null, ra_deg, dec_deg,
  /// aliases]`. A positional array rather than a keyed object - cheaper to
  /// parse at ~12,600 rows, unlike the few-hundred-row `double_stars.json`.
  factory SkyTarget.fromRow(List<dynamic> row) {
    final id = row[0] as String;
    final name = row[1] as String?;
    final TargetKind kind;
    if (RegExp(r'^M\d+$').hasMatch(id)) {
      kind = TargetKind.messier;
    } else if (RegExp(r'^C\d+$').hasMatch(id)) {
      kind = TargetKind.caldwell;
    } else if (id.startsWith('IC ')) {
      kind = TargetKind.ic;
    } else {
      kind = TargetKind.ngc;
    }
    return SkyTarget(
      id: id,
      displayName: name ?? id,
      kind: kind,
      typeLabel: row[2] as String,
      constellation: row[3] as String?,
      magnitude: (row[4] as num?)?.toDouble(),
      raDeg: (row[5] as num).toDouble(),
      decDeg: (row[6] as num).toDouble(),
      aliases: (row[7] as List<dynamic>).cast<String>(),
    );
  }

  /// Decodes one entry of `assets/double_stars.json` (build_wds.py's
  /// output): `{"id","name"|null,"label"|null,"mag","mag2","sep",
  /// "const"|null,"ra_deg","dec_deg"}`.
  factory SkyTarget.fromDoubleStarJson(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    final label = json['label'] as String?;
    return SkyTarget(
      id: json['id'] as String,
      displayName: name ?? label ?? json['id'] as String,
      kind: TargetKind.doubleStar,
      typeLabel: 'Double Star',
      constellation: json['const'] as String?,
      magnitude: (json['mag'] as num?)?.toDouble(),
      componentMagnitude: (json['mag2'] as num?)?.toDouble(),
      separationArcsec: (json['sep'] as num?)?.toDouble(),
      raDeg: (json['ra_deg'] as num).toDouble(),
      decDeg: (json['dec_deg'] as num).toDouble(),
      aliases: label == null ? const [] : [label],
    );
  }
}
