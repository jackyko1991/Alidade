import 'dart:async';

import 'package:flutter/material.dart';

import 'night_mode.dart';
import 'sky_target.dart';
import 'target_catalog.dart';

/// Pushes the target picker and returns the chosen [SkyTarget], or null if
/// the user backed out without choosing one — mirrors how the main screen
/// already opens history (`_openHistory` in main.dart: push a page, await
/// a value, apply it if non-null).
Future<SkyTarget?> showTargetPicker(
  BuildContext context, {
  SkyTarget? initial,
  TargetCatalog? catalog,
}) {
  return Navigator.push<SkyTarget>(
    context,
    MaterialPageRoute(
      builder: (context) =>
          TargetPickerPage(initial: initial, catalog: catalog),
    ),
  );
}

/// The category filter shown in the picker's dropdown. Deliberately not
/// the same as [TargetKind]: several kinds (Messier/Caldwell/NGC/IC; Sun/
/// Moon/planet) read as one user-facing group, matching the reference
/// app's own category list.
enum PickerCategory { all, stars, deepSky, doubleStars, planets }

extension on PickerCategory {
  String get label => switch (this) {
    PickerCategory.all => 'All',
    PickerCategory.stars => 'Stars',
    PickerCategory.deepSky => 'Deep sky',
    PickerCategory.doubleStars => 'Doubles',
    PickerCategory.planets => 'Planets',
  };

  bool matches(TargetKind kind) => switch (this) {
    PickerCategory.all => true,
    PickerCategory.stars => kind == TargetKind.star,
    PickerCategory.deepSky =>
      kind == TargetKind.messier ||
          kind == TargetKind.caldwell ||
          kind == TargetKind.ngc ||
          kind == TargetKind.ic,
    PickerCategory.doubleStars => kind == TargetKind.doubleStar,
    PickerCategory.planets =>
      kind == TargetKind.sun ||
          kind == TargetKind.moon ||
          kind == TargetKind.planet,
  };
}

/// A full-screen, pushed search page over every bundled sky-target
/// catalog — modeled on the reference telescope app's own target picker
/// (a category combobox above a search field, results below). Chosen
/// over a dialog (too height-constrained for a filterable list with the
/// keyboard up — even the short Settings *form* needs
/// `SizedBox(width: double.maxFinite)` + a scroll view) and over Material
/// 3's `SearchAnchor` (its view is themed through surfaces this app has
/// already found don't reliably cascade night-mode colors, and it has no
/// natural slot for a persistent category dropdown).
class TargetPickerPage extends StatefulWidget {
  const TargetPickerPage({super.key, this.initial, this.catalog});

  final SkyTarget? initial;

  /// Injection seam for tests; defaults to the real singleton catalog.
  final TargetCatalog? catalog;

  @override
  State<TargetPickerPage> createState() => _TargetPickerPageState();
}

class _TargetPickerPageState extends State<TargetPickerPage> {
  final _queryController = TextEditingController();
  Timer? _debounce;
  PickerCategory _category = PickerCategory.all;
  List<SkyTarget> _results = const [];
  bool _catalogReady = false;
  TargetCatalog? _catalog;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final catalog = widget.catalog ?? await TargetCatalog.load();
    if (!mounted) return;
    setState(() {
      _catalog = catalog;
      _catalogReady = true;
    });
    _runSearch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _runSearch);
  }

  void _runSearch() {
    final catalog = _catalog;
    if (catalog == null) return;
    // Over-fetch, then filter by the UI-level category client-side:
    // TargetCatalog.search's `category` is one TargetKind, but several
    // kinds (all four deep-sky kinds; Sun/Moon/planet) read as one group
    // here — see PickerCategory.matches.
    final raw = catalog.search(_queryController.text, limit: 200);
    final filtered = raw
        .where((t) => _category.matches(t.kind))
        .take(50)
        .toList();
    if (!mounted) return;
    setState(() => _results = filtered);
  }

  void _onCategoryChanged(PickerCategory? category) {
    if (category == null) return;
    setState(() => _category = category);
    _runSearch();
  }

  void _clearQuery() {
    _queryController.clear();
    _runSearch();
  }

  @override
  Widget build(BuildContext context) {
    final night = NightMode.enabled.value;
    final titleColor = night ? nightModeColor : null;
    final subtitleColor = night
        ? dimNightModeColor
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final dividerColor = night
        ? dimNightModeColor
        : Theme.of(context).dividerColor;
    final borderColor = night
        ? OutlineInputBorder(borderSide: BorderSide(color: dimNightModeColor))
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Choose target')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<PickerCategory>(
                      initialValue: _category,
                      decoration: InputDecoration(
                        labelText: 'Category',
                        labelStyle: night
                            ? TextStyle(color: subtitleColor)
                            : null,
                        border: const OutlineInputBorder(),
                        enabledBorder: borderColor,
                        isDense: true,
                      ),
                      items: PickerCategory.values
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(c.label),
                            ),
                          )
                          .toList(),
                      onChanged: _onCategoryChanged,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _queryController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      style: night ? TextStyle(color: titleColor) : null,
                      onChanged: _onQueryChanged,
                      decoration: InputDecoration(
                        labelText: 'Search targets',
                        labelStyle: night
                            ? TextStyle(color: subtitleColor)
                            : null,
                        border: const OutlineInputBorder(),
                        enabledBorder: borderColor,
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Clear search',
                          onPressed: _clearQuery,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            Expanded(
              child: !_catalogReady
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty && _queryController.text.trim().isNotEmpty
                  ? Center(
                      child: Text(
                        'No targets match "${_queryController.text.trim()}"',
                        style: TextStyle(color: subtitleColor),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (context, index) =>
                          Divider(height: 1, color: dividerColor),
                      itemBuilder: (context, index) {
                        final target = _results[index];
                        return TargetResultTile(
                          target: target,
                          selected: target.id == widget.initial?.id,
                          night: night,
                          onTap: () => Navigator.pop(context, target),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One result row: name + magnitude on top, catalog id/type/constellation
/// (or, for a double star, its separation) beneath. Public and stateless
/// so a widget test can pump it directly without a catalog.
class TargetResultTile extends StatelessWidget {
  const TargetResultTile({
    super.key,
    required this.target,
    required this.selected,
    required this.onTap,
    required this.night,
  });

  final SkyTarget target;
  final bool selected;
  final VoidCallback onTap;
  final bool night;

  @override
  Widget build(BuildContext context) {
    final titleColor = night ? nightModeColor : null;
    final subtitleColor = night
        ? dimNightModeColor
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return ListTile(
      onTap: onTap,
      selected: selected,
      minVerticalPadding: 10,
      title: Row(
        children: [
          Expanded(
            child: Text(
              target.displayName,
              style: TextStyle(color: titleColor, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formatMagnitude(target.magnitude),
            style: TextStyle(color: titleColor),
          ),
        ],
      ),
      subtitle: Text(
        targetSecondaryLine(target),
        style: TextStyle(color: subtitleColor),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(Icons.chevron_right, size: 20, color: titleColor),
    );
  }
}

/// The picker row's secondary line, e.g. "M31 · Galaxy · And" — pure, so
/// it's unit-testable without pumping a widget.
String targetSecondaryLine(SkyTarget t) => t.subtitle;

/// "-1.6" / "4.2" / "—" for null — pure, unit-testable.
String formatMagnitude(double? mag) =>
    mag == null ? '—' : mag.toStringAsFixed(1);

/// The main screen's optional "Target" row: renders like the lens dropdown
/// (an `InputDecorator` in the same `OutlineInputBorder`/`isDense` style)
/// but taps through to the full [TargetPickerPage] rather than opening
/// inline, since there's no inline control that fits hundreds of catalog
/// rows. Wrapped in an explicit [Semantics] label so e2e/accessibility
/// tooling has a stable name to find, independent of how Material
/// composes the InputDecorator's own label + value into one.
class TargetSelectorField extends StatelessWidget {
  const TargetSelectorField({
    super.key,
    required this.target,
    required this.onPick,
    required this.onClear,
  });

  final SkyTarget? target;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final night = NightMode.enabled.value;
    final dimColor = night
        ? dimNightModeColor
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final fullColor = night ? nightModeColor : null;
    final borderColor = night
        ? OutlineInputBorder(borderSide: BorderSide(color: dimNightModeColor))
        : null;

    return Semantics(
      button: true,
      label: 'Choose target',
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Target (optional)',
            labelStyle: night ? TextStyle(color: dimColor) : null,
            border: const OutlineInputBorder(),
            enabledBorder: borderColor,
            isDense: true,
            prefixIcon: Icon(
              Icons.my_location,
              size: 20,
              color: night ? dimColor : null,
            ),
            suffixIcon: target == null
                ? Icon(Icons.search, color: night ? dimColor : null)
                : IconButton(
                    icon: Icon(Icons.clear, color: night ? dimColor : null),
                    tooltip: 'Clear target',
                    onPressed: onClear,
                  ),
          ),
          child: Text(
            target?.displayName ?? 'None — solve blind',
            style: TextStyle(color: target == null ? dimColor : fullColor),
          ),
        ),
      ),
    );
  }
}
