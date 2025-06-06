import 'dart:math';
import 'package:flutter/material.dart';

/// A process box on the canvas
class ProcessNode {
  static const double width = 100, height = 50;
  final int id;
  String label;
  Offset position;
  ProcessNode({
    required this.id,
    required this.label,
    required this.position,
  });
}

/// A directed, labeled link between two nodes
class Connection {
  final int fromId, toId;
  final String label;
  Connection({
    required this.fromId,
    required this.toId,
    required this.label,
  });
}

/// The canvas area: drop-target, draggable-to-link, tooltip-on-hover
class EditorCanvas extends StatelessWidget {
  final List<ProcessNode> nodes;
  final List<Connection> connections;
  final void Function(String label, Offset globalPosition) onAddNode;
  final void Function(ProcessNode node, DragUpdateDetails d) onNodePanUpdate;
  final Future<void> Function(ProcessNode node) onNodeTap;
  final void Function(Connection conn) onLinkTap;

  const EditorCanvas({
    Key? key,
    required this.nodes,
    required this.connections,
    required this.onAddNode,
    required this.onNodePanUpdate,
    required this.onNodeTap,
    required this.onLinkTap,
  }) : super(key: key);

  bool _isNearLine(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return false;
    var t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * dx, a.dy + t * dy);
    return (proj - p).distance < 10.0;
  }

  @override
  Widget build(BuildContext ctx) {
    return DragTarget<String>(
      onAcceptWithDetails: (d) => onAddNode(d.data, d.offset),
      builder: (_, __, ___) {
        return Stack(children: [
          // 1) Render all links
          for (var conn in connections)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (ev) {
                  final from = nodes.firstWhere((n) => n.id == conn.fromId);
                  final to   = nodes.firstWhere((n) => n.id == conn.toId);
                  final a = from.position +
                      const Offset(ProcessNode.width / 2, ProcessNode.height / 2);
                  final b = to.position +
                      const Offset(ProcessNode.width / 2, ProcessNode.height / 2);
                  if (_isNearLine(ev.localPosition, a, b)) {
                    onLinkTap(conn);
                  }
                },
                child: CustomPaint(
                  painter: _LinkPainter(
                    start: nodes
                        .firstWhere((n) => n.id == conn.fromId)
                        .position +
                        const Offset(ProcessNode.width / 2, ProcessNode.height / 2),
                    end: nodes
                        .firstWhere((n) => n.id == conn.toId)
                        .position +
                        const Offset(ProcessNode.width / 2, ProcessNode.height / 2),
                    label: conn.label,
                  ),
                ),
              ),
            ),

          // 2) Render all nodes
          for (var node in nodes)
            Positioned(
              left: node.position.dx,
              top: node.position.dy,
              child: DragTarget<ProcessNode>(
                onWillAccept: (src) => src != null && src.id != node.id,
                onAccept: (src) async {
                  // link src → node
                  await onNodeTap(src); // we'll handle link naming there
                },
                builder: (ctx, cands, rej) {
                  return GestureDetector(
                    onPanUpdate: (d) => onNodePanUpdate(node, d),
                    onTap: () => onNodeTap(node),
                    child: Tooltip(
                      message: 'Process: ${node.label}',
                      child: LongPressDraggable<ProcessNode>(
                        data: node,
                        feedback: Opacity(
                          opacity: 0.7,
                          child: _ProcessBox(label: node.label),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.4,
                          child: _ProcessBox(label: node.label),
                        ),
                        child: _ProcessBox(label: node.label),
                      ),
                    ),
                  );
                },
              ),
            ),
        ]);
      },
    );
  }
}

/// Draws an arrowed line with centered label
class _LinkPainter extends CustomPainter {
  final Offset start, end;
  final String label;
  _LinkPainter({
    required this.start,
    required this.end,
    required this.label,
  });

  @override
  void paint(Canvas c, Size s) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2;
    c.drawLine(start, end, paint);

    // arrowhead
    final ang = atan2(end.dy - start.dy, end.dx - start.dx);
    const arrowSize = 8.0;
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
          end.dx - arrowSize * cos(ang - pi / 6),
          end.dy - arrowSize * sin(ang - pi / 6))
      ..moveTo(end.dx, end.dy)
      ..lineTo(
          end.dx - arrowSize * cos(ang + pi / 6),
          end.dy - arrowSize * sin(ang + pi / 6));
    c.drawPath(path, paint);

    // label at midpoint
    final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final span = TextSpan(
      text: label,
      style: const TextStyle(color: Colors.black, fontSize: 12),
    );
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(c, mid - Offset(tp.width / 2, tp.height + 4));
  }

  @override
  bool shouldRepaint(covariant _LinkPainter old) =>
      old.start != start || old.end != end || old.label != label;
}

/// Visual representation of a process node
class _ProcessBox extends StatelessWidget {
  final String label;
  const _ProcessBox({Key? key, required this.label}) : super(key: key);

  @override
  Widget build(BuildContext ctx) {
    return Container(
      width: ProcessNode.width,
      height: ProcessNode.height,
      decoration: BoxDecoration(
        color: Colors.green.shade300,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 3)],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white),
      ),
    );
  }
}
