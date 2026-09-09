import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'about_screen.dart';
import 'constellation_lines.dart';
import 'db_manager.dart';
import 'db_manifest.dart';
import 'history.dart';
import 'history_page.dart';
import 'lens_picker.dart';
import 'lens_preset.dart';
import 'night_mode.dart';
import 'object_names.dart';
import 'rust_bridge/rust_bridge.dart' as solver;
import 'sky_target.dart';
import 'solve_outcome.dart';
import 'star_names.dart';
import 'star_overlay.dart';
import 'target_picker.dart';
import 'wcs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await solver.initRust();
  await StarNames.load();
  await ObjectNameCatalog.load();
  await NightMode.load();
  runApp(const AlidadeApp());
}

class AlidadeApp extends StatelessWidget {
  const AlidadeApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Matches the app icon's own background (pubspec.yaml's
    // adaptive_icon_background) so the app bar reads as a continuation of
    // the launcher icon rather than Material 3's slightly-tinted default
    // surface color for an elevated app bar.
    const backgroundColor = Color(0xFF0C0D13);
    return ValueListenableBuilder<bool>(
      valueListenable: NightMode.enabled,
      builder: (context, night, _) {
        // Deriving the *whole* scheme from the red seed (rather than
        // hand-specifying only a few ColorScheme.dark() fields) matters:
        // any role left unspecified — onSurfaceVariant, outline,
        // outlineVariant, surfaceContainerHighest — otherwise falls back to
        // Material's stock light-gray dark-theme defaults. In practice this
        // (and the theme-level ListTileTheme/CheckboxTheme overrides below)
        // didn't reliably cascade to every widget — history rows and
        // settings text still showed white/gray in places — so those
        // specific widgets now apply `dimNightModeColor` directly instead
        // of relying on theme inheritance; this scheme override is kept as
        // a reasonable fallback for anything not explicitly wired up yet.
        final dimNightColor = dimNightModeColor;
        final nightScheme =
            ColorScheme.fromSeed(
              seedColor: nightModeColor,
              brightness: Brightness.dark,
            ).copyWith(
              primary: nightModeColor,
              secondary: nightModeColor,
              surface: Colors.black,
              onSurface: nightModeColor,
              onSurfaceVariant: dimNightColor,
              outline: dimNightColor,
              outlineVariant: dimNightColor,
              error: nightModeColor,
            );
        final theme = night
            ? ThemeData(
                brightness: Brightness.dark,
                scaffoldBackgroundColor: Colors.black,
                appBarTheme: const AppBarTheme(
                  backgroundColor: Colors.black,
                  surfaceTintColor: Colors.transparent,
                  foregroundColor: nightModeColor,
                ),
                colorScheme: nightScheme,
                textTheme: Typography.whiteMountainView.apply(
                  bodyColor: nightModeColor,
                  displayColor: nightModeColor,
                ),
                iconTheme: const IconThemeData(color: nightModeColor),
                // Pinned explicitly: Material 3's default FilledButton
                // background derives from the seed via tonal palette
                // generation, which doesn't land on exactly `nightModeColor`
                // — pin it so the button truly matches the icon/text red
                // instead of a lighter/different shade of it.
                filledButtonTheme: FilledButtonThemeData(
                  style: FilledButton.styleFrom(
                    backgroundColor: nightModeColor,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: nightModeColor.withValues(
                      alpha: 0.3,
                    ),
                  ),
                ),
                checkboxTheme: CheckboxThemeData(
                  fillColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? nightModeColor
                        : null,
                  ),
                  side: BorderSide(color: dimNightColor),
                ),
                listTileTheme: ListTileThemeData(
                  textColor: nightModeColor,
                  subtitleTextStyle: TextStyle(
                    color: dimNightColor,
                    fontSize: 12,
                  ),
                ),
                outlinedButtonTheme: OutlinedButtonThemeData(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: nightModeColor,
                    side: const BorderSide(color: nightModeColor),
                  ),
                ),
                textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(foregroundColor: nightModeColor),
                ),
              )
            : ThemeData(
                brightness: Brightness.dark,
                colorSchemeSeed: const Color(0xFFDBA84E),
                scaffoldBackgroundColor: backgroundColor,
                appBarTheme: const AppBarTheme(
                  backgroundColor: backgroundColor,
                  surfaceTintColor: Colors.transparent,
                ),
              );
        return MaterialApp(
          title: 'Alidade - Plate Solver',
          theme: theme,
          home: const SolveScreen(),
        );
      },
    );
  }
}

class SolveScreen extends StatefulWidget {
  const SolveScreen({super.key});

  @override
  State<SolveScreen> createState() => _SolveScreenState();
}

class _SolveScreenState extends State<SolveScreen> {
  // Not required for solving (the app only ships one ~15.2° database, so a
  // hardcoded default with a generous error margin works without asking the
  // user anything) — kept only as a power-user override, reachable via the
  // "Advanced" button, not part of the required input flow.
  final _fovErrorController = TextEditingController(text: '8');
  final _resultNameController = TextEditingController();

  List<LensPreset> _lensPresets = [];
  LensPreset? _selectedLens;

  Uint8List? _imageBytes;
  bool _solving = false;
  SolveOutcome? _result;
  List<NamedStarPosition> _namedStars = [];
  List<List<Offset?>> _constellationLines = [];
  String? _currentHistoryId;
  bool _showMatchedCircles = true;
  bool _showNamedStars = true;
  bool _showConstellationLines = true;
  // The object chosen via the pre-solve target picker, if any — purely a
  // display aid today (see _runSolve): the solve itself stays blind
  // whether or not a target is set. _targetMarker is the projection of
  // _target through the current solve's WCS, recomputed by
  // _recomputeTargetMarker whenever either changes.
  SkyTarget? _target;
  TargetMarker? _targetMarker;
  bool _showTarget = true;
  StarLabelStyle _starLabelStyle = StarLabelStyle.catalogDesignations;
  int? _lastImageWidth;
  int? _lastImageHeight;
  // Which bucket's bytes are currently loaded into the Rust solver, so a
  // solve for the same lens twice in a row doesn't reload+reparse a
  // multi-MB database it already has. Cleared whenever a different lens
  // (mapping to a different bucket) is selected or solved with.
  String? _loadedBucketId;

  @override
  void initState() {
    super.initState();
    _loadLensPresets();
    _loadStarLabelStyle();
  }

  Future<void> _loadLensPresets() async {
    final presets = await LensPresetStore.load();
    if (!mounted) return;
    setState(() {
      _lensPresets = presets;
      _selectedLens = presets.isNotEmpty ? presets.first : null;
    });
    // No lens configured yet — true on a genuine first launch, but also
    // whenever the user has deleted every profile since. Either way,
    // remind them rather than silently leaving Solve disabled with no
    // explanation: there's no auto-created default to fall back on (see
    // LensPresetStore.load), since with per-lens databases now downloaded
    // on demand, a made-up default would point at the wrong bucket for
    // whatever lens they actually shoot with.
    if (presets.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showNoLensReminder();
      });
    }
  }

  Future<void> _showNoLensReminder() async {
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a lens to get started'),
        content: const Text(
          'Alidade solves using whichever lens/FOV profile is active. Add '
          'your camera + lens (or enter a FOV directly) in Settings before '
          'importing a photo to solve.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
    if (openSettings == true && mounted) await _openAdvancedSettings();
  }

  Future<void> _loadStarLabelStyle() async {
    final style = await StarLabelStylePref.load();
    setState(() => _starLabelStyle = style);
  }

  /// The current solve's WCS, or null if there's no successful solve to
  /// project through — shared by [_reprojectNamedStars] and
  /// [_recomputeTargetMarker] so the two don't construct it separately.
  SolvedWcs? get _currentWcs {
    final result = _result;
    final width = _lastImageWidth;
    final height = _lastImageHeight;
    if (result == null || !result.success || width == null || height == null) {
      return null;
    }
    return SolvedWcs(
      centerRaDeg: result.raDeg,
      centerDecDeg: result.decDeg,
      rollDeg: result.rollDeg,
      fovDeg: result.fovDeg,
      imageWidthPx: width,
      imageHeightPx: height,
    );
  }

  /// Re-projects named stars for the current result using whichever catalog
  /// is currently selected — used both right after solving and when the
  /// user changes the label-style preference, so switching styles updates
  /// the overlay immediately without needing to re-solve.
  Future<void> _reprojectNamedStars() async {
    final wcs = _currentWcs;
    if (wcs == null) return;
    final starNames = await StarNames.load();
    // A named star's WCS-projected position and its actual tetra3-matched
    // detection (if any) are two independently-computed estimates of the
    // same point — the projection is an idealized pinhole calculation from
    // catalog coordinates, the match is the real detected pixel centroid,
    // and our camera model has no lens-distortion correction, so they can
    // land a few pixels apart even for the same star. Show both circles at
    // their own real position rather than merging them — when a star has
    // both, the gap between its green and gold circle is itself useful
    // information (how far off the idealized pinhole model is at that spot
    // in the frame).
    final namedStars = <NamedStarPosition>[];
    for (final star in starNames.all) {
      final pos = wcs.project(star.raDeg, star.decDeg);
      if (pos == null) continue;
      namedStars.add(NamedStarPosition(pos.dx, pos.dy, star.name));
    }

    final constellations = await ConstellationLines.load();
    final lines = <List<Offset?>>[];
    for (final constellation in constellations.all) {
      for (final polyline in constellation.polylines) {
        lines.add([for (final p in polyline) wcs.project(p.raDeg, p.decDeg)]);
      }
    }

    setState(() {
      _namedStars = namedStars;
      _constellationLines = lines;
    });
  }

  /// Projects the chosen target through the current solve — a sibling of
  /// [_reprojectNamedStars], not folded into it: that method is
  /// await-heavy and iterates thousands of catalog entries, while this is
  /// one synchronous projection that must also run right after a bare
  /// target change (picking or clearing), not just after a solve.
  void _recomputeTargetMarker() {
    final wcs = _currentWcs;
    final target = _target;
    if (wcs == null || target == null) {
      if (_targetMarker != null) setState(() => _targetMarker = null);
      return;
    }
    final projection = wcs.projectUnclipped(target.raDeg, target.decDeg);
    setState(
      () => _targetMarker = TargetMarker(
        name: target.displayName,
        status: projection.status,
        position: projection.position,
        direction: projection.direction,
        separationDeg: projection.separationDeg,
      ),
    );
  }

  /// Persists the current target selection to the in-progress history
  /// entry, if a solve has already been saved — a no-op otherwise (picking
  /// a target before solving has nothing to persist to yet; _solve itself
  /// includes the target when it first creates the entry).
  void _persistTargetToHistory() {
    final id = _currentHistoryId;
    if (id == null) return;
    HistoryStore.setTarget(id, _target?.toJson());
  }

  Future<void> _pickTarget() async {
    final picked = await showTargetPicker(context, initial: _target);
    if (picked == null || !mounted) return;
    setState(() => _target = picked);
    _recomputeTargetMarker();
    _persistTargetToHistory();
  }

  void _clearTarget() {
    setState(() {
      _target = null;
      _targetMarker = null;
    });
    _persistTargetToHistory();
  }

  @override
  void dispose() {
    _fovErrorController.dispose();
    _resultNameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final rawBytes = await picked.readAsBytes();
    // Bake the EXIF orientation into the pixel data once, here, so every
    // consumer (display, solving, the star-highlight overlay, history
    // thumbnails) shares one unambiguous layout. Rust's `image` crate does
    // not auto-rotate on decode, and Flutter's own image widgets are
    // inconsistent about honoring EXIF across platforms — normalizing once
    // removes the disagreement instead of trying to keep two decoders in
    // sync (this is what caused portrait photos to display sideways with
    // misplaced star-highlight circles).
    final bytes = await solver.normalizeOrientationBytes(rawBytes);
    setState(() {
      _imageBytes = bytes;
      _result = null;
      _namedStars = [];
      _constellationLines = [];
      // _target itself is kept — framing the same object again shouldn't
      // require re-picking it — but the marker is stale until the next
      // solve projects it through the new image's WCS.
      _targetMarker = null;
      _currentHistoryId = null;
      _resultNameController.clear();
    });
  }

  Future<void> _openAdvancedSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Settings'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                // Explicit rather than trusting theme-derived roles (see
                // history_page.dart's build() for why): those didn't
                // reliably cascade to this dialog's field borders/subtitle
                // text either.
                final night = NightMode.enabled.value;
                final subtitleStyle = night
                    ? TextStyle(color: dimNightModeColor)
                    : null;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Lens / FOV profiles',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    LensProfileList(
                      presets: _lensPresets,
                      selected: _selectedLens,
                      onSelected: (p) =>
                          setDialogState(() => _selectedLens = p),
                      onPresetsChanged: (presets) {
                        // Reclaiming a removed preset's now-unused database
                        // storage is handled inside LensProfileList itself
                        // (see its _remove) — that's also where the
                        // download-status cache lives, so the delete and
                        // the cache invalidation that must follow it stay
                        // in the same place.
                        setDialogState(() => _lensPresets = presets);
                        LensPresetStore.save(presets);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _fovErrorController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: night
                          ? const TextStyle(color: nightModeColor)
                          : null,
                      decoration: InputDecoration(
                        labelText: 'FOV error (±°)',
                        labelStyle: subtitleStyle,
                        border: const OutlineInputBorder(),
                        enabledBorder: night
                            ? OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: dimNightModeColor,
                                ),
                              )
                            : null,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.help_outline, size: 20),
                          tooltip: 'What is this?',
                          onPressed: _showFovErrorHelp,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Star labels',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    RadioGroup<StarLabelStyle>(
                      groupValue: _starLabelStyle,
                      onChanged: (style) async {
                        if (style == null) return;
                        setDialogState(() => _starLabelStyle = style);
                        setState(() => _starLabelStyle = style);
                        await StarLabelStylePref.save(style);
                        await _reprojectNamedStars();
                      },
                      child: Column(
                        children: [
                          RadioListTile<StarLabelStyle>(
                            value: StarLabelStyle.popularNames,
                            title: const Text('Popular names'),
                            subtitle: Text(
                              'e.g. "Deneb", ~67 famous stars',
                              style: subtitleStyle,
                            ),
                            dense: true,
                          ),
                          RadioListTile<StarLabelStyle>(
                            value: StarLabelStyle.catalogDesignations,
                            title: const Text('Catalog designations'),
                            subtitle: Text(
                              'e.g. "13 Vul", ~2,500 naked-eye stars',
                              style: subtitleStyle,
                            ),
                            dense: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    setState(() {});
  }

  /// Loads whichever bucket [bucket] is into the Rust solver, downloading
  /// it first (with a progress dialog) if it isn't cached locally yet.
  /// Returns false if the user cancels or the download fails, in which
  /// case the caller should not attempt to solve.
  Future<bool> _ensureDbReady(DbBucket bucket) async {
    if (_loadedBucketId == bucket.id) return true;
    if (!await DbManager.isDownloaded(bucket)) {
      if (!mounted) return false;
      final downloaded = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _DownloadDialog(bucket: bucket),
      );
      if (downloaded != true) return false;
    }
    final bytes = await DbManager.readBytes(bucket);
    await solver.loadDatabaseBytes(bytes);
    _loadedBucketId = bucket.id;
    return true;
  }

  /// The one place the solver is actually invoked. `hint` is deliberately
  /// unused today: choosing a target before solving is a display-only aid,
  /// and a solve must behave identically whether or not one is set — this
  /// is just the seam a future hinted solve (see spike/src/main.rs's
  /// solve_hint, using tetra3's attitude_hint/hint_uncertainty_rad) plugs
  /// into, and nowhere else.
  Future<SolveOutcome> _runSolve({
    required Uint8List bytes,
    required double fovDeg,
    required double fovErrorDeg,
    SkyTarget? hint,
  }) {
    return solver.solveImageBytes(
      imageBytes: bytes,
      fovDeg: fovDeg,
      fovErrorDeg: fovErrorDeg,
    );
  }

  Future<void> _solve() async {
    final bytes = _imageBytes;
    final lens = _selectedLens;
    if (bytes == null || lens == null) return;
    final fovErrorDeg = double.tryParse(_fovErrorController.text) ?? 8.0;

    // `bytes` has already been through normalizeOrientation, so its pixel
    // width/height are the actual "as viewed" dimensions — a portrait photo
    // has height > width here, and its pixel width maps to the sensor's
    // physical height (the short axis), not sensorWidthMm.
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final imageWidth = frame.image.width;
    final imageHeight = frame.image.height;
    // Only the dimensions are needed here — dispose immediately rather than
    // holding a decoded GPU texture alive for the whole solve (each `ui.Image`
    // from a manual decode like this owns native/GPU memory that Flutter's
    // own image cache doesn't know about and won't reclaim on its own).
    frame.image.dispose();
    final isPortrait = imageHeight > imageWidth;
    final fovDeg = lens.fovDegForImage(isPortrait: isPortrait);

    final ready = await _ensureDbReady(bucketForFovDeg(fovDeg));
    if (!ready || !mounted) return;

    setState(() => _solving = true);
    try {
      final result = await _runSolve(
        bytes: bytes,
        fovDeg: fovDeg,
        fovErrorDeg: fovErrorDeg,
        hint: _target,
      );

      setState(() {
        _result = result;
        _lastImageWidth = imageWidth;
        _lastImageHeight = imageHeight;
      });
      // Project every bundled named star (whichever catalog is selected)
      // through the solved WCS and keep whichever land inside the image —
      // independent of whether tetra3's small matched-verification set
      // happened to include them (it often doesn't: bright named stars are
      // commonly saturated/filtered out of that set even when clearly in
      // frame).
      await _reprojectNamedStars();
      _recomputeTargetMarker();

      if (result.success) {
        // Suggest a name from the nearest bundled catalog object to the
        // solved position ("what am I looking at"); fall back to a plain
        // timestamp if nothing is close enough to be a plausible match.
        final catalog = await ObjectNameCatalog.load();
        final nearest = catalog.nearestTo(
          result.raDeg,
          result.decDeg,
          maxSeparationDeg: result.fovDeg * 0.75,
        );
        final now = DateTime.now();
        final autoName =
            nearest?.displayName ??
            'Solve ${now.hour.toString().padLeft(2, '0')}:'
                '${now.minute.toString().padLeft(2, '0')}';
        final entries = await HistoryStore.add(
          imageBytes: bytes,
          name: autoName,
          imageWidth: frame.image.width,
          imageHeight: frame.image.height,
          raDeg: result.raDeg,
          decDeg: result.decDeg,
          fovDeg: result.fovDeg,
          rollDeg: result.rollDeg,
          matchedStars: result.matchedStars,
          rmseArcsec: result.rmseArcsec,
          solveTimeMs: result.solveTimeMs,
          matchedStarX: result.matchedStarX.toList(),
          matchedStarY: result.matchedStarY.toList(),
          target: _target?.toJson(),
        );
        setState(() {
          _currentHistoryId = entries.first.id;
          _resultNameController.text = autoName;
        });
      }
    } finally {
      setState(() => _solving = false);
    }
  }

  void _onResultNameChanged(String newName) {
    final id = _currentHistoryId;
    if (id == null || newName.trim().isEmpty) return;
    HistoryStore.rename(id, newName.trim());
  }

  /// Opens the history list; if the user taps a card, it pops back with
  /// that entry, and this screen loads it in place of whatever was on
  /// screen (rather than pushing a separate read-only detail page).
  Future<void> _openHistory() async {
    final entry = await Navigator.push<HistoryEntry>(
      context,
      MaterialPageRoute(builder: (context) => const HistoryListPage()),
    );
    if (entry != null) await _loadFromHistory(entry);
  }

  Future<void> _loadFromHistory(HistoryEntry entry) async {
    final bytes = await HistoryStore.fullImageBytes(entry);
    final result = SolveOutcome(
      success: true,
      raDeg: entry.raDeg,
      decDeg: entry.decDeg,
      fovDeg: entry.fovDeg,
      rollDeg: entry.rollDeg,
      matchedStars: entry.matchedStars,
      rmseArcsec: entry.rmseArcsec,
      solveTimeMs: entry.solveTimeMs,
      matchedStarX: entry.matchedStarX,
      matchedStarY: entry.matchedStarY,
    );
    final entryTarget = entry.target;
    setState(() {
      _imageBytes = bytes;
      _result = result;
      _lastImageWidth = entry.imageWidth;
      _lastImageHeight = entry.imageHeight;
      _currentHistoryId = entry.id;
      _resultNameController.text = entry.name;
      _target = entryTarget == null ? null : SkyTarget.fromJson(entryTarget);
    });
    await _reprojectNamedStars();
    _recomputeTargetMarker();
  }

  Future<void> _showFovErrorHelp() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('FOV error'),
        content: const Text(
          'How far off the selected lens\'s FOV estimate is allowed to be '
          'before the solve gives up — the solver searches within this '
          'window rather than requiring an exact match.\n\n'
          'Too narrow and a slightly-off estimate (wrong sensor crop, '
          'unusual aspect ratio, ...) can miss the true value entirely. '
          'Too wide and the search has more candidates to rule out, so it '
          'takes longer. 8° is a generous default that works well for '
          'most lenses without needing to be tuned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _showOverlayHelp() async {
    final night = NightMode.enabled.value;
    final matchedColor = night ? nightModeColor : const Color(0xFF33E07A);
    final namedColor = night ? nightModeColor : const Color(0xFFDBA84E);
    final targetColor = night ? nightModeColor : targetMarkerColor;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Matched stars & star names'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                children: [
                  Text(
                    'Matched stars',
                    style: TextStyle(
                      color: matchedColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Every star the solver actually detected and used to '
                    'confirm the solve.',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                children: [
                  Text(
                    'Star names',
                    style: TextStyle(
                      color: namedColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Stars from the selected name catalog (Settings → Star '
                    'labels) that fall inside this frame, worked out from the '
                    'solved coordinates rather than from detection.',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'These are two independent calculations for the same sky, so '
                'a named star can show both circles a pixel or two apart '
                'rather than one (our lens model doesn\'t correct for real '
                'lens distortion). Alidade draws both instead of merging '
                'them, since the gap itself shows how far off the idealized '
                'projection is at that point in the frame.',
              ),
              const SizedBox(height: 12),
              Wrap(
                children: [
                  Text(
                    'Target',
                    style: TextStyle(
                      color: targetColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    ' — the object you chose before solving. A red star marks '
                    'it when it\'s inside this frame; when it isn\'t, a red '
                    'arrow at the frame edge points the way, labeled with how '
                    'far off you are.',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'In night mode every marker is the same red, so the target '
                'is told apart by its shape: it\'s the only star-shaped '
                'marker, and the only one with a dashed ring around it.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final bytes = _imageBytes;

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: ValueListenableBuilder<bool>(
            valueListenable: NightMode.enabled,
            builder: (context, night, _) => night
                // The full-color icon (dark background, cream/gold glyph)
                // doesn't belong on night mode's plain black app bar — tint
                // just the glyph (transparent background) red instead of
                // showing colors night mode otherwise avoids everywhere else.
                ? ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      nightModeColor,
                      BlendMode.srcIn,
                    ),
                    child: Image.asset(
                      'assets/icon/alidade_icon_foreground.png',
                    ),
                  )
                : Image.asset('assets/icon/alidade_icon.png'),
          ),
        ),
        title: const Text('Alidade'),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: NightMode.enabled,
            builder: (context, night, _) => IconButton(
              icon: Icon(
                night ? Icons.remove_red_eye : Icons.remove_red_eye_outlined,
              ),
              tooltip: night
                  ? 'Night mode: on (tap for normal colors)'
                  : 'Night mode (preserve night vision)',
              onPressed: NightMode.toggle,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Solve history',
            onPressed: _openHistory,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Settings',
            onPressed: _openAdvancedSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1. Image preview.
            if (bytes != null && result != null && result.success)
              ValueListenableBuilder<bool>(
                valueListenable: NightMode.enabled,
                builder: (context, night, _) => StarOverlayImage(
                  imageBytes: bytes,
                  matchedX: _showMatchedCircles
                      ? result.matchedStarX
                      : const [],
                  matchedY: _showMatchedCircles
                      ? result.matchedStarY
                      : const [],
                  namedStars: _showNamedStars ? _namedStars : const [],
                  constellationLines: _showConstellationLines
                      ? _constellationLines
                      : const [],
                  target: _showTarget ? _targetMarker : null,
                  overrideColor: night ? nightModeColor : null,
                  height: 320,
                ),
              )
            else if (bytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 320,
                  width: double.infinity,
                  color: Colors.black,
                  // contain, not cover: a portrait photo shouldn't be
                  // cropped down to a thin strip matching the box's width.
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              )
            else
              Container(
                height: 320,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text('No image selected'),
              ),
            const SizedBox(height: 12),

            // 2. Import from gallery.
            FilledButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Import from gallery'),
            ),

            // 3. Which lens/FOV to solve with — only shown once there's an
            // actual choice to make (2+ profiles configured); each maps to
            // its own downloadable database, so which one is selected
            // matters for both solve speed and whether a download prompt
            // appears. Add more via the Settings gear.
            if (_selectedLens != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: LensQuickSelector(
                  presets: _lensPresets,
                  selected: _selectedLens!,
                  onSelected: (p) => setState(() => _selectedLens = p),
                ),
              ),

            // 3b. Optional pre-solve target — purely a display aid (see
            // _runSolve): choosing one never gates Solve below, and
            // solving with none selected keeps working exactly as before.
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TargetSelectorField(
                target: _target,
                onPick: _pickTarget,
                onClear: _clearTarget,
              ),
            ),
            const SizedBox(height: 16),

            // 4. Solve.
            FilledButton.icon(
              onPressed:
                  (_imageBytes == null || _selectedLens == null || _solving)
                  ? null
                  : _solve,
              icon: _solving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.travel_explore),
              label: Text(_solving ? 'Solving…' : 'Solve'),
            ),
            if (result != null && result.success)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ValueListenableBuilder<bool>(
                  valueListenable: NightMode.enabled,
                  builder: (context, night, _) {
                    final matchedColor = night
                        ? nightModeColor
                        : const Color(0xFF33E07A);
                    final namedColor = night
                        ? nightModeColor
                        : const Color(0xFFDBA84E);
                    final lineColor = night
                        ? nightModeColor
                        : const Color(0xFF5C8AC9);
                    final targetColor = night
                        ? nightModeColor
                        : targetMarkerColor;
                    return Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      children: [
                        _OverlayToggle(
                          label: 'Matched stars',
                          color: matchedColor,
                          // Smaller swatch circle: matches the small,
                          // unlabeled circles actually drawn for these.
                          swatch: _MarkerSwatch.circle(
                            color: matchedColor,
                            radius: 4,
                          ),
                          value: _showMatchedCircles,
                          onChanged: (v) =>
                              setState(() => _showMatchedCircles = v),
                        ),
                        _OverlayToggle(
                          label: 'Star names',
                          color: namedColor,
                          // Bigger swatch circle: matches the larger,
                          // labeled circles actually drawn for these.
                          swatch: _MarkerSwatch.circle(
                            color: namedColor,
                            radius: 7,
                          ),
                          value: _showNamedStars,
                          onChanged: (v) => setState(() => _showNamedStars = v),
                        ),
                        _OverlayToggle(
                          label: 'Constellation lines',
                          color: lineColor,
                          swatch: _MarkerSwatch.line(color: lineColor),
                          value: _showConstellationLines,
                          onChanged: (v) =>
                              setState(() => _showConstellationLines = v),
                        ),
                        // Only shown once there's a marker to toggle — no
                        // dead checkbox before a target has been chosen
                        // and successfully projected.
                        if (_targetMarker != null)
                          _OverlayToggle(
                            label: 'Target',
                            color: targetColor,
                            swatch: _MarkerSwatch.star(
                              color: targetColor,
                              radius: 8,
                            ),
                            value: _showTarget,
                            onChanged: (v) => setState(() => _showTarget = v),
                          ),
                        IconButton(
                          icon: const Icon(Icons.help_outline, size: 20),
                          tooltip: 'What are these?',
                          onPressed: _showOverlayHelp,
                        ),
                      ],
                    );
                  },
                ),
              ),
            const SizedBox(height: 24),

            // 5. Results.
            if (result != null)
              _ResultCard(
                result: result,
                nameController: _currentHistoryId != null
                    ? _resultNameController
                    : null,
                onNameChanged: _onResultNameChanged,
                onOpenSettings: _openAdvancedSettings,
                target: _targetMarker,
              ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AboutScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: const Text('About'),
                ),
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed: () => openExternalUrl(sponsorUrl),
                  icon: const Icon(Icons.coffee_outlined, size: 18),
                  label: const Text('Buy me a coffee'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Blocking progress dialog shown when a solve needs a bucket that isn't
/// downloaded yet. Starts the download immediately; pops `true` on
/// success, `false` if the user cancels, and offers Retry in place on
/// failure rather than popping (so a flaky connection doesn't force the
/// user back through the whole "tap Solve" flow again).
class _DownloadDialog extends StatefulWidget {
  const _DownloadDialog({required this.bucket});

  final DbBucket bucket;

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  double? _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _progress = 0;
    });
    try {
      await DbManager.download(
        widget.bucket,
        onProgress: (received, total) {
          if (mounted && total > 0)
            setState(() => _progress = received / total);
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Downloading solver database'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.bucket.focalLengthRange} lenses · ${widget.bucket.sizeLabel}',
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else
            LinearProgressIndicator(value: _progress),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        if (_error != null)
          FilledButton(onPressed: _start, child: const Text('Retry')),
      ],
    );
  }
}

class _OverlayToggle extends StatelessWidget {
  const _OverlayToggle({
    required this.label,
    required this.color,
    required this.swatch,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final Color color;
  // A small sample of the actual marker (a circle at its real relative
  // size, or a line) so the toggle communicates what you'll see and how
  // big it'll be, not just a color-matched label.
  final Widget swatch;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? !value),
            fillColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected) ? color : null,
            ),
          ),
          swatch,
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

/// A tiny rendering of the actual overlay marker shown next to each
/// toggle's label — a circle at (roughly) the marker's real relative size,
/// or a diagonal line for the constellation-line toggle.
enum _SwatchKind { circle, line, star }

class _MarkerSwatch extends StatelessWidget {
  const _MarkerSwatch.circle({required Color color, required double radius})
    : _color = color,
      _radius = radius,
      _kind = _SwatchKind.circle;

  const _MarkerSwatch.line({required Color color})
    : _color = color,
      _radius = 0,
      _kind = _SwatchKind.line;

  const _MarkerSwatch.star({required Color color, required double radius})
    : _color = color,
      _radius = radius,
      _kind = _SwatchKind.star;

  final Color _color;
  final double _radius;
  final _SwatchKind _kind;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _MarkerSwatchPainter(_color, _radius, _kind)),
    );
  }
}

class _MarkerSwatchPainter extends CustomPainter {
  _MarkerSwatchPainter(this.color, this.radius, this.kind);

  final Color color;
  final double radius;
  final _SwatchKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = kind == _SwatchKind.line ? 2.5 : 1.8;
    switch (kind) {
      case _SwatchKind.line:
        canvas.drawLine(
          Offset(3, size.height - 3),
          Offset(size.width - 3, 3),
          paint,
        );
      case _SwatchKind.circle:
        canvas.drawCircle(
          Offset(size.width / 2, size.height / 2),
          radius,
          paint,
        );
      case _SwatchKind.star:
        // The real overlay marker's own path constructor — a true
        // miniature of what's actually drawn, not a lookalike.
        canvas.drawPath(
          targetStarPath(Offset(size.width / 2, size.height / 2), radius),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _MarkerSwatchPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.kind != kind;
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.nameController,
    required this.onNameChanged,
    required this.onOpenSettings,
    this.target,
  });

  final SolveOutcome result;
  final TextEditingController? nameController;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onOpenSettings;
  final TargetMarker? target;

  @override
  Widget build(BuildContext context) {
    if (!result.success) {
      return Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(result.error ?? 'Solve failed'),
              const SizedBox(height: 8),
              // The most common real-world cause of a failed solve is a
              // wrong FOV/lens estimate (too far off for the search
              // window to bracket the true value) rather than a bad
              // photo — surface the fix, not just the failure.
              const Text(
                'If this keeps happening, double-check the lens/FOV in '
                'Settings — a wrong estimate is the most common cause.',
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.tune),
                label: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      );
    }

    final raHms = _formatRaHms(result.raDeg);
    final decDms = _formatDecDms(result.decDeg);
    final coordText = 'RA  $raHms\nDec $decDms';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (nameController != null) ...[
              TextField(
                controller: nameController,
                onChanged: onNameChanged,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              coordText,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'FOV: ${result.fovDeg.toStringAsFixed(2)}°   '
              'Roll: ${result.rollDeg.toStringAsFixed(1)}°',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            Text(
              'Matched: ${result.matchedStars} stars (highlighted above)   '
              'RMSE: ${result.rmseArcsec.toStringAsFixed(1)}"',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            Text(
              'Solve time: ${result.solveTimeMs.toStringAsFixed(1)} ms',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            if (target != null)
              Text(
                _targetOffsetLine(target!),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: coordText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Coordinates copied')),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy RA/Dec'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The result card's one-line summary of where the chosen target ended up
/// relative to this solve — under 1 degree switches to arcminutes, since a
/// well-centered target (the interesting case) would otherwise read as an
/// unreadable "0.03°".
String _targetOffsetLine(TargetMarker target) {
  final sep = target.separationDeg;
  final distance = sep < 1
      ? '${(sep * 60).toStringAsFixed(1)}\''
      : '${sep.toStringAsFixed(2)}°';
  switch (target.status) {
    case SkyProjectionStatus.inFrame:
      return 'Target: ${target.name} — $distance from center (in frame)';
    case SkyProjectionStatus.offFrame:
      return 'Target: ${target.name} — $distance from center (outside frame)';
    case SkyProjectionStatus.behindCamera:
      return target.direction == Offset.zero
          ? 'Target: ${target.name} — $distance away (opposite side of the sky)'
          : 'Target: ${target.name} — $distance away (behind the camera)';
  }
}

String _formatRaHms(double raDeg) {
  final totalHours = raDeg / 15.0;
  final h = totalHours.floor();
  final remMin = (totalHours - h) * 60;
  final m = remMin.floor();
  final s = (remMin - m) * 60;
  return '${h.toString().padLeft(2, '0')}h '
      '${m.toString().padLeft(2, '0')}m '
      '${s.toStringAsFixed(1).padLeft(4, '0')}s';
}

String _formatDecDms(double decDeg) {
  final sign = decDeg < 0 ? '-' : '+';
  final absDeg = decDeg.abs();
  final d = absDeg.floor();
  final remMin = (absDeg - d) * 60;
  final m = remMin.floor();
  final s = (remMin - m) * 60;
  return '$sign${d.toString().padLeft(2, '0')}° '
      '${m.toString().padLeft(2, '0')}\' '
      '${s.toStringAsFixed(0).padLeft(2, '0')}"';
}
