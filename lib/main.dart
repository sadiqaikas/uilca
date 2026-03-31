
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lca/newhome/start_page.dart';
 
// import 'lca/home.dart';


void main() {
  runApp(const MyApp());
  debugPrintAssetManifest() ;
}
void debugPrintAssetManifest() async {
  final manifest = await rootBundle.loadString('AssetManifest.json');
  final Map<String, dynamic> map = json.decode(manifest);
  final matches = map.keys
      .where((k) => k.endsWith('biosphere3_flows.json'))
      .toList();
  print('[AssetManifest] biosphere files: $matches');
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LCA Input',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const CanvasStartPage(),
    );
  }
}



