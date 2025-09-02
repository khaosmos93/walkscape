import 'package:flutter/material.dart';
import 'package:maplibre_gl/mapbox_gl.dart';

void main() => runApp(const WalkscapE());

class WalkscapE extends StatelessWidget {
  const WalkscapE({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MapPage(),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  MapLibreMapController? _controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WalkscapE')),
      body: MapLibreMap(
        styleString: 'https://demotiles.maplibre.org/style.json', // 추후 교체
        initialCameraPosition: const CameraPosition(
          target: LatLng(37.5665, 126.9780),
          zoom: 12,
        ),
        myLocationEnabled: true,
        myLocationTrackingMode: MyLocationTrackingMode.Tracking,
        onMapCreated: (c) => _controller = c,
      ),
    );
  }
}
