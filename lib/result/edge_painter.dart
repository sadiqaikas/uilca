// lib/painters/edge_painter.dart

import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'grid_layout.dart';

/// Draws smooth orthogonal arrows for each edge in [g] using positions from [layout].
class EdgePainter extends CustomPainter {
  const EdgePainter(this.g, this.layout);

  final Graph g;
  final GridLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blueGrey.shade400
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final edge in g.edges) {
      final srcOff = layout.posOf(edge.source)!;
      final dstOff = layout.posOf(edge.destination)!;
      final x1 = srcOff.dx + layout.nodeW;
      final y1 = srcOff.dy + layout.nodeH / 2;
      final x4 = dstOff.dx;
      final y4 = dstOff.dy + layout.nodeH / 2;
      final mx = (x1 + x4) / 2;

      // Orthogonal path: right → vertical → right
      final path = Path()
        ..moveTo(x1, y1)
        ..lineTo(mx, y1)
        ..lineTo(mx, y4)
        ..lineTo(x4, y4);

      canvas.drawPath(path, paint);

      // Arrowhead
      const ah = 6.0, aw = 5.0;
      final arrow = Path()
        ..moveTo(x4, y4)
        ..lineTo(x4 - ah, y4 - aw)
        ..lineTo(x4 - ah, y4 + aw)
        ..close();

      canvas.drawPath(arrow, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
