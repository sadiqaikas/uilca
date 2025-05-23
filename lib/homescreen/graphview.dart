// // lib/pages/process_diagram_page.dart
// import 'package:flutter/material.dart';
// import 'package:graphview/GraphView.dart';

// /// Full‑screen, force‑directed process diagram with rich labels.
// class ProcessDiagramPage extends StatefulWidget {
//   final Map<String, dynamic> lcaResult;
//   const ProcessDiagramPage({Key? key, required this.lcaResult}) : super(key: key);

//   @override
//   State<ProcessDiagramPage> createState() => _ProcessDiagramPageState();
// }

// class _ProcessDiagramPageState extends State<ProcessDiagramPage> {
//   late Graph _graph;
//   late FruchtermanReingoldAlgorithm _algorithm;
//   bool get _hasData {
//     final p = widget.lcaResult['lca_structure']['processes'];
//     final f = widget.lcaResult['lca_structure']['flows'];
//     return p is Map && p.isNotEmpty && f is List && f.isNotEmpty;
//   }

//   @override
//   void initState() {
//     super.initState();
//     _buildGraph();
//   }

//   void _buildGraph() {
//     _graph = Graph();
//     final processes = widget.lcaResult['lca_structure']['processes'] as Map<String, dynamic>;
//     final flows = widget.lcaResult['lca_structure']['flows'] as List<dynamic>;

//     // 1) Create nodes
//     final nodes = <String, Node>{};
//     for (final id in processes.keys) {
//       final node = Node.Id(id);
//       nodes[id] = node;
//       _graph.addNode(node);
//     }

//     // 2) Add edges with per‑edge paint based on uncertainty
//     for (final flow in flows) {
//       final from = flow['from'] as String;
//       final to = flow['to'] as String;
//       final mat = flow['material'] as String;

//       // lookup uncertainty %
//       final inputs = (processes[to]['inputs_materials'] as Map<String, dynamic>?) ?? {};
//       final det = inputs[mat] as Map<String, dynamic>? ?? {};
//       final uncStr = det['uncertainty'] as String? ?? '0%';
//       final unc = int.tryParse(uncStr.replaceAll('%', '')) ?? 0;

//       final paint = Paint()
//         ..color = _colorForUnc(unc)
//         ..strokeWidth = 2;

//       _graph.addEdge(nodes[from]!, nodes[to]!, paint: paint);
//     }

//     // 3) Configure force‑directed algorithm to avoid collisions
//     _algorithm = FruchtermanReingoldAlgorithm(iterations: 500);
//   }

//   Color _colorForUnc(int unc) {
//     if (unc >= 50) return Colors.red.shade600;
//     if (unc >= 25) return Colors.amber.shade700;
//     return Colors.green.shade600;
//   }

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('LCA Process Diagram', style: theme.textTheme.titleLarge),
//         centerTitle: true,
//         elevation: 2,
//       ),
//       body: _hasData
//           ? SizedBox.expand(
//               child: InteractiveViewer(
//                 boundaryMargin: const EdgeInsets.all(20),
//                 minScale: 0.3,
//                 maxScale: 2.5,
//                 child: GraphView(
//                   graph: _graph,
//                   algorithm: _algorithm,
//                   builder: (Node node) {
//                     final id = node.key!.value as String;
//                     final proc = widget.lcaResult['lca_structure']['processes'][id]
//                         as Map<String, dynamic>;
//                     final inputs =
//                         proc['inputs_materials'] as Map<String, dynamic>? ?? {};
//                     final outputs =
//                         proc['outputs_materials'] as Map<String, dynamic>? ?? {};
//                     return _ProcessNode(
//                       id: id,
//                       name: proc['process_name'] as String,
//                       inputs: inputs,
//                       outputs: outputs,
//                     );
//                   },
//                 ),
//               ),
//             )
//           : Center(
//               child: Text(
//                 'No LCA process data available',
//                 style: theme.textTheme.bodyLarge,
//               ),
//             ),
//       floatingActionButton: _hasData
//           ? Stack(
//               children: [
//                 Positioned(
//                   bottom: 16,
//                   right: 16,
//                   child: FloatingActionButton(
//                     heroTag: 'recenter',
//                     tooltip: 'Recenter',
//                     child: const Icon(Icons.center_focus_strong),
//                     onPressed: () => setState(_buildGraph),
//                   ),
//                 ),
//                 Positioned(
//                   bottom: 16,
//                   left: 16,
//                   child: FloatingActionButton.extended(
//                     heroTag: 'legend',
//                     icon: const Icon(Icons.info_outline),
//                     label: const Text('Legend'),
//                     onPressed: _showLegend,
//                   ),
//                 ),
//               ],
//             )
//           : null,
//     );
//   }

//   void _showLegend() {
//     showModalBottomSheet(
//       context: context,
//       backgroundColor: Colors.white,
//       shape: const RoundedRectangleBorder(
//         borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
//       ),
//       builder: (_) => Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(mainAxisSize: MainAxisSize.min, children: const [
//           Text('Edge Uncertainty Legend', style: TextStyle(fontWeight: FontWeight.bold)),
//           SizedBox(height: 12),
//           _LegendItem(color: Colors.red, text: '≥ 50%'),
//           _LegendItem(color: Colors.amber, text: '25–49%'),
//           _LegendItem(color: Colors.green, text: '≤ 24%'),
//           SizedBox(height: 12),
//         ]),
//       ),
//     );
//   }
// }

// /// Richly‑labeled node widget with inputs/outputs as Chips.
// class _ProcessNode extends StatelessWidget {
//   final String id;
//   final String name;
//   final Map<String, dynamic> inputs;
//   final Map<String, dynamic> outputs;

//   const _ProcessNode({
//     Key? key,
//     required this.id,
//     required this.name,
//     required this.inputs,
//     required this.outputs,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final t = Theme.of(context).textTheme;
//     return ConstrainedBox(
//       constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
//       child: Card(
//         elevation: 6,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//         color: Colors.grey.shade50,
//         child: Padding(
//           padding: const EdgeInsets.all(12),
//           child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
//             Text(name, style: t.titleMedium!.copyWith(fontWeight: FontWeight.bold)),
//             const SizedBox(height: 4),
//             Text(id, style: t.bodySmall),
//             if (inputs.isNotEmpty) ...[
//               const Divider(height: 16),
//               const Text('Inputs:', style: TextStyle(fontWeight: FontWeight.w600)),
//               Wrap(
//                 spacing: 6,
//                 runSpacing: 4,
//                 children: inputs.entries.map((e) {
//                   final det = e.value as Map<String, dynamic>;
//                   return Chip(
//                     label: Text('${e.key}: ${det['amount']} ${det['unit']}'),
//                     backgroundColor: Colors.blue.shade50,
//                     visualDensity: VisualDensity.compact,
//                   );
//                 }).toList(),
//               ),
//             ],
//             if (outputs.isNotEmpty) ...[
//               const Divider(height: 16),
//               const Text('Outputs:', style: TextStyle(fontWeight: FontWeight.w600)),
//               Wrap(
//                 spacing: 6,
//                 runSpacing: 4,
//                 children: outputs.entries.map((e) {
//                   final det = e.value as Map<String, dynamic>;
//                   return Chip(
//                     label: Text('${e.key}: ${det['amount']} ${det['unit']}'),
//                     backgroundColor: Colors.green.shade50,
//                     visualDensity: VisualDensity.compact,
//                   );
//                 }).toList(),
//               ),
//             ],
//           ]),
//         ),
//       ),
//     );
//   }
// }

// /// Single legend row.
// class _LegendItem extends StatelessWidget {
//   final Color color;
//   final String text;
//   const _LegendItem({Key? key, required this.color, required this.text}) : super(key: key);

//   @override
//   Widget build(BuildContext context) => Padding(
//         padding: const EdgeInsets.symmetric(vertical: 6),
//         child: Row(children: [
//           Container(width: 20, height: 20, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
//           const SizedBox(width: 12),
//           Text(text),
//         ]),
//       );
// }
// lib/pages/process_diagram_page.dart

// import 'package:flutter/material.dart';
// import 'package:graphview/GraphView.dart';

// /// Full-screen, force-directed process diagram using the
// /// accurate `process_loop` data from your LCA pipeline.
// class ProcessDiagramPage extends StatefulWidget {
//   final Map<String, dynamic> lcaResult;
//   const ProcessDiagramPage({Key? key, required this.lcaResult})
//       : super(key: key);

//   @override
//   State<ProcessDiagramPage> createState() => _ProcessDiagramPageState();
// }

// class _ProcessDiagramPageState extends State<ProcessDiagramPage> {
//   late final List<Map<String, dynamic>> _loopData;
//   late final Map<String, Map<String, dynamic>> _processById;
//   late Graph _graph;
//   late FruchtermanReingoldAlgorithm _algorithm;

//   bool get _hasData => _loopData.isNotEmpty && _processById.isNotEmpty;

//   @override
//   void initState() {
//     super.initState();

//     // 1) Safely extract `process_loop`
//     final raw = widget.lcaResult['process_loop'];
//     if (raw is List) {
//       _loopData = raw
//           .whereType<Map<String, dynamic>>()
//           .toList();
//     } else {
//       _loopData = [];
//     }

//     // 2) Build a lookup: processName -> its full data map
//     _processById = {
//       for (var entry in _loopData)
//         if (entry.containsKey('process'))
//           entry['process'] as String: entry
//     };

//     // 3) Build the graph
//     _buildGraph();
//   }

//   void _buildGraph() {
//     _graph = Graph();
//     _algorithm = FruchtermanReingoldAlgorithm(iterations: 500);

//     if (!_hasData) return;

//     // 1) Create a node for each process
//     final nodes = <String, Node>{};
//     for (final entry in _loopData) {
//       final id = entry['process'] as String;
//       final node = Node.Id(id);
//       nodes[id] = node;
//       _graph.addNode(node);
//     }

//     // 2) For each process, add edges for its inputs
//     for (final entry in _loopData) {
//       final toId = entry['process'] as String;
//       final inputs = entry['inputs'] as List<dynamic>? ?? [];

//       for (final inp in inputs.whereType<Map<String, dynamic>>()) {
//         final fromId = inp['from_process'] as String?;
//         if (fromId != null && nodes.containsKey(fromId)) {
//           // Optional: color/stroke by uncertainty or quantity
//           final paint = Paint()
//             ..color = Colors.green.shade600
//             ..strokeWidth = 2;
//           _graph.addEdge(nodes[fromId]!, nodes[toId]!, paint: paint);
//         }
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);

//     if (!_hasData) {
//       return Scaffold(
//         appBar: AppBar(title: const Text('LCA Process Diagram')),
//         body: Center(
//           child: Text(
//             'No process-loop data available.',
//             style: theme.textTheme.bodyLarge,
//           ),
//         ),
//       );
//     }

//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('LCA Process Diagram'),
//         centerTitle: true,
//       ),
//       body: SizedBox.expand(
//         child: InteractiveViewer(
//           boundaryMargin: const EdgeInsets.all(20),
//           minScale: 0.3,
//           maxScale: 2.5,
//           child: GraphView(
//             graph: _graph,
//             algorithm: _algorithm,
//             builder: (Node node) {
//               final id = node.key!.value as String;
//               final proc = _processById[id]!;

//               // Gather inputs & outputs with quantities
//               final inputs = <String, double>{};
//               for (var inp in (proc['inputs'] as List<dynamic>? ?? [])) {
//                 if (inp is Map<String, dynamic>) {
//                   final name = inp['name'] as String? ?? '(unknown)';
//                   final qty = (inp['quantity'] is num) ? (inp['quantity'] as num).toDouble() : 0.0;
//                   inputs[name] = qty;
//                 }
//               }

//               final outputs = <String, double>{};
//               for (var out in (proc['outputs'] as List<dynamic>? ?? [])) {
//                 if (out is Map<String, dynamic>) {
//                   final name = out['name'] as String? ?? '(unknown)';
//                   final qty = (out['quantity'] is num) ? (out['quantity'] as num).toDouble() : 0.0;
//                   outputs[name] = qty;
//                 }
//               }

//               return _ProcessNode(
//                 id:      id,
//                 name:    id, // or proc['display_name'] if you have one
//                 inputs:  inputs,
//                 outputs: outputs,
//               );
//             },
//           ),
//         ),
//       ),
//       floatingActionButton: _hasData
//           ? FloatingActionButton(
//               tooltip: 'Recenter',
//               child: const Icon(Icons.center_focus_strong),
//               onPressed: () => setState(_buildGraph),
//             )
//           : null,
//     );
//   }
// }

// /// A node widget showing a process name, plus Chips for inputs/outputs.
// class _ProcessNode extends StatelessWidget {
//   final String id;
//   final String name;
//   final Map<String, double> inputs;
//   final Map<String, double> outputs;

//   const _ProcessNode({
//     Key? key,
//     required this.id,
//     required this.name,
//     required this.inputs,
//     required this.outputs,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final t = Theme.of(context).textTheme;
//     return ConstrainedBox(
//       constraints: const BoxConstraints(minWidth: 150, maxWidth: 240),
//       child: Card(
//         elevation: 4,
//         margin: const EdgeInsets.all(6),
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//         child: Padding(
//           padding: const EdgeInsets.all(12),
//           child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
//             Text(name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
//             const SizedBox(height: 4),
//             Text(id, style: t.bodySmall),
//             if (inputs.isNotEmpty) ...[
//               const Divider(height: 16),
//               const Text('Inputs', style: TextStyle(fontWeight: FontWeight.w600)),
//               const SizedBox(height: 4),
//               Wrap(
//                 spacing: 6,
//                 runSpacing: 4,
//                 children: inputs.entries.map((e) {
//                   return Chip(
//                     label: Text('${e.key}: ${e.value.toStringAsFixed(2)}'),
//                     backgroundColor: Colors.blue.shade50,
//                   );
//                 }).toList(),
//               ),
//             ],
//             if (outputs.isNotEmpty) ...[
//               const Divider(height: 16),
//               const Text('Outputs', style: TextStyle(fontWeight: FontWeight.w600)),
//               const SizedBox(height: 4),
//               Wrap(
//                 spacing: 6,
//                 runSpacing: 4,
//                 children: outputs.entries.map((e) {
//                   return Chip(
//                     label: Text('${e.key}: ${e.value.toStringAsFixed(2)}'),
//                     backgroundColor: Colors.green.shade50,
//                   );
//                 }).toList(),
//               ),
//             ],
//           ]),
//         ),
//       ),
//     );
//   }
// }

// lib/pages/process_diagram_page.dart

// import 'package:flutter/material.dart';
// import 'package:graphview/GraphView.dart';

// /// Full-screen, force-directed process diagram driven
// /// entirely by the accurate `process_loop` data from LCA.
// class ProcessDiagramPage extends StatefulWidget {
//   final Map<String, dynamic> lcaResult;
//   const ProcessDiagramPage({Key? key, required this.lcaResult})
//       : super(key: key);

//   @override
//   State<ProcessDiagramPage> createState() => _ProcessDiagramPageState();
// }

// class _ProcessDiagramPageState extends State<ProcessDiagramPage> {
//   late final List<Map<String, dynamic>> _loopData;
//   late final Map<String, Map<String, dynamic>> _procByName;
//   late final Graph _graph;
//   late final FruchtermanReingoldAlgorithm _algo;

//   bool get _hasData => _loopData.isNotEmpty && _procByName.isNotEmpty;

//   @override
//   void initState() {
//     super.initState();
//     // 1) Extract process_loop safely
//     final rawLoop = widget.lcaResult['process_loop'];
//     if (rawLoop is List) {
//       _loopData = rawLoop.whereType<Map<String, dynamic>>().toList();
//     } else {
//       _loopData = [];
//     }
//     // 2) Build a name→entry lookup
//     _procByName = {
//       for (var e in _loopData)
//         if (e.containsKey('process')) e['process'] as String: e
//     };
//     // 3) Build the Graph once
//     _buildGraph();
//   }

//   void _buildGraph() {
//     _graph = Graph();
//     _algo = FruchtermanReingoldAlgorithm(iterations: 400);

//     if (!_hasData) return;

//     // A) Create nodes
//     final nodes = <String, Node>{};
//     for (var entry in _loopData) {
//       final name = entry['process'] as String;
//       final node = Node.Id(name);
//       nodes[name] = node;
//       _graph.addNode(node);
//     }

//     // B) Build producer lookup from outputs
//     final producerOf = <String, String>{};
//     for (var entry in _loopData) {
//       final procName = entry['process'] as String;
//       for (var out in (entry['outputs'] as List<dynamic>? ?? [])) {
//         if (out is Map<String, dynamic> && out.containsKey('name')) {
//           producerOf[out['name'] as String] = procName;
//         }
//       }
//     }

//     // C) Add directed edges for each input
//     for (var entry in _loopData) {
//       final toName = entry['process'] as String;
//       for (var inp in (entry['inputs'] as List<dynamic>? ?? [])) {
//         if (inp is Map<String, dynamic> && inp.containsKey('name')) {
//           // Prefer explicit link, else use producerOf
//           String? fromName = inp['from_process'] as String?;
//           fromName ??= producerOf[inp['name'] as String];

//           if (fromName != null && nodes.containsKey(fromName)) {
//             final paint = Paint()
//               ..color = Colors.black54
//               ..strokeWidth = 2;
//             // arrowPaint for the arrow head
//             final arrow = Paint()
//               ..color = Colors.black54
//               ..strokeWidth = 2;
//             _graph.addEdge(
//   nodes[fromName]!,
//   nodes[toName]!,
//   paint: paint,
// );

//           }
//         }
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     if (!_hasData) {
//       return Scaffold(
//         appBar: AppBar(title: const Text('LCA Process Diagram')),
//         body: Center(
//           child: Text('No process_loop data available.', style: theme.textTheme.bodyLarge),
//         ),
//       );
//     }

//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('LCA Process Diagram'),
//         centerTitle: true,
//       ),
//       body: InteractiveViewer(
//         boundaryMargin: const EdgeInsets.all(16),
//         minScale: 0.3,
//         maxScale: 2.5,
//         child: GraphView(
//           graph: _graph,
//           algorithm: _algo,
//           builder: (Node node) {
//             final id = node.key!.value as String;
//             final proc = _procByName[id]!;
//             // Gather inputs
//             final inputs = <String, String>{};
//             for (var inp in (proc['inputs'] as List<dynamic>? ?? [])) {
//               if (inp is Map<String, dynamic>) {
//                 final nm = inp['name'] as String? ?? '(?)';
//                 final qty = inp['quantity'] ?? 0;
//                 final unit = inp['unit'] ?? '';
//                 inputs[nm] = '$qty $unit';
//               }
//             }
//             // Gather outputs
//             final outputs = <String, String>{};
//             for (var out in (proc['outputs'] as List<dynamic>? ?? [])) {
//               if (out is Map<String, dynamic>) {
//                 final nm = out['name'] as String? ?? '(?)';
//                 final qty = out['quantity'] ?? 0;
//                 final unit = out['unit'] ?? '';
//                 outputs[nm] = '$qty $unit';
//               }
//             }
//             return _ProcessNode(
//               id: id,
//               name: id, // or display a prettier label if you like
//               inputs: inputs,
//               outputs: outputs,
//             );
//           },
//         ),
//       ),
//       floatingActionButton: FloatingActionButton(
//         tooltip: 'Recenter',
//         child: const Icon(Icons.center_focus_strong),
//         onPressed: () => setState(_buildGraph),
//       ),
//     );
//   }
// }

// /// Node widget showing exact inputs & outputs with units.
// class _ProcessNode extends StatelessWidget {
//   final String id, name;
//   final Map<String, String> inputs, outputs;
//   const _ProcessNode({
//     Key? key,
//     required this.id,
//     required this.name,
//     required this.inputs,
//     required this.outputs,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final t = Theme.of(context).textTheme;
//     return ConstrainedBox(
//       constraints: const BoxConstraints(minWidth: 160, maxWidth: 260),
//       child: Card(
//         elevation: 4,
//         margin: const EdgeInsets.all(6),
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//         child: Padding(
//           padding: const EdgeInsets.all(12),
//           child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//             Text(name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
//             const SizedBox(height: 4),
//             Text(id, style: t.bodySmall),
//             if (inputs.isNotEmpty) ...[
//               const Divider(height: 16),
//               const Text('Inputs', style: TextStyle(fontWeight: FontWeight.w600)),
//               const SizedBox(height: 4),
//               ...inputs.entries.map((e) => Text('• ${e.key}: ${e.value}',
//                   style: const TextStyle(fontSize: 13))),
//             ],
//             if (outputs.isNotEmpty) ...[
//               const Divider(height: 16),
//               const Text('Outputs', style: TextStyle(fontWeight: FontWeight.w600)),
//               const SizedBox(height: 4),
//               ...outputs.entries.map((e) => Text('• ${e.key}: ${e.value}',
//                   style: const TextStyle(fontSize: 13))),
//             ],
//           ]),
//         ),
//       ),
//     );
//   }
// }


// import 'package:flutter/material.dart';
// import 'package:graphview/GraphView.dart';

// /// Full-screen, force-directed process diagram driven
// /// by your Brightway flows and the three core processes.
// class ProcessDiagramPage extends StatefulWidget {
//   final Map<String, dynamic> lcaResult;
//   const ProcessDiagramPage({Key? key, required this.lcaResult})
//       : super(key: key);

//   @override
//   State<ProcessDiagramPage> createState() => _ProcessDiagramPageState();
// }

// class _ProcessDiagramPageState extends State<ProcessDiagramPage> {
//   late final List<String> _processes;
//   late final List<Map<String, dynamic>> _flows;
//   late Graph _graph;
//   late FruchtermanReingoldAlgorithm _algorithm;

//   bool get _hasData => _processes.isNotEmpty && _flows.isNotEmpty;

//   @override
//   void initState() {
//     super.initState();

//     // 1️⃣ Extract exactly the three process names from your payload
//     final rawProcs = widget.lcaResult['processes'];
//     if (rawProcs is List) {
//       _processes = rawProcs
//           .whereType<Map<String, dynamic>>()
//           .map((m) => m['name'] as String)
//           .toList();
//     } else {
//       _processes = [];
//     }

//     // 2️⃣ Pull the technosphere/biosphere flows from inside brightway_result
//     final brightway = widget.lcaResult['brightway_result'];
//     if (brightway is Map<String, dynamic> &&
//         brightway['brightway_flows'] is List) {
//       _flows = (brightway['brightway_flows'] as List)
//           .whereType<Map<String, dynamic>>()
//           .map((f) {
//             // Make every amount positive for display
//             final amt = (f['amount'] as num).abs();
//             return {
//               'type':         f['type']         as String? ?? '',
//               'from_process': f['from_process'] as String? ?? '',
//               'to_process':   f['to_process']   as String? ?? '',
//               'flow_name':    f['flow_name']    as String? ?? '',
//               'amount':       amt,
//               'unit':         f['unit']         as String? ?? '',
//             };
//           })
//           // Only keep edges that connect two of your core processes
//           .where((f) =>
//               _processes.contains(f['from_process']) &&
//               _processes.contains(f['to_process']))
//           .toList();
//     } else {
//       _flows = [];
//     }

//     // 3️⃣ Build the Graph object
//     _buildGraph();
//   }

//   void _buildGraph() {
//     _graph = Graph();
//     _algorithm = FruchtermanReingoldAlgorithm(iterations: 400);

//     if (!_hasData) return;

//     // A) Create one Node per process
//     final nodes = <String, Node>{};
//     for (final name in _processes) {
//       final node = Node.Id(name);
//       nodes[name] = node;
//       _graph.addNode(node);
//     }

//     // B) Add an edge for each technosphere flow
//     for (final f in _flows) {
//       if (f['type'] == 'technosphere') {
//         final from = f['from_process'] as String;
//         final to   = f['to_process']   as String;
//         if (nodes.containsKey(from) && nodes.containsKey(to)) {
//           final paint = Paint()
//             ..color = Colors.blueGrey
//             ..strokeWidth = 2;
//           _graph.addEdge(nodes[from]!, nodes[to]!, paint: paint);
//         }
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     if (!_hasData) {
//       return Scaffold(
//         appBar: AppBar(title: const Text('LCA Process Diagram')),
//         body: Center(
//           child: Text('No data to display.', style: theme.textTheme.bodyLarge),
//         ),
//       );
//     }

//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('LCA Process Diagram'),
//         centerTitle: true,
//       ),
//       body: InteractiveViewer(
//         boundaryMargin: const EdgeInsets.all(16),
//         minScale: 0.3,
//         maxScale: 2.5,
//         child: GraphView(
//           graph: _graph,
//           algorithm: _algorithm,
//           builder: (Node node) {
//             final id = node.key!.value as String;

//             // Gather all inputs that terminate here
//             final inputs = <String, String>{};
//             for (final f in _flows) {
//               if (f['type'] == 'technosphere' && f['to_process'] == id) {
//                 inputs[f['flow_name'] as String] =
//                     '${f['amount']} ${f['unit']}';
//               }
//             }

//             // Gather all outputs that originate here
//             final outputs = <String, String>{};
//             for (final f in _flows) {
//               if (f['type'] == 'technosphere' && f['from_process'] == id) {
//                 outputs[f['flow_name'] as String] =
//                     '${f['amount']} ${f['unit']}';
//               }
//             }

//             return _ProcessNode(
//               name: id,
//               inputs: inputs,
//               outputs: outputs,
//             );
//           },
//         ),
//       ),
//       floatingActionButton: FloatingActionButton(
//         tooltip: 'Recenter',
//         child: const Icon(Icons.center_focus_strong),
//         onPressed: () => setState(_buildGraph),
//       ),
//     );
//   }
// }

// /// A small card showing exactly what enters and leaves each process.
// class _ProcessNode extends StatelessWidget {
//   final String name;
//   final Map<String, String> inputs;
//   final Map<String, String> outputs;

//   const _ProcessNode({
//     Key? key,
//     required this.name,
//     required this.inputs,
//     required this.outputs,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final t = Theme.of(context).textTheme;
//     return ConstrainedBox(
//       constraints: const BoxConstraints(minWidth: 150, maxWidth: 240),
//       child: Card(
//         elevation: 4,
//         margin: const EdgeInsets.all(6),
//         shape:
//             RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//         child: Padding(
//           padding: const EdgeInsets.all(12),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(name,
//                   style:
//                       t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
//               const SizedBox(height: 8),
//               if (inputs.isNotEmpty) ...[
//                 const Text('Inputs:',
//                     style: TextStyle(fontWeight: FontWeight.w600)),
//                 ...inputs.entries.map((e) => Text('• ${e.key}: ${e.value}',
//                     style: const TextStyle(fontSize: 13))),
//                 const SizedBox(height: 8),
//               ],
//               if (outputs.isNotEmpty) ...[
//                 const Text('Outputs:',
//                     style: TextStyle(fontWeight: FontWeight.w600)),
//                 ...outputs.entries.map((e) => Text('• ${e.key}: ${e.value}',
//                     style: const TextStyle(fontSize: 13))),
//               ],
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
// i

// // working code
// import 'dart:math' as math;
// import 'package:flutter/material.dart';
// import 'package:graphview/GraphView.dart';

// /// A full‐screen, custom “grid‐layer” LCA diagram with visible flows.
// ///
// /// * Fixed node size 200×120px.
// /// * Columns = life‐cycle stages (cradle→grave).
// /// * Rows ordered by median heuristic to reduce crossings.
// /// * Edges painted as orthogonal H–V–H polylines with arrow‐heads.
// /// * All positions stored in GridLayout, not in node.data.
// class ProcessDiagramPage extends StatefulWidget {
//   final Map<String, dynamic> lcaResult;
//   const ProcessDiagramPage({Key? key, required this.lcaResult}) : super(key: key);

//   @override
//   State<ProcessDiagramPage> createState() => _ProcessDiagramPageState();
// }

// class _ProcessDiagramPageState extends State<ProcessDiagramPage> {
//   static const double nodeW = 200, nodeH = 120, hGap = 120, vGap = 40;

//   late final List<Map<String, dynamic>> _flows;
//   late final List<String> _processes;
//   late final Graph _graph;
//   late final GridLayout _layout;

//   bool get _hasData => _processes.isNotEmpty && _flows.isNotEmpty;

//   @override
//   void initState() {
//     super.initState();
//     final raw = widget.lcaResult['flows_enriched'] ?? widget.lcaResult['flows_linked'];
//     _flows = raw is List ? raw.cast<Map<String, dynamic>>() : const [];

//     final names = <String>{};
//     for (final f in _flows) {
//       names.add(f['from_process']?.toString() ?? '');
//       names.add(f['to_process']?.toString() ?? '');
//     }
//     names.removeWhere((s) => s.isEmpty);
//     _processes = names.toList()..sort();

//     _buildGraph();
//   }

//   void _buildGraph() {
//     _graph = Graph();
//     _layout = GridLayout(
//       flows: _flows,
//       nodeW: nodeW,
//       nodeH: nodeH,
//       hGap: hGap,
//       vGap: vGap,
//     );

//     final nodes = <String, Node>{};
//     for (final p in _processes) {
//       final n = Node.Id(p);
//       nodes[p] = n;
//       _graph.addNode(n);
//     }

//     final edgePaint = Paint()..color = Colors.transparent;
//     for (final f in _flows) {
//       if (f['flow_type'] != 'material') continue;
//       final s = nodes[f['from_process']], t = nodes[f['to_process']];
//       if (s != null && t != null) {
//         _graph.addEdge(s, t, paint: edgePaint);
//       }
//     }

//     _layout.position(_graph);
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (!_hasData) {
//       return Scaffold(
//         appBar: AppBar(title: const Text('LCA Process Diagram')),
//         body: const Center(child: Text('No process data to display.')),
//       );
//     }

//     return Scaffold(
//       appBar: AppBar(title: const Text('LCA Process Diagram'), centerTitle: true),
//       body: InteractiveViewer(
//         boundaryMargin: const EdgeInsets.all(80),
//         minScale: 0.3,
//         maxScale: 2.5,
//         child: CustomPaint(
//           painter: _EdgePainter(_graph, _layout),
//           child: SizedBox(
//             width: _layout.canvasW,
//             height: _layout.canvasH,
//             child: Stack(
//               children: _graph.nodes.map((n) {
//                 final pos = _layout.posOf(n)!;
//                 final id = n.key!.value as String;

//                 final ins = <String, String>{}, outs = <String, String>{};
//                 for (final f in _flows) {
//                   if (f['flow_type'] != 'material') continue;
//                   final name = f['name']?.toString() ?? '';
//                   final qty = f['quantity'];
//                   final unit = f['unit']?.toString() ?? '';
//                   final txt = qty == null ? unit : '$qty $unit';
//                   if (f['to_process'] == id) ins[name] = txt;
//                   if (f['from_process'] == id) outs[name] = txt;
//                 }

//                 return Positioned(
//                   left: pos.dx,
//                   top: pos.dy,
//                   width: nodeW,
//                   height: nodeH,
//                   child: _ProcessCard(name: id, ins: ins, outs: outs),
//                 );
//               }).toList(),
//             ),
//           ),
//         ),
//       ),
//       floatingActionButton: FloatingActionButton(
//         tooltip: 'Re-center',
//         child: const Icon(Icons.center_focus_strong),
//         onPressed: () => setState(_buildGraph),
//       ),
//     );
//   }
// }

// class _ProcessCard extends StatelessWidget {
//   final String name;
//   final Map<String, String> ins, outs;
//   const _ProcessCard({required this.name, required this.ins, required this.outs});

//   @override
//   Widget build(BuildContext context) {
//     final t = Theme.of(context).textTheme;
//     return Material(
//       elevation: 4,
//       borderRadius: BorderRadius.circular(12),
//       child: Padding(
//         padding: const EdgeInsets.all(10),
//         child: DefaultTextStyle(
//           style: const TextStyle(fontSize: 12),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
//               const SizedBox(height: 6),
//               if (ins.isNotEmpty) ...[
//                 const Text('Inputs:', style: TextStyle(fontWeight: FontWeight.w600)),
//                 for (final e in ins.entries) Text('• ${e.key}: ${e.value}'),
//                 const SizedBox(height: 4),
//               ],
//               if (outs.isNotEmpty) ...[
//                 const Text('Outputs:', style: TextStyle(fontWeight: FontWeight.w600)),
//                 for (final e in outs.entries) Text('• ${e.key}: ${e.value}'),
//               ],
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// class GridLayout {
//   GridLayout({
//     required this.flows,
//     required this.nodeW,
//     required this.nodeH,
//     required this.hGap,
//     required this.vGap,
//   });

//   final List<Map<String, dynamic>> flows;
//   final double nodeW, nodeH, hGap, vGap;
//   final Map<Node, Offset> _pos = {};
//   double canvasW = 0, canvasH = 0;

//   Offset? posOf(Node n) => _pos[n];

//   void position(Graph g) {
//     _pos.clear();

//     final succ = <String, Set<String>>{};
//     final pred = <String, Set<String>>{};
//     for (final n in g.nodes) {
//       final id = n.key!.value as String;
//       succ[id] = {};
//       pred[id] = {};
//     }
//     for (final e in g.edges) {
//       final a = e.source.key!.value as String;
//       final b = e.destination.key!.value as String;
//       succ[a]!.add(b);
//       pred[b]!.add(a);
//     }

//     final level = <String, int>{};
//     final queue = <String>[];

//     succ.keys.forEach((id) {
//       if (pred[id]!.isEmpty) {
//         level[id] = 0;
//         queue.add(id);
//       }
//     });
//     if (queue.isEmpty) {
//       final first = succ.keys.first;
//       level[first] = 0;
//       queue.add(first);
//     }
//     while (queue.isNotEmpty) {
//       final u = queue.removeAt(0), base = level[u]!;
//       for (final v in succ[u]!) {
//         final cand = base + 1;
//         if (level[v] == null || cand > level[v]!) level[v] = cand;
//         queue.add(v);
//       }
//     }

//     final cols = <int, List<String>>{};
//     level.forEach((id, lv) => cols.putIfAbsent(lv, () => []).add(id));

//     void sweep(bool ltr) {
//       final keys = cols.keys.toList()..sort();
//       if (!ltr) keys.reversed;
//       for (final c in keys) {
//         final list = cols[c]!;
//         list.sort((a, b) {
//           double median(String id) {
//             final neigh = ltr ? pred[id]! : succ[id]!;
//             if (neigh.isEmpty) return 0;
//             final idxs = neigh.map((n) {
//               final lv = level[n]!;
//               return cols[lv]!.indexOf(n).toDouble();
//             }).toList()..sort();
//             return idxs[idxs.length ~/ 2];
//           }
//           return median(a).compareTo(median(b));
//         });
//       }
//     }
//     sweep(true);
//     sweep(false);

//     double maxX = 0, maxY = 0;
//     for (final c in cols.keys) {
//       final list = cols[c]!;
//       for (var r = 0; r < list.length; r++) {
//         final id = list[r];
//         final node = g.getNodeUsingId(id)!;
//         final x = c * (nodeW + hGap), y = r * (nodeH + vGap);
//         final off = Offset(x, y);
//         _pos[node] = off;
//         maxX = math.max(maxX, x);
//         maxY = math.max(maxY, y);
//       }
//     }
//     canvasW = maxX + nodeW + hGap;
//     canvasH = maxY + nodeH + vGap;
//   }
// }

// class _EdgePainter extends CustomPainter {
//   _EdgePainter(this.g, this.layout);
//   final Graph g;
//   final GridLayout layout;

//   @override
//   void paint(Canvas canvas, Size size) {
//     final paint = Paint()
//       ..color = Colors.blueGrey.shade400
//       ..strokeWidth = 2
//       ..style = PaintingStyle.stroke;

//     for (final e in g.edges) {
//       final sOff = layout.posOf(e.source)!;
//       final tOff = layout.posOf(e.destination)!;

//       final x1 = sOff.dx + _ProcessDiagramPageState.nodeW;
//       final y1 = sOff.dy + _ProcessDiagramPageState.nodeH / 2;
//       final x4 = tOff.dx;
//       final y4 = tOff.dy + _ProcessDiagramPageState.nodeH / 2;
//       final mx = (x1 + x4) / 2;

//       final path = Path()
//         ..moveTo(x1, y1)
//         ..lineTo(mx, y1)
//         ..lineTo(mx, y4)
//         ..lineTo(x4, y4);
//       canvas.drawPath(path, paint);

//       const ah = 6.0, aw = 5.0;
//       final arrow = Path()
//         ..moveTo(x4, y4)
//         ..lineTo(x4 - ah, y4 - aw)
//         ..lineTo(x4 - ah, y4 + aw)
//         ..close();
//       canvas.drawPath(arrow, paint..style = PaintingStyle.fill);
//       paint.style = PaintingStyle.stroke;
//     }
//   }

//   @override
//   bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
// }

// works also

// // lib/homescreen/graphview.dart
// import 'dart:math' as math;
// import 'package:flutter/material.dart';
// import 'package:graphview/GraphView.dart';
// import 'package:fl_chart/fl_chart.dart';

// // ────────────── TWEAKABLE CONSTANTS ──────────────────────────────
// const double nodeW = 200, nodeH = 120, hGap = 120, vGap = 40;

// /// Full LCA page: grid-layer process graph + CO₂ bar chart.
// class ProcessDiagramPage extends StatefulWidget {
//   final Map<String, dynamic> lcaResult;
//   const ProcessDiagramPage({Key? key, required this.lcaResult}) : super(key: key);

//   @override
//   State<ProcessDiagramPage> createState() => _ProcessDiagramPageState();
// }

// class _ProcessDiagramPageState extends State<ProcessDiagramPage> {
//   late final List<Map<String, dynamic>> _flows;
//   late final List<String> _processes;
//   late final Graph _graph;
//   late final GridLayout _layout;

//   late final double _totalCo2;                       // kg CO₂e (≥0)
//   late final Map<String, double> _perProcessCo2;     // kg CO₂e per process
//   late final String _method;                         // method label

//   bool get _hasData => _processes.isNotEmpty && _flows.isNotEmpty;

//   // ───────────────────────────────────────────── initState
//   @override
//   void initState() {
//     super.initState();

//     // 1. choose flows
//     final raw = widget.lcaResult['flows_enriched'] ??
//         widget.lcaResult['flows_linked'];
//     _flows = raw is List ? raw.cast<Map<String, dynamic>>() : const [];

//     // 2. process names
//     final names = <String>{};
//     for (final f in _flows) {
//       names.add(f['from_process']?.toString() ?? '');
//       names.add(f['to_process']?.toString() ?? '');
//     }
//     names.removeWhere((s) => s.isEmpty);
//     _processes = names.toList()..sort();

//     // 3. LCA method label
//     _method = widget.lcaResult['method']?.toString() ?? 'Unknown method';

//     // 4. CO₂ impacts
//     final impacts = _computeImpacts();   // (total, perProcess)
//     _totalCo2     = impacts.$1;
//     _perProcessCo2 = impacts.$2;

//     // 5. build graph
//     _buildGraph();
//   }

//   /// Returns a Dart 3.x record: (total, map<process,impact>)
//   (double, Map<String, double>) _computeImpacts() {
//     final map = <String, double>{};
//     double total = 0;

//     // If backend already supplies impacts per process, prefer that
//     if (widget.lcaResult['process_impacts'] is Map) {
//       final m = widget.lcaResult['process_impacts'] as Map;
//       m.forEach((k, v) {
//         final d = (v as num).toDouble().clamp(0, double.infinity);
// map[k.toString()] = (v as num).toDouble();
//         total += d;
//       });
//       return (total, map);
//     }

//     // Fallback: sum emission flows whose name contains "co2"
//     for (final f in _flows) {
//       if (f['flow_type'] != 'emission') continue;
//       final name = (f['name'] ?? '').toString().toLowerCase();
//       if (!name.contains('co2')) continue;

//       final qty = (f['quantity'] as num?)?.toDouble() ?? 0;
//       if (qty <= 0) continue;

//       final proc = f['from_process']?.toString() ?? 'Unknown';
//       map[proc] = (map[proc] ?? 0) + qty;
//       total    += qty;
//     }
//     return (total, map);
//   }

//   void _buildGraph() {
//     _graph  = Graph();
//     _layout = GridLayout(
//       flows: _flows,
//       nodeW: nodeW,
//       nodeH: nodeH,
//       hGap : hGap,
//       vGap : vGap,
//     );

//     // nodes
//     final nodes = <String, Node>{};
//     for (final p in _processes) {
//       final n = Node.Id(p);
//       nodes[p] = n;
//       _graph.addNode(n);
//     }

//     // edges (material) – invisible, we paint custom later
//     final transparent = Paint()..color = Colors.transparent;
//     for (final f in _flows) {
//       if (f['flow_type'] != 'material') continue;
//       final s = nodes[f['from_process']], t = nodes[f['to_process']];
//       if (s != null && t != null) _graph.addEdge(s, t, paint: transparent);
//     }

//     _layout.position(_graph);
//   }

//   // ───────────────────────────────────────────── build
//   @override
//   Widget build(BuildContext context) {
//     if (!_hasData) {
//       return Scaffold(
//         appBar: AppBar(title: const Text('LCA Diagram')),
//         body: const Center(child: Text('No process data to display.')),
//       );
//     }

//     return Scaffold(
//       appBar: AppBar(
//         title: Text('$_method – Global Warming Potential'),
//         centerTitle: true,
//       ),
//       body: Column(
//         children: [
//           // ── GRID DIAGRAM ───────────────────────────────
//           Expanded(
//             flex: 3,
//             child: InteractiveViewer(
//               boundaryMargin: const EdgeInsets.all(80),
//               minScale: 0.3,
//               maxScale: 2.5,
//               child: CustomPaint(
//                 painter: _EdgePainter(_graph, _layout),
//                 child: SizedBox(
//                   width: _layout.canvasW,
//                   height: _layout.canvasH,
//                   child: Stack(
//                     children: _graph.nodes.map((n) {
//                       final pos = _layout.posOf(n)!;
//                       final id  = n.key!.value as String;

//                       final ins = <String, String>{}, outs = <String, String>{};
//                       for (final f in _flows) {
//                         if (f['flow_type'] != 'material') continue;
//                         final fname = f['name']?.toString() ?? '';
//                         final qty   = f['quantity'];
//                         final unit  = f['unit']?.toString() ?? '';
//                         final txt   = qty == null ? unit : '$qty $unit';
//                         if (f['to_process']   == id) ins [fname] = txt;
//                         if (f['from_process'] == id) outs[fname] = txt;
//                       }

//                       return Positioned(
//                         left: pos.dx,
//                         top : pos.dy,
//                         width: nodeW,
//                         height: nodeH,
//                         child: _ProcessCard(name: id, ins: ins, outs: outs),
//                       );
//                     }).toList(),
//                   ),
//                 ),
//               ),
//             ),
//           ),

//           // ── BAR CHART ──────────────────────────────────
//           Expanded(
//             flex: 2,
//             child: _ImpactBarChart(total: _totalCo2, perProc: _perProcessCo2),
//           ),
//         ],
//       ),
//       floatingActionButton: FloatingActionButton(
//         tooltip: 'Re-center',
//         child : const Icon(Icons.center_focus_strong),
//         onPressed: () => setState(_buildGraph),
//       ),
//     );
//   }
// }

// ////////////////////////////////////////////////////////////////
// ///  CARD  (scroll lists ⇒ no overflow)
// class _ProcessCard extends StatelessWidget {
//   final String name;
//   final Map<String, String> ins, outs;
//   const _ProcessCard({required this.name, required this.ins, required this.outs});

//   @override
//   Widget build(BuildContext context) => Material(
//         elevation: 4,
//         borderRadius: BorderRadius.circular(12),
//         child: Padding(
//           padding: const EdgeInsets.all(10),
//           child: DefaultTextStyle(
//             style: const TextStyle(fontSize: 12, overflow: TextOverflow.ellipsis),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(name,
//                     style: Theme.of(context)
//                         .textTheme
//                         .titleMedium
//                         ?.copyWith(fontWeight: FontWeight.bold),
//                     maxLines: 1,
//                     overflow: TextOverflow.ellipsis),
//                 const SizedBox(height: 4),
//                 if (ins.isNotEmpty) ...[
//                   const Text('Inputs:',
//                       style: TextStyle(fontWeight: FontWeight.w600)),
//                   Flexible(
//                     child: ListView(
//                       padding: EdgeInsets.zero,
//                       children: ins.entries
//                           .map((e) => Text('• ${e.key}: ${e.value}',
//                               maxLines: 1, overflow: TextOverflow.ellipsis))
//                           .toList(),
//                     ),
//                   ),
//                   const SizedBox(height: 4),
//                 ],
//                 if (outs.isNotEmpty) ...[
//                   const Text('Outputs:',
//                       style: TextStyle(fontWeight: FontWeight.w600)),
//                   Flexible(
//                     child: ListView(
//                       padding: EdgeInsets.zero,
//                       children: outs.entries
//                           .map((e) => Text('• ${e.key}: ${e.value}',
//                               maxLines: 1, overflow: TextOverflow.ellipsis))
//                           .toList(),
//                     ),
//                   ),
//                 ],
//               ],
//             ),
//           ),
//         ),
//       );
// }

// ////////////////////////////////////////////////////////////////
// ///  BAR CHART  (fl_chart)
// class _ImpactBarChart extends StatelessWidget {
//   const _ImpactBarChart({required this.total, required this.perProc});
//   final double total;
//   final Map<String, double> perProc;

//   @override
//   Widget build(BuildContext context) {
//     // build bar groups
//     final bars = <BarChartGroupData>[];

//     final totalColor = Theme.of(context).colorScheme.primary;
//     final procColor  = Theme.of(context).colorScheme.secondary;

//     // 0 = TOTAL
//     bars.add(BarChartGroupData(
//       x: 0,
//       barRods: [
//         BarChartRodData(
//           toY: total,
//           color: totalColor,
//           width: 16,
//           borderRadius: BorderRadius.circular(3),
//         ),
//       ],
//     ));

//     // per-process (desc)
//     var idx = 1;
//     final sorted = perProc.entries.toList()
//       ..sort((a, b) => b.value.compareTo(a.value));
//     for (final e in sorted) {
//       bars.add(BarChartGroupData(
//         x: idx++,
//         barRods: [
//           BarChartRodData(
//             toY: e.value,
//             color: procColor,
//             width: 12,
//             borderRadius: BorderRadius.circular(3),
//           ),
//         ],
//       ));
//     }

//     // y-axis max & interval
//     final maxY = (total * 1.25).clamp(10.0, double.infinity);
//     final interval = (maxY / 4).ceilToDouble();        // nice ~¼ steps

//     // axis labels
//     FlTitlesData titles = FlTitlesData(
//       bottomTitles: AxisTitles(
//         sideTitles: SideTitles(
//           showTitles: true,
//           getTitlesWidget: (double value, TitleMeta meta) {
//             if (value == 0) {
//               return const Text('TOTAL', style: TextStyle(fontSize: 10));
//             }
//             final i = value.toInt() - 1;
//             if (i < 0 || i >= sorted.length) return const SizedBox.shrink();
//             final lbl = sorted[i].key;
//             return Text(
//               lbl.length > 8 ? '${lbl.substring(0, 8)}…' : lbl,
//               style: const TextStyle(fontSize: 9),
//             );
//           },
//         ),
//       ),
//       leftTitles: AxisTitles(
//         sideTitles: SideTitles(
//           reservedSize: 40,
//           showTitles: true,
//           getTitlesWidget: (v, meta) =>
//               v == 0 ? const SizedBox.shrink() : Text(v.toInt().toString(),
//                   style: const TextStyle(fontSize: 10)),
//         ),
//       ),
//       topTitles   : AxisTitles(sideTitles: SideTitles(showTitles: false)),
//       rightTitles : AxisTitles(sideTitles: SideTitles(showTitles: false)),
//     );

//     return Padding(
//       padding: const EdgeInsets.fromLTRB(16, 8, 24, 16),
//       child: BarChart(
//         BarChartData(
//           barGroups : bars,
//           titlesData: titles,
//           gridData  : FlGridData(
//             show: true,
//             horizontalInterval: interval,
//           ),
//           borderData: FlBorderData(show: false),
//           alignment : BarChartAlignment.spaceBetween,
//           maxY      : maxY,
//         ),
//       ),
//     );
//   }
// }

// ////////////////////////////////////////////////////////////////
// ///  GRID LAYOUT
// class GridLayout {
//   GridLayout({
//     required this.flows,
//     required this.nodeW,
//     required this.nodeH,
//     required this.hGap,
//     required this.vGap,
//   });

//   final List<Map<String, dynamic>> flows;
//   final double nodeW, nodeH, hGap, vGap;
//   final _pos = <Node, Offset>{};
//   double canvasW = 0, canvasH = 0;

//   Offset? posOf(Node n) => _pos[n];

//   void position(Graph g) {
//     _pos.clear();

//     // adjacency (material)
//     final succ = <String, Set<String>>{}, pred = <String, Set<String>>{};
//     for (final n in g.nodes) {
//       final id = n.key!.value as String;
//       succ[id] = {}; pred[id] = {};
//     }
//     for (final e in g.edges) {
//       final a = e.source.key!.value as String, b = e.destination.key!.value as String;
//       succ[a]!.add(b);  pred[b]!.add(a);
//     }

//     // longest-path layering
//     final level = <String, int>{};
//     final q = <String>[];
//     succ.keys.forEach((id) {
//       if (pred[id]!.isEmpty) { level[id] = 0; q.add(id); }
//     });
//     if (q.isEmpty) { final first = succ.keys.first; level[first] = 0; q.add(first); }
//     while (q.isNotEmpty) {
//       final u = q.removeAt(0), base = level[u]!;
//       for (final v in succ[u]!) {
//         final cand = base + 1;
//         if (level[v] == null || cand > level[v]!) level[v] = cand;
//         q.add(v);
//       }
//     }

//     // column buckets
//     final cols = <int, List<String>>{};
//     level.forEach((id, lv) => cols.putIfAbsent(lv, () => []).add(id));

//     // two sweeps median ordering
//     void sweep(bool ltr) {
//       for (final c in cols.keys.toList()..sort()) {
//         final list = cols[c]!;
//         list.sort((a, b) {
//           double median(String id) {
//             final nb = ltr ? pred[id]! : succ[id]!;
//             if (nb.isEmpty) return 0;
//             final positions = nb.map((n) {
//               final lv = level[n]!;
//               return cols[lv]!.indexOf(n).toDouble();
//             }).toList()
//               ..sort();
//             return positions[positions.length ~/ 2];
//           }

//           return median(a).compareTo(median(b));
//         });
//       }
//     }
//     sweep(true);
//     sweep(false);

//     // final coordinates
//     double maxX = 0, maxY = 0;
//     for (final c in cols.keys) {
//       final list = cols[c]!;
//       for (var r = 0; r < list.length; r++) {
//         final id   = list[r];
//         final node = g.getNodeUsingId(id)!;
//         final x = c * (nodeW + hGap), y = r * (nodeH + vGap);
//         _pos[node] = Offset(x, y);
//         maxX = math.max(maxX, x);
//         maxY = math.max(maxY, y);
//       }
//     }
//     canvasW = maxX + nodeW + hGap;
//     canvasH = maxY + nodeH + vGap;
//   }
// }

// ////////////////////////////////////////////////////////////////
// ///  ORTHOGONAL EDGE PAINTER
// class _EdgePainter extends CustomPainter {
//   _EdgePainter(this.g, this.layout);
//   final Graph g;
//   final GridLayout layout;

//   @override
//   void paint(Canvas canvas, Size size) {
//     final p = Paint()
//       ..color = Colors.blueGrey.shade400
//       ..strokeWidth = 2
//       ..style = PaintingStyle.stroke;

//     for (final e in g.edges) {
//       final s = layout.posOf(e.source)!, t = layout.posOf(e.destination)!;
//       final x1 = s.dx + nodeW, y1 = s.dy + nodeH / 2;
//       final x4 = t.dx,         y4 = t.dy + nodeH / 2;
//       final mx = (x1 + x4) / 2;

//       final path = Path()
//         ..moveTo(x1, y1)
//         ..lineTo(mx, y1)
//         ..lineTo(mx, y4)
//         ..lineTo(x4, y4);
//       canvas.drawPath(path, p);

//       const ah = 6.0, aw = 5.0;
//       final arrow = Path()
//         ..moveTo(x4, y4)
//         ..lineTo(x4 - ah, y4 - aw)
//         ..lineTo(x4 - ah, y4 + aw)
//         ..close();
//       canvas.drawPath(arrow, p..style = PaintingStyle.fill);
//       p.style = PaintingStyle.stroke;
//     }
//   }

//   @override
//   bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
// }

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'package:fl_chart/fl_chart.dart';

const double nodeW = 200, nodeH = 120, hGap = 120, vGap = 40;

/// LCA diagram page: grid-layer graph + CO₂ bar chart + zoom controls.
class ProcessDiagramPage extends StatefulWidget {
  final Map<String, dynamic> lcaResult;
  const ProcessDiagramPage({Key? key, required this.lcaResult}) : super(key: key);

  @override
  State<ProcessDiagramPage> createState() => _ProcessDiagramPageState();
}

class _ProcessDiagramPageState extends State<ProcessDiagramPage> {
  // ─── data ────────────────────────────────────────────────────────────
  late final List<Map<String, dynamic>> _flows;
  late final List<String> _processes;
  late final double _totalCo2;
  late final Map<String, double> _perProcCo2;
  late final String _method;

  // ─── graph & layout ──────────────────────────────────────────────────
  late final Graph _graph;
  late final GridLayout _layout;

  // ─── zoom & viewport ────────────────────────────────────────────────
  final _zoomCtrl = TransformationController();
  Size _viewport = Size.zero;

  bool get _hasData => _processes.isNotEmpty && _flows.isNotEmpty;

  // ─── init ────────────────────────────────────────────────────────────
@override
void initState() {
  super.initState();

  final raw = widget.lcaResult['flows_enriched'] ?? widget.lcaResult['flows_linked'];
  _flows = raw is List ? raw.cast<Map<String, dynamic>>() : const [];

  // collect ALL process names
  final names = <String>{};
  for (final f in _flows) {
    names..add(f['from_process']?.toString() ?? '')
         ..add(f['to_process']  ?.toString() ?? '');
  }
  for (final p in (widget.lcaResult['processes'] as List? ?? [])) {
    names.add(p['name']?.toString() ?? '');
  }
  for (final ext in (widget.lcaResult['external_nodes'] as List? ?? [])) {
    names.add(ext.toString());
  }
  names.removeWhere((s) => s.isEmpty);
  _processes = names.toList()..sort();

  _method     = _formatMethod(widget.lcaResult['method']);
  final imp   = _calcImpacts();
  _totalCo2   = imp.$1;
  _perProcCo2 = imp.$2;

  _buildGraph();
}

  // ─── helpers ─────────────────────────────────────────────────────────
  String _formatMethod(dynamic raw) {
    if (raw is List && raw.isNotEmpty) return raw.join(' – ');
    if (raw is String && raw.trim().isNotEmpty) return raw;
    return 'IPCC 2021 – Climate Change – GWP100';
  }

  (double, Map<String, double>) _calcImpacts() {
    final map = <String, double>{};
    double total = 0;

    if (widget.lcaResult['process_impacts'] is Map) {
      for (final e in (widget.lcaResult['process_impacts'] as Map).entries) {
        final d = (e.value as num).toDouble();
        map[e.key.toString()] = d;
        total += d;
      }
      return (total.clamp(0, double.infinity), map);
    }

    for (final b in (widget.lcaResult['biosphere'] as List? ?? const [])) {
      final proc = b['process']?.toString() ?? 'Unknown';
      final name = b['name']?.toString().toLowerCase() ?? '';
      if (!name.contains('carbon dioxide')) continue;
      final q = (b['quantity'] as num?)?.toDouble() ?? 0;
      if (q <= 0) continue;
      map[proc] = (map[proc] ?? 0) + q;
      total    += q;
    }
    return (total.clamp(0, double.infinity), map);
  }

  void _buildGraph() {
    _graph  = Graph();
    _layout = GridLayout(flows: _flows, nodeW: nodeW, nodeH: nodeH, hGap: hGap, vGap: vGap);

    final nodes = <String, Node>{};
    for (final p in _processes) {
      final n = Node.Id(p);
      nodes[p] = n;
      _graph.addNode(n);
    }

    final invisible = Paint()..color = Colors.transparent;
    for (final f in _flows) {
      if (f['flow_type'] != 'material') continue;
      final s = nodes[f['from_process']], t = nodes[f['to_process']];
      if (s != null && t != null) _graph.addEdge(s, t, paint: invisible);
    }

    _layout.position(_graph);
  }

  // ─── zoom helpers ────────────────────────────────────────────────────
  void _zoomBy(double factor) {
    final m = _zoomCtrl.value.clone()..scale(factor);
    _zoomCtrl.value = m;
  }

  void _zoomFit() {
    if (_viewport == Size.zero) return;
    final scale = math.min(
      _viewport.width  / (_layout.canvasW + 40), // 40px margin
      _viewport.height / (_layout.canvasH + 40),
    );
    final dx = (_viewport.width  - _layout.canvasW * scale) / 2;
    final dy = (_viewport.height - _layout.canvasH * scale) / 2;
    _zoomCtrl.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
  }

  // ─── build UI ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_hasData) {
      return Scaffold(
        appBar: AppBar(title: const Text('LCA Diagram')),
        body: const Center(child: Text('No process data to display.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('$_method – Global Warming Potential'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ─ GRID DIAGRAM ─
          Expanded(
            flex: 3,
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewport = Size(constraints.maxWidth, constraints.maxHeight);
                return Stack(
                  children: [
                    InteractiveViewer(
                      transformationController: _zoomCtrl,
                      minScale: 0.2,
                      maxScale: 5.0,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      child: CustomPaint(
                        painter: _EdgePainter(_graph, _layout),
                        child: SizedBox(
                          width: _layout.canvasW,
                          height: _layout.canvasH,
                          child: Stack(
                            children: _graph.nodes.map((n) {
                              final pos = _layout.posOf(n)!;
                              final id  = n.key!.value as String;
                              final ins = <String, String>{}, outs = <String, String>{};
                              for (final f in _flows) {
                                if (f['flow_type'] != 'material') continue;
                                final name = f['name']?.toString() ?? '';
                                final q    = f['quantity'];
                                final unit = f['unit']?.toString() ?? '';
                                final txt  = q == null ? unit : '$q $unit';
                                if (f['to_process']   == id) ins [name] = txt;
                                if (f['from_process'] == id) outs[name] = txt;
                              }
                              return Positioned(
                                left: pos.dx, top: pos.dy, width: nodeW, height: nodeH,
                                child: _ProcessCard(name: id, ins: ins, outs: outs),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),

                    // ─ zoom buttons (bottom-right) ─
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Column(
                        children: [
                          FloatingActionButton(
                            heroTag: 'zoomIn',
                            mini: true,
                            tooltip: 'Zoom in',
                            child: const Icon(Icons.zoom_in),
                            onPressed: () => _zoomBy(1.3),
                          ),
                          const SizedBox(height: 6),
                          FloatingActionButton(
                            heroTag: 'zoomOut',
                            mini: true,
                            tooltip: 'Zoom out',
                            child: const Icon(Icons.zoom_out),
                            onPressed: () => _zoomBy(1 / 1.3),
                          ),
                          const SizedBox(height: 6),
                          FloatingActionButton(
                            heroTag: 'zoomFit',
                            mini: true,
                            tooltip: 'Fit to window',
                            child: const Icon(Icons.fit_screen),
                            onPressed: _zoomFit,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // ─ BAR CHART ─
          Expanded(
            flex: 2,
            child: _ImpactBarChart(
              total : _totalCo2,
              perProc: _perProcCo2,
              method : _method,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Rebuild layout',
        child: const Icon(Icons.refresh),
        onPressed: () => setState(_buildGraph),
      ),
    );
  }
}

// ───────────────────────────────── CARD (unchanged visual) ───────────
class _ProcessCard extends StatelessWidget {
  final String name;
  final Map<String, String> ins, outs;
  const _ProcessCard({required this.name, required this.ins, required this.outs});

  @override
  Widget build(BuildContext context) => Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 12, overflow: TextOverflow.ellipsis),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                if (ins.isNotEmpty) ...[
                  const Text('Inputs:', style: TextStyle(fontWeight: FontWeight.w600)),
                  Flexible(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: ins.entries
                          .map((e) => Text('• ${e.key}: ${e.value}'))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                if (outs.isNotEmpty) ...[
                  const Text('Outputs:', style: TextStyle(fontWeight: FontWeight.w600)),
                  Flexible(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: outs.entries
                          .map((e) => Text('• ${e.key}: ${e.value}'))
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );}

// ────────────────────────────────────────────────── BAR CHART (Final version)
class _ImpactBarChart extends StatelessWidget {
  const _ImpactBarChart({
    required this.total,
    required this.perProc,
    required this.method,
  });

  final double total;
  final Map<String, double> perProc;
  final String? method;

  @override
  Widget build(BuildContext context) {
    // ─── Method label with fallback ───
    final methodLabel = (method != null && method!.trim().isNotEmpty)
        ? method!
        : "'IPCC 2021', 'climate change', 'global warming potential (GWP100)'";

    // ─── Entries sorted, omit TOTAL if zero ───
    final entries = [
      if (total > 0) MapEntry('TOTAL', total),
      ...perProc.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    ];

    // ─── Create bars (all red) ───
    const barWidth = 32.0; // larger bars for visibility
    final barColor = Colors.redAccent; // modern vivid red

    final bars = List.generate(entries.length, (i) {
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: entries[i].value,
            color: barColor,
            width: barWidth,
            borderRadius: BorderRadius.circular(4),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: entries[i].value * 1.1,
              color: barColor.withOpacity(0.15),
            ),
          ),
        ],
      );
    });

    // ─── Axis labels (vertical rotated) ───
    final titles = FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 100,
          getTitlesWidget: (v, _) {
            final idx = v.toInt();
            if (idx < 0 || idx >= entries.length) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Transform.rotate(
                angle: -math.pi / 2,
                child: Text(
                  entries[idx].key,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  softWrap: false,
                ),
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 60,
          getTitlesWidget: (v, _) => Text(
            v == 0 ? '' : '${v.toInt()} kg',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ),
      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );

    // ─── Y-axis scaling ───
    final maxY = (entries.map((e) => e.value).reduce(math.max) * 1.2).clamp(5, double.infinity);

    // ─── Chart width ───
    final chartWidth = entries.length * (barWidth + 20)*2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Method clearly displayed
          Text(
            methodLabel,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: chartWidth,
                child: BarChart(
                  BarChartData(
                    barGroups: bars,
                    maxY: maxY.toDouble(),

                    titlesData: titles,
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(
                      show: true,
                      drawHorizontalLine: true,
                      horizontalInterval: maxY / 5,
                    ),
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


// ────────────────────────────────────────────────── GRID LAYOUT (unchanged core)
class GridLayout {
  GridLayout({
    required this.flows,
    required this.nodeW,
    required this.nodeH,
    required this.hGap,
    required this.vGap,
  });

  final List<Map<String, dynamic>> flows;
  final double nodeW, nodeH, hGap, vGap;
  final _pos = <Node, Offset>{};
  double canvasW = 0, canvasH = 0;

  Offset? posOf(Node n) => _pos[n];

  void position(Graph g) {
    _pos.clear();

    // build adjacency (material)
    final succ = <String, Set<String>>{}, pred = <String, Set<String>>{};
    for (final n in g.nodes) {
      final id = n.key!.value as String;
      succ[id] = {}; pred[id] = {};
    }
    for (final e in g.edges) {
      final a = e.source.key!.value as String, b = e.destination.key!.value as String;
      succ[a]!.add(b);  pred[b]!.add(a);
    }

    // longest-path layering
    final level = <String, int>{};
    final q = <String>[];
    succ.keys.forEach((id) { if (pred[id]!.isEmpty) { level[id] = 0; q.add(id);} });
    if (q.isEmpty) { final first = succ.keys.first; level[first] = 0; q.add(first);}
    while (q.isNotEmpty) {
      final u = q.removeAt(0), base = level[u]!;
      for (final v in succ[u]!) {
        final cand = base + 1;
        if (level[v] == null || cand > level[v]!) level[v] = cand;
        q.add(v);
      }
    }

    // bucket by column
    final cols = <int, List<String>>{};
    level.forEach((id, l) => cols.putIfAbsent(l, () => []).add(id));

    // simple crossing reduction (two median sweeps)
    void sweep(bool ltr) {
      for (final c in cols.keys.toList()..sort()) {
        final list = cols[c]!;
        list.sort((a, b) {
          double med(String id) {
            final nb = ltr ? pred[id]! : succ[id]!;
            if (nb.isEmpty) return 0;
            final idxs = nb
                .map((n) => cols[level[n]!]!.indexOf(n).toDouble())
                .toList()
              ..sort();
            return idxs[idxs.length ~/ 2];
          }
          return med(a).compareTo(med(b));
        });
      }
    }
    sweep(true); sweep(false);

    // final positions
    double maxX = 0, maxY = 0;
    for (final c in cols.keys) {
      final list = cols[c]!;
      for (var r = 0; r < list.length; r++) {
        final node = g.getNodeUsingId(list[r])!;
        final x = c * (nodeW + hGap), y = r * (nodeH + vGap);
        _pos[node] = Offset(x, y);
        maxX = math.max(maxX, x); maxY = math.max(maxY, y);
      }
    }
    canvasW = maxX + nodeW + hGap;
    canvasH = maxY + nodeH + vGap;
  }
}

// ────────────────────────────────────────────────── EDGE PAINTER
class _EdgePainter extends CustomPainter {
  const _EdgePainter(this.g, this.layout);
  final Graph g; final GridLayout layout;

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = Colors.blueGrey.shade400
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final e in g.edges) {
      final sOff = layout.posOf(e.source)!, tOff = layout.posOf(e.destination)!;
      final x1 = sOff.dx + nodeW, y1 = sOff.dy + nodeH / 2;
      final x4 = tOff.dx,         y4 = tOff.dy + nodeH / 2;
      final mx = (x1 + x4) / 2;

      final path = Path()
        ..moveTo(x1, y1)..lineTo(mx, y1)..lineTo(mx, y4)..lineTo(x4, y4);
      c.drawPath(path, p);

      // arrow head
      const ah = 6.0, aw = 5.0;
      final arrow = Path()
        ..moveTo(x4, y4)
        ..lineTo(x4 - ah, y4 - aw)
        ..lineTo(x4 - ah, y4 + aw)
        ..close();
      c.drawPath(arrow, p..style = PaintingStyle.fill);
      p.style = PaintingStyle.stroke;
    }
  }
  @override bool shouldRepaint(covariant CustomPainter o) => false;
}
