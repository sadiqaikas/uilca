// import 'package:flutter/material.dart';
// import 'package:fl_chart/fl_chart.dart';

// /// Expects a map like:
// /// {
// ///   "baseline": { "success": true, "result": { "score": 2.0, "unit": "impact units", … } },
// ///   "scenario2": { "success": false, "error": "…" },
// ///   …
// /// }
// class ResultsPage extends StatelessWidget {
//   final Map<String, dynamic> results;

//   const ResultsPage({required this.results, Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final scenarioNames = results.keys.toList();
//     final scores = scenarioNames.map((name) {
//       final info = results[name] as Map<String, dynamic>;
//       if (info['success'] == true) {
//         return (info['result']['score'] as num).toDouble();
//       } else {
//         return 0.0;
//       }
//     }).toList();

//     return Scaffold(
//       appBar: AppBar(title: const Text('LCA Results')),
//       body: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           children: [
//             // 1) Bar chart
//             AspectRatio(
//               aspectRatio: 1.7,
//               child: BarChart(
//                 BarChartData(
//                   alignment: BarChartAlignment.spaceAround,
//                   maxY: (scores.isEmpty ? 1 : scores.reduce((a, b) => a > b ? a : b)) * 1.2,
//                   titlesData: FlTitlesData(
//                     leftTitles: AxisTitles(
//                       sideTitles: SideTitles(showTitles: true),
//                     ),
//                     bottomTitles: AxisTitles(
//                       sideTitles: SideTitles(
//                         showTitles: true,
//                         getTitlesWidget: (value, meta) {
//                           final idx = value.toInt();
//                           if (idx < 0 || idx >= scenarioNames.length) return const SizedBox();
//                           return SideTitleWidget(
//                             axisSide: meta.axisSide,
//                             child: Text(
//                               scenarioNames[idx],
//                               style: const TextStyle(fontSize: 10),
//                             ),
//                           );
//                         },
//                       ),
//                     ),
//                     topTitles: AxisTitles(
//                       sideTitles: SideTitles(showTitles: false),
//                     ),
//                     rightTitles: AxisTitles(
//                       sideTitles: SideTitles(showTitles: false),
//                     ),
//                   ),
//                   barGroups: List.generate(scenarioNames.length, (i) {
//                     return BarChartGroupData(
//                       x: i,
//                       barRods: [
//                         BarChartRodData(
//                           toY: scores[i],
//                           width: 20,
//                           borderRadius: BorderRadius.circular(4),
//                         ),
//                       ],
//                     );
//                   }),
//                 ),
//               ),
//             ),

//             const SizedBox(height: 24),

//             // 2) Detailed cards
//             Expanded(
//               child: ListView.builder(
//                 itemCount: scenarioNames.length,
//                 itemBuilder: (context, i) {
//                   final name = scenarioNames[i];
//                   final info = results[name] as Map<String, dynamic>;
//                   final success = info['success'] as bool;
//                   return Card(
//                     margin: const EdgeInsets.symmetric(vertical: 8),
//                     child: ListTile(
//                       leading: Icon(
//                         success ? Icons.check_circle : Icons.error,
//                         color: success ? Colors.green : Colors.red,
//                       ),
//                       title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
//                       subtitle: success
//                           ? Text("Score: ${info['result']['score']} ${info['result']['unit']}")
//                           : Text("Error: ${info['error']}"),
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


// // lib/results.dart

// import 'package:flutter/material.dart';
// import 'package:fl_chart/fl_chart.dart';
// import 'dart:math';

// /// Expects:
// /// {
// ///   "scenarioA": { "success": true,  "result": { "score": 2.0, "unit": "impact units", … } },
// ///   "scenarioB": { "success": false, "error":  "…" },
// ///   …
// /// }
// class ResultsPage extends StatelessWidget {
//   final Map<String, dynamic> results;

//   const ResultsPage({required this.results, Key? key}) : super(key: key);

// @override
// Widget build(BuildContext context) {
//   final names = results.keys.toList();
//   final scores = names.map((n) {
//     final info = results[n] as Map<String, dynamic>;
//     if (info['success'] == true) {
//       return (info['result']['score'] as num).toDouble();
//     } else {
//       return 0.0;
//     }
//   }).toList();
//   final maxScore = (scores.isEmpty ? 1.0 : scores.reduce(max)) * 1.2;

//   return Scaffold(
//     appBar: AppBar(title: const Text('LCA Results')),
//     body: SafeArea(
//       child: Column(
//         children: [
//           // 1) Give the chart a fixed height:
//           SizedBox(
//             height: 240,
//             child: BarChart(
//               BarChartData(
//                 maxY: maxScore,
//                 alignment: BarChartAlignment.spaceAround,
//                 titlesData: FlTitlesData(
//                   leftTitles: AxisTitles(
//                     sideTitles: SideTitles(showTitles: true),
//                   ),
//                   bottomTitles: AxisTitles(
//                     sideTitles: SideTitles(
//                       showTitles: true,
//                       reservedSize: 28,   // make sure there's room for the labels
//                       getTitlesWidget: (value, meta) {
//                         final idx = value.toInt();
//                         if (idx < 0 || idx >= names.length) return const SizedBox();
//                         return SideTitleWidget(
//                           axisSide: meta.axisSide,
//                           child: Text(names[idx], style: const TextStyle(fontSize: 10)),
//                         );
//                       },
//                     ),
//                   ),
//                   topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
//                   rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
//                 ),
//                 barGroups: List.generate(names.length, (i) {
//                   return BarChartGroupData(
//                     x: i,
//                     barRods: [
//                       BarChartRodData(toY: scores[i], width: 20, borderRadius: BorderRadius.circular(4)),
//                     ],
//                   );
//                 }),
//               ),
//             ),
//           ),

//           const SizedBox(height: 24),

//           // 2) Now let the scenario cards fill the rest of the screen:
//           Expanded(
//             child: ListView.builder(
//               padding: const EdgeInsets.symmetric(horizontal: 16),
//               itemCount: names.length,
//               itemBuilder: (ctx, i) {
//                 final name = names[i];
//                 final info = results[name] as Map<String, dynamic>;
//                 final ok   = info['success'] as bool;
//                 return Card(
//                   margin: const EdgeInsets.symmetric(vertical: 6),
//                   child: ListTile(
//                     leading: Icon(ok ? Icons.check_circle : Icons.error,
//                                   color: ok ? Colors.green : Colors.red),
//                     title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
//                     subtitle: ok
//                         ? Text("Score: ${info['result']['score']} ${info['result']['unit']}")
//                         : Text("Error: ${info['error']}"),
//                   ),
//                 );
//               },
//             ),
//           ),
//         ],
//       ),
//     ),
//   );
// }
// }
// // This file contains the ResultsPage widget that displays the results of LCA scenarios.
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

class ResultsPage extends StatelessWidget {
  final Map<String, dynamic> results;
  const ResultsPage({required this.results, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final names = results.keys.toList();
    final scores = names.map((n) {
      final info = results[n] as Map<String, dynamic>;
      if (info['success'] == true) {
        return (info['result']['score'] as num).toDouble();
      }
      return 0.0;
    }).toList();
    final maxScore = (scores.isEmpty ? 1.0 : scores.reduce(max)) * 1.2;

    return Scaffold(
      appBar: AppBar(title: const Text('LCA Results')),
      body: SafeArea(
        child: Column(
          children: [
            // 1) Bar chart with fixed height
            SizedBox(
              height: 240,
              child: BarChart(
                BarChartData(
                  maxY: maxScore,
                  alignment: BarChartAlignment.spaceAround,
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= names.length) return const SizedBox();
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text(names[i], style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  barGroups: List.generate(names.length, (i) {
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(toY: scores[i], width: 20, borderRadius: BorderRadius.circular(4)),
                      ],
                    );
                  }),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 2) Expandable list of scenario details
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: names.length,
                itemBuilder: (ctx, i) {
                  final name = names[i];
                  final info = results[name] as Map<String, dynamic>;
                  final ok   = info['success'] as bool;
                  final res  = info['result'] as Map<String, dynamic>?;

                  // Build a human-readable method string if available
                  String methodText = res != null && res['method'] is List
                      ? (res['method'] as List).join(' ▶ ')
                      : 'n/a';

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ExpansionTile(
                      leading: Icon(ok ? Icons.check_circle : Icons.error,
                                    color: ok ? Colors.green : Colors.red),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: ok
                          ? Text("Score: ${res!['score']} ${res['unit']}")
                          : Text("Error: ${info['error']}"),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: ok 
                          ? [
                              Row(
                                children: [
                                  const Text("Method:", style: TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(methodText)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text("Database:", style: TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 8),
                                  Text(res!['database'] as String),
                                ],
                              ),
                            ]
                          : [],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
