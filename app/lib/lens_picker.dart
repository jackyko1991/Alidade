import 'package:flutter/material.dart';

import 'lens_preset.dart';

/// A tappable chip showing the current lens/FOV choice; tapping opens a
/// bottom sheet to pick a saved preset, enter a direct FOV, or add a lens.
class LensPickerField extends StatefulWidget {
  const LensPickerField({
    super.key,
    required this.presets,
    required this.selected,
    required this.onSelected,
    required this.onPresetsChanged,
  });

  final List<LensPreset> presets;
  final LensPreset selected;
  final ValueChanged<LensPreset> onSelected;
  final ValueChanged<List<LensPreset>> onPresetsChanged;

  @override
  State<LensPickerField> createState() => _LensPickerFieldState();
}

class _LensPickerFieldState extends State<LensPickerField> {
  Future<void> _openPicker() async {
    final result = await showModalBottomSheet<_PickerResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _LensPickerSheet(
        presets: widget.presets,
        selected: widget.selected,
      ),
    );
    if (result == null) return;
    switch (result) {
      case _SelectPreset(:final preset):
        widget.onSelected(preset);
      case _AddPreset(:final preset):
        final updated = [...widget.presets, preset];
        widget.onPresetsChanged(updated);
        widget.onSelected(preset);
      case _RemovePreset(:final index):
        final updated = [...widget.presets]..removeAt(index);
        widget.onPresetsChanged(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _openPicker,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Lens / FOV',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.expand_more),
        ),
        child: Text(
          '${widget.selected.name}  ·  ${widget.selected.fovDeg.toStringAsFixed(2)}°',
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ),
    );
  }
}

sealed class _PickerResult {}

class _SelectPreset extends _PickerResult {
  _SelectPreset(this.preset);
  final LensPreset preset;
}

class _AddPreset extends _PickerResult {
  _AddPreset(this.preset);
  final LensPreset preset;
}

class _RemovePreset extends _PickerResult {
  _RemovePreset(this.index);
  final int index;
}

class _LensPickerSheet extends StatelessWidget {
  const _LensPickerSheet({required this.presets, required this.selected});

  final List<LensPreset> presets;
  final LensPreset selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Choose lens / FOV', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...presets.asMap().entries.map((entry) {
              final i = entry.key;
              final p = entry.value;
              final isSelected = p.name == selected.name;
              return ListTile(
                leading: Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                ),
                title: Text(p.name),
                subtitle: Text('${p.fovDeg.toStringAsFixed(2)}° horizontal FOV'),
                trailing: presets.length > 1
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () =>
                            Navigator.pop(context, _RemovePreset(i)),
                      )
                    : null,
                onTap: () => Navigator.pop(context, _SelectPreset(p)),
              );
            }),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add lens (focal length + sensor)'),
              onTap: () async {
                final preset = await showDialog<LensPreset>(
                  context: context,
                  builder: (context) => const _AddLensDialog(),
                );
                if (preset != null && context.mounted) {
                  Navigator.pop(context, _AddPreset(preset));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.straighten),
              title: const Text('Enter FOV directly'),
              onTap: () async {
                final preset = await showDialog<LensPreset>(
                  context: context,
                  builder: (context) => const _DirectFovDialog(),
                );
                if (preset != null && context.mounted) {
                  Navigator.pop(context, _AddPreset(preset));
                }
              },
            ),
          ],
        ),
      ),
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
