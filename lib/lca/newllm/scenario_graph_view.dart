


// File: lib/lca/scenario_graph_view.dart

import 'package:earlylca/lca/newhome/lca_models.dart';
import 'package:earlylca/lca/newhome/lca_painters.dart';
import 'package:earlylca/lca/newhome/lca_widgets.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Displays a row of scenario graph previews, each clickable to view full-size.
class ScenarioGraphView extends StatelessWidget {
  final Map<String, dynamic> scenariosMap;

  /// Optional keys to wrap each preview in a RepaintBoundary so the caller
  /// can capture images for the PDF report. When provided, a key will be
  /// created or reused per scenario name.
  final Map<String, GlobalKey>? graphBoundaryKeys;

  const ScenarioGraphView({
    super.key,
    required this.scenariosMap,
    this.graphBoundaryKeys,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: scenariosMap.entries.map((entry) {
          final name = entry.key;
          final model = entry.value['model'] as Map<String, dynamic>;
          final processes = (model['processes'] as List)
              .cast<Map<String, dynamic>>()
              .map(ProcessNode.fromJson)
              .toList();
          final flows = (model['flows'] as List).cast<Map<String, dynamic>>();

          // compute bounding box
          double maxX = 0, maxY = 0;
          for (var node in processes) {
            final sz = ProcessNodeWidget.sizeFor(node);
            maxX = math.max(maxX, node.position.dx + sz.width);
            maxY = math.max(maxY, node.position.dy + sz.height);
          }
          final canvasW = maxX + 80;
          final canvasH = maxY + 80;

          Widget buildGraphCanvas() {
            // Full size canvas used inside the scaler
            return SizedBox(
              width: canvasW,
              height: canvasH,
              child: Stack(
                children: [
                  CustomPaint(
                    size: Size(canvasW, canvasH),
                    painter: UndirectedConnectionPainter(processes, flows, nodeHeightScale: const {},),
                  ),
                  for (var node in processes)
                    Positioned(
                      left: node.position.dx,
                      top: node.position.dy,
                      child: ProcessNodeWidget(node: node),
                    ),
                ],
              ),
            );
          }

          Widget buildScaledGraph({required double scale}) {
            return Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topLeft,
                  child: buildGraphCanvas(),
                ),
              ),
            );
          }

          // Choose preview scale to fit height 200
          final previewScale = canvasH > 0 ? 200.0 / canvasH : 1.0;
          final previewWidth = canvasW * previewScale;
          final previewHeight = canvasH * previewScale;

          // Optional key to allow screenshotting this preview
          GlobalKey? boundaryKey;
          if (graphBoundaryKeys != null) {
            boundaryKey = graphBoundaryKeys![name] ??= GlobalKey();
          }

          final preview = SizedBox(
            width: previewWidth,
            height: previewHeight,
            child: buildScaledGraph(scale: previewScale),
          );

          return Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                // Preview: scaled preview with tap to view full
                GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        insetPadding: const EdgeInsets.all(16),
                        child: InteractiveViewer(
                          constrained: false,
                          boundaryMargin: const EdgeInsets.all(20),
                          minScale: 0.5,
                          maxScale: 2.0,
                          child: Card(
                            elevation: 4,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: buildGraphCanvas(),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: boundaryKey == null
                      ? preview
                      : RepaintBoundary(key: boundaryKey, child: preview),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
