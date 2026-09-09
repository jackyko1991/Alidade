import 'dart:async';

import 'package:flutter/material.dart';

import 'observer_location.dart';
import 'sidereal.dart';
import 'sky_target.dart';

/// Shows the chosen target's current Hour Angle and time to (or since) its
/// meridian flip — the display a German-equatorial mount user wants next
/// to the pre-solve target field and in the result card. Renders nothing
/// when [target] is null. Manages its own location fetch (via
/// [ObserverLocationService], the app's one location-using feature) and a
/// periodic refresh, so callers don't need to thread any of that through
/// their own state.
///
/// Deliberately no explicit color/night-mode parameter: like the rest of
/// `_ResultCard`'s plain `Text` widgets, this relies on the surrounding
/// `Theme` (already switched to the night palette by `AlidadeApp`) for its
/// default text color rather than reading `NightMode.enabled` itself.
class MeridianStatusLine extends StatefulWidget {
  const MeridianStatusLine({super.key, required this.target});

  final SkyTarget? target;

  @override
  State<MeridianStatusLine> createState() => _MeridianStatusLineState();
}

class _MeridianStatusLineState extends State<MeridianStatusLine> {
  ObserverLocationResult? _locationResult;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(covariant MeridianStatusLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target?.id != widget.target?.id) _restart();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _restart() {
    _ticker?.cancel();
    if (widget.target == null) return;
    _loadLocation();
    // Hour Angle advances ~7.5 deg (30 min of HA) every 30s, so this keeps
    // the countdown visibly live without recomputing every frame; the
    // location itself isn't re-fetched this often (see ObserverLocationService's
    // own 10-minute cache).
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadLocation({bool forceRefresh = false}) async {
    final result = await ObserverLocationService.load(
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    setState(() => _locationResult = result);
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    if (target == null) return const SizedBox.shrink();

    final result = _locationResult;
    const style = TextStyle(fontFamily: 'monospace', fontSize: 12);

    if (result == null) {
      return const Text('Locating…', style: style);
    }
    if (!result.isAvailable) {
      return InkWell(
        onTap: () => _loadLocation(forceRefresh: true),
        child: Text(
          _unavailableMessage(result.reason!),
          style: style.copyWith(decoration: TextDecoration.underline),
        ),
      );
    }

    final utc = DateTime.now().toUtc();
    final ha = hourAngleDeg(target.raDeg, utc, result.location!.longitudeDeg);
    final flip = timeToMeridian(ha);
    return Text('${_formatHourAngle(ha)} · ${_formatFlip(flip)}', style: style);
  }
}

String _unavailableMessage(LocationUnavailableReason reason) =>
    switch (reason) {
      LocationUnavailableReason.permissionDenied =>
        'Tap to allow location (for hour angle)',
      LocationUnavailableReason.permissionDeniedForever =>
        'Location blocked — enable it in system settings',
      LocationUnavailableReason.serviceDisabled =>
        'Turn on location services for hour angle',
      LocationUnavailableReason.error => 'Tap to retry — location unavailable',
    };

/// "HA -1h23m" / "HA +0h05m".
String _formatHourAngle(double haDeg) {
  final totalMinutes = (haDeg.abs() / 15 * 60).round();
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  final sign = haDeg < 0 ? '-' : '+';
  return 'HA $sign${h}h${m.toString().padLeft(2, '0')}m';
}

/// "flip in 2h37m" while still approaching the meridian, "past meridian
/// 0h12m ago" once it's behind — the two situations a GEM user cares about
/// differently (plan ahead vs. flip now).
String _formatFlip(Duration untilFlip) {
  final past = untilFlip.isNegative;
  final magnitude = past ? -untilFlip : untilFlip;
  final h = magnitude.inHours;
  final m = magnitude.inMinutes % 60;
  final text = '${h}h${m.toString().padLeft(2, '0')}m';
  return past ? 'past meridian $text ago' : 'flip in $text';
}
