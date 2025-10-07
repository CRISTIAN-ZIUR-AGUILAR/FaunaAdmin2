// lib/services/location_service.dart
import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Pide permisos y regresa posición actual si es posible.
  /// Si no hay señal/permisos, intenta la última ubicación conocida.
  static Future<Position?> getPositionSafe() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (!serviceEnabled ||
        permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      // Fallback: última ubicación conocida (puede ser null)
      return Geolocator.getLastKnownPosition();
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }
}
