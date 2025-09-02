import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class TrackRecorder {
  bool get isRecording => _sub != null;
  final List<LatLng> points = [];
  DateTime? _startedAt;
  StreamSubscription<Position>? _sub;

  DateTime? get startedAt => _startedAt;

  Future<void> start() async {
    if (_sub != null) return;

    // Ensure permission is granted
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw StateError('Location permission denied');
    }

    _startedAt ??= DateTime.now();

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5, // meters between points
      ),
    ).listen((p) {
      points.add(LatLng(p.latitude, p.longitude));
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  void clear() {
    points.clear();
    _startedAt = null;
  }
}
