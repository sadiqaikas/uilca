// lib/widgets/impact_bar_chart.dart

// import 'package:flutter/material.dart';
// import 'package:fl_chart/fl_chart.dart';
// import 'dart:math' as math;

// /// A bar chart of LCA impacts (e.g. CO₂), showing TOTAL + per-process breakdown.
// ///
// /// - [totalImpact]: sum of all process impacts (will be clamped ≥0).
// /// - [perProcessImpact]: map from process ID/name → impact value.
// /// - [methodLabel]: LCIA method name to display above the chart.
// /// - [onBarTap]: optional callback when a bar is tapped; receives the label.
// class ImpactBarChart extends StatelessWidget {
//   /// Sum of all impacts.
//   final double totalImpact;

//   /// Impact per process.
//   final Map<String, double> perProcessImpact;

//   /// Label identifying the LCIA method used.
//   final String methodLabel;

//   /// Called when the user taps a bar; receives the process name ("TOTAL" for total).
//   final void Function(String label)? onBarTap;

//   const ImpactBarChart({
//     Key? key,
//     required this.totalImpact,
//     required this.perProcessImpact,
//     required this.methodLabel,
//     this.onBarTap,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     // Build sorted list of entries, with TOTAL first if > 0
//     final entries = <MapEntry<String, double>>[
//       if (totalImpact > 0) MapEntry('TOTAL', totalImpact),
//       ...perProcessImpact.entries.toList()
//         ..sort((a, b) => b.value.compareTo(a.value)),
//     ];

//     // Chart styling
//     final theme = Theme.of(context);
//     final barColor = theme.colorScheme.primary;
//     final labelStyle = theme.textTheme.bodySmall;

//     // Compute maxY for chart scaling
//     final rawMax = entries.isNotEmpty
//         ? entries.map((e) => e.value).reduce(math.max)
//         : 1.0;
//     final maxY = (rawMax * 1.2).clamp(1.0, double.infinity);

//     // Bar groups
//     final barGroups = List<BarChartGroupData>.generate(entries.length, (i) {
//       final val = entries[i].value;
//       return BarChartGroupData(
//         x: i,
//         barsSpace: 4,
//         barRods: [
//           BarChartRodData(
//             toY: val,
//             color: barColor,
//             width: 28,
//             borderRadius: BorderRadius.circular(4),
//             backDrawRodData: BackgroundBarChartRodData(
//               show: true,
//               toY: maxY,
//               color: barColor.withOpacity(0.1),
//             ),
//           ),
//         ],
//       );
//     });

//     return Padding(
//       padding: const EdgeInsets.all(12),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // Method label
//           Text(
//             methodLabel,
//             style: theme.textTheme.titleMedium
//                 ?.copyWith(fontWeight: FontWeight.bold),
//           ),
//           const SizedBox(height: 8),

//           // The chart
//           Expanded(
//             child: SingleChildScrollView(
//               scrollDirection: Axis.horizontal,
//               child: SizedBox(
//                 // width = (#bars) × (bar width + spacing)
//                 width: entries.length * (28 + 20).toDouble(),
//                 child: BarChart(
//                   BarChartData(
//                     maxY: maxY,
//                     barGroups: barGroups,
//                     barTouchData: BarTouchData(
//                       enabled: onBarTap != null,
//                       touchCallback: (event, response) {
//                         if (event.isInterestedForInteractions &&
//                             response != null &&
//                             response.spot != null) {
//                           final idx = response.spot!.touchedBarGroupIndex;
//                           final label = entries[idx].key;
//                           onBarTap?.call(label);
//                         }
//                       },
//                     ),
//                     titlesData: FlTitlesData(
//                       bottomTitles: AxisTitles(
//                         sideTitles: SideTitles(
//                           showTitles: true,
//                           reservedSize: 80,
//                           getTitlesWidget: (v, meta) {
//                             final idx = v.toInt();
//                             if (idx < 0 || idx >= entries.length) {
//                               return const SizedBox.shrink();
//                             }
//                             return Padding(
//                               padding: const EdgeInsets.only(top: 6),
//                               child: Transform.rotate(
//                                 angle: -math.pi / 2,
//                                 child: Text(
//                                   entries[idx].key,
//                                   style: labelStyle
//                                       ?.copyWith(fontWeight: FontWeight.bold),
//                                   softWrap: false,
//                                 ),
//                               ),
//                             );
//                           },
//                         ),
//                       ),
//                       leftTitles: AxisTitles(
//                         sideTitles: SideTitles(
//                           showTitles: true,
//                           reservedSize: 50,
//                           interval: maxY / 5,
//                           getTitlesWidget: (v, meta) {
//                             if (v == 0) return const SizedBox.shrink();
//                             return Text(
//                               '${v.toInt()}',
//                               style: labelStyle,
//                             );
//                           },
//                         ),
//                       ),
//                       rightTitles:
//                           const AxisTitles(sideTitles: SideTitles(showTitles: false)),
//                       topTitles:
//                           const AxisTitles(sideTitles: SideTitles(showTitles: false)),
//                     ),
//                     gridData: FlGridData(
//                       show: true,
//                       drawHorizontalLine: true,
//                       horizontalInterval: maxY / 5,
//                       getDrawingHorizontalLine: (_) =>
//                           FlLine(color: theme.dividerColor, strokeWidth: 1),
//                     ),
//                     borderData: FlBorderData(show: false),
//                     alignment: BarChartAlignment.spaceAround,
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;

/// A bar chart of LCA impacts (e.g. CO₂), showing TOTAL + per-process breakdown.
/// - [totalImpact]: sum of all process impacts (will be clamped ≥0).
/// - [perProcessImpact]: map from process ID/name → impact value.
/// - [methodLabel]: LCIA method name to display above the chart.
/// - [onBarTap]: optional callback when a bar is tapped; receives the label.
class ImpactBarChart extends StatelessWidget {
  final double totalImpact;
  final Map<String, double> emissions_per_process;
  final String methodLabel;
  final void Function(String label)? onBarTap;

  const ImpactBarChart({
    Key? key,
    required this.totalImpact,
    required this.emissions_per_process,
    required this.methodLabel,
    this.onBarTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 1) Build a single list of entries, including TOTAL
    final entries = <MapEntry<String, double>>[];
    if (totalImpact > 0) {
      entries.add(MapEntry('TOTAL', totalImpact));
    }
    // entries.addAll(emissions_per_process.entries);
    entries.addAll(
      emissions_per_process.entries.map(
        (e) => MapEntry(e.key, e.value < 0 ? 0.0 : e.value),
      ),
    );
    // 2) Sort *all* entries descending by impact value
    entries.sort((a, b) => b.value.compareTo(a.value));

    // Chart styling
    final theme = Theme.of(context);
    final barColor = Colors.red;
    final labelStyle = theme.textTheme.bodySmall;

    // Compute maxY for scaling
    final rawMax = entries.isNotEmpty
        ? entries.map((e) => e.value).reduce(math.max)
        : 1.0;
    final maxY = (rawMax * 1.2).clamp(1.0, double.infinity);

    // Build the bar groups
    final barGroups = List<BarChartGroupData>.generate(entries.length, (i) {
      final val = entries[i].value;
      return BarChartGroupData(
        x: i,
        barsSpace: 4,
        barRods: [
          BarChartRodData(
            toY: val,
            color: barColor,
            width: 28,
            borderRadius: BorderRadius.circular(4),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: maxY,
              color: barColor.withOpacity(0.1),
            ),
          ),
        ],
      );
    });

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Method label
          Text(
            methodLabel,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // Chart area
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: entries.length * (28 + 20).toDouble(),
                child: BarChart(
                  BarChartData(
                    maxY: maxY,
                    barGroups: barGroups,

                    // Touch handling
                    barTouchData: BarTouchData(
                      enabled: onBarTap != null,
                      touchCallback: (event, response) {
                        if (event.isInterestedForInteractions &&
                            response?.spot != null) {
                          final idx = response!.spot!.touchedBarGroupIndex;
                          onBarTap?.call(entries[idx].key);
                        }
                      },
                    ),

                    // Axis titles & labels
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 80,
                          getTitlesWidget: (v, meta) {
                            final idx = v.toInt();
                            if (idx < 0 || idx >= entries.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Transform.rotate(
                                angle: -math.pi / 2,
                                child: Text(
                                  entries[idx].key,
                                  style: labelStyle
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                  softWrap: false,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        axisNameWidget: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Kg CO₂ Eqv. ',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        axisNameSize: 32,
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 50,
                          interval: maxY / 5,
                          getTitlesWidget: (v, meta) {
                            if (v == 0) return const SizedBox.shrink();
                            return Text(v.toInt().toString(), style: labelStyle);
                          },
                        ),
                      ),
                      rightTitles:
                          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles:
                          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),

                    // Grid lines
                    gridData: FlGridData(
                      show: true,
                      drawHorizontalLine: true,
                      horizontalInterval: maxY / 5,
                      getDrawingHorizontalLine: (_) =>
                          FlLine(color: theme.dividerColor, strokeWidth: 1),
                    ),

                    borderData: FlBorderData(show: false),
                    alignment: BarChartAlignment.spaceAround,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
