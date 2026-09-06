import 'package:flutter/material.dart';

import 'db_manager.dart';
import 'db_manifest.dart';
import 'lens_preset.dart';

/// Compact quick-switch control for the main screen: a dropdown listing
/// every saved lens preset, pick one to make it active for the next
/// solve. Hidden entirely with 0-1 presets — nothing to choose between
/// yet, and the main screen stays minimal until the user actually has
/// more than one lens configured (add more via Settings).
class LensQuickSelector extends StatelessWidget {
  const LensQuickSelector({
    super.key,
    required this.presets,
    required this.selected,
    required this.onSelected,
  });

  final List<LensPreset> presets;
  final LensPreset selected;
  final ValueChanged<LensPreset> onSelected;

  @override
  Widget build(BuildContext context) {
    if (presets.length <= 1) return const SizedBox.shrink();
    return DropdownButtonFormField<String>(
      initialValue: selected.name,
      decoration: const InputDecoration(
        labelText: 'Lens',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: presets
          .map(
            (p) => DropdownMenuItem(
              value: p.name,
              child: Text('${p.name} · ${p.fovDeg.toStringAsFixed(1)}°'),
            ),
          )
          .toList(),
      onChanged: (name) {
        final preset = presets.firstWhere((p) => p.name == name, orElse: () => selected);
        onSelected(preset);
      },
    );
  }
}

/// The full editable list of lens/FOV profiles shown in Settings: each
/// row can be selected, downloaded (its FOV bucket's database), or
/// deleted, plus "Add lens" / "Direct FOV" actions below. Replaces an
/// earlier design where this lived behind a separate modal-bottom-sheet
/// picker — folding it directly into the Settings dialog removes a layer
/// of indirection between "tap download" and the button actually
/// responding.
class LensProfileList extends StatefulWidget {
  const LensProfileList({
    super.key,
    required this.presets,
    required this.selected,
    required this.onSelected,
    required this.onPresetsChanged,
  });

  final List<LensPreset> presets;
  // Nullable: the list can be emptied down to zero profiles (see _remove)
  // — Settings still needs to render (with just "Add lens"/"Direct FOV")
  // rather than disappear, so this can't require a non-null selection.
  final LensPreset? selected;
  final ValueChanged<LensPreset?> onSelected;
  final ValueChanged<List<LensPreset>> onPresetsChanged;

  @override
  State<LensProfileList> createState() => _LensProfileListState();
}

class _LensProfileListState extends State<LensProfileList> {
  // bucketId -> downloaded? / 0..1 in-flight progress. A bucket is often
  // shared by several presets (e.g. two lenses that both land in the
  // 100-180mm bucket), so this is keyed by bucket, not by preset.
  final Map<String, bool> _downloaded = {};
  final Map<String, double?> _progress = {};

  @override
  void initState() {
    super.initState();
    _refreshDownloadStatus();
  }

  Future<void> _refreshDownloadStatus() async {
    for (final bucket in dbBuckets) {
      final has = await DbManager.isDownloaded(bucket);
      if (mounted) setState(() => _downloaded[bucket.id] = has);
    }
  }

  Future<void> _download(DbBucket bucket) async {
    setState(() => _progress[bucket.id] = 0);
    try {
      await DbManager.download(
        bucket,
        onProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() => _progress[bucket.id] = received / total);
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _progress.remove(bucket.id);
        _downloaded[bucket.id] = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _progress.remove(bucket.id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  Future<void> _addLens() async {
    final preset = await showDialog<LensPreset>(
      context: context,
      builder: (context) => const _AddLensDialog(),
    );
    if (preset == null || !mounted) return;
    widget.onPresetsChanged([...widget.presets, preset]);
    widget.onSelected(preset);
  }

  Future<void> _addDirectFov() async {
    final preset = await showDialog<LensPreset>(
      context: context,
      builder: (context) => const _DirectFovDialog(),
    );
    if (preset == null || !mounted) return;
    widget.onPresetsChanged([...widget.presets, preset]);
    widget.onSelected(preset);
  }

  Future<void> _remove(int index) async {
    final removed = widget.presets[index];
    final updated = [...widget.presets]..removeAt(index);
    final bucket = bucketForFovDeg(removed.fovDeg);
    final remainingFovDegs = updated.map((p) => p.fovDeg).toList();
    // Reclaim the bucket's storage here, in the same place that owns
    // `_downloaded` — deleting it from the caller's `onPresetsChanged`
    // left this widget's cached download status stale (still `true` from
    // before the delete), so a newly-added preset landing in the same
    // bucket would show an already-downloaded tick for a file that was
    // actually just removed from disk.
    await DbManager.deleteIfUnused(bucket, remainingFovDegs);
    final stillDownloaded = await DbManager.isDownloaded(bucket);
    if (mounted) setState(() => _downloaded[bucket.id] = stillDownloaded);
    widget.onPresetsChanged(updated);
    if (removed.name == widget.selected?.name) {
      // Removed the active preset: fall back to whatever's left, or to
      // no selection at all if that was the last one — "Add lens"/
      // "Direct FOV" stay available either way to get back to one.
      widget.onSelected(updated.isNotEmpty ? updated.first : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...widget.presets.asMap().entries.map((entry) {
          final i = entry.key;
          final p = entry.value;
          final isSelected = p.name == widget.selected?.name;
          final bucket = bucketForFovDeg(p.fovDeg);
          final isDownloaded = _downloaded[bucket.id] ?? false;
          final progress = _progress[bucket.id];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            // Selection is shown via the tile's own selected-state tint
            // (title/subtitle color) rather than a separate radio icon —
            // tapping the row already selects it, so the icon was a
            // second, redundant way to show the same state.
            selected: isSelected,
            title: Text(p.name),
            subtitle: Text(
              '${p.fovDeg.toStringAsFixed(2)}° · DB: ${bucket.focalLengthRange}'
              '${isDownloaded ? '' : ' (${bucket.sizeLabel})'}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (progress != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5, value: progress),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 34,
                        child: Text(
                          '${(progress * 100).round()}%',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    ],
                  )
                else if (!isDownloaded)
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      icon: const Icon(Icons.download_outlined),
                      tooltip: 'Download database (${bucket.sizeLabel})',
                      onPressed: () => _download(bucket),
                    ),
                  )
                else
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(Icons.check_circle_outline, color: Color(0xFF33E07A), size: 20),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _remove(i),
                ),
              ],
            ),
            onTap: () => widget.onSelected(p),
          );
        }),
        const Divider(),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: _addLens,
                icon: const Icon(Icons.add),
                label: const Text('Add lens'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: _addDirectFov,
                icon: const Icon(Icons.straighten),
                label: const Text('Direct FOV'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AddLensDialog extends StatefulWidget {
  const _AddLensDialog();

  @override
  State<_AddLensDialog> createState() => _AddLensDialogState();
}

class _AddLensDialogState extends State<_AddLensDialog> {
  final _nameController = TextEditingController();
  final _focalLengthController = TextEditingController();
  String _sensorName = 'Full frame (35mm)';

  @override
  void dispose() {
    _nameController.dispose();
    _focalLengthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add lens'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name (e.g. "135mm, A7R")'),
          ),
          TextField(
            controller: _focalLengthController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Focal length (mm)'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _sensorName,
            decoration: const InputDecoration(labelText: 'Sensor'),
            items: commonSensorSizes.keys
                .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                .toList(),
            onChanged: (v) => setState(() => _sensorName = v ?? _sensorName),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final focalLength = double.tryParse(_focalLengthController.text);
            if (focalLength == null || focalLength <= 0) return;
            final name = _nameController.text.trim().isEmpty
                ? '${focalLength.toStringAsFixed(0)}mm'
                : _nameController.text.trim();
            final (sensorWidthMm, sensorHeightMm) = commonSensorSizes[_sensorName]!;
            Navigator.pop(
              context,
              LensPreset(
                name: name,
                focalLengthMm: focalLength,
                sensorWidthMm: sensorWidthMm,
                sensorHeightMm: sensorHeightMm,
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _DirectFovDialog extends StatefulWidget {
  const _DirectFovDialog();

  @override
  State<_DirectFovDialog> createState() => _DirectFovDialogState();
}

class _DirectFovDialogState extends State<_DirectFovDialog> {
  final _fovController = TextEditingController();

  @override
  void dispose() {
    _fovController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter FOV directly'),
      content: TextField(
        controller: _fovController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Horizontal FOV (°)'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final fov = double.tryParse(_fovController.text);
            if (fov == null || fov <= 0) return;
            Navigator.pop(
              context,
              LensPreset(name: '${fov.toStringAsFixed(1)}° (manual)', fovDegOverride: fov),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
