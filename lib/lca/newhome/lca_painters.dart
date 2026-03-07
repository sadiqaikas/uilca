// File: lib/lca/lca_painters.dart
//
// Painters used by the LCA canvas. Extracted to keep drawing isolated
// from models and page orchestration.

import 'package:flutter/material.dart';

import 'lca_models.dart';   // kEdgeLabelMaxChars, truncateText, ProcessNode
import 'lca_widgets.dart';  // ProcessNodeWidget.sizeFor

class UndirectedConnectionPainter extends CustomPainter {
  final List<ProcessNode> nodes;
  final List<Map<String, dynamic>> flows;
  final Map<String, double> nodeHeightScale;
  final Map<String, bool> collapsed;

  UndirectedConnectionPainter(
    this.nodes,
    this.flows, {
    required this.nodeHeightScale,
    this.collapsed = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    const edgeColor = Color(0xFF0B6E63);
    const labelColor = Color(0xFF1F2937);
    final paint = Paint()
      ..color = edgeColor
      ..strokeWidth = 2.3
      ..style = PaintingStyle.stroke;

    for (var flow in flows) {
      final fromNode = nodes.firstWhere((n) => n.id == flow['from']);
      final toNode = nodes.firstWhere((n) => n.id == flow['to']);
      final sharedNames = (flow['names'] as List<dynamic>).cast<String>();

      // final szFrom = ProcessNodeWidget.sizeFor(
      //   fromNode,
      //   heightScale: nodeHeightScale[fromNode.id] ?? 1.0,
      // );
      // final szTo = ProcessNodeWidget.sizeFor(
      //   toNode,
      //   heightScale: nodeHeightScale[toNode.id] ?? 1.0,
      // );
final szFrom = ProcessNodeWidget.sizeFor(
  fromNode,
  heightScale: nodeHeightScale[fromNode.id] ?? 1.0,
  collapsed: collapsed[fromNode.id] ?? false, // <-- use collapsed
);
final szTo = ProcessNodeWidget.sizeFor(
  toNode,
  heightScale: nodeHeightScale[toNode.id] ?? 1.0,
  collapsed: collapsed[toNode.id] ?? false,   // <-- use collapsed
);

      final startCenter = Offset(
        fromNode.position.dx + szFrom.width / 2,
        fromNode.position.dy + szFrom.height / 2,
      );
      final endCenter = Offset(
        toNode.position.dx + szTo.width / 2,
        toNode.position.dy + szTo.height / 2,
      );

      final clippedStart = _clipLineToRect(
        endCenter,
        startCenter,
        Rect.fromLTWH(fromNode.position.dx, fromNode.position.dy, szFrom.width, szFrom.height),
      );
      final clippedEnd = _clipLineToRect(
        startCenter,
        endCenter,
        Rect.fromLTWH(toNode.position.dx, toNode.position.dy, szTo.width, szTo.height),
      );

      canvas.drawLine(clippedStart, clippedEnd, paint);

      final mid = Offset(
        (clippedStart.dx + clippedEnd.dx) / 2,
        (clippedStart.dy + clippedEnd.dy) / 2,
      );

      final label = truncateText(sharedNames.join(', '), kEdgeLabelMaxChars);
      final tp = TextPainter(
        text: const TextSpan(style: TextStyle(fontSize: 12, color: labelColor)),
        textDirection: TextDirection.ltr,
      );
      tp.text = TextSpan(text: label, style: const TextStyle(fontSize: 12, color: labelColor));
      tp.layout();

      final textOffset = mid - Offset(tp.width / 2, tp.height / 2);
      // white background for legibility
      final bgRect = Rect.fromLTWH(textOffset.dx - 2, textOffset.dy - 1, tp.width + 4, tp.height + 2);
      canvas.drawRect(bgRect, Paint()..color = const Color(0xF7FFFFFF));
      tp.paint(canvas, textOffset);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  /// Clips the line segment (startC -> endC) to the boundary of `rect`
  /// and returns the intersection point from the start toward the end.
  Offset _clipLineToRect(Offset startC, Offset endC, Rect rect) {
    final dx = endC.dx - startC.dx;
    final dy = endC.dy - startC.dy;
    if (dx == 0 && dy == 0) return endC;

    double tMin = double.infinity;
    Offset? intersection;

    void testEdge(double px, double py, bool vertical) {
      final t = vertical ? (px - startC.dx) / dx : (py - startC.dy) / dy;
      if (t > 0) {
        final x = startC.dx + t * dx;
        final y = startC.dy + t * dy;
        final onSegment = vertical
            ? (y >= rect.top && y <= rect.bottom)
            : (x >= rect.left && x <= rect.right);
        if (onSegment && t < tMin) {
          tMin = t;
          intersection = Offset(x, y);
        }
      }
    }

    if (dx != 0) {
      testEdge(rect.left, 0, true);
      testEdge(rect.right, 0, true);
    }
    if (dy != 0) {
      testEdge(0, rect.top, false);
      testEdge(0, rect.bottom, false);
    }
    return intersection ?? endC;
  }
}
