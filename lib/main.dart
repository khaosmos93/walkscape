import 'package:flutter/material.dart';

void main() => runApp(const WalkscapeApp());

class WalkscapeApp extends StatelessWidget {
  const WalkscapeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WalkscapE',
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const _Home(),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('WalkscapE booted ✔')),
    );
  }
}
