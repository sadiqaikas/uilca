// // lib/widgets/data_panel.dart

// import 'dart:convert';

// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';

// import 'graph_pipeline.dart' show GraphPipelineViewModel;
// import 'process_node.dart';
// import 'flow_link.dart';

// /// A tabbed panel showing Summary, Processes, Flows, and Raw JSON.
// class DataPanel extends StatelessWidget {
//   const DataPanel({Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final vm = context.watch<GraphPipelineViewModel>();

//     return DefaultTabController(
//       length: 4,
//       child: Column(
//         children: [
//           // Tab bar
//           Material(
//             color: Colors.white,
//             child: const TabBar(
//               labelColor: Colors.black87,
//               indicatorColor: Colors.lightGreen,
//               tabs: [
//                 Tab(icon: Icon(Icons.info_outline), text: 'Summary'),
//                 Tab(icon: Icon(Icons.list), text: 'Processes'),
//                 Tab(icon: Icon(Icons.share), text: 'Flows'),
//                 Tab(icon: Icon(Icons.code), text: 'Raw JSON'),
//               ],
//             ),
//           ),

//           // Tab views
//           Expanded(
//             child: TabBarView(
//               children: [
//                 _SummaryTab(vm: vm),
//                 _ProcessesTab(vm: vm),
//                 _FlowsTab(vm: vm),
//                 _RawJsonTab(raw: vm.rawResult),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _SummaryTab extends StatelessWidget {
//   final GraphPipelineViewModel vm;
//   const _SummaryTab({required this.vm});

//   @override
//   Widget build(BuildContext context) {
//     final functionalUnit = vm.rawResult['functional_unit']?.toString() ?? '—';
//     final goalScope = vm.rawResult['goal_scope'] as Map<String,dynamic>? ?? {};
//     return Padding(
//       padding: const EdgeInsets.all(16),
//       child: ListView(
//         children: [
//           Card(
//             elevation: 2,
//             child: ListTile(
//               leading: const Icon(Icons.track_changes),
//               title: const Text('Functional Unit'),
//               subtitle: Text(functionalUnit),
//             ),
//           ),
//           const SizedBox(height: 12),
//           Card(
//             elevation: 2,
//             child: ExpansionTile(
//               leading: const Icon(Icons.map_outlined),
//               title: const Text('Goal & Scope'),
//               children: goalScope.entries.map((e) {
//                 return ListTile(
//                   title: Text(e.key),
//                   subtitle: Text(e.value.toString()),
//                 );
//               }).toList(),
//             ),
//           ),
//           const SizedBox(height: 12),
//           Card(
//             elevation: 2,
//             child: ListTile(
//               leading: const Icon(Icons.calculate_outlined),
//               title: const Text('Total Impact'),
//               subtitle: Text(vm.totalImpact.toStringAsFixed(3)),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _ProcessesTab extends StatelessWidget {
//   final GraphPipelineViewModel vm;
//   const _ProcessesTab({required this.vm});

//   @override
//   Widget build(BuildContext context) {
//     return SingleChildScrollView(
//       scrollDirection: Axis.horizontal,
//       child: DataTable(
//         headingRowColor: MaterialStateProperty.all(Colors.lightGreen.shade100),
//         columns: const [
//           DataColumn(label: Text('Process')),
//           DataColumn(label: Text('Uncertainty')),
//           DataColumn(label: Text('Impact')),
//         ],
//         rows: vm.processes.map((p) {
//           final impact = vm.perProcessImpact[p.name] ?? 0.0;
//           return DataRow(
//             selected: p.id == vm.selectedProcess?.id,
//             onSelectChanged: (_) => vm.selectProcess(p),
//             cells: [
//               DataCell(Text(p.name)),
//               DataCell(Text(p.uncertainty.label)),
//               DataCell(Text(impact.toStringAsFixed(3))),
//             ],
//           );
//         }).toList(),
//       ),
//     );
//   }
// }

// class _FlowsTab extends StatelessWidget {
//   final GraphPipelineViewModel vm;
//   const _FlowsTab({required this.vm});

//   @override
//   Widget build(BuildContext context) {
//     return SingleChildScrollView(
//       scrollDirection: Axis.horizontal,
//       child: DataTable(
//         headingRowColor: MaterialStateProperty.all(Colors.lightGreen.shade100),
//         columns: const [
//           DataColumn(label: Text('Flow')),
//           DataColumn(label: Text('From')),
//           DataColumn(label: Text('To')),
//           DataColumn(label: Text('Qty')),
//           DataColumn(label: Text('Unit')),
//           DataColumn(label: Text('Type')),
//         ],
//         rows: vm.flows.map((f) {
//           return DataRow(cells: [
//             DataCell(Text(f.name)),
//             DataCell(Text(f.from)),
//             DataCell(Text(f.to)),
//             DataCell(Text(f.quantity.toStringAsFixed(3))),
//             DataCell(Text(f.unit)),
//             DataCell(Text(f.type == FlowType.material ? 'Material' : 'Emission')),
//           ]);
//         }).toList(),
//       ),
//     );
//   }
// }

// class _RawJsonTab extends StatelessWidget {
//   final Map<String, dynamic> raw;
//   const _RawJsonTab({required this.raw});

//   @override
//   Widget build(BuildContext context) {
//     final pretty = const JsonEncoder.withIndent('  ').convert(raw);
//     return SingleChildScrollView(
//       padding: const EdgeInsets.all(12),
//       child: SelectableText(
//         pretty,
//         style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
//       ),
//     );
//   }
// }

// // lib/widgets/data_panel.dart

// import 'dart:convert';

// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';

// import 'graph_pipeline.dart' show GraphPipelineViewModel;
// import 'process_node.dart';
// import 'flow_link.dart';
// import 'uncertainty_level.dart';

// /// A tabbed panel showing Summary, Processes, Flows, and Raw JSON.
// class DataPanel extends StatelessWidget {
//   const DataPanel({Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final vm = context.watch<GraphPipelineViewModel>();

//     return DefaultTabController(
//       length: 3,
//       child: Column(
//         children: [
//           // ─── Tabs ──────────────────────────────────────────────
//           Material(
//             color: Colors.white,
//             child: const TabBar(
//               labelColor: Colors.black87,
//               indicatorColor: Colors.lightGreen,
//               tabs: [
//                 // Tab(icon: Icon(Icons.info_outline), text: 'Summary'),
//                 Tab(icon: Icon(Icons.list), text: 'Processes'),
//                 Tab(icon: Icon(Icons.share), text: 'Flows'),
//                 Tab(icon: Icon(Icons.code), text: 'Raw JSON'),
//               ],
//             ),
//           ),

//           // ─── Tab views ─────────────────────────────────────────
//           Expanded(
//             child: TabBarView(
//               children: [
//                 // _SummaryTab(vm: vm),
//                 _ProcessesTab(vm: vm),
//                 _FlowsTab(vm: vm),
//                 _RawJsonTab(raw: vm.rawResult),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _SummaryTab extends StatelessWidget {
//   final GraphPipelineViewModel vm;
//   const _SummaryTab({required this.vm});

//   @override
//   Widget build(BuildContext context) {
//     final funcUnit = vm.rawResult['functional_unit']?.toString() ?? '—';
//     final goalScope = vm.rawResult['goal_scope'] as Map<String, dynamic>? ?? {};

//     return Padding(
//       padding: const EdgeInsets.all(16),
//       child: ListView(
//         children: [
//           Card(
//             elevation: 2,
//             shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(12)),
//             child: ListTile(
//               leading: const Icon(Icons.track_changes),
//               title: const Text('Functional Unit'),
//               subtitle: Text(funcUnit),
//             ),
//           ),
//           const SizedBox(height: 12),
//           Card(
//             elevation: 2,
//             shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(12)),
//             child: ExpansionTile(
//               leading: const Icon(Icons.map_outlined),
//               title: const Text('Goal & Scope'),
//               children: goalScope.entries.map((e) {
//                 return ListTile(
//                   title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
//                   subtitle: Text(e.value.toString()),
//                 );
//               }).toList(),
//             ),
//           ),
//           const SizedBox(height: 12),
//           Card(
//             elevation: 2,
//             shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(12)),
//             child: ListTile(
//               leading: const Icon(Icons.calculate_outlined),
//               title: const Text('Total Impact'),
//               subtitle: Text(vm.totalImpact.toStringAsFixed(3)),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _ProcessesTab extends StatelessWidget {
//   final GraphPipelineViewModel vm;
//   const _ProcessesTab({required this.vm});

//   @override
//   Widget build(BuildContext context) {
//     final columns = const [
//       DataColumn(label: Text('Process')),
//       DataColumn(label: Text('Uncertainty')),
//       DataColumn(label: Text('Impact')),
//     ];

//     final rows = vm.processes.asMap().entries.map((entry) {
//       final idx = entry.key;
//       final p   = entry.value;
//       final impact = vm.emissions_per_process[p.name] ?? 0.0;
//       return DataRow.byIndex(
//         index: idx,
//         selected: p.id == vm.selectedProcess?.id,
//         onSelectChanged: (_) => vm.selectProcess(p),
//         color: MaterialStateProperty.resolveWith<Color?>(
//           (states) => idx.isEven
//               ? Colors.grey.shade50
//               : Colors.white,
//         ),
//         cells: [
//           DataCell(Text(p.name)),
//           DataCell(Text(p.uncertainty.label)),
//           DataCell(Text(impact.toStringAsFixed(3))),
//         ],
//       );
//     }).toList();

//     return Card(
//       margin: const EdgeInsets.all(12),
//       elevation: 2,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: Scrollbar(
//         thumbVisibility: true,
//         child: SingleChildScrollView(
//           scrollDirection: Axis.vertical,
//           child: SingleChildScrollView(
//             scrollDirection: Axis.horizontal,
//             child: DataTable(
//               headingRowColor: MaterialStateProperty.all(Colors.lightGreen.shade100),
//               columns: columns,
//               rows: rows,
//               columnSpacing: 24,
//               dataRowHeight: 48,
//               headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _FlowsTab extends StatelessWidget {
//   final GraphPipelineViewModel vm;
//   const _FlowsTab({required this.vm});

//   @override
//   Widget build(BuildContext context) {
//     final columns = const [
//       DataColumn(label: Text('Flow')),
//       DataColumn(label: Text('From')),
//       DataColumn(label: Text('To')),
//       DataColumn(label: Text('Qty')),
//       DataColumn(label: Text('Unit')),
//       DataColumn(label: Text('Type')),
//     ];

//     final rows = vm.flows.asMap().entries.map((entry) {
//       final idx = entry.key;
//       final f   = entry.value;
//       return DataRow.byIndex(
//         index: idx,
//         color: MaterialStateProperty.resolveWith<Color?>(
//           (states) => idx.isEven
//               ? Colors.grey.shade50
//               : Colors.white,
//         ),
//         cells: [
//           DataCell(Text(f.name)),
//           DataCell(Text(f.from)),
//           DataCell(Text(f.to)),
//           DataCell(Text(f.quantity.toStringAsFixed(3))),
//           DataCell(Text(f.unit)),
//           DataCell(Text(
//               f.type == FlowType.material ? 'Material' : 'Emission')),
//         ],
//       );
//     }).toList();

//     return Card(
//       margin: const EdgeInsets.all(12),
//       elevation: 2,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: Scrollbar(
//         thumbVisibility: true,
//         child: SingleChildScrollView(
//           scrollDirection: Axis.vertical,
//           child: SingleChildScrollView(
//             scrollDirection: Axis.horizontal,
//             child: DataTable(
//               headingRowColor: MaterialStateProperty.all(Colors.lightGreen.shade100),
//               columns: columns,
//               rows: rows,
//               columnSpacing: 16,
//               dataRowHeight: 48,
//               headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _RawJsonTab extends StatelessWidget {
//   final Map<String, dynamic> raw;
//   const _RawJsonTab({required this.raw});

//   @override
//   Widget build(BuildContext context) {
//     return Card(
//       color: Colors.white,
//       margin: const EdgeInsets.all(12),
//       elevation: 2,
//       shape:
//           RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: const JsonViewerWrapper(),
//     );
//   }
// }

// /// A small wrapper to pull raw JSON from the ViewModel.
// class JsonViewerWrapper extends StatelessWidget {
//   const JsonViewerWrapper({Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final raw = context.watch<GraphPipelineViewModel>().rawResult;
//     return JsonViewer(jsonObj: raw);
//   }
// }


// class JsonViewer extends StatelessWidget {
//   final dynamic jsonObj;
//   const JsonViewer({Key? key, required this.jsonObj}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return SingleChildScrollView(
//       padding: const EdgeInsets.all(12),
//       child: _buildNode(jsonObj, 0),
//     );
//   }

//   Widget _buildNode(dynamic node, int indent) {
//     final indentPx = indent * 16.0;
//     if (node is Map<String, dynamic>) {
//       return Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: node.entries.map((entry) {
//           return Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Padding(
//                 padding: EdgeInsets.only(left: indentPx),
//                 child: Text(
//                   '${entry.key}:',
//                   style: const TextStyle(fontWeight: FontWeight.bold),
//                 ),
//               ),
//               _buildNode(entry.value, indent + 1),
//             ],
//           );
//         }).toList(),
//       );
//     }
//     if (node is List) {
//       return Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: List.generate(node.length, (i) {
//           return Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Padding(
//                 padding: EdgeInsets.only(left: indentPx),
//                 child: Text(
//                   '- [$i]',
//                   style: const TextStyle(fontWeight: FontWeight.bold),
//                 ),
//               ),
//               _buildNode(node[i], indent + 1),
//             ],
//           );
//         }),
//       );
//     }
//     // primitive
//     return Padding(
//       padding: EdgeInsets.only(left: indentPx + 8),
//       child: Text(
//         node == null ? 'null' : node.toString(),
//         style: const TextStyle(fontFamily: 'monospace'),
//       ),
//     );
//   }
// }

// lib/widgets/data_panel.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'graph_pipeline.dart' show GraphPipelineViewModel;
import 'process_node.dart';
import 'flow_link.dart';
import 'uncertainty_level.dart';

/// A tabbed panel showing Processes, Flows, and Emissions.
class DataPanel extends StatelessWidget {
  const DataPanel({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GraphPipelineViewModel>();

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          // ─── Tabs ──────────────────────────────────────────────
          Material(
            color: Colors.white,
            child: const TabBar(
              labelColor: Colors.black87,
              indicatorColor: Colors.lightGreen,
              tabs: [
                Tab(icon: Icon(Icons.list), text: 'Processes'),
                Tab(icon: Icon(Icons.share), text: 'Flows'),
                Tab(icon: Icon(Icons.cloud), text: 'Emissions'),
              ],
            ),
          ),

          // ─── Tab views ─────────────────────────────────────────
          Expanded(
            child: TabBarView(
              children: [
                _ProcessesTab(vm: vm),
                _FlowsTab(vm: vm),
                _EmissionsTab(vm: vm),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcessesTab extends StatelessWidget {
  final GraphPipelineViewModel vm;
  const _ProcessesTab({required this.vm});

  @override
  Widget build(BuildContext context) {
    final columns = const [
      DataColumn(label: Text('Process')),
      DataColumn(label: Text('Uncertainty')),
      DataColumn(label: Text('Impact')),
    ];

    final rows = vm.processes.asMap().entries.map((entry) {
      final idx = entry.key;
      final p   = entry.value;
      final impact = vm.emissions_per_process[p.name] ?? 0.0;
      return DataRow.byIndex(
        index: idx,
        selected: p.id == vm.selectedProcess?.id,
        onSelectChanged: (_) => vm.selectProcess(p),
        color: MaterialStateProperty.resolveWith<Color?>(
          (states) => idx.isEven ? Colors.grey.shade50 : Colors.white,
        ),
        cells: [
          DataCell(Text(p.name)),
          DataCell(Text(p.uncertainty.label)),
          DataCell(Text(impact.toStringAsFixed(3))),
        ],
      );
    }).toList();

    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(Colors.lightGreen.shade100),
              columns: columns,
              rows: rows,
              columnSpacing: 24,
              dataRowHeight: 48,
              headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlowsTab extends StatelessWidget {
  final GraphPipelineViewModel vm;
  const _FlowsTab({required this.vm});

  @override
  Widget build(BuildContext context) {
    final columns = const [
      DataColumn(label: Text('Flow')),
      DataColumn(label: Text('From')),
      DataColumn(label: Text('To')),
      DataColumn(label: Text('Qty')),
      DataColumn(label: Text('Unit')),
      DataColumn(label: Text('Type')),
    ];

    final rows = vm.flows.asMap().entries.map((entry) {
      final idx = entry.key;
      final f   = entry.value;
      return DataRow.byIndex(
        index: idx,
        color: MaterialStateProperty.resolveWith<Color?>(
          (states) => idx.isEven ? Colors.grey.shade50 : Colors.white,
        ),
        cells: [
          DataCell(Text(f.name)),
          DataCell(Text(f.from)),
          DataCell(Text(f.to)),
          DataCell(Text(f.quantity.toStringAsFixed(3))),
          DataCell(Text(f.unit)),
          DataCell(Text(f.type == FlowType.material ? 'Material' : 'Emission')),
        ],
      );
    }).toList();

    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(Colors.lightGreen.shade100),
              columns: columns,
              rows: rows,
              columnSpacing: 16,
              dataRowHeight: 48,
              headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}

/// NEW: Flat table of all biosphere emissions, sorted by process.
class _EmissionsTab extends StatelessWidget {
  final GraphPipelineViewModel vm;
  const _EmissionsTab({required this.vm});

  @override
  Widget build(BuildContext context) {
    // Extract & normalize the biosphere list
    final biosphere = vm.rawResult['biosphere'] as List<dynamic>? ?? [];
    final emissions = biosphere.map((e) => {
          'process': e['process'] ?? 'Unknown',
          'name': e['name'] ?? '',
          'quantity': (e['quantity'] as num).toDouble(),
          'unit': e['unit'] ?? '',
          'type': e['flow_type'] ?? '',
        }).toList();

    // Sort by process name
    emissions.sort((a, b) => (a['process'] as String)
        .compareTo(b['process'] as String));

    final columns = const [
      DataColumn(label: Text('Process')),
      DataColumn(label: Text('Emission')),
      DataColumn(label: Text('Quantity')),
      DataColumn(label: Text('Unit')),
      DataColumn(label: Text('Type')),
    ];

    final rows = emissions.asMap().entries.map((entry) {
      final idx = entry.key;
      final e   = entry.value;
      return DataRow.byIndex(
        index: idx,
        color: MaterialStateProperty.resolveWith<Color?>(
          (states) => idx.isEven ? Colors.grey.shade50 : Colors.white,
        ),
        cells: [
          DataCell(Text(e['process'] as String)),
          DataCell(Text(e['name'] as String)),
          DataCell(Text((e['quantity'] as double).toStringAsFixed(3))),
          DataCell(Text(e['unit'] as String)),
          DataCell(Text(e['type'] as String)),
        ],
      );
    }).toList();

    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(Colors.lightGreen.shade100),
              columns: columns,
              rows: rows,
              columnSpacing: 16,
              dataRowHeight: 48,
              headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}
