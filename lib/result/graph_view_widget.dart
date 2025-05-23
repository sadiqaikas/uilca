// // lib/widgets/graph_view_widget.dart

// import 'package:flutter/material.dart';
// import 'package:graphview/GraphView.dart';

// import 'process_node.dart';
// import 'flow_link.dart';
// import 'uncertainty_level.dart';
// import 'grid_layout.dart';
// import 'edge_painter.dart';

// /// Signature for mapping an uncertainty level to a color.
// typedef NodeColorBuilder = Color Function(UncertaintyLevel level);

// /// A zoomable, pannable graph of processes & material flows.
// ///
// /// - [processes] is your list of nodes.
// /// - [flows] is your list of directed edges (material flows).
// /// - [onTapNode] fires when you tap a node.
// /// - [colorOf] maps each node’s uncertainty into a color badge.
// class GraphViewWidget extends StatefulWidget {
//   final List<ProcessNode> processes;
//   final List<FlowLink> flows;
//   final void Function(ProcessNode) onTapNode;
//   final NodeColorBuilder colorOf;
// final String? selectedProcessId;

//   const GraphViewWidget({
//     Key? key,
//     required this.processes,
//     required this.flows,
//     required this.onTapNode,
//     required this.colorOf,
//     this.selectedProcessId,

//   }) : super(key: key);

//   @override
//   _GraphViewWidgetState createState() => _GraphViewWidgetState();
// }

// class _GraphViewWidgetState extends State<GraphViewWidget> {
//   late final Graph _graph;
//   late final GridLayout _layout;
//   final TransformationController _ctrl = TransformationController();

//   @override
//   void initState() {
//     super.initState();
//     _buildGraph();
//   }

//   void _buildGraph() {
//     _graph = Graph();
//     _layout = GridLayout(
//       flows: widget.flows.map((f) => f.toJson()).toList(),
//       nodeW: 200,
//       nodeH: 120,
//       hGap: 120,
//       vGap: 40,
//     );

//     // create nodes
//     final Map<String, Node> nodes = {
//       for (final p in widget.processes) p.id: Node.Id(p.id)
//     };
//     nodes.values.forEach(_graph.addNode);

//     // create invisible edges for layout, then paint them with EdgePainter
//     final invisible = Paint()..color = Colors.transparent;
//     for (final f in widget.flows) {
//       if (f.type == FlowType.material) {
//         final src = nodes[f.from], dst = nodes[f.to];
//         if (src != null && dst != null) {
//           _graph.addEdge(src, dst, paint: invisible);
//         }
//       }
//     }

//     _layout.position(_graph);
//   }

//   @override
//   void didUpdateWidget(covariant GraphViewWidget old) {
//     super.didUpdateWidget(old);
//     // rebuild if data changes
//     if (old.processes != widget.processes || old.flows != widget.flows) {
//       _buildGraph();
//       setState(() {});
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return InteractiveViewer(
//       transformationController: _ctrl,
//       minScale: 0.3,
//       maxScale: 5.0,
//       boundaryMargin: const EdgeInsets.all(double.infinity),
//       child: Stack(
//         children: [
//           // 1) paint edges/arrows
//           CustomPaint(
//             painter: EdgePainter(_graph, _layout),
//             size: Size(_layout.canvasW, _layout.canvasH),
//           ),

//           // 2) overlay process cards
//           ..._graph.nodes.map((node) {
//             final id = node.key!.value as String;
//             final proc = widget.processes.firstWhere((p) => p.id == id);
//             final pos = _layout.posOf(node)!;
//           final isSelected = id == widget.selectedProcessId;

//             return Positioned(
//               left: pos.dx,
//               top: pos.dy,
//               width: _layout.nodeW,
//               height: _layout.nodeH,
//               child: GestureDetector(
//                 onTap: () => widget.onTapNode(proc),
//                 child: _GraphNodeCard(
//                   process: proc,
//                   badgeColor: widget.colorOf(proc.uncertainty),
//                   isSelected: isSelected,

//                 ),
//               ),
//             );
//           }),
//         ],
//       ),
//     );
//   }
// }

// /// A little card with process name + tiny uncertainty badge.
// class _GraphNodeCard extends StatelessWidget {
//   final ProcessNode process;
//   final Color badgeColor;
// final bool isSelected;

//   const _GraphNodeCard({
//     Key? key,
//     required this.process,
//     required this.badgeColor,
//     this.isSelected = false,

//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return Material(
//       elevation: isSelected ? 8 : 6,
//   shape: RoundedRectangleBorder(
//     borderRadius: BorderRadius.circular(12),
//     side: BorderSide(
//       color: isSelected ? Colors.green : Colors.transparent,
//       width: isSelected ? 3 : 1,
//     ),
//   ),
//   color: isSelected ? Colors.green.shade50 : Colors.white,
//   child: Stack(
//     children: [

//           // Main content
//           Padding(
//             padding: const EdgeInsets.all(12.0),
//             child: Center(
//               child: Text(
//                 process.name,
//                 textAlign: TextAlign.center,
//                 style: Theme.of(context).textTheme.titleMedium?.copyWith(
//                       fontWeight: FontWeight.bold,
//                     ),
//               ),
//             ),
//           ),

//           // Uncertainty badge (top-right)
//           Positioned(
//             top: 6,
//             right: 6,
//             child: Container(
//               width: 14,
//               height: 14,
//               decoration: BoxDecoration(
//                 color: badgeColor,
//                 shape: BoxShape.circle,
//                 border: Border.all(color: Colors.white, width: 1.5),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
// lib/widgets/graph_view_widget.dart

// import 'package:flutter/material.dart';
// import 'package:graphview/GraphView.dart';

// import 'process_node.dart';
// import 'flow_link.dart';
// import 'uncertainty_level.dart';
// import 'grid_layout.dart';
// import 'edge_painter.dart';

// /// Signature for mapping an uncertainty level to a color.
// typedef NodeColorBuilder = Color Function(UncertaintyLevel);

// /// A zoomable, pannable graph of processes & material flows.
// ///
// /// - [processes]: list of nodes.
// /// - [flows]: list of directed edges (material flows).
// /// - [onTapNode]: fires when you tap a node.
// /// - [colorOf]: maps each node’s uncertainty into a color badge.
// /// - [selectedProcessId]: id of the currently selected node.
// class GraphViewWidget extends StatefulWidget {
//   final List<ProcessNode> processes;
//   final List<FlowLink> flows;
//   final ValueChanged<ProcessNode> onTapNode;
//   final NodeColorBuilder colorOf;
//   final String? selectedProcessId;

//   const GraphViewWidget({
//     Key? key,
//     required this.processes,
//     required this.flows,
//     required this.onTapNode,
//     required this.colorOf,
//     this.selectedProcessId,
//   }) : super(key: key);

//   @override
//   _GraphViewWidgetState createState() => _GraphViewWidgetState();
// }

// class _GraphViewWidgetState extends State<GraphViewWidget> {
//   late Graph _graph;
//   late GridLayout _layout;
//   final TransformationController _ctrl = TransformationController();

//   static const double _nodeW = 260;
//   static const double _nodeH = 180;
//   static const double _hGap  = 120;
//   static const double _vGap  = 40;

//   @override
//   void initState() {
//     super.initState();
//     _buildGraph();
//   }

//   @override
//   void didUpdateWidget(covariant GraphViewWidget old) {
//     super.didUpdateWidget(old);
//     if (old.processes != widget.processes || old.flows != widget.flows) {
//       _buildGraph();
//       setState(() {});
//     }
//   }

//   void _buildGraph() {
//     _graph = Graph();
//     _layout = GridLayout(
//       flows: widget.flows.map((f) => f.toJson()).toList(),
//       nodeW: _nodeW,
//       nodeH: _nodeH,
//       hGap: _hGap,
//       vGap: _vGap,
//     );

//     final nodes = { for (var p in widget.processes) p.id: Node.Id(p.id) };
//     nodes.values.forEach(_graph.addNode);

//     final invisible = Paint()..color = Colors.transparent;
//     for (var f in widget.flows) {
//       if (f.type == FlowType.material) {
//         final src = nodes[f.from], dst = nodes[f.to];
//         if (src != null && dst != null) {
//           _graph.addEdge(src, dst, paint: invisible);
//         }
//       }
//     }

//     _layout.position(_graph);
//   }

//   @override
//   Widget build(BuildContext context) {
//     return InteractiveViewer(
//       transformationController: _ctrl,
//       constrained: false,
//       boundaryMargin: EdgeInsets.only(
//         left:   _layout.canvasW,
//         right:  _layout.canvasW,
//         top:    _layout.canvasH,
//         bottom: _layout.canvasH,
//       ),
//       clipBehavior: Clip.none,
//       minScale: 0.3,
//       maxScale: 5.0,
//       child: Stack(
//         children: [
//           // Draw edges/arrows
//           CustomPaint(
//             painter: EdgePainter(_graph, _layout),
//             size: Size(_layout.canvasW, _layout.canvasH),
//           ),

//           // Position each process card
//           ..._graph.nodes.map((node) {
//             final id   = node.key!.value as String;
//             final proc = widget.processes.firstWhere((p) => p.id == id);
//             final pos  = _layout.posOf(node)!;
//             final isSelected = id == widget.selectedProcessId;

//             final incoming = widget.flows.where((f) => f.to == id).toList();
//             final outgoing = widget.flows.where((f) => f.from == id).toList();

//             return Positioned(
//               left: pos.dx,
//               top:  pos.dy,
//               width:  _nodeW,
//               // height: _nodeH,
//               child: GestureDetector(
//                 onTap: () => widget.onTapNode(proc),
//                 child: _GraphNodeCard(
//                   process: proc,
//                   badgeColor: widget.colorOf(proc.uncertainty),
//                   isSelected: isSelected,
//                   incoming: incoming,
//                   outgoing: outgoing,
//                 ),
//               ),
//             );
//           }),
//         ],
//       ),
//     );
//   }
// }

// /// A polished card with a **consistent header color**, bold title, badge, and flow-chips.
// class _GraphNodeCard extends StatelessWidget {
//   final ProcessNode process;
//   final Color badgeColor;
//   final bool isSelected;
//   final List<FlowLink> incoming;
//   final List<FlowLink> outgoing;

//   const _GraphNodeCard({
//     Key? key,
//     required this.process,
//     required this.badgeColor,
//     required this.isSelected,
//     required this.incoming,
//     required this.outgoing,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final borderColor = isSelected ? Colors.green.shade800 : Colors.grey.shade300;
//     // **Consistent header background**:
//     final headerColor = Colors.grey.shade100;

//     return Container(
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black26,
//             blurRadius: isSelected ? 8 : 4,
//             offset: const Offset(2, 2),
//           ),
//         ],
//         border: Border.all(color: borderColor, width: isSelected ? 3 : 1),
//       ),
//       clipBehavior: Clip.hardEdge,
//       child: Column(
//         children: [
//           // ── Header with consistent bg ───────────────────
//           Container(
//             color: headerColor,
//             padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//             child: Row(
//               children: [
//                 Container(
//                   width: 14,
//                   height: 14,
//                   decoration: BoxDecoration(
//                     color: badgeColor,
//                     shape: BoxShape.circle,
//                     border: Border.all(color: Colors.white, width: 1.5),
//                   ),
//                 ),
//                 const SizedBox(width: 8),
//                 Expanded(
//                   child: Text(
//                     process.name,
//                     style: Theme.of(context).textTheme.titleMedium?.copyWith(
//                           fontWeight: FontWeight.bold,
//                         ),
//                     overflow: TextOverflow.ellipsis,
//                   ),
//                 ),
//               ],
//             ),
//           ),

//           const Divider(height: 1),

//           // ── Flows ───────────────────────────────────────
// Padding(
//   padding: const EdgeInsets.all(8),
//   child: Column(
//     crossAxisAlignment: CrossAxisAlignment.start,
//     children: [
//       if (incoming.isNotEmpty) ...[
//         _SectionHeader(icon: Icons.call_received, label: 'Inputs'),
//         const SizedBox(height: 4),
//         _FlowChips(flows: incoming, chipColor: Colors.green.shade50),
//         const SizedBox(height: 8),
//       ],
//       if (outgoing.isNotEmpty) ...[
//         _SectionHeader(icon: Icons.call_made, label: 'Outputs'),
//         const SizedBox(height: 4),
//         _FlowChips(flows: outgoing, chipColor: Colors.blue.shade50),
//       ],
//     ],
//   ),
// ),

//         ],
//       ),
//     );
//   }
// }

// /// Small header row with icon + label.
// class _SectionHeader extends StatelessWidget {
//   final IconData icon;
//   final String label;

//   const _SectionHeader({
//     Key? key,
//     required this.icon,
//     required this.label,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       children: [
//         Icon(icon, size: 16, color: Colors.grey.shade600),
//         const SizedBox(width: 6),
//         Text(
//           label,
//           style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
//         ),
//       ],
//     );
//   }
// }

// /// Wrap of Chips for each flow link.
// class _FlowChips extends StatelessWidget {
//   final List<FlowLink> flows;
//   final Color chipColor;

//   const _FlowChips({
//     Key? key,
//     required this.flows,
//     required this.chipColor,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return Wrap(
//       spacing: 6,
//       runSpacing: 4,
//       children: flows.map((f) {
//         return Chip(
//           visualDensity: VisualDensity.compact,
//           backgroundColor: chipColor,
//           label: Text(
//             '${f.name}: ${f.quantity} ${f.unit}',
//             style: Theme.of(context).textTheme.bodySmall,
//           ),
//         );
//       }).toList(),
//     );
//   }
// }
// lib/widgets/graph_view_widget.dart
// lib/widgets/graph_view_widget.dart

import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';

import 'process_node.dart';
import 'flow_link.dart';
import 'uncertainty_level.dart';
import 'grid_layout.dart';
import 'edge_painter.dart';

/// Signature for mapping an uncertainty level to a color.
typedef NodeColorBuilder = Color Function(UncertaintyLevel);

/// A zoomable, pannable graph of processes & material flows—with
/// on-screen zoom controls kept separate from the nodes.
class GraphViewWidget extends StatefulWidget {
  final List<ProcessNode> processes;
  final List<FlowLink> flows;
  final ValueChanged<ProcessNode> onTapNode;
  final NodeColorBuilder colorOf;
  final String? selectedProcessId;

  const GraphViewWidget({
    Key? key,
    required this.processes,
    required this.flows,
    required this.onTapNode,
    required this.colorOf,
    this.selectedProcessId,
  }) : super(key: key);

  @override
  _GraphViewWidgetState createState() => _GraphViewWidgetState();
}

class _GraphViewWidgetState extends State<GraphViewWidget> {
  late Graph _graph;
  late GridLayout _layout;
  final TransformationController _ctrl = TransformationController();

  static const double _nodeW  = 260;
  static const double _nodeH  = 180;
  static const double _hGap   = 120;
  static const double _vGap   = 40;
  static const double _zoomBy = 1.2; // 20% per tap

  @override
  void initState() {
    super.initState();
    _buildGraph();
  }

  @override
  void didUpdateWidget(covariant GraphViewWidget old) {
    super.didUpdateWidget(old);
    if (old.processes != widget.processes || old.flows != widget.flows) {
      _buildGraph();
      setState(() {});
    }
  }

  void _buildGraph() {
    _graph = Graph();
    _layout = GridLayout(
      flows: widget.flows.map((f) => f.toJson()).toList(),
      nodeW: _nodeW,
      nodeH: _nodeH,
      hGap: _hGap,
      vGap: _vGap,
    );
    // Create node objects
    final nodes = { for (var p in widget.processes) p.id: Node.Id(p.id) };
    nodes.values.forEach(_graph.addNode);

    // Invisible edges just for layout
    final invisiblePaint = Paint()..color = Colors.transparent;
    for (var f in widget.flows) {
      if (f.type == FlowType.material) {
        final src = nodes[f.from], dst = nodes[f.to];
        if (src != null && dst != null) {
          _graph.addEdge(src, dst, paint: invisiblePaint);
        }
      }
    }

    _layout.position(_graph);
  }

  void _zoom(double factor) {
    _ctrl.value = _ctrl.value.clone()..scale(factor, factor, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── The pannable, zoomable canvas ──────────────────────────
        InteractiveViewer(
          transformationController: _ctrl,
          constrained: false, // let child size itself
          boundaryMargin: EdgeInsets.only(
            left:   _layout.canvasW,
            right:  _layout.canvasW,
            top:    _layout.canvasH,
            bottom: _layout.canvasH,
          ),
          clipBehavior: Clip.none,
          minScale: 0.3,
          maxScale: 5.0,
          child: Stack(
            children: [
              // 1) Draw all arrows/edges
              CustomPaint(
                painter: EdgePainter(_graph, _layout),
                size: Size(_layout.canvasW, _layout.canvasH),
              ),

              // 2) Position each process card
              ..._graph.nodes.map((node) {
                final id   = node.key!.value as String;
                final proc = widget.processes.firstWhere((p) => p.id == id);
                final pos  = _layout.posOf(node)!;
                final isSel = id == widget.selectedProcessId;

                final incoming = widget.flows.where((f) => f.to == id).toList();
                final outgoing = widget.flows.where((f) => f.from == id).toList();

                return Positioned(
                  left:  pos.dx,
                  top:   pos.dy,
                  width: _nodeW,
                  // No height: let the card size itself to content
                  child: GestureDetector(
                    onTap: () => widget.onTapNode(proc),
                    child: _GraphNodeCard(
                      process: proc,
                      badgeColor: widget.colorOf(proc.uncertainty),
                      isSelected: isSel,
                      incoming: incoming,
                      outgoing: outgoing,
                    ),
                  ),
                );
              }),
            ],
          ),
        ),

        // ── Zoom controls in their own little card ────────────────
        Positioned(
          top: 16,
          right: 16,
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.zoom_in,size: 50,),
                  color: Colors.green,
                  
                  tooltip: 'Zoom In',
                  onPressed: () => _zoom(_zoomBy),
                ),
                IconButton(
                  icon: const Icon(Icons.zoom_out,size: 50,),
                  color: Colors.green,
                  tooltip: 'Zoom Out',
                  onPressed: () => _zoom(1 / _zoomBy),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The same nice card you had before (consistent header, chips, etc.)
class _GraphNodeCard extends StatelessWidget {
  final ProcessNode process;
  final Color badgeColor;
  final bool isSelected;
  final List<FlowLink> incoming;
  final List<FlowLink> outgoing;

  const _GraphNodeCard({
    Key? key,
    required this.process,
    required this.badgeColor,
    required this.isSelected,
    required this.incoming,
    required this.outgoing,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected ? Colors.green.shade800 : Colors.grey.shade300;
    final headerColor = Colors.grey.shade100;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: isSelected ? 8 : 4,
            offset: const Offset(2, 2),
          ),
        ],
        border: Border.all(color: borderColor, width: isSelected ? 3 : 1),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: MainAxisSize.min, // allow dynamic height
        children: [
          // Header
          Container(
            color: badgeColor,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    process.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Flow lists
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (incoming.isNotEmpty) ...[
                  _SectionHeader(icon: Icons.call_received, label: 'Inputs'),
                  const SizedBox(height: 4),
                  _FlowChips(flows: incoming, chipColor: Colors.green.shade50),
                  const SizedBox(height: 8),
                ],
                if (outgoing.isNotEmpty) ...[
                  _SectionHeader(icon: Icons.call_made, label: 'Outputs'),
                  const SizedBox(height: 4),
                  _FlowChips(flows: outgoing, chipColor: Colors.blue.shade50),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({Key? key, required this.icon, required this.label}) : super(key: key);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        ],
      );
}

class _FlowChips extends StatelessWidget {
  final List<FlowLink> flows;
  final Color chipColor;

  const _FlowChips({Key? key, required this.flows, required this.chipColor}) : super(key: key);

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 4,
        children: flows
            .map((f) => Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: chipColor,
                  label: Text('${f.name}: ${f.quantity} ${f.unit}',
                      style: Theme.of(context).textTheme.bodySmall),
                ))
            .toList(),
      );
}
