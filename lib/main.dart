import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'features/map/presentation/map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env"); // requires MAPTILER_KEY (and optional MAPTILER_STYLE_URL)
  runApp(const WalkscapeApp());
}

class WalkscapeApp extends StatelessWidget {
  const WalkscapeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WalkscapE',
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const MapScreen(),
    );
  }
}
