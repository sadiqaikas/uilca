



// File: lib/lca_functions.dart

import 'dart:math' as math;

import 'newhome/lca_models.dart';

/// Utilities for generating numeric change-lists over model parameters.
/// Each function returns a List of change-lists. A “change-list” is a
/// List<Map<String, dynamic>> where each map has one of the forms:
///
///   Global parameter:
///     { 'field': 'parameters.global.<ParamName>',
///       'new_value': <number> }
///
///   Per-process parameter:
///     { 'process_id': '<processId>',
///       'field': 'parameters.process.<ParamName>',
///       'new_value': <number> }
///
/// Notes:
/// - We only touch parameters that exist in the base model.
/// - For OFAT we vary one parameter name at a time across all occurrences
///   (global occurrence and any per-process occurrences sharing that name).
/// - For simplex-lattice design we redistribute totals across the selected
///   parameterNames while preserving per-occurrence proportions.

/// -------------------------------------------------------------------------------------------------
/// 1) One-Factor-at-a-Time Sensitivity (OFAT) on parameters
///
/// For each parameter name in `parameterNames`, generate scenarios that vary that parameter’s value
/// by ±percent (or by each level in `levels`), while leaving all other parameter names unchanged.
/// If a name exists in multiple places (global and several processes), all occurrences of that name
/// are scaled together in that scenario.
/// -------------------------------------------------------------------------------------------------
List<List<Map<String, dynamic>>> oneAtATimeSensitivity({
  required Map<String, dynamic> baseModel,
  required List<String> parameterNames,
  double percent = 10.0,
  List<double>? levels,
}) {
  final params = (baseModel['parameters'] as Map?) ?? const {};
  final globals = (params['global_parameters'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final procParams =
      (params['process_parameters'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
  final resolved = _resolveParameterSymbols(params.cast<String, dynamic>());

  final List<List<Map<String, dynamic>>> allChangeLists = [];

  // Default sweep: [-percent, +percent]
  final List<double> sweepLevels = levels ?? <double>[-percent, percent];

  // Pre-index occurrences of each requested name
  final Map<String, _ParamOccurrences> occByName = {};
  for (final name in parameterNames) {
    occByName[name] = _collectOccurrencesForName(
      name,
      globals,
      procParams,
      globalSymbols: resolved.global,
      processSymbols: resolved.processById,
    );
  }

  for (final name in parameterNames) {
    final occ = occByName[name]!;
    if (occ.isEmpty) {
      // No such parameter anywhere; still emit an empty changeList per level
      // so the downstream can see that the scenario was considered.
      for (final _ in sweepLevels) {
        allChangeLists.add(const <Map<String, dynamic>>[]);
      }
      continue;
    }

    for (final lvl in sweepLevels) {
      final double factor = 1.0 + (lvl / 100.0);
      final List<Map<String, dynamic>> changeList = [];

      // Global occurrences for this name
      for (final g in occ.global) {
        final double newVal = _round6(g.value * factor);
        changeList.add({
          'field': 'parameters.global.${g.name}',
          'new_value': newVal,
        });
      }

      // Per-process occurrences for this name
      for (final p in occ.process) {
        final double newVal = _round6(p.value * factor);
        changeList.add({
          'process_id': p.processId,
          'field': 'parameters.process.${p.name}',
          'new_value': newVal,
        });
      }

      allChangeLists.add(changeList);
    }
  }

  return allChangeLists;
}

/// -------------------------------------------------------------------------------------------------
/// 2) Simplex-Lattice Mixture Design on parameters
///
/// Redistribute the combined total of the selected parameter names according to a {q, m}
/// simplex-lattice design, where q is the count of valid, resolved parameter names and each component takes values
/// in {0, 1/m, …, 1} with the sum equal to 1. For each lattice point:
///   - Compute the target total for each parameter name: totalBaseline * (ci / m)
///   - Scale every occurrence of that parameter name (global and per-process) by the same factor
///     so that the name’s overall total hits the target, keeping per-occurrence proportions.
/// Set removeEdges=true to omit boundary points where any selected component is zero.
/// If a parameter name has a baseline total of 0, it is skipped for that lattice point.
/// -------------------------------------------------------------------------------------------------
List<List<Map<String, dynamic>>> simplexLatticeDesign({
  required Map<String, dynamic> baseModel,
  required List<String> parameterNames,
  required int m,
  bool removeEdges = false,
}) {
  if (m <= 0) {
    throw ArgumentError('simplexLatticeDesign requires m >= 1. Received m=$m.');
  }

  final params = (baseModel['parameters'] as Map?) ?? const {};
  final globals = (params['global_parameters'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  final procParams =
      (params['process_parameters'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
  final resolved = _resolveParameterSymbols(params.cast<String, dynamic>());

  // Normalise: trim, remove empties, dedupe case-insensitively.
  final seenKeys = <String>{};
  final requestedNames = <String>[];
  for (final raw in parameterNames) {
    final name = raw.trim();
    if (name.isEmpty) continue;
    final key = name.toLowerCase();
    if (seenKeys.add(key)) {
      requestedNames.add(name);
    }
  }

  // Gather occurrences and baseline totals for each requested name.
  // Keep only names that actually resolve in the model and have positive totals.
  final activeNames = <String>[];
  final Map<String, _ParamOccurrences> occByName = {};
  final Map<String, double> totalByName = {};
  for (final name in requestedNames) {
    final occ = _collectOccurrencesForName(
      name,
      globals,
      procParams,
      globalSymbols: resolved.global,
      processSymbols: resolved.processById,
    );
    occByName[name] = occ;
    final total = occ.sum();
    totalByName[name] = total;
    if (!occ.isEmpty && total > 0.0 && total.isFinite) {
      activeNames.add(name);
    }
  }
  final int q = activeNames.length;
  if (q == 0) {
    return const <List<Map<String, dynamic>>>[];
  }
  if (removeEdges && m < q) {
    return const <List<Map<String, dynamic>>>[];
  }

  final pointCountEstimate = removeEdges
      ? _estimateSimplexPointCount(q: q, m: m - q)
      : _estimateSimplexPointCount(q: q, m: m);
  if (pointCountEstimate > _maxSimplexLatticePoints) {
    throw ArgumentError(
      'simplexLatticeDesign would generate $pointCountEstimate lattice points '
      '(limit=$_maxSimplexLatticePoints). Reduce m or the number of selected parameters.',
    );
  }

  // Sum of all selected names
  final double grandTotal =
      activeNames.fold(0.0, (a, n) => a + (totalByName[n] ?? 0.0));
  if (grandTotal <= 0.0) {
    // Nothing to mix
    return const <List<Map<String, dynamic>>>[];
  }

  // Build integer combinations c[0..q-1] with sum m
  final List<List<int>> combos = [];
  void build(List<int> current, int idx, int remaining) {
    if (idx == q - 1) {
      current[idx] = remaining;
      combos.add(List<int>.from(current));
      return;
    }
    for (int i = 0; i <= remaining; i++) {
      current[idx] = i;
      build(current, idx + 1, remaining - i);
    }
  }
  build(List<int>.filled(q, 0), 0, m);

  final List<List<Map<String, dynamic>>> allChangeLists = [];

  for (final combo in combos) {
    if (removeEdges && combo.any((value) => value == 0)) {
      continue;
    }
    final Map<String, double> targetTotals = {};
    for (int k = 0; k < q; k++) {
      final name = activeNames[k];
      targetTotals[name] = grandTotal * (combo[k] / m);
    }

    final List<Map<String, dynamic>> changeList = [];

    for (final name in activeNames) {
      final occ = occByName[name]!;
      final double baseTotal = totalByName[name]!;
      if (baseTotal <= 0.0) {
        continue;
      }
      final double factor = targetTotals[name]! / baseTotal;

      for (final g in occ.global) {
        final double newVal = _round6(g.value * factor);
        changeList.add({
          'field': 'parameters.global.${g.name}',
          'new_value': newVal,
        });
      }
      for (final p in occ.process) {
        final double newVal = _round6(p.value * factor);
        changeList.add({
          'process_id': p.processId,
          'field': 'parameters.process.${p.name}',
          'new_value': newVal,
        });
      }
    }

    allChangeLists.add(changeList);
  }

  return allChangeLists;
}

/// Deterministic engineering formula calculator.
///
/// The LLM selects a named formula and supplies typed numeric arguments; this
/// function performs the arithmetic and returns auditable structured results.
Map<String, dynamic> formulaCalculator({
  required List<Map<String, dynamic>> calculations,
}) {
  const catalogVersion = 'engineering_formula_catalog_v1';
  final results = <Map<String, dynamic>>[];

  for (var i = 0; i < calculations.length; i += 1) {
    final calculation = calculations[i];
    final formula = _nameText(calculation['formula']);
    final id = _nameText(calculation['id']).isNotEmpty
        ? _nameText(calculation['id'])
        : 'calc_${i + 1}';
    final argsRaw = calculation['arguments'];
    final args = argsRaw is Map
        ? argsRaw.cast<String, dynamic>()
        : const <String, dynamic>{};

    try {
      results.add({
        'id': id,
        'formula': formula,
        ..._runFormulaCalculation(formula, args),
      });
    } catch (e) {
      results.add({
        'id': id,
        'formula': formula,
        'success': false,
        'error': e.toString(),
      });
    }
  }

  return {
    'formula_catalog_version': catalogVersion,
    'results': results,
  };
}

Map<String, dynamic> _runFormulaCalculation(
  String formula,
  Map<String, dynamic> args,
) {
  switch (formula) {
    case 'abrams_compressive_strength':
      final a = _requiredNumber(args, 'a');
      final b = _requiredNumber(args, 'b');
      final wc = _waterCementRatio(args);
      if (a <= 0 || b <= 0 || wc <= 0) {
        throw ArgumentError('a, b, and water_cement_ratio must be positive.');
      }
      final fc = a / math.pow(b, wc);
      return _formulaSuccess(
        expression: 'f_c = a / b^(w/c)',
        inputs: {'a': a, 'b': b, 'water_cement_ratio': wc},
        outputs: {'compressive_strength': fc},
      );

    case 'electrical_resistivity':
      final resistance = _requiredNumber(args, 'resistance');
      final area = _requiredNumber(args, 'area');
      final length = _requiredNumber(args, 'length');
      if (area <= 0 || length <= 0) {
        throw ArgumentError('area and length must be positive.');
      }
      return _formulaSuccess(
        expression: 'rho = R * A / L',
        inputs: {'resistance': resistance, 'area': area, 'length': length},
        outputs: {'resistivity': resistance * area / length},
      );

    case 'thermal_conduction_rate':
      final k = _requiredNumber(args, 'thermal_conductivity');
      final area = _requiredNumber(args, 'area');
      final deltaT = _requiredNumber(args, 'temperature_difference');
      final thickness = _requiredNumber(args, 'thickness');
      if (k < 0 || area <= 0 || thickness <= 0) {
        throw ArgumentError(
          'thermal_conductivity must be non-negative; area and thickness must be positive.',
        );
      }
      return _formulaSuccess(
        expression: 'q_dot = k * A * delta_T / L',
        inputs: {
          'thermal_conductivity': k,
          'area': area,
          'temperature_difference': deltaT,
          'thickness': thickness,
        },
        outputs: {'heat_transfer_rate': k * area * deltaT / thickness},
      );

    case 'capital_recovery_factor':
      final rate = _requiredNumber(args, 'interest_rate');
      final periods = _requiredNumber(args, 'periods');
      final capitalCost = _optionalNumber(args, 'capital_cost');
      if (periods <= 0 || periods.roundToDouble() != periods) {
        throw ArgumentError('periods must be a positive integer.');
      }
      if (rate < 0) {
        throw ArgumentError('interest_rate must be non-negative.');
      }
      final n = periods.toInt();
      final crf = rate == 0
          ? 1.0 / n
          : rate * math.pow(1 + rate, n) / (math.pow(1 + rate, n) - 1);
      return _formulaSuccess(
        expression: 'CRF = i(1+i)^n / ((1+i)^n - 1)',
        inputs: {
          'interest_rate': rate,
          'periods': n,
          if (capitalCost != null) 'capital_cost': capitalCost,
        },
        outputs: {
          'capital_recovery_factor': crf,
          if (capitalCost != null) 'annualized_cost': capitalCost * crf,
        },
      );

    case 'learning_curve_cost':
      final initialCost = _requiredNumber(args, 'initial_cost');
      final cumulativeQuantity = _requiredNumber(args, 'cumulative_quantity');
      final referenceQuantity = _requiredNumber(args, 'reference_quantity');
      final progressRatio = _requiredNumber(args, 'progress_ratio');
      if (initialCost < 0 ||
          cumulativeQuantity <= 0 ||
          referenceQuantity <= 0 ||
          progressRatio <= 0 ||
          progressRatio >= 1) {
        throw ArgumentError(
          'initial_cost must be non-negative; quantities must be positive; progress_ratio must be between 0 and 1.',
        );
      }
      final exponent = math.log(progressRatio) / math.log(2);
      final cost =
          initialCost * math.pow(cumulativeQuantity / referenceQuantity, exponent);
      return _formulaSuccess(
        expression: 'cost = C0 * (Q/Q0)^(ln(progress_ratio)/ln(2))',
        inputs: {
          'initial_cost': initialCost,
          'cumulative_quantity': cumulativeQuantity,
          'reference_quantity': referenceQuantity,
          'progress_ratio': progressRatio,
        },
        outputs: {'unit_cost': cost, 'learning_exponent': exponent},
      );

    default:
      throw ArgumentError('Unknown formula "$formula".');
  }
}

Map<String, dynamic> _formulaSuccess({
  required String expression,
  required Map<String, dynamic> inputs,
  required Map<String, dynamic> outputs,
}) {
  return {
    'success': true,
    'expression': expression,
    'inputs': inputs,
    'outputs': outputs.map(
      (key, value) => MapEntry(key, value is num ? _roundSignificant(value) : value),
    ),
  };
}

double _waterCementRatio(Map<String, dynamic> args) {
  final direct = _optionalNumber(args, 'water_cement_ratio');
  if (direct != null) return direct;
  final water = _requiredNumber(args, 'water');
  final cement = _requiredNumber(args, 'cement');
  if (cement == 0) {
    throw ArgumentError('cement must be non-zero when deriving water_cement_ratio.');
  }
  return water / cement;
}

/// ===== Helpers ================================================================================

const int _maxSimplexLatticePoints = 1200;

int _estimateSimplexPointCount({
  required int q,
  required int m,
}) {
  if (q <= 0 || m < 0) return 0;
  if (q == 1) return 1;

  // Number of integer solutions to c1 + ... + cq = m is C(m+q-1, q-1).
  int n = m + q - 1;
  int k = q - 1;
  if (k > n - k) k = n - k;

  int out = 1;
  for (int i = 1; i <= k; i++) {
    out = (out * (n - k + i)) ~/ i;
  }
  return out;
}

double _round6(double x) => double.parse(x.toStringAsFixed(6));

double _roundSignificant(num value) {
  final x = value.toDouble();
  if (!x.isFinite || x == 0) return x;
  final exponent = (math.log(x.abs()) / math.ln10).floor();
  final scale = math.pow(10, 10 - exponent - 1).toDouble();
  return (x * scale).roundToDouble() / scale;
}

double _requiredNumber(Map<String, dynamic> args, String key) {
  final value = _optionalNumber(args, key);
  if (value == null || !value.isFinite) {
    throw ArgumentError('Missing or non-numeric argument "$key".');
  }
  return value;
}

double? _optionalNumber(Map<String, dynamic> args, String key) {
  final value = _asDouble(args[key]);
  if (value == null || !value.isFinite) return null;
  return value;
}

class _GlobalParamRef {
  final String name;
  final double value;
  _GlobalParamRef({required this.name, required this.value});
}

class _ProcessParamRef {
  final String processId;
  final String name;
  final double value;
  _ProcessParamRef({
    required this.processId,
    required this.name,
    required this.value,
  });
}

class _ParamOccurrences {
  final List<_GlobalParamRef> global;
  final List<_ProcessParamRef> process;

  _ParamOccurrences({required this.global, required this.process});

  bool get isEmpty => global.isEmpty && process.isEmpty;

  double sum() {
    double s = 0.0;
    for (final g in global) {
      s += g.value;
    }
    for (final p in process) {
      s += p.value;
    }
    return s;
  }
}

class _ResolvedParameterSymbols {
  final Map<String, double> global;
  final Map<String, Map<String, double>> processById;
  _ResolvedParameterSymbols({
    required this.global,
    required this.processById,
  });
}

_ResolvedParameterSymbols _resolveParameterSymbols(Map<String, dynamic> params) {
  try {
    final parameterSet = ParameterSet.fromJson(params);
    final global = parameterSet.evaluateGlobalSymbolsLenient();

    final processById = <String, Map<String, double>>{};
    final rawProc = (params['process_parameters'] as Map?) ?? const {};
    for (final e in rawProc.entries) {
      final pid = e.key.toString();
      processById[pid] = parameterSet.evaluateSymbolsForProcessLenient(pid);
    }
    return _ResolvedParameterSymbols(global: global, processById: processById);
  } catch (_) {
    return _ResolvedParameterSymbols(global: const {}, processById: const {});
  }
}

double? _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

String _nameText(dynamic value) => (value ?? '').toString().trim();

double? _resolvedValue(
  Map<String, dynamic> rawParam,
  Map<String, double> symbols,
) {
  final direct = _asDouble(rawParam['value']);
  if (direct != null) return direct;
  final key = _nameText(rawParam['name']).toLowerCase();
  if (key.isEmpty) return null;
  return symbols[key];
}

_ParamOccurrences _collectOccurrencesForName(
  String name,
  List<Map<String, dynamic>> globals,
  Map<String, dynamic> procParams,
  {
  required Map<String, double> globalSymbols,
  required Map<String, Map<String, double>> processSymbols,
  }
) {
  final List<_GlobalParamRef> gRefs = [];
  final List<_ProcessParamRef> pRefs = [];
  final needle = name.trim().toLowerCase();
  if (needle.isEmpty) {
    return _ParamOccurrences(global: gRefs, process: pRefs);
  }

  for (final gp in globals) {
    final rawName = _nameText(gp['name']);
    if (rawName.toLowerCase() != needle) continue;
    final value = _resolvedValue(gp, globalSymbols);
    if (value == null) continue;
    gRefs.add(_GlobalParamRef(name: rawName, value: value));
  }

  procParams.forEach((pid, listAny) {
    final pidText = pid.toString();
    final symbols = processSymbols[pidText] ?? const <String, double>{};
    final list = (listAny as List?)?.cast<Map<String, dynamic>>() ?? const [];
    for (final pp in list) {
      final rawName = _nameText(pp['name']);
      if (rawName.toLowerCase() != needle) continue;
      final value = _resolvedValue(pp, symbols);
      if (value == null) continue;
      pRefs.add(_ProcessParamRef(
        processId: pidText,
        name: rawName,
        value: value,
      ));
    }
  });

  return _ParamOccurrences(global: gRefs, process: pRefs);
}

_ParamOccurrences _collectAllOccurrences(
  List<Map<String, dynamic>> globals,
  Map<String, dynamic> procParams,
  {
  required Map<String, double> globalSymbols,
  required Map<String, Map<String, double>> processSymbols,
  }
) {
  final List<_GlobalParamRef> gRefs = [];
  final List<_ProcessParamRef> pRefs = [];

  for (final gp in globals) {
    final rawName = _nameText(gp['name']);
    if (rawName.isEmpty) continue;
    final value = _resolvedValue(gp, globalSymbols);
    if (value == null) continue;
    gRefs.add(_GlobalParamRef(name: rawName, value: value));
  }

  procParams.forEach((pid, listAny) {
    final pidText = pid.toString();
    final symbols = processSymbols[pidText] ?? const <String, double>{};
    final list = (listAny as List?)?.cast<Map<String, dynamic>>() ?? const [];
    for (final pp in list) {
      final rawName = _nameText(pp['name']);
      if (rawName.isEmpty) continue;
      final value = _resolvedValue(pp, symbols);
      if (value == null) continue;
        pRefs.add(_ProcessParamRef(
          processId: pidText,
          name: rawName,
          value: value,
        ));
    }
  });

  return _ParamOccurrences(global: gRefs, process: pRefs);
}
