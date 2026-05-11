part of 'llm_scenario_controller.dart';

class _OptimizationToolMemory {
  final List<_ResolvedImpactCategory> searchMatches;
  final Map<String, _ResolvedImpactCategory> preferredAliasByNeedle;
  final Map<String, List<_ResolvedImpactCategory>> aliasMatchesByNeedle;

  _OptimizationToolMemory()
      : searchMatches = <_ResolvedImpactCategory>[],
        preferredAliasByNeedle = <String, _ResolvedImpactCategory>{},
        aliasMatchesByNeedle = <String, List<_ResolvedImpactCategory>>{};

  bool get isEmpty =>
      searchMatches.isEmpty &&
      preferredAliasByNeedle.isEmpty &&
      aliasMatchesByNeedle.isEmpty;
}

void _recordToolResult({
  required LlmScenarioController controller,
  required String name,
  required Map<String, dynamic> args,
  required Map<String, dynamic> toolReturn,
  required _OptimizationToolMemory toolMemory,
}) {
  if (name != 'searchOpenLcaIndicators') return;

  final records = <Map<String, dynamic>>[];
  final results = toolReturn['results'];
  if (results is List) {
    for (final item in results) {
      if (item is Map) {
        records.add(item.cast<String, dynamic>());
      }
    }
  }
  if (records.isEmpty) {
    records.add(toolReturn);
  }

  for (final record in records) {
    final query = (record['query'] ?? args['query'] ?? '').toString().trim();
    final disambiguationNeeded = record['disambiguation_needed'] == true;
    final matches = _impactMatchesFromDynamic(record['matches']);
    if (matches.isEmpty) continue;

    _appendUniqueImpactCategories(toolMemory.searchMatches, matches);

    final aliases =
        query.isEmpty ? const <String>{} : controller._expandedImpactNeedles(query);
    for (final alias in aliases) {
      final bucket = toolMemory.aliasMatchesByNeedle.putIfAbsent(
        alias,
        () => <_ResolvedImpactCategory>[],
      );
      _appendUniqueImpactCategories(bucket, matches);
    }

    if (disambiguationNeeded || aliases.isEmpty) continue;
    final best = _impactMatchFromDynamic(record['best_match']) ?? matches.first;
    for (final alias in aliases) {
      toolMemory.preferredAliasByNeedle.putIfAbsent(alias, () => best);
    }
  }
}

Map<String, dynamic> _buildOptimizationContextForPromptImpl({
  required Map<String, dynamic> optimizationContext,
}) {
  return {
    if (optimizationContext['product_system'] is Map)
      'product_system': optimizationContext['product_system'],
    if (optimizationContext['impact_categories'] is List)
      'impact_categories': optimizationContext['impact_categories'],
    'indicator_resolution_note':
        'Reuse impact_category_id, indicator, and impact_method_id verbatim when exact entries or tool results provide them.',
  };
}

_ValidatedScenarioChanges _validateOptimizationPayloadImpl({
  required LlmScenarioController controller,
  required Map<String, dynamic> optimization,
  required Map<String, dynamic> baseModelFull,
  required Map<String, dynamic> optimizationContext,
  required _OptimizationToolMemory toolMemory,
}) {
  final productSystem = optimizationContext['product_system'];
  final productSystemId = productSystem is Map
      ? (productSystem['id'] ?? '').toString().trim()
      : '';
  if (productSystemId.isEmpty) {
    return const _ValidatedScenarioChanges(
      abstention: LlmScenarioAbstention(
        reason:
            'Optimization requires an imported OpenLCA product system, but none was available in context.',
        requiredCapability: 'OpenLCA product system selected before optimization',
      ),
    );
  }

  final rawMode = (optimization['mode'] ?? '').toString().trim();
  if (rawMode.isNotEmpty &&
      rawMode != 'parameter_threshold' &&
      rawMode != 'indicator_optimization' &&
      rawMode != 'constrained_optimization') {
    return const _ValidatedScenarioChanges(
      abstention: LlmScenarioAbstention(
        reason:
            'Optimization mode must be "parameter_threshold", "constrained_optimization", or "indicator_optimization".',
        requiredCapability: 'Supported optimization JSON mode',
      ),
    );
  }

  final index = controller._buildModelValidationIndex(baseModelFull);
  final variablesAny = optimization['variables'];
  if (variablesAny is! List || variablesAny.isEmpty) {
    return const _ValidatedScenarioChanges(
      abstention: LlmScenarioAbstention(
        reason: 'Optimization must include at least one variable parameter.',
        requiredCapability: 'Optimization variables over editable parameters',
      ),
    );
  }

  final variables = <Map<String, dynamic>>[];
  for (var i = 0; i < variablesAny.length; i += 1) {
    final raw = variablesAny[i];
    if (raw is! Map) {
      return _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason: 'Optimization variable ${i + 1} is not a JSON object.',
          requiredCapability: 'Valid optimization variable schema',
        ),
      );
    }
    final variable = raw.cast<String, dynamic>();
    final field = (variable['field'] ?? '').toString().trim();
    final lower = controller._toFiniteDouble(variable['lower']);
    final upper = controller._toFiniteDouble(variable['upper']);
    final initial = controller._toFiniteDouble(variable['initial']);
    if (field.isEmpty || lower == null || upper == null || lower >= upper) {
      return _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason:
              'Optimization variable ${i + 1} has invalid field or bounds.',
          requiredCapability: 'Finite lower and upper bounds for each variable',
        ),
      );
    }

    if (field.startsWith('parameters.global.')) {
      final paramName = field.substring('parameters.global.'.length).trim();
      if (!index.globalParamNames.contains(paramName.toLowerCase())) {
        return _ValidatedScenarioChanges(
          abstention: LlmScenarioAbstention(
            reason:
                'Optimization variable "$field" does not match an editable global parameter.',
            requiredCapability: 'Valid global parameter from model_context',
          ),
        );
      }
      variables.add({
        'field': 'parameters.global.$paramName',
        'lower': lower,
        'upper': upper,
        if (initial != null) 'initial': initial,
      });
      continue;
    }

    if (field.startsWith('parameters.process.')) {
      final paramName = field.substring('parameters.process.'.length).trim();
      final processIdRaw = (variable['process_id'] ?? '').toString().trim();
      final processId = controller._resolveProcessId(
        processIdRaw,
        index.processIdByLower,
      );
      if (processId == null) {
        return _ValidatedScenarioChanges(
          abstention: LlmScenarioAbstention(
            reason:
                'Optimization process variable "$field" is missing a valid process_id.',
            requiredCapability: 'Valid process_id for process parameter variable',
          ),
        );
      }
      final editableParams =
          index.processParamNamesById[processId] ?? const <String>{};
      if (!editableParams.contains(paramName.toLowerCase())) {
        return _ValidatedScenarioChanges(
          abstention: LlmScenarioAbstention(
            reason:
                'Optimization variable "$field" does not exist for process "$processId".',
            requiredCapability: 'Valid process parameter from model_context',
          ),
        );
      }
      variables.add({
        'field': 'parameters.process.$paramName',
        'process_id': processId,
        'lower': lower,
        'upper': upper,
        if (initial != null) 'initial': initial,
      });
      continue;
    }

    return _ValidatedScenarioChanges(
      abstention: LlmScenarioAbstention(
        reason:
            'Optimization variable "$field" is not an editable parameter field.',
        requiredCapability: 'Global or process parameter optimization variable',
      ),
    );
  }

  final impactIndex = _buildCombinedImpactValidationIndex(
    controller: controller,
    optimizationContext: optimizationContext,
    toolMemory: toolMemory,
  );
  final resolvedIndicators = <_ResolvedImpactCategory>[];

  final constraintsAny = optimization['constraints'];
  final constraints = <Map<String, dynamic>>[];
  if (constraintsAny is List) {
    for (var i = 0; i < constraintsAny.length; i += 1) {
      final raw = constraintsAny[i];
      if (raw is! Map) {
        return _ValidatedScenarioChanges(
          abstention: LlmScenarioAbstention(
            reason: 'Optimization constraint ${i + 1} is not a JSON object.',
            requiredCapability: 'Valid optimization constraint schema',
          ),
        );
      }
      final constraint = raw.cast<String, dynamic>();
      final constraintMethodHint = ((constraint['impact_method_id'] ??
                  optimization['impact_method_id']) ??
              '')
          .toString()
          .trim();
      final constraintMethodNameHint =
          (constraint['impact_method_name'] ?? '').toString().trim();
      final impactCategoryId =
          (constraint['impact_category_id'] ?? '').toString().trim();
      final indicator = (constraint['indicator'] ?? '').toString().trim();
      final operator = (constraint['operator'] ?? '').toString().trim();
      final target = controller._toFiniteDouble(constraint['target']);
      if (operator != '<=' && operator != '>=' && operator != '==') {
        return _ValidatedScenarioChanges(
          abstention: LlmScenarioAbstention(
            reason: 'Optimization constraint "$indicator" has invalid operator.',
            requiredCapability: 'Constraint operator <=, >=, or ==',
          ),
        );
      }
      if (target == null) {
        return _ValidatedScenarioChanges(
          abstention: LlmScenarioAbstention(
            reason: 'Optimization constraint "$indicator" has non-numeric target.',
            requiredCapability: 'Numeric optimization constraint target',
          ),
        );
      }
      final resolved = _resolveImpactCategoryForOptimization(
        controller: controller,
        rawIndicator: indicator,
        rawImpactCategoryId: impactCategoryId,
        methodIdHint: constraintMethodHint,
        index: impactIndex,
        toolMemory: toolMemory,
      );
      if (resolved == null &&
          impactCategoryId.isNotEmpty &&
          constraintMethodHint.isNotEmpty) {
        final passthrough = _passthroughImpactCategory(
          controller: controller,
          impactCategoryId: impactCategoryId,
          indicator: indicator,
          methodId: constraintMethodHint,
          index: impactIndex,
        );
        resolvedIndicators.add(passthrough);
        constraints.add({
          'impact_method_id': passthrough.methodId,
          if ((constraintMethodNameHint.isNotEmpty
                  ? constraintMethodNameHint
                  : passthrough.methodName)
              .trim()
              .isNotEmpty)
            'impact_method_name': constraintMethodNameHint.isNotEmpty
                ? constraintMethodNameHint
                : passthrough.methodName,
          'impact_category_id': passthrough.impactCategoryId,
          'indicator': passthrough.indicator,
          'operator': operator,
          'target': target,
        });
        controller._log(
          '[LCA] Accepted passthrough impact_category_id for constraint: '
          'id=${passthrough.impactCategoryId} method=${passthrough.methodId}',
        );
        continue;
      }
      if (resolved == null) {
        return _ValidatedScenarioChanges(
          abstention: LlmScenarioAbstention(
            reason:
                'Optimization indicator "$indicator" (id="$impactCategoryId") is not available in OpenLCA impact categories.',
            requiredCapability: 'Valid impact category from optimization_context',
          ),
        );
      }
      resolvedIndicators.add(resolved);
      constraints.add({
        'impact_method_id': resolved.methodId,
        if (resolved.methodName.trim().isNotEmpty)
          'impact_method_name': resolved.methodName,
        if (resolved.impactCategoryId.isNotEmpty)
          'impact_category_id': resolved.impactCategoryId,
        'indicator': resolved.indicator,
        'operator': operator,
        'target': target,
      });
    }
  }

  final objectiveAny = optimization['objective'];
  final objective = objectiveAny is Map
      ? objectiveAny.cast<String, dynamic>()
      : <String, dynamic>{};
  final objectiveType = (objective['type'] ?? '').toString().trim();
  final direction = (objective['direction'] ?? 'minimize').toString().trim();
  if (direction != 'minimize' && direction != 'maximize') {
    return const _ValidatedScenarioChanges(
      abstention: LlmScenarioAbstention(
        reason: 'Optimization objective direction must be minimize or maximize.',
        requiredCapability: 'Valid optimization objective direction',
      ),
    );
  }

  late final String mode;
  if (objectiveType == 'parameter') {
    mode = direction == 'minimize' && variables.length == 1 && constraints.length == 1
        ? 'parameter_threshold'
        : 'constrained_optimization';
  } else {
    mode = 'constrained_optimization';
  }

  if (mode == 'parameter_threshold' && constraints.isEmpty) {
    return const _ValidatedScenarioChanges(
      abstention: LlmScenarioAbstention(
        reason: 'Parameter-threshold optimization requires LCIA constraints.',
        requiredCapability: 'At least one impact constraint',
      ),
    );
  }

  final normalizedObjective = <String, dynamic>{};
  if (objectiveType == 'parameter' || mode == 'parameter_threshold') {
    if (objectiveType.isNotEmpty && objectiveType != 'parameter') {
      return const _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason:
              'Parameter-threshold optimization must use a parameter objective.',
          requiredCapability: 'objective.type="parameter"',
        ),
      );
    }
    final variableIndex = controller._toInt(objective['variable_index']) ?? 0;
    if (variableIndex < 0 || variableIndex >= variables.length) {
      return _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason:
              'Parameter objective variable_index $variableIndex is out of range.',
          requiredCapability: 'Valid objective variable_index',
        ),
      );
    }
    normalizedObjective.addAll({
      'type': 'parameter',
      'variable_index': variableIndex,
      'direction': direction,
    });
  } else if (objectiveType == 'indicator') {
    final impactCategoryId =
        (objective['impact_category_id'] ?? '').toString().trim();
    final indicator = (objective['indicator'] ?? '').toString().trim();
    final objectiveMethodHint =
        ((objective['impact_method_id'] ?? optimization['impact_method_id']) ??
                '')
            .toString()
            .trim();
    final objectiveMethodNameHint =
        (objective['impact_method_name'] ?? '').toString().trim();
    final resolved = _resolveImpactCategoryForOptimization(
      controller: controller,
      rawIndicator: indicator,
      rawImpactCategoryId: impactCategoryId,
      methodIdHint: objectiveMethodHint,
      index: impactIndex,
      toolMemory: toolMemory,
    );
    if (resolved == null &&
        impactCategoryId.isNotEmpty &&
        objectiveMethodHint.isNotEmpty) {
      final passthrough = _passthroughImpactCategory(
        controller: controller,
        impactCategoryId: impactCategoryId,
        indicator: indicator,
        methodId: objectiveMethodHint,
        index: impactIndex,
      );
      resolvedIndicators.add(passthrough);
      normalizedObjective.addAll({
        'type': 'indicator',
        'impact_method_id': passthrough.methodId,
        if ((objectiveMethodNameHint.isNotEmpty
                ? objectiveMethodNameHint
                : passthrough.methodName)
            .trim()
            .isNotEmpty)
          'impact_method_name': objectiveMethodNameHint.isNotEmpty
              ? objectiveMethodNameHint
              : passthrough.methodName,
        'impact_category_id': passthrough.impactCategoryId,
        'indicator': passthrough.indicator,
        'direction': direction,
      });
      controller._log(
        '[LCA] Accepted passthrough impact_category_id for objective: '
        'id=${passthrough.impactCategoryId} method=${passthrough.methodId}',
      );
    } else if (resolved == null) {
      return _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason:
              'Optimization objective indicator "$indicator" (id="$impactCategoryId") is not available in OpenLCA impact categories.',
          requiredCapability: 'Valid objective indicator from optimization_context',
        ),
      );
    } else {
      resolvedIndicators.add(resolved);
      normalizedObjective.addAll({
        'type': 'indicator',
        'impact_method_id': resolved.methodId,
        if (resolved.methodName.trim().isNotEmpty)
          'impact_method_name': resolved.methodName,
        if (resolved.impactCategoryId.isNotEmpty)
          'impact_category_id': resolved.impactCategoryId,
        'indicator': resolved.indicator,
        'direction': direction,
      });
    }
  } else {
    return const _ValidatedScenarioChanges(
      abstention: LlmScenarioAbstention(
        reason: 'Optimization objective type must be parameter or indicator.',
        requiredCapability: 'Valid optimization objective type',
      ),
    );
  }

  final methodIds = {
    for (final resolved in resolvedIndicators) resolved.methodId,
  }..removeWhere((id) => id.trim().isEmpty);
  final sharedMethodId = methodIds.length == 1 ? methodIds.first : '';
  final sharedMethodName = sharedMethodId.isEmpty
      ? ''
      : resolvedIndicators
          .firstWhere((item) => item.methodId == sharedMethodId)
          .methodName;

  final n = ((controller._toInt(optimization['n']) ?? 256).clamp(1, 512) as num)
      .toInt();
  final iters =
      ((controller._toInt(optimization['iters']) ?? 4).clamp(1, 8) as num)
          .toInt();
  final samplingMethod =
      (optimization['sampling_method'] ?? '').toString().trim();
  final payload = <String, dynamic>{
    'mode': mode,
    'product_system_id': productSystemId,
    if (sharedMethodId.isNotEmpty) 'impact_method_id': sharedMethodId,
    if (sharedMethodName.trim().isNotEmpty)
      'impact_method_name': sharedMethodName,
    'variables': variables,
    'constraints': constraints,
    'objective': normalizedObjective,
    'n': n,
    'iters': iters,
    'sampling_method': samplingMethod.isEmpty ? 'sobol' : samplingMethod,
  };
  controller._log('[LCA] Optimization JSON validated: ${jsonEncode(payload)}');
  return _ValidatedScenarioChanges(optimizationPayload: payload);
}

Map<String, dynamic> _searchOpenLcaIndicatorsImpl({
  required LlmScenarioController controller,
  required String query,
  required String methodHint,
  required int limit,
  required List<Map<String, dynamic>>? queries,
  required Map<String, dynamic> optimizationContext,
}) {
  final batched = <Map<String, dynamic>>[];
  if (queries != null && queries.isNotEmpty) {
    for (final q in queries.take(4)) {
      final qText = (q['query'] ?? '').toString().trim();
      if (qText.isEmpty) continue;
      batched.add({
        'query': qText,
        'method_hint': (q['method_hint'] ?? '').toString(),
        'limit': controller._toInt(q['limit']) ?? limit,
      });
    }
  } else {
    final qText = query.trim();
    if (qText.isNotEmpty) {
      batched.add({
        'query': qText,
        'method_hint': methodHint,
        'limit': limit,
      });
    }
  }

  if (batched.isEmpty) {
    return {
      'query': query,
      'matches': const <Map<String, dynamic>>[],
      'total_matches': 0,
    };
  }

  final results = <Map<String, dynamic>>[];
  var totalMatches = 0;
  for (final request in batched) {
    final item = controller._searchOpenLcaIndicatorsSingle(
      query: (request['query'] ?? '').toString(),
      methodHint: (request['method_hint'] ?? '').toString(),
      limit: controller._toInt(request['limit']) ?? 5,
      optimizationContext: optimizationContext,
    );
    final matches = (item['matches'] as List?) ?? const [];
    totalMatches += matches.length;
    results.add(item);
  }

  if (results.length == 1 && (queries == null || queries.isEmpty)) {
    final single = results.first;
    return {
      ...single,
      'total_matches': totalMatches,
    };
  }

  final allMatches = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final result in results) {
    final matches = (result['matches'] as List?) ?? const [];
    for (final raw in matches) {
      if (raw is! Map) continue;
      final m = raw.cast<String, dynamic>();
      final key =
          '${m['method_id'] ?? ''}|${m['impact_category_id'] ?? ''}|${m['indicator'] ?? ''}'
              .toLowerCase();
      if (seen.add(key)) {
        allMatches.add(m);
      }
    }
  }

  return {
    'queries': batched,
    'results': results,
    'all_matches': allMatches,
    'total_matches': totalMatches,
  };
}

List<_ResolvedImpactCategory> _buildCombinedImpactValidationIndex({
  required LlmScenarioController controller,
  required Map<String, dynamic> optimizationContext,
  required _OptimizationToolMemory toolMemory,
}) {
  final out = <_ResolvedImpactCategory>[];
  _appendUniqueImpactCategories(
    out,
    controller._buildImpactValidationIndex(optimizationContext),
  );
  _appendUniqueImpactCategories(out, toolMemory.searchMatches);
  return out;
}

_ResolvedImpactCategory? _resolveImpactCategoryForOptimization({
  required LlmScenarioController controller,
  required String rawIndicator,
  required String rawImpactCategoryId,
  required String methodIdHint,
  required List<_ResolvedImpactCategory> index,
  required _OptimizationToolMemory toolMemory,
}) {
  final resolved = controller._resolveImpactCategory(
    rawIndicator,
    rawImpactCategoryId,
    methodIdHint,
    index,
  );
  if (resolved != null) return resolved;
  if (toolMemory.isEmpty) return null;
  return _resolveImpactCategoryFromToolMemory(
    controller: controller,
    rawIndicator: rawIndicator,
    methodIdHint: methodIdHint,
    toolMemory: toolMemory,
  );
}

_ResolvedImpactCategory? _resolveImpactCategoryFromToolMemory({
  required LlmScenarioController controller,
  required String rawIndicator,
  required String methodIdHint,
  required _OptimizationToolMemory toolMemory,
}) {
  final aliases = controller._expandedImpactNeedles(rawIndicator);
  if (aliases.isEmpty) return null;

  for (final alias in aliases) {
    final preferred = toolMemory.preferredAliasByNeedle[alias];
    if (preferred != null && _matchesMethodHint(controller, preferred, methodIdHint)) {
      return preferred;
    }
  }

  final candidates = <_ResolvedImpactCategory>[];
  for (final alias in aliases) {
    final bucket = toolMemory.aliasMatchesByNeedle[alias];
    if (bucket == null || bucket.isEmpty) continue;
    _appendUniqueImpactCategories(candidates, bucket);
  }
  if (candidates.isEmpty) return null;

  final filtered = methodIdHint.trim().isEmpty
      ? candidates
      : candidates
          .where((item) => _matchesMethodHint(controller, item, methodIdHint))
          .toList();
  final pool = filtered.isNotEmpty ? filtered : candidates;
  if (pool.length == 1) return pool.first;

  final impactIds = pool
      .map((item) => item.impactCategoryId.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  if (impactIds.length == 1) return pool.first;
  return null;
}

bool _matchesMethodHint(
  LlmScenarioController controller,
  _ResolvedImpactCategory item,
  String methodIdHint,
) {
  final hint = controller._normalizeImpactText(methodIdHint);
  if (hint.isEmpty) return true;
  final methodId = controller._normalizeImpactText(item.methodId);
  final methodName = controller._normalizeImpactText(item.methodName);
  return methodId == hint ||
      methodName == hint ||
      methodName.contains(hint) ||
      hint.contains(methodName);
}

_ResolvedImpactCategory _passthroughImpactCategory({
  required LlmScenarioController controller,
  required String impactCategoryId,
  required String indicator,
  required String methodId,
  required List<_ResolvedImpactCategory> index,
}) {
  final fallbackIndicator =
      indicator.isNotEmpty ? indicator : impactCategoryId;
  final methodName = controller._methodNameForId(methodId, index);
  return _ResolvedImpactCategory(
    methodId: methodId,
    methodName: methodName,
    impactCategoryId: impactCategoryId,
    indicator: fallbackIndicator,
  );
}

List<_ResolvedImpactCategory> _impactMatchesFromDynamic(dynamic rawMatches) {
  if (rawMatches is! List) return const <_ResolvedImpactCategory>[];
  final out = <_ResolvedImpactCategory>[];
  for (final raw in rawMatches) {
    final parsed = _impactMatchFromDynamic(raw);
    if (parsed != null) {
      out.add(parsed);
    }
  }
  return out;
}

_ResolvedImpactCategory? _impactMatchFromDynamic(dynamic raw) {
  if (raw is! Map) return null;
  final map = raw.cast<String, dynamic>();
  final methodId = (map['method_id'] ?? '').toString().trim();
  final methodName = (map['method_name'] ?? '').toString().trim();
  final impactCategoryId = (map['impact_category_id'] ?? '').toString().trim();
  final indicator = (map['indicator'] ?? '').toString().trim();
  if (methodId.isEmpty || indicator.isEmpty) return null;
  return _ResolvedImpactCategory(
    methodId: methodId,
    methodName: methodName,
    impactCategoryId: impactCategoryId,
    indicator: indicator,
  );
}

void _appendUniqueImpactCategories(
  List<_ResolvedImpactCategory> target,
  Iterable<_ResolvedImpactCategory> source,
) {
  final seen = {
    for (final item in target)
      '${item.methodId}|${item.impactCategoryId}|${item.indicator}'.toLowerCase(),
  };
  for (final item in source) {
    final key =
        '${item.methodId}|${item.impactCategoryId}|${item.indicator}'.toLowerCase();
    if (seen.add(key)) {
      target.add(item);
    }
  }
}
