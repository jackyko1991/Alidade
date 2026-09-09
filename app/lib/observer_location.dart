import 'package:geolocator/geolocator.dart';

/// The observer's position, to whatever precision matters here: longitude
/// (and latitude, for a possible future horizon/altitude check) for
/// sidereal-time math. Not persisted — re-requested (subject to
/// [ObserverLocation.load]'s in-memory cache) each time it's needed, since
/// unlike everything else this app stores, a location can go stale the
/// moment the user travels.
class ObserverLocation {
  const ObserverLocation({
    required this.latitudeDeg,
    required this.longitudeDeg,
  });

  final double latitudeDeg;
  final double longitudeDeg;
}

/// Why [ObserverLocation.load] returned null — lets the UI show a specific,
/// actionable message (open Settings vs. just try again) instead of one
/// generic "unavailable" string.
enum LocationUnavailableReason {
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  error,
}

class ObserverLocationResult {
  const ObserverLocationResult.available(this.location) : reason = null;

  const ObserverLocationResult.unavailable(this.reason) : location = null;

  final ObserverLocation? location;
  final LocationUnavailableReason? reason;

  bool get isAvailable => location != null;
}

/// Requests and caches the device's location for the target picker's
/// hour-angle / meridian-flip display. This is the only feature in the app
/// that uses location; solving itself never does.
class ObserverLocationService {
  static ObserverLocationResult? _cached;
  static DateTime? _cachedAt;

  /// A coarse fix is plenty for sidereal-time math (a few km of error is
  /// well under a second of time), so this deliberately asks for low
  /// accuracy — faster to obtain and a smaller privacy footprint than a
  /// precise GPS fix.
  static Future<ObserverLocationResult> load({
    bool forceRefresh = false,
  }) async {
    final cached = _cached;
    final cachedAt = _cachedAt;
    if (!forceRefresh &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 10)) {
      return cached;
    }

    final result = await _requestLocation();
    _cached = result;
    _cachedAt = DateTime.now();
    return result;
  }

  static Future<ObserverLocationResult> _requestLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const ObserverLocationResult.unavailable(
          LocationUnavailableReason.serviceDisabled,
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const ObserverLocationResult.unavailable(
          LocationUnavailableReason.permissionDenied,
        );
      }
      if (permission == LocationPermission.deniedForever) {
        return const ObserverLocationResult.unavailable(
          LocationUnavailableReason.permissionDeniedForever,
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return ObserverLocationResult.available(
        ObserverLocation(
          latitudeDeg: position.latitude,
          longitudeDeg: position.longitude,
        ),
      );
    } catch (_) {
      return const ObserverLocationResult.unavailable(
        LocationUnavailableReason.error,
      );
    }
  }
}
