// // // This file contains the ResultsPage widget that displays the results of LCA scenarios.
// import 'package:flutter/material.dart';
// import 'package:fl_chart/fl_chart.dart';
// import 'dart:math';

// class ResultsPage extends StatelessWidget {
//   final Map<String, dynamic> results;
//   const ResultsPage({required this.results, Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final names = results.keys.toList();
//     final scores = names.map((n) {
//       final info = results[n] as Map<String, dynamic>;
//       if (info['success'] == true) {
//         return (info['result']['score'] as num).toDouble();
//       }
//       return 0.0;
//     }).toList();
//     final maxScore = (scores.isEmpty ? 1.0 : scores.reduce(max)) * 1.2;

//     return Scaffold(
//       appBar: AppBar(title: const Text('LCA Results')),
//       body: SafeArea(
//         child: Column(
//           children: [
//             // 1) Bar chart with fixed height
//             SizedBox(
//               height: 240,
//               child: BarChart(
//                 BarChartData(
//                   maxY: maxScore,
//                   alignment: BarChartAlignment.spaceAround,
//                   titlesData: FlTitlesData(
//                     leftTitles: AxisTitles(
//                       sideTitles: SideTitles(showTitles: true),
//                     ),
//                     bottomTitles: AxisTitles(
//                       sideTitles: SideTitles(
//                         showTitles: true,
//                         reservedSize: 28,
//                         getTitlesWidget: (value, meta) {
//                           final i = value.toInt();
//                           if (i < 0 || i >= names.length) return const SizedBox();
//                           return SideTitleWidget(
//                             axisSide: meta.axisSide,
//                             child: Text(names[i], style: const TextStyle(fontSize: 10)),
//                           );
//                         },
//                       ),
//                     ),
//                     topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
//                     rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
//                   ),
//                   barGroups: List.generate(names.length, (i) {
//                     return BarChartGroupData(
//                       x: i,
//                       barRods: [
//                         BarChartRodData(toY: scores[i], width: 20, borderRadius: BorderRadius.circular(4)),
//                       ],
//                     );
//                   }),
//                 ),
//               ),
//             ),

//             const SizedBox(height: 24),

//             // 2) Expandable list of scenario details
//             Expanded(
//               child: ListView.builder(
//                 padding: const EdgeInsets.symmetric(horizontal: 16),
//                 itemCount: names.length,
//                 itemBuilder: (ctx, i) {
//                   final name = names[i];
//                   final info = results[name] as Map<String, dynamic>;
//                   final ok   = info['success'] as bool;
//                   final res  = info['result'] as Map<String, dynamic>?;

//                   // Build a human-readable method string if available
//                   String methodText = res != null && res['method'] is List
//                       ? (res['method'] as List).join(' ▶ ')
//                       : 'n/a';

//                   return Card(
//                     margin: const EdgeInsets.symmetric(vertical: 6),
//                     child: ExpansionTile(
//                       leading: Icon(ok ? Icons.check_circle : Icons.error,
//                                     color: ok ? Colors.green : Colors.red),
//                       title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
//                       subtitle: ok
//                           ? Text("Score: ${res!['score']} ${res['unit']}")
//                           : Text("Error: ${info['error']}"),
//                       childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
//                       children: ok 
//                           ? [
//                               Row(
//                                 children: [
//                                   const Text("Method:", style: TextStyle(fontWeight: FontWeight.w600)),
//                                   const SizedBox(width: 8),
//                                   Expanded(child: Text(methodText)),
//                                 ],
//                               ),
//                               const SizedBox(height: 8),
//                               Row(
//                                 children: [
//                                   const Text("Database:", style: TextStyle(fontWeight: FontWeight.w600)),
//                                   const SizedBox(width: 8),
//                                   Text(res!['database'] as String),
//                                 ],
//                               ),
//                             ]
//                           : [],
//                     ),
//                   );
//                 },
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }



//  this works well, just needs improvements.

// import 'package:flutter/material.dart';
// import 'package:fl_chart/fl_chart.dart';
// import 'dart:math';

// class ResultsPage extends StatelessWidget {
//   final Map<String, dynamic> results;
//   const ResultsPage({required this.results, Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final names = results.keys.toList();
//     final scores = names.map((n) {
//       final info = results[n] as Map<String, dynamic>;
//       if (info['success'] == true) {
//         return (info['result']['score'] as num).toDouble();
//       }
//       return 0.0;
//     }).toList();

//     // Pull out a “global” method string if all scenarios use the same LCIA method
//     final methods = names.map((n) {
//       final info = results[n]!['result'] as Map<String, dynamic>?;
//       if (info != null && info['method'] is List) {
//         return (info['method'] as List).join(' ▶ ');
//       }
//       return null;
//     }).where((m) => m != null).cast<String>().toSet();

//     // Use the single method if there’s exactly one, otherwise a generic title
//     final chartTitle = methods.length == 1
//         ? methods.first
//         : 'LCA Impact Comparison';

//     final maxScore = (scores.isEmpty ? 1.0 : scores.reduce(max)) * 1.2;

//     return Scaffold(
//       appBar: AppBar(title: const Text('LCA Results')),
//       body: SafeArea(
//         child: Column(
//           children: [
//             // 1) Chart title
//             Padding(
//               padding: const EdgeInsets.symmetric(vertical: 12),
//               child: Text(
//                 chartTitle,
//                 style: Theme.of(context).textTheme.titleLarge,
//                 textAlign: TextAlign.center,
//               ),
//             ),

//             // 2) Bar chart
//             SizedBox(
//               height: 260,
//               child: BarChart(
//                 BarChartData(
//                   maxY: maxScore,
//                   alignment: BarChartAlignment.spaceAround,

//                   // Axis Titles
//                   titlesData: FlTitlesData(
//                     leftTitles: AxisTitles(
//                       axisNameWidget: const Text('kg CO₂ eqv'),
//                       axisNameSize: 16,
//                       sideTitles: SideTitles(showTitles: true),
//                     ),
//                     bottomTitles: AxisTitles(
//                       axisNameWidget: const Text('Scenarios'),
//                       axisNameSize: 16,
//                       sideTitles: SideTitles(
//                         showTitles: true,
//                         reservedSize: 30,
//                         getTitlesWidget: (value, meta) {
//                           final i = value.toInt();
//                           if (i < 0 || i >= names.length) return const SizedBox();
//                           return SideTitleWidget(
//                             axisSide: meta.axisSide,
//                             child: Text(names[i], style: const TextStyle(fontSize: 12)),
//                           );
//                         },
//                       ),
//                     ),
//                     topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
//                     rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
//                   ),

//                   // The bars themselves
//                   barGroups: List.generate(names.length, (i) {
//                     return BarChartGroupData(
//                       x: i,
//                       barRods: [
//                         BarChartRodData(
//                           toY: scores[i],
//                           width: 22,
//                           borderRadius: BorderRadius.circular(4),
//                         ),
//                       ],
//                     );
//                   }),
//                 ),
//               ),
//             ),

//             const SizedBox(height: 24),

//             // 3) Expandable list of details
//             Expanded(
//               child: ListView.builder(
//                 padding: const EdgeInsets.symmetric(horizontal: 16),
//                 itemCount: names.length,
//                 itemBuilder: (ctx, i) {
//                   final name = names[i];
//                   final info = results[name] as Map<String, dynamic>;
//                   final ok   = info['success'] as bool;
//                   final res  = info['result'] as Map<String, dynamic>?;

//                   // Build method text for this scenario
//                   final methodText = (res != null && res['method'] is List)
//                       ? (res['method'] as List).join(' ▶ ')
//                       : 'n/a';

//                   return Card(
//                     margin: const EdgeInsets.symmetric(vertical: 6),
//                     child: ExpansionTile(
//                       leading: Icon(
//                         ok ? Icons.check_circle : Icons.error,
//                         color: ok ? Colors.green : Colors.red,
//                       ),
//                       title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
//                       subtitle: ok
//                           ? Text("Score: ${res!['score']} ${res['unit']}")
//                           : Text("Error: ${info['error']}"),
//                       childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
//                       children: ok
//                           ? [
//                               Row(
//                                 children: [
//                                   const Text("Method:", style: TextStyle(fontWeight: FontWeight.w600)),
//                                   const SizedBox(width: 8),
//                                   Expanded(child: Text(methodText)),
//                                 ],
//                               ),
//                               const SizedBox(height: 8),
//                               Row(
//                                 children: [
//                                   const Text("Database:", style: TextStyle(fontWeight: FontWeight.w600)),
//                                   const SizedBox(width: 8),
//                                   Text(res!['database'] as String),
//                                 ],
//                               ),
//                             ]
//                           : [],
//                     ),
//                   );
//                 },
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// File: lib/lca/results.dart

// import 'package:flutter/material.dart';
// import 'package:fl_chart/fl_chart.dart';
// import 'dart:math';

// class ResultsPage extends StatelessWidget {
//   final Map<String, dynamic> results;
//   const ResultsPage({required this.results, Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final names = results.keys.toList();
//     final scores = names.map((n) {
//       final info = results[n] as Map<String, dynamic>;
//       return info['success'] == true
//         ? (info['result']['score'] as num).toDouble()
//         : 0.0;
//     }).toList();

//     // Determine chart title from LCIA method(s)
//     final methods = names
//       .map((n) {
//         final info = results[n]!['result'] as Map<String, dynamic>?;
//         if (info != null && info['method'] is List) {
//           return (info['method'] as List).join(' ▶ ');
//         }
//         return null;
//       })
//       .whereType<String>()
//       .toSet();
//     final chartTitle = methods.length == 1
//         ? methods.first
//         : 'LCA Impact Comparison';

//     final maxScore = (scores.isEmpty ? 1.0 : scores.reduce(max)) * 1.2;
//     const barColor = Colors.teal;

//     return Scaffold(
//       appBar: AppBar(title: const Text('LCA Results')),
//       body: SafeArea(
//         child: Column(
//           children: [
//             // 1) Chart title
//             Padding(
//               padding: const EdgeInsets.symmetric(vertical: 12),
//               child: Text(
//                 chartTitle,
//                 style: Theme.of(context).textTheme.titleLarge,
//                 textAlign: TextAlign.center,
//               ),
//             ),

//             // 2) Bar chart
//             SizedBox(
//               height: 260,
//               child: BarChart(
//                 BarChartData(
//                   maxY: maxScore,
//                   alignment: BarChartAlignment.spaceAround,

//                   // Axis Titles
//                   titlesData: FlTitlesData(
//                     leftTitles: AxisTitles(
//                       axisNameWidget: const Text('kg CO₂ eqv'),
//                       axisNameSize: 16,
//                       sideTitles: SideTitles(showTitles: true),
//                     ),
//                     bottomTitles: AxisTitles(
//                       axisNameWidget: const Text('Scenarios'),
//                       axisNameSize: 16,
//                       sideTitles: SideTitles(
//                         showTitles: true,
//                         reservedSize: 30,
//                         getTitlesWidget: (value, meta) {
//                           final i = value.toInt();
//                           if (i < 0 || i >= names.length) return const SizedBox();
//                           return SideTitleWidget(
//                             axisSide: meta.axisSide,
//                             child: Text(names[i], style: const TextStyle(fontSize: 12)),
//                           );
//                         },
//                       ),
//                     ),
//                     topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
//                     rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
//                   ),

//                   // The bars themselves
//                   barGroups: List.generate(names.length, (i) {
//                     return BarChartGroupData(
//                       x: i,
//                       barRods: [
//                         BarChartRodData(
//                           toY: scores[i],
//                           width: 22,
//                           borderRadius: BorderRadius.circular(4),
//                         ),
//                       ],
//                     );
//                   }),
//                 ),
//               ),
//             ),

//             const SizedBox(height: 24),

//             // 3) Expandable list of details
//             Expanded(
//               child: ListView.builder(
//                 padding: const EdgeInsets.symmetric(horizontal: 16),
//                 itemCount: names.length,
//                 itemBuilder: (ctx, i) {
//                   final name = names[i];
//                   final info = results[name] as Map<String, dynamic>;
//                   final ok   = info['success'] as bool;
//                   final res  = info['result'] as Map<String, dynamic>?;

//                   // Build method text for this scenario
//                   final methodText = (res != null && res['method'] is List)
//                       ? (res['method'] as List).join(' ▶ ')
//                       : 'n/a';

//                   return Card(
//                     margin: const EdgeInsets.symmetric(vertical: 6),
//                     child: ExpansionTile(
//                       leading: Icon(
//                         ok ? Icons.check_circle : Icons.error,
//                         color: ok ? Colors.green : Colors.red,
//                       ),
//                       title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
//                       subtitle: ok
//                           ? Text("Score: ${res!['score']} ${res['unit']}")
//                           : Text("Error: ${info['error']}"),
//                       childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
//                       children: ok
//                           ? [
//                               Row(
//                                 children: [
//                                   const Text("Method:", style: TextStyle(fontWeight: FontWeight.w600)),
//                                   const SizedBox(width: 8),
//                                   Expanded(child: Text(methodText)),
//                                 ],
//                               ),
//                               const SizedBox(height: 8),
//                               Row(
//                                 children: [
//                                   const Text("Database:", style: TextStyle(fontWeight: FontWeight.w600)),
//                                   const SizedBox(width: 8),
//                                   Text(res!['database'] as String),
//                                 ],
//                               ),
//                             ]
//                           : [],
//                     ),
//                   );
//                 },
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// File: lib/lca/results.dart
// File: lib/lca/results.dart

// import 'package:flutter/material.dart';
// import 'package:fl_chart/fl_chart.dart';
// import 'dart:math';

// class ResultsPage extends StatelessWidget {
//   final Map<String, dynamic> results;
//   const ResultsPage({required this.results, Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final names = results.keys.toList();
//     final scores = names.map((n) {
//       final info = results[n] as Map<String, dynamic>;
//       return info['success'] == true
//           ? (info['result']['score'] as num).toDouble()
//           : 0.0;
//     }).toList();

//     // Chart title from LCIA method(s)
//     final methods = names
//         .map((n) {
//           final info = results[n]!['result'] as Map<String, dynamic>?;
//           if (info != null && info['method'] is List) {
//             return (info['method'] as List).join(' ▶ ');
//           }
//           return null;
//         })
//         .whereType<String>()
//         .toSet();
//     final chartTitle = methods.length == 1
//         ? methods.first
//         : 'LCA Impact Comparison';

//     final maxScore = (scores.isEmpty ? 1.0 : scores.reduce(max)) * 1.2;
//     const barGradient = LinearGradient(
//       begin: Alignment.bottomCenter,
//       end: Alignment.topCenter,
//       colors: [Colors.lightGreen, Colors.green],
//     );

//     // Dynamic chart height: between 200 and 300
//     final chartHeight = min(max(names.length * 60.0 + 80.0, 200.0), 300.0);

//     // Each bar slot width and maximum gap of 10px
//     const barSlotWidth = 50.0;
//     const groupsSpace = 60.0;

//     // Total width = N * slot + (N - 1) * gap
//     final totalChartWidth =
//         names.length * barSlotWidth + (names.length - 1) * groupsSpace;

//     return Scaffold(
//       appBar: AppBar(title: const Text('LCA Results')),
//       body: SafeArea(
//         child: Column(
//           children: [
//             // —— Chart Title —— 
//             Padding(
//               padding: const EdgeInsets.symmetric(vertical: 16),
//               child: Text(
//                 chartTitle,
//                 style: Theme.of(context)
//                     .textTheme
//                     .titleLarge!
//                     .copyWith(fontWeight: FontWeight.bold),
//                 textAlign: TextAlign.center,
//               ),
//             ),

//             // —— Bar Chart —— 
//             SizedBox(
//               height: 300,
//               child: BarChart(
//                 BarChartData(
//                   maxY: maxScore,
//                   alignment: BarChartAlignment.spaceBetween,
//                   groupsSpace: groupsSpace,

//                   // grid lines
//                   gridData: FlGridData(
//                     show: true,
//                     drawVerticalLine: false,
//                     horizontalInterval: maxScore / 5,
//                     getDrawingHorizontalLine: (_) => FlLine(
//                       color: Colors.grey.shade300,
//                       strokeWidth: 1,
//                     ),
//                   ),

//                   // axis labels & titles
//                   titlesData: FlTitlesData(
//                     leftTitles: AxisTitles(
//                       axisNameWidget: const Text(
//                         'kg CO₂ eqv',
//                         style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
//                       ),
//                       axisNameSize: 24,
//                       sideTitles: SideTitles(
//                         showTitles: true,
//                         interval: maxScore / 5,
//                         reservedSize: 40,
//                         getTitlesWidget: (val, _) => Text(
//                           val.toStringAsFixed(0),
//                           style: const TextStyle(fontSize: 12),
//                         ),
//                       ),
//                     ),
//                     bottomTitles: AxisTitles(
//                       axisNameWidget: const Padding(
//                         padding: EdgeInsets.only(top: 8.0),
//                         child: Text(
//                           'Scenarios',
//                           style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
//                         ),
//                       ),
//                       axisNameSize: 24,
//                       sideTitles: SideTitles(
//                         showTitles: true,
//                         reservedSize: 50,
//                         getTitlesWidget: (val, meta) {
//                           final i = val.toInt();
//                           if (i < 0 || i >= names.length) return const SizedBox();
//                           return SideTitleWidget(
//                             axisSide: meta.axisSide,
//                             child: RotatedBox(
//                               quarterTurns: 1,
//                               child: Text(names[i], style: const TextStyle(fontSize: 12)),
//                             ),
//                           );
//                         },
//                       ),
//                     ),
//                     topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
//                     rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
//                   ),

//                   // tooltips (using up-to-date API — no `tooltipBgColor`)
//                   barTouchData: BarTouchData(
//                     enabled: true,
//                     touchTooltipData: BarTouchTooltipData(
//                       tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                       tooltipRoundedRadius: 4,
//                       getTooltipItem: (group, groupIndex, rod, rodIndex) {
//                         return BarTooltipItem(
//                           rod.toY.toStringAsFixed(2),
//                           const TextStyle(
//                             color: Colors.black,
//                             fontWeight: FontWeight.bold,
//                           ),
//                         );
//                       },
//                     ),
//                   ),

//                   // the bars
//                   barGroups: List.generate(names.length, (i) {
//                     return BarChartGroupData(
//                       x: i,
//                       showingTooltipIndicators: [0],
//                       barRods: [
//                         BarChartRodData(
//                           toY: scores[i],
//                           width: 26,
//                           borderRadius: BorderRadius.circular(6),
//                           color: barColor,
//                         ),
//                       ],
//                     );
//                   }),
//                 ),
//               ),
//             ),

//             const SizedBox(height: 16),

//             // —— Detail Tiles —— 
//             Expanded(
//               child: ListView.builder(
//                 padding: const EdgeInsets.symmetric(horizontal: 16),
//                 itemCount: names.length,
//                 itemBuilder: (ctx, i) {
//                   final name = names[i];
//                   final info = results[name] as Map<String, dynamic>;
//                   final ok   = info['success'] as bool;
//                   final res  = info['result'] as Map<String, dynamic>?;

//                   // Build method text for this scenario
//                   final methodText = (res != null && res['method'] is List)
//                       ? (res['method'] as List).join(' ▶ ')
//                       : 'n/a';

//                   return Card(
//                     margin: const EdgeInsets.symmetric(vertical: 6),
//                     child: ExpansionTile(
//                       leading: Icon(
//                         ok ? Icons.check_circle : Icons.error,
//                         color: ok ? Colors.green : Colors.red,
//                       ),
//                       title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
//                       subtitle: ok
//                           ? Text("Score: ${res!['score']} ${res['unit']}")
//                           : Text("Error: ${info['error']}"),
//                       childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
//                       children: ok
//                           ? [
//                               Row(
//                                 children: [
//                                   const Text("Method:", style: TextStyle(fontWeight: FontWeight.w600)),
//                                   const SizedBox(width: 8),
//                                   Expanded(child: Text(methodText)),
//                                 ],
//                               ),
//                               const SizedBox(height: 8),
//                               Row(
//                                 children: [
//                                   const Text("Database:", style: TextStyle(fontWeight: FontWeight.w600)),
//                                   const SizedBox(width: 8),
//                                   Text(res!['database'] as String),
//                                 ],
//                               ),
//                             ]
//                           : [],
//                     ),
//                   );
//                 },
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// // File: lib/lca/results.dart

// import 'package:flutter/material.dart';
// import 'package:fl_chart/fl_chart.dart';
// import 'dart:math';

// // Your existing imports:
// import 'home.dart';       // ProcessNode, ProcessNodeWidget

// class ResultsPage extends StatelessWidget {
//   final Map<String, dynamic> results;
//   final Map<String, dynamic>? scenariosMap;

//   const ResultsPage({
//     required this.results,
//     this.scenariosMap,
//     Key? key,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final names = results.keys.toList();
//     final scores = names.map((n) {
//       final info = results[n] as Map<String, dynamic>;
//       return (info['success'] == true)
//           ? (info['result']['score'] as num).toDouble()
//           : 0.0;
//     }).toList();

//     // Chart title from LCIA method(s)
//     final methods = names
//         .map((n) {
//           final info = results[n]!['result'] as Map<String, dynamic>?;
//           if (info != null && info['method'] is List) {
//             return (info['method'] as List).join(' ▶ ');
//           }
//           return null;
//         })
//         .whereType<String>()
//         .toSet();
//     final chartTitle = (methods.length == 1)
//         ? methods.first
//         : 'LCA Impact Comparison';

//     final maxScore =
//         (scores.isEmpty ? 1.0 : scores.reduce(max)) * 1.2;
//     const barGradient = LinearGradient(
//       begin: Alignment.bottomCenter,
//       end: Alignment.topCenter,
//       colors: [Colors.lightGreen, Colors.green],
//     );

//     // Each bar group gets 60px between its neighbor (30px padding each side)
//     const barPadding = 60.0;

//     // Dynamic chart height (between 200–300)
//     final chartHeight =
//         min(max(names.length * 60.0 + 80.0, 200.0), 300.0);

//     // Total width = bars * 22px + gaps * barPadding
//     final totalChartWidth = names.length * 22 +
//         (names.length - 1) * barPadding;

//     // Pick the best (lowest‐CO₂) scenario
//     String? bestName;
//     if (scenariosMap != null) {
//       final valid = names
//           .where((n) => results[n]['success'] as bool)
//           .toList();
//       if (valid.isNotEmpty) {
//         bestName = valid.first;
//         double bestScore = (results[bestName]!['result']['score']
//                 as num)
//             .toDouble();
//         for (var n in valid) {
//           final s = (results[n]!['result']['score']
//                   as num)
//               .toDouble();
//           if (s < bestScore) {
//             bestScore = s;
//             bestName = n;
//           }
//         }
//       }
//     }

//     return Scaffold(
//       appBar: AppBar(title: const Text('LCA Results')),
//       body: SafeArea(
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             // —— Chart Title —— 
//             Padding(
//               padding:
//                   const EdgeInsets.symmetric(vertical: 16),
//               child: Text(
//                 chartTitle,
//                 style: Theme.of(context)
//                     .textTheme
//                     .titleLarge!
//                     .copyWith(fontWeight: FontWeight.bold),
//                 textAlign: TextAlign.center,
//               ),
//             ),

//             // —— Bar Chart —— 
//             SingleChildScrollView(
//               scrollDirection: Axis.horizontal,
//               padding:
//                   const EdgeInsets.symmetric(horizontal: 16),
//               child: SizedBox(
//                 width: totalChartWidth,
//                 height: chartHeight,
//                 child: BarChart(
//                   BarChartData(
//                     maxY: maxScore,
//                     alignment: BarChartAlignment.spaceBetween,
//                     groupsSpace: barPadding,

//                     gridData: FlGridData(
//                       show: true,
//                       drawVerticalLine: false,
//                       horizontalInterval: maxScore / 5,
//                       getDrawingHorizontalLine: (_) =>
//                           FlLine(
//                         color: Colors.grey.shade300,
//                         strokeWidth: 1,
//                       ),
//                     ),

//                     titlesData: FlTitlesData(
//                       leftTitles: AxisTitles(
//                         axisNameWidget: const Text(
//                           'kg CO₂ eqv',
//                           style: TextStyle(
//                               fontSize: 14,
//                               fontWeight: FontWeight.w600),
//                         ),
//                         axisNameSize: 24,
//                         sideTitles: SideTitles(
//                           showTitles: true,
//                           interval: maxScore / 5,
//                           reservedSize: 40,
//                           getTitlesWidget: (val, _) =>
//                               Text(
//                             val.toStringAsFixed(0),
//                             style: const TextStyle(
//                                 fontSize: 12),
//                           ),
//                         ),
//                       ),
//                       bottomTitles: AxisTitles(
//                         axisNameWidget:
//                             const Padding(
//                           padding:
//                               EdgeInsets.only(top: 8.0),
//                           child: Text(
//                             'Scenarios',
//                             style: TextStyle(
//                                 fontSize: 14,
//                                 fontWeight:
//                                     FontWeight.w600),
//                           ),
//                         ),
//                         axisNameSize: 24,
//                         sideTitles: SideTitles(
//                           showTitles: true,
//                           reservedSize: 50,
//                           getTitlesWidget:
//                               (val, meta) {
//                             final i = val.toInt();
//                             if (i < 0 ||
//                                 i >= names.length)
//                               return const SizedBox();
//                             return SideTitleWidget(
//                               axisSide: meta.axisSide,
//                               child: RotatedBox(
//                                 quarterTurns: 1,
//                                 child: Text(
//                                   names[i],
//                                   style: const TextStyle(
//                                       fontSize: 12),
//                                 ),
//                               ),
//                             );
//                           },
//                         ),
//                       ),
//                       topTitles: AxisTitles(
//                           sideTitles:
//                               SideTitles(showTitles: false)),
//                       rightTitles: AxisTitles(
//                           sideTitles:
//                               SideTitles(showTitles: false)),
//                     ),

//                     barTouchData: BarTouchData(
//                       enabled: true,
//                       touchTooltipData:
//                           BarTouchTooltipData(
//                         tooltipPadding:
//                             const EdgeInsets.symmetric(
//                                 horizontal: 8,
//                                 vertical: 4),
//                         tooltipRoundedRadius: 4,
//                         getTooltipItem: (group,
//                             groupIndex, rod,
//                             rodIndex) {
//                           return BarTooltipItem(
//                             rod.toY
//                                 .toStringAsFixed(2),
//                             const TextStyle(
//                                 color: Colors.black,
//                                 fontWeight:
//                                     FontWeight.bold),
//                           );
//                         },
//                       ),
//                     ),

//                     barGroups: List.generate(
//                         names.length, (i) {
//                       return BarChartGroupData(
//                         x: i,
//                         showingTooltipIndicators: [0],
//                         barRods: [
//                           BarChartRodData(
//                             toY: scores[i],
//                             width: 22,
//                             borderRadius:
//                                 BorderRadius.circular(
//                                     6),
//                             gradient: barGradient,
//                           ),
//                         ],
//                       );
//                     }),
//                   ),
//                 ),
//               ),
//             ),

//             const SizedBox(height: 16),

//             // —— Best Scenario Graph —— 
//             if (bestName != null && scenariosMap != null) ...[
//               Padding(
//                 padding: const EdgeInsets.symmetric(
//                     horizontal: 16, vertical: 8),
//                 child: Text(
//                   'Best Scenario: $bestName',
//                   style: Theme.of(context)
//                       .textTheme
//                       .titleMedium!
//                       .copyWith(
//                           fontWeight:
//                               FontWeight.bold),
//                 ),
//               ),
//               Flexible(
//                 // lets it size to available space & avoid overflow
//                 child: ScenarioGraphView(
//                   scenariosMap: {
//                     bestName: scenariosMap![bestName]
//                   },
//                 ),
//               ),
//               const SizedBox(height: 16),
//             ],

//             // —— Details List —— 
//             Expanded(
//               child: ListView.builder(
//                 padding: const EdgeInsets.symmetric(
//                     horizontal: 16),
//                 itemCount: names.length,
//                 itemBuilder: (ctx, i) {
//                   final name = names[i];
//                   final info =
//                       results[name] as Map<String, dynamic>;
//                   final ok = info['success'] as bool;
//                   final res = ok
//                       ? info['result']
//                           as Map<String, dynamic>
//                       : null;
//                   final scoreText = ok
//                       ? (res!['score']
//                               as num)
//                           .toStringAsFixed(2)
//                       : '-';
//                   final methodText =
//                       ok && res!['method'] is List
//                           ? (res['method'] as List)
//                               .join(' ▶ ')
//                           : 'n/a';
//                   final dbText = ok && res != null
//                       ? res['database'] as String
//                       : 'n/a';

//                   return Card(
//                     margin: const EdgeInsets.symmetric(
//                         vertical: 6),
//                     child: ExpansionTile(
//                       leading: Icon(
//                         ok
//                             ? Icons.check_circle
//                             : Icons.error,
//                         color:
//                             ok ? Colors.green : Colors.red,
//                       ),
//                       title: Text(name,
//                           style: const TextStyle(
//                               fontWeight:
//                                   FontWeight.bold)),
//                       subtitle: Text(ok
//                           ? "Score: $scoreText kg CO₂ eqv"
//                           : "Error: ${info['error']}"),
//                       childrenPadding:
//                           const EdgeInsets.fromLTRB(
//                               16, 0, 16, 16),
//                       children: ok
//                           ? [
//                               Row(
//                                 children: [
//                                   const Text(
//                                     "Method:",
//                                     style: TextStyle(
//                                         fontWeight:
//                                             FontWeight
//                                                 .w600),
//                                   ),
//                                   const SizedBox(
//                                       width: 8),
//                                   Expanded(
//                                       child: Text(
//                                           methodText)),
//                                 ],
//                               ),
//                               const SizedBox(
//                                   height: 8),
//                               Row(
//                                 children: [
//                                   const Text(
//                                     "Database:",
//                                     style: TextStyle(
//                                         fontWeight:
//                                             FontWeight
//                                                 .w600),
//                                   ),
//                                   const SizedBox(
//                                       width: 8),
//                                   Text(dbText),
//                                 ],
//                               ),
//                             ]
//                           : [],
//                     ),
//                   );
//                 },
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }




// /// Widget that displays each scenario’s graph in a horizontal scroll.
// /// If a single graph is taller than the viewport, it will scroll vertically.
// /// Relies on the merged JSON having full "processes" and "flows" for each scenario.
// class ScenarioGraphView extends StatelessWidget {
//   final Map<String, dynamic> scenariosMap;

//   const ScenarioGraphView({required this.scenariosMap});

//   @override
//   Widget build(BuildContext context) {
//     return SingleChildScrollView(
//       scrollDirection: Axis.horizontal,
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: scenariosMap.entries.map((entry) {
//           final String scenarioName = entry.key;
//           final Map<String, dynamic> model = entry.value['model'] as Map<String, dynamic>;
//           final List<Map<String, dynamic>> processesJson =
//               (model['processes'] as List<dynamic>).cast<Map<String, dynamic>>();
//           final List<Map<String, dynamic>> flowsJson =
//               (model['flows'] as List<dynamic>).cast<Map<String, dynamic>>();

//           // Convert JSON into ProcessNode objects
//           final List<ProcessNode> processes =
//               processesJson.map((j) => ProcessNode.fromJson(j)).toList();

//           // Compute bounding box so the canvas fits all ProcessNodeWidgets
//           double maxX = 0, maxY = 0;
//           for (var node in processes) {
//             final sz = ProcessNodeWidget.sizeFor(node);
//             final double rightEdge = node.position.dx + sz.width;
//             final double bottomEdge = node.position.dy + sz.height;
//             if (rightEdge > maxX) maxX = rightEdge;
//             if (bottomEdge > maxY) maxY = bottomEdge;
//           }
//           // Add padding around the canvas
//           final double canvasWidth = maxX + 200;
//           final double canvasHeight = maxY + 200;

//           return Padding(
//             padding: const EdgeInsets.all(8.0),
//             child: SizedBox(
//               width: canvasWidth + 35, // extra for vertical scrollbars
//               child: SingleChildScrollView(
//                 scrollDirection: Axis.vertical,
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.center,
//                   children: [
//                     Text(
//                       scenarioName,
//                       style: TextStyle(fontWeight: FontWeight.bold),
//                     ),
//                     SizedBox(
//                       width: canvasWidth,
//                       height: canvasHeight,
//                       child: Card(
//                         elevation: 4,
//                         child: Padding(
//                           padding: const EdgeInsets.all(8.0),
//                           child: Stack(
//                             children: [
//                               // Draw connections behind using UndirectedConnectionPainter
//                               CustomPaint(
//                                 size: Size(canvasWidth, canvasHeight),
//                                 painter: UndirectedConnectionPainter(processes, flowsJson),
//                               ),
//                               // Position each process node
//                               for (var node in processes)
//                                 Positioned(
//                                   left: node.position.dx,
//                                   top: node.position.dy,
//                                   child: ProcessNodeWidget(node: node),
//                                 ),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           );
//         }).toList(),
//       ),
//     );
//   }
// }


// File: lib/lca/results.dart

// import 'dart:math';

// import 'package:flutter/material.dart';
// import 'package:fl_chart/fl_chart.dart';

// // Adjust this import to wherever you defined ProcessNode, ProcessNodeWidget, UndirectedConnectionPainter:
// import 'home.dart';
// // File: lib/lca/results.dart

// import 'dart:math';

// import 'package:flutter/material.dart';
// import 'package:fl_chart/fl_chart.dart';

// import 'home.dart';
// // File: lib/lca/results.dart

// import 'dart:math';
// import 'package:flutter/material.dart';
// import 'package:fl_chart/fl_chart.dart';
// import 'home.dart';

// class ResultsPage extends StatefulWidget {
//   final Map<String, dynamic> results;
//   final Map<String, dynamic>? scenariosMap;

//   const ResultsPage({
//     required this.results,
//     this.scenariosMap,
//     Key? key,
//   }) : super(key: key);

//   @override
//   _ResultsPageState createState() => _ResultsPageState();
// }

// class _ResultsPageState extends State<ResultsPage> with SingleTickerProviderStateMixin {
//   late final TabController _tabController;
//   late final List<String> _names;
//   late final List<double> _scores;
//   String? _bestName;
//   double? _bestScore;

//   static const double _barWidth = 24.0;
//   static const double _groupSpace = 25.0;
//   static const double _leftMargin = 40.0;
//   static const double _rightMargin = 16.0;
//   static const double _bottomMargin = 60.0;

//   @override
//   void initState() {
//     super.initState();
//     _tabController = TabController(length: 2, vsync: this);

//     _names = widget.results.keys.toList();
//     // _scores = _names.map((n) {
//     //   final info = widget.results[n] as Map<String, dynamic>;
//     //   return info['success'] == true
//     //       ? (info['result']['score'] as num).toDouble()
//     //       : 0.0;
//     // }).toList();
//     _scores = _names.map((n) {
//   final info = widget.results[n] as Map<String, dynamic>;
//   final emissionsMap = info['result']?['emissions_per_process'] as Map<String, dynamic>?;
//   return (info['success'] == true && emissionsMap != null)
//       ? emissionsMap.values.map((e) => (e as num).toDouble()).fold(0.0, (a, b) => a + b)
//       : 0.0;
// }).toList();


//     for (var i = 0; i < _names.length; i++) {
//       final sc = _scores[i];
//       if (_bestScore == null || sc < _bestScore!) {
//         _bestScore = sc;
//         _bestName = _names[i];
//       }
//     }
//   }

//   double _niceNum(double x, bool round) {
//     if (x == 0) return 0;
//     final exp = (log(x) / ln10).floor();
//     final f = x / pow(10, exp);
//     double nf;
//     if (round) {
//       if (f < 1.5) nf = 1;
//       else if (f < 3) nf = 2;
//       else if (f < 7) nf = 5;
//       else nf = 10;
//     } else {
//       if (f <= 1) nf = 1;
//       else if (f <= 2) nf = 2;
//       else if (f <= 5) nf = 5;
//       else nf = 10;
//     }
//     return nf * pow(10, exp);
//   }

//   @override
//   Widget build(BuildContext context) {
//     // Compute “nice” axis max & interval
//     final rawMax = _scores.isEmpty ? 1.0 : _scores.reduce(max);
//     final niceMax = _niceNum(rawMax, false);
//     final interval = _niceNum(niceMax / 5, true);

//     // Adaptive width for dynamic number of bars
//     final chartWidth = _leftMargin +
//         _names.length * _barWidth +
//         (_names.length - 1) * _groupSpace +
//         _rightMargin;

//     final accent = Theme.of(context).colorScheme.secondary;

//     final chartCard = Card(
//       margin: const EdgeInsets.all(16),
//       elevation: 4,
//       child: Padding(
//         padding: const EdgeInsets.symmetric(vertical: 16),
//         child: Column(
//           children: [
//             Text(
//               widget.results.isNotEmpty
//                   ? widget.results.values
//                           .map((v) => (v['result']?['method'] as List?)?.join(' ▶ '))
//                           .whereType<String>()
//                           .toSet()
//                           .single
//                   : 'LCA Impact Comparison',
//               style: Theme.of(context)
//                   .textTheme
//                   .titleLarge!
//                   .copyWith(fontWeight: FontWeight.bold),
//             ),
//             const SizedBox(height: 4),
//             Text(
//               'Lower bars = less CO₂ eqv',
//               style: Theme.of(context).textTheme.bodySmall,
//             ),
//             const SizedBox(height: 16),
//             SingleChildScrollView(
//               scrollDirection: Axis.horizontal,
//               padding: const EdgeInsets.symmetric(horizontal: 16),
//               child: SizedBox(
//                 width: chartWidth,
//                 height: 300,
//                 child: BarChart(
//                   BarChartData(
//                     maxY: niceMax,
//                     gridData: FlGridData(
//                       show: true,
//                       drawVerticalLine: false,
//                       horizontalInterval: interval,
//                       getDrawingHorizontalLine: (_) => FlLine(
//                         color: Colors.grey.shade300,
//                         strokeWidth: 1,
//                       ),
//                     ),
//                     titlesData: FlTitlesData(
//                       leftTitles: AxisTitles(
//                         axisNameWidget: const Padding(
//                           padding: EdgeInsets.only(bottom: 4),
//                           child: Text('kg CO₂ eqv'),
//                         ),
//                         axisNameSize: 20,
//                         sideTitles: SideTitles(
//                           showTitles: true,
//                           interval: interval,
//                           reservedSize: _leftMargin,
//                           getTitlesWidget: (val, _) => Text(
//                             val.toStringAsFixed(0),
//                             style: const TextStyle(fontSize: 12),
//                           ),
//                         ),
//                       ),
//                       bottomTitles: AxisTitles(
//                         axisNameWidget: const Padding(
//                           padding: EdgeInsets.only(top: 4),
//                           child: Text('Scenarios'),
//                         ),
//                         axisNameSize: 20,
//                         sideTitles: SideTitles(
//                           showTitles: true,
//                           reservedSize: _bottomMargin,
//                           getTitlesWidget: (val, meta) {
//                             final i = val.toInt();
//                             if (i < 0 || i >= _names.length) return const SizedBox();
//                             return SideTitleWidget(
//                               axisSide: meta.axisSide,
//                               child: RotatedBox(
//                                 quarterTurns: 1, // fully vertical
//                                 child: Text(
//                                   _names[i],
//                                   style: const TextStyle(fontSize: 12),
//                                 ),
//                               ),
//                             );
//                           },
//                         ),
//                       ),
//                       topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
//                       rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
//                     ),
//                     barTouchData: BarTouchData(
//                       enabled: true,
//                       touchTooltipData: BarTouchTooltipData(
//                         tooltipPadding:
//                             const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                         getTooltipItem: (group, groupIndex, rod, rodIndex) =>
//                             BarTooltipItem(
//                           '${rod.toY.toStringAsFixed(2)} kg',
//                           const TextStyle(
//                               color: Colors.black, fontWeight: FontWeight.bold),
//                         ),
//                       ),
//                     ),
//                     barGroups: List.generate(_names.length, (i) {
//                       final isBest = _names[i] == _bestName;
//                       return BarChartGroupData(
//                         x: i,
//                         barRods: [
//                           BarChartRodData(
//                             toY: _scores[i],
//                             width: _barWidth,
//                             borderRadius: BorderRadius.circular(6),
//                             color: isBest ? accent : null,
//                             gradient: isBest
//                                 ? null
//                                 : const LinearGradient(
//                                     begin: Alignment.bottomCenter,
//                                     end: Alignment.topCenter,
//                                     colors: [Colors.lightGreen, Colors.green],
//                                   ),
//                           ),
//                         ],
//                       );
//                     }),
//                     groupsSpace: _groupSpace,
//                   ),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );

//     final detailList = ListView.builder(
//       padding: const EdgeInsets.symmetric(horizontal: 16),
//       itemCount: _names.length,
//       itemBuilder: (ctx, i) {
//         final name = _names[i];
//         final info = widget.results[name] as Map<String, dynamic>;
//         final ok = info['success'] as bool;
//         final res = ok ? info['result'] as Map<String, dynamic> : null;
//         final scoreText = ok ? (res!['score'] as num).toStringAsFixed(2) : '-';
//         final methodText = ok && res != null && res['method'] is List
//             ? (res?['method'] as List?)?.join(' ▶ ') ?? 'n/a'
//             : 'n/a';
//         final dbText = ok && res != null ? res['database'] as String : 'n/a';

//         return Card(
//           margin: const EdgeInsets.symmetric(vertical: 6),
//           child: ExpansionTile(
//             leading: Icon(
//               ok ? Icons.check_circle : Icons.error,
//               color: ok ? Colors.green : Colors.red,
//             ),
//             title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
//             subtitle: Text(
//               ok ? 'Score: $scoreText kg CO₂' : 'Error: ${info['error']}',
//             ),
//             children: ok
//                 ? [
//                     _buildDetailRow('Method:', methodText),
//                     _buildDetailRow('Database:', dbText),
//                   ]
//                 : [],
//           ),
//         );
//       },
//     );

//     final graphView = (widget.scenariosMap != null &&
//             _bestName != null &&
//             widget.scenariosMap!.containsKey(_bestName!))
//         ? _buildGraphCard(context)
//         : Center(
//             child: Padding(
//               padding: const EdgeInsets.all(32),
//               child: Text(
//                 'No detailed graph available.\nExpand the list below to see details for each scenario.',
//                 textAlign: TextAlign.center,
//                 style: Theme.of(context).textTheme.bodySmall,
//               ),
//             ),
//           );

//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('LCA Results'),
//         bottom: TabBar(
//           controller: _tabController,
//           tabs: const [
//             Tab(text: 'Overview'),
//             Tab(text: 'Process Graph'),
//           ],
//         ),
//       ),
//       body: TabBarView(
//         controller: _tabController,
//         children: [
//           Column(
//             children: [
//               chartCard,
//               Expanded(child: detailList),
//             ],
//           ),
//           graphView,
//         ],
//       ),
//     );
//   }

//   Widget _buildDetailRow(String label, String value) {
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
//       child: Row(
//         children: [
//           Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
//           const SizedBox(width: 8),
//           Expanded(child: Text(value)),
//         ],
//       ),
//     );
//   }

//   Widget _buildGraphCard(BuildContext context) {
//     final scenarioData = widget.scenariosMap![_bestName!] as Map<String, dynamic>;
//     final model = scenarioData['model'] as Map<String, dynamic>;
//     final processesJson = (model['processes'] as List).cast<Map<String, dynamic>>();
//     final flowsJson = (model['flows'] as List).cast<Map<String, dynamic>>();
//     final processes = processesJson.map((j) => ProcessNode.fromJson(j)).toList();

//     double maxX = 0, maxY = 0;
//     for (var n in processes) {
//       final sz = ProcessNodeWidget.sizeFor(n);
//       maxX = max(maxX, n.position.dx + sz.width);
//       maxY = max(maxY, n.position.dy + sz.height);
//     }
//     final canvasW = maxX + 40;
//     final canvasH = maxY + 40;

//     return Card(
//       margin: const EdgeInsets.all(16),
//       elevation: 4,
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.stretch,
//         children: [
//           Padding(
//             padding: const EdgeInsets.all(16),
//             child: Text(
//               'Best Scenario: $_bestName',
//               style: Theme.of(context)
//                   .textTheme
//                   .titleMedium!
//                   .copyWith(fontWeight: FontWeight.bold),
//             ),
//           ),
//           Expanded(
//             child: InteractiveViewer(
//               boundaryMargin: const EdgeInsets.all(32),
//               minScale: 0.5,
//               maxScale: 2.5,
//               child: SizedBox(
//                 width: canvasW,
//                 height: canvasH,
//                 child: Stack(
//                   children: [
//                     CustomPaint(
//                       size: Size(canvasW, canvasH),
//                       painter: UndirectedConnectionPainter(processes, flowsJson),
//                     ),
//                     for (var node in processes)
//                       Positioned(
//                         left: node.position.dx,
//                         top: node.position.dy,
//                         child: ProcessNodeWidget(node: node),
//                       ),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }





// import 'dart:io';
// import 'dart:math';

// import 'package:earlylca/lca/newhome/lca_models.dart';
// import 'package:earlylca/lca/newhome/lca_painters.dart';
// import 'package:earlylca/lca/newhome/lca_widgets.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:fl_chart/fl_chart.dart';
// import 'package:path_provider/path_provider.dart';

// import 'generate_pdf.dart';
// import 'home.dart';
// import 'dart:html' as html;
// import 'generate_pdf.dart';

// /// Presents LCA results in a 2×3 grid of charts.  
// /// Tap any chart to see the process graph for its best scenario.
// class ResultsPage extends StatefulWidget {
//   final Map<String, dynamic> results;
//   final Map<String, dynamic>? scenariosMap;

//   const ResultsPage({
//     required this.results,
//     this.scenariosMap,
//     Key? key,
//   }) : super(key: key);

//   @override
//   _ResultsPageState createState() => _ResultsPageState();
// }

// class _ResultsPageState extends State<ResultsPage> {
//   late final List<String> _methodNames;
//   late final List<String> _scenarioNames;
//   late final Map<String, String> _bestPerMethod;

//   static const double _barWidth = 24.0;
//   static const double _leftMargin = 40.0;
//   static const double _bottomMargin = 80.0;

//   /// Map of method → y-axis label
//   // static const Map<String, String> _yAxisLabels = {
//   //   'GWP 100a': 'kg CO₂ eq',
//   //   'GWP 20a':  'kg CO₂ eq',
//   //   'acidification (incl. fate, average Europe total, A&B) no LT': 'kg SO₂ eq',
//   //   'eutrophication (fate not incl.) no LT':              'kg PO₄³⁻ eq',
//   //   'ozone layer depletion (ODP steady state) no LT':     'kg CFC-11 eq',
//   //   'human toxicity (HTP inf) no LT':                     'kg 1,4-DB eq',
//   //   'freshwater ecotoxicity potential (FETP) no LT':        'kg 1,4-DB eq',
//   //   'marine ecotoxicity potential (METP) no LT':            'kg 1,4-DB eq',
//   //   'terrestrial acidification potential (TAP) no LT':      'kg SO₂ eq',
//   //   'global warming potential (GWP1000) no LT':         'kg CO₂ eq',
//   // };
// static const List<MapEntry<String, String>> _yAxisLabelRules = [

//   // Climate change (GWP) — ReCiPe 2016
//   MapEntry('climate change', 'kg CO₂ eq'),
//   MapEntry('global warming', 'kg CO₂ eq'),
//   MapEntry('GWP100', 'kg CO₂ eq'),
//   MapEntry('GWP 100a', 'kg CO₂ eq'),
//   MapEntry('GWP20', 'kg CO₂ eq'),
//   MapEntry('GWP 20a', 'kg CO₂ eq'),
//   MapEntry('GWP500', 'kg CO₂ eq'),
//   MapEntry('GWP1000', 'kg CO₂ eq'),

//   // Terrestrial acidification (TAP)
//   MapEntry('acidification: terrestrial', 'kg SO₂ eq'),
//   MapEntry('terrestrial acidification', 'kg SO₂ eq'),
//   MapEntry('TAP', 'kg SO₂ eq'),

//   // Photochemical oxidant (ozone) formation — ReCiPe 2016 uses kg NMVOC eq
//   MapEntry('photochemical oxidant formation: human health', 'kg NMVOC eq'),
//   MapEntry('photochemical oxidant formation: terrestrial ecosystems', 'kg NMVOC eq'),
//   MapEntry('photochemical ozone formation', 'kg NMVOC eq'),
//   MapEntry('POFP', 'kg NMVOC eq'),
//   MapEntry('HOFP', 'kg NMVOC eq'),
//   MapEntry('EOFP', 'kg NMVOC eq'),

//   // Ecotoxicity: freshwater (FETP)
//   MapEntry('ecotoxicity: freshwater', 'kg 1,4-DCB eq'),
//   MapEntry('freshwater ecotoxicity', 'kg 1,4-DCB eq'),
//   MapEntry('FETP', 'kg 1,4-DCB eq'),

//   // Human toxicity (ReCiPe splits cancer / non-cancer but both are 1,4-DCB eq)
//   MapEntry('human toxicity: cancer', 'kg 1,4-DCB eq'),
//   MapEntry('human toxicity: non-cancer', 'kg 1,4-DCB eq'),
//   MapEntry('human toxicity', 'kg 1,4-DCB eq'),
//   MapEntry('HTP', 'kg 1,4-DCB eq'),

//   // Optional extras you already hint at — corrected units
//   MapEntry('marine ecotoxicity', 'kg 1,4-DCB eq'),
//   MapEntry('METP', 'kg 1,4-DCB eq'),

//   // Eutrophication (ReCiPe 2016 splits freshwater vs marine)
//   MapEntry('freshwater eutrophication', 'kg P eq'),
//   MapEntry('FEP', 'kg P eq'),
//   MapEntry('marine eutrophication', 'kg N eq'),
//   MapEntry('MEP', 'kg N eq'),

//   // Stratospheric ozone depletion (avoid the ambiguous key "ozone")
//   MapEntry('ozone depletion', 'kg CFC-11 eq'),
//   MapEntry('ODP', 'kg CFC-11 eq'),

//   // A few common ReCiPe midpoints if you show them later
//   MapEntry('particulate matter formation', 'kg PM2.5 eq'),
//   MapEntry('PMFP', 'kg PM2.5 eq'),
//   MapEntry('ionising radiation', 'kBq Co-60 eq'),
//   MapEntry('IRP', 'kBq Co-60 eq'),
//   MapEntry('water consumption', 'm³ world eq deprived'),
//   MapEntry('WDP', 'm³ world eq deprived'),
//   MapEntry('fossil resource scarcity', 'kg oil eq'),
//   MapEntry('FDP', 'kg oil eq'),
//   MapEntry('mineral resource scarcity', 'kg Cu eq'),
//   MapEntry('MDP', 'kg Cu eq'),
//   MapEntry('land use', 'm²a crop eq'),
//   MapEntry('LDP', 'm²a crop eq'),
// ];


//   @override
//   void initState() {
//     super.initState();

//     // 1. Gather names
//     _scenarioNames = widget.results.keys.toList();
//     final firstScores = (widget.results[_scenarioNames.first]!['result']
//             as Map<String, dynamic>)['scores'] as Map<String, dynamic>;
//     _methodNames = firstScores.keys.toList();

//     // 2. Compute best scenario per method
//     _bestPerMethod = {};
//     for (var method in _methodNames) {
//       var bestScore = double.infinity;
//       var bestName = _scenarioNames.first;
//       for (var scenario in _scenarioNames) {
//         final info = widget.results[scenario]! as Map<String, dynamic>;
//         if (info['success'] == true) {
//           final scmap = (info['result'] as Map<String, dynamic>)['scores']
//               as Map<String, dynamic>;
//           final val = (scmap[method] as num).toDouble();
//           if (val < bestScore) {
//             bestScore = val;
//             bestName = scenario;
//           }
//         }
//       }
//       _bestPerMethod[method] = bestName;
//     }
//   }
// void _downloadPdf(Uint8List pdfData) {
//   final blob = html.Blob([pdfData], 'application/pdf');
//   final url  = html.Url.createObjectUrlFromBlob(blob);
//   final anchor = html.document.createElement('a') as html.AnchorElement
//     ..href     = url
//     ..style.display = 'none'
//     ..download = 'lca_results.pdf';
//   html.document.body!.append(anchor);
// anchor.click();
// // remove the anchor from the DOM
// anchor.remove();
// // then revoke the blob URL
// html.Url.revokeObjectUrl(url);

// }
// String _guessYAxisLabel(String methodName) {
//   final nameLower = methodName.toLowerCase();
//   for (final entry in _yAxisLabelRules) {
//     if (nameLower.contains(entry.key.toLowerCase())) {
//       return entry.value;
//     }
//   }
//   return 'impact units'; // fallback
// }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//       title: const Text('LCA Results by Method'),
    
//     ),

//       body: Padding(
//         padding: const EdgeInsets.all(8),
//         child: GridView.builder(
//           itemCount: _methodNames.length,
//           gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//             crossAxisCount: 2,       // two columns
//             mainAxisSpacing: 8,
//             crossAxisSpacing: 8,
//             childAspectRatio: 0.9,   // roughly fits 3 rows per screen
//           ),
//           itemBuilder: (context, i) => _buildMethodCard(context, _methodNames[i]),
//         ),
//       ),
//     );
//   }

//   Widget _buildMethodCard(BuildContext context, String method) {
//     // collect scores
//     final scores = _scenarioNames.map((scenario) {
//       final info = widget.results[scenario]! as Map<String, dynamic>;
//       if (info['success'] != true) return 0.0;
//       final scmap = (info['result'] as Map<String, dynamic>)['scores']
//           as Map<String, dynamic>;
//       return (scmap[method] as num).toDouble();
//     }).toList();

//     // axis computation
//     var rawMax = scores.isEmpty ? 0.0 : scores.reduce(max);
//     if (rawMax <= 0) rawMax = 1.0;
//     final niceMax = _niceNum(rawMax, false);
//     var interval = _niceNum(niceMax / 5, true);
//     if (interval <= 0) interval = 1;

//     final bestScenario = _bestPerMethod[method]!;

//     // lookup y-axis label
// final yLabel = _guessYAxisLabel(method);

//     return GestureDetector(
//       onTap: () {
//         Navigator.push(
//           context,
//           MaterialPageRoute(
//             builder: (_) => ScenarioDetailPage(
//               scenarioName: bestScenario,
//               scenariosMap: widget.scenariosMap,
//             ),
//           ),
//         );
//       },
//       child: Card(
//         elevation: 2,
//         color: Colors.white,
//         child: Column(
//           children: [
//             Padding(
//               padding: const EdgeInsets.symmetric(vertical: 6),
//               child: Text(
//                 method,
//                 textAlign: TextAlign.center,
//                 style: Theme.of(context)
//                     .textTheme
//                     .bodyMedium
//                     ?.copyWith(fontWeight: FontWeight.bold),
//               ),
//             ),
//             Expanded(
//               child: SingleChildScrollView(
//                 scrollDirection: Axis.horizontal,
//                 padding: const EdgeInsets.only(bottom: 4),
//                 child: SizedBox(
//                   width: _leftMargin +
//                       _scenarioNames.length * _barWidth +
//                       (_scenarioNames.length - 1) * 16 +
//                       _leftMargin,
//                   child: BarChart(
//                     BarChartData(
//                       backgroundColor: Colors.white,

//                       maxY: niceMax,
//                       gridData: FlGridData(
//                         show: true,
//                         drawVerticalLine: false,
//                         horizontalInterval: interval,
//                         getDrawingHorizontalLine: (_) => FlLine(
//                           color: Colors.grey.shade300,
//                           strokeWidth: 1,
//                         ),
//                       ),
//                       titlesData: FlTitlesData(
//                         leftTitles: AxisTitles(
//                           axisNameWidget: Padding(
//                             padding: const EdgeInsets.only(bottom: 0),
//                             child: Text(yLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
// ),
//                           ),
//                           sideTitles: SideTitles(
//                             showTitles: true,
//                             interval: interval,
//                             reservedSize: _leftMargin,
//                             getTitlesWidget: (val, _) => Text(
//                               val.toStringAsFixed(0),
//                               style: const TextStyle(fontSize: 10),
//                             ),
//                           ),
//                         ),
//                         bottomTitles: AxisTitles(
//                           axisNameWidget: const SizedBox(),
//                           sideTitles: SideTitles(
//                             showTitles: true,
//                             reservedSize: _bottomMargin,
//                             getTitlesWidget: (val, meta) {
//                               final idx = val.toInt();
//                               if (idx < 0 || idx >= _scenarioNames.length) {
//                                 return const SizedBox();
//                               }
//                               return SideTitleWidget(
//                                 axisSide: meta.axisSide,
//                                 child: 
//                                 Transform.rotate(
//                                   angle: -pi / 3, // less rotation (-60°)
//                                   child: SizedBox(
//                                     width: 80, // fixed width to wrap or clip text
//                                     child: Text(
//                                       _scenarioNames[idx],
//                                       style: const TextStyle(fontSize: 11),
//                                       overflow: TextOverflow.ellipsis,
//                                       softWrap: false,
//                                       maxLines: 1,
//                                     ),
//                                   ),
//                                 ),

//                                 // Transform.rotate(
//                                 //   angle: -pi / 2,
//                                 //   child: Padding(
//                                 //     padding: const EdgeInsets.all(8.0),
//                                 //     child: Text(
//                                 //       _scenarioNames[idx],
//                                 //       style: const TextStyle(fontSize: 10,fontWeight: FontWeight.w500),
//                                 //     ),
//                                 //   ),
//                                 // ),
//                               );
//                             },
//                           ),
//                         ),
//                         topTitles: AxisTitles(
//                           sideTitles: SideTitles(showTitles: false),
//                         ),
//                         rightTitles: AxisTitles(
//                           sideTitles: SideTitles(showTitles: false),
//                         ),
//                       ),
//                       barGroups: List.generate(
//                         _scenarioNames.length,
//                         (i) {
//                           final name = _scenarioNames[i];
//                           final y = scores[i];
//                           final isBest = name == bestScenario;
//                           return BarChartGroupData(
//                             x: i,
//                             barRods: [
//                               BarChartRodData(
//                                 toY: y,
//                                 width: _barWidth,
//                                 borderRadius: BorderRadius.circular(4),
//                                 color: isBest ? Colors.green : Colors.black,

//                               ),
//                             ],
//                           );
//                         },
//                       ),
//                       groupsSpace: 16,
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   double _niceNum(double x, bool round) {
//     if (x == 0) return 0;
//     final exp = (log(x) / ln10).floor();
//     final f = x / pow(10, exp);
//     double nf;
//     if (round) {
//       if (f < 1.5) nf = 1;
//       else if (f < 3) nf = 2;
//       else if (f < 7) nf = 5;
//       else nf = 10;
//     } else {
//       if (f <= 1) nf = 1;
//       else if (f <= 2) nf = 2;
//       else if (f <= 5) nf = 5;
//       else nf = 10;
//     }
//     return nf * pow(10, exp);
//   }
// }

// /// Detail page showing the interactive process graph.
// class ScenarioDetailPage extends StatelessWidget {
//   final String scenarioName;
//   final Map<String, dynamic>? scenariosMap;

//   const ScenarioDetailPage({
//     required this.scenarioName,
//     required this.scenariosMap,
//     Key? key,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     if (scenariosMap == null ||
//         scenariosMap!.containsKey(scenarioName) == false) {
//       return Scaffold(
//         appBar: AppBar(title: Text(scenarioName)),
//         body: const Center(child: Text('No graph data available')),
//       );
//     }

//     final data = scenariosMap![scenarioName] as Map<String, dynamic>;
//     final model = data['model'] as Map<String, dynamic>;
//     final procsJson = (model['processes'] as List)
//         .cast<Map<String, dynamic>>();
//     final flowsJson = (model['flows'] as List)
//         .cast<Map<String, dynamic>>();
//     final processes =
//         procsJson.map((j) => ProcessNode.fromJson(j)).toList();

//     // compute canvas size
//     double maxX = 0, maxY = 0;
//     for (var n in processes) {
//       final sz = ProcessNodeWidget.sizeFor(n);
//       maxX = max(maxX, n.position.dx + sz.width);
//       maxY = max(maxY, n.position.dy + sz.height);
//     }
//     final canvasW = maxX + 40;
//     final canvasH = maxY + 40;

//     return Scaffold(
//       appBar: AppBar(title: Text(scenarioName)),
//       body: InteractiveViewer(
//         boundaryMargin: const EdgeInsets.all(32),
//         minScale: 0.5,
//         maxScale: 2.5,
//         child: SizedBox(
//           width: canvasW,
//           height: canvasH,
//           child: Stack(
//             children: [
//               CustomPaint(
//                 size: Size(canvasW, canvasH),
//               painter: UndirectedConnectionPainter(processes, flowsJson, nodeHeightScale: const {}),

//               ),
//               for (var node in processes)
//                 Positioned(
//                   left: node.position.dx,
//                   top: node.position.dy,
//                   child: ProcessNodeWidget(node: node),
//                 ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }



// import 'dart:io';
// import 'dart:math';

// import 'package:earlylca/lca/newhome/lca_models.dart';
// import 'package:earlylca/lca/newhome/lca_painters.dart';
// import 'package:earlylca/lca/newhome/lca_widgets.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:fl_chart/fl_chart.dart';
// import 'package:path_provider/path_provider.dart';

// import 'generate_pdf.dart';
// import 'home.dart';
// import 'dart:html' as html;
// // keep single import
// // import 'generate_pdf.dart';

// /// Presents LCA results in a 2×3 grid of charts.
// /// Tap any chart to see the process graph for its best scenario.
// class ResultsPage extends StatefulWidget {
//   final Map<String, dynamic> results;
//   final Map<String, dynamic>? scenariosMap;

//   const ResultsPage({
//     required this.results,
//     this.scenariosMap,
//     Key? key,
//   }) : super(key: key);

//   @override
//   _ResultsPageState createState() => _ResultsPageState();
// }

// class _ResultsPageState extends State<ResultsPage> {
//   late final List<String> _methodNames;
//   late final List<String> _scenarioNames;
//   late final Map<String, String> _bestPerMethod;

//   static const double _barWidth = 24.0;
//   static const double _leftMargin = 48.0;   // slightly wider to fit larger fonts
//   static const double _bottomMargin = 92.0; // slightly taller to fit labels

//   /// Ordered rules for guessing y-axis labels based on method names
//   static const List<MapEntry<String, String>> _yAxisLabelRules = [
//     // Climate change (GWP) ReCiPe 2016
//     MapEntry('climate change', 'kg CO₂ eq'),
//     MapEntry('global warming', 'kg CO₂ eq'),
//     MapEntry('GWP100', 'kg CO₂ eq'),
//     MapEntry('GWP 100a', 'kg CO₂ eq'),
//     MapEntry('GWP20', 'kg CO₂ eq'),
//     MapEntry('GWP 20a', 'kg CO₂ eq'),
//     MapEntry('GWP500', 'kg CO₂ eq'),
//     MapEntry('GWP1000', 'kg CO₂ eq'),

//     // Terrestrial acidification (TAP)
//     MapEntry('acidification: terrestrial', 'kg SO₂ eq'),
//     MapEntry('terrestrial acidification', 'kg SO₂ eq'),
//     MapEntry('TAP', 'kg SO₂ eq'),

//     // Photochemical oxidant formation
//     MapEntry('photochemical oxidant formation: human health', 'kg NMVOC eq'),
//     MapEntry('photochemical oxidant formation: terrestrial ecosystems', 'kg NMVOC eq'),
//     MapEntry('photochemical ozone formation', 'kg NMVOC eq'),
//     MapEntry('POFP', 'kg NMVOC eq'),
//     MapEntry('HOFP', 'kg NMVOC eq'),
//     MapEntry('EOFP', 'kg NMVOC eq'),

//     // Ecotoxicity
//     MapEntry('ecotoxicity: freshwater', 'kg 1,4-DCB eq'),
//     MapEntry('freshwater ecotoxicity', 'kg 1,4-DCB eq'),
//     MapEntry('FETP', 'kg 1,4-DCB eq'),
//     MapEntry('marine ecotoxicity', 'kg 1,4-DCB eq'),
//     MapEntry('METP', 'kg 1,4-DCB eq'),

//     // Human toxicity
//     MapEntry('human toxicity: cancer', 'kg 1,4-DCB eq'),
//     MapEntry('human toxicity: non-cancer', 'kg 1,4-DCB eq'),
//     MapEntry('human toxicity', 'kg 1,4-DCB eq'),
//     MapEntry('HTP', 'kg 1,4-DCB eq'),

//     // Eutrophication
//     MapEntry('freshwater eutrophication', 'kg P eq'),
//     MapEntry('FEP', 'kg P eq'),
//     MapEntry('marine eutrophication', 'kg N eq'),
//     MapEntry('MEP', 'kg N eq'),

//     // Ozone depletion
//     MapEntry('ozone depletion', 'kg CFC-11 eq'),
//     MapEntry('ODP', 'kg CFC-11 eq'),

//     // Misc ReCiPe midpoints
//     MapEntry('particulate matter formation', 'kg PM2.5 eq'),
//     MapEntry('PMFP', 'kg PM2.5 eq'),
//     MapEntry('ionising radiation', 'kBq Co-60 eq'),
//     MapEntry('IRP', 'kBq Co-60 eq'),
//     MapEntry('water consumption', 'm³ world eq deprived'),
//     MapEntry('WDP', 'm³ world eq deprived'),
//     MapEntry('fossil resource scarcity', 'kg oil eq'),
//     MapEntry('FDP', 'kg oil eq'),
//     MapEntry('mineral resource scarcity', 'kg Cu eq'),
//     MapEntry('MDP', 'kg Cu eq'),
//     MapEntry('land use', 'm²a crop eq'),
//     MapEntry('LDP', 'm²a crop eq'),
//   ];

//   @override
//   void initState() {
//     super.initState();

//     // 1. Gather names
//     _scenarioNames = widget.results.keys.toList();
//     final firstScores = (widget.results[_scenarioNames.first]!['result']
//             as Map<String, dynamic>)['scores'] as Map<String, dynamic>;
//     _methodNames = firstScores.keys.toList();

//     // 2. Compute best scenario per method
//     _bestPerMethod = {};
//     for (var method in _methodNames) {
//       var bestScore = double.infinity;
//       var bestName = _scenarioNames.first;
//       for (var scenario in _scenarioNames) {
//         final info = widget.results[scenario]! as Map<String, dynamic>;
//         if (info['success'] == true) {
//           final scmap = (info['result'] as Map<String, dynamic>)['scores']
//               as Map<String, dynamic>;
//           final val = (scmap[method] as num).toDouble();
//           if (val < bestScore) {
//             bestScore = val;
//             bestName = scenario;
//           }
//         }
//       }
//       _bestPerMethod[method] = bestName;
//     }
//   }

//   void _downloadPdf(Uint8List pdfData) {
//     final blob = html.Blob([pdfData], 'application/pdf');
//     final url = html.Url.createObjectUrlFromBlob(blob);
//     final anchor = html.document.createElement('a') as html.AnchorElement
//       ..href = url
//       ..style.display = 'none'
//       ..download = 'lca_results.pdf';
//     html.document.body!.append(anchor);
//     anchor.click();
//     anchor.remove();
//     html.Url.revokeObjectUrl(url);
//   }

//   String _guessYAxisLabel(String methodName) {
//     final nameLower = methodName.toLowerCase();
//     for (final entry in _yAxisLabelRules) {
//       if (nameLower.contains(entry.key.toLowerCase())) {
//         return entry.value;
//       }
//     }
//     return 'impact units'; // fallback
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('LCA Results by Method'),
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(8),
//         child: GridView.builder(
//           itemCount: _methodNames.length,
//           gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//             crossAxisCount: 2,       // two columns
//             mainAxisSpacing: 8,
//             crossAxisSpacing: 8,
//             childAspectRatio: 0.9,   // roughly fits 3 rows per screen
//           ),
//           itemBuilder: (context, i) => _buildMethodCard(context, _methodNames[i]),
//         ),
//       ),
//     );
//   }

//   Widget _buildMethodCard(BuildContext context, String method) {
//     // Collect scores for this method across all scenarios
//     final scores = _scenarioNames.map((scenario) {
//       final info = widget.results[scenario]! as Map<String, dynamic>;
//       if (info['success'] != true) return 0.0;
//       final scmap = (info['result'] as Map<String, dynamic>)['scores']
//           as Map<String, dynamic>;
//       return (scmap[method] as num).toDouble();
//     }).toList();

//     // Compute axis from actual min and max
//     final axis = _computeNiceAxis(scores, maxTicks: 6);
//     final bestScenario = _bestPerMethod[method]!;
//     final yLabel = _guessYAxisLabel(method);

//     return GestureDetector(
//       onTap: () {
//         Navigator.push(
//           context,
//           MaterialPageRoute(
//             builder: (_) => ScenarioDetailPage(
//               scenarioName: bestScenario,
//               scenariosMap: widget.scenariosMap,
//             ),
//           ),
//         );
//       },
//       child: Card(
//         elevation: 2,
//         color: Colors.white,
//         child: Column(
//           children: [
//             Padding(
//               padding: const EdgeInsets.symmetric(vertical: 6),
//               child: Text(
//                 method,
//                 textAlign: TextAlign.center,
//                 style: Theme.of(context)
//                     .textTheme
//                     .bodyMedium
//                     ?.copyWith(fontWeight: FontWeight.bold, fontSize: 15),
//               ),
//             ),
//             Expanded(
//               child: SingleChildScrollView(
//                 scrollDirection: Axis.horizontal,
//                 padding: const EdgeInsets.only(bottom: 4),
//                 child: SizedBox(
//                   width: _leftMargin +
//                       _scenarioNames.length * _barWidth +
//                       (_scenarioNames.length - 1) * 16 +
//                       _leftMargin,
//                   child: BarChart(
//                     BarChartData(
//                       backgroundColor: Colors.white,
//                       minY: axis.min,
//                       maxY: axis.max,
//                       gridData: FlGridData(
//                         show: true,
//                         drawVerticalLine: false,
//                         horizontalInterval: axis.interval,
//                         getDrawingHorizontalLine: (_) => FlLine(
//                           color: Colors.grey.shade300,
//                           strokeWidth: 1,
//                         ),
//                       ),
//                       titlesData: FlTitlesData(
//                         leftTitles: AxisTitles(
//                           axisNameWidget: Padding(
//                             padding: const EdgeInsets.only(bottom: 0),
//                             child: Text(
//                               yLabel,
//                               style: const TextStyle(
//                                 fontSize: 13,
//                                 fontWeight: FontWeight.w600,
//                               ),
//                             ),
//                           ),
//                           sideTitles: SideTitles(
//                             showTitles: true,
//                             interval: axis.interval,
//                             reservedSize: _leftMargin,
//                             getTitlesWidget: (val, _) => Text(
//                               _formatTick(val, axis.interval),
//                               style: const TextStyle(fontSize: 11),
//                             ),
//                           ),
//                         ),
//                         bottomTitles: AxisTitles(
//                           axisNameWidget: const SizedBox(),
//                           sideTitles: SideTitles(
//                             showTitles: true,
//                             reservedSize: _bottomMargin,
//                             getTitlesWidget: (val, meta) {
//                               final idx = val.toInt();
//                               if (idx < 0 || idx >= _scenarioNames.length) {
//                                 return const SizedBox();
//                               }
//                               return SideTitleWidget(
//                                 axisSide: meta.axisSide,
//                                 child: Transform.rotate(
//                                   angle: -pi / 3, // -60°
//                                   child: SizedBox(
//                                     width: 92,
//                                     child: Text(
//                                       _scenarioNames[idx],
//                                       style: const TextStyle(fontSize: 12),
//                                       overflow: TextOverflow.ellipsis,
//                                       softWrap: false,
//                                       maxLines: 1,
//                                     ),
//                                   ),
//                                 ),
//                               );
//                             },
//                           ),
//                         ),
//                         topTitles: const AxisTitles(
//                           sideTitles: SideTitles(showTitles: false),
//                         ),
//                         rightTitles: const AxisTitles(
//                           sideTitles: SideTitles(showTitles: false),
//                         ),
//                       ),
//                       barGroups: List.generate(
//                         _scenarioNames.length,
//                         (i) {
//                           final name = _scenarioNames[i];
//                           final y = scores[i];
//                           final isBest = name == bestScenario;
//                           return BarChartGroupData(
//                             x: i,
//                             barRods: [
//                               BarChartRodData(
//                                 toY: y,
//                                 width: _barWidth,
//                                 borderRadius: BorderRadius.circular(4),
//                                 color: isBest ? Colors.green : Colors.black,
//                               ),
//                             ],
//                           );
//                         },
//                       ),
//                       groupsSpace: 16,
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   /// Compute a nice axis that respects data min and max, supports negatives,
//   /// constant series, and tiny ranges. Returns min, max, interval.
//   _Axis _computeNiceAxis(List<double> values, {int maxTicks = 6}) {
//     if (values.isEmpty) {
//       return const _Axis(min: 0, max: 1, interval: 0.2);
//     }

//     double vMin = values.reduce(min);
//     double vMax = values.reduce(max);

//     // Handle all-equal case
//     if (vMin == vMax) {
//       final zero = vMin == 0.0;
//       final padding = zero ? 1.0 : vMin.abs() * 0.2 + 1e-9;
//       final minY = vMin - padding;
//       final maxY = vMax + padding;
//       final interval = _niceStep((maxY - minY) / (maxTicks - 1));
//       final niceMin = _floorTo(minY, interval);
//       final niceMax = _ceilTo(maxY, interval);
//       return _Axis(min: niceMin, max: niceMax, interval: interval);
//     }

//     // Add a bit of headroom and footroom
//     final range = vMax - vMin;
//     final pad = range * 0.08;
//     double rawMin = vMin - pad;
//     double rawMax = vMax + pad;

//     // If the data straddles zero, include zero nicely
//     if (vMin < 0 && vMax > 0) {
//       rawMin = min(rawMin, 0);
//       rawMax = max(rawMax, 0);
//     }

//     // Compute a nice interval
//     final roughStep = (rawMax - rawMin) / max(maxTicks - 1, 1);
//     final step = _niceStep(roughStep);

//     // Snap bounds to the step
//     final niceMin = _floorTo(rawMin, step);
//     final niceMax = _ceilTo(rawMax, step);

//     // Avoid degenerate interval
//     final interval = step <= 0 ? (niceMax - niceMin) / max(maxTicks - 1, 1) : step;

//     return _Axis(min: niceMin, max: niceMax, interval: interval);
//   }

//   /// Return a "nice" step size like 1, 2, 2.5, 5, 10, 20, etc.
//   double _niceStep(double raw) {
//     if (!raw.isFinite || raw == 0) return 1.0;
//     final sign = raw.sign;
//     final x = raw.abs();

//     final exp10 = pow(10, (log(x) / ln10).floor()).toDouble();
//     final f = x / exp10;

//     double nf;
//     if (f < 1.5)      nf = 1;
//     else if (f < 2.3) nf = 2;
//     else if (f < 3.5) nf = 2.5;
//     else if (f < 7)   nf = 5;
//     else              nf = 10;

//     return sign * nf * exp10;
//   }

//   double _floorTo(double x, double step) {
//     if (step == 0) return x;
//     return (x / step).floorToDouble() * step;
//   }

//   double _ceilTo(double x, double step) {
//     if (step == 0) return x;
//     return (x / step).ceilToDouble() * step;
//   }

//   /// Format tick values based on the interval scale so labels are clean and compact.
//   String _formatTick(double value, double interval) {
//     final absStep = interval.abs();
//     if (absStep >= 1000) {
//       return value.toStringAsFixed(0);
//     } else if (absStep >= 1) {
//       return value.toStringAsFixed(0);
//     } else if (absStep >= 0.1) {
//       return value.toStringAsFixed(1);
//     } else if (absStep >= 0.01) {
//       return value.toStringAsFixed(2);
//     } else if (absStep >= 0.001) {
//       return value.toStringAsFixed(3);
//     } else {
//       // fallback for very small steps
//       return value.toStringAsPrecision(4);
//     }
//   }
// }

// /// Detail page showing the interactive process graph.
// class ScenarioDetailPage extends StatelessWidget {
//   final String scenarioName;
//   final Map<String, dynamic>? scenariosMap;

//   const ScenarioDetailPage({
//     required this.scenarioName,
//     required this.scenariosMap,
//     Key? key,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     if (scenariosMap == null || scenariosMap!.containsKey(scenarioName) == false) {
//       return Scaffold(
//         appBar: AppBar(title: Text(scenarioName)),
//         body: const Center(child: Text('No graph data available')),
//       );
//     }

//     final data = scenariosMap![scenarioName] as Map<String, dynamic>;
//     final model = data['model'] as Map<String, dynamic>;
//     final procsJson = (model['processes'] as List).cast<Map<String, dynamic>>();
//     final flowsJson = (model['flows'] as List).cast<Map<String, dynamic>>();
//     final processes = procsJson.map((j) => ProcessNode.fromJson(j)).toList();

//     // compute canvas size
//     double maxX = 0, maxY = 0;
//     for (var n in processes) {
//       final sz = ProcessNodeWidget.sizeFor(n);
//       maxX = max(maxX, n.position.dx + sz.width);
//       maxY = max(maxY, n.position.dy + sz.height);
//     }
//     final canvasW = maxX + 40;
//     final canvasH = maxY + 40;

//     return Scaffold(
//       appBar: AppBar(title: Text(scenarioName)),
//       body: InteractiveViewer(
//         boundaryMargin: const EdgeInsets.all(32),
//         minScale: 0.5,
//         maxScale: 2.5,
//         child: SizedBox(
//           width: canvasW,
//           height: canvasH,
//           child: Stack(
//             children: [
//               CustomPaint(
//                 size: Size(canvasW, canvasH),
//                 painter: UndirectedConnectionPainter(
//                   processes,
//                   flowsJson,
//                   nodeHeightScale: const {},
//                 ),
//               ),
//               for (var node in processes)
//                 Positioned(
//                   left: node.position.dx,
//                   top: node.position.dy,
//                   child: ProcessNodeWidget(node: node),
//                 ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// /// Simple value class for axis definition
// class _Axis {
//   final double min;
//   final double max;
//   final double interval;
//   const _Axis({required this.min, required this.max, required this.interval});
// }

// import 'dart:io';
// import 'dart:math';

// import 'package:earlylca/lca/newhome/lca_models.dart';
// import 'package:earlylca/lca/newhome/lca_painters.dart';
// import 'package:earlylca/lca/newhome/lca_widgets.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:fl_chart/fl_chart.dart';
// import 'package:path_provider/path_provider.dart';

// import 'generate_pdf.dart';
// import 'home.dart';
// import 'dart:html' as html;

// /// Presents LCA results in a 2×3 grid of charts.
// /// If a chart would be too wide, it takes the whole row.
// class ResultsPage extends StatefulWidget {
//   final Map<String, dynamic> results;
//   final Map<String, dynamic>? scenariosMap;

//   const ResultsPage({
//     required this.results,
//     this.scenariosMap,
//     Key? key,
//   }) : super(key: key);

//   @override
//   _ResultsPageState createState() => _ResultsPageState();
// }

// class _ResultsPageState extends State<ResultsPage> {
//   late final List<String> _methodNames;
//   late final List<String> _scenarioNames;
//   late final Map<String, String> _bestPerMethod;

//   static const double _barWidth = 24.0;
//   static const double _groupSpace = 16.0;
//   static const double _leftMargin = 48.0;   // slightly wider to fit larger fonts
//   static const double _bottomMargin = 110.0; // taller to avoid x-label overlap

//   /// Ordered rules for guessing y-axis labels based on method names
//   static const List<MapEntry<String, String>> _yAxisLabelRules = [
//     // Climate change (GWP) ReCiPe 2016
//     MapEntry('climate change', 'kg CO₂ eq'),
//     MapEntry('global warming', 'kg CO₂ eq'),
//     MapEntry('GWP100', 'kg CO₂ eq'),
//     MapEntry('GWP 100a', 'kg CO₂ eq'),
//     MapEntry('GWP20', 'kg CO₂ eq'),
//     MapEntry('GWP 20a', 'kg CO₂ eq'),
//     MapEntry('GWP500', 'kg CO₂ eq'),
//     MapEntry('GWP1000', 'kg CO₂ eq'),

//     // Terrestrial acidification (TAP)
//     MapEntry('acidification: terrestrial', 'kg SO₂ eq'),
//     MapEntry('terrestrial acidification', 'kg SO₂ eq'),
//     MapEntry('TAP', 'kg SO₂ eq'),

//     // Photochemical oxidant formation
//     MapEntry('photochemical oxidant formation: human health', 'kg NMVOC eq'),
//     MapEntry('photochemical oxidant formation: terrestrial ecosystems', 'kg NMVOC eq'),
//     MapEntry('photochemical ozone formation', 'kg NMVOC eq'),
//     MapEntry('POFP', 'kg NMVOC eq'),
//     MapEntry('HOFP', 'kg NMVOC eq'),
//     MapEntry('EOFP', 'kg NMVOC eq'),

//     // Ecotoxicity
//     MapEntry('ecotoxicity: freshwater', 'kg 1,4-DCB eq'),
//     MapEntry('freshwater ecotoxicity', 'kg 1,4-DCB eq'),
//     MapEntry('FETP', 'kg 1,4-DCB eq'),
//     MapEntry('marine ecotoxicity', 'kg 1,4-DCB eq'),
//     MapEntry('METP', 'kg 1,4-DCB eq'),

//     // Human toxicity
//     MapEntry('human toxicity: cancer', 'kg 1,4-DCB eq'),
//     MapEntry('human toxicity: non-cancer', 'kg 1,4-DCB eq'),
//     MapEntry('human toxicity', 'kg 1,4-DCB eq'),
//     MapEntry('HTP', 'kg 1,4-DCB eq'),

//     // Eutrophication
//     MapEntry('freshwater eutrophication', 'kg P eq'),
//     MapEntry('FEP', 'kg P eq'),
//     MapEntry('marine eutrophication', 'kg N eq'),
//     MapEntry('MEP', 'kg N eq'),

//     // Ozone depletion
//     MapEntry('ozone depletion', 'kg CFC-11 eq'),
//     MapEntry('ODP', 'kg CFC-11 eq'),

//     // Misc ReCiPe midpoints
//     MapEntry('particulate matter formation', 'kg PM2.5 eq'),
//     MapEntry('PMFP', 'kg PM2.5 eq'),
//     MapEntry('ionising radiation', 'kBq Co-60 eq'),
//     MapEntry('IRP', 'kBq Co-60 eq'),
//     MapEntry('water consumption', 'm³ world eq deprived'),
//     MapEntry('WDP', 'm³ world eq deprived'),
//     MapEntry('fossil resource scarcity', 'kg oil eq'),
//     MapEntry('FDP', 'kg oil eq'),
//     MapEntry('mineral resource scarcity', 'kg Cu eq'),
//     MapEntry('MDP', 'kg Cu eq'),
//     MapEntry('land use', 'm²a crop eq'),
//     MapEntry('LDP', 'm²a crop eq'),
//   ];

//   @override
//   void initState() {
//     super.initState();

//     // 1. Gather names
//     _scenarioNames = widget.results.keys.toList();
//     final firstScores = (widget.results[_scenarioNames.first]!['result']
//             as Map<String, dynamic>)['scores'] as Map<String, dynamic>;
//     _methodNames = firstScores.keys.toList();

//     // 2. Compute best scenario per method
//     _bestPerMethod = {};
//     for (var method in _methodNames) {
//       var bestScore = double.infinity;
//       var bestName = _scenarioNames.first;
//       for (var scenario in _scenarioNames) {
//         final info = widget.results[scenario]! as Map<String, dynamic>;
//         if (info['success'] == true) {
//           final scmap = (info['result'] as Map<String, dynamic>)['scores']
//               as Map<String, dynamic>;
//           final val = (scmap[method] as num).toDouble();
//           if (val < bestScore) {
//             bestScore = val;
//             bestName = scenario;
//           }
//         }
//       }
//       _bestPerMethod[method] = bestName;
//     }
//   }

//   void _downloadPdf(Uint8List pdfData) {
//     final blob = html.Blob([pdfData], 'application/pdf');
//     final url = html.Url.createObjectUrlFromBlob(blob);
//     final anchor = html.document.createElement('a') as html.AnchorElement
//       ..href = url
//       ..style.display = 'none'
//       ..download = 'lca_results.pdf';
//     html.document.body!.append(anchor);
//     anchor.click();
//     anchor.remove();
//     html.Url.revokeObjectUrl(url);
//   }

//   String _guessYAxisLabel(String methodName) {
//     final nameLower = methodName.toLowerCase();
//     for (final entry in _yAxisLabelRules) {
//       if (nameLower.contains(entry.key.toLowerCase())) {
//         return entry.value;
//       }
//     }
//     return 'impact units'; // fallback
//   }

//   /// Pixel width the chart would naturally need without scaling.
//   double _naturalChartWidth(int n) {
//     if (n <= 0) return _leftMargin * 2;
//     return _leftMargin + n * _barWidth + max(0, n - 1) * _groupSpace + _leftMargin;
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('LCA Results by Method'),
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(8),
//         child: LayoutBuilder(
//           builder: (context, constraints) {
//             final n = _scenarioNames.length;
//             final natural = _naturalChartWidth(n);

//             // If a two-column card would be narrower than the natural width,
//             // use a single column so each chart takes the whole row.
//             final twoColCardWidth = (constraints.maxWidth - 8) / 2; // crossAxisSpacing = 8
//             final needsFullRow = natural > twoColCardWidth - 16; // allow small wiggle
//             final crossAxisCount = needsFullRow ? 1 : 2;

//             return GridView.builder(
//               itemCount: _methodNames.length,
//               gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
//                 crossAxisCount: crossAxisCount,
//                 mainAxisSpacing: 8,
//                 crossAxisSpacing: 8,
//                 childAspectRatio: 0.9,
//               ),
//               itemBuilder: (context, i) {
//                 final cardWidth =
//                     (constraints.maxWidth - (crossAxisCount - 1) * 8) / crossAxisCount;
//                 // inner content width inside the Card
//                 final innerWidth = max(0.0, cardWidth - 16); // subtract a bit for padding
//                 return _buildMethodCard(context, _methodNames[i], innerWidth);
//               },
//             );
//           },
//         ),
//       ),
//     );
//   }

//   Widget _buildMethodCard(BuildContext context, String method, double availableInnerWidth) {
//     // Collect scores for this method across all scenarios
//     final scores = _scenarioNames.map((scenario) {
//       final info = widget.results[scenario]! as Map<String, dynamic>;
//       if (info['success'] != true) return 0.0;
//       final scmap = (info['result'] as Map<String, dynamic>)['scores']
//           as Map<String, dynamic>;
//       return (scmap[method] as num).toDouble();
//     }).toList();

//     // Compute axis from actual min and max
//     final axis = _computeNiceAxis(scores, maxTicks: 6);
//     final bestScenario = _bestPerMethod[method]!;
//     final yLabel = _guessYAxisLabel(method);

//     // Work out the width we will give the chart.
//     // If we have room, stretch to fill the card. If not, use the natural width
//     // and allow horizontal scrolling.
//     final naturalWidth = _naturalChartWidth(_scenarioNames.length);
//     final chartWidth = max(naturalWidth, availableInnerWidth);

//     // Use this to decide how dense the x labels can be without overlapping.
//     final groupCount = _scenarioNames.length;
//     final extraSpace = max(0.0, chartWidth - naturalWidth);
//     final extraPerGap = groupCount > 1 ? extraSpace / (groupCount - 1) : 0.0;
//     final effectivePerGroup = _barWidth + _groupSpace + extraPerGap;
//     const neededPerLabel = 92.0; // rough rotated label footprint
//     final labelEvery = max(1, (neededPerLabel / max(1.0, effectivePerGroup)).ceil());

//     return GestureDetector(
//       onTap: () {
//         Navigator.push(
//           context,
//           MaterialPageRoute(
//             builder: (_) => ScenarioDetailPage(
//               scenarioName: bestScenario,
//               scenariosMap: widget.scenariosMap,
//             ),
//           ),
//         );
//       },
//       child: Card(
//         elevation: 2,
//         color: Colors.white,
//         child: Column(
//           children: [
//             Padding(
//               padding: const EdgeInsets.symmetric(vertical: 6),
//               child: Text(
//                 method,
//                 textAlign: TextAlign.center,
//                 style: Theme.of(context)
//                     .textTheme
//                     .bodyMedium
//                     ?.copyWith(fontWeight: FontWeight.bold, fontSize: 15),
//               ),
//             ),
//             Expanded(
//               child: SingleChildScrollView(
//                 scrollDirection: Axis.horizontal,
//                 padding: const EdgeInsets.only(bottom: 4),
//                 child: SizedBox(
//                   width: chartWidth,
//                   child: BarChart(
//                     BarChartData(
//                       backgroundColor: Colors.white,
//                       minY: axis.min,
//                       maxY: axis.max,
//                       gridData: FlGridData(
//                         show: true,
//                         drawVerticalLine: false,
//                         horizontalInterval: axis.interval,
//                         getDrawingHorizontalLine: (_) => FlLine(
//                           color: Colors.grey.shade300,
//                           strokeWidth: 1,
//                         ),
//                       ),
//                       titlesData: FlTitlesData(
//                         leftTitles: AxisTitles(
//                           axisNameWidget: Padding(
//                             padding: const EdgeInsets.only(bottom: 0),
//                             child: Text(
//                               yLabel,
//                               style: const TextStyle(
//                                 fontSize: 13,
//                                 fontWeight: FontWeight.w600,
//                               ),
//                             ),
//                           ),
//                           sideTitles: SideTitles(
//                             showTitles: true,
//                             interval: axis.interval,
//                             reservedSize: _leftMargin,
//                             getTitlesWidget: (val, _) => Text(
//                               _formatTick(val, axis.interval),
//                               style: const TextStyle(fontSize: 11),
//                             ),
//                           ),
//                         ),
//                         bottomTitles: AxisTitles(
//                           axisNameWidget: const SizedBox(),
//                           sideTitles: SideTitles(
//                             showTitles: true,
//                             reservedSize: _bottomMargin,
//                             getTitlesWidget: (val, meta) {
//                               final idx = val.toInt();
//                               if (idx < 0 || idx >= _scenarioNames.length) {
//                                 return const SizedBox();
//                               }
//                               // Skip labels to avoid overlap
//                               if (idx % labelEvery != 0) {
//                                 return const SizedBox.shrink();
//                               }
//                               return SideTitleWidget(
//                                 axisSide: meta.axisSide,
//                                 space: 14, // extra gap so labels do not touch the chart
//                                 child: Transform.rotate(
//                                   angle: -pi / 4, // -45° reads better and reduces overlap
//                                   child: SizedBox(
//                                     width: 92,
//                                     child: Text(
//                                       _scenarioNames[idx],
//                                       style: const TextStyle(fontSize: 12),
//                                       overflow: TextOverflow.ellipsis,
//                                       softWrap: false,
//                                       maxLines: 1,
//                                     ),
//                                   ),
//                                 ),
//                               );
//                             },
//                           ),
//                         ),
//                         topTitles: const AxisTitles(
//                           sideTitles: SideTitles(showTitles: false),
//                         ),
//                         rightTitles: const AxisTitles(
//                           sideTitles: SideTitles(showTitles: false),
//                         ),
//                       ),
//                       barGroups: List.generate(
//                         _scenarioNames.length,
//                         (i) {
//                           final name = _scenarioNames[i];
//                           final y = scores[i];
//                           final isBest = name == bestScenario;
//                           return BarChartGroupData(
//                             x: i,
//                             barsSpace: 0,
//                             barRods: [
//                               BarChartRodData(
//                                 toY: y,
//                                 width: _barWidth,
//                                 borderRadius: BorderRadius.circular(4),
//                                 color: isBest ? Colors.green : Colors.black,
//                               ),
//                             ],
//                           );
//                         },
//                       ),
//                       groupsSpace: _groupSpace,
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   /// Compute a nice axis that respects data min and max, supports negatives,
//   /// constant series, and tiny ranges. Returns min, max, interval.
//   _Axis _computeNiceAxis(List<double> values, {int maxTicks = 6}) {
//     if (values.isEmpty) {
//       return const _Axis(min: 0, max: 1, interval: 0.2);
//     }

//     double vMin = values.reduce(min);
//     double vMax = values.reduce(max);

//     // Handle all-equal case
//     if (vMin == vMax) {
//       final zero = vMin == 0.0;
//       final padding = zero ? 1.0 : vMin.abs() * 0.2 + 1e-9;
//       final minY = vMin - padding;
//       final maxY = vMax + padding;
//       final interval = _niceStep((maxY - minY) / (maxTicks - 1));
//       final niceMin = _floorTo(minY, interval);
//       final niceMax = _ceilTo(maxY, interval);
//       return _Axis(min: niceMin, max: niceMax, interval: interval);
//     }

//     // Add a bit of headroom and footroom
//     final range = vMax - vMin;
//     final pad = range * 0.08;
//     double rawMin = vMin - pad;
//     double rawMax = vMax + pad;

//     // If the data straddles zero, include zero nicely
//     if (vMin < 0 && vMax > 0) {
//       rawMin = min(rawMin, 0);
//       rawMax = max(rawMax, 0);
//     }

//     // Compute a nice interval
//     final roughStep = (rawMax - rawMin) / max(maxTicks - 1, 1);
//     final step = _niceStep(roughStep);

//     // Snap bounds to the step
//     final niceMin = _floorTo(rawMin, step);
//     final niceMax = _ceilTo(rawMax, step);

//     // Avoid degenerate interval
//     final interval = step <= 0 ? (niceMax - niceMin) / max(maxTicks - 1, 1) : step;

//     return _Axis(min: niceMin, max: niceMax, interval: interval);
//   }

//   /// Return a "nice" step size like 1, 2, 2.5, 5, 10, 20, etc.
//   double _niceStep(double raw) {
//     if (!raw.isFinite || raw == 0) return 1.0;
//     final sign = raw.sign;
//     final x = raw.abs();

//     final exp10 = pow(10, (log(x) / ln10).floor()).toDouble();
//     final f = x / exp10;

//     double nf;
//     if (f < 1.5)      nf = 1;
//     else if (f < 2.3) nf = 2;
//     else if (f < 3.5) nf = 2.5;
//     else if (f < 7)   nf = 5;
//     else              nf = 10;

//     return sign * nf * exp10;
//   }

//   double _floorTo(double x, double step) {
//     if (step == 0) return x;
//     return (x / step).floorToDouble() * step;
//   }

//   double _ceilTo(double x, double step) {
//     if (step == 0) return x;
//     return (x / step).ceilToDouble() * step;
//   }

//   /// Format tick values based on the interval scale so labels are clean and compact.
//   String _formatTick(double value, double interval) {
//     final absStep = interval.abs();
//     if (absStep >= 1000) {
//       return value.toStringAsFixed(0);
//     } else if (absStep >= 1) {
//       return value.toStringAsFixed(0);
//     } else if (absStep >= 0.1) {
//       return value.toStringAsFixed(1);
//     } else if (absStep >= 0.01) {
//       return value.toStringAsFixed(2);
//     } else if (absStep >= 0.001) {
//       return value.toStringAsFixed(3);
//     } else {
//       // fallback for very small steps
//       return value.toStringAsPrecision(4);
//     }
//   }
// }

// /// Detail page showing the interactive process graph.
// class ScenarioDetailPage extends StatelessWidget {
//   final String scenarioName;
//   final Map<String, dynamic>? scenariosMap;

//   const ScenarioDetailPage({
//     required this.scenarioName,
//     required this.scenariosMap,
//     Key? key,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     if (scenariosMap == null || scenariosMap!.containsKey(scenarioName) == false) {
//       return Scaffold(
//         appBar: AppBar(title: Text(scenarioName)),
//         body: const Center(child: Text('No graph data available')),
//       );
//     }

//     final data = scenariosMap![scenarioName] as Map<String, dynamic>;
//     final model = data['model'] as Map<String, dynamic>;
//     final procsJson = (model['processes'] as List).cast<Map<String, dynamic>>();
//     final flowsJson = (model['flows'] as List).cast<Map<String, dynamic>>();
//     final processes = procsJson.map((j) => ProcessNode.fromJson(j)).toList();

//     // compute canvas size
//     double maxX = 0, maxY = 0;
//     for (var n in processes) {
//       final sz = ProcessNodeWidget.sizeFor(n);
//       maxX = max(maxX, n.position.dx + sz.width);
//       maxY = max(maxY, n.position.dy + sz.height);
//     }
//     final canvasW = maxX + 40;
//     final canvasH = maxY + 40;

//     return Scaffold(
//       appBar: AppBar(title: Text(scenarioName)),
//       body: InteractiveViewer(
//         boundaryMargin: const EdgeInsets.all(32),
//         minScale: 0.5,
//         maxScale: 2.5,
//         child: SizedBox(
//           width: canvasW,
//           height: canvasH,
//           child: Stack(
//             children: [
//               CustomPaint(
//                 size: Size(canvasW, canvasH),
//                 painter: UndirectedConnectionPainter(
//                   processes,
//                   flowsJson,
//                   nodeHeightScale: const {},
//                 ),
//               ),
//               for (var node in processes)
//                 Positioned(
//                   left: node.position.dx,
//                   top: node.position.dy,
//                   child: ProcessNodeWidget(node: node),
//                 ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// /// Simple value class for axis definition
// class _Axis {
//   final double min;
//   final double max;
//   final double interval;
//   const _Axis({required this.min, required this.max, required this.interval});
// }


// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:earlylca/lca/newhome/lca_models.dart';
import 'package:earlylca/lca/newhome/lca_painters.dart';
import 'package:earlylca/lca/newhome/lca_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:earlylca/lca/newllm/pdf_download.dart';
import 'package:earlylca/lca/newllm/report_exporter.dart';

/// ResultsPage can render either:
///  - Tornado sensitivity plots when scenarios look like one-at-a-time parameter changes,
///    or when functionsUsed contains "oneAtATimeSensitivity".
///  - Otherwise, a 2×3 grid of bar charts (one card per LCIA method).
///
/// Sensitivity detection does not rely on scenario names. It inspects per-scenario
/// ParameterSet differences against the baseline to find single-parameter changes.
/// Baseline is detected by name if possible, else by a simple heuristic.
class ResultsPage extends StatefulWidget {
  final Map<String, dynamic> results;
  final Map<String, dynamic>? scenariosMap;
  final List<String>? functionsUsed; // optional hint from caller
  final String? prompt;
  final Map<String, List<Map<String, dynamic>>>? rawDeltasByScenario;
  final String? productSystemName;
  final String? impactMethodName;

  const ResultsPage({
    required this.results,
    this.scenariosMap,
    this.functionsUsed,
    this.prompt,
    this.rawDeltasByScenario,
    this.productSystemName,
    this.impactMethodName,
    Key? key,
  }) : super(key: key);

  @override
  _ResultsPageState createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  // Common
  late final List<String> _scenarioNames;
  late final List<String> _methodNames;

  // Tornado UI state
  final PageController _methodPager = PageController();
  int _methodIndex = 0;

  // Bar grid helpers
  late final Map<String, String> _bestPerMethod;
  late final Map<String, String> _unitsByMethod;

  // Decide which UI to show
  late final bool _useTornado;
  bool _isExportingPdf = false;
  final Map<String, GlobalKey> _methodChartBoundaryKeys = {};

  // ----- Axis helpers for bar charts -----
  static const double _barWidth = 24.0;
  static const double _leftMargin = 48.0;
  static const double _bottomMargin = 92.0;

  static const List<MapEntry<String, String>> _yAxisLabelRules = [
    // Climate / GWP families
    MapEntry('climate change', 'kg CO₂ eq'),
    MapEntry('global warming potential', 'kg CO₂ eq'),
    MapEntry('global warming', 'kg CO₂ eq'),
    MapEntry('gwp100', 'kg CO₂ eq'),
    MapEntry('gwp 100a', 'kg CO₂ eq'),
    MapEntry('gwp20', 'kg CO₂ eq'),
    MapEntry('gwp 20a', 'kg CO₂ eq'),
    MapEntry('gwp500', 'kg CO₂ eq'),
    MapEntry('gwp1000', 'kg CO₂ eq'),
    // Acidification
    MapEntry('acidification', 'mol H+ eq'),
    MapEntry('acidification: terrestrial', 'kg SO₂ eq'),
    MapEntry('terrestrial acidification', 'kg SO₂ eq'),
    MapEntry('tap', 'kg SO₂ eq'),
    // Photochemical ozone
    MapEntry('photochemical oxidant formation: human health', 'kg NMVOC eq'),
    MapEntry('photochemical oxidant formation: terrestrial ecosystems', 'kg NMVOC eq'),
    MapEntry('photochemical ozone formation', 'kg NMVOC eq'),
    MapEntry('ozone formation, human health', 'kg NMVOC eq'),
    MapEntry('ozone formation, terrestrial ecosystems', 'kg NMVOC eq'),
    MapEntry('pofp', 'kg NMVOC eq'),
    MapEntry('hofp', 'kg NMVOC eq'),
    MapEntry('eofp', 'kg NMVOC eq'),
    // Toxicity / ecotoxicity
    MapEntry('ecotoxicity, freshwater', 'CTUe'),
    MapEntry('ecotoxicity: freshwater', 'kg 1,4-DCB eq'),
    MapEntry('freshwater ecotoxicity', 'kg 1,4-DCB eq'),
    MapEntry('fetp', 'kg 1,4-DCB eq'),
    MapEntry('marine ecotoxicity', 'kg 1,4-DCB eq'),
    MapEntry('metp', 'kg 1,4-DCB eq'),
    MapEntry('human toxicity, cancer effects', 'CTUh'),
    MapEntry('human toxicity, non-cancer effects', 'CTUh'),
    MapEntry('human toxicity potential', 'CTUh'),
    MapEntry('human toxicity: cancer', 'kg 1,4-DCB eq'),
    MapEntry('human toxicity: non-cancer', 'kg 1,4-DCB eq'),
    MapEntry('human toxicity', 'kg 1,4-DCB eq'),
    MapEntry('htp', 'kg 1,4-DCB eq'),
    // Eutrophication
    MapEntry('freshwater eutrophication', 'kg P eq'),
    MapEntry('fep', 'kg P eq'),
    MapEntry('marine eutrophication', 'kg N eq'),
    MapEntry('mep', 'kg N eq'),
    MapEntry('terrestrial eutrophication', 'mol N eq'),
    // Ozone depletion
    MapEntry('ozone depletion', 'kg CFC-11 eq'),
    MapEntry('odp', 'kg CFC-11 eq'),
    // PM / ionizing radiation
    MapEntry('particulate matter formation', 'kg PM2.5 eq'),
    MapEntry('particulate matter', 'disease incidence'),
    MapEntry('pmfp', 'kg PM2.5 eq'),
    MapEntry('ionising radiation', 'kBq Co-60 eq'),
    MapEntry('ionizing radiation', 'kBq Co-60 eq'),
    MapEntry('irp', 'kBq Co-60 eq'),
    // Water / resources / land
    MapEntry('water use', 'm³ world eq deprived'),
    MapEntry('water consumption', 'm³ world eq deprived'),
    MapEntry('wdp', 'm³ world eq deprived'),
    MapEntry('resource use, fossils', 'MJ'),
    MapEntry('fossil resource use', 'MJ'),
    MapEntry('fossil resource scarcity', 'kg oil eq'),
    MapEntry('fdp', 'kg oil eq'),
    MapEntry('resource use, minerals and metals', 'kg Sb eq'),
    MapEntry('mineral resource scarcity', 'kg Cu eq'),
    MapEntry('mdp', 'kg Cu eq'),
    MapEntry('land occupation', 'm²a crop eq'),
    MapEntry('land use', 'm²a crop eq'),
    MapEntry('ldp', 'm²a crop eq'),
    // Endpoint/single score catch-alls
    MapEntry('single score', 'Pt'),
    MapEntry('total score', 'Pt'),
  ];

  @override
  void initState() {
    super.initState();

    _scenarioNames = widget.results.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final methodSet = <String>{};
    for (final scenario in _scenarioNames) {
      final payload = widget.results[scenario];
      if (payload is! Map) continue;
      final result = payload['result'];
      if (result is! Map) continue;
      final scores = result['scores'];
      if (scores is! Map) continue;
      for (final method in scores.keys) {
        final name = method.toString().trim();
        if (name.isNotEmpty) methodSet.add(name);
      }
    }
    _methodNames = methodSet.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _unitsByMethod = _collectUnitsByMethod();

    _bestPerMethod = {};
    for (final method in _methodNames) {
      double? bestScore;
      String? bestName;
      for (final scenario in _scenarioNames) {
        final info = widget.results[scenario]! as Map<String, dynamic>;
        if (info['success'] == true) {
          final result = info['result'];
          if (result is! Map) continue;
          final scmap = result['scores'];
          if (scmap is! Map) continue;
          final raw = scmap[method];
          if (raw is! num) continue;
          final val = raw.toDouble();
          if (bestScore == null || val < bestScore) {
            bestScore = val;
            bestName = scenario;
          }
        }
      }
      if (bestName == null && _scenarioNames.isNotEmpty) {
        bestName = _scenarioNames.first;
      }
      if (bestName != null) {
        _bestPerMethod[method] = bestName;
      }
    }

    _useTornado = _decideUseTornado();
  }

  @override
  void dispose() {
    _methodPager.dispose();
    super.dispose();
  }

  bool _decideUseTornado() {
    // 1) Respect explicit hint if provided
    final fu = widget.functionsUsed;
    if (fu != null &&
        fu.any((e) => e.toLowerCase().contains('oneatatimesensitivity'))) {
      return true;
    }
    // 2) Infer from parameters if scenariosMap is available
    return _looksLikeOneAtATimeFromParams();
  }

  bool _looksLikeOneAtATimeFromParams() {
    final sm = widget.scenariosMap;
    if (sm == null || sm.isEmpty) return false;

    final baselineName = _detectBaselineName(_scenarioNames);
    final base = sm[baselineName];
    if (base == null) return false;

    final _ParamSnapshot baseSnap = _snapshotParams(base);

    int countSingleChange = 0;
    int considered = 0;

    for (final s in _scenarioNames) {
      if (s == baselineName) continue;
      final entry = sm[s];
      if (entry == null) continue;

      final snap = _snapshotParams(entry);
      final diff = _diffParams(baseSnap, snap);

      // Count exactly one changed variable (parameter or FU)
      if (diff.changedKeys.length == 1) countSingleChange++;
      considered++;
    }

    if (considered == 0) return false;
    // Heuristic: at least two scenarios with single-parameter changes
    return countSingleChange >= 2;
  }

  // ----- Build -----
  @override
  Widget build(BuildContext context) {
    final hasMethods = _methodNames.isNotEmpty;
    final title = _useTornado && hasMethods
        ? 'LCA Results by Method (${_methodIndex + 1}/${_methodNames.length})'
        : 'LCA Results by Method';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: _isExportingPdf ? null : _onExportPdfPressed,
            tooltip: _isExportingPdf ? 'Exporting PDF...' : 'Export PDF',
            icon: _isExportingPdf
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf),
          ),
        ],
      ),
      body: hasMethods
          ? (_useTornado ? _buildTornadoBody() : _buildBarGridBody())
          : const Center(
              child: Text(
                'No impact categories were returned. '
                'Run LCA again with at least one successful scenario.',
                textAlign: TextAlign.center,
              ),
            ),
    );
  }

  Future<void> _onExportPdfPressed() async {
    if (_isExportingPdf) return;
    setState(() => _isExportingPdf = true);
    try {
      final methodChartImages = await _captureMethodCharts();
      final promptText = (widget.prompt ?? '').trim();

      final pdfBytes = await ReportExporter.buildPdf(
        prompt: promptText.isEmpty
            ? 'Prompt unavailable (exported from LCA results tab).'
            : promptText,
        functionsUsed: widget.functionsUsed ?? const [],
        rawDeltasByScenario: widget.rawDeltasByScenario ?? const {},
        graphPngByScenario: const {},
        resultGraphPngByMethod: methodChartImages,
        lcaResults: widget.results,
        productSystemName: widget.productSystemName,
        impactMethodName: widget.impactMethodName,
      );

      await downloadPdf(
        bytes: pdfBytes,
        filename: 'lca_results_by_method_report.pdf',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'PDF exported as lca_results_by_method_report.pdf '
            '(${methodChartImages.length} graph snapshot(s)).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF export failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      }
    }
  }

  Future<Map<String, Uint8List>> _captureMethodCharts() async {
    if (_methodChartBoundaryKeys.isEmpty) {
      return const <String, Uint8List>{};
    }
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 70));

    final out = <String, Uint8List>{};
    final entries = _methodChartBoundaryKeys.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    for (final entry in entries) {
      final boundary = entry.value.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) continue;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        out[entry.key] = byteData.buffer.asUint8List();
      }
    }
    return out;
  }

  // ===================== TORNADO BODY =====================
  Widget _buildTornadoBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _methodPager,
                onPageChanged: (i) => setState(() => _methodIndex = i),
                itemCount: _methodNames.length,
                itemBuilder: (context, mi) {
                  final method = _methodNames[mi];
                  return Padding(
                    padding: const EdgeInsets.all(8),
                    child: _buildMethodTornado(
                      methodIndex: mi,
                      methodName: method,
                      maxHeight: constraints.maxHeight - 16,
                      maxWidth: constraints.maxWidth - 16,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            _Dots(count: _methodNames.length, index: _methodIndex),
            const SizedBox(height: 6),
          ],
        );
      },
    );
  }

  Widget _buildMethodTornado({
    required int methodIndex,
    required String methodName,
    required double maxWidth,
    required double maxHeight,
  }) {
    // scenario -> score for this method
    final Map<String, double> scoresByScenario = {};
    for (final s in _scenarioNames) {
      final info = widget.results[s]! as Map<String, dynamic>;
      if (info['success'] == true) {
        final scmap =
            (info['result'] as Map<String, dynamic>)['scores'] as Map<String, dynamic>;
        final val = scmap[methodName];
        if (val is num) {
          scoresByScenario[s] = val.toDouble();
        }
      }
    }

    // detect a global baseline name
    final baselineName = _detectBaselineName(scoresByScenario.keys.toList());
    final globalBaseline = scoresByScenario[baselineName];
    if (globalBaseline == null) {
      return _errorCard(
        'Could not detect a baseline scenario for "$methodName". '
        'Include a scenario named "baseline", "base", "reference" or one without a percent.',
      );
    }

    // Build complete list with parameter-aware pairing and mirroring.
    final pairOut = _buildCompleteSensitivity(
      scoresByScenario,
      baselineName,
      globalBaseline,
      preferredPct: 10.0,
    );

    if (pairOut.items.isEmpty) {
      return _errorCard('No sensitivity scenarios detected for "$methodName".');
    }

    pairOut.items.sort((a, b) => b.maxAbsDelta.compareTo(a.maxAbsDelta));

    final maxAbs = pairOut.items
        .expand((e) => [e.negDelta.abs(), e.posDelta.abs()])
        .fold<double>(0, (m, v) => max(m, v));
    final nice = _niceExtent(maxAbs * 1.08);

    return Card(
      elevation: 2,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: _OnePageTornado(
          methodName: methodName,
          baselineNote: pairOut.usesPerVarBaseline
              ? 'Baseline per variable: 0% scenarios'
              : 'Baseline: ${globalBaseline.toStringAsFixed(4)}',
          items: pairOut.items,
          xExtent: nice,
          stats: pairOut.stats,
        ),
      ),
    );
  }

  // Parse and pair scenarios using parameters first, then names as fallback.
  _PairResult _buildCompleteSensitivity(
    Map<String, double> scoresByScenario,
    String globalBaselineName,
    double globalBaseline, {
    double preferredPct = 10.0,
  }) {
    // ---------- 1) Try parameter-based scan ----------
    final paramScan = _scanParamBasedSensitivity(
      scoresByScenario: scoresByScenario,
      baselineName: globalBaselineName,
      preferredPct: preferredPct,
    );

    if (paramScan.items.isNotEmpty) {
      return paramScan;
    }

    // ---------- 2) Fallback to name parsing ----------
    // normalise: replace Unicode dashes with '-', collapse spaces
    String normalise(String s) {
      final replaced = s
          .replaceAll('−', '-')
          .replaceAll('–', '-')
          .replaceAll('—', '-')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return replaced;
    }

    // regex after normalisation: optional sign, number, percent, variable
    final reg = RegExp(
      r'^\s*([+\-])?\s*(\d+(?:\.\d+)?)%\s*(?:of\s+)?(.+?)\s*$',
      caseSensitive: false,
    );

    String canonVar(String s) => s.toLowerCase().trim();

    // per variable: signed percent -> score
    final Map<String, Map<double, double>> varScores = {};
    // variable-specific 0% baselines
    final Map<String, double> varZero = {};
    bool sawAnyZero = false;

    scoresByScenario.forEach((rawName, score) {
      final name = normalise(rawName);
      final m = reg.firstMatch(name);
      if (m == null) return;

      final sign = (m.group(1) ?? '+').trim();
      final pct = double.tryParse(m.group(2)!) ?? 0.0;
      final varRaw = m.group(3)!.trim();
      final key = canonVar(varRaw);

      final signedPct = sign == '-' ? -pct : pct;

      final map = varScores.putIfAbsent(key, () => {});
      map[signedPct] = score;

      if (signedPct == 0.0) {
        varZero[key] = score;
        sawAnyZero = true;
      }
    });

    final Set<String> allVars = varScores.keys.toSet();

    final List<_SensItem> items = [];
    int realPairs = 0;
    int mirroredSides = 0;
    int scaledPairs = 0;
    int asymmetryFlags = 0;

    const double asymThresh = 0.15; // 15%

    for (final vKey in allVars) {
      final entries = varScores[vKey]!;
      final hasPos10 = entries.containsKey(preferredPct);
      final hasNeg10 = entries.containsKey(-preferredPct);

      final varBaseline = varZero[vKey] ?? globalBaseline;

      double posDelta, negDelta;
      double posPctUsed = preferredPct, negPctUsed = preferredPct;
      bool posMir = false, negMir = false;

      double deltaAt(double signedPct) => entries[signedPct]! - varBaseline;

      if (hasPos10 && hasNeg10) {
        posDelta = deltaAt(preferredPct);
        negDelta = deltaAt(-preferredPct);
        realPairs += 1;
      } else {
        double? closest(List<double> pcts, double targetAbs) {
          if (pcts.isEmpty) return null;
          double best = pcts.first;
          for (final p in pcts) {
            if ((p.abs() - targetAbs).abs() < (best.abs() - targetAbs).abs()) {
              best = p;
            }
          }
          return best;
        }

        final posPcts = entries.keys.where((p) => p > 0).toList();
        final negPcts = entries.keys.where((p) => p < 0).toList();
        final havePos = closest(posPcts, preferredPct);
        final haveNeg = closest(negPcts, preferredPct);

        if (havePos != null) {
          final d = entries[havePos]! - varBaseline;
          final slope = d / havePos; // units per 1%
          posDelta = slope * preferredPct;
          posPctUsed = preferredPct;
          if ((havePos.abs() - preferredPct).abs() > 1e-9) scaledPairs += 1;
        } else if (haveNeg != null) {
          final useNeg = haveNeg;
          final d = entries[useNeg]! - varBaseline;
          final slope = d / useNeg; // negative percent
          posDelta = slope * preferredPct;
          posMir = true;
          mirroredSides += 1;
        } else {
          // No data on either side, skip variable
          continue;
        }

        if (haveNeg != null) {
          final d = entries[haveNeg]! - varBaseline;
          final slope = d / haveNeg;
          negDelta = slope * (-preferredPct);
          negPctUsed = preferredPct;
          if ((haveNeg.abs() - preferredPct).abs() > 1e-9) scaledPairs += 1;
        } else if (havePos != null) {
          final usePos = havePos;
          final d = entries[usePos]! - varBaseline;
          final slope = d / usePos;
          negDelta = slope * (-preferredPct);
          negMir = true;
          mirroredSides += 1;
        } else {
          continue;
        }
      }

      bool asymFlag = false;
      if (hasPos10 && hasNeg10) {
        final sp = (entries[preferredPct]! - varBaseline).abs() / preferredPct;
        final sn = (entries[-preferredPct]! - varBaseline).abs() / preferredPct;
        final smax = max(sp, sn);
        if (smax > 0) {
          final asym = (sp - sn).abs() / smax;
          if (asym > asymThresh) {
            asymFlag = true;
            asymmetryFlags += 1;
          }
        }
      }

      items.add(
        _SensItem(_titleCase(vKey))
          ..posDelta = posDelta
          ..negDelta = negDelta
          ..posPct = posPctUsed
          ..negPct = negPctUsed
          ..posMirrored = posMir
          ..negMirrored = negMir
          ..flagAsymmetric = asymFlag,
      );
    }

    final stats = _SensStats(
      total: items.length,
      realPairs: realPairs,
      mirroredSides: mirroredSides,
      scaledPairs: scaledPairs,
      asymmetryFlags: asymmetryFlags,
    );

    return _PairResult(
      items: items,
      stats: stats,
      usesPerVarBaseline: false,
    );
  }

  // Parameter-aware scanner that does not rely on scenario names.
  _PairResult _scanParamBasedSensitivity({
    required Map<String, double> scoresByScenario,
    required String baselineName,
    required double preferredPct,
  }) {
    final sm = widget.scenariosMap;
    if (sm == null || sm.isEmpty) {
      return _PairResult(items: [], stats: _emptyStats(), usesPerVarBaseline: false);
    }
    final baseEntry = sm[baselineName];
    if (baseEntry == null) {
      return _PairResult(items: [], stats: _emptyStats(), usesPerVarBaseline: false);
    }

    final baseSnap = _snapshotParams(baseEntry);
    final procNames = _processIdToName(baseEntry);

    // Build: variable label -> { signedPct -> scenario score }
    final Map<String, Map<double, double>> varScores = {};

    for (final s in scoresByScenario.keys) {
      final entry = sm[s];
      if (entry == null) continue;
      final snap = _snapshotParams(entry);
      final dif = _diffParams(baseSnap, snap);

      if (dif.changedKeys.length != 1) continue;

      final changed = dif.changedKeys.first;
      final ch = dif.changes[changed]!;

      // Label construction
      String label;
      if (changed.startsWith('g::')) {
        final pname = changed.substring(3);
        label = _titleCase(pname);
      } else if (changed.startsWith('p::')) {
        final rest = changed.substring(3); // pid::param
        final idx = rest.indexOf('::');
        final pid = idx >= 0 ? rest.substring(0, idx) : rest;
        final pname = idx >= 0 ? rest.substring(idx + 2) : '';
        final niceProc = procNames[pid] ?? pid;
        label = '${_titleCase(pname)}: $niceProc';
      } else if (changed == 'fu') {
        label = 'Functional units';
      } else {
        label = changed;
      }

      // Compute signed percent if possible
      final oldVal = ch.oldValue;
      final newVal = ch.newValue;
      double signedPct;
      if (changed == 'fu') {
        if (oldVal == null || newVal == null || oldVal == 0) {
          signedPct = (newVal ?? 0) >= (oldVal ?? 0) ? preferredPct : -preferredPct;
        } else {
          signedPct = ((newVal - oldVal) / oldVal) * 100.0;
        }
      } else {
        if (oldVal == null || newVal == null || oldVal == 0) {
          // Fall back to preferred magnitude if old is zero or missing
          signedPct = (newVal ?? 0) >= (oldVal ?? 0) ? preferredPct : -preferredPct;
        } else {
          signedPct = ((newVal - oldVal) / oldVal) * 100.0;
        }
      }

      final m = varScores.putIfAbsent(label.toLowerCase(), () => {});
      m[signedPct] = scoresByScenario[s]!;
    }

    if (varScores.isEmpty) {
      return _PairResult(items: [], stats: _emptyStats(), usesPerVarBaseline: false);
    }

    // Pairing, scaling to preferredPct, mirroring if needed
    final List<_SensItem> items = [];
    int realPairs = 0;
    int mirroredSides = 0;
    int scaledPairs = 0;
    int asymmetryFlags = 0;

    const double asymThresh = 0.15; // 15%

    for (final vKey in varScores.keys) {
      final entries = varScores[vKey]!;
      // Each variable uses the global baseline score
      final varBaseline = scoresByScenario[baselineName]!;

      // Do we have both sides at preferredPct already
      final hasPos10 = entries.containsKey(preferredPct);
      final hasNeg10 = entries.containsKey(-preferredPct);

      double posDelta, negDelta;
      double posPctUsed = preferredPct, negPctUsed = preferredPct;
      bool posMir = false, negMir = false;

      double deltaAtPct(double signedPct) => entries[signedPct]! - varBaseline;

      if (hasPos10 && hasNeg10) {
        posDelta = deltaAtPct(preferredPct);
        negDelta = deltaAtPct(-preferredPct);
        realPairs += 1;
      } else {
        // choose closest available percent on each side
        double? closest(List<double> pcts, double targetAbs) {
          if (pcts.isEmpty) return null;
          double best = pcts.first;
          for (final p in pcts) {
            if ((p.abs() - targetAbs).abs() < (best.abs() - targetAbs).abs()) {
              best = p;
            }
          }
          return best;
        }

        final posPcts = entries.keys.where((p) => p > 0).toList();
        final negPcts = entries.keys.where((p) => p < 0).toList();
        final havePos = closest(posPcts, preferredPct);
        final haveNeg = closest(negPcts, preferredPct);

        if (havePos != null) {
          final d = entries[havePos]! - varBaseline;
          final slope = d / havePos; // units per 1%
          posDelta = slope * preferredPct;
          posPctUsed = preferredPct;
          if ((havePos.abs() - preferredPct).abs() > 1e-9) scaledPairs += 1;
        } else if (haveNeg != null) {
          final useNeg = haveNeg;
          final d = entries[useNeg]! - varBaseline;
          final slope = d / useNeg;
          posDelta = slope * preferredPct;
          posMir = true;
          mirroredSides += 1;
        } else {
          // No observations
          continue;
        }

        if (haveNeg != null) {
          final d = entries[haveNeg]! - varBaseline;
          final slope = d / haveNeg;
          negDelta = slope * (-preferredPct);
          negPctUsed = preferredPct;
          if ((haveNeg.abs() - preferredPct).abs() > 1e-9) scaledPairs += 1;
        } else if (havePos != null) {
          final usePos = havePos;
          final d = entries[usePos]! - varBaseline;
          final slope = d / usePos;
          negDelta = slope * (-preferredPct);
          negMir = true;
          mirroredSides += 1;
        } else {
          continue;
        }
      }

      bool asymFlag = false;
      if (hasPos10 && hasNeg10) {
        final sp = (entries[preferredPct]! - varBaseline).abs() / preferredPct;
        final sn = (entries[-preferredPct]! - varBaseline).abs() / preferredPct;
        final smax = max(sp, sn);
        if (smax > 0) {
          final asym = (sp - sn).abs() / smax;
          if (asym > asymThresh) {
            asymFlag = true;
            asymmetryFlags += 1;
          }
        }
      }

      items.add(
        _SensItem(_titleCaseFromKey(vKey))
          ..posDelta = posDelta
          ..negDelta = negDelta
          ..posPct = posPctUsed
          ..negPct = negPctUsed
          ..posMirrored = posMir
          ..negMirrored = negMir
          ..flagAsymmetric = asymFlag,
      );
    }

    final stats = _SensStats(
      total: items.length,
      realPairs: realPairs,
      mirroredSides: mirroredSides,
      scaledPairs: scaledPairs,
      asymmetryFlags: asymmetryFlags,
    );

    return _PairResult(
      items: items,
      stats: stats,
      usesPerVarBaseline: false,
    );
  }

  _SensStats _emptyStats() =>
      _SensStats(total: 0, realPairs: 0, mirroredSides: 0, scaledPairs: 0, asymmetryFlags: 0);

  // ===================== BAR GRID BODY =====================
  Widget _buildBarGridBody() {
    if (_methodNames.isEmpty) {
      return const Center(child: Text('No impact categories to display.'));
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        itemCount: _methodNames.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.9,
        ),
        itemBuilder: (context, i) => _buildMethodCard(context, _methodNames[i]),
      ),
    );
  }

  Widget _buildMethodCard(BuildContext context, String method) {
    // Collect scores for this method across all scenarios
    final scores = _scenarioNames.map((scenario) {
      final info = widget.results[scenario]! as Map<String, dynamic>;
      if (info['success'] != true) return 0.0;
      final result = info['result'];
      if (result is! Map) return 0.0;
      final scmap = result['scores'];
      if (scmap is! Map) return 0.0;
      final value = scmap[method];
      if (value is! num) return 0.0;
      return value.toDouble();
    }).toList();

    // Compute axis from actual min and max
    final axis = _computeNiceAxis(scores, maxTicks: 6);
    final bestScenario = _bestPerMethod[method] ?? '';
    final yLabel = _guessYAxisLabel(method);
    final chartBoundaryKey =
        _methodChartBoundaryKeys.putIfAbsent(method, () => GlobalKey());

    return GestureDetector(
      onTap: bestScenario.isEmpty
          ? null
          : () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScenarioDetailPage(
              scenarioName: bestScenario,
              scenariosMap: widget.scenariosMap,
            ),
          ),
        );
      },
      child: Card(
        elevation: 2,
        color: Colors.white,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                _unitsByMethod[method] == null
                    ? method
                    : '$method (${_unitsByMethod[method]})',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            Expanded(
              child: RepaintBoundary(
                key: chartBoundaryKey,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SizedBox(
                    width: _leftMargin +
                        _scenarioNames.length * _barWidth +
                        (_scenarioNames.length - 1) * 16 +
                        _leftMargin,
                    child: BarChart(
                      BarChartData(
                        backgroundColor: Colors.white,
                        minY: axis.min,
                        maxY: axis.max,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: axis.interval,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: Colors.grey.shade300,
                            strokeWidth: 1,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            axisNameWidget: Padding(
                              padding: const EdgeInsets.only(bottom: 0),
                              child: Text(
                                yLabel,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: axis.interval,
                              reservedSize: _leftMargin,
                              getTitlesWidget: (val, _) => Text(
                                _formatTick(val, axis.interval),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            axisNameWidget: const SizedBox(),
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: _bottomMargin,
                              getTitlesWidget: (val, meta) {
                                final idx = val.toInt();
                                if (idx < 0 || idx >= _scenarioNames.length) {
                                  return const SizedBox();
                                }
                                return SideTitleWidget(
                                  axisSide: meta.axisSide,
                                  child: Transform.rotate(
                                    angle: -pi / 3, // -60 degrees
                                    child: SizedBox(
                                      width: 92,
                                      child: Text(
                                        _scenarioNames[idx],
                                        style: const TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                        softWrap: false,
                                        maxLines: 1,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        barGroups: List.generate(
                          _scenarioNames.length,
                          (i) {
                            final name = _scenarioNames[i];
                            final y = scores[i];
                            final isBest = name == bestScenario;
                            return BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: y,
                                  width: _barWidth,
                                  borderRadius: BorderRadius.circular(4),
                                  color: isBest ? Colors.green : Colors.black,
                                ),
                              ],
                            );
                          },
                        ),
                        groupsSpace: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== Shared helpers =====================

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');
  }

  String _titleCaseFromKey(String keyLower) {
    // keyLower is already lowercased; reconstruct a nicer label
    // Try to preserve separator text like ":"
    final parts = keyLower.split(':');
    if (parts.length == 1) return _titleCase(parts[0]);
    return '${_titleCase(parts[0])}:${parts.sublist(1).join(':')}';
  }

  String _detectBaselineName(List<String> names) {
    for (final n in names) {
      final s = n.toLowerCase();
      if (s.contains('baseline') || s == 'base' || s.contains('reference')) {
        return n;
      }
    }
    for (final n in names) {
      if (!n.contains('%')) return n;
    }
    return names.isNotEmpty ? names.first : 'baseline';
  }

  double _niceExtent(double maxAbs) {
    if (maxAbs <= 0) return 1.0;
    final mag = pow(10, (log(maxAbs) / ln10).floor()).toDouble();
    final norm = maxAbs / mag;
    double ceilv;
    if (norm <= 1.2)       ceilv = 1.2;
    else if (norm <= 1.5)  ceilv = 1.5;
    else if (norm <= 2.0)  ceilv = 2.0;
    else if (norm <= 2.5)  ceilv = 2.5;
    else if (norm <= 5.0)  ceilv = 5.0;
    else                   ceilv = 10.0;
    return ceilv * mag;
  }

  Widget _errorCard(String msg) {
    return Card(
      elevation: 2,
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(msg, textAlign: TextAlign.center),
        ),
      ),
    );
  }

  // ----- Axis helpers for bar charts -----
  _Axis _computeNiceAxis(List<double> values, {int maxTicks = 6}) {
    if (values.isEmpty) {
      return const _Axis(min: 0, max: 1, interval: 0.2);
    }

    double vMin = values.reduce(min);
    double vMax = values.reduce(max);

    if (vMin == vMax) {
      final zero = vMin == 0.0;
      final padding = zero ? 1.0 : vMin.abs() * 0.2 + 1e-9;
      final minY = vMin - padding;
      final maxY = vMax + padding;
      final interval = _niceStep((maxY - minY) / (maxTicks - 1));
      final niceMin = _floorTo(minY, interval);
      final niceMax = _ceilTo(maxY, interval);
      return _Axis(min: niceMin, max: niceMax, interval: interval);
    }

    final range = vMax - vMin;
    final pad = range * 0.08;
    double rawMin = vMin - pad;
    double rawMax = vMax + pad;

    if (vMin < 0 && vMax > 0) {
      rawMin = min(rawMin, 0);
      rawMax = max(rawMax, 0);
    }

    final roughStep = (rawMax - rawMin) / max(maxTicks - 1, 1);
    final step = _niceStep(roughStep);

    final niceMin = _floorTo(rawMin, step);
    final niceMax = _ceilTo(rawMax, step);

    final interval = step <= 0 ? (niceMax - niceMin) / max(maxTicks - 1, 1) : step;

    return _Axis(min: niceMin, max: niceMax, interval: interval);
  }

  double _niceStep(double raw) {
    if (!raw.isFinite || raw == 0) return 1.0;
    final sign = raw.sign;
    final x = raw.abs();

    final exp10 = pow(10, (log(x) / ln10).floor()).toDouble();
    final f = x / exp10;

    double nf;
    if (f < 1.5)      nf = 1;
    else if (f < 2.3) nf = 2;
    else if (f < 3.5) nf = 2.5;
    else if (f < 7)   nf = 5;
    else              nf = 10;

    return sign * nf * exp10;
  }

  double _floorTo(double x, double step) {
    if (step == 0) return x;
    return (x / step).floorToDouble() * step;
  }

  double _ceilTo(double x, double step) {
    if (step == 0) return x;
    return (x / step).ceilToDouble() * step;
  }

  String _guessYAxisLabel(String methodName) {
    final fromPayload = _unitsByMethod[methodName];
    if (fromPayload != null && fromPayload.isNotEmpty) {
      return fromPayload;
    }

    final fromName = _extractUnitFromMethodLabel(methodName);
    if (fromName != null && fromName.isNotEmpty) {
      return fromName;
    }

    final nameLower = methodName.toLowerCase();
    for (final entry in _yAxisLabelRules) {
      if (nameLower.contains(entry.key)) {
        return entry.value;
      }
    }
    return 'impact units';
  }

  Map<String, String> _collectUnitsByMethod() {
    final out = <String, String>{};

    for (final scenario in _scenarioNames) {
      final payload = widget.results[scenario];
      if (payload is! Map) continue;
      final result = payload['result'];
      if (result is! Map) continue;

      for (final method in _methodNames) {
        if (out.containsKey(method)) continue;
        final unit = _extractUnitFromResultMap(
          result.cast<String, dynamic>(),
          method,
        );
        if (unit != null) {
          out[method] = unit;
        }
      }
    }

    return out;
  }

  String? _extractUnitFromResultMap(
    Map<String, dynamic> resultMap,
    String methodName,
  ) {
    for (final key in const [
      'score_units',
      'method_units',
      'unit_by_method',
      'units',
    ]) {
      final raw = resultMap[key];
      if (raw is! Map) continue;

      final byMethod = raw.cast<dynamic, dynamic>();
      final exact = byMethod[methodName];
      final exactUnit = _sanitizeUnit(exact?.toString());
      if (exactUnit != null) return exactUnit;

      final needle = methodName.toLowerCase().trim();
      for (final entry in byMethod.entries) {
        if (entry.key.toString().toLowerCase().trim() != needle) continue;
        final unit = _sanitizeUnit(entry.value?.toString());
        if (unit != null) return unit;
      }
    }

    final singleUnit = _sanitizeUnit(resultMap['unit']?.toString());
    if (singleUnit != null) {
      final scores = resultMap['scores'];
      if (scores is Map && scores.length == 1) {
        return singleUnit;
      }
    }

    return _extractUnitFromMethodLabel(methodName);
  }

  String? _extractUnitFromMethodLabel(String methodName) {
    final candidates = <String>[];
    final bracket = RegExp(r'\[([^\[\]]+)\]');
    for (final m in bracket.allMatches(methodName)) {
      final value = m.group(1)?.trim();
      if (value != null && value.isNotEmpty) {
        candidates.add(value);
      }
    }
    final paren = RegExp(r'\(([^()]+)\)');
    for (final m in paren.allMatches(methodName)) {
      final value = m.group(1)?.trim();
      if (value != null && value.isNotEmpty) {
        candidates.add(value);
      }
    }

    for (final c in candidates.reversed) {
      final normalized = _sanitizeUnit(c);
      if (normalized == null) continue;
      if (_looksLikeUnitExpression(normalized)) {
        return normalized;
      }
    }
    return null;
  }

  bool _looksLikeUnitExpression(String text) {
    final lower = text.toLowerCase();
    const tokens = [
      'kg',
      'mg',
      'mj',
      'kwh',
      'mol',
      'bq',
      'kbq',
      'm3',
      'm²',
      'm2',
      'ctu',
      'pt',
      'eq',
      'co2',
      'co₂',
      'so2',
      'so₂',
      'cfc',
      'pm2.5',
      'nmvoc',
      'disease incidence',
      'world eq deprived',
    ];
    return tokens.any(lower.contains);
  }

  String? _sanitizeUnit(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();
    if (lower == 'null' || lower == 'none' || lower == 'n/a') {
      return null;
    }
    return text;
  }

  String _formatTick(double value, double interval) {
    final absStep = interval.abs();
    if (absStep >= 1000) {
      return value.toStringAsFixed(0);
    } else if (absStep >= 1) {
      return value.toStringAsFixed(0);
    } else if (absStep >= 0.1) {
      return value.toStringAsFixed(1);
    } else if (absStep >= 0.01) {
      return value.toStringAsFixed(2);
    } else if (absStep >= 0.001) {
      return value.toStringAsFixed(3);
    } else {
      return value.toStringAsPrecision(4);
    }
  }
}

// ===================== Tornado page widgets =====================

class _PairResult {
  final List<_SensItem> items;
  final _SensStats stats;
  final bool usesPerVarBaseline;
  _PairResult({
    required this.items,
    required this.stats,
    required this.usesPerVarBaseline,
  });
}

class _SensStats {
  final int total;
  final int realPairs;
  final int mirroredSides;
  final int scaledPairs;
  final int asymmetryFlags;
  _SensStats({
    required this.total,
    required this.realPairs,
    required this.mirroredSides,
    required this.scaledPairs,
    required this.asymmetryFlags,
  });
}

/// Single-page tornado.
class _OnePageTornado extends StatelessWidget {
  final String methodName;
  final String baselineNote;
  final double xExtent;   // axis is [-xExtent, +xExtent]
  final List<_SensItem> items;
  final _SensStats stats;

  const _OnePageTornado({
    Key? key,
    required this.methodName,
    required this.baselineNote,
    required this.xExtent,
    required this.items,
    required this.stats,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TornadoPainter(
        methodName: methodName,
        baselineNote: baselineNote,
        items: items,
        extent: xExtent,
        stats: stats,
      ),
      size: Size.infinite,
    );
  }
}

class _TornadoPainter extends CustomPainter {
  final String methodName;
  final String baselineNote;
  final List<_SensItem> items;
  final double extent;
  final _SensStats stats;

  // colours
  final Color negColour = const Color(0xFFE44F4F);
  final Color posColour = const Color(0xFF1FA774);
  final Color axisColour = Colors.black87;
  final Color gridColour = const Color(0xFFE6E6E6);
  final Color textColour = Colors.black;

  _TornadoPainter({
    required this.methodName,
    required this.baselineNote,
    required this.items,
    required this.extent,
    required this.stats,
  });

  String _fmt(double v) {
    final av = v.abs();
    if (av >= 1000) return v.toStringAsFixed(0);
    if (av >= 1) return v.toStringAsFixed(2);
    if (av >= 0.1) return v.toStringAsFixed(3);
    if (av >= 0.01) return v.toStringAsFixed(4);
    return v.toStringAsPrecision(3);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final top = 72.0;
    final bottom = 56.0;
    final right = 16.0;

    final maxLabelWidthFrac = 0.38;
    final longestLabel = items.map((e) => e.label.length).fold<int>(0, max);
    final estCharWidth = 7.0;
    final estLabelWidth =
        min(w * maxLabelWidthFrac, max(120.0, longestLabel * estCharWidth));

    final rows = items.length;
    final availableH = h - top - bottom;
    double rowH = (availableH / rows).clamp(22.0, 46.0);
    final barThickness = max(10.0, min(22.0, rowH * 0.46));
    final labelFontSize = _scaleBetween(rowH, 22.0, 46.0, 11.0, 15.0);
    final tickFontSize = _scaleBetween(rowH, 22.0, 46.0, 10.0, 13.0);
    final valueFontSize = _scaleBetween(rowH, 22.0, 46.0, 10.5, 13.0);

    final labelRect = Rect.fromLTWH(12.0, top, estLabelWidth, availableH);
    final plotRect = Rect.fromLTWH(
      labelRect.right + 12.0,
      top,
      w - right - (labelRect.right + 12.0),
      availableH,
    );

    // background
    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bg);

    // title and baseline note
    _drawText(
      canvas,
      methodName,
      Offset(w / 2, 12),
      fontSize: 16,
      weight: FontWeight.w700,
      anchor: Alignment.topCenter,
    );
    _drawText(
      canvas,
      baselineNote,
      Offset(w / 2, 34),
      fontSize: 12.5,
      colour: Colors.black87,
      anchor: Alignment.topCenter,
    );

    // stats line
    final statsLine =
        'Variables: ${stats.total} | Real pairs: ${stats.realPairs}'
        '${stats.scaledPairs > 0 ? ' | Scaled pairs: ${stats.scaledPairs}' : ''}'
        '${stats.mirroredSides > 0 ? ' | Mirrored sides: ${stats.mirroredSides}' : ''}'
        '${stats.asymmetryFlags > 0 ? ' | Asymmetry flags: ${stats.asymmetryFlags}' : ''}';
    _drawText(
      canvas,
      statsLine,
      Offset(w / 2, 54),
      fontSize: 11.5,
      colour: Colors.black87,
      anchor: Alignment.topCenter,
    );

    // axis and grid
    final xMin = -extent;
    final xMax = extent;
    final zeroX = _mapX(0, xMin, xMax, plotRect);

    final tickInterval = _niceTick((xMax - xMin) / 6);
    final gridPaint = Paint()
      ..color = gridColour
      ..strokeWidth = 1;

    for (double v = 0; v <= xMax + 1e-9; v += tickInterval) {
      if (v == 0) continue;
      final x = _mapX(v, xMin, xMax, plotRect);
      final xm = _mapX(-v, xMin, xMax, plotRect);
      canvas.drawLine(Offset(x, plotRect.top), Offset(x, plotRect.bottom), gridPaint);
      canvas.drawLine(Offset(xm, plotRect.top), Offset(xm, plotRect.bottom), gridPaint);
    }

    final axisPaint = Paint()
      ..color = axisColour
      ..strokeWidth = 1.6;
    canvas.drawLine(Offset(zeroX, plotRect.top), Offset(zeroX, plotRect.bottom), axisPaint);

    for (double v = -xMax; v <= xMax + 1e-9; v += tickInterval) {
      final x = _mapX(v, xMin, xMax, plotRect);
      _drawText(
        canvas,
        v == 0 ? '0' : _fmt(v),
        Offset(x, plotRect.bottom + 6),
        fontSize: tickFontSize,
        anchor: Alignment.topCenter,
      );
    }

    // legend
    final legendY = plotRect.top - 10;
    _drawSwatch(canvas, Offset(plotRect.left, legendY), negColour, '-10%');
    _drawSwatch(canvas, Offset(plotRect.left + 70, legendY), posColour, '+10%');
    _drawText(
      canvas,
      '',
      Offset(plotRect.left + 150, legendY - 5),
      fontSize: 11,
      colour: Colors.black87,
      anchor: Alignment.topLeft,
    );

    // bars
    for (int i = 0; i < rows; i++) {
      final item = items[i];
      final cy = plotRect.top + i * rowH + rowH / 2;
      final halfBar = barThickness / 2;

      // variable label
      _drawText(
        canvas,
        item.label,
        Offset(labelRect.right - 6, cy),
        fontSize: labelFontSize,
        anchor: Alignment.centerRight,
        maxWidth: labelRect.width - 6,
        useEllipsis: true,
      );

      // negative bar
      final negLen = (_mapX(item.negDelta.abs(), xMin, xMax, plotRect) -
              _mapX(0, xMin, xMax, plotRect))
          .abs();
      final negRect =
          Rect.fromLTWH(zeroX - negLen, cy - halfBar, negLen, barThickness);
      _drawBar(canvas, negRect, negColour);
      _drawText(
        canvas,
        '-Δ ${_fmt(item.negDelta.abs())} (-${_trimPct(item.negPct)}%)${item.negMirrored ? ' mirrored' : ''}',
        Offset(negRect.left - 6, cy),
        fontSize: valueFontSize,
        anchor: Alignment.centerRight,
      );

      // positive bar
      final posLen = (_mapX(item.posDelta.abs(), xMin, xMax, plotRect) -
              _mapX(0, xMin, xMax, plotRect))
          .abs();
      final posRect = Rect.fromLTWH(zeroX, cy - halfBar, posLen, barThickness);
      _drawBar(canvas, posRect, posColour);
      _drawText(
        canvas,
        '+Δ ${_fmt(item.posDelta.abs())} (+${_trimPct(item.posPct)}%)${item.posMirrored ? ' mirrored' : ''}',
        Offset(posRect.right + 6, cy),
        fontSize: valueFontSize,
        anchor: Alignment.centerLeft,
      );

      // asymmetry marker
      if (item.flagAsymmetric) {
        _drawText(
          canvas,
          'asymmetry',
          Offset(zeroX, cy + halfBar + 3),
          fontSize: valueFontSize - 1,
          colour: Colors.black87,
          anchor: Alignment.topCenter,
        );
      }
    }

    // border
    final border = Paint()
      ..color = Colors.black12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(plotRect.deflate(0.5), border);

    // footer
    _drawText(
      canvas,
      'Bars show change from baseline (impact units).',
      Offset(size.width / 2, size.height - 10),
      fontSize: 11.5,
      colour: Colors.black87,
      anchor: Alignment.bottomCenter,
    );
  }

  double _mapX(double v, double xMin, double xMax, Rect plot) {
    final t = (v - xMin) / (xMax - xMin);
    return plot.left + t * plot.width;
  }

  double _niceTick(double rough) {
    if (!rough.isFinite || rough <= 0) return 1.0;
    final mag = pow(10, (log(rough) / ln10).floor()).toDouble();
    final f = rough / mag;
    double nf;
    if (f <= 1.0)      nf = 1.0;
    else if (f <= 2.0) nf = 2.0;
    else if (f <= 2.5) nf = 2.5;
    else if (f <= 5.0) nf = 5.0;
    else               nf = 10.0;
    return nf * mag;
  }

  double _scaleBetween(double x, double a1, double a2, double b1, double b2) {
    final t = ((x - a1) / (a2 - a1)).clamp(0.0, 1.0);
    return b1 + t * (b2 - b1);
  }

  String _trimPct(double p) {
    final ap = p.abs();
    if ((ap - ap.roundToDouble()).abs() < 1e-9) return ap.toStringAsFixed(0);
    return ap.toStringAsFixed(1);
  }

  void _drawBar(Canvas canvas, Rect r, Color colour) {
    final paint = Paint()..color = colour;
    canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(4)), paint);
  }

  void _drawSwatch(Canvas canvas, Offset origin, Color c, String label) {
    final box = Rect.fromLTWH(origin.dx, origin.dy - 10, 16, 10);
    final p = Paint()..color = c;
    canvas.drawRect(box, p);
    _drawText(
      canvas,
      label,
      Offset(box.right + 6, origin.dy - 5),
      fontSize: 11.5,
      colour: Colors.black87,
      anchor: Alignment.topLeft,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset anchorPoint, {
    double fontSize = 12,
    Color colour = Colors.black,
    FontWeight weight = FontWeight.w500,
    Alignment anchor = Alignment.centerLeft,
    double? maxWidth,
    bool useEllipsis = false,
  }) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: colour,
        fontSize: fontSize,
        fontWeight: weight,
        fontFamily: 'Roboto',
      ),
    );
    final tp = TextPainter(
      text: textSpan,
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      maxLines: useEllipsis ? 1 : null,
      ellipsis: useEllipsis ? '...' : null,
    );
    if (maxWidth != null) {
      tp.layout(minWidth: 0, maxWidth: maxWidth);
    } else {
      tp.layout();
    }
    final dx = anchorPoint.dx - anchor.alongOffset(Offset(tp.width, tp.height)).dx;
    final dy = anchorPoint.dy - anchor.alongOffset(Offset(tp.width, tp.height)).dy;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _TornadoPainter old) {
    return methodName != old.methodName ||
        baselineNote != old.baselineNote ||
        extent != old.extent ||
        !listEquals(items, old.items) ||
        stats.total != old.stats.total ||
        stats.realPairs != old.stats.realPairs ||
        stats.mirroredSides != old.stats.mirroredSides ||
        stats.scaledPairs != old.stats.scaledPairs ||
        stats.asymmetryFlags != old.stats.asymmetryFlags;
  }
}

/// Row model. Both sides are present after processing (mirrored if missing).
class _SensItem {
  final String label;
  late double negDelta;     // at -negPct
  late double posDelta;     // at +posPct
  late double negPct;       // magnitude
  late double posPct;       // magnitude
  bool negMirrored = false; // created from opposite side
  bool posMirrored = false;
  bool flagAsymmetric = false;

  _SensItem(this.label);

  double get maxAbsDelta => max(negDelta.abs(), posDelta.abs());

  @override
  bool operator ==(Object other) =>
      other is _SensItem &&
      other.label == label &&
      other.negDelta == negDelta &&
      other.posDelta == posDelta &&
      other.negPct == negPct &&
      other.posPct == posPct &&
      other.negMirrored == negMirrored &&
      other.posMirrored == posMirrored &&
      other.flagAsymmetric == flagAsymmetric;

  @override
  int get hashCode => Object.hash(
        label, negDelta, posDelta, negPct, posPct, negMirrored, posMirrored, flagAsymmetric);
}

/// Simple page dots
class _Dots extends StatelessWidget {
  final int count;
  final int index;
  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 8,
          width: active ? 22 : 8,
          decoration: BoxDecoration(
            color: active ? Colors.black87 : Colors.black26,
            borderRadius: BorderRadius.circular(12),
          ),
        );
      }),
    );
  }
}

// ===================== Scenario detail page (shared) =====================

class ScenarioDetailPage extends StatelessWidget {
  final String scenarioName;
  final Map<String, dynamic>? scenariosMap;

  const ScenarioDetailPage({
    required this.scenarioName,
    required this.scenariosMap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (scenariosMap == null || scenariosMap!.containsKey(scenarioName) == false) {
      return Scaffold(
        appBar: AppBar(title: Text(scenarioName)),
        body: const Center(child: Text('No graph data available')),
      );
    }

    final data = scenariosMap![scenarioName] as Map<String, dynamic>;
    final model = data['model'] as Map<String, dynamic>;
    final procsJson = (model['processes'] as List).cast<Map<String, dynamic>>();
    final flowsJson = (model['flows'] as List).cast<Map<String, dynamic>>();
    final processes = procsJson.map((j) => ProcessNode.fromJson(j)).toList();

    double maxX = 0, maxY = 0;
    for (var n in processes) {
      final sz = ProcessNodeWidget.sizeFor(n);
      maxX = max(maxX, n.position.dx + sz.width);
      maxY = max(maxY, n.position.dy + sz.height);
    }
    final canvasW = maxX + 40;
    final canvasH = maxY + 40;

    return Scaffold(
      appBar: AppBar(title: Text(scenarioName)),
      body: InteractiveViewer(
        boundaryMargin: const EdgeInsets.all(32),
        minScale: 0.5,
        maxScale: 2.5,
        child: SizedBox(
          width: canvasW,
          height: canvasH,
          child: Stack(
            children: [
              CustomPaint(
                size: Size(canvasW, canvasH),
                painter: UndirectedConnectionPainter(
                  processes,
                  flowsJson,
                  nodeHeightScale: const {},
                ),
              ),
              for (var node in processes)
                Positioned(
                  left: node.position.dx,
                  top: node.position.dy,
                  child: ProcessNodeWidget(node: node),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===================== Parameter diffing utilities =====================

class _ParamSnapshot {
  final Map<String, double> values; // keys like g::Name or p::<pid>::Name
  final double? fu;
  _ParamSnapshot(this.values, this.fu);
}

class _ParamChange {
  final double? oldValue;
  final double? newValue;
  _ParamChange({required this.oldValue, required this.newValue});
}

class _ParamDiff {
  final Map<String, _ParamChange> changes;
  List<String> get changedKeys => changes.entries
      .where((e) => _changed(e.value.oldValue, e.value.newValue))
      .map((e) => e.key)
      .toList();

  _ParamDiff(this.changes);

  static bool _changed(double? a, double? b) {
    if (a == null && b == null) return false;
    if (a == null || b == null) return true;
    final diff = (a - b).abs();
    if (a == 0 && b == 0) return false;
    if (a == 0 || b == 0) return diff > 1e-12;
    return diff / max(a.abs(), b.abs()) > 1e-9;
  }
}

_ParamSnapshot _snapshotParams(Map<String, dynamic> scenarioEntry) {
  final out = <String, double>{};

  // Prefer explicit ParameterSet snapshot if present
  final params = scenarioEntry['parameters'];
  if (params is Map) {
    final m = params.cast<String, dynamic>();

    final gp = m['global_parameters'];
    if (gp is List) {
      for (final p in gp) {
        if (p is Map && p['name'] != null) {
          final name = (p['name'] as String).trim();
          final val = p['value'];
          if (val is num) {
            out['g::${name.toLowerCase()}'] = val.toDouble();
          }
        }
      }
    }

    final pp = m['process_parameters'];
    if (pp is Map) {
      pp.forEach((pid, list) {
        if (list is List) {
          for (final p in list) {
            if (p is Map && p['name'] != null) {
              final name = (p['name'] as String).trim();
              final val = p['value'];
              if (val is num) {
                out['p::${pid.toString()}::${name.toLowerCase()}'] = val.toDouble();
              }
            }
          }
        }
      });
    }
  } else {
    // Fallback: try model.parameters
    final model = scenarioEntry['model'];
    if (model is Map) {
      final mp = model['parameters'];
      if (mp is Map) {
        final gp = mp['global_parameters'];
        if (gp is List) {
          for (final p in gp) {
            if (p is Map && p['name'] != null) {
              final name = (p['name'] as String).trim();
              final val = p['value'];
              if (val is num) {
                out['g::${name.toLowerCase()}'] = val.toDouble();
              }
            }
          }
        }
        final pp = mp['process_parameters'];
        if (pp is Map) {
          pp.forEach((pid, list) {
            if (list is List) {
              for (final p in list) {
                if (p is Map && p['name'] != null) {
                  final name = (p['name'] as String).trim();
                  final val = p['value'];
                  if (val is num) {
                    out['p::${pid.toString()}::${name.toLowerCase()}'] = val.toDouble();
                  }
                }
              }
            }
          });
        }
      }
    }
  }

  // Functional units
  double? fu;
  final model = scenarioEntry['model'];
  if (model is Map) {
    final fuVal = model['number_functional_units'];
    if (fuVal is num) fu = fuVal.toDouble();
  }

  return _ParamSnapshot(out, fu);
}

_ParamDiff _diffParams(_ParamSnapshot base, _ParamSnapshot other) {
  final allKeys = <String>{}..addAll(base.values.keys)..addAll(other.values.keys);
  final changes = <String, _ParamChange>{};

  for (final k in allKeys) {
    changes[k] = _ParamChange(
      oldValue: base.values[k],
      newValue: other.values[k],
    );
  }

  // FU as special key "fu"
  if (base.fu != null || other.fu != null) {
    changes['fu'] = _ParamChange(oldValue: base.fu, newValue: other.fu);
  }

  return _ParamDiff(changes);
}

Map<String, String> _processIdToName(Map<String, dynamic> scenarioEntry) {
  final m = <String, String>{};
  final model = scenarioEntry['model'];
  if (model is Map) {
    final procs = model['processes'];
    if (procs is List) {
      for (final p in procs) {
        if (p is Map && p['id'] != null) {
          final id = p['id'].toString();
          final name = (p['name'] ?? id).toString();
          m[id] = name;
        }
      }
    }
  }
  return m;
}

// ----- Axis value class for bar charts -----
class _Axis {
  final double min;
  final double max;
  final double interval;
  const _Axis({required this.min, required this.max, required this.interval});
}
