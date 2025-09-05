import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as mgl;
import 'package:share_plus/share_plus.dart';

import '../../tracks/recorder.dart';
import '../../tracks/gpx_export.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  mgl.MapLibreMapController? _mgl;
  mgl.Line? _trackLine;

  final _recorder = TrackRecorder();
  ll.LatLng? _me;
  Stream<Position>? _posStream;

  String? _styleString; // <-- final style after injecting the key

  @override
  void initState() {
    super.initState();
    _loadStyleFromAssetAndInjectKey();
    _initLocation();
  }

  Future<void> _loadStyleFromAssetAndInjectKey() async {
    if (!dotenv.isInitialized) {
      try { await dotenv.load(fileName: '.env'); } catch (_) {}
    }

    // 1) Read the asset JSON that contains {MAPTILER_KEY}
    final raw = await rootBundle.loadString('assets/styles/walkscape.json');

    // 2) Get the key from .env (make sure you load dotenv in main.dart)
    final key = dotenv.env['MAPTILER_KEY'] ?? '';
    if (key.isEmpty) {
      debugPrint('MAPTILER_KEY is empty. Did you call dotenv.load(fileName: ".env") in main()?');
    }

    // 3) Replace placeholder -> actual key
    final injected = raw.replaceAll('{MAPTILER_KEY}', key);

    if (!mounted) return;
    setState(() => _styleString = injected);
  }

  Future<void> _initLocation() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
    );
    if (!mounted) return;
    setState(() => _me = ll.LatLng(p.latitude, p.longitude));

    _posStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 3),
    );
    _posStream!.listen((pos) async {
      if (!mounted) return;
      setState(() => _me = ll.LatLng(pos.latitude, pos.longitude));
      if (_recorder.isRecording) {
        await _updateTrackLine();
      }
    });
  }

  // ---- Track line (light cyan) ----------------------------------------------
  Future<void> _updateTrackLine() async {
    final c = _mgl;
    if (c == null) return;

    if (_recorder.points.length < 2) {
      if (_trackLine != null) {
        await c.removeLine(_trackLine!);
        _trackLine = null;
      }
      return;
    }

    final geom = _recorder.points.map(_toMgl).toList();
    if (_trackLine == null) {
      _trackLine = await c.addLine(mgl.LineOptions(
        geometry: geom,
        lineColor: _hexRGB(const Color(0xFFBFFFFF)), // light cyan
        lineWidth: 4,
        lineOpacity: 0.95,
      ));
    } else {
      await c.updateLine(_trackLine!, mgl.LineOptions(geometry: geom));
    }
  }

  // Helpers
  mgl.LatLng _toMgl(ll.LatLng p) => mgl.LatLng(p.latitude, p.longitude);

  String _hexRGB(Color c) {
    // If your SDK doesn’t expose .r/.g/.b, switch to c.red/c.green/c.blue
    final r = (c.r * 255.0).round() & 0xff;
    final g = (c.g * 255.0).round() & 0xff;
    final b = (c.b * 255.0).round() & 0xff;
    return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
  }

  double _trackDistanceMeters() {
    if (_recorder.points.length < 2) return 0;
    final dist = const DistanceHaversine();
    double sum = 0;
    for (var i = 1; i < _recorder.points.length; i++) {
      sum += dist(_recorder.points[i - 1], _recorder.points[i]);
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final center = _me ?? const ll.LatLng(37.5665, 126.9780);
    final km = _trackDistanceMeters() / 1000.0;

    return Scaffold(
      appBar: AppBar(title: const Text('WalkscapE')),
      body: Stack(
        children: [
          // Wait until the style with injected key is ready
          if (_styleString == null)
            const Center(child: CircularProgressIndicator())
          else
            mgl.MapLibreMap(
              styleString: _styleString!, // <-- final style with key inlined
              initialCameraPosition: mgl.CameraPosition(
                target: _toMgl(center),
                zoom: 12,
              ),
              myLocationEnabled: true,
              compassEnabled: false,
              onMapCreated: (controller) async {
                _mgl = controller;
                if (_me != null) {
                  await controller.animateCamera(mgl.CameraUpdate.newLatLng(_toMgl(_me!)));
                }
              },
              onStyleLoadedCallback: () async {
                await _updateTrackLine();
              },
            ),

          // Stats pill
          Positioned(
            left: 12,
            top: MediaQuery.of(context).padding.top + 12,
            child: _StatsPill(
              isRecording: _recorder.isRecording,
              km: km,
              startedAt: _recorder.startedAt,
            ),
          ),
        ],
      ),

      // Actions
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Fab(
            icon: Icons.my_location,
            tooltip: 'Recenter',
            onPressed: () async {
              final c = _mgl;
              if (c == null) return;
              final tgt = _toMgl(_me ?? center);
              await c.animateCamera(mgl.CameraUpdate.newLatLng(tgt));
              await c.animateCamera(mgl.CameraUpdate.zoomTo(16));
            },
          ),
          const SizedBox(height: 10),
          _recorder.isRecording
              ? _Fab(
                  icon: Icons.stop,
                  color: const Color(0xFFFF5252),
                  tooltip: 'Stop recording',
                  onPressed: () async {
                    await _recorder.stop();
                    await _updateTrackLine();
                    if (!mounted) return;
                    setState(() {});
                  },
                )
              : _Fab(
                  icon: Icons.fiber_manual_record,
                  color: const Color(0xFF2EE59D),
                  tooltip: 'Start recording',
                  onPressed: () async {
                    try {
                      await _recorder.start();
                      if (!mounted) return;
                      setState(() {});
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Location permission required')),
                      );
                    }
                  },
                ),
          const SizedBox(height: 10),

          // Export GPX with the new SharePlus API (ShareParams)
          _Fab(
            icon: Icons.ios_share,
            tooltip: 'Export GPX',
            onPressed: _recorder.points.length < 2
                ? null
                : () async {
                    // Anchor BEFORE awaits (async-gap lint)
                    final box = context.findRenderObject() as RenderBox?;
                    final origin = box != null ? (box.localToGlobal(Offset.zero) & box.size) : null;

                    final file = await exportGpx(_recorder.points);
                    final fileName = 'walkscape_${DateTime.now().toIso8601String().replaceAll(':', '-')}.gpx';

                    await SharePlus.instance.share(
                      ShareParams(
                        files: [XFile(file.path)],
                        text: 'WalkscapE track',
                        subject: 'WalkscapE GPX',
                        sharePositionOrigin: origin,
                        fileNameOverrides: [fileName],
                        downloadFallbackEnabled: true,
                      ),
                    );
                  },
          ),
          const SizedBox(height: 10),
          _Fab(
            icon: Icons.delete_outline,
            tooltip: 'Clear track',
            onPressed: _recorder.points.isEmpty
                ? null
                : () async {
                    _recorder.clear();
                    await _updateTrackLine();
                    if (!mounted) return;
                    setState(() {});
                  },
          ),
        ],
      ),
    );
  }
}

// --- Accurate great-circle distance
class DistanceHaversine {
  const DistanceHaversine();
  double call(ll.LatLng a, ll.LatLng b) {
    const R = 6371000.0;
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final la1 = _deg2rad(a.latitude);
    final la2 = _deg2rad(b.latitude);
    final h = _hav(dLat) + math.cos(la1) * math.cos(la2) * _hav(dLon);
    return 2 * R * math.asin(math.sqrt(h));
  }
  double _hav(double x) => math.sin(x / 2) * math.sin(x / 2);
  double _deg2rad(double d) => d * math.pi / 180.0;
}

class _Fab extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final String? tooltip;
  const _Fab({required this.icon, this.onPressed, this.color, this.tooltip});
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: icon.codePoint,
      backgroundColor: color,
      onPressed: onPressed,
      tooltip: tooltip,
      child: Icon(icon),
    );
  }
}

class _StatsPill extends StatefulWidget {
  final bool isRecording;
  final double km;
  final DateTime? startedAt;
  const _StatsPill({required this.isRecording, required this.km, required this.startedAt});
  @override
  State<_StatsPill> createState() => _StatsPillState();
}
class _StatsPillState extends State<_StatsPill> {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_onTick)..start();
  }

  void _onTick(Duration d) {
    if (!mounted) return;
    if (!widget.isRecording || widget.startedAt == null) return;
    setState(() => _elapsed = DateTime.now().difference(widget.startedAt!));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = '${widget.km.toStringAsFixed(2)} km'
        '${widget.isRecording && widget.startedAt != null ? ' • ${_fmt(_elapsed)}' : ''}';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF000000).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '$m:${s.toString().padLeft(2, '0')}';
  }
}

// Lightweight ticker
class Ticker {
  final void Function(Duration) onTick;
  bool _running = false;
  late final Stopwatch _sw;
  Ticker(this.onTick) {
    _sw = Stopwatch()..start();
  }
  void start() {
    if (_running) return;
    _running = true;
    _tick();
  }
  void _tick() async {
    while (_running) {
      await Future<void>.delayed(const Duration(seconds: 1));
      onTick(Duration(milliseconds: _sw.elapsedMilliseconds));
    }
  }
  void dispose() => _running = false;
}
