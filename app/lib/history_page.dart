import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'history.dart';
import 'night_mode.dart';

/// Full-page solve history list (replaces the earlier swipe-open Drawer —
/// a dedicated page gives the list room to breathe and lets tapping a card
/// hand the entry back to the caller). Tapping a card's body pops this page
/// with the tapped [HistoryEntry] as the result; the caller (the main solve
/// screen) is expected to load it into its own state. Each row also has an
/// always-visible checkbox (no hidden long-press mode to discover) — check
/// any number of entries and tap the app bar's delete icon to remove them.
class HistoryListPage extends StatefulWidget {
  const HistoryListPage({super.key});

  @override
  State<HistoryListPage> createState() => _HistoryListPageState();
}

class _HistoryListPageState extends State<HistoryListPage> {
  List<HistoryEntry> _entries = [];
  bool _loaded = false;
  final Set<String> _selected = {};
  // Cached per-entry, not recreated in the itemBuilder: a `FutureBuilder`
  // with a `future:` built fresh on every call restarts (and re-decodes)
  // every time ANY row rebuilds — checking one checkbox rebuilds the whole
  // list, which was re-decoding every visible thumbnail on every tap. That
  // GPU churn is what crashed the app natively (Impeller "ErrorDeviceLost"
  // followed by a Mali-driver abort, confirmed via logcat) after a bit of
  // scrolling/selecting. Decoding each thumbnail once and reusing the same
  // Future/bytes object across rebuilds removes the churn.
  final Map<String, Future<Uint8List>> _thumbnails = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await HistoryStore.load();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _thumbnails
        ..clear()
        ..addEntries(entries.map((e) => MapEntry(e.id, HistoryStore.thumbnailBytes(e))));
      _loaded = true;
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selected.length == _entries.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_entries.map((e) => e.id));
      }
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $count solve${count == 1 ? '' : 's'}?'),
        content: const Text('This removes the saved image and result. This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    var entries = _entries;
    for (final id in _selected) {
      entries = await HistoryStore.remove(id);
    }
    if (!mounted) return;
    setState(() {
      _entries = entries;
      for (final id in _selected) {
        _thumbnails.remove(id);
      }
      _selected.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Read once rather than via ValueListenableBuilder: this page is a
    // fresh instance every time it's pushed (the toggle lives on the main
    // screen's app bar, not here), so it can't go stale mid-view. Applied
    // explicitly rather than through theme roles like
    // ColorScheme.onSurfaceVariant/ListTileTheme, which didn't reliably
    // cascade to this row's subtitle/checkbox in practice.
    final night = NightMode.enabled.value;
    final subtitleColor = night ? dimNightModeColor : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Solve history'),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              icon: Icon(
                _selected.length == _entries.length
                    ? Icons.deselect
                    : Icons.select_all,
              ),
              tooltip: _selected.length == _entries.length ? 'Deselect all' : 'Select all',
              onPressed: _toggleSelectAll,
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete selected',
            onPressed: _selected.isEmpty ? null : _deleteSelected,
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? const Center(child: Text('No solves yet'))
          : ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final entry = _entries[index];
                final isSelected = _selected.contains(entry.id);
                return ListTile(
                  selected: isSelected,
                  leading: FutureBuilder(
                    future: _thumbnails[entry.id],
                    builder: (context, snapshot) {
                      final bytes = snapshot.data;
                      if (bytes == null) {
                        return const SizedBox(width: 56, height: 56);
                      }
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(
                          bytes,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      );
                    },
                  ),
                  title: Text(entry.name, style: night ? const TextStyle(color: nightModeColor) : null),
                  subtitle: Text(
                    'RA ${entry.raDeg.toStringAsFixed(2)}° '
                    'Dec ${entry.decDeg.toStringAsFixed(2)}°   '
                    '${entry.matchedStars} stars',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: subtitleColor),
                  ),
                  onTap: () => Navigator.pop(context, entry),
                  trailing: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleSelected(entry.id),
                    side: night ? BorderSide(color: dimNightModeColor) : null,
                  ),
                );
              },
            ),
    );
  }
}
