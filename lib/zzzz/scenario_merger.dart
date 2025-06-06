// // File: lib/zzzz/scenario_merger.dart

// import 'dart:ui';

// import 'home.dart';

// /// Merge the LLM‐returned “changes” into full scenario models.
// ///
// /// - [baseModel]: { "processes":[…], "flows":[…] }
// /// - [scenariosDeltas]: { scenarioName: { "changes":[…] }, … }
// ///
// /// Returns:
// ///   { "scenarios": { scenarioName: { "model":{ "processes":[…], "flows":[…] } }, … } }
// Map<String, dynamic> mergeScenarios(
//   Map<String, dynamic> baseModel,
//   Map<String, dynamic> scenariosDeltas,
// ) {
//   final baseProcessesJson =
//       (baseModel['processes'] as List<dynamic>).cast<Map<String, dynamic>>();
//   final baseFlows =
//       List<Map<String, dynamic>>.from(baseModel['flows'] as List);

//   // Convert JSON → List<ProcessNode>
//   final List<ProcessNode> baseProcesses = baseProcessesJson
//       .map((j) => ProcessNode.fromJson(j))
//       .toList();

//   final mergedScenarios = <String, dynamic>{};

//   scenariosDeltas.forEach((scenarioName, scenarioContent) {
//     // Extract the “deltas” for this scenario
//     final deltas = (scenarioContent['changes'] as List<dynamic>)
//         .cast<Map<String, dynamic>>();

//     // Apply them to get a new list of ProcessNode
//     final fullProcesses = _applyScenarioDelays(baseProcesses, deltas);

//     // Recompute flows based on output→input matching
//     final fullFlows = _computeFlowsFromProcesses(fullProcesses);

//     // Convert updated processes back to JSON
//     final fullProcessesJson =
//         fullProcesses.map((p) => p.toJson()).toList();

//     mergedScenarios[scenarioName] = {
//       'model': {
//         'processes': fullProcessesJson,
//         'flows': fullFlows,
//       }
//     };
//   });

//   return {'scenarios': mergedScenarios};
// }

// /// Applies a scenario’s “deltas” to the base processes.
// List<ProcessNode> _applyScenarioDelays(
//   List<ProcessNode> baseProcesses,
//   List<Map<String, dynamic>> deltas,
// ) {
//   // 1) Group deltas by process_id
//   final byProcess = <String, List<Map<String, dynamic>>>{};
//   for (var change in deltas) {
//     final pid = change['process_id'] as String;
//     byProcess.putIfAbsent(pid, () => []).add(change);
//   }

//   final newProcesses = <ProcessNode>[];

//   for (var orig in baseProcesses) {
//     final pid = orig.id;
//     final procChanges = byProcess[pid] ?? [];

//     if (procChanges.isEmpty) {
//       // No changes → keep the original
//       newProcesses.add(orig);
//       continue;
//     }

//     // 2) Split “input‐amount” changes vs explicit “output” or “co2” overrides
//     final inputChanges = <Map<String, dynamic>>[];
//     final explicitOtherChanges = <Map<String, dynamic>>[];

//     for (var ch in procChanges) {
//       final field = ch['field'] as String;
//       if (field.startsWith('inputs.') && field.endsWith('.amount')) {
//         inputChanges.add(ch);
//       } else {
//         explicitOtherChanges.add(ch);
//       }
//     }

//     // 3) Derive changes for outputs and co2 from any inputChanges
//     final derivedChanges = _propagateChangesForProcess(orig, inputChanges);

//     // 4) Merge all (inputChanges + explicitOtherChanges + derivedChanges)
//     final allChanges = <Map<String, dynamic>>[];
//     allChanges.addAll(inputChanges);
//     allChanges.addAll(explicitOtherChanges);
//     allChanges.addAll(derivedChanges);

//     // 5) Apply them to a copy of orig
//     final updated = _applyAllChangesToProcess(orig, allChanges);
//     newProcesses.add(updated);
//   }

//   return newProcesses;
// }

// /// For each “inputs.<Flow>.amount” change, compute proportional “outputs.*.amount”
// /// and “co2” changes. Returns those derived changes.
// List<Map<String, dynamic>> _propagateChangesForProcess(
//   ProcessNode proc,
//   List<Map<String, dynamic>> inputChanges,
// ) {
//   final derived = <Map<String, dynamic>>[];

//   for (var change in inputChanges) {
//     final fieldPath = change['field'] as String;
//     final newValue = (change['new_value'] as num).toDouble();

//     // Expect "inputs.<InputName>.amount"
//     final parts = fieldPath.split('.');
//     if (parts.length == 3 && parts[0] == 'inputs' && parts[2] == 'amount') {
//       final inputName = parts[1];
//       final origInput = proc.inputs.firstWhere(
//         (f) => f.name == inputName,
//         orElse: () => FlowValue(name: inputName, amount: 0, unit: ''),
//       );
//       final oldInputAmt = origInput.amount;
//       if (oldInputAmt == 0) continue; // avoid division by zero

//       final ratioFactor = newValue / oldInputAmt;

//       // 1) Scale outputs
//       for (var outFlow in proc.outputs) {
//         final oldOutAmt = outFlow.amount;
//         final newOutAmt = double.parse((oldOutAmt * ratioFactor).toStringAsFixed(6));
//         derived.add({
//           'process_id': proc.id,
//           'field': 'outputs.${outFlow.name}.amount',
//           'new_value': newOutAmt,
//         });
//       }

//       // 2) Scale co2
//       final oldCo2 = proc.co2;
//       final newCo2 = double.parse((oldCo2 * ratioFactor).toStringAsFixed(6));
//       derived.add({
//         'process_id': proc.id,
//         'field': 'co2',
//         'new_value': newCo2,
//       });
//     }
//   }

//   return derived;
// }

// /// Apply a mixed set of “co2”, “inputs.*”, and “outputs.*” changes to a ProcessNode,
// /// returning a brand‐new ProcessNode with updated input/output/CO₂.
// ProcessNode _applyAllChangesToProcess(
//   ProcessNode orig,
//   List<Map<String, dynamic>> changes,
// ) {
//   final String name = orig.name;
//   double co2 = orig.co2;
//   final Offset position = orig.position;

//   // Deep copies of inputs & outputs
//   final inputs = orig.inputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();
//   final outputs = orig.outputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();

//   // Apply each change
//   for (var ch in changes) {
//     final field = ch['field'] as String;
//     final newVal = ch['new_value'];

//     if (field == 'co2') {
//       co2 = (newVal as num).toDouble();
//     } else if (field.startsWith('inputs.')) {
//       // "inputs.<InputName>.amount" or "inputs.<InputName>.unit"
//       final parts = field.split('.');
//       final inName = parts[1];
//       final subField = parts[2]; // "amount" or "unit"

//       final idx = inputs.indexWhere((f) => f.name == inName);
//       if (idx >= 0) {
//         final old = inputs[idx];
//         if (subField == 'amount') {
//           inputs[idx] = FlowValue(
//             name: old.name,
//             amount: (newVal as num).toDouble(),
//             unit: old.unit,
//           );
//         } else if (subField == 'unit') {
//           inputs[idx] = FlowValue(
//             name: old.name,
//             amount: old.amount,
//             unit: newVal as String,
//           );
//         }
//       }
//     } else if (field.startsWith('outputs.')) {
//       // "outputs.<OutputName>.amount" or "outputs.<OutputName>.unit"
//       final parts = field.split('.');
//       final outName = parts[1];
//       final subField = parts[2];

//       final idx = outputs.indexWhere((f) => f.name == outName);
//       if (idx >= 0) {
//         final old = outputs[idx];
//         if (subField == 'amount') {
//           outputs[idx] = FlowValue(
//             name: old.name,
//             amount: (newVal as num).toDouble(),
//             unit: old.unit,
//           );
//         } else if (subField == 'unit') {
//           outputs[idx] = FlowValue(
//             name: old.name,
//             amount: old.amount,
//             unit: newVal as String,
//           );
//         }
//       }
//     }
//   }

//   return ProcessNode(
//     id: orig.id,
//     name: name,
//     inputs: inputs,
//     outputs: outputs,
//     co2: co2,
//     position: position,
//   );
// }

// /// Recompute “flows” by matching each process’s outputs → any other process’s inputs (case‐insensitive).
// List<Map<String, dynamic>> _computeFlowsFromProcesses(
//   List<ProcessNode> processes,
// ) {
//   final flows = <Map<String, dynamic>>[];

//   for (var producer in processes) {
//     for (var outVal in producer.outputs) {
//       final outNameLower = outVal.name.trim().toLowerCase();
//       for (var consumer in processes) {
//         if (consumer.id == producer.id) continue;
//         final match = consumer.inputs.any(
//             (inp) => inp.name.trim().toLowerCase() == outNameLower);
//         if (match) {
//           flows.add({
//             'from': producer.id,
//             'to': consumer.id,
//             'names': [outVal.name],
//           });
//         }
//       }
//     }
//   }

//   return flows;
// }



// // File: lib/zzzz/scenario_merger.dart

// import 'dart:collection';
// import 'home.dart';

// /// Holds adjacency information for quick lookup.
// class Adjacency {
//   final Map<String, List<String>> producersByFlow;
//   final Map<String, List<String>> consumersByFlow;
//   final Map<String, ProcessNode> processById;

//   Adjacency({
//     required this.producersByFlow,
//     required this.consumersByFlow,
//     required this.processById,
//   });
// }

// /// Builds adjacency maps so that for any flow name, you can find which processes
// /// produce it (upstream) and which consume it (downstream), and also easily look up
// /// any ProcessNode by its ID.
// Adjacency buildAdjacency(
//   List<ProcessNode> processes,
//   List<Map<String, dynamic>> flows,
// ) {
//   final Map<String, List<String>> producersByFlow = {};
//   final Map<String, List<String>> consumersByFlow = {};
//   final Map<String, ProcessNode> processById = {};

//   for (var p in processes) {
//     processById[p.id] = p;
//   }

//   for (var conn in flows) {
//     final String fromId = conn['from'] as String;
//     final String toId = conn['to'] as String;
//     final List<String> names = List<String>.from(conn['names'] as List);

//     for (var fName in names) {
//       producersByFlow.putIfAbsent(fName, () => []).add(fromId);
//       consumersByFlow.putIfAbsent(fName, () => []).add(toId);
//     }
//   }

//   return Adjacency(
//     producersByFlow: producersByFlow,
//     consumersByFlow: consumersByFlow,
//     processById: processById,
//   );
// }

// /// Computes a scale factor for a single process when it has one or more flow changes.
// /// - If there is exactly one flow change, returns (newValue / oldValue).
// /// - If multiple flows changed, sums old amounts and new amounts, then returns (newSum / oldSum).
// double computeScaleFactorForProcess(
//   ProcessNode orig,
//   List<Map<String, dynamic>> deltas,
// ) {
//   final Map<String, double> newAmounts = {};
//   final Map<String, double> oldAmounts = {};

//   for (var change in deltas) {
//     final String field = change['field'] as String; // e.g. "inputs.diesel.amount"
//     final double newVal = (change['new_value'] as num).toDouble();
//     final parts = field.split('.');
//     final flowName = parts[1];

//     newAmounts[flowName] = newVal;
//     if (parts[0] == 'inputs') {
//       final matched = orig.inputs.firstWhere((f) => f.name == flowName);
//       oldAmounts[flowName] = matched.amount;
//     } else {
//       final matched = orig.outputs.firstWhere((f) => f.name == flowName);
//       oldAmounts[flowName] = matched.amount;
//     }
//   }

//   if (newAmounts.length == 1) {
//     final fn = newAmounts.keys.first;
//     final oldVal = oldAmounts[fn]!;
//     if (oldVal == 0) return 1.0;
//     return newAmounts[fn]! / oldVal;
//   }

//   double oldSum = 0.0, newSum = 0.0;
//   newAmounts.forEach((fname, nval) {
//     oldSum += oldAmounts[fname]!;
//     newSum += nval;
//   });
//   if (oldSum == 0) return 1.0;
//   return newSum / oldSum;
// }

// /// Applies deltas (field changes) to a single ProcessNode, returning a new ProcessNode.
// /// - Overrides any inputs.*.amount or outputs.*.amount or co2 if specified.
// /// - Computes a scale factor (if more than one flow changed) and scales all inputs, outputs, and co2.
// ProcessNode applyDeltasToProcess(
//   ProcessNode orig,
//   List<Map<String, dynamic>> deltas,
// ) {
//   // Copy inputs/outputs into mutable lists
//   List<FlowValue> newInputs = orig.inputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();
//   List<FlowValue> newOutputs = orig.outputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();
//   double newCo2 = orig.co2;

//   // Override co2 if needed
//   for (var change in deltas) {
//     final field = change['field'] as String;
//     if (field == 'co2') {
//       newCo2 = (change['new_value'] as num).toDouble();
//     }
//   }

//   // Override individual input/output amounts
//   for (var change in deltas) {
//     final String field = change['field'] as String; // e.g. "inputs.diesel.amount"
//     final double newVal = (change['new_value'] as num).toDouble();
//     final parts = field.split('.');
//     final isInput = (parts[0] == 'inputs');
//     final flowName = parts[1];

//     if (isInput) {
//       for (int i = 0; i < newInputs.length; i++) {
//         if (newInputs[i].name == flowName) {
//           newInputs[i] =
//               FlowValue(name: flowName, amount: newVal, unit: newInputs[i].unit);
//         }
//       }
//     } else {
//       for (int i = 0; i < newOutputs.length; i++) {
//         if (newOutputs[i].name == flowName) {
//           newOutputs[i] =
//               FlowValue(name: flowName, amount: newVal, unit: newOutputs[i].unit);
//         }
//       }
//     }
//   }

//   // Compute scale factor
//   final scale = computeScaleFactorForProcess(orig, deltas);

//   if ((scale - 1.0).abs() > 1e-9) {
//     newInputs = newInputs
//         .map((f) => FlowValue(name: f.name, amount: f.amount * scale, unit: f.unit))
//         .toList();
//     newOutputs = newOutputs
//         .map((f) => FlowValue(name: f.name, amount: f.amount * scale, unit: f.unit))
//         .toList();
//     newCo2 = newCo2 * scale;
//   }

//   return ProcessNode(
//     id: orig.id,
//     name: orig.name,
//     inputs: newInputs,
//     outputs: newOutputs,
//     co2: newCo2,
//     position: orig.position,
//   );
// }

// /// Merges baseModel + scenario‐specific deltas into fully balanced scenario models.
// /// 
// /// baseModel: {
// ///   'processes': [ { … each ProcessNode.toJson() … } ],
// ///   'flows':      [ { 'from': pidA, 'to': pidB, 'names': [flowName,…] }, … ]
// /// }
// /// 
// /// allDeltasByScenario: {
// ///   'scenarioName': [
// ///     { 'process_id': 'P', 'field': 'inputs.diesel.amount', 'new_value': 25.0 },
// ///     …
// ///   ],
// ///   …
// /// }
// /// 
// /// Returns:
// /// {
// ///   'scenarioName': {
// ///     'model': {
// ///       'processes': [ … final ProcessNode.toJson() … ],
// ///       'flows': [ … same as baseModel['flows'] … ]
// ///     }
// ///   },
// ///   …
// /// }
// Map<String, Map<String, dynamic>> mergeScenarios(
//   Map<String, dynamic> baseModel,
//   Map<String, List<Map<String, dynamic>>> allDeltasByScenario,
// ) {
//   // 1) Extract base processes + flows
//   final baseProcessesJson = List<Map<String, dynamic>>.from(baseModel['processes'] as List);
//   final baseFlowsJson = List<Map<String, dynamic>>.from(baseModel['flows'] as List);

//   // Convert JSON → ProcessNode
//   final baseProcesses =
//       baseProcessesJson.map((j) => ProcessNode.fromJson(j)).toList();

//   // Build adjacency maps once (use the original baseProcesses)
//   final adjacency = buildAdjacency(baseProcesses, baseFlowsJson);

//   final Map<String, Map<String, dynamic>> result = {};

//   // 2) For each scenario
//   allDeltasByScenario.forEach((scenarioName, rawDeltas) {
//     // 2a) Clone base processes into a mutable map by ID
//     final Map<String, ProcessNode> cloned = {};
//     for (var p in baseProcesses) {
//       cloned[p.id] = ProcessNode.fromJson(p.toJson());
//     }

//     // 2b) Group raw deltas by process_id
//     final Map<String, List<Map<String, dynamic>>> deltasByProcess = {};
//     for (var d in rawDeltas) {
//       final pid = d['process_id'] as String;
//       deltasByProcess.putIfAbsent(pid, () => []).add(d);
//     }

//     // 2c) Apply each process's direct deltas (absolute overrides + scaling)
//     //     and enqueue those processes for propagation.
//     final Queue<String> toVisit = Queue<String>();
//     for (var pid in deltasByProcess.keys) {
//       final orig = adjacency.processById[pid]!;
//       final updated = applyDeltasToProcess(orig, deltasByProcess[pid]!);
//       cloned[pid] = updated;
//       toVisit.add(pid);
//     }

//     // 2d) BFS propagation up/down the graph
//     final Set<String> seen = Set<String>.of(deltasByProcess.keys);
//     while (toVisit.isNotEmpty) {
//       final currentId = toVisit.removeFirst();
//       final curr = cloned[currentId]!;

//       // --- Propagate Input Changes Upstream ---
//       for (var inFlow in curr.inputs) {
//         final flowName = inFlow.name;
//         final newAmount = inFlow.amount;

//         final origProc = adjacency.processById[currentId]!;
//         final oldAmount = origProc.inputs
//             .firstWhere((f) => f.name == flowName)
//             .amount;
//         final deltaAmt = newAmount - oldAmount;
//         if (deltaAmt.abs() < 1e-9) continue;

//         final upstreams = adjacency.producersByFlow[flowName] ?? [];
//         for (var prodId in upstreams) {
//           if (prodId == currentId) continue;
//           final prodNode = cloned[prodId]!;
//           final origProd = adjacency.processById[prodId]!;
//           final oldOutVal = origProd.outputs
//               .firstWhere((f) => f.name == flowName)
//               .amount;
//           final newOutVal = (oldOutVal + deltaAmt).clamp(0.0, double.infinity);

//           final overrideDelta = {
//             'process_id': prodId,
//             'field': 'outputs.$flowName.amount',
//             'new_value': newOutVal,
//           };
//           final accum = (deltasByProcess[prodId] ?? []).toList();
//           accum.add(overrideDelta);
//           deltasByProcess[prodId] = accum;

//           final reScaled = applyDeltasToProcess(origProd, accum);
//           cloned[prodId] = reScaled;

//           if (!seen.contains(prodId)) {
//             seen.add(prodId);
//             toVisit.add(prodId);
//           }
//         }
//       }

//       // --- Propagate Output Changes Downstream ---
//       for (var outFlow in curr.outputs) {
//         final flowName = outFlow.name;
//         final newAmount = outFlow.amount;

//         final origProc = adjacency.processById[currentId]!;
//         final oldAmount = origProc.outputs
//             .firstWhere((f) => f.name == flowName)
//             .amount;
//         final deltaAmt = newAmount - oldAmount;
//         if (deltaAmt.abs() < 1e-9) continue;

//         final downstreams = adjacency.consumersByFlow[flowName] ?? [];
//         for (var consId in downstreams) {
//           if (consId == currentId) continue;
//           final consNode = cloned[consId]!;
//           final origCons = adjacency.processById[consId]!;
//           final oldInVal = origCons.inputs
//               .firstWhere((f) => f.name == flowName)
//               .amount;
//           final newInVal = (oldInVal + deltaAmt).clamp(0.0, double.infinity);

//           final overrideDelta = {
//             'process_id': consId,
//             'field': 'inputs.$flowName.amount',
//             'new_value': newInVal,
//           };
//           final accum = (deltasByProcess[consId] ?? []).toList();
//           accum.add(overrideDelta);
//           deltasByProcess[consId] = accum;

//           final reScaled = applyDeltasToProcess(origCons, accum);
//           cloned[consId] = reScaled;

//           if (!seen.contains(consId)) {
//             seen.add(consId);
//             toVisit.add(consId);
//           }
//         }
//       }
//     }

//     // 2e) Build final JSON for this scenario
//     final List<Map<String, dynamic>> finalProcessesJson = [];
//     for (var p in cloned.values) {
//       finalProcessesJson.add(p.toJson());
//     }
//     result[scenarioName] = {
//       'model': {
//         'processes': finalProcessesJson,
//         'flows': baseFlowsJson,
//       }
//     };
//   });

//   return result;
// }


// // File: lib/zzzz/scenario_merger.dart

// import 'dart:collection';
// import 'home.dart';  // ProcessNode, FlowValue, etc.

// /// Holds adjacency information for quick lookup.
// class Adjacency {
//   final Map<String, List<String>> producersByFlow;
//   final Map<String, List<String>> consumersByFlow;
//   final Map<String, ProcessNode> processById;

//   Adjacency({
//     required this.producersByFlow,
//     required this.consumersByFlow,
//     required this.processById,
//   });
// }

// /// Builds adjacency maps so that for any flow name, you can find which
// /// processes produce it (upstream) and which consume it (downstream),
// /// and also easily look up any ProcessNode by its ID.
// Adjacency buildAdjacency(
//   List<ProcessNode> processes,
//   List<Map<String, dynamic>> flows,
// ) {
//   final Map<String, List<String>> producersByFlow = {};
//   final Map<String, List<String>> consumersByFlow = {};
//   final Map<String, ProcessNode> processById = {};

//   for (var p in processes) {
//     processById[p.id] = p;
//   }

//   for (var conn in flows) {
//     final String fromId = conn['from'] as String;
//     final String toId = conn['to'] as String;
//     final List<String> names = List<String>.from(conn['names'] as List);

//     for (var fName in names) {
//       producersByFlow.putIfAbsent(fName, () => []).add(fromId);
//       consumersByFlow.putIfAbsent(fName, () => []).add(toId);
//     }
//   }

//   return Adjacency(
//     producersByFlow: producersByFlow,
//     consumersByFlow: consumersByFlow,
//     processById: processById,
//   );
// }

// /// Computes a scale factor for a single process when it has one or more flow changes.
// /// - If there is exactly one flow change, returns (newValue / oldValue).
// /// - If multiple flows changed, sums old amounts and new amounts, then returns (newSum / oldSum).
// double computeScaleFactorForProcess(
//   ProcessNode orig,
//   List<Map<String, dynamic>> deltas,
// ) {
//   final Map<String, double> newAmounts = {};
//   final Map<String, double> oldAmounts = {};

//   for (var change in deltas) {
//     final String field = change['field'] as String; // e.g. "inputs.diesel.amount"
//     final double newVal = (change['new_value'] as num).toDouble();
//     final parts = field.split('.');
//     final flowName = parts[1];

//     newAmounts[flowName] = newVal;
//     if (parts[0] == 'inputs') {
//       final matched = orig.inputs.firstWhere((f) => f.name == flowName);
//       oldAmounts[flowName] = matched.amount;
//     } else {
//       final matched = orig.outputs.firstWhere((f) => f.name == flowName);
//       oldAmounts[flowName] = matched.amount;
//     }
//   }

//   if (newAmounts.length == 1) {
//     final fn = newAmounts.keys.first;
//     final oldVal = oldAmounts[fn]!;
//     if (oldVal == 0) return 1.0;
//     return newAmounts[fn]! / oldVal;
//   }

//   double oldSum = 0.0, newSum = 0.0;
//   newAmounts.forEach((fname, nval) {
//     oldSum += oldAmounts[fname]!;
//     newSum += nval;
//   });
//   if (oldSum == 0) return 1.0;
//   return newSum / oldSum;
// }

// /// Applies deltas (field changes) to a single ProcessNode, returning a new ProcessNode.
// /// - Overrides any inputs.*.amount or outputs.*.amount or co2 if specified.
// /// - Computes a scale factor (if more than one flow changed) and scales all inputs, outputs, and co2.
// ProcessNode applyDeltasToProcess(
//   ProcessNode orig,
//   List<Map<String, dynamic>> deltas,
// ) {
//   // Copy inputs/outputs into mutable lists
//   List<FlowValue> newInputs = orig.inputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();
//   List<FlowValue> newOutputs = orig.outputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();
//   double newCo2 = orig.co2;

//   // Override co2 if needed
//   for (var change in deltas) {
//     final field = change['field'] as String;
//     if (field == 'co2') {
//       newCo2 = (change['new_value'] as num).toDouble();
//     }
//   }

//   // Override individual input/output amounts
//   for (var change in deltas) {
//     final String field = change['field'] as String; // e.g. "inputs.diesel.amount"
//     final double newVal = (change['new_value'] as num).toDouble();
//     final parts = field.split('.');
//     final isInput = (parts[0] == 'inputs');
//     final flowName = parts[1];

//     if (isInput) {
//       for (int i = 0; i < newInputs.length; i++) {
//         if (newInputs[i].name == flowName) {
//           newInputs[i] =
//               FlowValue(name: flowName, amount: newVal, unit: newInputs[i].unit);
//         }
//       }
//     } else {
//       for (int i = 0; i < newOutputs.length; i++) {
//         if (newOutputs[i].name == flowName) {
//           newOutputs[i] =
//               FlowValue(name: flowName, amount: newVal, unit: newOutputs[i].unit);
//         }
//       }
//     }
//   }

//   // Compute scale factor
//   final scale = computeScaleFactorForProcess(orig, deltas);

//   if ((scale - 1.0).abs() > 1e-9) {
//     newInputs = newInputs
//         .map((f) => FlowValue(name: f.name, amount: f.amount * scale, unit: f.unit))
//         .toList();
//     newOutputs = newOutputs
//         .map((f) => FlowValue(name: f.name, amount: f.amount * scale, unit: f.unit))
//         .toList();
//     newCo2 = newCo2 * scale;
//   }

//   return ProcessNode(
//     id: orig.id,
//     name: orig.name,
//     inputs: newInputs,
//     outputs: newOutputs,
//     co2: newCo2,
//     position: orig.position,
//   );
// }

// /// Merges baseModel + scenario‐specific deltas into fully balanced scenario models.
// ///
// /// baseModel: {
// ///   'processes': [ { … each ProcessNode.toJson() … } ],
// ///   'flows':      [ { 'from': pidA, 'to': pidB, 'names': [flowName,…] }, … ]
// /// }
// ///
// /// allDeltasByScenario: {
// ///   'scenarioName': [
// ///     { 'process_id': 'P', 'field': 'inputs.diesel.amount', 'new_value': 25.0 },
// ///     …
// ///   ],
// ///   …
// /// }
// ///
// /// **CORRECTED SIGNATURE**: Returns a Map whose single key is "scenarios",
// /// and whose value is itself a map of scenario‐name → { 'model': { processes, flows } }.
// Map<String, dynamic> mergeScenarios(
//   Map<String, dynamic> baseModel,
//   Map<String, List<Map<String, dynamic>>> allDeltasByScenario,
// ) {
//   // 1) Extract base processes + flows
//   final baseProcessesJson =
//       List<Map<String, dynamic>>.from(baseModel['processes'] as List);
//   final baseFlowsJson = List<Map<String, dynamic>>.from(baseModel['flows'] as List);

//   // Convert JSON → ProcessNode
//   final baseProcesses =
//       baseProcessesJson.map((j) => ProcessNode.fromJson(j)).toList();

//   // Build adjacency maps once (use the original baseProcesses)
//   final adjacency = buildAdjacency(baseProcesses, baseFlowsJson);

//   // We'll build the inner map of "scenarioName" → { 'model': { … } }
//   final Map<String, Map<String, dynamic>> resultByScenario = {};

//   // 2) For each scenario
//   allDeltasByScenario.forEach((scenarioName, rawDeltas) {
//     // 2a) Clone base processes into a mutable map by ID
//     final Map<String, ProcessNode> cloned = {};
//     for (var p in baseProcesses) {
//       cloned[p.id] = ProcessNode.fromJson(p.toJson());
//     }

//     // 2b) Group raw deltas by process_id
//     final Map<String, List<Map<String, dynamic>>> deltasByProcess = {};
//     for (var d in rawDeltas) {
//       final pid = d['process_id'] as String;
//       deltasByProcess.putIfAbsent(pid, () => []).add(d);
//     }

//     // 2c) Apply each process's direct deltas (absolute overrides + scaling)
//     //     and enqueue those processes for propagation.
//     final Queue<String> toVisit = Queue<String>();
//     for (var pid in deltasByProcess.keys) {
//       final orig = adjacency.processById[pid]!;
//       final updated = applyDeltasToProcess(orig, deltasByProcess[pid]!);
//       cloned[pid] = updated;
//       toVisit.add(pid);
//     }

//     // 2d) BFS propagation up/down the graph
//     final Set<String> seen = Set<String>.of(deltasByProcess.keys);
//     while (toVisit.isNotEmpty) {
//       final currentId = toVisit.removeFirst();
//       final curr = cloned[currentId]!;

//       // --- Propagate Input Changes Upstream ---
//       for (var inFlow in curr.inputs) {
//         final flowName = inFlow.name;
//         final newAmount = inFlow.amount;

//         final origProc = adjacency.processById[currentId]!;
//         final oldAmount = origProc.inputs
//             .firstWhere((f) => f.name == flowName)
//             .amount;
//         final deltaAmt = newAmount - oldAmount;
//         if (deltaAmt.abs() < 1e-9) continue;

//         final upstreams = adjacency.producersByFlow[flowName] ?? [];
//         for (var prodId in upstreams) {
//           if (prodId == currentId) continue;
//           final origProd = adjacency.processById[prodId]!;
//           final oldOutVal = origProd.outputs
//               .firstWhere((f) => f.name == flowName)
//               .amount;
//           final newOutVal = (oldOutVal + deltaAmt).clamp(0.0, double.infinity);

//           final overrideDelta = {
//             'process_id': prodId,
//             'field': 'outputs.$flowName.amount',
//             'new_value': newOutVal,
//           };
//           final accum = (deltasByProcess[prodId] ?? []).toList();
//           accum.add(overrideDelta);
//           deltasByProcess[prodId] = accum;

//           final reScaled = applyDeltasToProcess(origProd, accum);
//           cloned[prodId] = reScaled;

//           if (!seen.contains(prodId)) {
//             seen.add(prodId);
//             toVisit.add(prodId);
//           }
//         }
//       }

//       // --- Propagate Output Changes Downstream ---
//       for (var outFlow in curr.outputs) {
//         final flowName = outFlow.name;
//         final newAmount = outFlow.amount;

//         final origProc = adjacency.processById[currentId]!;
//         final oldAmount = origProc.outputs
//             .firstWhere((f) => f.name == flowName)
//             .amount;
//         final deltaAmt = newAmount - oldAmount;
//         if (deltaAmt.abs() < 1e-9) continue;

//         final downstreams = adjacency.consumersByFlow[flowName] ?? [];
//         for (var consId in downstreams) {
//           if (consId == currentId) continue;
//           final origCons = adjacency.processById[consId]!;
//           final oldInVal = origCons.inputs
//               .firstWhere((f) => f.name == flowName)
//               .amount;
//           final newInVal = (oldInVal + deltaAmt).clamp(0.0, double.infinity);

//           final overrideDelta = {
//             'process_id': consId,
//             'field': 'inputs.$flowName.amount',
//             'new_value': newInVal,
//           };
//           final accum = (deltasByProcess[consId] ?? []).toList();
//           accum.add(overrideDelta);
//           deltasByProcess[consId] = accum;

//           final reScaled = applyDeltasToProcess(origCons, accum);
//           cloned[consId] = reScaled;

//           if (!seen.contains(consId)) {
//             seen.add(consId);
//             toVisit.add(consId);
//           }
//         }
//       }
//     }

//     // 2e) Build final JSON for this scenario
//     final List<Map<String, dynamic>> finalProcessesJson = [];
//     for (var p in cloned.values) {
//       finalProcessesJson.add(p.toJson());
//     }
//     resultByScenario[scenarioName] = {
//       'model': {
//         'processes': finalProcessesJson,
//         'flows': baseFlowsJson,
//       }
//     };
//   });

//   // ─── WRAP the result under a top-level "scenarios" key ───
//   return {
//     'scenarios': resultByScenario,
//   };
// }




// // File: lib/zzzz/scenario_merger.dart

// import 'dart:collection';
// import 'home.dart';  // ProcessNode, FlowValue, etc.

// /// Holds adjacency information for quick lookup.
// class Adjacency {
//   final Map<String, List<String>> producersByFlow;
//   final Map<String, List<String>> consumersByFlow;
//   final Map<String, ProcessNode> processById;

//   Adjacency({
//     required this.producersByFlow,
//     required this.consumersByFlow,
//     required this.processById,
//   });
// }

// /// Builds adjacency maps so that for any flow name, you can find which
// /// processes produce it (upstream) and which consume it (downstream),
// /// and also easily look up any ProcessNode by its ID.
// Adjacency buildAdjacency(
//   List<ProcessNode> processes,
//   List<Map<String, dynamic>> flows,
// ) {
//   final Map<String, List<String>> producersByFlow = {};
//   final Map<String, List<String>> consumersByFlow = {};
//   final Map<String, ProcessNode> processById = {};

//   for (var p in processes) {
//     processById[p.id] = p;
//   }

//   for (var conn in flows) {
//     final String fromId = conn['from'] as String;
//     final String toId = conn['to'] as String;
//     final List<String> names = List<String>.from(conn['names'] as List);

//     for (var fName in names) {
//       producersByFlow.putIfAbsent(fName, () => []).add(fromId);
//       consumersByFlow.putIfAbsent(fName, () => []).add(toId);
//     }
//   }

//   return Adjacency(
//     producersByFlow: producersByFlow,
//     consumersByFlow: consumersByFlow,
//     processById: processById,
//   );
// }

// /// Computes a scale factor for a single process when it has one or more flow changes.
// /// - If there is exactly one flow change, returns (newValue / oldValue).
// /// - If multiple flows changed, sums old amounts and new amounts, then returns (newSum / oldSum).
// double computeScaleFactorForProcess(
//   ProcessNode orig,
//   List<Map<String, dynamic>> deltas,
// ) {
//   final Map<String, double> newAmounts = {};
//   final Map<String, double> oldAmounts = {};

//   for (var change in deltas) {
//     final String field = change['field'] as String; // e.g. "inputs.diesel.amount"
//     final double newVal = (change['new_value'] as num).toDouble();
//     final parts = field.split('.');
//     final flowName = parts[1];

//     newAmounts[flowName] = newVal;
//     if (parts[0] == 'inputs') {
//       final matched = orig.inputs.firstWhere((f) => f.name == flowName);
//       oldAmounts[flowName] = matched.amount;
//     } else {
//       final matched = orig.outputs.firstWhere((f) => f.name == flowName);
//       oldAmounts[flowName] = matched.amount;
//     }
//   }

//   if (newAmounts.length == 1) {
//     final fn = newAmounts.keys.first;
//     final oldVal = oldAmounts[fn]!;
//     if (oldVal == 0) return 1.0;
//     return newAmounts[fn]! / oldVal;
//   }

//   double oldSum = 0.0, newSum = 0.0;
//   newAmounts.forEach((fname, nval) {
//     oldSum += oldAmounts[fname]!;
//     newSum += nval;
//   });
//   if (oldSum == 0) return 1.0;
//   return newSum / oldSum;
// }

// /// Applies deltas (field changes) to a single ProcessNode, returning a new ProcessNode.
// /// - Overrides any inputs.*.amount or outputs.*.amount or co2 if specified.
// /// - Computes a scale factor (if more than one flow changed) and scales all inputs, outputs, and co2.
// ProcessNode applyDeltasToProcess(
//   ProcessNode orig,
//   List<Map<String, dynamic>> deltas,
// ) {
//   // Copy inputs/outputs into mutable lists
//   List<FlowValue> newInputs = orig.inputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();
//   List<FlowValue> newOutputs = orig.outputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();
//   double newCo2 = orig.co2;

//   // Override co2 if needed
//   for (var change in deltas) {
//     final field = change['field'] as String;
//     if (field == 'co2') {
//       newCo2 = (change['new_value'] as num).toDouble();
//     }
//   }

//   // Override individual input/output amounts
//   for (var change in deltas) {
//     final String field = change['field'] as String; // e.g. "inputs.diesel.amount"
//     final double newVal = (change['new_value'] as num).toDouble();
//     final parts = field.split('.');
//     final isInput = (parts[0] == 'inputs');
//     final flowName = parts[1];

//     if (isInput) {
//       for (int i = 0; i < newInputs.length; i++) {
//         if (newInputs[i].name == flowName) {
//           newInputs[i] =
//               FlowValue(name: flowName, amount: newVal, unit: newInputs[i].unit);
//         }
//       }
//     } else {
//       for (int i = 0; i < newOutputs.length; i++) {
//         if (newOutputs[i].name == flowName) {
//           newOutputs[i] =
//               FlowValue(name: flowName, amount: newVal, unit: newOutputs[i].unit);
//         }
//       }
//     }
//   }

//   // Compute scale factor
//   final scale = computeScaleFactorForProcess(orig, deltas);

//   if ((scale - 1.0).abs() > 1e-9) {
//     newInputs = newInputs
//         .map((f) => FlowValue(name: f.name, amount: f.amount * scale, unit: f.unit))
//         .toList();
//     newOutputs = newOutputs
//         .map((f) => FlowValue(name: f.name, amount: f.amount * scale, unit: f.unit))
//         .toList();
//     newCo2 = newCo2 * scale;
//   }

//   return ProcessNode(
//     id: orig.id,
//     name: orig.name,
//     inputs: newInputs,
//     outputs: newOutputs,
//     co2: newCo2,
//     position: orig.position,
//   );
// }

// /// Merges baseModel + scenario‐specific deltas into fully balanced scenario models.
// ///
// /// baseModel: {
// ///   'processes': [ { … each ProcessNode.toJson() … } ],
// ///   'flows':      [ { 'from': pidA, 'to': pidB, 'names': [flowName,…] }, … ]
// /// }
// ///
// /// allDeltasByScenario: {
// ///   'scenarioName': [
// ///     { 'process_id': 'P', 'field': 'inputs.diesel.amount', 'new_value': 25.0 },
// ///     …
// ///   ],
// ///   …
// /// }
// ///
// /// **CORRECTED SIGNATURE**: Returns a Map whose single key is "scenarios",
// /// and whose value is itself a map of scenario‐name → { 'model': { processes, flows } }.
// Map<String, dynamic> mergeScenarios(
//   Map<String, dynamic> baseModel,
//   Map<String, List<Map<String, dynamic>>> allDeltasByScenario,
// ) {
//   // 1) Extract base processes + flows
//   final baseProcessesJson =
//       List<Map<String, dynamic>>.from(baseModel['processes'] as List);
//   final baseFlowsJson = List<Map<String, dynamic>>.from(baseModel['flows'] as List);

//   // Convert JSON → ProcessNode
//   final baseProcesses =
//       baseProcessesJson.map((j) => ProcessNode.fromJson(j)).toList();

//   // Build adjacency maps once (use the original baseProcesses)
//   final adjacency = buildAdjacency(baseProcesses, baseFlowsJson);

//   // We'll build the inner map of "scenarioName" → { 'model': { … } }
//   final Map<String, Map<String, dynamic>> resultByScenario = {};

//   // 2) For each scenario
//   allDeltasByScenario.forEach((scenarioName, rawDeltas) {
//     // 2a) Clone base processes into a mutable map by ID
//     final Map<String, ProcessNode> cloned = {};
//     for (var p in baseProcesses) {
//       cloned[p.id] = ProcessNode.fromJson(p.toJson());
//     }

//     // 2b) Group raw deltas by process_id
//     final Map<String, List<Map<String, dynamic>>> deltasByProcess = {};
//     for (var d in rawDeltas) {
//       final pid = d['process_id'] as String;
//       deltasByProcess.putIfAbsent(pid, () => []).add(d);
//     }

//     // 2c) Apply each process's direct deltas (absolute overrides + scaling)
//     //     and enqueue those processes for propagation.
//     final Queue<String> toVisit = Queue<String>();
//     for (var pid in deltasByProcess.keys) {
//       final orig = adjacency.processById[pid]!;
//       final updated = applyDeltasToProcess(orig, deltasByProcess[pid]!);
//       cloned[pid] = updated;
//       toVisit.add(pid);
//     }

//     // 2d) BFS propagation up/down the graph
//     final Set<String> seen = Set<String>.of(deltasByProcess.keys);
//     while (toVisit.isNotEmpty) {
//       final currentId = toVisit.removeFirst();
//       final curr = cloned[currentId]!;

//       // --- Propagate Input Changes Upstream ---
//       for (var inFlow in curr.inputs) {
//         final flowName = inFlow.name;
//         final newAmount = inFlow.amount;

//         final origProc = adjacency.processById[currentId]!;
//         final oldAmount = origProc.inputs
//             .firstWhere((f) => f.name == flowName)
//             .amount;
//         final deltaAmt = newAmount - oldAmount;
//         if (deltaAmt.abs() < 1e-9) continue;

//         final upstreams = adjacency.producersByFlow[flowName] ?? [];
//         for (var prodId in upstreams) {
//           if (prodId == currentId) continue;
//           final origProd = adjacency.processById[prodId]!;
//           final oldOutVal = origProd.outputs
//               .firstWhere((f) => f.name == flowName)
//               .amount;
//           final newOutVal = (oldOutVal + deltaAmt).clamp(0.0, double.infinity);

//           final overrideDelta = {
//             'process_id': prodId,
//             'field': 'outputs.$flowName.amount',
//             'new_value': newOutVal,
//           };
//           final accum = (deltasByProcess[prodId] ?? []).toList();
//           accum.add(overrideDelta);
//           deltasByProcess[prodId] = accum;

//           final reScaled = applyDeltasToProcess(origProd, accum);
//           cloned[prodId] = reScaled;

//           if (!seen.contains(prodId)) {
//             seen.add(prodId);
//             toVisit.add(prodId);
//           }
//         }
//       }

//       // --- Propagate Output Changes Downstream ---
//       for (var outFlow in curr.outputs) {
//         final flowName = outFlow.name;
//         final newAmount = outFlow.amount;

//         final origProc = adjacency.processById[currentId]!;
//         final oldAmount = origProc.outputs
//             .firstWhere((f) => f.name == flowName)
//             .amount;
//         final deltaAmt = newAmount - oldAmount;
//         if (deltaAmt.abs() < 1e-9) continue;

//         final downstreams = adjacency.consumersByFlow[flowName] ?? [];
//         for (var consId in downstreams) {
//           if (consId == currentId) continue;
//           final origCons = adjacency.processById[consId]!;
//           final oldInVal = origCons.inputs
//               .firstWhere((f) => f.name == flowName)
//               .amount;
//           final newInVal = (oldInVal + deltaAmt).clamp(0.0, double.infinity);

//           final overrideDelta = {
//             'process_id': consId,
//             'field': 'inputs.$flowName.amount',
//             'new_value': newInVal,
//           };
//           final accum = (deltasByProcess[consId] ?? []).toList();
//           accum.add(overrideDelta);
//           deltasByProcess[consId] = accum;

//           final reScaled = applyDeltasToProcess(origCons, accum);
//           cloned[consId] = reScaled;

//           if (!seen.contains(consId)) {
//             seen.add(consId);
//             toVisit.add(consId);
//           }
//         }
//       }
//     }

//     // 2e) Build final JSON for this scenario
//     final List<Map<String, dynamic>> finalProcessesJson = [];
//     for (var p in cloned.values) {
//       finalProcessesJson.add(p.toJson());
//     }
//     resultByScenario[scenarioName] = {
//       'model': {
//         'processes': finalProcessesJson,
//         'flows': baseFlowsJson,
//       }
//     };
//   });

//   // ─── WRAP the result under a top-level "scenarios" key ───
//   return {
//     'scenarios': resultByScenario,
//   };
// }


// // File: lib/zzzz/scenario_merger.dart

// import 'home.dart'; // Provides ProcessNode, FlowValue, etc.

// /// A much‐simplified mergeScenarios: for each scenario, clone the base model,
// /// then apply each delta directly to the matching ProcessNode—no propagation,
// /// no scaling, just “override that one field (input, output, or co2).”
// Map<String, dynamic> mergeScenarios(
//   Map<String, dynamic> baseModel,
//   Map<String, List<Map<String, dynamic>>> allDeltasByScenario,
// ) {
//   // 1) Extract base JSON lists
//   final List<Map<String, dynamic>> baseProcessesJson =
//       List<Map<String, dynamic>>.from(baseModel['processes'] as List);
//   final List<Map<String, dynamic>> baseFlowsJson =
//       List<Map<String, dynamic>>.from(baseModel['flows'] as List);

//   // 2) Convert base JSON → ProcessNode instances
//   final List<ProcessNode> baseProcesses = baseProcessesJson
//       .map((j) => ProcessNode.fromJson(j))
//       .toList();

//   // 3) Prepare a container for per‐scenario results
//   final Map<String, Map<String, dynamic>> resultByScenario = {};

//   // 4) For each scenario…
//   allDeltasByScenario.forEach((scenarioName, rawDeltas) {
//     // 4a) Clone the base processes (deep copy)
//     final Map<String, ProcessNode> clonedById = {};
//     for (var p in baseProcesses) {
//       clonedById[p.id] = ProcessNode.fromJson(p.toJson());
//     }

//     // 4b) Apply each delta in turn
//     for (var delta in rawDeltas) {
//       final String pid = delta['process_id'] as String;
//       final String field = delta['field'] as String;         // e.g. "inputs.diesel.amount", "outputs.heat.amount", or "co2"
//       final double newVal = (delta['new_value'] as num).toDouble();

//       // Fetch the current version of that node (already cloned)
//       final origNode = clonedById[pid]!;
//       List<FlowValue> newInputs = origNode.inputs
//           .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//           .toList();
//       List<FlowValue> newOutputs = origNode.outputs
//           .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//           .toList();
//       double newCo2 = origNode.co2;

//       if (field == 'co2') {
//         // Override CO2 directly
//         newCo2 = newVal;
//       } else {
//         // Expect "inputs.<flowName>.amount" or "outputs.<flowName>.amount"
//         final parts = field.split('.');
//         if (parts.length == 3) {
//           final prefix = parts[0];       // "inputs" or "outputs"
//           final flowName = parts[1];     // e.g. "diesel" or "heat"
//           // parts[2] should be "amount", so we ignore it.

//           if (prefix == 'inputs') {
//             newInputs = newInputs.map((f) {
//               if (f.name == flowName) {
//                 return FlowValue(name: f.name, amount: newVal, unit: f.unit);
//               }
//               return f;
//             }).toList();
//           } else if (prefix == 'outputs') {
//             newOutputs = newOutputs.map((f) {
//               if (f.name == flowName) {
//                 return FlowValue(name: f.name, amount: newVal, unit: f.unit);
//               }
//               return f;
//             }).toList();
//           }
//         }
//       }

//       // Replace that ProcessNode with a new one reflecting the override(s)
//       clonedById[pid] = ProcessNode(
//         id: origNode.id,
//         name: origNode.name,
//         inputs: newInputs,
//         outputs: newOutputs,
//         co2: newCo2,
//         position: origNode.position,
//       );
//     }

//     // 4c) Convert all cloned ProcessNode → JSON again
//     final List<Map<String, dynamic>> finalProcessesJson = clonedById.values
//         .map((p) => p.toJson())
//         .toList();

//     // 4d) Stick it under “model” for this scenario
//     resultByScenario[scenarioName] = {
//       'model': {
//         'processes': finalProcessesJson,
//         // Flows never change in this simplified version
//         'flows': baseFlowsJson,
//       }
//     };
//   });

//   // 5) Wrap in a top‐level "scenarios" key and return
//   return {
//     'scenarios': resultByScenario,
//   };
// }

// File: lib/zzzz/scenario_merger.dart
// File: lib/zzzz/scenario_merger.dart

// import 'dart:collection';
// import 'home.dart'; // Provides ProcessNode, FlowValue, etc.

// /// Holds adjacency information for quick lookup.
// class Adjacency {
//   final Map<String, List<String>> producersByFlow;
//   final Map<String, List<String>> consumersByFlow;
//   final Map<String, ProcessNode> processById;

//   Adjacency({
//     required this.producersByFlow,
//     required this.consumersByFlow,
//     required this.processById,
//   });
// }

// /// Builds adjacency maps so that for any flow name, you can find which
// /// processes produce it (upstream) and which consume it (downstream),
// /// and also easily look up any ProcessNode by its ID.
// Adjacency buildAdjacency(
//   List<ProcessNode> processes,
//   List<Map<String, dynamic>> flows,
// ) {
//   final Map<String, List<String>> producersByFlow = {};
//   final Map<String, List<String>> consumersByFlow = {};
//   final Map<String, ProcessNode> processById = {};

//   for (var p in processes) {
//     processById[p.id] = p;
//   }

//   for (var conn in flows) {
//     final String fromId = conn['from'] as String;
//     final String toId = conn['to'] as String;
//     final List<String> names = List<String>.from(conn['names'] as List);

//     for (var flowName in names) {
//       producersByFlow.putIfAbsent(flowName, () => []).add(fromId);
//       consumersByFlow.putIfAbsent(flowName, () => []).add(toId);
//     }
//   }

//   return Adjacency(
//     producersByFlow: producersByFlow,
//     consumersByFlow: consumersByFlow,
//     processById: processById,
//   );
// }

// /// Applies exactly one override to a ProcessNode (no scaling).
// /// Prints what override is happening.
// /// - If field == 'co2', override co2.
// /// - If field == 'inputs.<flowName>.amount', set that input to newVal.
// /// - If field == 'outputs.<flowName>.amount', set that output to newVal.
// ProcessNode applyOverrideToProcess(
//   ProcessNode orig,
//   String field,
//   double newVal,
// ) {
//   print("  [Override] Process ${orig.id}: setting $field → $newVal");
//   final List<FlowValue> newInputs = orig.inputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();
//   final List<FlowValue> newOutputs = orig.outputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();
//   double newCo2 = orig.co2;

//   if (field == 'co2') {
//     print("    → Overriding CO₂ from ${orig.co2} to $newVal");
//     newCo2 = newVal;
//   } else {
//     final parts = field.split('.');
//     if (parts.length == 3) {
//       final prefix = parts[0];   // "inputs" or "outputs"
//       final flowName = parts[1]; 
//       if (prefix == 'inputs') {
//         for (int i = 0; i < newInputs.length; i++) {
//           if (newInputs[i].name == flowName) {
//             final oldAmt = newInputs[i].amount;
//             print("    → Overriding input $flowName: $oldAmt → $newVal");
//             newInputs[i] = FlowValue(name: flowName, amount: newVal, unit: newInputs[i].unit);
//             break;
//           }
//         }
//       } else if (prefix == 'outputs') {
//         for (int i = 0; i < newOutputs.length; i++) {
//           if (newOutputs[i].name == flowName) {
//             final oldAmt = newOutputs[i].amount;
//             print("    → Overriding output $flowName: $oldAmt → $newVal");
//             newOutputs[i] = FlowValue(name: flowName, amount: newVal, unit: newOutputs[i].unit);
//             break;
//           }
//         }
//       }
//     }
//   }

//   return ProcessNode(
//     id: orig.id,
//     name: orig.name,
//     inputs: newInputs,
//     outputs: newOutputs,
//     co2: newCo2,
//     position: orig.position,
//   );
// }

// /// Merges baseModel + scenario‐specific deltas into fully balanced scenario models.
// /// Now with “additive delta” propagation only on that one flow, with print tracing.
// Map<String, dynamic> mergeScenarios(
//   Map<String, dynamic> baseModel,
//   Map<String, List<Map<String, dynamic>>> allDeltasByScenario,
// ) {
//   // 1) Extract base processes + flows
//   final baseProcessesJson =
//       List<Map<String, dynamic>>.from(baseModel['processes'] as List);
//   final baseFlowsJson = List<Map<String, dynamic>>.from(baseModel['flows'] as List);

//   // Convert JSON → ProcessNode
//   final baseProcesses =
//       baseProcessesJson.map((j) => ProcessNode.fromJson(j)).toList();

//   // Build adjacency maps once
//   final adjacency = buildAdjacency(baseProcesses, baseFlowsJson);

//   // Prepare container for scenario outputs
//   final Map<String, Map<String, dynamic>> resultByScenario = {};

//   // 2) For each scenario
//   allDeltasByScenario.forEach((scenarioName, rawDeltas) {
//     print("\n=== Scenario: $scenarioName ===");

//     // 2a) Clone base processes into a mutable map
//     final Map<String, ProcessNode> clonedById = {};
//     for (var p in baseProcesses) {
//       clonedById[p.id] = ProcessNode.fromJson(p.toJson());
//     }

//     // 2b) Group deltas by process_id for convenience
//     final Map<String, List<Map<String, dynamic>>> deltasByProcess = {};
//     for (var d in rawDeltas) {
//       final pid = d['process_id'] as String;
//       deltasByProcess.putIfAbsent(pid, () => []).add(d);
//     }

//     // 2c) Apply each delta in turn and enqueue for BFS propagation
//     final Queue<String> toVisit = Queue<String>();
//     for (var pid in deltasByProcess.keys) {
//       ProcessNode updatedNode = clonedById[pid]!;
//       print(" Applying raw deltas to process $pid:");
//       for (var change in deltasByProcess[pid]!) {
//         final String field = change['field'] as String;
//         final double newVal = (change['new_value'] as num).toDouble();
//         updatedNode = applyOverrideToProcess(updatedNode, field, newVal);
//       }
//       clonedById[pid] = updatedNode;
//       toVisit.add(pid);
//     }

//     // 2d) BFS propagation: add Δ only to the “adjacent” producer/consumer of that exact flow
//     final Set<String> seen = Set<String>.of(deltasByProcess.keys);
//     while (toVisit.isNotEmpty) {
//       final currentId = toVisit.removeFirst();
//       final currUpdated = clonedById[currentId]!;     // updated version
//       final currOrig = adjacency.processById[currentId]!; // original version

//       //  --- Propagate any INPUT changes upstream ---
//       for (var inFlow in currUpdated.inputs) {
//         final flowName = inFlow.name;
//         final double newAmt = inFlow.amount;
//         // original amount on that process
//         final double oldAmt = currOrig.inputs
//             .firstWhere((f) => f.name == flowName)
//             .amount;
//         final double deltaAmt = newAmt - oldAmt;
//         if ((deltaAmt).abs() < 1e-9) continue;

//         print(
//             "  [Propagate UP] Process $currentId input.$flowName changed: $oldAmt → $newAmt (Δ = $deltaAmt)");
//         // Find the actual upstream producer(s) of this flow
//         final List<String> upstreams = adjacency.producersByFlow[flowName] ?? [];
//         for (var prodId in upstreams) {
//           if (prodId == currentId) continue;
//           final origProd = adjacency.processById[prodId]!;       // original producer
//           final updatedProd = clonedById[prodId]!;               // “in‐progress” updated

//           // original producer’s old output
//           final double oldOut = origProd.outputs
//               .firstWhere((f) => f.name == flowName)
//               .amount;
//           final double newOut = (oldOut + deltaAmt).clamp(0.0, double.infinity);

//           print(
//               "    → Propagate to PRODUCER $prodId: outputs.$flowName $oldOut → $newOut");
//           // Override just that flow on the producer
//           final ProcessNode reprod = applyOverrideToProcess(
//             updatedProd,
//             'outputs.$flowName.amount',
//             newOut,
//           );
//           clonedById[prodId] = reprod;

//           if (!seen.contains(prodId)) {
//             seen.add(prodId);
//             toVisit.add(prodId);
//           }
//         }
//       }

//       // --- Propagate any OUTPUT changes downstream ---
//       for (var outFlow in currUpdated.outputs) {
//         final flowName = outFlow.name;
//         final double newAmt = outFlow.amount;
//         final double oldAmt = currOrig.outputs
//             .firstWhere((f) => f.name == flowName)
//             .amount;
//         final double deltaAmt = newAmt - oldAmt;
//         if ((deltaAmt).abs() < 1e-9) continue;

//         print(
//             "  [Propagate DOWN] Process $currentId output.$flowName changed: $oldAmt → $newAmt (Δ = $deltaAmt)");
//         // Find the actual downstream consumer(s) of this flow
//         final List<String> downstreams = adjacency.consumersByFlow[flowName] ?? [];
//         for (var consId in downstreams) {
//           if (consId == currentId) continue;
//           final origCons = adjacency.processById[consId]!;     // original consumer
//           final updatedCons = clonedById[consId]!;             // “in‐progress” updated

//           final double oldIn = origCons.inputs
//               .firstWhere((f) => f.name == flowName)
//               .amount;
//           final double newIn = (oldIn + deltaAmt).clamp(0.0, double.infinity);

//           print(
//               "    → Propagate to CONSUMER $consId: inputs.$flowName $oldIn → $newIn");
//           // Override just that flow on the consumer
//           final ProcessNode recon = applyOverrideToProcess(
//             updatedCons,
//             'inputs.$flowName.amount',
//             newIn,
//           );
//           clonedById[consId] = recon;

//           if (!seen.contains(consId)) {
//             seen.add(consId);
//             toVisit.add(consId);
//           }
//         }
//       }
//     }

//     // 2e) Convert all cloned ProcessNode → JSON
//     final List<Map<String, dynamic>> finalProcessesJson = [];
//     for (var p in clonedById.values) {
//       finalProcessesJson.add(p.toJson());
//     }

//     // 2f) Record under “model” for this scenario
//     resultByScenario[scenarioName] = {
//       'model': {
//         'processes': finalProcessesJson,
//         'flows': baseFlowsJson,
//       }
//     };

//     print("=== Finished scenario: $scenarioName ===");
//   });

//   // 3) Wrap in a top‐level "scenarios" key and return
//   return {
//     'scenarios': resultByScenario,
//   };
// }


// // File: lib/zzzz/scenario_merger.dart

// import 'dart:collection';
// import 'home.dart'; // Provides ProcessNode, FlowValue, etc.

// /// Holds adjacency information for quick lookup.
// class Adjacency {
//   final Map<String, List<String>> producersByFlow;
//   final Map<String, List<String>> consumersByFlow;
//   final Map<String, ProcessNode> processById;

//   Adjacency({
//     required this.producersByFlow,
//     required this.consumersByFlow,
//     required this.processById,
//   });
// }

// /// Builds adjacency maps so that for any flow name (case‐insensitive), you can find which
// /// processes produce it (producersByFlow) and which consume it (consumersByFlow),
// /// and also easily look up any ProcessNode by its ID.
// Adjacency buildAdjacency(
//   List<ProcessNode> processes,
//   List<Map<String, dynamic>> flows,
// ) {
//   final Map<String, List<String>> producersByFlow = {};
//   final Map<String, List<String>> consumersByFlow = {};
//   final Map<String, ProcessNode> processById = {};

//   // Map each process ID to its ProcessNode
//   for (var p in processes) {
//     processById[p.id] = p;
//   }

//   // For each flow connection, lowercase the flow names when indexing
//   for (var conn in flows) {
//     final String fromId = conn['from'] as String;
//     final String toId = conn['to'] as String;
//     final List<String> names = List<String>.from(conn['names'] as List);

//     for (var rawName in names) {
//       final String flowName = rawName.toLowerCase();
//       producersByFlow.putIfAbsent(flowName, () => []).add(fromId);
//       consumersByFlow.putIfAbsent(flowName, () => []).add(toId);
//     }
//   }

//   return Adjacency(
//     producersByFlow: producersByFlow,
//     consumersByFlow: consumersByFlow,
//     processById: processById,
//   );
// }

// /// Applies exactly one override to a ProcessNode (no scaling of other fields).
// /// Prints a line so you can trace what override is happening.
// ///
// /// - If field == 'co2', override the CO₂ value directly.
// /// - If field == 'inputs.<flowName>.amount', set that single input to newVal.
// /// - If field == 'outputs.<flowName>.amount', set that single output to newVal.
// ProcessNode applyOverrideToProcess(
//   ProcessNode orig,
//   String field,
//   double newVal,
// ) {
//   print("  [Override] Process ${orig.id}: setting $field → $newVal");
//   // Copy existing inputs/outputs
//   final List<FlowValue> newInputs = orig.inputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();
//   final List<FlowValue> newOutputs = orig.outputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();
//   double newCo2 = orig.co2;

//   if (field == 'co2') {
//     print("    → Overriding CO₂ from ${orig.co2} to $newVal");
//     newCo2 = newVal;
//   } else {
//     // Expect "inputs.<flowName>.amount" or "outputs.<flowName>.amount"
//     final parts = field.split('.');
//     if (parts.length == 3) {
//       final prefix = parts[0];   // "inputs" or "outputs"
//       final rawFlow = parts[1];  // e.g. "PMMA" or "glass"
//       final flowName = rawFlow.toLowerCase();

//       if (prefix == 'inputs') {
//         for (int i = 0; i < newInputs.length; i++) {
//           if (newInputs[i].name.toLowerCase() == flowName) {
//             final double oldAmt = newInputs[i].amount;
//             print("    → Overriding input $rawFlow: $oldAmt → $newVal");
//             newInputs[i] = FlowValue(
//               name: newInputs[i].name,
//               amount: newVal,
//               unit: newInputs[i].unit,
//             );
//             break;
//           }
//         }
//       } else if (prefix == 'outputs') {
//         for (int i = 0; i < newOutputs.length; i++) {
//           if (newOutputs[i].name.toLowerCase() == flowName) {
//             final double oldAmt = newOutputs[i].amount;
//             print("    → Overriding output $rawFlow: $oldAmt → $newVal");
//             newOutputs[i] = FlowValue(
//               name: newOutputs[i].name,
//               amount: newVal,
//               unit: newOutputs[i].unit,
//             );
//             break;
//           }
//         }
//       }
//     }
//   }

//   return ProcessNode(
//     id: orig.id,
//     name: orig.name,
//     inputs: newInputs,
//     outputs: newOutputs,
//     co2: newCo2,
//     position: orig.position,
//   );
// }

// /// Merges baseModel + scenario‐specific deltas into fully balanced scenario models.
// /// Uses “additive delta” propagation along adjacency, case‐insensitive on flow names.
// /// Prints each step so you can trace exactly what happens.
// Map<String, dynamic> mergeScenarios(
//   Map<String, dynamic> baseModel,
//   Map<String, List<Map<String, dynamic>>> allDeltasByScenario,
// ) {
//   // 1) Extract base JSON lists
//   final List<Map<String, dynamic>> baseProcessesJson =
//       List<Map<String, dynamic>>.from(baseModel['processes'] as List);
//   final List<Map<String, dynamic>> baseFlowsJson =
//       List<Map<String, dynamic>>.from(baseModel['flows'] as List);

//   // 2) Convert base JSON → ProcessNode
//   final List<ProcessNode> baseProcesses =
//       baseProcessesJson.map((j) => ProcessNode.fromJson(j)).toList();

//   // 3) Build adjacency maps once (original baseProcesses)
//   final Adjacency adjacency = buildAdjacency(baseProcesses, baseFlowsJson);

//   // 4) Prepare container for per‐scenario results
//   final Map<String, Map<String, dynamic>> resultByScenario = {};

//   // 5) For each scenario …
//   allDeltasByScenario.forEach((scenarioName, rawDeltas) {
//     print("\n=== Scenario: $scenarioName ===");

//     // 5a) Clone base processes (deep copy) into a mutable map
//     final Map<String, ProcessNode> clonedById = {};
//     for (var p in baseProcesses) {
//       clonedById[p.id] = ProcessNode.fromJson(p.toJson());
//     }

//     // 5b) Group raw deltas by process_id
//     final Map<String, List<Map<String, dynamic>>> deltasByProcess = {};
//     for (var d in rawDeltas) {
//       final String pid = d['process_id'] as String;
//       deltasByProcess.putIfAbsent(pid, () => []).add(d);
//     }

//     // 5c) Apply each override to its process, enqueue for BFS
//     final Queue<String> toVisit = Queue<String>();
//     for (var pid in deltasByProcess.keys) {
//       ProcessNode updatedNode = clonedById[pid]!;
//       print(" Applying raw deltas to process $pid:");
//       for (var change in deltasByProcess[pid]!) {
//         final String field = change['field'] as String;         // e.g. "inputs.glass.amount"
//         final double newVal = (change['new_value'] as num).toDouble();
//         updatedNode = applyOverrideToProcess(updatedNode, field, newVal);
//       }
//       clonedById[pid] = updatedNode;
//       toVisit.add(pid);
//     }

//     // 5d) BFS propagation: propagate Δ only to adjacent producers/consumers
//     final Set<String> seen = Set<String>.of(deltasByProcess.keys);
//     while (toVisit.isNotEmpty) {
//       final String currentId = toVisit.removeFirst();
//       final ProcessNode currUpdated = clonedById[currentId]!;     // updated node
//       final ProcessNode currOrig = adjacency.processById[currentId]!; // original node

//       //  Propagate any INPUT changes upstream
//       for (var inFlow in currUpdated.inputs) {
//         final String rawFlow = inFlow.name;
//         final String flowName = rawFlow.toLowerCase();
//         final double newAmt = inFlow.amount;
//         final double oldAmt = currOrig.inputs
//             .firstWhere((f) => f.name.toLowerCase() == flowName)
//             .amount;
//         final double deltaAmt = newAmt - oldAmt;
//         if ((deltaAmt).abs() < 1e-9) continue;

//         print(
//           "  [Propagate UP] Process $currentId input.$rawFlow changed: "
//           "$oldAmt → $newAmt (Δ = $deltaAmt)"
//         );
//         final List<String> upstreams = adjacency.producersByFlow[flowName] ?? [];
//         for (var prodId in upstreams) {
//           if (prodId == currentId) continue;
//           final ProcessNode origProd = adjacency.processById[prodId]!;   // original
//           final ProcessNode updatedProd = clonedById[prodId]!;           // in‐progress

//           final double oldOut = origProd.outputs
//               .firstWhere((f) => f.name.toLowerCase() == flowName)
//               .amount;
//           final double newOut = (oldOut + deltaAmt).clamp(0.0, double.infinity);

//           print(
//             "    → Propagate to PRODUCER $prodId: outputs.$rawFlow $oldOut → $newOut"
//           );
//           final ProcessNode reprod = applyOverrideToProcess(
//             updatedProd,
//             'outputs.$rawFlow.amount',
//             newOut,
//           );
//           clonedById[prodId] = reprod;

//           if (!seen.contains(prodId)) {
//             seen.add(prodId);
//             toVisit.add(prodId);
//           }
//         }
//       }

//       //  Propagate any OUTPUT changes downstream
//       for (var outFlow in currUpdated.outputs) {
//         final String rawFlow = outFlow.name;
//         final String flowName = rawFlow.toLowerCase();
//         final double newAmt = outFlow.amount;
//         final double oldAmt = currOrig.outputs
//             .firstWhere((f) => f.name.toLowerCase() == flowName)
//             .amount;
//         final double deltaAmt = newAmt - oldAmt;
//         if ((deltaAmt).abs() < 1e-9) continue;

//         print(
//           "  [Propagate DOWN] Process $currentId output.$rawFlow changed: "
//           "$oldAmt → $newAmt (Δ = $deltaAmt)"
//         );
//         final List<String> downstreams = adjacency.consumersByFlow[flowName] ?? [];
//         for (var consId in downstreams) {
//           if (consId == currentId) continue;
//           final ProcessNode origCons = adjacency.processById[consId]!; // original
//           final ProcessNode updatedCons = clonedById[consId]!;         // in‐progress

//           final double oldIn = origCons.inputs
//               .firstWhere((f) => f.name.toLowerCase() == flowName)
//               .amount;
//           final double newIn = (oldIn + deltaAmt).clamp(0.0, double.infinity);

//           print(
//             "    → Propagate to CONSUMER $consId: inputs.$rawFlow $oldIn → $newIn"
//           );
//           final ProcessNode recon = applyOverrideToProcess(
//             updatedCons,
//             'inputs.$rawFlow.amount',
//             newIn,
//           );
//           clonedById[consId] = recon;

//           if (!seen.contains(consId)) {
//             seen.add(consId);
//             toVisit.add(consId);
//           }
//         }
//       }
//     }

//     // 5e) Convert all cloned ProcessNode → JSON
//     final List<Map<String, dynamic>> finalProcessesJson = [];
//     for (var p in clonedById.values) {
//       finalProcessesJson.add(p.toJson());
//     }

//     // 5f) Record under “model” for this scenario
//     resultByScenario[scenarioName] = {
//       'model': {
//         'processes': finalProcessesJson,
//         'flows': baseFlowsJson,
//       }
//     };

//     print("=== Finished scenario: $scenarioName ===\n");
//   });

//   // 6) Wrap in a top‐level "scenarios" key and return
//   return {
//     'scenarios': resultByScenario,
//   };
// }

// File: lib/zzzz/scenario_merger.dart
// File: lib/zzzz/scenario_merger.dart
// File: lib/zzzz/scenario_merger.dart
// File: lib/zzzz/scenario_merger.dart

// import 'dart:collection';
// import 'home.dart'; // Provides ProcessNode, FlowValue, etc.

// /// Holds adjacency information for quick lookup.
// /// - producersByFlow maps a lowercase flow name → list of process IDs that produce it.
// /// - consumersByFlow maps a lowercase flow name → list of process IDs that consume it.
// /// - processById maps a process ID → the original ProcessNode (before any overrides).
// class Adjacency {
//   final Map<String, List<String>> producersByFlow;
//   final Map<String, List<String>> consumersByFlow;
//   final Map<String, ProcessNode> processById;

//   Adjacency({
//     required this.producersByFlow,
//     required this.consumersByFlow,
//     required this.processById,
//   });
// }

// /// Builds adjacency maps so that for any flow name (case‐insensitive), you can find which
// /// processes produce it (producersByFlow) and which consume it (consumersByFlow),
// /// and also easily look up any ProcessNode by its ID.
// Adjacency buildAdjacency(
//   List<ProcessNode> processes,
//   List<Map<String, dynamic>> flows,
// ) {
//   final Map<String, List<String>> producersByFlow = {};
//   final Map<String, List<String>> consumersByFlow = {};
//   final Map<String, ProcessNode> processById = {};

//   // Register each process in the lookup map.
//   for (var p in processes) {
//     processById[p.id] = p;
//   }

//   // For each flow connection (edge in the graph), index producers/consumers by the flow names.
//   // The 'flows' list is expected to contain maps with keys: 'from': String (producer ID),
//   // 'to': String (consumer ID), and 'names': List<String> (flow names).
//   for (var conn in flows) {
//     final String fromId = conn['from'] as String;
//     final String toId = conn['to'] as String;
//     final List<String> names = List<String>.from(conn['names'] as List);

//     for (var rawName in names) {
//       final String flowName = rawName.toLowerCase();
//       producersByFlow.putIfAbsent(flowName, () => []).add(fromId);
//       consumersByFlow.putIfAbsent(flowName, () => []).add(toId);
//     }
//   }

//   return Adjacency(
//     producersByFlow: producersByFlow,
//     consumersByFlow: consumersByFlow,
//     processById: processById,
//   );
// }

// /// Applies exactly one override to a ProcessNode (no scaling of other fields).
// /// - If field == 'co2', override the CO₂ value directly.
// /// - If field == 'inputs.<flowName>.amount', set that single input to newVal (adding it if missing).
// /// - If field == 'outputs.<flowName>.amount', set that single output to newVal (adding it if missing).
// /// Returns a NEW ProcessNode instance with the modification applied.
// ProcessNode applyOverrideToProcess(
//   ProcessNode orig,
//   String field,
//   double newVal,
// ) {
//   print("[mergeScenarios] [Override] Process \"${orig.id}\": setting $field → $newVal");

//   // Make deep copies of the original inputs/outputs lists.
//   final List<FlowValue> newInputs = orig.inputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();
//   final List<FlowValue> newOutputs = orig.outputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();
//   double newCo2 = orig.co2;

//   if (field == 'co2') {
//     print("[mergeScenarios]     → Overriding CO₂ from ${orig.co2} to $newVal");
//     newCo2 = newVal;
//   } else {
//     // Expect "inputs.<flowName>.amount" or "outputs.<flowName>.amount"
//     final parts = field.split('.');
//     if (parts.length == 3) {
//       final prefix = parts[0]; // "inputs" or "outputs"
//       final rawFlow = parts[1]; // e.g. "glass" or "PMMA"
//       final flowNameLower = rawFlow.toLowerCase();

//       if (prefix == 'inputs') {
//         bool found = false;
//         for (int i = 0; i < newInputs.length; i++) {
//           if (newInputs[i].name.toLowerCase() == flowNameLower) {
//             final double oldAmt = newInputs[i].amount;
//             print("[mergeScenarios]     → Overriding input \"$rawFlow\": $oldAmt → $newVal");
//             newInputs[i] = FlowValue(
//               name: newInputs[i].name,
//               amount: newVal,
//               unit: newInputs[i].unit,
//             );
//             found = true;
//             break;
//           }
//         }
//         if (!found) {
//           // Add new FlowValue if missing.
//           print("[mergeScenarios]     → Adding new input flow \"$rawFlow\" with amount $newVal");
//           newInputs.add(FlowValue(
//             name: rawFlow,
//             amount: newVal,
//             unit: 'kg', // default unit; adjust if needed
//           ));
//         }
//       } else if (prefix == 'outputs') {
//         bool found = false;
//         for (int i = 0; i < newOutputs.length; i++) {
//           if (newOutputs[i].name.toLowerCase() == flowNameLower) {
//             final double oldAmt = newOutputs[i].amount;
//             print("[mergeScenarios]     → Overriding output \"$rawFlow\": $oldAmt → $newVal");
//             newOutputs[i] = FlowValue(
//               name: newOutputs[i].name,
//               amount: newVal,
//               unit: newOutputs[i].unit,
//             );
//             found = true;
//             break;
//           }
//         }
//         if (!found) {
//           // Add new FlowValue if missing.
//           print("[mergeScenarios]     → Adding new output flow \"$rawFlow\" with amount $newVal");
//           newOutputs.add(FlowValue(
//             name: rawFlow,
//             amount: newVal,
//             unit: 'kg', // default unit; adjust if needed
//           ));
//         }
//       }
//     }
//   }

//   return ProcessNode(
//     id: orig.id,
//     name: orig.name,
//     inputs: newInputs,
//     outputs: newOutputs,
//     co2: newCo2,
//     position: orig.position,
//   );
// }

// /// Updates adjacency maps when a new flow is introduced within a ProcessNode’s inputs/outputs.
// /// Ensures that producersByFlow and consumersByFlow have an entry for the new flow name (lowercased),
// /// even if no producers/consumers are connected yet.
// void maybeAddNewFlowsToAdjacency(
//   Adjacency adjacency,
//   ProcessNode updatedNode,
// ) {
//   // Inspect inputs
//   for (var inp in updatedNode.inputs) {
//     final flowName = inp.name.toLowerCase();
//     if (!adjacency.producersByFlow.containsKey(flowName)) {
//       adjacency.producersByFlow[flowName] = <String>[];
//       adjacency.consumersByFlow[flowName] = <String>[];
//       print("[mergeScenarios]     → Registered new flow \"$flowName\" in adjacency (as input) with no producers/consumers yet");
//     }
//   }
//   // Inspect outputs
//   for (var outp in updatedNode.outputs) {
//     final flowName = outp.name.toLowerCase();
//     if (!adjacency.producersByFlow.containsKey(flowName)) {
//       adjacency.producersByFlow[flowName] = <String>[];
//       adjacency.consumersByFlow[flowName] = <String>[];
//       print("[mergeScenarios]     → Registered new flow \"$flowName\" in adjacency (as output) with no producers/consumers yet");
//     }
//   }
// }

// /// Merges baseModel + scenario‐specific deltas into fully balanced scenario models.
// /// Now also handles:
// ///   1. Renaming existing processes (field == "name" on a process_id) and automatically
// ///      renaming any flows whose name matches the old process name.
// ///   2. Renaming existing flows    (field == "name" on a flow_id). If no global flow matches, 
// ///      but flow_id matches a process_id, rename that process’s internal flow names.
// ///   3. Adding new processes        (action == "add_process").
// ///   4. Adding new flows            (action == "add_flow").
// ///
// /// The workflow is:
// ///   • Deep-copy the base processes and flows.
// ///   • Apply structural edits (renames, additions) first: update the cloned processes list,
// ///     update the cloned flows list, and update adjacency maps accordingly.
// ///     • If renaming a process, also rename matching flows in both the flow list and all processes.
// ///     • If a flow-rename entry’s flow_id matches a process_id instead of a global flow ID, 
// ///       rename all FlowValue.name inside that process (inputs/outputs).
// ///   • Then apply numeric overrides (inputs/outputs/co2) and propagate deltas via BFS.
// ///
// /// Returns a Map<String, dynamic> of the form:
// /// {
// ///   'scenarios': {
// ///     '<scenarioName>': {
// ///       'model': {
// ///         'processes': [ ...ProcessNode JSON... ],
// ///         'flows': [ ...Flow JSON... ]
// ///       }
// ///     },
// ///     ...
// ///   }
// /// }
// Map<String, dynamic> mergeScenarios(
//   Map<String, dynamic> baseModel,
//   Map<String, List<Map<String, dynamic>>> allDeltasByScenario,
// ) {
//   // 1) Extract base JSON lists
//   final List<Map<String, dynamic>> baseProcessesJson =
//       List<Map<String, dynamic>>.from(baseModel['processes'] as List);
//   final List<Map<String, dynamic>> baseFlowsJson =
//       List<Map<String, dynamic>>.from(baseModel['flows'] as List);

//   // 2) Convert base JSON → ProcessNode
//   final List<ProcessNode> baseProcesses =
//       baseProcessesJson.map((j) => ProcessNode.fromJson(j)).toList();

//   // 3) Build adjacency maps once (from the base processes & base flows)
//   final Adjacency adjacency = buildAdjacency(baseProcesses, baseFlowsJson);

//   // 4) Build a lookup from flow_id → flow JSON, so we can rename flows by ID.
//   final Map<String, Map<String, dynamic>> flowById = {
//     for (var f in baseFlowsJson) f['id'] as String: f
//   };

//   // 5) Prepare container for per‐scenario results
//   final Map<String, Map<String, dynamic>> resultByScenario = {};

//   // 6) Process each scenario one by one.
//   allDeltasByScenario.forEach((scenarioName, rawDeltas) {
//     print("\n=== [mergeScenarios][$scenarioName] Starting scenario ===");

//     // 6a) Deep-copy base processes into a mutable map: clonedById
//     final Map<String, ProcessNode> clonedById = {};
//     for (var p in baseProcesses) {
//       clonedById[p.id] = ProcessNode.fromJson(p.toJson());
//     }

//     // 6b) Deep-copy baseFlowsJson into a new list, so we can rename/add flows
//     final List<Map<String, dynamic>> flowsJson = [
//       for (var f in baseFlowsJson) Map<String, dynamic>.from(f)
//     ];

//     // Also maintain a mutable flowById for the cloned flows
//     final Map<String, Map<String, dynamic>> clonedFlowById = {
//       for (var f in flowsJson) f['id'] as String: f
//     };

//     // 6c) First pass: handle all structural edits (rename/add) BEFORE numeric overrides.
//     for (var change in rawDeltas) {
//       // A) Add a new process?
//       if (change.containsKey('action') && change['action'] == 'add_process') {
//         final Map<String, dynamic> newProcessJson =
//             Map<String, dynamic>.from(change['process'] as Map<String, dynamic>);
//         final ProcessNode newNode = ProcessNode.fromJson(newProcessJson);
//         print("[mergeScenarios][$scenarioName]   [Add Process] Adding new process ID=\"${newNode.id}\", name=\"${newNode.name}\"");

//         // 1. Add to clonedById
//         clonedById[newNode.id] = newNode;

//         // 2. Add to adjacency.processById (so that numeric propagation can see it)
//         adjacency.processById[newNode.id] = newNode;

//         // 3. Register any flows that this new process references
//         maybeAddNewFlowsToAdjacency(adjacency, newNode);
//       }

//       // B) Add a new flow?
//       else if (change.containsKey('action') && change['action'] == 'add_flow') {
//         final Map<String, dynamic> newFlowJson =
//             Map<String, dynamic>.from(change['flow'] as Map<String, dynamic>);
//         final String newFlowId = newFlowJson['id'] as String;
//         final String newFlowName = newFlowJson['name'] as String;
//         print("[mergeScenarios][$scenarioName]   [Add Flow] Adding new flow ID=\"$newFlowId\", name=\"$newFlowName\"");

//         // 1. Add to flowsJson
//         flowsJson.add(newFlowJson);

//         // 2. Add to adjacency maps under lowercase name
//         final String newFlowNameLower = newFlowName.toLowerCase();
//         adjacency.producersByFlow.putIfAbsent(newFlowNameLower, () => []);
//         adjacency.consumersByFlow.putIfAbsent(newFlowNameLower, () => []);

//         // 3. Register in clonedFlowById
//         clonedFlowById[newFlowId] = newFlowJson;
//       }

//       // C) Rename an existing process?
//       else if (change.containsKey('process_id') && change['field'] == 'name') {
//         final String pid = change['process_id'] as String;
//         final String newName = change['new_value'] as String;
//         if (clonedById.containsKey(pid)) {
//           final oldNode = clonedById[pid]!;
//           final String oldName = oldNode.name;
//           print("[mergeScenarios][$scenarioName]   [Rename Process] \"$pid\": \"$oldName\" → \"$newName\"");

//           // 1. Update the ProcessNode’s name
//           clonedById[pid] = ProcessNode(
//             id: oldNode.id,
//             name: newName,
//             inputs: oldNode.inputs
//                 .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//                 .toList(),
//             outputs: oldNode.outputs
//                 .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//                 .toList(),
//             co2: oldNode.co2,
//             position: oldNode.position,
//           );
//           adjacency.processById[pid] = clonedById[pid]!;

//           // 2. Automatically rename any flow whose name matches the old process name
//           final String oldNameLower = oldName.toLowerCase();
//           final String newNameLower = newName.toLowerCase();
//           final List<String> flowsToRename = [];

//           // Identify flow IDs to rename
//           for (var entry in clonedFlowById.entries) {
//             final String fid = entry.key;
//             final Map<String, dynamic> flowJson = entry.value;
//             final String flowName = flowJson['name'] as String;
//             if (flowName.toLowerCase() == oldNameLower) {
//               flowsToRename.add(fid);
//             }
//           }

//           for (var fid in flowsToRename) {
//             final flowJson = clonedFlowById[fid]!;
//             final String oldFlowName = flowJson['name'] as String;
//             print("[mergeScenarios][$scenarioName]     [Auto-Rename Flow] \"$fid\": \"$oldFlowName\" → \"$newName\"");

//             // Update flow JSON
//             flowJson['name'] = newName;

//             // Update adjacency: move entries from oldNameLower to newNameLower
//             final List<String> upstreamList = adjacency.producersByFlow.remove(oldNameLower) ?? [];
//             final List<String> downstreamList = adjacency.consumersByFlow.remove(oldNameLower) ?? [];
//             adjacency.producersByFlow[newNameLower] = upstreamList;
//             adjacency.consumersByFlow[newNameLower] = downstreamList;

//             // Update in each ProcessNode’s inputs/outputs
//             clonedById.forEach((otherPid, node) {
//               bool nodeChanged = false;

//               // Update inputs
//               final List<FlowValue> updatedInputs = node.inputs.map((fv) {
//                 if (fv.name.toLowerCase() == oldNameLower) {
//                   nodeChanged = true;
//                   print("[mergeScenarios][$scenarioName]       → Process \"$otherPid\" input \"$oldFlowName\" → \"$newName\"");
//                   return FlowValue(name: newName, amount: fv.amount, unit: fv.unit);
//                 }
//                 return fv;
//               }).toList();

//               // Update outputs
//               final List<FlowValue> updatedOutputs = node.outputs.map((fv) {
//                 if (fv.name.toLowerCase() == oldNameLower) {
//                   nodeChanged = true;
//                   print("[mergeScenarios][$scenarioName]       → Process \"$otherPid\" output \"$oldFlowName\" → \"$newName\"");
//                   return FlowValue(name: newName, amount: fv.amount, unit: fv.unit);
//                 }
//                 return fv;
//               }).toList();

//               if (nodeChanged) {
//                 clonedById[otherPid] = ProcessNode(
//                   id: node.id,
//                   name: node.name,
//                   inputs: updatedInputs,
//                   outputs: updatedOutputs,
//                   co2: node.co2,
//                   position: node.position,
//                 );
//                 adjacency.processById[otherPid] = clonedById[otherPid]!;
//               }
//             });
//           }
//         } else {
//           print("[mergeScenarios][$scenarioName]   [Warning] Process ID=\"$pid\" not found to rename.");
//         }
//       }

//       // D) Rename an existing flow?
//       //    If flow_id matches a global flow, rename that. Otherwise, if flow_id matches a process,
//       //    rename all FlowValue names inside that process.
//       else if (change.containsKey('flow_id') && change['field'] == 'name') {
//         final String fid = change['flow_id'] as String;
//         final String newName = change['new_value'] as String;

//         if (clonedFlowById.containsKey(fid)) {
//           // Case 1: flow_id is a real global flow entry
//           final oldFlowJson = clonedFlowById[fid]!;
//           final String oldName = oldFlowJson['name'] as String;
//           print("[mergeScenarios][$scenarioName]   [Rename Flow] \"$fid\": \"$oldName\" → \"$newName\"");

//           // Update the flow JSON itself
//           oldFlowJson['name'] = newName;

//           // Update adjacency: move producers/consumers under oldName → newName
//           final String oldNameLower = oldName.toLowerCase();
//           final String newNameLower = newName.toLowerCase();

//           final List<String> upstreamList = adjacency.producersByFlow.remove(oldNameLower) ?? [];
//           final List<String> downstreamList = adjacency.consumersByFlow.remove(oldNameLower) ?? [];
//           adjacency.producersByFlow[newNameLower] = upstreamList;
//           adjacency.consumersByFlow[newNameLower] = downstreamList;

//           // In every cloned ProcessNode, update any FlowValue whose name matches oldName
//           clonedById.forEach((pid, node) {
//             bool nodeChanged = false;

//             // Update inputs
//             final List<FlowValue> updatedInputs = node.inputs.map((fv) {
//               if (fv.name.toLowerCase() == oldNameLower) {
//                 nodeChanged = true;
//                 print("[mergeScenarios][$scenarioName]     → Process \"$pid\" input \"$oldName\" → \"$newName\"");
//                 return FlowValue(name: newName, amount: fv.amount, unit: fv.unit);
//               }
//               return fv;
//             }).toList();

//             // Update outputs
//             final List<FlowValue> updatedOutputs = node.outputs.map((fv) {
//               if (fv.name.toLowerCase() == oldNameLower) {
//                 nodeChanged = true;
//                 print("[mergeScenarios][$scenarioName]     → Process \"$pid\" output \"$oldName\" → \"$newName\"");
//                 return FlowValue(name: newName, amount: fv.amount, unit: fv.unit);
//               }
//               return fv;
//             }).toList();

//             if (nodeChanged) {
//               clonedById[pid] = ProcessNode(
//                 id: node.id,
//                 name: node.name,
//                 inputs: updatedInputs,
//                 outputs: updatedOutputs,
//                 co2: node.co2,
//                 position: node.position,
//               );
//               adjacency.processById[pid] = clonedById[pid]!;
//             }
//           });
//         }
//         else if (clonedById.containsKey(fid)) {
//           // Case 2: flow_id actually refers to a process, so rename that process’s internal flows.
//           print("[mergeScenarios][$scenarioName]   [Rename Internal Flows of Process] \"$fid\" → new flow name \"$newName\"");

//           final ProcessNode origNode = clonedById[fid]!;
//           bool nodeChanged = false;
//           final List<FlowValue> updatedInputs = origNode.inputs.map((fv) {
//             nodeChanged = true;
//             print("[mergeScenarios][$scenarioName]     → Renaming Process \"$fid\" input \"${fv.name}\" → \"$newName\"");
//             return FlowValue(name: newName, amount: fv.amount, unit: fv.unit);
//           }).toList();

//           final List<FlowValue> updatedOutputs = origNode.outputs.map((fv) {
//             nodeChanged = true;
//             print("[mergeScenarios][$scenarioName]     → Renaming Process \"$fid\" output \"${fv.name}\" → \"$newName\"");
//             return FlowValue(name: newName, amount: fv.amount, unit: fv.unit);
//           }).toList();

//           if (nodeChanged) {
//             clonedById[fid] = ProcessNode(
//               id: origNode.id,
//               name: origNode.name,
//               inputs: updatedInputs,
//               outputs: updatedOutputs,
//               co2: origNode.co2,
//               position: origNode.position,
//             );
//             adjacency.processById[fid] = clonedById[fid]!;
//             // Register newly renamed internal flows in adjacency:
//             maybeAddNewFlowsToAdjacency(adjacency, clonedById[fid]!);
//           }
//         }
//         else {
//           print("[mergeScenarios][$scenarioName]   [Warning] Neither global flow nor process ID=\"$fid\" found to rename.");
//         }
//       }
//       // E) Otherwise, it might be a numeric override (inputs/outputs/co2) → handle later.
//     }

//     // 7) After structural edits, rebuild adjacency.processById for any newly added processes.
//     //    (Note: add_process already inserted into adjacency.processById above.)
//     for (var pid in clonedById.keys) {
//       adjacency.processById[pid] = clonedById[pid]!;
//     }

//     // 8) Now that structural edits are done, apply numeric overrides and propagate.
//     //    First, group numeric changes by process_id (ignore structural entries).
//     final Map<String, List<Map<String, dynamic>>> numericDeltasByProcess = {};
//     for (var change in rawDeltas) {
//       // Identify numeric override if it has 'process_id' AND 'new_value' is numeric,
//       // AND field starts with "inputs." or "outputs." or is "co2".
//       if (change.containsKey('process_id') &&
//           change.containsKey('field') &&
//           change.containsKey('new_value')) {
//         final field = change['field'] as String;
//         if ((field == 'co2') ||
//             field.startsWith('inputs.') ||
//             field.startsWith('outputs.')) {
//           final String pid = change['process_id'] as String;
//           numericDeltasByProcess.putIfAbsent(pid, () => []).add(change);
//         }
//       }
//     }

//     // 9) Prepare BFS queue for processes with numeric deltas
//     final Queue<String> toVisit = Queue<String>();
//     final Set<String> seen = {};

//     // 10) Apply each numeric override to its process and enqueue for propagation.
//     for (var pid in numericDeltasByProcess.keys) {
//       if (!clonedById.containsKey(pid)) {
//         print("[mergeScenarios][$scenarioName]   [Warning] Cannot apply numeric change to missing process \"$pid\".");
//         continue;
//       }
//       ProcessNode updatedNode = clonedById[pid]!;
//       print("[mergeScenarios][$scenarioName]   [Apply Numeric] to process \"$pid\":");
//       for (var change in numericDeltasByProcess[pid]!) {
//         final String field = change['field'] as String; // e.g., "inputs.glass.amount"
//         final double newVal = (change['new_value'] as num).toDouble();
//         updatedNode = applyOverrideToProcess(updatedNode, field, newVal);
//       }
//       // Register any newly introduced flows from these overrides.
//       maybeAddNewFlowsToAdjacency(adjacency, updatedNode);

//       clonedById[pid] = updatedNode;
//       toVisit.add(pid);
//       seen.add(pid);
//     }

//     // 11) BFS propagation: propagate delta changes along adjacency graph.
//     while (toVisit.isNotEmpty) {
//       final String currentId = toVisit.removeFirst();
//       final ProcessNode currUpdated = clonedById[currentId]!; // updated node
//       final ProcessNode currOrig = adjacency.processById[currentId]!; // original node

//       // --- Propagate INPUT changes upstream ---
//       for (var inFlow in currUpdated.inputs) {
//         final String rawFlow = inFlow.name;
//         final String flowNameLower = rawFlow.toLowerCase();
//         final double newAmt = inFlow.amount;

//         final double oldAmt = currOrig.inputs
//             .where((f) => f.name.toLowerCase() == flowNameLower)
//             .map((f) => f.amount)
//             .fold(0.0, (prev, amt) => amt);
//         final double deltaAmt = newAmt - oldAmt;
//         if ((deltaAmt).abs() < 1e-9) continue;

//         print(
//           "[mergeScenarios][$scenarioName]   [Propagate UP] Process \"$currentId\" input.$rawFlow changed: "
//           "$oldAmt → $newAmt (Δ = $deltaAmt)"
//         );

//         final List<String> upstreams =
//             adjacency.producersByFlow[flowNameLower] ?? [];
//         for (var prodId in upstreams) {
//           if (prodId == currentId) continue;
//           if (!clonedById.containsKey(prodId)) continue;

//           final ProcessNode origProd = adjacency.processById[prodId]!; // original producer
//           final ProcessNode updatedProd = clonedById[prodId]!; // in-progress producer

//           final double oldOut = origProd.outputs
//               .where((f) => f.name.toLowerCase() == flowNameLower)
//               .map((f) => f.amount)
//               .fold(0.0, (prev, amt) => amt);
//           final double newOut = (oldOut + deltaAmt).clamp(0.0, double.infinity);

//           print(
//             "[mergeScenarios][$scenarioName]     → To PRODUCER \"$prodId\": outputs.$rawFlow $oldOut → $newOut"
//           );

//           final ProcessNode reprod = applyOverrideToProcess(
//             updatedProd,
//             'outputs.$rawFlow.amount',
//             newOut,
//           );
//           maybeAddNewFlowsToAdjacency(adjacency, reprod);

//           clonedById[prodId] = reprod;
//           if (!seen.contains(prodId)) {
//             seen.add(prodId);
//             toVisit.add(prodId);
//           }
//         }
//       }

//       // --- Propagate OUTPUT changes downstream ---
//       for (var outFlow in currUpdated.outputs) {
//         final String rawFlow = outFlow.name;
//         final String flowNameLower = rawFlow.toLowerCase();
//         final double newAmt = outFlow.amount;

//         final double oldAmt = currOrig.outputs
//             .where((f) => f.name.toLowerCase() == flowNameLower)
//             .map((f) => f.amount)
//             .fold(0.0, (prev, amt) => amt);
//         final double deltaAmt = newAmt - oldAmt;
//         if ((deltaAmt).abs() < 1e-9) continue;

//         print(
//           "[mergeScenarios][$scenarioName]   [Propagate DOWN] Process \"$currentId\" output.$rawFlow changed: "
//           "$oldAmt → $newAmt (Δ = $deltaAmt)"
//         );

//         final List<String> downstreams =
//             adjacency.consumersByFlow[flowNameLower] ?? [];
//         for (var consId in downstreams) {
//           if (consId == currentId) continue;
//           if (!clonedById.containsKey(consId)) continue;

//           final ProcessNode origCons = adjacency.processById[consId]!; // original consumer
//           final ProcessNode updatedCons = clonedById[consId]!; // in-progress consumer

//           final double oldIn = origCons.inputs
//               .where((f) => f.name.toLowerCase() == flowNameLower)
//               .map((f) => f.amount)
//               .fold(0.0, (prev, amt) => amt);
//           final double newIn = (oldIn + deltaAmt).clamp(0.0, double.infinity);

//           print(
//             "[mergeScenarios][$scenarioName]     → To CONSUMER \"$consId\": inputs.$rawFlow $oldIn → $newIn"
//           );

//           final ProcessNode recon = applyOverrideToProcess(
//             updatedCons,
//             'inputs.$rawFlow.amount',
//             newIn,
//           );
//           maybeAddNewFlowsToAdjacency(adjacency, recon);

//           clonedById[consId] = recon;
//           if (!seen.contains(consId)) {
//             seen.add(consId);
//             toVisit.add(consId);
//           }
//         }
//       }
//     }

//     // 12) After all propagation, prepare final JSON for this scenario.

//     // 12a) Convert cloned ProcessNode → JSON
//     final List<Map<String, dynamic>> finalProcessesJson = [];
//     for (var p in clonedById.values) {
//       finalProcessesJson.add(p.toJson());
//     }

//     // 12b) The final flows list is whatever we mutated in flowsJson (with renames/adds applied).
//     final List<Map<String, dynamic>> finalFlowsJson = flowsJson;

//     // 12c) Record under "model" for this scenario
//     resultByScenario[scenarioName] = {
//       'model': {
//         'processes': finalProcessesJson,
//         'flows': finalFlowsJson,
//       }
//     };

//     print("[mergeScenarios][$scenarioName] Finished scenario\n");
//   });

//   // 13) Wrap in a top‐level "scenarios" key and return
//   return {
//     'scenarios': resultByScenario,
//   };
// }


// // File: lib/zzzz/scenario_merger.dart

// import 'dart:collection';
// import 'home.dart'; // Provides ProcessNode, FlowValue, etc.

// /// Holds adjacency information for quick lookup.
// /// - producersByFlow maps a lowercase flow name → list of process IDs that produce it.
// /// - consumersByFlow maps a lowercase flow name → list of process IDs that consume it.
// /// - processById maps a process ID → the original ProcessNode (before any overrides).
// class Adjacency {
//   final Map<String, List<String>> producersByFlow;
//   final Map<String, List<String>> consumersByFlow;
//   final Map<String, ProcessNode> processById;

//   Adjacency({
//     required this.producersByFlow,
//     required this.consumersByFlow,
//     required this.processById,
//   });
// }

// /// Builds adjacency maps so that for any flow name (case‐insensitive), you can find which
// /// processes produce it (producersByFlow) and which consume it (consumersByFlow),
// /// and also easily look up any ProcessNode by its ID.
// Adjacency buildAdjacency(
//   List<ProcessNode> processes,
//   List<Map<String, dynamic>> flows,
// ) {
//   final Map<String, List<String>> producersByFlow = {};
//   final Map<String, List<String>> consumersByFlow = {};
//   final Map<String, ProcessNode> processById = {};

//   // Register each process in the lookup map.
//   for (var p in processes) {
//     processById[p.id] = p;
//   }

//   // For each flow connection (edge in the graph), index producers/consumers by the flow names.
//   // The 'flows' list is expected to contain maps with keys: 'from': String (producer ID),
//   // 'to': String (consumer ID), and 'names': List<String> (flow names).
//   for (var conn in flows) {
//     final fromId = conn['from'] as String?; // may be null
//     final toId = conn['to'] as String?;     // may be null
//     final rawNames = conn['names'] as List<dynamic>?;

//     if (fromId == null || toId == null || rawNames == null) continue;

//     for (var rawName in rawNames) {
//       if (rawName == null) continue;
//       final flowName = rawName.toString().toLowerCase();
//       producersByFlow.putIfAbsent(flowName, () => []).add(fromId);
//       consumersByFlow.putIfAbsent(flowName, () => []).add(toId);
//     }
//   }

//   return Adjacency(
//     producersByFlow: producersByFlow,
//     consumersByFlow: consumersByFlow,
//     processById: processById,
//   );
// }

// /// Applies exactly one override to a ProcessNode (no scaling of other fields).
// /// - If field == 'co2', override the CO₂ value directly.
// /// - If field == 'inputs.<flowName>.amount', set that single input to newVal (adding it if missing).
// /// - If field == 'outputs.<flowName>.amount', set that single output to newVal (adding it if missing).
// /// Returns a NEW ProcessNode instance with the modification applied.
// ProcessNode applyOverrideToProcess(
//   ProcessNode orig,
//   String field,
//   double newVal,
// ) {
//   print("[mergeScenarios] [Override] Process \"${orig.id}\": setting $field → $newVal");

//   // Make deep copies of the original inputs/outputs lists.
//   final newInputs = orig.inputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();
//   final newOutputs = orig.outputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();
//   double newCo2 = orig.co2;

//   if (field == 'co2') {
//     print("[mergeScenarios]     → Overriding CO₂ from ${orig.co2} to $newVal");
//     newCo2 = newVal;
//   } else {
//     // Expect "inputs.<flowName>.amount" or "outputs.<flowName>.amount"
//     final parts = field.split('.');
//     if (parts.length == 3) {
//       final prefix = parts[0];    // "inputs" or "outputs"
//       final rawFlow = parts[1];   // e.g. "glass" or "Germany"
//       final flowNameLower = rawFlow.toLowerCase();

//       if (prefix == 'inputs') {
//         var found = false;
//         for (var i = 0; i < newInputs.length; i++) {
//           if (newInputs[i].name.toLowerCase() == flowNameLower) {
//             final oldAmt = newInputs[i].amount;
//             print("[mergeScenarios]     → Overriding input \"$rawFlow\": $oldAmt → $newVal");
//             newInputs[i] = FlowValue(
//               name: newInputs[i].name,
//               amount: newVal,
//               unit: newInputs[i].unit,
//             );
//             found = true;
//             break;
//           }
//         }
//         if (!found) {
//           print("[mergeScenarios]     → Adding new input flow \"$rawFlow\" with amount $newVal");
//           newInputs.add(FlowValue(
//             name: rawFlow,
//             amount: newVal,
//             unit: 'kg', // default unit; adjust if needed
//           ));
//         }
//       } else if (prefix == 'outputs') {
//         var found = false;
//         for (var i = 0; i < newOutputs.length; i++) {
//           if (newOutputs[i].name.toLowerCase() == flowNameLower) {
//             final oldAmt = newOutputs[i].amount;
//             print("[mergeScenarios]     → Overriding output \"$rawFlow\": $oldAmt → $newVal");
//             newOutputs[i] = FlowValue(
//               name: newOutputs[i].name,
//               amount: newVal,
//               unit: newOutputs[i].unit,
//             );
//             found = true;
//             break;
//           }
//         }
//         if (!found) {
//           print("[mergeScenarios]     → Adding new output flow \"$rawFlow\" with amount $newVal");
//           newOutputs.add(FlowValue(
//             name: rawFlow,
//             amount: newVal,
//             unit: 'kg', // default unit; adjust if needed
//           ));
//         }
//       }
//     }
//   }

//   return ProcessNode(
//     id: orig.id,
//     name: orig.name,
//     inputs: newInputs,
//     outputs: newOutputs,
//     co2: newCo2,
//     position: orig.position,
//   );
// }

// /// Updates adjacency maps when a new flow is introduced within a ProcessNode’s inputs/outputs.
// /// Ensures that producersByFlow and consumersByFlow have an entry for the new flow name (lowercased),
// /// even if no producers/consumers are connected yet.
// void maybeAddNewFlowsToAdjacency(
//   Adjacency adjacency,
//   ProcessNode updatedNode,
// ) {
//   // Inspect inputs
//   for (var inp in updatedNode.inputs) {
//     final flowName = inp.name.toLowerCase();
//     if (!adjacency.producersByFlow.containsKey(flowName)) {
//       adjacency.producersByFlow[flowName] = <String>[];
//       adjacency.consumersByFlow[flowName] = <String>[];
//       print("[mergeScenarios]     → Registered new flow \"$flowName\" in adjacency (as input) with no producers/consumers yet");
//     }
//   }
//   // Inspect outputs
//   for (var outp in updatedNode.outputs) {
//     final flowName = outp.name.toLowerCase();
//     if (!adjacency.producersByFlow.containsKey(flowName)) {
//       adjacency.producersByFlow[flowName] = <String>[];
//       adjacency.consumersByFlow[flowName] = <String>[];
//       print("[mergeScenarios]     → Registered new flow \"$flowName\" in adjacency (as output) with no producers/consumers yet");
//     }
//   }
// }

// /// Merges baseModel + scenario‐specific deltas into fully balanced scenario models.
// /// Now also handles:
// ///   1. Renaming existing processes (field == "name" on a process_id) and automatically
// ///      renaming any flows whose name matches the old process name.
// ///   2. Renaming existing flows    (field == "name" on a flow_id). If no global flow matches, 
// ///      but flow_id matches a process_id, rename that process’s internal flow names.
// ///   3. Adding new processes        (action == "add_process").
// ///   4. Adding new flows            (action == "add_flow").
// ///
// /// The workflow is:
// ///   • Deep-copy the base processes and flows.
// ///   • Apply structural edits (renames, additions) first: update the cloned processes list,
// ///     update the cloned flows list, and update adjacency maps accordingly.
// ///     • If renaming a process, also rename matching flows in both the flow list and all processes.
// ///     • If a flow-rename entry’s flow_id matches a process_id instead of a global flow ID, 
// ///       rename all FlowValue.name inside that process (inputs/outputs).
// ///   • Then apply numeric overrides (inputs/outputs/co2) and propagate deltas via BFS.
// ///
// /// Returns a Map<String, dynamic> of the form:
// /// {
// ///   'scenarios': {
// ///     '<scenarioName>': {
// ///       'model': {
// ///         'processes': [ ...ProcessNode JSON... ],
// ///         'flows': [ ...Flow JSON... ]
// ///       }
// ///     },
// ///     ...
// ///   }
// /// }
// Map<String, dynamic> mergeScenarios(
//   Map<String, dynamic> baseModel,
//   Map<String, List<Map<String, dynamic>>> allDeltasByScenario,
// ) {
//   // 1) Extract base JSON lists
//   final List<Map<String, dynamic>> baseProcessesJson =
//       List<Map<String, dynamic>>.from(baseModel['processes'] as List? ?? []);
//   final List<Map<String, dynamic>> baseFlowsJson =
//       List<Map<String, dynamic>>.from(baseModel['flows'] as List? ?? []);

//   // 2) Convert base JSON → ProcessNode
//   final List<ProcessNode> baseProcesses =
//       baseProcessesJson.map((j) => ProcessNode.fromJson(j)).toList();

//   // 3) Build adjacency maps once (from the base processes & base flows)
//   final Adjacency adjacency = buildAdjacency(baseProcesses, baseFlowsJson);

//   // 4) Build a lookup from flow_id → flow JSON, so we can rename flows by ID.
//   final Map<String, Map<String, dynamic>> flowById = {
//     for (var f in baseFlowsJson)
//       if (f['id'] is String) f['id'] as String: f
//   };

//   // 5) Prepare container for per‐scenario results
//   final Map<String, Map<String, dynamic>> resultByScenario = {};

//   // 6) Process each scenario one by one.
//   allDeltasByScenario.forEach((scenarioName, rawDeltas) {
//     print("\n=== [mergeScenarios][$scenarioName] Starting scenario ===");

//     // 6a) Deep-copy base processes into a mutable map: clonedById
//     final clonedById = <String, ProcessNode>{};
//     for (var p in baseProcesses) {
//       clonedById[p.id] = ProcessNode.fromJson(p.toJson());
//     }

//     // 6b) Deep-copy baseFlowsJson into a new list, so we can rename/add flows
//     final flowsJson = <Map<String, dynamic>>[
//       for (var f in baseFlowsJson) Map<String, dynamic>.from(f)
//     ];

//     // Also maintain a mutable flowById for the cloned flows
//     final clonedFlowById = <String, Map<String, dynamic>>{
//       for (var f in flowsJson) if (f['id'] is String) f['id'] as String: f
//     };

//     // 6c) First pass: handle all structural edits (rename/add) BEFORE numeric overrides.
//     for (var change in rawDeltas) {
//       final action = change['action'] as String?;
//       final field = change['field'] as String?;
//       final procId = change['process_id'] as String?;
//       final flowId = change['flow_id'] as String?;

//       // A) Add a new process?
//       if (action == 'add_process') {
//         final newProcessJson = (change['process'] as Map<String, dynamic>?);
//         if (newProcessJson != null) {
//           try {
//             final newNode = ProcessNode.fromJson(newProcessJson);
//             print("[mergeScenarios][$scenarioName]   [Add Process] Adding new process ID=\"${newNode.id}\", name=\"${newNode.name}\"");
//             // 1. Add to clonedById
//             clonedById[newNode.id] = newNode;
//             // 2. Add to adjacency.processById (so that numeric propagation can see it)
//             adjacency.processById[newNode.id] = newNode;
//             // 3. Register any flows that this new process references
//             maybeAddNewFlowsToAdjacency(adjacency, newNode);
//           } catch (e) {
//             print("[mergeScenarios][$scenarioName]   [Error] invalid add_process JSON: $e");
//           }
//         }
//       }
//       // B) Add a new flow?
//       else if (action == 'add_flow') {
//         final newFlowJson = (change['flow'] as Map<String, dynamic>?);
//         if (newFlowJson != null && newFlowJson['id'] is String && newFlowJson['name'] is String) {
//           final newFlowId = newFlowJson['id'] as String;
//           final newFlowName = newFlowJson['name'] as String;
//           print("[mergeScenarios][$scenarioName]   [Add Flow] Adding new flow ID=\"$newFlowId\", name=\"$newFlowName\"");

//           // 1. Add to flowsJson
//           flowsJson.add(newFlowJson);
//           // 2. Add to adjacency maps under lowercase name
//           final newFlowNameLower = newFlowName.toLowerCase();
//           adjacency.producersByFlow.putIfAbsent(newFlowNameLower, () => []);
//           adjacency.consumersByFlow.putIfAbsent(newFlowNameLower, () => []);
//           // 3. Register in clonedFlowById
//           clonedFlowById[newFlowId] = newFlowJson;
//         } else {
//           print("[mergeScenarios][$scenarioName]   [Warning] invalid add_flow JSON or missing id/name");
//         }
//       }
//       // C) Rename an existing process?
//       else if (procId != null && field == 'name') {
//         if (clonedById.containsKey(procId)) {
//           final oldNode = clonedById[procId]!;
//           final oldName = oldNode.name;
//           final newName = change['new_value'] is String ? change['new_value'] as String : '';
//           if (newName.isNotEmpty) {
//             print("[mergeScenarios][$scenarioName]   [Rename Process] \"$procId\": \"$oldName\" → \"$newName\"");
//             // 1. Update the ProcessNode’s name
//             clonedById[procId] = ProcessNode(
//               id: oldNode.id,
//               name: newName,
//               inputs: oldNode.inputs
//                   .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//                   .toList(),
//               outputs: oldNode.outputs
//                   .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//                   .toList(),
//               co2: oldNode.co2,
//               position: oldNode.position,
//             );
//             adjacency.processById[procId] = clonedById[procId]!;

//             // 2. Automatically rename any flow whose name matches the old process name
//             final oldNameLower = oldName.toLowerCase();
//             final newNameLower = newName.toLowerCase();
//             final flowsToRename = <String>[];

//             // Identify flow IDs to rename
//             for (var entry in clonedFlowById.entries) {
//               final fidKey = entry.key;
//               final flowJson = entry.value;
//               final nameVal = flowJson['name'] as String?;
//               if (nameVal != null && nameVal.toLowerCase() == oldNameLower) {
//                 flowsToRename.add(fidKey);
//               }
//             }

//             for (var fidKey in flowsToRename) {
//               final flowJson = clonedFlowById[fidKey]!;
//               final oldFlowName = (flowJson['name'] as String?) ?? '';
//               print("[mergeScenarios][$scenarioName]     [Auto-Rename Flow] \"$fidKey\": \"$oldFlowName\" → \"$newName\"");

//               // Update flow JSON
//               flowJson['name'] = newName;

//               // Update adjacency: move producers/consumers under oldNameLower → newNameLower
//               final upstreamList = adjacency.producersByFlow.remove(oldNameLower) ?? [];
//               final downstreamList = adjacency.consumersByFlow.remove(oldNameLower) ?? [];
//               adjacency.producersByFlow[newNameLower] = upstreamList;
//               adjacency.consumersByFlow[newNameLower] = downstreamList;

//               // Update in each ProcessNode’s inputs/outputs
//               clonedById.forEach((otherPid, node) {
//                 var nodeChanged = false;

//                 // Update inputs
//                 final updatedInputs = node.inputs.map((fv) {
//                   if (fv.name.toLowerCase() == oldNameLower) {
//                     nodeChanged = true;
//                     print("[mergeScenarios][$scenarioName]       → Process \"$otherPid\" input \"$oldFlowName\" → \"$newName\"");
//                     return FlowValue(name: newName, amount: fv.amount, unit: fv.unit);
//                   }
//                   return fv;
//                 }).toList();

//                 // Update outputs
//                 final updatedOutputs = node.outputs.map((fv) {
//                   if (fv.name.toLowerCase() == oldNameLower) {
//                     nodeChanged = true;
//                     print("[mergeScenarios][$scenarioName]       → Process \"$otherPid\" output \"$oldFlowName\" → \"$newName\"");
//                     return FlowValue(name: newName, amount: fv.amount, unit: fv.unit);
//                   }
//                   return fv;
//                 }).toList();

//                 if (nodeChanged) {
//                   clonedById[otherPid] = ProcessNode(
//                     id: node.id,
//                     name: node.name,
//                     inputs: updatedInputs,
//                     outputs: updatedOutputs,
//                     co2: node.co2,
//                     position: node.position,
//                   );
//                   adjacency.processById[otherPid] = clonedById[otherPid]!;
//                 }
//               });
//             }
//           } else {
//             print("[mergeScenarios][$scenarioName]   [Warning] rename process missing new_value or new_value not a string");
//           }
//         } else {
//           print("[mergeScenarios][$scenarioName]   [Warning] Process ID=\"$procId\" not found to rename.");
//         }
//       }
//       // D) Rename an existing flow?
//       //    If flow_id matches a global flow entry, rename that. Otherwise, if flow_id matches a process,
//       //    rename all FlowValue names inside that process.
//       else if (flowId != null && field == 'name') {
//         final newName = change['new_value'] is String ? change['new_value'] as String : '';
//         if (newName.isEmpty) {
//           print("[mergeScenarios][$scenarioName]   [Warning] rename flow missing new_value or new_value not a string");
//           continue;
//         }

//         if (clonedFlowById.containsKey(flowId)) {
//           // Case 1: flow_id is a real global flow entry
//           final flowJson = clonedFlowById[flowId]!;
//           final oldNameVal = (flowJson['name'] as String?) ?? '';
//           if (oldNameVal.isEmpty) {
//             print("[mergeScenarios][$scenarioName]   [Warning] flow ID=\"$flowId\" has no 'name' field to rename");
//             continue;
//           }
//           final oldNameLower = oldNameVal.toLowerCase();
//           final newNameLower = newName.toLowerCase();

//           print("[mergeScenarios][$scenarioName]   [Rename Flow] \"$flowId\": \"$oldNameVal\" → \"$newName\"");

//           // 1. Update the flow JSON itself
//           flowJson['name'] = newName;

//           // 2. Update adjacency: move producers/consumers under oldNameLower → newNameLower
//           final upstreamList = adjacency.producersByFlow.remove(oldNameLower) ?? [];
//           final downstreamList = adjacency.consumersByFlow.remove(oldNameLower) ?? [];
//           adjacency.producersByFlow[newNameLower] = upstreamList;
//           adjacency.consumersByFlow[newNameLower] = downstreamList;

//           // 3. In every cloned ProcessNode, update any FlowValue whose name matches oldNameLower
//           clonedById.forEach((pidKey, node) {
//             var nodeChanged = false;

//             // Update inputs
//             final updatedInputs = node.inputs.map((fv) {
//               if (fv.name.toLowerCase() == oldNameLower) {
//                 nodeChanged = true;
//                 print("[mergeScenarios][$scenarioName]     → Process \"$pidKey\" input \"$oldNameVal\" → \"$newName\"");
//                 return FlowValue(name: newName, amount: fv.amount, unit: fv.unit);
//               }
//               return fv;
//             }).toList();

//             // Update outputs
//             final updatedOutputs = node.outputs.map((fv) {
//               if (fv.name.toLowerCase() == oldNameLower) {
//                 nodeChanged = true;
//                 print("[mergeScenarios][$scenarioName]     → Process \"$pidKey\" output \"$oldNameVal\" → \"$newName\"");
//                 return FlowValue(name: newName, amount: fv.amount, unit: fv.unit);
//               }
//               return fv;
//             }).toList();

//             if (nodeChanged) {
//               clonedById[pidKey] = ProcessNode(
//                 id: node.id,
//                 name: node.name,
//                 inputs: updatedInputs,
//                 outputs: updatedOutputs,
//                 co2: node.co2,
//                 position: node.position,
//               );
//               adjacency.processById[pidKey] = clonedById[pidKey]!;
//             }
//           });
//         }
//         else if (clonedById.containsKey(flowId)) {
//           // Case 2: flow_id actually refers to a process, so rename that process’s internal flows.
//           print("[mergeScenarios][$scenarioName]   [Rename Internal Flows of Process] \"$flowId\" → new flow name \"$newName\"");

//           final origNode = clonedById[flowId]!;
//           var nodeChanged = false;

//           final updatedInputs = origNode.inputs.map((fv) {
//             nodeChanged = true;
//             print("[mergeScenarios][$scenarioName]     → Renaming Process \"$flowId\" input \"${fv.name}\" → \"$newName\"");
//             return FlowValue(name: newName, amount: fv.amount, unit: fv.unit);
//           }).toList();

//           final updatedOutputs = origNode.outputs.map((fv) {
//             nodeChanged = true;
//             print("[mergeScenarios][$scenarioName]     → Renaming Process \"$flowId\" output \"${fv.name}\" → \"$newName\"");
//             return FlowValue(name: newName, amount: fv.amount, unit: fv.unit);
//           }).toList();

//           if (nodeChanged) {
//             clonedById[flowId] = ProcessNode(
//               id: origNode.id,
//               name: origNode.name,
//               inputs: updatedInputs,
//               outputs: updatedOutputs,
//               co2: origNode.co2,
//               position: origNode.position,
//             );
//             adjacency.processById[flowId] = clonedById[flowId]!;
//             maybeAddNewFlowsToAdjacency(adjacency, clonedById[flowId]!);
//           }
//         } else {
//           print("[mergeScenarios][$scenarioName]   [Warning] Neither global flow nor process ID=\"$flowId\" found to rename.");
//         }
//       }
//       // E) Otherwise, it's a numeric override (inputs/outputs/co2)—handle later.
//     }

//     // 7) After structural edits, rebuild adjacency.processById for any newly added processes.
//     for (var pidKey in clonedById.keys) {
//       adjacency.processById[pidKey] = clonedById[pidKey]!;
//     }

//     // 8) Now that structural edits are done, apply numeric overrides and propagate.
//     //    First, group numeric changes by process_id.
//     final numericDeltasByProcess = <String, List<Map<String, dynamic>>>{};
//     for (var change in rawDeltas) {
//       final procId = change['process_id'] as String?;
//       final field = change['field'] as String?;
//       final newValRaw = change['new_value'];

//       if (procId != null && field != null && newValRaw is num) {
//         if (field == 'co2' || field.startsWith('inputs.') || field.startsWith('outputs.')) {
//           numericDeltasByProcess.putIfAbsent(procId, () => []).add(change);
//         }
//       }
//     }

//     // 9) Prepare BFS queue for processes with numeric deltas
//     final toVisit = Queue<String>();
//     final seen = <String>{};

//     // 10) Apply each numeric override to its process and enqueue for propagation.
//     numericDeltasByProcess.forEach((procId, changes) {
//       if (!clonedById.containsKey(procId)) {
//         print("[mergeScenarios][$scenarioName]   [Warning] Cannot apply numeric change to missing process \"$procId\".");
//         return;
//       }
//       var updatedNode = clonedById[procId]!;
//       print("[mergeScenarios][$scenarioName]   [Apply Numeric] to process \"$procId\":");
//       for (var change in changes) {
//         final field = change['field'] as String;
//         final newVal = (change['new_value'] as num).toDouble();
//         updatedNode = applyOverrideToProcess(updatedNode, field, newVal);
//       }
//       maybeAddNewFlowsToAdjacency(adjacency, updatedNode);
//       clonedById[procId] = updatedNode;
//       toVisit.add(procId);
//       seen.add(procId);
//     });

//     // 11) BFS propagation: propagate delta changes along adjacency graph.
//     while (toVisit.isNotEmpty) {
//       final currentId = toVisit.removeFirst();
//       final currUpdated = clonedById[currentId]!;       // updated node
//       final currOrig = adjacency.processById[currentId]!; // original node

//       // --- Propagate INPUT changes upstream ---
//       for (var inFlow in currUpdated.inputs) {
//         final rawFlow = inFlow.name;
//         final flowNameLower = rawFlow.toLowerCase();
//         final newAmt = inFlow.amount;

//         final oldAmt = currOrig.inputs
//             .where((f) => f.name.toLowerCase() == flowNameLower)
//             .map((f) => f.amount)
//             .fold(0.0, (prev, amt) => amt);
//         final deltaAmt = newAmt - oldAmt;
//         if ((deltaAmt).abs() < 1e-9) continue;

//         print(
//           "[mergeScenarios][$scenarioName]   [Propagate UP] Process \"$currentId\" input.$rawFlow changed: "
//           "$oldAmt → $newAmt (Δ = $deltaAmt)"
//         );

//         final upstreams = adjacency.producersByFlow[flowNameLower] ?? [];
//         for (var prodId in upstreams) {
//           if (prodId == currentId || !clonedById.containsKey(prodId)) continue;
//           final origProd = adjacency.processById[prodId]!;
//           final updatedProd = clonedById[prodId]!;

//           final oldOut = origProd.outputs
//               .where((f) => f.name.toLowerCase() == flowNameLower)
//               .map((f) => f.amount)
//               .fold(0.0, (prev, amt) => amt);
//           final newOut = (oldOut + deltaAmt).clamp(0.0, double.infinity);

//           print(
//             "[mergeScenarios][$scenarioName]     → To PRODUCER \"$prodId\": outputs.$rawFlow $oldOut → $newOut"
//           );

//           final reprod = applyOverrideToProcess(
//             updatedProd,
//             'outputs.$rawFlow.amount',
//             newOut,
//           );
//           maybeAddNewFlowsToAdjacency(adjacency, reprod);
//           clonedById[prodId] = reprod;
//           if (!seen.contains(prodId)) {
//             seen.add(prodId);
//             toVisit.add(prodId);
//           }
//         }
//       }

//       // --- Propagate OUTPUT changes downstream ---
//       for (var outFlow in currUpdated.outputs) {
//         final rawFlow = outFlow.name;
//         final flowNameLower = rawFlow.toLowerCase();
//         final newAmt = outFlow.amount;

//         final oldAmt = currOrig.outputs
//             .where((f) => f.name.toLowerCase() == flowNameLower)
//             .map((f) => f.amount)
//             .fold(0.0, (prev, amt) => amt);
//         final deltaAmt = newAmt - oldAmt;
//         if ((deltaAmt).abs() < 1e-9) continue;

//         print(
//           "[mergeScenarios][$scenarioName]   [Propagate DOWN] Process \"$currentId\" output.$rawFlow changed: "
//           "$oldAmt → $newAmt (Δ = $deltaAmt)"
//         );

//         final downstreams = adjacency.consumersByFlow[flowNameLower] ?? [];
//         for (var consId in downstreams) {
//           if (consId == currentId || !clonedById.containsKey(consId)) continue;
//           final origCons = adjacency.processById[consId]!;
//           final updatedCons = clonedById[consId]!;

//           final oldIn = origCons.inputs
//               .where((f) => f.name.toLowerCase() == flowNameLower)
//               .map((f) => f.amount)
//               .fold(0.0, (prev, amt) => amt);
//           final newIn = (oldIn + deltaAmt).clamp(0.0, double.infinity);

//           print(
//             "[mergeScenarios][$scenarioName]     → To CONSUMER \"$consId\": inputs.$rawFlow $oldIn → $newIn"
//           );

//           final recon = applyOverrideToProcess(
//             updatedCons,
//             'inputs.$rawFlow.amount',
//             newIn,
//           );
//           maybeAddNewFlowsToAdjacency(adjacency, recon);
//           clonedById[consId] = recon;
//           if (!seen.contains(consId)) {
//             seen.add(consId);
//             toVisit.add(consId);
//           }
//         }
//       }
//     }

//     // 12) After all propagation, prepare final JSON for this scenario.

//     // 12a) Convert cloned ProcessNode → JSON
//     final finalProcessesJson = <Map<String, dynamic>>[];
//     for (var p in clonedById.values) {
//       finalProcessesJson.add(p.toJson());
//     }

//     // 12b) The final flows list is whatever we mutated in flowsJson (with renames/adds applied).
//     final finalFlowsJson = flowsJson;

//     // 12c) Record under "model" for this scenario
//     resultByScenario[scenarioName] = {
//       'model': {
//         'processes': finalProcessesJson,
//         'flows': finalFlowsJson,
//       }
//     };

//     print("[mergeScenarios][$scenarioName] Finished scenario\n");
//   });

//   // 13) Wrap in a top‐level "scenarios" key and return
//   return {
//     'scenarios': resultByScenario,
//   };
// }


// // File: lib/zzzz/scenario_merger.dart

// import 'dart:collection';
// import 'home.dart'; // Provides ProcessNode, FlowValue, etc.

// /// Holds adjacency information for quick lookup.
// /// - producersByFlow maps a lowercase flow name → list of process IDs that produce it.
// /// - consumersByFlow maps a lowercase flow name → list of process IDs that consume it.
// /// - processById maps a process ID → the original ProcessNode (before any overrides).
// class Adjacency {
//   final Map<String, List<String>> producersByFlow;
//   final Map<String, List<String>> consumersByFlow;
//   final Map<String, ProcessNode> processById;

//   Adjacency({
//     required this.producersByFlow,
//     required this.consumersByFlow,
//     required this.processById,
//   });
// }

// /// Builds adjacency maps so that for any flow name (case‐insensitive), you can find which
// /// processes produce it (producersByFlow) and which consume it (consumersByFlow),
// /// and also easily look up any ProcessNode by its ID.
// Adjacency buildAdjacency(
//   List<ProcessNode> processes,
//   List<Map<String, dynamic>> flows,
// ) {
//   final Map<String, List<String>> producersByFlow = {};
//   final Map<String, List<String>> consumersByFlow = {};
//   final Map<String, ProcessNode> processById = {};

//   // Register each process in the lookup map.
//   for (var p in processes) {
//     processById[p.id] = p;
//   }

//   // For each flow connection (edge in the graph), index producers/consumers by the flow names.
//   // The 'flows' list is expected to contain maps with keys: 'from': String (producer ID),
//   // 'to': String (consumer ID), and 'names': List<String> (flow names).
//   for (var conn in flows) {
//     final String fromId = conn['from'] as String;
//     final String toId = conn['to'] as String;
//     final List<String> names = List<String>.from(conn['names'] as List);

//     for (var rawName in names) {
//       final String flowName = rawName.toLowerCase();
//       producersByFlow.putIfAbsent(flowName, () => []).add(fromId);
//       consumersByFlow.putIfAbsent(flowName, () => []).add(toId);
//     }
//   }

//   return Adjacency(
//     producersByFlow: producersByFlow,
//     consumersByFlow: consumersByFlow,
//     processById: processById,
//   );
// }

// /// Applies exactly one override to a ProcessNode (no scaling of other fields).
// /// - If field == 'co2', override the CO₂ value directly.
// /// - If field == 'inputs.<flowName>.amount', set that single input to newVal (adding it if missing).
// /// - If field == 'outputs.<flowName>.amount', set that single output to newVal (adding it if missing).
// /// Returns a NEW ProcessNode instance with the modification applied.
// ProcessNode applyOverrideToProcess(
//   ProcessNode orig,
//   String field,
//   double newVal,
// ) {
//   print("  [Override] Process ${orig.id}: setting $field → $newVal");

//   // Make deep copies of the original inputs/outputs lists.
//   final List<FlowValue> newInputs = orig.inputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();
//   final List<FlowValue> newOutputs = orig.outputs
//       .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//       .toList();
//   double newCo2 = orig.co2;

//   if (field == 'co2') {
//     print("    → Overriding CO₂ from ${orig.co2} to $newVal");
//     newCo2 = newVal;
//   } else {
//     // Expect "inputs.<flowName>.amount" or "outputs.<flowName>.amount"
//     final parts = field.split('.');
//     if (parts.length == 3) {
//       final prefix = parts[0]; // "inputs" or "outputs"
//       final rawFlow = parts[1]; // e.g. "glass" or "PMMA"
//       final flowNameLower = rawFlow.toLowerCase();

//       if (prefix == 'inputs') {
//         bool found = false;
//         for (int i = 0; i < newInputs.length; i++) {
//           if (newInputs[i].name.toLowerCase() == flowNameLower) {
//             final double oldAmt = newInputs[i].amount;
//             print("    → Overriding input $rawFlow: $oldAmt → $newVal");
//             newInputs[i] = FlowValue(
//               name: newInputs[i].name,
//               amount: newVal,
//               unit: newInputs[i].unit,
//             );
//             found = true;
//             break;
//           }
//         }
//         if (!found) {
//           // Add new FlowValue if missing.
//           print("    → Adding new input flow \"$rawFlow\" with amount $newVal");
//           newInputs.add(FlowValue(
//             name: rawFlow,
//             amount: newVal,
//             unit: 'kg', // default unit; adjust if needed
//           ));
//         }
//       } else if (prefix == 'outputs') {
//         bool found = false;
//         for (int i = 0; i < newOutputs.length; i++) {
//           if (newOutputs[i].name.toLowerCase() == flowNameLower) {
//             final double oldAmt = newOutputs[i].amount;
//             print("    → Overriding output $rawFlow: $oldAmt → $newVal");
//             newOutputs[i] = FlowValue(
//               name: newOutputs[i].name,
//               amount: newVal,
//               unit: newOutputs[i].unit,
//             );
//             found = true;
//             break;
//           }
//         }
//         if (!found) {
//           // Add new FlowValue if missing.
//           print("    → Adding new output flow \"$rawFlow\" with amount $newVal");
//           newOutputs.add(FlowValue(
//             name: rawFlow,
//             amount: newVal,
//             unit: 'kg', // default unit; adjust if needed
//           ));
//         }
//       }
//     }
//   }

//   return ProcessNode(
//     id: orig.id,
//     name: orig.name,
//     inputs: newInputs,
//     outputs: newOutputs,
//     co2: newCo2,
//     position: orig.position,
//   );
// }

// /// Updates adjacency maps when a new flow is introduced within a ProcessNode’s inputs/outputs.
// /// Ensures that producersByFlow and consumersByFlow have an entry for the new flow name (lowercased),
// /// even if no producers/consumers are connected yet.
// void maybeAddNewFlowsToAdjacency(
//   Adjacency adjacency,
//   ProcessNode updatedNode,
// ) {
//   // Inspect inputs
//   for (var inp in updatedNode.inputs) {
//     final flowName = inp.name.toLowerCase();
//     if (!adjacency.producersByFlow.containsKey(flowName)) {
//       adjacency.producersByFlow[flowName] = <String>[];
//       adjacency.consumersByFlow[flowName] = <String>[];
//       print("    → Registered new flow \"$flowName\" in adjacency (as input) with no producers/consumers yet");
//     }
//   }
//   // Inspect outputs
//   for (var outp in updatedNode.outputs) {
//     final flowName = outp.name.toLowerCase();
//     if (!adjacency.producersByFlow.containsKey(flowName)) {
//       adjacency.producersByFlow[flowName] = <String>[];
//       adjacency.consumersByFlow[flowName] = <String>[];
//       print("    → Registered new flow \"$flowName\" in adjacency (as output) with no producers/consumers yet");
//     }
//   }
// }

// /// Merges baseModel + scenario‐specific deltas into fully balanced scenario models.
// /// Now also handles:
// ///   1. Renaming existing processes (field == "name" on a process_id).
// ///   2. Renaming existing flows    (field == "name" on a flow_id).
// ///   3. Adding new processes        (action == "add_process").
// ///   4. Adding new flows            (action == "add_flow").
// ///   5. ***New***: Add a new flow *and* its supplier process in one go 
// ///      (action == "add_flow_with_supplier").
// ///
// /// The workflow is:
// ///   • Deep-copy the base processes and flows.
// ///   • Apply structural edits (renames, additions, “add_flow_with_supplier”) first: update
// ///     the cloned processes list, update the cloned flows list, and update adjacency maps accordingly.
// ///   • Then apply numeric overrides (inputs/outputs/co2) and propagate deltas via BFS.
// ///
// /// Returns a Map<String, dynamic> of the form:
// /// {
// ///   'scenarios': {
// ///     '<scenarioName>': {
// ///       'model': {
// ///         'processes': [ ...ProcessNode JSON... ],
// ///         'flows': [ ...Flow JSON... ]
// ///       }
// ///     },
// ///     ...
// ///   }
// /// }
// Map<String, dynamic> mergeScenarios(
//   Map<String, dynamic> baseModel,
//   Map<String, List<Map<String, dynamic>>> allDeltasByScenario,
// ) {
//   // 1) Extract base JSON lists
//   final List<Map<String, dynamic>> baseProcessesJson =
//       List<Map<String, dynamic>>.from(baseModel['processes'] as List);
//   final List<Map<String, dynamic>> baseFlowsJson =
//       List<Map<String, dynamic>>.from(baseModel['flows'] as List);

//   // 2) Convert base JSON → ProcessNode
//   final List<ProcessNode> baseProcesses =
//       baseProcessesJson.map((j) => ProcessNode.fromJson(j)).toList();

//   // 3) Build adjacency maps once (from the base processes & base flows)
//   final Adjacency adjacency = buildAdjacency(baseProcesses, baseFlowsJson);

//   // 4) Build a lookup from flow_id → flow JSON, so we can rename flows by ID.
//   final Map<String, Map<String, dynamic>> flowById = {
//     for (var f in baseFlowsJson) f['id'] as String: f
//   };

//   // 5) Prepare container for per‐scenario results
//   final Map<String, Map<String, dynamic>> resultByScenario = {};

//   // 6) Process each scenario one by one.
//   allDeltasByScenario.forEach((scenarioName, rawDeltas) {
//     print("\n=== [mergeScenarios][$scenarioName] Starting scenario ===");

//     // 6a) Deep-copy base processes into a mutable map: clonedById
//     final Map<String, ProcessNode> clonedById = {};
//     for (var p in baseProcesses) {
//       clonedById[p.id] = ProcessNode.fromJson(p.toJson());
//     }

//     // 6b) Deep-copy baseFlowsJson into a new list, so we can rename/add flows
//     final List<Map<String, dynamic>> flowsJson = [
//       for (var f in baseFlowsJson) Map<String, dynamic>.from(f)
//     ];

//     // Also maintain a mutable flowById for the cloned flows
//     final Map<String, Map<String, dynamic>> clonedFlowById = {
//       for (var f in flowsJson) f['id'] as String: f
//     };

//     // 6c) First pass: handle all structural edits (rename/add/add_flow_with_supplier) BEFORE numeric overrides.
//     for (var change in rawDeltas) {
//       // A) Add a new process?
//       if (change.containsKey('action') && change['action'] == 'add_process') {
//         final Map<String, dynamic> newProcessJson =
//             Map<String, dynamic>.from(change['process'] as Map<String, dynamic>);
//         final ProcessNode newNode = ProcessNode.fromJson(newProcessJson);
//         print("  [Add Process] Adding new process with ID \"${newNode.id}\" and name \"${newNode.name}\"");

//         // 1. Add to clonedById
//         clonedById[newNode.id] = newNode;

//         // 2. Add to adjacency.processById (so that numeric propagation can see it)
//         adjacency.processById[newNode.id] = newNode;

//         // 3. Register any flows that this new process references
//         maybeAddNewFlowsToAdjacency(adjacency, newNode);
//       }

//       // B) Add a new flow?
//       else if (change.containsKey('action') && change['action'] == 'add_flow') {
//         final Map<String, dynamic> newFlowJson =
//             Map<String, dynamic>.from(change['flow'] as Map<String, dynamic>);
//         final String newFlowId = newFlowJson['id'] as String;
//         print("  [Add Flow] Adding new flow with ID \"$newFlowId\" and name \"${newFlowJson['name']}\"");

//         // 1. Add to flowsJson
//         flowsJson.add(newFlowJson);

//         // 2. Add to adjacency maps under lowercase name
//         final String newFlowNameLower =
//             (newFlowJson['name'] as String).toLowerCase();
//         adjacency.producersByFlow.putIfAbsent(newFlowNameLower, () => []);
//         adjacency.consumersByFlow.putIfAbsent(newFlowNameLower, () => []);

//         // 3. Register in clonedFlowById
//         clonedFlowById[newFlowId] = newFlowJson;
//       }

//       // C) Rename an existing process?
//       else if (change.containsKey('process_id') &&
//           change['field'] == 'name') {
//         final String pid = change['process_id'] as String;
//         final String newName = change['new_value'] as String;
//         if (clonedById.containsKey(pid)) {
//           print("  [Rename Process] Changing name of process \"$pid\" → \"$newName\"");
//           final oldNode = clonedById[pid]!;
//           clonedById[pid] = ProcessNode(
//             id: oldNode.id,
//             name: newName,
//             inputs: oldNode.inputs
//                 .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//                 .toList(),
//             outputs: oldNode.outputs
//                 .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//                 .toList(),
//             co2: oldNode.co2,
//             position: oldNode.position,
//           );
//           // Also update adjacency.processById so propagation sees the new node name.
//           adjacency.processById[pid] = clonedById[pid]!;
//         } else {
//           print("  [Warning] Could not find process with ID \"$pid\" to rename.");
//         }
//       }

//       // D) Rename an existing flow?
//       else if (change.containsKey('flow_id') && change['field'] == 'name') {
//         final String fid = change['flow_id'] as String;
//         final String newName = change['new_value'] as String;
//         if (clonedFlowById.containsKey(fid)) {
//           final oldFlowJson = clonedFlowById[fid]!;
//           final String oldName = oldFlowJson['name'] as String;
//           print("  [Rename Flow] Changing name of flow \"$fid\": \"$oldName\" → \"$newName\"");

//           // 1. Update the flow JSON itself
//           oldFlowJson['name'] = newName;

//           // 2. Update adjacency: move producers/consumers under oldName → newName
//           final String oldNameLower = oldName.toLowerCase();
//           final String newNameLower = newName.toLowerCase();

//           final List<String> upstreamList =
//               adjacency.producersByFlow.remove(oldNameLower) ?? [];
//           final List<String> downstreamList =
//               adjacency.consumersByFlow.remove(oldNameLower) ?? [];

//           adjacency.producersByFlow[newNameLower] = upstreamList;
//           adjacency.consumersByFlow[newNameLower] = downstreamList;

//           // 3. In every cloned ProcessNode, update any FlowValue whose name matches oldName
//           clonedById.forEach((pid, node) {
//             bool nodeChanged = false;

//             // Update inputs
//             final List<FlowValue> updatedInputs = node.inputs.map((fv) {
//               if (fv.name.toLowerCase() == oldNameLower) {
//                 nodeChanged = true;
//                 print("    → Updating in process \"$pid\": input flow \"$oldName\" → \"$newName\"");
//                 return FlowValue(name: newName, amount: fv.amount, unit: fv.unit);
//               }
//               return fv;
//             }).toList();

//             // Update outputs
//             final List<FlowValue> updatedOutputs = node.outputs.map((fv) {
//               if (fv.name.toLowerCase() == oldNameLower) {
//                 nodeChanged = true;
//                 print("    → Updating in process \"$pid\": output flow \"$oldName\" → \"$newName\"");
//                 return FlowValue(name: newName, amount: fv.amount, unit: fv.unit);
//               }
//               return fv;
//             }).toList();

//             if (nodeChanged) {
//               clonedById[pid] = ProcessNode(
//                 id: node.id,
//                 name: node.name,
//                 inputs: updatedInputs,
//                 outputs: updatedOutputs,
//                 co2: node.co2,
//                 position: node.position,
//               );
//             }
//           });
//         } else {
//           print("  [Warning] Could not find flow with ID \"$fid\" to rename.");
//         }
//       }

//       // E) Add a new flow + supplier process in one go?
//       else if (change.containsKey('action') && change['action'] == 'add_flow_with_supplier') {
//         //
//         // Expected change map:
//         // {
//         //   "action": "add_flow_with_supplier",
//         //   "process_id": "<existingConsumerID>",
//         //   "flow": { … full Flow JSON … },
//         //   "supplier_process": { … full ProcessNode JSON … }
//         // }
//         //
//         final String existingConsumerId = change['process_id'] as String;
//         final Map<String, dynamic> newFlowJson =
//             Map<String, dynamic>.from(change['flow'] as Map<String, dynamic>);
//         final Map<String, dynamic> supplierJson =
//             Map<String, dynamic>.from(change['supplier_process'] as Map<String, dynamic>);

//         // 1) Add the new flow to flowsJson & adjacency
//         final String newFlowId = newFlowJson['id'] as String;
//         final String newFlowName = newFlowJson['name'] as String;
//         print("  [Add Flow+Supplier] Adding flow \"$newFlowName\" (ID=\"$newFlowId\") and linking to existing process \"$existingConsumerId\"");

//         flowsJson.add(newFlowJson);
//         final String newFlowLower = newFlowName.toLowerCase();
//         // Ensure adjacency entries exist
//         adjacency.producersByFlow.putIfAbsent(newFlowLower, () => []);
//         adjacency.consumersByFlow.putIfAbsent(newFlowLower, () => []);
//         // Register in clonedFlowById
//         clonedFlowById[newFlowId] = newFlowJson;

//         // 2) Add that flow as an **input** to the existing consumer process
//         if (clonedById.containsKey(existingConsumerId)) {
//           final existingNode = clonedById[existingConsumerId]!;
//           // Make a copy of its inputs and add the new flow
//           final List<FlowValue> updatedInputs = existingNode.inputs
//               .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//               .toList();

//           // Because baseModel’s consumer had no such input, oldAmt = 0
//           print("    → Adding new input \"$newFlowName\" → 0 (will be overridden or propagated later)");
//           updatedInputs.add(FlowValue(name: newFlowName, amount: 0.0, unit: newFlowJson['unit'] as String));

//           clonedById[existingConsumerId] = ProcessNode(
//             id: existingNode.id,
//             name: existingNode.name,
//             inputs: updatedInputs,
//             outputs: existingNode.outputs
//                 .map((f) => FlowValue(name: f.name, amount: f.amount, unit: f.unit))
//                 .toList(),
//             co2: existingNode.co2,
//             position: existingNode.position,
//           );

//           // Update adjacency: mark this consumer in consumersByFlow
//           adjacency.consumersByFlow[newFlowLower]!.add(existingConsumerId);
//         } else {
//           print("    [Warning] Could not find existing consumer process \"$existingConsumerId\" to attach the new flow.");
//         }

//         // 3) Create the supplier process from supplierJson
//         final ProcessNode supplierNode = ProcessNode.fromJson(supplierJson);
//         print("    → Adding supplier process \"${supplierNode.name}\" (ID=\"${supplierNode.id}\")");

//         // 3a) Add to clonedById
//         clonedById[supplierNode.id] = supplierNode;
//         // 3b) Add to adjacency.processById
//         adjacency.processById[supplierNode.id] = supplierNode;
//         // 3c) Register any flows that this new supplier references
//         maybeAddNewFlowsToAdjacency(adjacency, supplierNode);

//         // 3d) In adjacency, connect the supplier’s output (the new flowName) → the existing consumer
//         //    Find the supplier’s outputs: it should produce newFlowName
//         final String supId = supplierNode.id;
//         adjacency.producersByFlow[newFlowLower]!.add(supId);
//         // We already added the consumer above in consumersByFlow

//         // Note: If the supplier’s output amount is zero or missing, that’s acceptable; 
//         //       numeric overrides later can set actual amounts or propagation can fill in.
//       }

//       // F) Otherwise, it might be a numeric override (inputs/outputs/co2) → handle later.
//     }

//     // 7) After structural edits, rebuild adjacency.processById for any newly added processes.
//     //    (Note: we already inserted new ProcessNode into adjacency.processById above.)
//     //    We also should refresh adjacency keys if any new flows were added by add_process or add_flow_with_supplier.
//     for (var pid in clonedById.keys) {
//       adjacency.processById[pid] = clonedById[pid]!;
//     }

//     // 8) Now that structural edits are done, apply numeric overrides and propagate.
//     //    First, group numeric changes by process_id (ignore structural entries).
//     final Map<String, List<Map<String, dynamic>>> numericDeltasByProcess = {};
//     for (var change in rawDeltas) {
//       // Identify numeric override if it has 'process_id' AND 'new_value' is numeric,
//       // AND field starts with "inputs." or "outputs." or is "co2".
//       if (change.containsKey('process_id') &&
//           change.containsKey('field') &&
//           change.containsKey('new_value')) {
//         final field = change['field'] as String;
//         if (field == 'co2' ||
//             field.startsWith('inputs.') ||
//             field.startsWith('outputs.')) {
//           // This is numeric override; group it.
//           final String pid = change['process_id'] as String;
//           numericDeltasByProcess.putIfAbsent(pid, () => []).add(change);
//         }
//       }
//     }

//     // 9) Clone adjacency maps of producers/consumers so that BFS propagation includes
//     //    newly renamed/added flows. (We already amended adjacency above.)
//     //    Now prepare a queue for BFS: initially enqueue every process with a numeric delta.
//     final Queue<String> toVisit = Queue<String>();
//     final Set<String> seen = {};

//     // 10) Apply each numeric override to its process and enqueue for propagation.
//     for (var pid in numericDeltasByProcess.keys) {
//       if (!clonedById.containsKey(pid)) {
//         print("  [Warning] Cannot apply numeric change to missing process \"$pid\".");
//         continue;
//       }
//       ProcessNode updatedNode = clonedById[pid]!;
//       print("  [Apply Numeric] Applying numeric overrides to process \"$pid\":");
//       for (var change in numericDeltasByProcess[pid]!) {
//         final String field = change['field'] as String; // e.g., "inputs.glass.amount"
//         final double newVal = (change['new_value'] as num).toDouble();
//         updatedNode = applyOverrideToProcess(updatedNode, field, newVal);
//       }
//       // Register any newly introduced flows from these overrides.
//       maybeAddNewFlowsToAdjacency(adjacency, updatedNode);

//       clonedById[pid] = updatedNode;
//       toVisit.add(pid);
//       seen.add(pid);
//     }

//     // 11) BFS propagation: propagate delta changes along adjacency graph.
//     while (toVisit.isNotEmpty) {
//       final String currentId = toVisit.removeFirst();
//       final ProcessNode currUpdated = clonedById[currentId]!; // updated node
//       final ProcessNode currOrig = adjacency.processById[currentId]!; // original node (before any scenario edits)

//       // --- Propagate INPUT changes upstream ---
//       for (var inFlow in currUpdated.inputs) {
//         final String rawFlow = inFlow.name;
//         final String flowNameLower = rawFlow.toLowerCase();
//         final double newAmt = inFlow.amount;

//         // Find old amount in original node (0 if it didn't exist)
//         final double oldAmt = currOrig.inputs
//             .where((f) => f.name.toLowerCase() == flowNameLower)
//             .map((f) => f.amount)
//             .fold(0.0, (prev, amt) => amt);

//         final double deltaAmt = newAmt - oldAmt;
//         if ((deltaAmt).abs() < 1e-9) continue;

//         print(
//           "  [Propagate UP] Process \"$currentId\" input.$rawFlow changed: "
//           "$oldAmt → $newAmt (Δ = $deltaAmt)"
//         );

//         final List<String> upstreams =
//             adjacency.producersByFlow[flowNameLower] ?? [];
//         for (var prodId in upstreams) {
//           if (prodId == currentId) continue;
//           if (!clonedById.containsKey(prodId)) continue;

//           final ProcessNode origProd = adjacency.processById[prodId]!; // original producer
//           final ProcessNode updatedProd = clonedById[prodId]!; // in-progress producer

//           // Find old output amount in the producer (0 if not present)
//           final double oldOut = origProd.outputs
//               .where((f) => f.name.toLowerCase() == flowNameLower)
//               .map((f) => f.amount)
//               .fold(0.0, (prev, amt) => amt);
//           final double newOut = (oldOut + deltaAmt).clamp(0.0, double.infinity);

//           print(
//             "    → Propagate to PRODUCER \"$prodId\": outputs.$rawFlow $oldOut → $newOut"
//           );

//           final ProcessNode reprod = applyOverrideToProcess(
//             updatedProd,
//             'outputs.$rawFlow.amount',
//             newOut,
//           );
//           maybeAddNewFlowsToAdjacency(adjacency, reprod);

//           clonedById[prodId] = reprod;
//           if (!seen.contains(prodId)) {
//             seen.add(prodId);
//             toVisit.add(prodId);
//           }
//         }
//       }

//       // --- Propagate OUTPUT changes downstream ---
//       for (var outFlow in currUpdated.outputs) {
//         final String rawFlow = outFlow.name;
//         final String flowNameLower = rawFlow.toLowerCase();
//         final double newAmt = outFlow.amount;

//         // Find old amount in original node’s outputs (0 if it didn't exist)
//         final double oldAmt = currOrig.outputs
//             .where((f) => f.name.toLowerCase() == flowNameLower)
//             .map((f) => f.amount)
//             .fold(0.0, (prev, amt) => amt);

//         final double deltaAmt = newAmt - oldAmt;
//         if ((deltaAmt).abs() < 1e-9) continue;

//         print(
//           "  [Propagate DOWN] Process \"$currentId\" output.$rawFlow changed: "
//           "$oldAmt → $newAmt (Δ = $deltaAmt)"
//         );

//         final List<String> downstreams =
//             adjacency.consumersByFlow[flowNameLower] ?? [];
//         for (var consId in downstreams) {
//           if (consId == currentId) continue;
//           if (!clonedById.containsKey(consId)) continue;

//           final ProcessNode origCons = adjacency.processById[consId]!; // original consumer
//           final ProcessNode updatedCons = clonedById[consId]!; // in-progress consumer

//           // Find old input amount in the consumer (0 if not present)
//           final double oldIn = origCons.inputs
//               .where((f) => f.name.toLowerCase() == flowNameLower)
//               .map((f) => f.amount)
//               .fold(0.0, (prev, amt) => amt);
//           final double newIn = (oldIn + deltaAmt).clamp(0.0, double.infinity);

//           print(
//             "    → Propagate to CONSUMER \"$consId\": inputs.$rawFlow $oldIn → $newIn"
//           );

//           final ProcessNode recon = applyOverrideToProcess(
//             updatedCons,
//             'inputs.$rawFlow.amount',
//             newIn,
//           );
//           maybeAddNewFlowsToAdjacency(adjacency, recon);

//           clonedById[consId] = recon;
//           if (!seen.contains(consId)) {
//             seen.add(consId);
//             toVisit.add(consId);
//           }
//         }
//       }
//     }

//     // 12) After all propagation, prepare final JSON for this scenario.

//     // 12a) Convert cloned ProcessNode → JSON
//     final List<Map<String, dynamic>> finalProcessesJson = [];
//     for (var p in clonedById.values) {
//       finalProcessesJson.add(p.toJson());
//     }

//     // 12b) The final flows list is whatever we mutated in flowsJson (with renames/adds applied).
//     final List<Map<String, dynamic>> finalFlowsJson = flowsJson;

//     // 12c) Record under "model" for this scenario
//     resultByScenario[scenarioName] = {
//       'model': {
//         'processes': finalProcessesJson,
//         'flows': finalFlowsJson,
//       }
//     };

//     print("=== [mergeScenarios][$scenarioName] Finished scenario ===\n");
//   });

//   // 13) Wrap in a top‐level "scenarios" key and return
//   return {
//     'scenarios': resultByScenario,
//   };
// }


// File: lib/zzzz/scenario_merger.dart

import 'dart:convert';

/// Merges a baseModel (with "processes" and "flows") and a set of “deltas” for each scenario.
/// 
/// - [baseModel] is expected to be a Map like:
///   {
///     "processes": [ <ProcessNode JSON>, … ],
///     "flows":     [ <Flow JSON>, … ]
///   }
///
/// - [deltasByScenario] is a map from scenarioName → list of “change” Maps. Each change Map
///   may be one of:
/// 
///   A) Numeric adjustment:
///      {
///        "process_id": "<existing-process-ID>",
///        "field":      "inputs.<flowName>.amount"   OR  "outputs.<flowName>.amount",
///        "new_value":  <number>
///      }
///
///   B) Rename process:
///      {
///        "process_id": "<existing-process-ID>",
///        "field":      "name",
///        "new_value":  "<new process name>"
///      }
///
///   C) Rename flow:
///      {
///        "flow_id": "<existing-flow-ID>",
///        "field":   "name",
///        "new_value":"<new flow name>"
///      }
///
///   D) Add a new process:
///      {
///        "action": "add_process",
///        "process": { … full ProcessNode JSON … }
///      }
///
///   E) Add a new flow:
///      {
///        "action": "add_flow",
///        "flow":    { … full Flow JSON … }
///      }
///
/// Any unrecognized “action” or missing fields are simply skipped. This function never throws
/// because we check for null at every step.
///
/// Returns a Map<String, dynamic> of the form:
/// {
///   "scenarios": {
///     "<scenarioName>": {
///       "model": {
///         "processes": [ … ],   // deep-copied and modified
///         "flows":     [ … ]    // deep-copied and modified
///       }
///     },
///     …
///   }
/// }
Map<String, dynamic> mergeScenarios(
  Map<String, dynamic> baseModel,
  Map<String, List<Map<String, dynamic>>> deltasByScenario,
) {
  // Prepare the final result
  final Map<String, dynamic> output = {
    'scenarios': <String, dynamic>{},
  };

  for (final kv in deltasByScenario.entries) {
    final scenarioName = kv.key;
    final changes = kv.value;
    print(changes);
    // 1) Deep-copy the baseModel for this scenario
    final Map<String, dynamic> scenarioCopy =
        jsonDecode(jsonEncode(baseModel)) as Map<String, dynamic>;

    final List<dynamic> processes =
        (scenarioCopy['processes'] as List<dynamic>);
    final List<dynamic> flows = (scenarioCopy['flows'] as List<dynamic>);

    // 2) Apply each “change” in order
    for (final change in changes) {
      // 2.A) ADD A NEW PROCESS
      if (change.containsKey('action') && change['action'] == 'add_process') {
        final procJson = change['process'] as Map<String, dynamic>?;
        if (procJson != null) {
          processes.add(jsonDecode(jsonEncode(procJson)));
        }
        continue;
      }

      // 2.B) ADD A NEW FLOW
      if (change.containsKey('action') && change['action'] == 'add_flow') {
        final flowJson = change['flow'] as Map<String, dynamic>?;
        if (flowJson != null) {
          flows.add(jsonDecode(jsonEncode(flowJson)));
        }
        continue;
      }

      // 2.C) RENAME AN EXISTING PROCESS
      if (change.containsKey('process_id') &&
          change.containsKey('field') &&
          change['field'] == 'name' &&
          change.containsKey('new_value')) {
        final pid = change['process_id'] as String;
        final newName = change['new_value'] as String;
        final idx = processes.indexWhere(
            (p) => ((p as Map<String, dynamic>)['id'] as String) == pid);
        if (idx >= 0) {
          final procMap = (processes[idx] as Map<String, dynamic>);
          procMap['name'] = newName;
        }
        continue;
      }

      // 2.D) RENAME AN EXISTING FLOW
      if (change.containsKey('flow_id') &&
          change.containsKey('field') &&
          change['field'] == 'name' &&
          change.containsKey('new_value')) {
        final fid = change['flow_id'] as String;
        final newName = change['new_value'] as String;
        final flowIdx = flows.indexWhere(
            (f) => ((f as Map<String, dynamic>)['id'] as String) == fid);
        if (flowIdx >= 0) {
          final flowMap = (flows[flowIdx] as Map<String, dynamic>);
          final oldName = (flowMap['name'] as String);
          flowMap['name'] = newName;

          // Also update every process’s inputs/outputs if they refer to oldName
          for (final p in processes) {
            final procMap = (p as Map<String, dynamic>);
            final inputsList = (procMap['inputs'] as List<dynamic>);
            for (final inp in inputsList) {
              final inpMap = (inp as Map<String, dynamic>);
              if (inpMap['name'] == oldName) {
                inpMap['name'] = newName;
              }
            }
            final outputsList = (procMap['outputs'] as List<dynamic>);
            for (final outp in outputsList) {
              final outpMap = (outp as Map<String, dynamic>);
              if (outpMap['name'] == oldName) {
                outpMap['name'] = newName;
              }
            }
          }
        }
        continue;
      }

      // 2.E) PROCESS A “numeric adjustment” OR “add new input/output if missing”
      if (change.containsKey('process_id') &&
          change.containsKey('field') &&
          change.containsKey('new_value')) {
        final pid = change['process_id'] as String;
        final field = change['field'] as String;
        final newValue = change['new_value'];
        final idx = processes.indexWhere(
            (p) => ((p as Map<String, dynamic>)['id'] as String) == pid);
        if (idx < 0) {
          // No such process; skip
          continue;
        }
        final procMap = (processes[idx] as Map<String, dynamic>);

        // 2.E.1) If field == "inputs.<flowName>.amount"
        if (field.startsWith('inputs.')) {
          final parts = field.split('.');
          if (parts.length >= 3) {
            final flowName = parts[1]; // e.g. "cap"
            // Find in procMap['inputs']
            final inputsList = (procMap['inputs'] as List<dynamic>);
            final foundIndex = inputsList.indexWhere((i) =>
                ((i as Map<String, dynamic>)['name'] as String) == flowName);
            if (foundIndex >= 0) {
              final inpMap = (inputsList[foundIndex] as Map<String, dynamic>);
              inpMap['amount'] = newValue;
            } else {
              // <flowName> not yet in inputs: create it with default unit "kg"
              inputsList.add({
                'name': flowName,
                'amount': newValue,
                'unit': 'kg',
              });
            }
          }
          continue;
        }

        // 2.E.2) If field == "outputs.<flowName>.amount"
        if (field.startsWith('outputs.')) {
          final parts = field.split('.');
          if (parts.length >= 3) {
            final flowName = parts[1];
            final outputsList = (procMap['outputs'] as List<dynamic>);
            final foundIndex = outputsList.indexWhere((o) =>
                ((o as Map<String, dynamic>)['name'] as String) == flowName);
            if (foundIndex >= 0) {
              final outMap = (outputsList[foundIndex] as Map<String, dynamic>);
              outMap['amount'] = newValue;
            } else {
              // Not yet in outputs: create it with default unit "kg"
              outputsList.add({
                'name': flowName,
                'amount': newValue,
                'unit': 'kg',
              });
            }
          }
          continue;
        }
      }

      // Any other combinations are ignored (we simply skip unknown keys)
    }

    // 3) After applying *all* changes, stash this scenario’s final “model”
    output['scenarios'][scenarioName] = {
      'model': {
        'processes': processes,
        'flows': flows,
      }
    };
  }

  return output;
}
