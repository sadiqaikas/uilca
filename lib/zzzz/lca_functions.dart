// // File: lib/zzzz/lca_functions.dart

// import 'dart:math';

// /// 1) CO₂‐only random perturbation.
// /// Generates `count` scenarios, each with a random ±percentRange% change to every process’s CO₂.
// List<List<Map<String, dynamic>>> randomPerturbation({
//   required Map<String, dynamic> baseModel,
//   required double percentRange,
//   required int count,
// }) {
//   final rng = Random();
//   final processes = (baseModel['processes'] as List).cast<Map<String, dynamic>>();
//   final List<List<Map<String, dynamic>>> allChangeLists = [];

//   for (int i = 0; i < count; i++) {
//     final changeList = <Map<String, dynamic>>[];
//     for (var proc in processes) {
//       final id = proc['id'] as String;
//       final oldCo2 = (proc['co2'] as num).toDouble();
//       final deltaPct = (rng.nextDouble() * 2 - 1) * (percentRange / 100);
//       final newCo2 = double.parse((oldCo2 * (1 + deltaPct)).toStringAsFixed(6));
//       if ((newCo2 - oldCo2).abs() > 1e-9) {
//         changeList.add({
//           'process_id': id,
//           'field': 'co2',
//           'new_value': newCo2,
//         });
//       }
//     }
//     allChangeLists.add(changeList);
//   }

//   return allChangeLists;
// }

// /// 2) CO₂‐only simplex sweep.
// /// For each process, creates two scenarios: +step% and -step% on that process’s CO₂.
// List<List<Map<String, dynamic>>> simplexSweep({
//   required Map<String, dynamic> baseModel,
//   required double step,
// }) {
//   final processes = (baseModel['processes'] as List).cast<Map<String, dynamic>>();
//   final List<List<Map<String, dynamic>>> allChangeLists = [];

//   for (var proc in processes) {
//     final id = proc['id'] as String;
//     final oldCo2 = (proc['co2'] as num).toDouble();

//     // +step%
//     final upCo2 = double.parse((oldCo2 * (1 + step / 100)).toStringAsFixed(6));
//     allChangeLists.add([
//       {
//         'process_id': id,
//         'field': 'co2',
//         'new_value': upCo2,
//       }
//     ]);

//     // -step%
//     final downCo2 = double.parse((oldCo2 * (1 - step / 100)).toStringAsFixed(6));
//     allChangeLists.add([
//       {
//         'process_id': id,
//         'field': 'co2',
//         'new_value': downCo2,
//       }
//     ]);
//   }

//   return allChangeLists;
// }

// /// 3) Random flow variation.
// /// Generates `count` scenarios, each randomly varying any flow (inputs or outputs)
// /// whose name is in [flowNames]. If [flowNames] is empty, vary ALL flows.
// /// Variation is ±percentRange%.
// List<List<Map<String, dynamic>>> randomFlowVariation({
//   required Map<String, dynamic> baseModel,
//   required List<String> flowNames,
//   required double percentRange,
//   required int count,
// }) {
//   final rng = Random();
//   final processes = (baseModel['processes'] as List).cast<Map<String, dynamic>>();
//   final List<List<Map<String, dynamic>>> allChangeLists = [];

//   for (int i = 0; i < count; i++) {
//     final changeList = <Map<String, dynamic>>[];

//     for (var proc in processes) {
//       final pid = proc['id'] as String;

//       // Perturb inputs
//       final inputs = (proc['inputs'] as List<dynamic>).cast<Map<String, dynamic>>();
//       for (var inp in inputs) {
//         final name = inp['name'] as String;
//         if (flowNames.isEmpty || flowNames.contains(name)) {
//           final oldAmt = (inp['amount'] as num).toDouble();
//           final deltaPct = (rng.nextDouble() * 2 - 1) * (percentRange / 100);
//           final newAmt = double.parse((oldAmt * (1 + deltaPct)).toStringAsFixed(6));
//           if ((newAmt - oldAmt).abs() > 1e-9) {
//             changeList.add({
//               'process_id': pid,
//               'field': 'inputs.$name.amount',
//               'new_value': newAmt,
//             });
//           }
//         }
//       }

//       // Perturb outputs
//       final outputs = (proc['outputs'] as List<dynamic>).cast<Map<String, dynamic>>();
//       for (var outp in outputs) {
//         final name = outp['name'] as String;
//         if (flowNames.isEmpty || flowNames.contains(name)) {
//           final oldAmt = (outp['amount'] as num).toDouble();
//           final deltaPct = (rng.nextDouble() * 2 - 1) * (percentRange / 100);
//           final newAmt = double.parse((oldAmt * (1 + deltaPct)).toStringAsFixed(6));
//           if ((newAmt - oldAmt).abs() > 1e-9) {
//             changeList.add({
//               'process_id': pid,
//               'field': 'outputs.$name.amount',
//               'new_value': newAmt,
//             });
//           }
//         }
//       }
//     }

//     allChangeLists.add(changeList);
//   }

//   return allChangeLists;
// }

// /// 4) Simplex flow sweep (pairwise lattice).
// /// For each named flow in [flowNames], creates two single-flow change sets:
// ///   - One scenario where that flow is +step%
// ///   - One scenario where that flow is -step%
// /// Additionally, for each distinct pair of flows (i < j), creates:
// ///   - One scenario where i is +step% and j is -step%
// ///   - One scenario where i is -step% and j is +step%
// /// This yields `2 * n + 2 * (n*(n-1)/2) = 2n + n(n-1) = n^2 + n` scenarios,
// /// where n = flowNames.length. You can expand to higher‐order combinations if desired.
// List<List<Map<String, dynamic>>> simplexFlowSweep({
//   required Map<String, dynamic> baseModel,
//   required List<String> flowNames,
//   required double step,
// }) {
//   final processes = (baseModel['processes'] as List).cast<Map<String, dynamic>>();
//   final List<List<Map<String, dynamic>>> allChangeLists = [];

//   // Helper to build a single-change scenario for (pid, field, newAmt)
//   List<Map<String, dynamic>> _singleChange(String pid, String field, double newAmt) {
//     return [
//       {
//         'process_id': pid,
//         'field': field,
//         'new_value': double.parse(newAmt.toStringAsFixed(6)),
//       }
//     ];
//   }

//   // 1) One‐at‐a‐time: ±step% for each flowName
//   for (var flowName in flowNames) {
//     // +step% on that flow across all processes that have it
//     final plusList = <Map<String, dynamic>>[];
//     // -step% on that flow
//     final minusList = <Map<String, dynamic>>[];

//     for (var proc in processes) {
//       final pid = proc['id'] as String;

//       // Check if that flow exists under inputs
//       for (var inp in (proc['inputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
//         if (inp['name'] == flowName) {
//           final oldAmt = (inp['amount'] as num).toDouble();
//           plusList.addAll(_singleChange(pid, 'inputs.$flowName.amount', oldAmt * (1 + step / 100)));
//           minusList.addAll(_singleChange(pid, 'inputs.$flowName.amount', oldAmt * (1 - step / 100)));
//         }
//       }
//       // Check if that flow exists under outputs
//       for (var outp in (proc['outputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
//         if (outp['name'] == flowName) {
//           final oldAmt = (outp['amount'] as num).toDouble();
//           plusList.addAll(_singleChange(pid, 'outputs.$flowName.amount', oldAmt * (1 + step / 100)));
//           minusList.addAll(_singleChange(pid, 'outputs.$flowName.amount', oldAmt * (1 - step / 100)));
//         }
//       }
//     }

//     if (plusList.isNotEmpty) allChangeLists.add(plusList);
//     if (minusList.isNotEmpty) allChangeLists.add(minusList);
//   }

//   // 2) Pairwise: for each pair (i, j), do (i:+step, j:-step) and (i:-step, j:+step)
//   for (int i = 0; i < flowNames.length; i++) {
//     for (int j = i + 1; j < flowNames.length; j++) {
//       final fnameI = flowNames[i];
//       final fnameJ = flowNames[j];

//       final combo1 = <Map<String, dynamic>>[]; // i:+step, j:-step
//       final combo2 = <Map<String, dynamic>>[]; // i:-step, j:+step

//       for (var proc in processes) {
//         final pid = proc['id'] as String;

//         // If proc has input i?
//         for (var inp in (proc['inputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
//           if (inp['name'] == fnameI) {
//             final oldAmt = (inp['amount'] as num).toDouble();
//             combo1.addAll(_singleChange(pid, 'inputs.$fnameI.amount', oldAmt * (1 + step / 100)));
//             combo2.addAll(_singleChange(pid, 'inputs.$fnameI.amount', oldAmt * (1 - step / 100)));
//           }
//           if (inp['name'] == fnameJ) {
//             final oldAmt = (inp['amount'] as num).toDouble();
//             combo1.addAll(_singleChange(pid, 'inputs.$fnameJ.amount', oldAmt * (1 - step / 100)));
//             combo2.addAll(_singleChange(pid, 'inputs.$fnameJ.amount', oldAmt * (1 + step / 100)));
//           }
//         }

//         // If proc has output i?
//         for (var outp in (proc['outputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
//           if (outp['name'] == fnameI) {
//             final oldAmt = (outp['amount'] as num).toDouble();
//             combo1.addAll(_singleChange(pid, 'outputs.$fnameI.amount', oldAmt * (1 + step / 100)));
//             combo2.addAll(_singleChange(pid, 'outputs.$fnameI.amount', oldAmt * (1 - step / 100)));
//           }
//           if (outp['name'] == fnameJ) {
//             final oldAmt = (outp['amount'] as num).toDouble();
//             combo1.addAll(_singleChange(pid, 'outputs.$fnameJ.amount', oldAmt * (1 - step / 100)));
//             combo2.addAll(_singleChange(pid, 'outputs.$fnameJ.amount', oldAmt * (1 + step / 100)));
//           }
//         }
//       }

//       if (combo1.isNotEmpty) allChangeLists.add(combo1);
//       if (combo2.isNotEmpty) allChangeLists.add(combo2);
//     }
//   }

//   return allChangeLists;
// }

// /// “Safe” wrapper around randomFlowVariation:
// List<List<Map<String, dynamic>>> safeRandomFlowVariation({
//   required Map<String, dynamic> baseModel,
//   required List<String> flowNames,
//   required double percentRange,
//   required int count,
// }) {
//   // Identify shared flows (in both inputs and outputs)
//   final sharedFlows = <String>{};
//   final seenInputs = <String>{};
//   final seenOutputs = <String>{};

//   for (var proc in (baseModel['processes'] as List).cast<Map<String, dynamic>>()) {
//     for (var inp in (proc['inputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
//       seenInputs.add(inp['name'] as String);
//     }
//     for (var outp in (proc['outputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
//       seenOutputs.add(outp['name'] as String);
//     }
//   }
//   for (var name in seenInputs) {
//     if (seenOutputs.contains(name)) sharedFlows.add(name);
//   }

//   // Call the original randomFlowVariation:
//   final raw = randomFlowVariation(
//     baseModel: baseModel,
//     flowNames: flowNames,
//     percentRange: percentRange,
//     count: count,
//   );

//   // Filter out any “inputs.<shared>.amount” changes:
//   return raw.map((changeList) {
//     return changeList.where((change) {
//       final field = change['field'] as String;
//       for (var shared in sharedFlows) {
//         if (field == 'inputs.$shared.amount') {
//           return false;
//         }
//       }
//       return true;
//     }).toList();
//   }).toList();
// }

// File: lib/zzzz/lca_functions.dart

// import 'dart:math';

// /// 1) CO₂‐only random perturbation (unchanged).
// List<List<Map<String, dynamic>>> randomPerturbation({
//   required Map<String, dynamic> baseModel,
//   required double percentRange,
//   required int count,
// }) {
//   final rng = Random();
//   final processes = (baseModel['processes'] as List).cast<Map<String, dynamic>>();
//   final List<List<Map<String, dynamic>>> allChangeLists = [];

//   for (int i = 0; i < count; i++) {
//     final changeList = <Map<String, dynamic>>[];
//     for (var proc in processes) {
//       final id = proc['id'] as String;
//       final oldCo2 = (proc['co2'] as num).toDouble();
//       final deltaPct = (rng.nextDouble() * 2 - 1) * (percentRange / 100);
//       final newCo2 = double.parse((oldCo2 * (1 + deltaPct)).toStringAsFixed(6));
//       if ((newCo2 - oldCo2).abs() > 1e-9) {
//         changeList.add({
//           'process_id': id,
//           'field': 'co2',
//           'new_value': newCo2,
//         });
//       }
//     }
//     allChangeLists.add(changeList);
//   }
//   return allChangeLists;
// }

// /// 2) CO₂‐only simplex sweep (unchanged).
// List<List<Map<String, dynamic>>> simplexSweep({
//   required Map<String, dynamic> baseModel,
//   required double step,
// }) {
//   final processes = (baseModel['processes'] as List).cast<Map<String, dynamic>>();
//   final List<List<Map<String, dynamic>>> allChangeLists = [];

//   for (var proc in processes) {
//     final id = proc['id'] as String;
//     final oldCo2 = (proc['co2'] as num).toDouble();

//     // +step%
//     final upCo2 = double.parse((oldCo2 * (1 + step / 100)).toStringAsFixed(6));
//     allChangeLists.add([
//       {
//         'process_id': id,
//         'field': 'co2',
//         'new_value': upCo2,
//       }
//     ]);

//     // -step%
//     final downCo2 = double.parse((oldCo2 * (1 - step / 100)).toStringAsFixed(6));
//     allChangeLists.add([
//       {
//         'process_id': id,
//         'field': 'co2',
//         'new_value': downCo2,
//       }
//     ]);
//   }

//   return allChangeLists;
// }

// /// 3a) Original randomFlowVariation (unchanged).
// List<List<Map<String, dynamic>>> randomFlowVariation({
//   required Map<String, dynamic> baseModel,
//   required List<String> flowNames,
//   required double percentRange,
//   required int count,
// }) {
//   final rng = Random();
//   final processes = (baseModel['processes'] as List).cast<Map<String, dynamic>>();
//   final List<List<Map<String, dynamic>>> allChangeLists = [];

//   for (int i = 0; i < count; i++) {
//     final changeList = <Map<String, dynamic>>[];

//     for (var proc in processes) {
//       final pid = proc['id'] as String;

//       // Perturb inputs
//       final inputs = (proc['inputs'] as List<dynamic>).cast<Map<String, dynamic>>();
//       for (var inp in inputs) {
//         final name = inp['name'] as String;
//         if (flowNames.isEmpty || flowNames.contains(name)) {
//           final oldAmt = (inp['amount'] as num).toDouble();
//           final deltaPct = (rng.nextDouble() * 2 - 1) * (percentRange / 100);
//           final newAmt = double.parse((oldAmt * (1 + deltaPct)).toStringAsFixed(6));
//           if ((newAmt - oldAmt).abs() > 1e-9) {
//             changeList.add({
//               'process_id': pid,
//               'field': 'inputs.$name.amount',
//               'new_value': newAmt,
//             });
//           }
//         }
//       }

//       // Perturb outputs
//       final outputs = (proc['outputs'] as List<dynamic>).cast<Map<String, dynamic>>();
//       for (var outp in outputs) {
//         final name = outp['name'] as String;
//         if (flowNames.isEmpty || flowNames.contains(name)) {
//           final oldAmt = (outp['amount'] as num).toDouble();
//           final deltaPct = (rng.nextDouble() * 2 - 1) * (percentRange / 100);
//           final newAmt = double.parse((oldAmt * (1 + deltaPct)).toStringAsFixed(6));
//           if ((newAmt - oldAmt).abs() > 1e-9) {
//             changeList.add({
//               'process_id': pid,
//               'field': 'outputs.$name.amount',
//               'new_value': newAmt,
//             });
//           }
//         }
//       }
//     }
//     allChangeLists.add(changeList);
//   }
//   return allChangeLists;
// }

// /// 3b) “Producer‐only” wrapper:
// /// Strips any “inputs.<shared>.amount” changes, keeping only “outputs.<shared>.amount” for shared flows.
// List<List<Map<String, dynamic>>> safeRandomFlowVariationProducer({
//   required Map<String, dynamic> baseModel,
//   required List<String> flowNames,
//   required double percentRange,
//   required int count,
// }) {
//   // Step A: find shared flows
//   final sharedFlows = <String>{};
//   final seenInputs = <String>{};
//   final seenOutputs = <String>{};

//   for (var proc in (baseModel['processes'] as List).cast<Map<String, dynamic>>()) {
//     for (var inp in (proc['inputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
//       seenInputs.add(inp['name'] as String);
//     }
//     for (var outp in (proc['outputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
//       seenOutputs.add(outp['name'] as String);
//     }
//   }
//   for (var name in seenInputs) {
//     if (seenOutputs.contains(name)) {
//       sharedFlows.add(name);
//     }
//   }

//   // Step B: call original randomFlowVariation
//   final raw = randomFlowVariation(
//     baseModel: baseModel,
//     flowNames: flowNames,
//     percentRange: percentRange,
//     count: count,
//   );

//   // Step C: drop “inputs.<shared>.amount”—keep only “outputs.<shared>.amount”
//   return raw.map((changeList) {
//     return changeList.where((change) {
//       final field = change['field'] as String;
//       for (var shared in sharedFlows) {
//         if (field == 'inputs.$shared.amount') {
//           return false;
//         }
//       }
//       return true;
//     }).toList();
//   }).toList();
// }

// /// 3c) “Consumer‐only” wrapper:
// /// Strips any “outputs.<shared>.amount” changes, keeping only “inputs.<shared>.amount” for shared flows.
// List<List<Map<String, dynamic>>> safeRandomFlowVariationConsumer({
//   required Map<String, dynamic> baseModel,
//   required List<String> flowNames,
//   required double percentRange,
//   required int count,
// }) {
//   // Step A: find shared flows
//   final sharedFlows = <String>{};
//   final seenInputs = <String>{};
//   final seenOutputs = <String>{};

//   for (var proc in (baseModel['processes'] as List).cast<Map<String, dynamic>>()) {
//     for (var inp in (proc['inputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
//       seenInputs.add(inp['name'] as String);
//     }
//     for (var outp in (proc['outputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
//       seenOutputs.add(outp['name'] as String);
//     }
//   }
//   for (var name in seenInputs) {
//     if (seenOutputs.contains(name)) {
//       sharedFlows.add(name);
//     }
//   }

//   // Step B: call original randomFlowVariation
//   final raw = randomFlowVariation(
//     baseModel: baseModel,
//     flowNames: flowNames,
//     percentRange: percentRange,
//     count: count,
//   );

//   // Step C: drop “outputs.<shared>.amount”—keep only “inputs.<shared>.amount”
//   return raw.map((changeList) {
//     return changeList.where((change) {
//       final field = change['field'] as String;
//       for (var shared in sharedFlows) {
//         if (field == 'outputs.$shared.amount') {
//           return false;
//         }
//       }
//       return true;
//     }).toList();
//   }).toList();
// }

// /// 4) Simplex flow sweep (unchanged).
// List<List<Map<String, dynamic>>> simplexFlowSweep({
//   required Map<String, dynamic> baseModel,
//   required List<String> flowNames,
//   required double step,
// }) {
//   final processes = (baseModel['processes'] as List).cast<Map<String, dynamic>>();
//   final List<List<Map<String, dynamic>>> allChangeLists = [];

//   List<Map<String, dynamic>> _singleChange(
//       String pid, String field, double newAmt) {
//     return [
//       {
//         'process_id': pid,
//         'field': field,
//         'new_value': double.parse(newAmt.toStringAsFixed(6)),
//       }
//     ];
//   }

//   // One‐at‐a‐time ±step%
//   for (var flowName in flowNames) {
//     final plusList = <Map<String, dynamic>>[];
//     final minusList = <Map<String, dynamic>>[];

//     for (var proc in processes) {
//       final pid = proc['id'] as String;
//       for (var inp in (proc['inputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
//         if (inp['name'] == flowName) {
//           final oldAmt = (inp['amount'] as num).toDouble();
//           plusList.addAll(
//               _singleChange(pid, 'inputs.$flowName.amount', oldAmt * (1 + step / 100)));
//           minusList.addAll(
//               _singleChange(pid, 'inputs.$flowName.amount', oldAmt * (1 - step / 100)));
//         }
//       }
//       for (var outp in (proc['outputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
//         if (outp['name'] == flowName) {
//           final oldAmt = (outp['amount'] as num).toDouble();
//           plusList.addAll(
//               _singleChange(pid, 'outputs.$flowName.amount', oldAmt * (1 + step / 100)));
//           minusList.addAll(
//               _singleChange(pid, 'outputs.$flowName.amount', oldAmt * (1 - step / 100)));
//         }
//       }
//     }

//     if (plusList.isNotEmpty) allChangeLists.add(plusList);
//     if (minusList.isNotEmpty) allChangeLists.add(minusList);
//   }

//   // Pairwise ±step% on (i, j)
//   for (int i = 0; i < flowNames.length; i++) {
//     for (int j = i + 1; j < flowNames.length; j++) {
//       final fnameI = flowNames[i];
//       final fnameJ = flowNames[j];

//       final combo1 = <Map<String, dynamic>>[]; // i:+step, j:-step
//       final combo2 = <Map<String, dynamic>>[]; // i:-step, j:+step

//       for (var proc in processes) {
//         final pid = proc['id'] as String;
//         for (var inp in (proc['inputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
//           if (inp['name'] == fnameI) {
//             final oldAmt = (inp['amount'] as num).toDouble();
//             combo1.addAll(
//                 _singleChange(pid, 'inputs.$fnameI.amount', oldAmt * (1 + step / 100)));
//             combo2.addAll(
//                 _singleChange(pid, 'inputs.$fnameI.amount', oldAmt * (1 - step / 100)));
//           }
//           if (inp['name'] == fnameJ) {
//             final oldAmt = (inp['amount'] as num).toDouble();
//             combo1.addAll(
//                 _singleChange(pid, 'inputs.$fnameJ.amount', oldAmt * (1 - step / 100)));
//             combo2.addAll(
//                 _singleChange(pid, 'inputs.$fnameJ.amount', oldAmt * (1 + step / 100)));
//           }
//         }
//         for (var outp in (proc['outputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
//           if (outp['name'] == fnameI) {
//             final oldAmt = (outp['amount'] as num).toDouble();
//             combo1.addAll(
//                 _singleChange(pid, 'outputs.$fnameI.amount', oldAmt * (1 + step / 100)));
//             combo2.addAll(
//                 _singleChange(pid, 'outputs.$fnameI.amount', oldAmt * (1 - step / 100)));
//           }
//           if (outp['name'] == fnameJ) {
//             final oldAmt = (outp['amount'] as num).toDouble();
//             combo1.addAll(
//                 _singleChange(pid, 'outputs.$fnameJ.amount', oldAmt * (1 - step / 100)));
//             combo2.addAll(
//                 _singleChange(pid, 'outputs.$fnameJ.amount', oldAmt * (1 + step / 100)));
//           }
//         }
//       }

//       if (combo1.isNotEmpty) allChangeLists.add(combo1);
//       if (combo2.isNotEmpty) allChangeLists.add(combo2);
//     }
//   }

//   return allChangeLists;
// }


// File: lib/lca_functions.dart

import 'dart:math';

/// -------------------------------------------------------------------------------------------------
/// 1) One-Factor-at-a-Time Sensitivity (OFAT)
///
/// For each flow in `flowNames`, generate scenarios that vary that flow by ±percent (or by each
/// level in `levels`), while leaving every other flow at its baseline. Returns a list of “change
/// lists,” where each change list is a `List<Map<String, dynamic>>` of overrides:
///   { 'process_id': 'P', 'field': 'inputs.<flow>.amount' or 'outputs.<flow>.amount', 'new_value': <number> }.
/// -------------------------------------------------------------------------------------------------
List<List<Map<String, dynamic>>> oneAtATimeSensitivity({
  required Map<String, dynamic> baseModel,
  required List<String> flowNames,
  double percent = 10.0,
  List<double>? levels,
}) {
  final processes = (baseModel['processes'] as List).cast<Map<String, dynamic>>();
  final List<List<Map<String, dynamic>>> allChangeLists = [];

  // If no custom levels provided, default to [−percent, +percent]
  final List<double> sweepLevels = levels ?? [-percent, percent];

  for (var flow in flowNames) {
    for (var lvl in sweepLevels) {
      final double deltaPct = lvl / 100.0;
      final List<Map<String, dynamic>> changeList = [];

      for (var proc in processes) {
        final String pid = proc['id'] as String;

        // — Perturb inputs matching `flow` —
        for (var inp in (proc['inputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
          if (inp['name'] == flow) {
            final double oldAmt = (inp['amount'] as num).toDouble();
            final double newAmt = double.parse((oldAmt * (1 + deltaPct)).toStringAsFixed(6));
            changeList.add({
              'process_id': pid,
              'field': 'inputs.$flow.amount',
              'new_value': newAmt,
            });
          }
        }

        // — Perturb outputs matching `flow` —
        for (var outp in (proc['outputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
          if (outp['name'] == flow) {
            final double oldAmt = (outp['amount'] as num).toDouble();
            final double newAmt = double.parse((oldAmt * (1 + deltaPct)).toStringAsFixed(6));
            changeList.add({
              'process_id': pid,
              'field': 'outputs.$flow.amount',
              'new_value': newAmt,
            });
          }
        }
      }

      allChangeLists.add(changeList);
    }
  }

  return allChangeLists;
}

/// -------------------------------------------------------------------------------------------------
/// 2) Full-System ± X % Uncertainty Sweep
///
/// Scale **all** input and output flows in **every** process by ±percent (or by each level in
/// `levels`). Returns two (or more) change lists:
///   • One where every flow amount = old × (1 + percent/100)
///   • One where every flow amount = old × (1 − percent/100)
/// If you supply `levels: [−10, 0, +10]`, you’ll get three change lists, etc.
/// -------------------------------------------------------------------------------------------------
List<List<Map<String, dynamic>>> fullSystemUncertainty({
  required Map<String, dynamic> baseModel,
  double percent = 10.0,
  List<double>? levels,
}) {
  final processes = (baseModel['processes'] as List).cast<Map<String, dynamic>>();
  final List<List<Map<String, dynamic>>> allChangeLists = [];

  // Default to [−percent, +percent] if no custom levels
  final List<double> sweepLevels = levels ?? [-percent, percent];

  for (var lvl in sweepLevels) {
    final double deltaPct = lvl / 100.0;
    final List<Map<String, dynamic>> changeList = [];

    for (var proc in processes) {
      final String pid = proc['id'] as String;

      // — Scale every input by (1 + deltaPct) —
      for (var inp in (proc['inputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final String name = inp['name'] as String;
        final double oldAmt = (inp['amount'] as num).toDouble();
        final double newAmt = double.parse((oldAmt * (1 + deltaPct)).toStringAsFixed(6));
        changeList.add({
          'process_id': pid,
          'field': 'inputs.$name.amount',
          'new_value': newAmt,
        });
      }

      // — Scale every output by (1 + deltaPct) —
      for (var outp in (proc['outputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final String name = outp['name'] as String;
        final double oldAmt = (outp['amount'] as num).toDouble();
        final double newAmt = double.parse((oldAmt * (1 + deltaPct)).toStringAsFixed(6));
        changeList.add({
          'process_id': pid,
          'field': 'outputs.$name.amount',
          'new_value': newAmt,
        });
      }
    }

    allChangeLists.add(changeList);
  }

  return allChangeLists;
}
// File: lib/lca_functions.dart  (add or replace the old simplexLatticeDesign)

/// -------------------------------------------------------------------------------------------------
/// Corrected Simplex-Lattice Mixture Design
///
/// Steps:
/// 1) For each flow in flowNames, sum its baseline amount across ALL processes → globalBaseline[flow].
/// 2) Compute totalGlobalBaseline = sum(globalBaseline.values).
/// 3) Build all integer combinations [c0, c1, …, c_{q-1}] such that sum(ci) = m (q = flowNames.length).
///    For each combination:
///      - New global amount for flow_i = totalGlobalBaseline × (ci / m).
///      - For each process, if it originally had amount oldProcAmt for that flow:
///          newProcAmt = oldProcAmt × (newGlobalAmt / oldGlobalAmt)  (if oldGlobalAmt > 0).
///      - Emit one change entry per process‐flow where oldGlobalAmt > 0.
///
/// Returns a List of change‐lists, one per scenario.
///
/// Example: {q=2 (diesel, gas), m=3} → integer combos: [0,3], [1,2], [2,1], [3,0].
///    totalGlobalBaseline = diesel_sum + gas_sum.
///    Scenario “diesel_0/3__gas_3/3”: newGlobalDiesel=0, newGlobalGas=totalBase.
///    Then each process’s newProcGas = oldProcGas × (totalBase / oldGlobalGas), etc.
/// -------------------------------------------------------------------------------------------------
List<List<Map<String, dynamic>>> simplexLatticeDesign({
  required Map<String, dynamic> baseModel,
  required List<String> flowNames,
  required int m,
}) {
  final processes = (baseModel['processes'] as List).cast<Map<String, dynamic>>();
  final int q = flowNames.length;

  // 1) Compute global baseline per flow_name
  final Map<String,double> globalBaseline = { for (var f in flowNames) f: 0.0 };
  final List<Map<String,double>> processBaselines = [];

  for (var proc in processes) {
    final Map<String,double> procMap = {};
    for (var inp in (proc['inputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final name = inp['name'] as String;
      if (flowNames.contains(name)) {
        final amt = (inp['amount'] as num).toDouble();
        procMap[name] = amt;
        globalBaseline[name] = globalBaseline[name]! + amt;
      }
    }
    processBaselines.add(procMap);
  }

  final double totalGlobalBaseline = globalBaseline.values.fold(0.0, (a, b) => a + b);
  if (totalGlobalBaseline <= 0.0) {
    // Nothing to mix if all baselines are zero or missing
    return [];
  }

  // 2) Build all integer combinations [c0, c1, ... c_{q-1}] such that sum(ci)=m
  final List<List<int>> integerCombinations = [];
  void _buildCombo(List<int> current, int idx, int remaining) {
    if (idx == q - 1) {
      current[idx] = remaining;
      integerCombinations.add(List<int>.from(current));
      return;
    }
    for (int i = 0; i <= remaining; i++) {
      current[idx] = i;
      _buildCombo(current, idx + 1, remaining - i);
    }
  }
  _buildCombo(List<int>.filled(q, 0), 0, m);

  // 3) For each combination, compute new global amounts and redistribute to each process
  final List<List<Map<String, dynamic>>> allScenarios = [];

  for (var combo in integerCombinations) {
    // newGlobal[flowNames[k]] = totalGlobalBaseline * (combo[k]/m)
    final Map<String,double> newGlobal = {
      for (int k = 0; k < q; k++)
        flowNames[k]: totalGlobalBaseline * (combo[k] / m)
    };

    // Build the change list for this scenario
    final List<Map<String, dynamic>> changeList = [];

    for (int p = 0; p < processes.length; p++) {
      final proc = processes[p];
      final pid = proc['id'] as String;
      final procMap = processBaselines[p];

      for (int k = 0; k < q; k++) {
        final String flow = flowNames[k];
        final double oldGlobalAmt = globalBaseline[flow]!;
        final double oldProcAmt = procMap[flow] ?? 0.0;
        if (oldGlobalAmt > 0 && oldProcAmt > 0) {
          final double proportion = newGlobal[flow]! / oldGlobalAmt;
          final double newProcAmt = double.parse((oldProcAmt * proportion).toStringAsFixed(6));
          changeList.add({
            'process_id': pid,
            'field': 'inputs.$flow.amount',
            'new_value': newProcAmt,
          });
        }
      }
    }

    // Assemble a scenario name, e.g. "diesel_1/3__gas_2/3"
    final String scenarioName = List<String>.generate(q, (k) {
      return '${flowNames[k]}_${combo[k]}/$m';
    }).join('__');

    allScenarios.add(changeList);
  }

  return allScenarios;
}
