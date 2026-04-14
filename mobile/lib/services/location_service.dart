import 'package:dart_geohash/dart_geohash.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Manages GPS location and geohash computation.
class LocationService {
  LocationService._();
  static final instance = LocationService._();

  Position? _lastPosition;
  final _geoHasher = GeoHasher();

  /// The last known position.
  Position? get lastPosition => _lastPosition;

  /// The last known geohash (6 chars = ~1.2km precision).
  String get lastGeohash {
    final pos = _lastPosition;
    if (pos == null) return '';
    return _geoHasher.encode(pos.longitude, pos.latitude, precision: 6);
  }

  /// Request permission and get current position.
  Future<Position?> getCurrentPosition() async {
    try {
      // Check if location services are enabled.
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[LocationService] location services disabled');
        return null;
      }

      // Check/request permission.
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('[LocationService] permission denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('[LocationService] permission permanently denied');
        return null;
      }

      // Get current position.
      _lastPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      debugPrint(
        '[LocationService] position: ${_lastPosition!.latitude}, '
        '${_lastPosition!.longitude} → geohash: $lastGeohash',
      );
      return _lastPosition;
    } catch (e) {
      debugPrint('[LocationService] error: $e');
      return null;
    }
  }

  /// Compute geohash from lat/lon.
  String computeGeohash(
    double latitude,
    double longitude, {
    int precision = 6,
  }) {
    return _geoHasher.encode(longitude, latitude, precision: precision);
  }
}
