// lib/pages/graph_pipeline.dart

// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';

// import 'process_node.dart';
// import 'flow_link.dart';
// import 'uncertainty_level.dart';
// import 'lca_controller.dart';

// import 'graph_view_widget.dart';
// import 'impact_bar_chart.dart';
// import 'process_editor.dart';

// /// Entry point page: sets up the ViewModel and injects it via Provider.
// class GraphPipelinePage extends StatelessWidget {
//   final Map<String, dynamic> initialLcaResult;

//   const GraphPipelinePage({
//     Key? key,
//     required this.initialLcaResult,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return ChangeNotifierProvider<GraphPipelineViewModel>(
//       create: (_) => GraphPipelineViewModel(initialLcaResult),
//       child: const GraphPipelineView(),
//     );
//   }
// }

// /// The main UI: graph + chart + editor + run button
// class GraphPipelineView extends StatelessWidget {
//   const GraphPipelineView({Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final vm = context.watch<GraphPipelineViewModel>();

//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('LCA Pipeline'),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             tooltip: 'Re-run LCA',
//             onPressed: vm.isRunning ? null : vm.runLca,
//           ),
//         ],
//       ),
//       body: vm.isRunning
//           ? const Center(child: CircularProgressIndicator())
//           : Column(
//               children: [
//                 // 1) Flow graph
//                 Expanded(
//                   flex: 3,
//                   child: GraphViewWidget(
//                     processes: vm.processes,
//                     flows: vm.flows,
//                     onTapNode: vm.selectProcess,
//                     // supply color by uncertainty:
//                     colorOf: vm.colorOf
//                   ),
//                 ),

//                 // 2) Impact bar chart
//                 Expanded(
//                   flex: 2,
//                   child: ImpactBarChart(
//                     totalImpact: vm.totalImpact,
//                     perProcessImpact: vm.perProcessImpact,
//                     methodLabel: vm.methodLabel,
//                   ),
//                 ),

//                 // 3) Editor panel (when a node is selected)
//                 if (vm.selectedProcess != null)
//                   SizedBox(
//                     height: 200,
//                     child: ProcessEditor(
//                       process: vm.selectedProcess!,
//                       onSave: vm.updateProcess,
//                       flowLinks: vm.flowsFor(vm.selectedProcess!),
//                       onFlowUpdate: vm.updateFlow,
//                     ),
//                   ),
//               ],
//             ),
//     );
//   }
// }

// /// ViewModel: holds all LCA state, parsing, and editing logic.
// class GraphPipelineViewModel extends ChangeNotifier {
//   // Raw LCA JSON
//   Map<String, dynamic> _lcaResult;

//   // Parsed models
//   late List<ProcessNode> processes;
//   late List<FlowLink> flows;

//   // Impacts
//   late double totalImpact;
//   late Map<String, double> perProcessImpact;
//   late String methodLabel;

//   // UI state
//   bool isRunning = false;
//   ProcessNode? selectedProcess;

//   GraphPipelineViewModel(this._lcaResult) {
//     _parseResult(_lcaResult);
//   }

//   void _parseResult(Map<String, dynamic> r) {
//     // TODO: parse into ProcessNode & FlowLink (with uncertainty levels)
//     processes = ProcessNode.fromLcaJson(r);
//     flows     = FlowLink.fromLcaJson(r);
//     methodLabel       = r['method']?.toString() ?? '';
//     totalImpact       = r['totalImpact'] as double? ?? 0;
//     perProcessImpact  = Map<String, double>.from(r['perProcessImpact'] ?? {});
//     notifyListeners();
//   }

//   /// Called when user clicks “Re-run LCA”
//   Future<void> runLca() async {
//     isRunning = true;
//     notifyListeners();
//     final updated = await LcaController.run(_lcaResult);
//     _lcaResult = updated;
//     _parseResult(updated);
//     selectedProcess = null;
//     isRunning = false;
//     notifyListeners();
//   }

//   /// Helpers for editor callbacks
//   void selectProcess(ProcessNode node) {
//     selectedProcess = node;
//     notifyListeners();
//   }

//   void updateProcess(ProcessNode updated) {
//     // apply edits in-memory
//     final idx = processes.indexWhere((p) => p.id == updated.id);
//     if (idx != -1) processes[idx] = updated;
//     // reflect back to raw JSON if needed...
//     notifyListeners();
//   }

//   void updateFlow(FlowLink updated) {
//     final idx = flows.indexWhere((f) => f.id == updated.id);
//     if (idx != -1) flows[idx] = updated;
//     // reflect back to raw JSON if needed...
//     notifyListeners();
//   }

//   /// Returns only the flows connected to a given process
//   List<FlowLink> flowsFor(ProcessNode node) {
//     return flows.where((f) =>
//       f.from == node.id || f.to == node.id
//     ).toList();
//   }

//   /// Map uncertainty to a color
//   Color colorOf(UncertaintyLevel u) {
//     switch (u) {
//       case UncertaintyLevel.user:     return Colors.blue;
//       case UncertaintyLevel.database: return Colors.green;
//       case UncertaintyLevel.adapted:  return Colors.yellow.shade700;
//       case UncertaintyLevel.inferred: return Colors.red;
//     }
//   }
// }

// // lib/pages/graph_pipeline.dart
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';

// import 'process_node.dart';
// import 'flow_link.dart';
// import 'uncertainty_level.dart';
// import 'lca_controller.dart';

// import 'graph_view_widget.dart';
// import 'impact_bar_chart.dart';
// import 'process_editor.dart';

// /// Page: provides ViewModel and scaffold
// class GraphPipelinePage extends StatelessWidget {
//   final Map<String, dynamic> initialLcaResult;

//   const GraphPipelinePage({
//     Key? key,
//     required this.initialLcaResult,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return ChangeNotifierProvider<GraphPipelineViewModel>(
//       create: (_) => GraphPipelineViewModel(initialLcaResult),
//       child: const _GraphPipelineScaffold(),
//     );
//   }
// }

// /// Scaffold + layout
// class _GraphPipelineScaffold extends StatefulWidget {
//   const _GraphPipelineScaffold({Key? key}) : super(key: key);

//   @override
//   State<_GraphPipelineScaffold> createState() => _GraphPipelineScaffoldState();
// }

// class _GraphPipelineScaffoldState extends State<_GraphPipelineScaffold>
//     with SingleTickerProviderStateMixin {
//   late final TabController _tabController;

//   @override
//   void initState() {
//     super.initState();
//     _tabController = TabController(length: 2, vsync: this);
//   }

//   @override
//   void dispose() {
//     _tabController.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final vm = context.watch<GraphPipelineViewModel>();

//     // Whenever a process is selected, jump to the "Edit" tab (index 1)
//     if (vm.selectedProcess != null && _tabController.index != 1) {
//       _tabController.animateTo(1);
//     }

//     return SafeArea(
//       child: Scaffold(
//         backgroundColor: Colors.white,
//         appBar: AppBar(
//           backgroundColor: Colors.white,
//           title: const Text('LCA Pipeline'),
//         ),
//         body: vm.isRunning
//             ? const Center(child: CircularProgressIndicator())
//             : LayoutBuilder(
//                 builder: (ctx, constraints) {
//                   final panelWidth =
//                       (constraints.maxWidth * 0.25).clamp(200.0, 500.0);
      
//                   return Row(
//                     children: [
//                       // ── Graph Canvas ─────────────────────────────────────
//                       Expanded(
//                         child: Container(
//                           color: Colors.white,
//                           child: GraphViewWidget(
//                             processes: vm.processes,
//                             flows: vm.flows,
//                             onTapNode: vm.selectProcess,
//                             colorOf: vm.colorOf,
//                             // <-- New: pass selectedProcessId for highlighting
//                             selectedProcessId: vm.selectedProcess?.id,
//                           ),
//                         ),
//                       ),
      
//                       // ── Side Panel ───────────────────────────────────────
//                       VerticalDivider(width: 1, color: Colors.grey.shade300),
//                       SizedBox(
//                         width: panelWidth,
//                         child: Column(
//                           children: [
//                             // Tabs
//                             Material(
//                               color: Colors.white,
//                               child: TabBar(
//                                 controller: _tabController,
//                                 labelColor: Colors.green.shade800,
//                                 indicatorColor: Colors.green,
//                                 tabs: const [
//                                   Tab(text: 'Impacts'),
//                                   Tab(text: 'Edit'),
//                                 ],
//                               ),
//                             ),
      
//                             // Tab content
//                             Expanded(
//                               child: TabBarView(
//                                 controller: _tabController,
//                                 children: [
//                                   // ── Impacts Chart ───────────────────
//                                   Padding(
//                                     padding: const EdgeInsets.all(12),
//                                     child: ImpactBarChart(
//                                       totalImpact: vm.totalImpact,
//                                       perProcessImpact: vm.perProcessImpact,
//                                       methodLabel: vm.methodLabel,
//                                       onBarTap: vm.selectProcessByName,
//                                     ),
//                                   ),
      
//                                   // ── Editor ─────────────────────────
//                                   vm.selectedProcess == null
//                                       ? const Center(
//                                           child: Text(
//                                             'Tap a process to edit',
//                                             style: TextStyle(
//                                                 fontStyle: FontStyle.italic),
//                                           ),
//                                         )
//                                       : ProcessEditor(
//                                           process: vm.selectedProcess!,
//                                           flowLinks:
//                                               vm.flowsFor(vm.selectedProcess!),
//                                           onSave: vm.commitProcessEdits,
//                                           onFlowUpdate: vm.updateFlow,
//                                           onDeleteProcess: vm.deleteProcess,
//                                           onDeleteFlow: vm.deleteFlow,
//                                           onReconnectFlow: vm.reconnectFlow,
//                                           onCancel: () =>
//                                               vm.selectProcess(null),
//                                         ),
//                                 ],
//                               ),
//                             ),
      
//                             // ── Run LCA Button ────────────────────
//                             if (vm.hasEdits)
//                               Padding(
//                                 padding:
//                                     const EdgeInsets.symmetric(vertical: 12),
//                                 child: ElevatedButton.icon(
//                                   onPressed: vm.runLca,
//                                   style: ElevatedButton.styleFrom(
//                                     backgroundColor: Colors.green,
//                                     padding: const EdgeInsets.symmetric(
//                                         vertical: 16, horizontal: 24),
//                                     textStyle: const TextStyle(fontSize: 16),
//                                   ),
//                                   icon: const Icon(Icons.refresh, size: 20),
//                                   label: const Text('Run LCA'),
//                                 ),
//                               ),
//                           ],
//                         ),
//                       ),
//                     ],
//                   );
//                 },
//               ),
//       ),
//     );
//   }
// }

// /// ViewModel (unchanged)
// class GraphPipelineViewModel extends ChangeNotifier {
//   Map<String, dynamic> _lcaResult;
//   List<ProcessNode> processes = [];
//   List<FlowLink> flows = [];
//   double totalImpact = 0;
//   Map<String, double> perProcessImpact = {};
//   String methodLabel = '';

//   bool isRunning = false;
//   ProcessNode? selectedProcess;

//   bool _edited = false;
//   bool get hasEdits => _edited;

//   GraphPipelineViewModel(this._lcaResult) {
//     _parseResult(_lcaResult);
//   }

//   void _parseResult(Map<String, dynamic> r) {
//     processes = ProcessNode.fromLcaJson(r);
//     flows = FlowLink.fromLcaJson(r);
//     methodLabel = r['method']?.join(' – ') ?? '';
//     totalImpact = (r['totalImpact'] as num?)?.toDouble() ?? 0;
//     perProcessImpact =
//         Map<String, double>.from(r['perProcessImpact'] as Map? ?? {});
//     _edited = false;
//     selectedProcess = null;
//     notifyListeners();
//   }

//   void updateFlow(FlowLink updated) {
//     final idx = flows.indexWhere((f) => f.id == updated.id);
//     if (idx != -1) {
//       flows[idx] = updated;
//       final raw = _lcaResult['flows_enriched'] as List<dynamic>;
//       raw[idx]['quantity'] = updated.quantity;
//       raw[idx]['unit'] = updated.unit;
//       _edited = true;
//       notifyListeners();
//     }
//   }

//   Future<void> runLca() async {
//     isRunning = true;
//     notifyListeners();
//     try {
//       final updated = await LcaController.run(_lcaResult);
//       _lcaResult = updated;
//       _parseResult(updated);
//     } catch (e) {
//       // TODO: show Snackbar with error
//     } finally {
//       isRunning = false;
//       notifyListeners();
//     }
//   }

//   void selectProcess(ProcessNode? p) {
//     selectedProcess = p;
//     notifyListeners();
//   }

//   void selectProcessByName(String name) {
//     final p = processes.firstWhere(
//       (x) => x.name == name,
//       orElse: () => processes.first,
//     );
//     selectProcess(p);
//   }

//   void commitProcessEdits(ProcessNode updated) {
//     final idx = processes.indexWhere((p) => p.id == updated.id);
//     if (idx != -1) {
//       processes[idx] = updated;
//       _lcaResult['process_loop'][idx]['process'] = updated.name;
//       _lcaResult['process_loop'][idx]['uncertainty'] =
//           updated.uncertaintyValue;
//       _edited = true;
//       notifyListeners();
//     }
//   }

//   void deleteProcess(ProcessNode p) {
//     processes.removeWhere((x) => x.id == p.id);
//     _lcaResult['process_loop']
//         .removeWhere((e) => e['process'] == p.id);
//     flows.removeWhere((f) => f.from == p.id || f.to == p.id);
//     _lcaResult['flows_enriched']
//         .removeWhere((e) => e['from_process'] == p.id || e['to_process'] == p.id);
//     selectedProcess = null;
//     _edited = true;
//     notifyListeners();
//   }

//   void deleteFlow(FlowLink f) {
//     flows.removeWhere((x) => x.id == f.id);
//     _lcaResult['flows_enriched'].removeWhere((e) {
//       return e['name'] == f.name &&
//           e['from_process'] == f.from &&
//           e['to_process'] == f.to;
//     });
//     _edited = true;
//     notifyListeners();
//   }

//   void reconnectFlow(FlowLink f, String newFrom, String newTo) {
//     final idx = flows.indexWhere((x) => x.id == f.id);
//     if (idx != -1) {
//       flows[idx] = f.copyWith(from: newFrom, to: newTo);
//       _lcaResult['flows_enriched'][idx]['from_process'] = newFrom;
//       _lcaResult['flows_enriched'][idx]['to_process'] = newTo;
//       _edited = true;
//       notifyListeners();
//     }
//   }

//   List<FlowLink> flowsFor(ProcessNode p) =>
//       flows.where((f) => f.from == p.id || f.to == p.id).toList();

//   Color colorOf(UncertaintyLevel u) {
//     switch (u) {
//       case UncertaintyLevel.user:
//         return Colors.blue;
//       case UncertaintyLevel.database:
//         return Colors.green;
//       case UncertaintyLevel.adapted:
//         return Colors.orange;
//       case UncertaintyLevel.inferred:
//         return Colors.red;
//     }
//   }
// }
// lib/pages/graph_pipeline.dart
// lib/pages/graph_pipeline.dart

// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';

// import 'process_node.dart';
// import 'flow_link.dart';
// import 'uncertainty_level.dart';
// import 'lca_controller.dart';
// import 'graph_view_widget.dart';
// import 'impact_bar_chart.dart';

// class GraphPipelinePage extends StatelessWidget {
//   final Map<String, dynamic> initialLcaResult;

//   const GraphPipelinePage({
//     Key? key,
//     required this.initialLcaResult,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return ChangeNotifierProvider<GraphPipelineViewModel>(
//       create: (_) => GraphPipelineViewModel(initialLcaResult),
//       child: const _GraphPipelineView(),
//     );
//   }
// }

// class _GraphPipelineView extends StatelessWidget {
//   const _GraphPipelineView({Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     final vm = context.watch<GraphPipelineViewModel>();

//     return Scaffold(
//       backgroundColor: Colors.white,
//       appBar: AppBar(
//         backgroundColor: Colors.white,
//         title: const Text('LCA Pipeline'),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             tooltip: 'Re-run LCA',
//             onPressed: vm.isRunning ? null : vm.runLca,
//           ),
//         ],
//       ),
//       body: vm.isRunning
//           ? const Center(child: CircularProgressIndicator())
//           : LayoutBuilder(
//               builder: (context, constraints) {
//                 // If wide, arrange side-by-side; otherwise stack.
//                 final isWide = constraints.maxWidth >= 800;
//                 return isWide
//                     ? Row(
//                         children: [
//                           // Graph takes 2/3 of width
//                           Expanded(
//                             flex: 2,
//                             child: GraphViewWidget(
//                               processes: vm.processes,
//                               flows: vm.flows,
//                               onTapNode: vm.selectProcess,
//                               colorOf: vm.colorOf,
//                               selectedProcessId: vm.selectedProcess?.id,
//                             ),
//                           ),
//                           // Divider
//                           const VerticalDivider(width: 1),
//                           // Chart takes 1/3 of width
//                           Expanded(
//                             flex: 1,
//                             child: Padding(
//                               padding: const EdgeInsets.all(12),
//                               child: Container(
//                                 color: Colors.white,
//                                 child: ImpactBarChart(
//                                   totalImpact: vm.totalImpact,
//                                   perProcessImpact: vm.perProcessImpact,
//                                   methodLabel: vm.methodLabel,
//                                   onBarTap: vm.selectProcessByName,
//                                 ),
//                               ),
//                             ),
//                           ),
//                         ],
//                       )
//                     : Column(
//                         children: [
//                           // Graph on top
//                           Expanded(
//                             flex: 2,
//                             child: GraphViewWidget(
//                               processes: vm.processes,
//                               flows: vm.flows,
//                               onTapNode: vm.selectProcess,
//                               colorOf: vm.colorOf,
//                               selectedProcessId: vm.selectedProcess?.id,
//                             ),
//                           ),
//                           const Divider(height: 1),
//                           // Chart below
//                           Expanded(
//                             flex: 1,
//                             child: Padding(
//                               padding: const EdgeInsets.all(12),
//                               child: Container(
//                                 color: Colors.white,
//                                 child: ImpactBarChart(
//                                   totalImpact: vm.totalImpact,
//                                   perProcessImpact: vm.perProcessImpact,
//                                   methodLabel: vm.methodLabel,
//                                   onBarTap: vm.selectProcessByName,
//                                 ),
//                               ),
//                             ),
//                           ),
//                         ],
//                       );
//               },
//             ),
//     );
//   }
// }

// /// ViewModel holds all LCA state: processes, flows, impacts, selection, run flag.
// class GraphPipelineViewModel extends ChangeNotifier {
//   Map<String, dynamic> _lcaResult;
//   List<ProcessNode> processes = [];
//   List<FlowLink> flows = [];
//   double totalImpact = 0;
//   Map<String, double> perProcessImpact = {};
//   String methodLabel = '';

//   bool isRunning = false;
//   ProcessNode? selectedProcess;

//   GraphPipelineViewModel(this._lcaResult) {
//     _parseResult(_lcaResult);
//   }

//   void _parseResult(Map<String, dynamic> r) {
//     processes = ProcessNode.fromLcaJson(r);
//     flows = FlowLink.fromLcaJson(r);
//     methodLabel = (r['method'] as List<dynamic>?)
//             ?.join(' – ')
//             .toString() ??
//         '';
//     totalImpact = (r['totalImpact'] as num?)?.toDouble() ?? 0;
//     perProcessImpact =
//         Map<String, double>.from(r['perProcessImpact'] ?? {});
//     isRunning = false;
//     selectedProcess = null;
//     notifyListeners();
//   }

//   Future<void> runLca() async {
//     isRunning = true;
//     notifyListeners();
//     try {
//       final updated = await LcaController.run(_lcaResult);
//       _lcaResult = updated;
//       _parseResult(updated);
//     } catch (e) {
//       // TODO: show a Snackbar with error
//       isRunning = false;
//       notifyListeners();
//     }
//   }

//   void selectProcess(ProcessNode p) {
//     selectedProcess = p;
//     notifyListeners();
//   }

//   void selectProcessByName(String name) {
//     final p = processes.firstWhere(
//       (x) => x.name == name,
//       orElse: () => processes.first,
//     );
//     selectProcess(p);
//   }

//   Color colorOf(UncertaintyLevel u) {
//     switch (u) {
//       case UncertaintyLevel.user:
//         return Colors.blue;
//       case UncertaintyLevel.database:
//         return Colors.green;
//       case UncertaintyLevel.adapted:
//         return Colors.orange;
//       case UncertaintyLevel.inferred:
//         return Colors.red;
//     }
//   }
// }
// lib/pages/graph_pipeline.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data_panel.dart';
import 'process_node.dart';
import 'flow_link.dart';
import 'uncertainty_level.dart';
import 'lca_controller.dart';
import 'graph_view_widget.dart';
import 'impact_bar_chart.dart';

class GraphPipelinePage extends StatelessWidget {
  final Map<String, dynamic> initialLcaResult;

  const GraphPipelinePage({
    Key? key,
    required this.initialLcaResult,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GraphPipelineViewModel>(
      create: (_) => GraphPipelineViewModel(initialLcaResult),
      child: const _GraphPipelineView(),
    );
  }
}

class _GraphPipelineView extends StatelessWidget {
  const _GraphPipelineView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GraphPipelineViewModel>();

    return Scaffold(
      backgroundColor: Colors.white,
appBar: AppBar(
  backgroundColor: Colors.white,
  leading: IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => Navigator.of(context).maybePop(),
  ),
  title: const Text('LCA Pipeline'),
  actions: [
    IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: 'Re-run LCA',
      onPressed: vm.isRunning ? null : vm.runLca,
    ),
  ],
),
      body: vm.isRunning
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;
                return isWide
                    ? Row(
                        children: [
                          
                          // ─── Graph ─────────────────────────────
                          Expanded(
                            flex: 2,
                            child: GraphViewWidget(
                              processes: vm.processes,
                              flows: vm.flows,
                              onTapNode: vm.selectProcess,
                              colorOf: vm.colorOf,
                              selectedProcessId: vm.selectedProcess?.id,
                            ),
                          ),

                          const VerticalDivider(width: 1),

                          // ─── Right Pane: Impacts & Data ──────────
                          Expanded(
                            flex: 1,
                            child: DefaultTabController(
                              length: 2,
                              child: Column(
                                children: [
                                  Material(
                                    color: Colors.white,
                                    child: const TabBar(
                                      labelColor: Colors.black87,
                                      tabs: [
                                        Tab(
                                          icon: Icon(Icons.bar_chart),
                                          text: 'Impacts',
                                        ),
                                        Tab(
                                          icon: Icon(Icons.table_chart),
                                          text: 'Data',
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      color: Colors.white,
                                      child: TabBarView(
                                        children: [
                                          // ── Impacts Chart ────────────
                                          Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: ImpactBarChart(
                                              totalImpact: vm.totalImpact,
                                              emissions_per_process:
                                                  vm.emissions_per_process,
                                              methodLabel: vm.methodLabel,
                                              onBarTap: vm.selectProcessByName,
                                            ),
                                          ),
                                      
                                          // ── Data Table ───────────────
                                          Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: DataPanel(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // const UncertaintyLegend(),

                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    // ── Narrow: stack graph then tabs ─────────
                    : Column(
                        children: [
                          Expanded(
                            flex: 2,
                            child: GraphViewWidget(
                              processes: vm.processes,
                              flows: vm.flows,
                              onTapNode: vm.selectProcess,
                              colorOf: vm.colorOf,
                              selectedProcessId: vm.selectedProcess?.id,
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            flex: 1,
                            child: DefaultTabController(
                              length: 2,
                              child: Column(
                                children: [
                                  Material(
                                    color: Colors.white,
                                    child: const TabBar(
                                      labelColor: Colors.black87,
                                      tabs: [
                                        Tab(
                                          icon: Icon(Icons.bar_chart),
                                          text: 'Impacts',
                                        ),
                                        Tab(
                                          icon: Icon(Icons.table_chart),
                                          text: 'Data',
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: TabBarView(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: ImpactBarChart(
                                            totalImpact: vm.totalImpact,
                                            emissions_per_process:
                                                vm.emissions_per_process,
                                            methodLabel: vm.methodLabel,
                                            onBarTap:
                                                vm.selectProcessByName,
                                          ),
                                        ),
                                        Text("Meaning of colors on processes"),
                                        Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: DataPanel()
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
              },
            ),
    );
  }
}
 
/// ViewModel holds all LCA state: processes, flows, impacts, selection, run flag.
class GraphPipelineViewModel extends ChangeNotifier {
  Map<String, dynamic> _lcaResult;
  List<ProcessNode> processes = [];
  List<FlowLink> flows = [];
  double totalImpact = 0;
  Map<String, double> emissions_per_process = {};
  String methodLabel = '';
  Map<String, dynamic> get rawResult => _lcaResult;

  bool isRunning = false;
  ProcessNode? selectedProcess;

  GraphPipelineViewModel(this._lcaResult) {
    _parseResult(_lcaResult);
  }

  // void _parseResult(Map<String, dynamic> r) {
  //   processes = ProcessNode.fromLcaJson(r);
  //   flows = FlowLink.fromLcaJson(r);
  //   methodLabel = (r['method'] as List<dynamic>?)?.join(' – ') ?? '';
  //   totalImpact = (r['totalImpact'] as num?)?.toDouble() ?? 0;
  //   emissions_per_process = Map<String, double>.from(r['emissions_per_process'] ?? {});
  //   isRunning = false;
  //   selectedProcess = null;
  //   notifyListeners();
  // }
void _parseResult(Map<String, dynamic> r) {
  final bw = r['brightway_result'] as Map<String, dynamic>? ?? {};

  emissions_per_process = Map<String, double>.from(
    (bw['emissions_per_process'] as Map?)?.map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ) ??
        {},
  );

  totalImpact = (bw['score'] as num?)?.toDouble() ?? 0.0;
  methodLabel = (bw['method'] as List<dynamic>?)?.join(' – ') ?? '';

  processes = ProcessNode.fromLcaJson(r);
  flows = FlowLink.fromLcaJson(r);
  isRunning = false;
  selectedProcess = null;
  notifyListeners();
}

  Future<void> runLca() async {
    isRunning = true;
    notifyListeners();
    try {
      final updated = await LcaController.run(_lcaResult);
      _lcaResult = updated;
      _parseResult(updated);
    } catch (e) {
      // TODO: show a Snackbar with error
      isRunning = false;
      notifyListeners();
    }
  }

  void selectProcess(ProcessNode p) {
    selectedProcess = p;
    notifyListeners();
  }

  void selectProcessByName(String name) {
    final p = processes.firstWhere(
      (x) => x.name == name,
      orElse: () => processes.first,
    );
    selectProcess(p);
  }

  Color colorOf(UncertaintyLevel u) {
    switch (u) {
      case UncertaintyLevel.user:
        return Colors.blue;
      case UncertaintyLevel.database:
        return Colors.green;
      case UncertaintyLevel.adapted:
        return Colors.orange;
      case UncertaintyLevel.inferred:
        return Colors.red;
    }
  }
}


class UncertaintyLegend extends StatelessWidget {
  const UncertaintyLegend({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget item(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(label),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Wrap(
        spacing: 24,
        children: [
          item(Colors.blue, 'User stated'),
          item(Colors.green, 'From database'),
          item(Colors.yellow, 'Database edited by LLM'),
          item(Colors.red, 'From LLM'),
        ],
      ),
    );
  }
}
