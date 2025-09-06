// 3D curved-wire terrain from MapTiler Terrain-RGB (no `http` package).
// Requires .env with MAPTILER_KEY and dotenv.load() in main().

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:three_js_core/three_js_core.dart' as three;
import 'package:three_js_core/buffer/buffer_attribute.dart' as tbuf;
import 'package:three_js_math/three_js_math.dart' as tmath;
import 'package:three_js_geometry/three_js_geometry.dart' as tgeo;
import 'package:three_js_controls/three_js_controls.dart' as controls;

class LandscapeView extends StatefulWidget {
  const LandscapeView({
    super.key,
    this.centerLat = 37.5665, // Seoul
    this.centerLon = 126.9780,
    this.zoom = 12, // 0..14 supported by MapTiler Terrain-RGB
    this.grid = 128, // vertices per side (sampling resolution)
    this.verticalExaggeration = 1.2,
    this.wireColor = const Color(0xFFEED7A1), // pale wire
    this.bgColor = const Color(0xFF0B0B16), // deep dark bg
  });

  final double centerLat;
  final double centerLon;
  final int zoom;
  final int grid;
  final double verticalExaggeration;
  final Color wireColor;
  final Color bgColor;

  @override
  State<LandscapeView> createState() => _LandscapeViewState();
}

class _LandscapeViewState extends State<LandscapeView> {
  /// High-level renderer wrapper (from `three_js_core`)
  late final three.ThreeJS _three;
  three.Scene? _scene;
  three.PerspectiveCamera? _camera;
  controls.OrbitControls? _orbit;

  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _three = three.ThreeJS(
      setup: _setupScene,
      onSetupComplete: () {},
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() => _ready = true);
    });
  }

  Future<void> _setupScene() async {
    _scene = _three.scene = three.Scene()
      ..background = tmath.Color.fromHex32(widget.bgColor.value);

    final w = (_three.width > 0 ? _three.width : 1280).toDouble();
    final h = (_three.height > 0 ? _three.height : 720).toDouble();
    _camera = _three.camera = three.PerspectiveCamera(55, w / h, 0.1, 2.0e7)
      ..position.setValues(0, 900, 1400);

    _orbit = controls.OrbitControls(_camera!, _three.globalKey)
      ..enableDamping = true
      ..dampingFactor = 0.12
      ..rotateSpeed = 0.6
      ..minDistance = 120
      ..maxDistance = 8e6
      ..target.setValues(0, 0, 0);

    _three.addAnimationEvent((_) {
      _orbit?.update();
    });

    _scene!.add(three.AmbientLight(0xffffff, 0.4));

    final terrain = await _buildWireTerrain(
      lat: widget.centerLat,
      lon: widget.centerLon,
      zoom: widget.zoom,
      grid: widget.grid,
      exaggeration: widget.verticalExaggeration,
      wireColor: widget.wireColor,
    );
    _scene!.add(terrain);
  }

  // --------------------- Terrain helpers ---------------------

  (int x, int y) _latLonToTileXY(double lat, double lon, int z) {
    final n = 1 << z;
    final x = ((lon + 180.0) / 360.0 * n).floor();
    final latRad = lat * math.pi / 180.0;
    final y = ((1.0 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2.0 * n).floor();
    return (x, y);
  }

  ({double latMin, double latMax, double lonMin, double lonMax}) _tileBounds(int x, int y, int z) {
    final n = 1 << z;
    final lonMin = x / n * 360.0 - 180.0;
    final lonMax = (x + 1) / n * 360.0 - 180.0;

    double mercToLat(double a) => (math.atan(math.sinh(a)) * 180.0 / math.pi);
    final latMax = mercToLat(math.pi * (1 - 2 * y / n));
    final latMin = mercToLat(math.pi * (1 - 2 * (y + 1) / n));
    return (latMin: latMin, latMax: latMax, lonMin: lonMin, lonMax: lonMax);
  }

  Future<Uint8List> _fetchTerrainRgbPng(int x, int y, int z) async {
    final key = dotenv.env['MAPTILER_KEY'] ?? '';
    if (key.isEmpty) {
      throw StateError('MAPTILER_KEY missing. Ensure dotenv.load() ran in main().');
    }
    final url = Uri.parse('https://api.maptiler.com/tiles/terrain-rgb/$z/$x/$y.png?key=$key');
    final client = HttpClient();
    try {
      final req = await client.getUrl(url);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw Exception('Terrain tile HTTP ${res.statusCode}');
      }
      return await consolidateHttpClientResponseBytes(res);
    } finally {
      client.close(force: true);
    }
  }

  Future<ui.Image> _decodePng(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  List<double> _decodeHeights(ui.Image image) {
    final bd = image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) throw Exception('Failed to read RGBA bytes');
    final u8 = bd.buffer.asUint8List();

    final out = List<double>.filled(image.width * image.height, 0.0, growable: false);
    for (int i = 0, p = 0; i < out.length; i++, p += 4) {
      final r = u8[p], g = u8[p + 1], b = u8[p + 2];
      out[i] = -10000.0 + (r * 256 * 256 + g * 256 + b) * 0.1;
    }
    return out;
  }

  Future<three.Object3D> _buildWireTerrain({
    required double lat,
    required double lon,
    required int zoom,
    required int grid,
    required double exaggeration,
    required Color wireColor,
  }) async {
    final (tx, ty) = _latLonToTileXY(lat, lon, zoom);
    final b = _tileBounds(tx, ty, zoom);

    final bytes = await _fetchTerrainRgbPng(tx, ty, zoom);
    final img = await _decodePng(bytes);
    final side = img.width;
    final heights = _decodeHeights(img);

    const R = 6_371_000.0;

    tmath.Vector3 ecef(double la, double lo, double h) {
      final laR = la * math.pi / 180.0;
      final loR = lo * math.pi / 180.0;
      final cosLa = math.cos(laR), sinLa = math.sin(laR);
      final cosLo = math.cos(loR), sinLo = math.sin(loR);
      final rr = R + h * exaggeration;
      return tmath.Vector3(rr * cosLa * cosLo, rr * cosLa * sinLo, rr * sinLa);
    }

    final latC = (b.latMin + b.latMax) * 0.5;
    final lonC = (b.lonMin + b.lonMax) * 0.5;
    final origin = ecef(latC, lonC, 0);

    double sample(double sx, double sy) {
      final x0 = sx.floor().clamp(0, side - 1).toInt();
      final y0 = sy.floor().clamp(0, side - 1).toInt();
      final x1 = (x0 + 1).clamp(0, side - 1);
      final y1 = (y0 + 1).clamp(0, side - 1);
      final fx = sx - x0, fy = sy - y0;

      final h00 = heights[y0 * side + x0];
      final h10 = heights[y0 * side + x1];
      final h01 = heights[y1 * side + x0];
      final h11 = heights[y1 * side + x1];

      final h0 = h00 * (1 - fx) + h10 * fx;
      final h1 = h01 * (1 - fx) + h11 * fx;
      return h0 * (1 - fy) + h1 * fy;
    }

    final positions = <double>[];
    for (int gy = 0; gy <= grid; gy++) {
      final tY = gy / grid;
      final la = b.latMax + (b.latMin - b.latMax) * tY;
      final sy = (1.0 - tY) * (side - 1);
      for (int gx = 0; gx <= grid; gx++) {
        final tX = gx / grid;
        final lo = b.lonMin + (b.lonMax - b.lonMin) * tX;
        final sx = tX * (side - 1);

        final h = sample(sx, sy);
        final p = ecef(la, lo, h)..sub(origin);
        positions.addAll([p.x, p.y, p.z]);
      }
    }

    final indices = <int>[];
    final stride = grid + 1;
    for (int y = 0; y < grid; y++) {
      for (int x = 0; x < grid; x++) {
        final i0 = y * stride + x;
        final i1 = i0 + 1;
        final i2 = i0 + stride;
        final i3 = i2 + 1;
        indices.addAll([i0, i2, i1, i1, i2, i3]);
      }
    }

    final geom = three.BufferGeometry()
      ..setAttributeFromString(
        'position',
        tbuf.Float32BufferAttribute.fromList(positions, 3),
      );
    geom.setIndex(indices);
    geom.computeVertexNormals();

    final wireGeo = tgeo.WireframeGeometry(geom);
    final lineMat = three.LineBasicMaterial.fromMap({
      'color': wireColor.value,
      'transparent': true,
      'opacity': 0.9,
    });
    final wire = three.LineSegments(wireGeo, lineMat);

    final group = three.Group();
    group.add(wire);
    return group;
  }

  @override
  void dispose() {
    _orbit?.dispose();
    _three.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        Positioned.fill(child: _three.build()),
        Positioned(
          right: 12,
          top: MediaQuery.of(context).padding.top + 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF000000).withOpacity(0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text('Drag: orbit • Pinch/scroll: zoom', style: TextStyle(fontSize: 12)),
            ),
          ),
        ),
      ],
    );
  }
}