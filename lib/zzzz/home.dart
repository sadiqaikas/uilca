// File: lib/zzzz/home.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'export.dart';
import 'io_utils.dart';

/// Allowed units for flows
const List<String> kFlowUnits = ['kg', 'MW', 'units', 'L', 'm³','m', 'Km', 'KWh', 'g'];

/// A single flow (input or output) with a name, a numeric amount, and a unit.
class FlowValue {
  final String name;
  final double amount;
  final String unit;

  FlowValue({
    required this.name,
    required this.amount,
    required this.unit,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'amount': amount,
        'unit': unit,
      };

  factory FlowValue.fromJson(Map<String, dynamic> json) {
    return FlowValue(
      name: json['name'],
      amount: (json['amount'] as num).toDouble(),
      unit: json['unit'] as String,
    );
  }
}

/// One process node in the LCA—stores an ID, name, list of inputs, list of outputs, CO₂, and its position on the canvas.
class ProcessNode {
  final String id;
  final String name;
  final List<FlowValue> inputs;
  final List<FlowValue> outputs;
  final double co2;
  final Offset position;

  ProcessNode({
    required this.id,
    required this.name,
    required this.inputs,
    required this.outputs,
    required this.co2,
    required this.position,
  });

  /// JSON serialization
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'inputs': inputs.map((f) => f.toJson()).toList(),
        'outputs': outputs.map((f) => f.toJson()).toList(),
        'co2': co2,
        'position': {
          'x': position.dx,
          'y': position.dy,
        },
      };

  factory ProcessNode.fromJson(Map<String, dynamic> json) {
    return ProcessNode(
      id: json['id'],
      name: json['name'],
      inputs: (json['inputs'] as List)
          .map((item) => FlowValue.fromJson(item))
          .toList(),
      outputs: (json['outputs'] as List)
          .map((item) => FlowValue.fromJson(item))
          .toList(),
      co2: (json['co2'] as num).toDouble(),
      position: Offset(
        (json['position']['x'] as num).toDouble(),
        (json['position']['y'] as num).toDouble(),
      ),
    );
  }

  /// Create a copy with a new position (for dragging).
  ProcessNode copyWith({Offset? position}) {
    return ProcessNode(
      id: id,
      name: name,
      inputs: inputs,
      outputs: outputs,
      co2: co2,
      position: position ?? this.position,
    );
  }

  /// Create a copy with all fields possibly replaced (for editing).
  ProcessNode copyWithFields({
    String? name,
    List<FlowValue>? inputs,
    List<FlowValue>? outputs,
    double? co2,
    Offset? position,
  }) {
    return ProcessNode(
      id: id,
      name: name ?? this.name,
      inputs: inputs ?? this.inputs,
      outputs: outputs ?? this.outputs,
      co2: co2 ?? this.co2,
      position: position ?? this.position,
    );
  }
}



/// The main canvas page where processes are added, dragged, connected, and editable.
class LCACanvasPage extends StatefulWidget {
  @override
  State<LCACanvasPage> createState() => _LCACanvasPageState();
}

class _LCACanvasPageState extends State<LCACanvasPage> {
  final List<ProcessNode> _processes = [];
  String? _draggedNodeId;
  Offset? _dragOffsetFromOrigin;

  /// Recompute “connections” between any two processes that share at least one flow name.
  /// Returns a list of maps, each containing:
  ///   'from': producerId,
  ///   'to': consumerId,
  ///   'names': List<String> of the shared flow names (lowercased).
  List<Map<String, dynamic>> get _computedFlows {
    final flows = <Map<String, dynamic>>[];

    // Build a map: nodeId -> set of flow names (all inputs + outputs, lowercased & trimmed)
    final Map<String, Set<String>> nameSets = {};
    for (var node in _processes) {
      final names = <String>{};
      for (var inp in node.inputs) {
        names.add(inp.name.trim().toLowerCase());
      }
      for (var outp in node.outputs) {
        names.add(outp.name.trim().toLowerCase());
      }
      nameSets[node.id] = names;
    }

    // For every pair (i < j), if they share at least one flow name, add one map entry.
    final ids = _processes.map((n) => n.id).toList();
    for (int i = 0; i < ids.length; i++) {
      for (int j = i + 1; j < ids.length; j++) {
        final idA = ids[i], idB = ids[j];
        final setA = nameSets[idA]!;
        final setB = nameSets[idB]!;
        final intersection = setA.intersection(setB);
        if (intersection.isNotEmpty) {
          // We will draw exactly one line between them, labeled by all shared names.
          flows.add({
            'from': idA,
            'to': idB,
            'names': intersection.toList(),
          });
        }
      }
    }

    return flows;
  }

  /// Show the “Add Process” dialog, wait for a new node, then append it.
  void _addProcess() async {
    // Stagger initial position so new nodes don't overlap exactly:
    final initial = Offset(80, 80 + _processes.length * 100.0);
    final newNode = await showDialog<ProcessNode>(
      context: context,
      builder: (_) => AddProcessDialog(initialPosition: initial),
    );
    if (newNode != null) {
      setState(() {
        _processes.add(newNode);
      });
    }
  }

  /// Navigate to a page that shows the JSON export of all processes and connections.
  void _exportJson() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LCAJsonExportPage(
          processes: _processes,
          flows: _computedFlows,
        ),
      ),
    );
  }

  /* ───── DRAGGING LOGIC: tap & drag anywhere on a node to move it ───── */

  void _onPanStart(DragStartDetails details) {
    final local = details.localPosition;
    for (var node in _processes) {
      final size = ProcessNodeWidget.sizeFor(node);
      final rect = Rect.fromLTWH(
        node.position.dx,
        node.position.dy,
        size.width,
        size.height,
      );
      if (rect.contains(local)) {
        _draggedNodeId = node.id;
        // Save offset from the node’s top-left corner so it doesn’t “jump”:
        _dragOffsetFromOrigin = local - node.position;
        return;
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_draggedNodeId == null || _dragOffsetFromOrigin == null) return;
    final idx = _processes.indexWhere((n) => n.id == _draggedNodeId);
    if (idx < 0) return;
    setState(() {
      _processes[idx] = _processes[idx].copyWith(
        position: details.localPosition - _dragOffsetFromOrigin!,
      );
    });
  }

  void _onPanEnd(DragEndDetails _) {
    _draggedNodeId = null;
    _dragOffsetFromOrigin = null;
  }

  /// Called when the user long-presses on a node. Pops up a bottom sheet
  /// with “Edit” and “Delete” options.
  void _onNodeLongPress(ProcessNode node) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.edit, color: Colors.teal),
                title: Text('Edit'),
                onTap: () {
                  Navigator.pop(ctx);
                  _editProcess(node);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete, color: Colors.redAccent),
                title: Text('Delete'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _processes.removeWhere((p) => p.id == node.id);
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Opens the EditProcessDialog, and if the user returns an updated node,
  /// replaces the old one in the list.
  void _editProcess(ProcessNode node) async {
    final updated = await showDialog<ProcessNode>(
      context: context,
      builder: (_) => EditProcessDialog(original: node),
    );
    if (updated != null) {
      setState(() {
        final idx = _processes.indexWhere((p) => p.id == updated.id);
        if (idx >= 0) {
          _processes[idx] = updated;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  title: Center(child: Text('LCA Canvas Designer', style: TextStyle(fontSize: 20))),
  actions: [
    IconButton(
      icon: Icon(Icons.upload_file, size: 28),
      tooltip: 'Load from JSON File',
      onPressed: () => uploadProcesses(
        (loaded) {
          setState(() {
            _processes
              ..clear()
              ..addAll(loaded);
          });
        },
        context,
      ),
    ),
    IconButton(
      icon: Icon(Icons.download, size: 28),
      tooltip: 'Save to JSON File',
      onPressed: () => promptAndDownloadProcesses(_processes, context),
    ),
  ],
),

      body: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(
          children: [
            // 1) Paint all connecting lines (with labels) behind:
            CustomPaint(
              size: Size.infinite,
              painter: UndirectedConnectionPainter(_processes, _computedFlows),
            ),

            // 2) Position each process card on top, with long-press detection:
            for (var node in _processes)
              Positioned(
                left: node.position.dx,
                top: node.position.dy,
                child: GestureDetector(
                  onLongPress: () => _onNodeLongPress(node),
                  child: ProcessNodeWidget(node: node),
                ),
              ),
          ],
        ),
      ),

      // Floating buttons to add a new process or export JSON:
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'add',
            onPressed: _addProcess,
            icon: Icon(Icons.add_box),
            label: Text('Add Process'),
          ),
          SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'export',
            backgroundColor: Colors.teal,
            onPressed: _exportJson,
            icon: Icon(Icons.play_arrow),
            label: Text('Run / Export'),
          ),
        ],
      ),
    );
  }
}

/// A CustomPainter that draws a straight line between any two nodes that share a flow name,
/// and labels it with the shared name(s).
class UndirectedConnectionPainter extends CustomPainter {
  final List<ProcessNode> nodes;
  final List<Map<String, dynamic>> flows;
  // Each entry: { 'from': String idA, 'to': String idB, 'names': List<String> }

  UndirectedConnectionPainter(this.nodes, this.flows);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.teal.shade700
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (var flow in flows) {
      // Look up the two nodes by ID.
      final fromNode = nodes.firstWhere((n) => n.id == flow['from']);
      final toNode = nodes.firstWhere((n) => n.id == flow['to']);
      final sharedNames = (flow['names'] as List<String>);

      final szFrom = ProcessNodeWidget.sizeFor(fromNode);
      final szTo = ProcessNodeWidget.sizeFor(toNode);

      // Compute center points of each node's card:
      final startCenter = Offset(
        fromNode.position.dx + szFrom.width / 2,
        fromNode.position.dy + szFrom.height / 2,
      );
      final endCenter = Offset(
        toNode.position.dx + szTo.width / 2,
        toNode.position.dy + szTo.height / 2,
      );

      // Clip each endpoint so the line meets the card border, not go through the card.
      final clippedStart = _clipLineToRect(
        endCenter,
        startCenter,
        Rect.fromLTWH(
          fromNode.position.dx,
          fromNode.position.dy,
          szFrom.width,
          szFrom.height,
        ),
      );
      final clippedEnd = _clipLineToRect(
        startCenter,
        endCenter,
        Rect.fromLTWH(
          toNode.position.dx,
          toNode.position.dy,
          szTo.width,
          szTo.height,
        ),
      );

      // Draw the line:
      canvas.drawLine(clippedStart, clippedEnd, paint);

      // Draw the label (sharedNames.join(', ')) at the midpoint:
      final label = sharedNames.join(', ');
      final mid = Offset(
        (clippedStart.dx + clippedEnd.dx) / 2,
        (clippedStart.dy + clippedEnd.dy) / 2,
      );

      final textSpan = TextSpan(
        text: label,
        style: TextStyle(fontSize: 12, color: Colors.black),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final textOffset = mid -
          Offset(textPainter.width / 2, textPainter.height / 2);

      // Optionally, draw a small white background behind text to ensure readability:
      final bgRect = Rect.fromLTWH(
        textOffset.dx - 2,
        textOffset.dy - 1,
        textPainter.width + 4,
        textPainter.height + 2,
      );
      final bgPaint = Paint()..color = Colors.white;
      canvas.drawRect(bgRect, bgPaint);

      textPainter.paint(canvas, textOffset);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  /// Given an infinite line from `startC` to `endC`, find where it first intersects `rect`.
  /// Parameterize the line as: P(t) = startC + t*(endC - startC), t>0. Return the intersection
  /// point on the rectangle boundary with the smallest positive t, or `endC` if none found.
  Offset _clipLineToRect(Offset startC, Offset endC, Rect rect) {
    final dx = endC.dx - startC.dx;
    final dy = endC.dy - startC.dy;

    if (dx == 0 && dy == 0) return endC; // Degenerate

    double tMin = double.infinity;
    Offset? intersection;

    // 1) Left edge: x = rect.left
    if (dx != 0) {
      final t = (rect.left - startC.dx) / dx;
      if (t > 0) {
        final y = startC.dy + t * dy;
        if (y >= rect.top && y <= rect.bottom) {
          if (t < tMin) {
            tMin = t;
            intersection = Offset(rect.left, y);
          }
        }
      }
    }

    // 2) Right edge: x = rect.right
    if (dx != 0) {
      final t = (rect.right - startC.dx) / dx;
      if (t > 0) {
        final y = startC.dy + t * dy;
        if (y >= rect.top && y <= rect.bottom) {
          if (t < tMin) {
            tMin = t;
            intersection = Offset(rect.right, y);
          }
        }
      }
    }

    // 3) Top edge: y = rect.top
    if (dy != 0) {
      final t = (rect.top - startC.dy) / dy;
      if (t > 0) {
        final x = startC.dx + t * dx;
        if (x >= rect.left && x <= rect.right) {
          if (t < tMin) {
            tMin = t;
            intersection = Offset(x, rect.top);
          }
        }
      }
    }

    // 4) Bottom edge: y = rect.bottom
    if (dy != 0) {
      final t = (rect.bottom - startC.dy) / dy;
      if (t > 0) {
        final x = startC.dx + t * dx;
        if (x >= rect.left && x <= rect.right) {
          if (t < tMin) {
            tMin = t;
            intersection = Offset(x, rect.bottom);
          }
        }
      }
    }

    return intersection ?? endC;
  }
}

/// Renders a single process node as a Card widget.
class ProcessNodeWidget extends StatelessWidget {
  final ProcessNode node;
  const ProcessNodeWidget({required this.node});

  /// Calculate width & height based on content (# of lines). Keeps text from overflowing.
  static Size sizeFor(ProcessNode n) {
    const lineHeight = 18.0;
    const padding = 16.0;
    // 1 line for name, 1 line for "Inputs:", inputs.length lines,
    // 1 line for "Outputs:", outputs.length lines, 1 line for CO2
    int totalLines = 1;
    if (n.inputs.isNotEmpty) {
      totalLines += 1 + n.inputs.length;
    }
    if (n.outputs.isNotEmpty) {
      totalLines += 1 + n.outputs.length;
    }
    totalLines += 1; // CO₂ line

    final height = padding + totalLines * lineHeight;
    final width = 200.0; // a bit wider to accommodate unit dropdown visually
    return Size(width, height < 80 ? 80 : height);
  }

  @override
  Widget build(BuildContext context) {
    final sz = sizeFor(node);

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        width: sz.width,
        padding: EdgeInsets.all(8),
        child: DefaultTextStyle(
          style: TextStyle(fontSize: 13, color: Colors.black87),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1) Process name
              Text(
                node.name,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),

              // 2) Inputs list
              if (node.inputs.isNotEmpty) ...[
                SizedBox(height: 4),
                Text('Inputs:', style: TextStyle(fontWeight: FontWeight.w600)),
                ...node.inputs.map((f) => Text(
                      '${f.name}: ${f.amount} ${f.unit}',
                      overflow: TextOverflow.ellipsis,
                    )),
              ],

              // 3) Outputs list
              if (node.outputs.isNotEmpty) ...[
                SizedBox(height: 4),
                Text('Outputs:', style: TextStyle(fontWeight: FontWeight.w600)),
                ...node.outputs.map((f) => Text(
                      '${f.name}: ${f.amount} ${f.unit}',
                      overflow: TextOverflow.ellipsis,
                    )),
              ],

              // 4) CO₂ line
              SizedBox(height: 4),
              Text(
                'CO₂: ${node.co2.toStringAsFixed(2)} kg',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog for adding a new process node.
class AddProcessDialog extends StatefulWidget {
  final Offset initialPosition;
  const AddProcessDialog({required this.initialPosition});

  @override
  State<AddProcessDialog> createState() => _AddProcessDialogState();
}

class _AddProcessDialogState extends State<AddProcessDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _co2Ctrl = TextEditingController();

  final List<TextEditingController> _inputNameCtrls = [TextEditingController()];
  final List<TextEditingController> _inputAmtCtrls = [TextEditingController()];
  final List<String> _inputUnitSelections = [kFlowUnits[0]];

  final List<TextEditingController> _outputNameCtrls =
      [TextEditingController()];
  final List<TextEditingController> _outputAmtCtrls = [TextEditingController()];
  final List<String> _outputUnitSelections = [kFlowUnits[0]];

  void _addInputField() {
    setState(() {
      _inputNameCtrls.add(TextEditingController());
      _inputAmtCtrls.add(TextEditingController());
      _inputUnitSelections.add(kFlowUnits[0]);
    });
  }

  void _addOutputField() {
    setState(() {
      _outputNameCtrls.add(TextEditingController());
      _outputAmtCtrls.add(TextEditingController());
      _outputUnitSelections.add(kFlowUnits[0]);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _co2Ctrl.dispose();
    for (var c in _inputNameCtrls) c.dispose();
    for (var c in _inputAmtCtrls) c.dispose();
    for (var c in _outputNameCtrls) c.dispose();
    for (var c in _outputAmtCtrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add Process Node'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1) Process Name
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(labelText: 'Process Name'),
            ),
            SizedBox(height: 14),

            // 2) Inputs section with dynamic name+amount+unit fields
            Row(
              children: [
                Text('Inputs', style: TextStyle(fontWeight: FontWeight.bold)),
                Spacer(),
                IconButton(
                  onPressed: _addInputField,
                  icon: Icon(Icons.add_circle_outline, color: Colors.teal),
                  tooltip: 'Add another input',
                ),
              ],
            ),
            ...List.generate(_inputNameCtrls.length, (i) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    // Input name
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _inputNameCtrls[i],
                        decoration: InputDecoration(
                          hintText: 'Input name',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    // Input amount
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _inputAmtCtrls[i],
                        decoration: InputDecoration(
                          hintText: 'Amount',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    SizedBox(width: 8),
                    // Unit dropdown
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: DropdownButton<String>(
                        value: _inputUnitSelections[i],
                        items: kFlowUnits
                            .map((u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(u, style: TextStyle(fontSize: 12)),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _inputUnitSelections[i] = val;
                            });
                          }
                        },
                        underline: SizedBox.shrink(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              );
            }),

            SizedBox(height: 14),

            // 3) Outputs section with dynamic name+amount+unit fields
            Row(
              children: [
                Text('Outputs', style: TextStyle(fontWeight: FontWeight.bold)),
                Spacer(),
                IconButton(
                  onPressed: _addOutputField,
                  icon: Icon(Icons.add_circle_outline, color: Colors.teal),
                  tooltip: 'Add another output',
                ),
              ],
            ),
            ...List.generate(_outputNameCtrls.length, (i) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    // Output name
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _outputNameCtrls[i],
                        decoration: InputDecoration(
                          hintText: 'Output name',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    // Output amount
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _outputAmtCtrls[i],
                        decoration: InputDecoration(
                          hintText: 'Amount',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    SizedBox(width: 8),
                    // Unit dropdown
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: DropdownButton<String>(
                        value: _outputUnitSelections[i],
                        items: kFlowUnits
                            .map((u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(u, style: TextStyle(fontSize: 12)),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _outputUnitSelections[i] = val;
                            });
                          }
                        },
                        underline: SizedBox.shrink(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              );
            }),

            SizedBox(height: 14),

            // 4) CO₂ emissions field
            TextField(
              controller: _co2Ctrl,
              decoration: InputDecoration(labelText: 'CO₂ Emissions (kg)'),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
        ElevatedButton(
          child: Text('Add'),
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;

            // Build inputs list (key-value-unit) from non-empty fields
            final inputs = <FlowValue>[];
            for (int i = 0; i < _inputNameCtrls.length; i++) {
              final fname = _inputNameCtrls[i].text.trim();
              final famt = double.tryParse(_inputAmtCtrls[i].text.trim()) ?? 0.0;
              final funit = _inputUnitSelections[i];
              if (fname.isNotEmpty) {
                inputs.add(FlowValue(name: fname, amount: famt, unit: funit));
              }
            }

            // Build outputs list (key-value-unit) from non-empty fields
            final outputs = <FlowValue>[];
            for (int i = 0; i < _outputNameCtrls.length; i++) {
              final oname = _outputNameCtrls[i].text.trim();
              final oamt =
                  double.tryParse(_outputAmtCtrls[i].text.trim()) ?? 0.0;
              final ounit = _outputUnitSelections[i];
              if (oname.isNotEmpty) {
                outputs.add(FlowValue(name: oname, amount: oamt, unit: ounit));
              }
            }

            final co2Value = double.tryParse(_co2Ctrl.text.trim()) ?? 0.0;

            final node = ProcessNode(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              name: name,
              inputs: inputs,
              outputs: outputs,
              co2: co2Value,
              position: widget.initialPosition,
            );
            Navigator.pop(context, node);
          },
        ),
      ],
    );
  }
}

/// Dialog for editing an existing process node. Prefills all fields
/// and returns an updated ProcessNode on “Save.”
class EditProcessDialog extends StatefulWidget {
  final ProcessNode original;
  const EditProcessDialog({required this.original});

  @override
  State<EditProcessDialog> createState() => _EditProcessDialogState();
}

class _EditProcessDialogState extends State<EditProcessDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _co2Ctrl;

  late List<TextEditingController> _inputNameCtrls;
  late List<TextEditingController> _inputAmtCtrls;
  late List<String> _inputUnitSelections;

  late List<TextEditingController> _outputNameCtrls;
  late List<TextEditingController> _outputAmtCtrls;
  late List<String> _outputUnitSelections;

  @override
  void initState() {
    super.initState();
    // Prefill with original values:
    _nameCtrl = TextEditingController(text: widget.original.name);
    _co2Ctrl = TextEditingController(text: widget.original.co2.toStringAsFixed(2));

    _inputNameCtrls = widget.original.inputs
        .map((f) => TextEditingController(text: f.name))
        .toList();
    _inputAmtCtrls = widget.original.inputs
        .map((f) => TextEditingController(text: f.amount.toString()))
        .toList();
    _inputUnitSelections =
        widget.original.inputs.map((f) => f.unit).toList();

    _outputNameCtrls = widget.original.outputs
        .map((f) => TextEditingController(text: f.name))
        .toList();
    _outputAmtCtrls = widget.original.outputs
        .map((f) => TextEditingController(text: f.amount.toString()))
        .toList();
    _outputUnitSelections =
        widget.original.outputs.map((f) => f.unit).toList();

    // If there were zero inputs/outputs originally, ensure at least one empty controller
    if (_inputNameCtrls.isEmpty) {
      _inputNameCtrls = [TextEditingController()];
      _inputAmtCtrls = [TextEditingController()];
      _inputUnitSelections = [kFlowUnits[0]];
    }
    if (_outputNameCtrls.isEmpty) {
      _outputNameCtrls = [TextEditingController()];
      _outputAmtCtrls = [TextEditingController()];
      _outputUnitSelections = [kFlowUnits[0]];
    }
  }

  void _addInputField() {
    setState(() {
      _inputNameCtrls.add(TextEditingController());
      _inputAmtCtrls.add(TextEditingController());
      _inputUnitSelections.add(kFlowUnits[0]);
    });
  }

  void _addOutputField() {
    setState(() {
      _outputNameCtrls.add(TextEditingController());
      _outputAmtCtrls.add(TextEditingController());
      _outputUnitSelections.add(kFlowUnits[0]);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _co2Ctrl.dispose();
    for (var c in _inputNameCtrls) c.dispose();
    for (var c in _inputAmtCtrls) c.dispose();
    for (var c in _outputNameCtrls) c.dispose();
    for (var c in _outputAmtCtrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Process Node'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1) Process Name
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(labelText: 'Process Name'),
            ),
            SizedBox(height: 14),

            // 2) Inputs section with dynamic name+amount+unit fields
            Row(
              children: [
                Text('Inputs', style: TextStyle(fontWeight: FontWeight.bold)),
                Spacer(),
                IconButton(
                  onPressed: _addInputField,
                  icon: Icon(Icons.add_circle_outline, color: Colors.teal),
                  tooltip: 'Add another input',
                ),
              ],
            ),
            ...List.generate(_inputNameCtrls.length, (i) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    // Input name
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _inputNameCtrls[i],
                        decoration: InputDecoration(
                          hintText: 'Input name',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    // Input amount
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _inputAmtCtrls[i],
                        decoration: InputDecoration(
                          hintText: 'Amount',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    SizedBox(width: 8),
                    // Unit dropdown
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: DropdownButton<String>(
                        value: _inputUnitSelections[i],
                        items: kFlowUnits
                            .map((u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(u, style: TextStyle(fontSize: 12)),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _inputUnitSelections[i] = val;
                            });
                          }
                        },
                        underline: SizedBox.shrink(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              );
            }),

            SizedBox(height: 14),

            // 3) Outputs section with dynamic name+amount+unit fields
            Row(
              children: [
                Text('Outputs', style: TextStyle(fontWeight: FontWeight.bold)),
                Spacer(),
                IconButton(
                  onPressed: _addOutputField,
                  icon: Icon(Icons.add_circle_outline, color: Colors.teal),
                  tooltip: 'Add another output',
                ),
              ],
            ),
            ...List.generate(_outputNameCtrls.length, (i) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    // Output name
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _outputNameCtrls[i],
                        decoration: InputDecoration(
                          hintText: 'Output name',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    // Output amount
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _outputAmtCtrls[i],
                        decoration: InputDecoration(
                          hintText: 'Amount',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    SizedBox(width: 8),
                    // Unit dropdown
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: DropdownButton<String>(
                        value: _outputUnitSelections[i],
                        items: kFlowUnits
                            .map((u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(u, style: TextStyle(fontSize: 12)),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _outputUnitSelections[i] = val;
                            });
                          }
                        },
                        underline: SizedBox.shrink(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              );
            }),

            SizedBox(height: 14),

            // 4) CO₂ emissions field
            TextField(
              controller: _co2Ctrl,
              decoration: InputDecoration(labelText: 'CO₂ Emissions (kg)'),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
        ElevatedButton(
          child: Text('Save'),
          onPressed: () {
            final newName = _nameCtrl.text.trim();
            if (newName.isEmpty) return;

            // Build inputs list (name, amount, unit) from non-empty fields
            final newInputs = <FlowValue>[];
            for (int i = 0; i < _inputNameCtrls.length; i++) {
              final fname = _inputNameCtrls[i].text.trim();
              final famt = double.tryParse(_inputAmtCtrls[i].text.trim()) ?? 0.0;
              final funit = _inputUnitSelections[i];
              if (fname.isNotEmpty) {
                newInputs.add(FlowValue(name: fname, amount: famt, unit: funit));
              }
            }

            // Build outputs list (name, amount, unit) from non-empty fields
            final newOutputs = <FlowValue>[];
            for (int i = 0; i < _outputNameCtrls.length; i++) {
              final oname = _outputNameCtrls[i].text.trim();
              final oamt =
                  double.tryParse(_outputAmtCtrls[i].text.trim()) ?? 0.0;
              final ounit = _outputUnitSelections[i];
              if (oname.isNotEmpty) {
                newOutputs.add(FlowValue(name: oname, amount: oamt, unit: ounit));
              }
            }

            final newCo2 = double.tryParse(_co2Ctrl.text.trim()) ?? 0.0;

            final updatedNode = widget.original.copyWithFields(
              name: newName,
              inputs: newInputs,
              outputs: newOutputs,
              co2: newCo2,
              // keep the same position
            );
            Navigator.pop(context, updatedNode);
          },
        ),
      ],
    );
  }
}

// /// Page that shows the JSON export of all processes and flows.
// class LCAJsonExportPage extends StatelessWidget {
//   final List<ProcessNode> processes;
//   final List<Map<String, dynamic>> flows;

//   const LCAJsonExportPage({
//     required this.processes,
//     required this.flows,
//   });

//   @override
//   Widget build(BuildContext context) {
//     // Convert processes and flows to a JSON map:
//     final exportMap = {
//       'processes': processes.map((p) => p.toJson()).toList(),
//       'flows': flows.map((f) {
//         return {
//           'from': f['from'],
//           'to': f['to'],
//           // join the names into a single comma-separated string for readability
//           'shared_names': (f['names'] as List<String>).join(', '),
//         };
//       }).toList(),
//     };
//     final jsonString = const JsonEncoder.withIndent('  ').convert(exportMap);

//     return Scaffold(
//       appBar: AppBar(title: Text('LCA JSON Export')),
//       body: Padding(
//         padding: EdgeInsets.all(16),
//         child: SelectableText(
//           jsonString,
//           style: TextStyle(fontFamily: 'monospace', fontSize: 14),
//         ),
//       ),
//     );
//   }
// }
