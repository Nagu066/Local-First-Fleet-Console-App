import 'dart:math';

class DistanceCalculator {
  /// Calculates the Haversine distance in meters between two GPS coordinates.
  static double haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0; // Earth radius in meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  /// Calculates distance in kilometers between two points.
  static double haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return haversineMeters(lat1, lon1, lat2, lon2) / 1000.0;
  }

  static double _toRadians(double degree) {
    return degree * pi / 180.0;
  }

  /// Checks if a vehicle at (lat, lng) is inside circular geofence with (centerLat, centerLng, radiusMeters).
  /// [hysteresisMarginMeters] adds spatial dampening to prevent boundary flickering.
  static bool isInsideGeofence({
    required double lat,
    required double lng,
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
    double hysteresisMarginMeters = 10.0,
    bool currentlyInside = false,
  }) {
    final dist = haversineMeters(lat, lng, centerLat, centerLng);
    if (currentlyInside) {
      // Vehicle needs to move outside (radius + hysteresis) to trigger an exit
      return dist <= (radiusMeters + hysteresisMarginMeters);
    } else {
      // Vehicle needs to enter within (radius - hysteresis) to trigger an entry
      return dist <= (radiusMeters - hysteresisMarginMeters);
    }
  }
}
