import 'dart:convert';
import '../newhome/lca_models.dart';

/// Merge parameter-only deltas into a base LCA model.
///
/// Rules:
///  - Only parameters (global/process) + number_functional_units can be changed.
///  - Parameters are applied first (formulas cleared when an explicit numeric value is set).
///  - Inputs/outputs are re-evaluated with ParameterEngine using the updated ParameterSet.
///  - Emissions scale by reference-output ratio (first output: new/old).
///  - Warnings are collected (no silent zeroing) and returned per-scenario.
///
/// Model parameter placement supported:
///   a) model['parameters'] = { 'global_parameters': [...], 'process_parameters': {...} }
///   b) top-level 'global_parameters' / 'process_parameters'  (back-compat)
///
/// Deltas: { "ScenarioName": [ { "field":.., "new_value":.., ["process_id": ".."] }, ... ] }
///   Accepted fields:
///     - "parameters.global.<Name>"
///     - "parameters.process.<Name>"  (+ "process_id")
///     - "parameters.process:<pid>.<Name>"   // legacy
///     - "number_functional_units"
///
/// Returns:
///   {
///     "scenarios": {
///       "<scenario>": {
///         "model": { ... },            // processes, flows, parameters written back
///         "parameters": { ... },       // ParameterSet JSON
///         "merge_warnings": [ ... ]    // strings
///       }, ...
///     }
///   }
Map<String, dynamic> mergeScenarios(
  Map<String, dynamic> baseModel,
  Map<String, List<Map<String, dynamic>>> deltasByScenario,
) {
  final out = <String, dynamic>{};

  // Snapshot baseline reference outputs (first output) once.
  final baseSnapshot =
      jsonDecode(jsonEncode(baseModel)) as Map<String, dynamic>;
  final baselineRefOut = <String, double>{};
  for (final pJson in (baseSnapshot['processes'] as List)) {
    final p = ProcessNode.fromJson((pJson as Map).cast<String, dynamic>());
    baselineRefOut[p.id] = p.outputs.isNotEmpty ? p.outputs.first.amount : 0.0;
  }

  for (final entry in deltasByScenario.entries) {
    final scenarioName = entry.key;
    final deltas = entry.value;
    final warnings = <String>[];

    // Fresh copy of the full model for this scenario
    final model = jsonDecode(jsonEncode(baseModel)) as Map<String, dynamic>;

    // --- 1) Read parameters (nested or top-level)
    final read = _readParameterSetFromModel(model);

    // --- 2) Apply deltas → new ParameterSet (+ FU override)
    double? fuOverride;
    final paramSet = _applyParameterDeltas(
      read.paramSet,
      deltas,
      onFunctionalUnits: (v) => fuOverride = v,
      onWarning: (w) => warnings.add(w),
    );

    if (fuOverride != null) {
      model['number_functional_units'] = fuOverride;
    }

    // --- 3) Re-evaluate inputs/outputs with the updated parameters
    final engine = ParameterEngine();
    final processes = (model['processes'] as List)
        .map((m) => ProcessNode.fromJson((m as Map).cast<String, dynamic>()))
        .toList();

    ProcessNode resolveNode(ProcessNode node) {
      final symbols = _safeEvalSymbols(paramSet, node.id, warnings);
      List<FlowValue> resolveList(List<FlowValue> list) {
        return list.map((f) {
          try {
            return evaluateFlowAmount(f, symbols, engine: engine);
          } catch (e) {
            warnings.add(
              "Failed to evaluate flow '${f.name}' in process '${node.name}' (${node.id}): $e",
            );
            // Keep original numeric amount if present; otherwise set to 0 to remain defined.
            return f.copyWith(amount: f.amount);
          }
        }).toList();
      }

      return node.copyWithFields(
        inputs: resolveList(node.inputs),
        outputs: resolveList(node.outputs),
        // emissions handled in step 4 by scaling only
      );
    }

    final reEvaluated = processes.map(resolveNode).toList();

    // --- 4) Scale emissions by reference output ratio
    final scaled = <ProcessNode>[];
    for (final n in reEvaluated) {
      final oldRef = baselineRefOut[n.id] ?? 0.0;
      final newRef = n.outputs.isNotEmpty ? n.outputs.first.amount : oldRef;

      if (n.emissions.isEmpty || oldRef <= 0 || newRef <= 0) {
        if (n.emissions.isNotEmpty && oldRef <= 0) {
          warnings.add(
              "Cannot scale emissions for process '${n.name}' (${n.id}): baseline reference output is 0.");
        }
        scaled.add(n);
        continue;
      }

      final ratio = newRef / oldRef;
      final newEm =
          n.emissions.map((e) => e.copyWith(amount: e.amount * ratio)).toList();
      scaled.add(n.copyWithFields(emissions: newEm));
    }

    // --- 5) Write processes + parameters back
    model['processes'] = scaled.map((p) => p.toJson()).toList();
    final paramJson = paramSet.toJson();

    if (read.usedNestedContainer) {
      model['parameters'] ??= <String, dynamic>{};
      final params = (model['parameters'] as Map).cast<String, dynamic>();
      if (paramJson['global_parameters'] != null) {
        params['global_parameters'] = paramJson['global_parameters'];
      }
      if (paramJson['process_parameters'] != null) {
        params['process_parameters'] = paramJson['process_parameters'];
      }
    } else {
      if (paramJson['global_parameters'] != null) {
        model['global_parameters'] = paramJson['global_parameters'];
      }
      if (paramJson['process_parameters'] != null) {
        model['process_parameters'] = paramJson['process_parameters'];
      }
    }

    out[scenarioName] = {
      'model': model,
      'parameters': paramJson,
      if (warnings.isNotEmpty) 'merge_warnings': warnings,
    };
  }

  return {'scenarios': out};
}

/// --- helpers ----------------------------------------------------------------

class _ReadParams {
  final ParameterSet paramSet;
  final bool usedNestedContainer;
  _ReadParams(this.paramSet, this.usedNestedContainer);
}

_ReadParams _readParameterSetFromModel(Map<String, dynamic> model) {
  // Preferred nested block
  final params = model['parameters'];
  if (params is Map) {
    final m = params.cast<String, dynamic>();
    final gp = m['global_parameters'];
    final pp = m['process_parameters'];
    if (gp is List || pp is Map) {
      return _ReadParams(
        ParameterSet.fromJson({
          if (gp is List) 'global_parameters': gp,
          if (pp is Map) 'process_parameters': pp,
        }.cast<String, dynamic>()),
        true,
      );
    }
  }

  // Top-level (back-compat)
  final gpTop = model['global_parameters'];
  final ppTop = model['process_parameters'];
  if (gpTop is List || ppTop is Map) {
    return _ReadParams(
      ParameterSet.fromJson({
        if (gpTop is List) 'global_parameters': gpTop,
        if (ppTop is Map) 'process_parameters': ppTop,
      }.cast<String, dynamic>()),
      false,
    );
  }

  // Fallback: inline per-process parameters
  final perProc = <String, List<Parameter>>{};
  for (final pJson in (model['processes'] as List)) {
    final m = (pJson as Map).cast<String, dynamic>();
    final pid = m['id'] as String;
    final paramsList =
        (m['parameters'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final parsed = paramsList.map(Parameter.fromJson).toList();
    if (parsed.isNotEmpty) perProc[pid] = parsed;
  }
  return _ReadParams(ParameterSet(global: const [], perProcess: perProc), true);
}

Map<String, double> _safeEvalSymbols(
  ParameterSet paramSet,
  String processId,
  List<String> warnings,
) {
  try {
    return paramSet.evaluateSymbolsForProcess(processId);
  } catch (e) {
    warnings.add("Failed to evaluate symbols for process '$processId': $e");
    return const <String, double>{};
  }
}

/// Apply deltas to a ParameterSet, return a new set.
/// Accepts:
///  - Global: field 'parameters.global.<Name>'
///  - Process: field 'parameters.process.<Name>' with a separate 'process_id'
///  - Legacy process: field 'parameters.process:<pid>.<Name>' with embedded pid
///  - Functional units: field 'number_functional_units'
ParameterSet _applyParameterDeltas(
  ParameterSet base,
  List<Map<String, dynamic>> deltas, {
  void Function(double value)? onFunctionalUnits,
  void Function(String warning)? onWarning,
}) {
  final globals = {for (final p in base.global) p.name.toLowerCase(): p};
  final perProc = <String, Map<String, Parameter>>{
    for (final e in base.perProcess.entries)
      e.key: {for (final p in e.value) p.name.toLowerCase(): p}
  };
  final globallyChangedNames = <String>{};
  for (final d in deltas) {
    final field = (d['field'] ?? '').toString();
    if (!field.startsWith('parameters.global.')) continue;
    final nameKey =
        field.substring('parameters.global.'.length).trim().toLowerCase();
    if (nameKey.isNotEmpty) globallyChangedNames.add(nameKey);
  }

  String? resolveProcessId(String raw) {
    final pid = raw.trim();
    if (pid.isEmpty) return null;
    if (perProc.containsKey(pid)) return pid;
    final needle = pid.toLowerCase();
    for (final key in perProc.keys) {
      if (key.toLowerCase() == needle) return key;
    }
    return null;
  }

  for (final d in deltas) {
    final field = (d['field'] ?? '').toString();
    final newVal = d['new_value'];

    if (field == 'number_functional_units') {
      final parsed = _toDoubleMaybe(newVal);
      if (parsed != null) {
        onFunctionalUnits?.call(parsed);
      } else {
        onWarning?.call(
            "number_functional_units expects a number; got '$newVal'. Ignored.");
      }
      continue;
    }

    if (field.startsWith('parameters.global.')) {
      final name = field.substring('parameters.global.'.length);
      final key = name.trim().toLowerCase();
      final p = globals[key];
      if (p == null) {
        onWarning?.call("Unknown global parameter '$name'. Ignored.");
        continue;
      }
      final parsed = _toDoubleMaybe(newVal);
      if (parsed != null) {
        globals[key] = p.copyWith(value: parsed, formula: null);
      } else {
        onWarning?.call(
            "Global parameter '$name' expects numeric 'new_value'; got '$newVal'. Ignored.");
      }
      continue;
    }

    if (field.startsWith('parameters.process.')) {
      // New shape requires 'process_id'
      final pid = (d['process_id'] ?? '').toString();
      if (pid.isEmpty) {
        onWarning?.call(
            "Process parameter delta '$field' missing 'process_id'. Ignored.");
        continue;
      }
      final resolvedPid = resolveProcessId(pid);
      if (resolvedPid == null) {
        onWarning
            ?.call("Unknown process id '$pid' for delta '$field'. Ignored.");
        continue;
      }
      final name = field.substring('parameters.process.'.length);
      final nameKey = name.trim().toLowerCase();
      if (globallyChangedNames.contains(nameKey)) {
        onWarning?.call(
            "Skipped process parameter '$name' for process '$resolvedPid' because the same name is changed globally in this scenario.");
        continue;
      }
      final p = perProc[resolvedPid]?[nameKey];
      if (p == null) {
        onWarning?.call(
            "Unknown process parameter '$name' for process '$resolvedPid'. Ignored.");
        continue;
      }
      final parsed = _toDoubleMaybe(newVal);
      if (parsed != null) {
        perProc[resolvedPid]![nameKey] =
            p.copyWith(value: parsed, formula: null);
      } else {
        onWarning?.call(
            "Process parameter '$name' for process '$resolvedPid' expects numeric 'new_value'; got '$newVal'. Ignored.");
      }
      continue;
    }

    if (field.startsWith('parameters.process:')) {
      // Legacy embedded pid: 'parameters.process:<pid>.<name>'
      final rest = field.substring('parameters.process:'.length);
      final dot = rest.indexOf('.');
      if (dot <= 0) {
        onWarning?.call(
            "Malformed legacy process parameter field '$field'. Ignored.");
        continue;
      }
      final pid = rest.substring(0, dot);
      final name = rest.substring(dot + 1);
      final resolvedPid = resolveProcessId(pid);
      if (resolvedPid == null) {
        onWarning
            ?.call("Unknown process id '$pid' for delta '$field'. Ignored.");
        continue;
      }
      final nameKey = name.trim().toLowerCase();
      if (globallyChangedNames.contains(nameKey)) {
        onWarning?.call(
            "Skipped process parameter '$name' for process '$resolvedPid' because the same name is changed globally in this scenario.");
        continue;
      }
      final p = perProc[resolvedPid]?[nameKey];
      if (p == null) {
        onWarning?.call(
            "Unknown process parameter '$name' for process '$resolvedPid'. Ignored.");
        continue;
      }
      final parsed = _toDoubleMaybe(newVal);
      if (parsed != null) {
        perProc[resolvedPid]![nameKey] =
            p.copyWith(value: parsed, formula: null);
      } else {
        onWarning?.call(
            "Process parameter '$name' for process '$resolvedPid' expects numeric 'new_value'; got '$newVal'. Ignored.");
      }
      continue;
    }

    // Unknown field → ignore but record
    onWarning?.call("Unsupported delta field '$field'. Ignored.");
  }

  final newGlobals = globals.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final newPerProc = <String, List<Parameter>>{
    for (final e in perProc.entries)
      e.key: e.value.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()))
  };

  return ParameterSet(global: newGlobals, perProcess: newPerProc);
}

double? _toDoubleMaybe(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value.trim());
    if (parsed != null) return parsed;
  }
  return null;
}
