// lib/lca_editor.dart

import 'dart:math';
import 'package:flutter/material.dart';

class LCAEditorPage extends StatefulWidget {
  const LCAEditorPage({Key? key}) : super(key: key);
  @override
  _LCAEditorPageState createState() => _LCAEditorPageState();
}

class _LCAEditorPageState extends State<LCAEditorPage> {
  // controllers & keys
  final TextEditingController _textController = TextEditingController(text: 'car');
  final GlobalKey _canvasKey = GlobalKey();

  // state
  List<ProcessNode> _nodes = [];
  List<Connection> _connections = [];
  List<String> _palette = ['Process'];
  bool _linkingMode = false;
  ProcessNode? _connectingNode;
  Offset? _tempConnectionEnd;
  int _nextNodeId = 0;

  // ─── Palette & Linking ─────────────────────────────

  void _setPalette(List<String> items) {
    setState(() {
      _palette = items;
    });
  }

  void _toggleLinking() {
    setState(() {
      _linkingMode = !_linkingMode;
      _connectingNode = null;
      _tempConnectionEnd = null;
    });
  }

  // ─── Canvas Behaviors ──────────────────────────────

  void _addNode(Offset globalPos, String label) {
    final box = _canvasKey.currentContext!.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPos);
    setState(() {
      _nodes.add(ProcessNode(
        id: _nextNodeId++,
        position: local,
        label: label,
      ));
    });
  }

  void _finishLink(DragEndDetails details) {
    if (_connectingNode == null) return;
    final box = _canvasKey.currentContext!.findRenderObject() as RenderBox;
    final local = box.globalToLocal(details.velocity.pixelsPerSecond);
    ProcessNode? target;
    for (var n in _nodes) {
      if (n == _connectingNode) continue;
      final center = n.position + Offset(ProcessNode.width/2, ProcessNode.height/2);
      if ((center - local).distance < 40) {
        target = n;
        break;
      }
    }
    if (target != null) {
      setState(() {
        _connections.add(Connection(
          fromId: _connectingNode!.id,
          toId: target!.id,
        ));
      });
    }
    setState(() {
      _connectingNode = null;
      _tempConnectionEnd = null;
    });
  }

  // ─── Node Gestures ────────────────────────────────

  Widget _buildNode(ProcessNode node) {
    return Positioned(
      left: node.position.dx,
      top:  node.position.dy,
      child: GestureDetector(
        onPanStart: (d) {
          if (_linkingMode) setState(() => _connectingNode = node);
        },
        onPanUpdate: (d) {
          if (_linkingMode && _connectingNode == node) {
            final box = _canvasKey.currentContext!.findRenderObject() as RenderBox;
            setState(() => _tempConnectionEnd = box.globalToLocal(d.globalPosition));
          } else if (!_linkingMode) {
            setState(() => node.position += d.delta);
          }
        },
        onPanEnd: (d) {
          if (_linkingMode && _connectingNode == node) _finishLink(d);
        },
        onDoubleTap: () async {
          final newLabel = await showDialog<String>(
            context: context,
            builder: (_) {
              final ctl = TextEditingController(text: node.label);
              return AlertDialog(
                title: const Text('Rename process'),
                content: TextField(controller: ctl),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(context, ctl.text), child: const Text('OK')),
                ],
              );
            },
          );
          if (newLabel != null && newLabel.trim().isNotEmpty) {
            setState(() => node.label = newLabel.trim());
          }
        },
        child: _processBox(node.label),
      ),
    );
  }

  // ─── Auto-Predict & Run ────────────────────────────

  void _autoPredict() {
    final prompt = _textController.text.toLowerCase();
    final items = prompt.contains('car')
        ? ['Raw Material', 'Manufacturing', 'Assembly', 'Distribution', 'Use Phase', 'EoL']
        : ['Process A','Process B','Process C'];

    // reset everything
    setState(() {
      _palette = items;
      _nodes.clear();
      _connections.clear();
      _nextNodeId = 0;
    });

    // after layout, lay out nodes + auto-link them in order
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _canvasKey.currentContext!.findRenderObject() as RenderBox;
      final size = box.size;
      final gap = size.width / (items.length + 1);
      final centerY = size.height / 2 - ProcessNode.height/2;

      List<ProcessNode> newNodes = [];
      for (int i = 0; i < items.length; i++) {
        final dx = gap * (i + 1) - ProcessNode.width/2;
        final node = ProcessNode(
          id: _nextNodeId++,
          position: Offset(dx, centerY),
          label: items[i],
        );
        newNodes.add(node);
      }

      List<Connection> newConns = [];
      for (int i = 0; i < newNodes.length - 1; i++) {
        newConns.add(Connection(fromId: newNodes[i].id, toId: newNodes[i + 1].id));
      }

      setState(() {
        _nodes = newNodes;
        _connections = newConns;
      });
    });
  }

  void _runLCA() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Run LCA logic here…')),
    );
  }

  // ─── Build ─────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LCA Editor')),
      body: Column(
        children: [
          // Top Palette + Flow toggle
          Container(
            height: 60,
            color: Colors.grey[100],
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _palette.length + 1,
              separatorBuilder: (_,__) => const SizedBox(width: 12),
              itemBuilder: (ctx, i) {
                if (i < _palette.length) {
                  final label = _palette[i];
                  return Draggable<String>(
                    data: label,
                    feedback: _processBox(label, opacity: 0.7),
                    childWhenDragging: Opacity(opacity:0.4, child:_processBox(label)),
                    child: _processBox(label),
                  );
                } else {
                  return IconButton(
                    icon: Icon(Icons.alt_route,
                        color: _linkingMode ? Colors.blue : Colors.black54),
                    onPressed: _toggleLinking,
                    tooltip: 'Link (flow) mode',
                  );
                }
              },
            ),
          ),

          // Text + Canvas
          Expanded(
            child: Row(children: [
              // Text input
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: TextField(
                        controller: _textController,
                        expands: true,
                        maxLines: null,
                        decoration: const InputDecoration(
                          hintText: 'Describe LCA scenario…',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const VerticalDivider(width: 1),

              // Canvas
              Expanded(
                flex: 2,
                child: DragTarget<String>(
                  onAcceptWithDetails: (d) => _addNode(d.offset, d.data),
                  builder: (ctx, c, r) => Container(
                    key: _canvasKey,
                    color: Colors.white,
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: Size.infinite,
                          painter: _ConnectionPainter(
                            nodes: _nodes,
                            connections: _connections,
                            inFlightFrom: _connectingNode,
                            inFlightTo: _tempConnectionEnd,
                          ),
                        ),
                        ..._nodes.map(_buildNode),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
          ),

          // Bottom Buttons
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(onPressed: _autoPredict, child: const Text('Auto-Predict')),
                const SizedBox(width: 12),
                ElevatedButton(onPressed: _runLCA, child: const Text('Run LCA Analysis')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helper for drawing a process box ───────────────

  Widget _processBox(String label, {double opacity = 1.0}) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: ProcessNode.width,
        height: ProcessNode.height,
        decoration: BoxDecoration(
          color: Colors.green.shade400,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// ─── Data Models & Connection Painter ─────────────────

class ProcessNode {
  static const double width = 100, height = 50;
  final int id;
  Offset position;
  String label;
  ProcessNode({required this.id, required this.position, required this.label});
}

class Connection {
  final int fromId, toId;
  Connection({required this.fromId, required this.toId});
}

class _ConnectionPainter extends CustomPainter {
  final List<ProcessNode> nodes;
  final List<Connection> connections;
  final ProcessNode? inFlightFrom;
  final Offset? inFlightTo;

  _ConnectionPainter({
    required this.nodes,
    required this.connections,
    this.inFlightFrom,
    this.inFlightTo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black87..strokeWidth = 2;

    // drawn flows
    for (var c in connections) {
      final a = _center(nodes.firstWhere((n) => n.id == c.fromId));
      final b = _center(nodes.firstWhere((n) => n.id == c.toId));
      canvas.drawLine(a, b, paint);
      _drawArrow(canvas, a, b, paint);
    }
    // in-flight
    if (inFlightFrom != null && inFlightTo != null) {
      canvas.drawLine(_center(inFlightFrom!), inFlightTo!, paint);
    }
  }

  Offset _center(ProcessNode n) =>
      n.position + const Offset(ProcessNode.width/2, ProcessNode.height/2);

  void _drawArrow(Canvas c, Offset p1, Offset p2, Paint p) {
    const s = 8.0;
    final ang = atan2(p2.dy - p1.dy, p2.dx - p1.dx);
    final path = Path()
      ..moveTo(p2.dx, p2.dy)
      ..lineTo(p2.dx - s * cos(ang - pi/6), p2.dy - s * sin(ang - pi/6))
      ..moveTo(p2.dx, p2.dy)
      ..lineTo(p2.dx - s * cos(ang + pi/6), p2.dy - s * sin(ang + pi/6));
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _ConnectionPainter old) =>
      old.nodes != nodes ||
      old.connections != connections ||
      old.inFlightFrom != inFlightFrom ||
      old.inFlightTo != inFlightTo;
}
