import 'dart:io';
import 'package:gpx/gpx.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

Future<File> exportGpx(List<LatLng> pts, {String name = 'WalkscapE Track'}) async {
  // Build a single track segment from points
  final seg = Trkseg();
  for (final p in pts) {
    seg.trkpts.add(Wpt(lat: p.latitude, lon: p.longitude));
  }

  // Build the track
  final trk = Trk(name: name, trksegs: [seg]);

  // gpx ^2.3.0: use no-arg constructor, then set fields
  final gpx = Gpx();
  gpx.creator = 'WalkscapE';
  gpx.trks = [trk];

  // Serialize
  final xml = GpxWriter().asString(gpx, pretty: true);

  // Save to a temp file
  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '');
  final file = File('${dir.path}/walkscape_track_$stamp.gpx');
  return file.writeAsString(xml);
}
