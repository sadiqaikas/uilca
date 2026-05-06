part of 'llm_scenario_controller.dart';

class _UncertaintyParameterMeta {
  final String scope;
  final String name;
  final String? processId;
  final String? processName;
  final double? baselineValue;
  final String? formula;
  final String? unit;
  final String? note;

  const _UncertaintyParameterMeta({
    required this.scope,
    required this.name,
    this.processId,
    this.processName,
    this.baselineValue,
    this.formula,
    this.unit,
    this.note,
  });

  bool get isCalculatedOnly =>
      (formula ?? '').trim().isNotEmpty || baselineValue == null;

  bool get isEditable => !isCalculatedOnly;
}

class _UncertaintyParameterRegistry {
  final Map<String, _UncertaintyParameterMeta> globalByLower;
  final Map<String, Map<String, _UncertaintyParameterMeta>> processById;
  final Map<String, String> processNameById;
  final Map<String, List<String>> processIdsByNameLower;

  const _UncertaintyParameterRegistry({
    required this.globalByLower,
    required this.processById,
    required this.processNameById,
    required this.processIdsByNameLower,
  });
}

const Set<String> _uncertaintyUnsupportedStructuralKeys = {
  'flows',
  'processes',
  'inputs',
  'emissions',
  'biosphere',
  'biosphere_flows',
  'exchanges',
  'exchange',
  'datasets',
  'dataset',
  'background_dataset',
  'background_datasets',
  'providers',
  'provider',
  'technosphere',
  'flow_id',
  'add_process',
  'remove_process',
  'replace_process',
  'create_flow',
  'create_process',
  'change_provider',
  'remap_database',
  'database',
  'allocation',
  'system_boundary',
  'systemboundary',
};

const Set<String> _uncertaintyTopLevelKeys = {
  'tool',
  'model_id',
  'product_system',
  'product_system_id',
  'functional_unit',
  'impact_method',
  'impact_method_id',
  'impact_categories',
  'sampling',
  'parameters',
  'outputs',
  'ipc_url',
  'user_prompt',
};

const Set<String> _uncertaintyFunctionalUnitKeys = {
  'amount',
  'unit',
};

const Set<String> _uncertaintyImpactCategoryKeys = {
  'indicator',
  'name',
  'impact_category_id',
  'impact_method_id',
  'impact_method_name',
  'unit',
};

const Set<String> _uncertaintySamplingKeys = {
  'method',
  'n_samples',
  'random_seed',
};

const Set<String> _uncertaintyOutputsKeys = {
  'percentiles',
  'include_sample_matrix',
  'include_failed_runs',
};

const Set<String> _uncertaintyParameterKeys = {
  'scope',
  'context',
  'name',
  'baseline_value',
  'baseline_value_supplied',
  'unit',
  'note',
  'uncertainty',
};

const Set<String> _uncertaintyContextKeys = {
  'process_name',
  'process_id',
  'id',
};

const Set<String> _uncertaintyDistributionKeys = {
  'distributionType',
  'minimum',
  'mode',
  'maximum',
  'mean',
  'sd',
  'geomMean',
  'geomSd',
  'lower_bound',
  'upper_bound',
};

_ValidatedScenarioChanges _validateUncertaintyPayloadImpl({
  required LlmScenarioController controller,
  required Map<String, dynamic> uncertainty,
  required Map<String, dynamic> baseModelFull,
  required Map<String, dynamic> optimizationContext,
  required _OptimizationToolMemory toolMemory,
}) {
  controller._log(
    '[LCA][uncertainty] Starting validation '
    'keys=${uncertainty.keys.join(', ')}',
  );
  if ((uncertainty['tool'] ?? '').toString().trim() !=
      'uncertainty_propagation') {
    controller._log(
      '[LCA][uncertainty] Rejecting payload because tool='
      '"${(uncertainty['tool'] ?? '').toString().trim()}"',
    );
    return const _ValidatedScenarioChanges(
      abstention: LlmScenarioAbstention(
        reason:
            'Uncertainty propagation payload must set tool to "uncertainty_propagation".',
        requiredCapability: 'Exact uncertainty_propagation tool schema',
      ),
    );
  }

  final unsupportedPath = _findUnsupportedUncertaintyStructuralEdit(uncertainty);
  if (unsupportedPath != null) {
    controller._log(
      '[LCA][uncertainty] Rejecting payload because unsupported '
      'structural path was found: $unsupportedPath',
    );
    return _ValidatedScenarioChanges(
      abstention: LlmScenarioAbstention(
        reason:
            'Uncertainty propagation may not include structural model edits. '
            'Found unsupported field at "$unsupportedPath".',
        requiredCapability:
            'Parameter-only uncertainty propagation over the existing model',
      ),
    );
  }

  final productSystem = optimizationContext['product_system'];
  final productSystemId = productSystem is Map
      ? (productSystem['id'] ?? '').toString().trim()
      : '';
  final productSystemName = productSystem is Map
      ? (productSystem['name'] ?? '').toString().trim()
      : '';
  if (productSystemId.isEmpty) {
    controller._log(
      '[LCA][uncertainty] Rejecting payload because no OpenLCA '
      'product system is available in optimization_context',
    );
    return const _ValidatedScenarioChanges(
      abstention: LlmScenarioAbstention(
        reason:
            'Uncertainty propagation requires an imported OpenLCA product system.',
        requiredCapability: 'OpenLCA product system selected before propagation',
      ),
    );
  }

  final requestedProductSystem =
      (uncertainty['product_system'] ?? '').toString().trim();
  if (requestedProductSystem.isNotEmpty) {
    final selectedNeedles = {
      productSystemId.toLowerCase(),
      productSystemName.toLowerCase(),
    }..remove('');
    if (!selectedNeedles.contains(requestedProductSystem.toLowerCase())) {
      controller._log(
        '[LCA][uncertainty] Rejecting payload because requested '
        'product system "$requestedProductSystem" does not match '
        'selected product system "$productSystemId" / "$productSystemName"',
      );
      return _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason:
              'Requested product system "$requestedProductSystem" does not match the currently selected OpenLCA product system.',
          requiredCapability: 'Use the active product system from optimization_context',
        ),
      );
    }
  }

  final registry =
      _buildUncertaintyParameterRegistry(
        controller: controller,
        baseModelFull: baseModelFull,
      );
  controller._log(
    '[LCA][uncertainty] Parameter registry built: '
    'global=${registry.globalByLower.length} '
    'processes=${registry.processById.length}',
  );

  final functionalUnit =
      _normalizeUncertaintyFunctionalUnit(controller, uncertainty);
  if (functionalUnit == null) {
    controller._log(
      '[LCA][uncertainty] Rejecting payload because functional_unit '
      'could not be normalized: ${jsonEncode(uncertainty['functional_unit'])}',
    );
    return const _ValidatedScenarioChanges(
      abstention: LlmScenarioAbstention(
        reason: 'functional_unit.amount must be a positive number.',
        requiredCapability: 'Valid functional_unit amount for uncertainty propagation',
      ),
    );
  }

  final sampling = _normalizeUncertaintySampling(controller, uncertainty);
  if (sampling == null) {
    controller._log(
      '[LCA][uncertainty] Rejecting payload because sampling '
      'could not be normalized: ${jsonEncode(uncertainty['sampling'])}',
    );
    return const _ValidatedScenarioChanges(
      abstention: LlmScenarioAbstention(
        reason:
            'Sampling must use method "latin_hypercube" or "monte_carlo" and n_samples between 10 and 5000.',
        requiredCapability:
            'Supported sampling method and safe sample count for uncertainty propagation',
      ),
    );
  }

  final outputs = _normalizeUncertaintyOutputs(controller, uncertainty);
  if (outputs == null) {
    controller._log(
      '[LCA][uncertainty] Rejecting payload because outputs '
      'could not be normalized: ${jsonEncode(uncertainty['outputs'])}',
    );
    return const _ValidatedScenarioChanges(
      abstention: LlmScenarioAbstention(
        reason:
            'outputs.percentiles must be a non-empty list of numbers between 0 and 100.',
        requiredCapability: 'Valid uncertainty output percentile configuration',
      ),
    );
  }

  final impactIndex = _buildCombinedImpactValidationIndex(
    controller: controller,
    optimizationContext: optimizationContext,
    toolMemory: toolMemory,
  );
  final methodHint = (uncertainty['impact_method'] ?? '').toString().trim();
  final rawImpactCategories = uncertainty['impact_categories'];
  if (rawImpactCategories is! List || rawImpactCategories.isEmpty) {
    controller._log(
      '[LCA][uncertainty] Rejecting payload because impact_categories '
      'is empty or invalid: ${jsonEncode(rawImpactCategories)}',
    );
    return const _ValidatedScenarioChanges(
      abstention: LlmScenarioAbstention(
        reason: 'Uncertainty propagation requires at least one impact category.',
        requiredCapability: 'Selected LCIA indicators from optimization_context',
      ),
    );
  }

  final normalizedImpactCategories = <Map<String, dynamic>>[];
  final resolvedImpactCategories = <_ResolvedImpactCategory>[];
  for (var i = 0; i < rawImpactCategories.length; i += 1) {
    final raw = rawImpactCategories[i];
    String rawIndicator = '';
    String rawImpactCategoryId = '';
    String localMethodHint = methodHint;
    if (raw is String) {
      rawIndicator = raw.trim();
    } else if (raw is Map) {
      final map = raw.cast<String, dynamic>();
      rawIndicator = (map['indicator'] ?? map['name'] ?? '').toString().trim();
      rawImpactCategoryId =
          (map['impact_category_id'] ?? '').toString().trim();
      localMethodHint =
          ((map['impact_method_id'] ?? map['impact_method_name']) ?? methodHint)
              .toString()
              .trim();
    } else {
      controller._log(
        '[LCA][uncertainty] Rejecting payload because impact category '
        '${i + 1} is not string/map: ${raw.runtimeType}',
      );
      return _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason:
              'impact_categories entry ${i + 1} must be a string or object.',
          requiredCapability: 'Valid uncertainty impact category schema',
        ),
      );
    }

    final resolved = _resolveImpactCategoryForOptimization(
      controller: controller,
      rawIndicator: rawIndicator,
      rawImpactCategoryId: rawImpactCategoryId,
      methodIdHint: localMethodHint,
      index: impactIndex,
      toolMemory: toolMemory,
    );
    if (resolved == null) {
      controller._log(
        '[LCA][uncertainty] Rejecting payload because impact category '
        'could not be resolved: indicator="$rawIndicator" '
        'impact_category_id="$rawImpactCategoryId" '
        'method_hint="$localMethodHint"',
      );
      return _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason:
              'Impact category "${rawIndicator.isEmpty ? rawImpactCategoryId : rawIndicator}" is not available in the current OpenLCA impact context.',
          requiredCapability: 'Valid impact category from optimization_context',
        ),
      );
    }
    final key =
        '${resolved.methodId}|${resolved.impactCategoryId}|${resolved.indicator}'
            .toLowerCase();
    final alreadyPresent = normalizedImpactCategories.any(
      (item) =>
          '${item['impact_method_id']}|${item['impact_category_id']}|${item['indicator']}'
              .toLowerCase() ==
          key,
    );
    if (alreadyPresent) continue;
    resolvedImpactCategories.add(resolved);
    normalizedImpactCategories.add({
      'impact_method_id': resolved.methodId,
      if (resolved.methodName.trim().isNotEmpty)
        'impact_method_name': resolved.methodName,
      if (resolved.impactCategoryId.trim().isNotEmpty)
        'impact_category_id': resolved.impactCategoryId,
      'indicator': resolved.indicator,
    });
  }

  final resolvedMethodIds = {
    for (final resolved in resolvedImpactCategories)
      resolved.methodId.trim().toLowerCase(),
  }..remove('');
  if (resolvedMethodIds.length != 1) {
    controller._log(
      '[LCA][uncertainty] Rejecting payload because multiple LCIA '
      'methods were resolved: ${resolvedMethodIds.join(', ')}',
    );
    return const _ValidatedScenarioChanges(
      abstention: LlmScenarioAbstention(
        reason:
            'Uncertainty propagation currently requires all selected impact categories to belong to one LCIA method.',
        requiredCapability:
            'Single-method uncertainty propagation over selected impact categories',
      ),
    );
  }
  final resolvedMethod = resolvedImpactCategories.first;

  final rawParameters = uncertainty['parameters'];
  if (rawParameters is! List || rawParameters.isEmpty) {
    controller._log(
      '[LCA][uncertainty] Rejecting payload because parameters '
      'is empty or invalid: ${jsonEncode(rawParameters)}',
    );
    return const _ValidatedScenarioChanges(
      abstention: LlmScenarioAbstention(
        reason:
            'Uncertainty propagation must include at least one parameter specification.',
        requiredCapability: 'Practitioner-defined uncertainty over existing parameters',
      ),
    );
  }

  final normalizedParameters = <Map<String, dynamic>>[];
  for (var i = 0; i < rawParameters.length; i += 1) {
    final raw = rawParameters[i];
    if (raw is! Map) {
      controller._log(
        '[LCA][uncertainty] Rejecting payload because parameter '
        '${i + 1} is not a map: ${raw.runtimeType}',
      );
      return _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason: 'Parameter ${i + 1} is not a JSON object.',
          requiredCapability: 'Valid uncertainty parameter schema',
        ),
      );
    }
    final parameter = raw.cast<String, dynamic>();
    final scope = (parameter['scope'] ?? '').toString().trim().toLowerCase();
    final name = (parameter['name'] ?? '').toString().trim();
    controller._log(
      '[LCA][uncertainty] Validating parameter ${i + 1}: '
      'scope="$scope" name="$name" context=${jsonEncode(parameter['context'])}',
    );
    if (scope != 'global' && scope != 'process') {
      return _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason:
              'Parameter ${i + 1} has unsupported scope "$scope". Use "global" or "process".',
          requiredCapability: 'Supported parameter scope for uncertainty propagation',
        ),
      );
    }
    if (name.isEmpty) {
      return _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason: 'Parameter ${i + 1} is missing a name.',
          requiredCapability: 'Valid parameter names from model_context',
        ),
      );
    }

    final resolvedParameter = _resolveUncertaintyParameter(
      registry: registry,
      scope: scope,
      name: name,
      context: parameter['context'],
    );
    if (resolvedParameter.error != null) {
      controller._log(
        '[LCA][uncertainty] Rejecting parameter "$name": '
        '${resolvedParameter.error}',
      );
      return _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason: resolvedParameter.error!,
          requiredCapability:
              'Unambiguous editable parameter context for uncertainty propagation',
        ),
      );
    }
    final meta = resolvedParameter.meta!;
    if (!meta.isEditable) {
      controller._log(
        '[LCA][uncertainty] Rejecting parameter "${meta.name}" '
        'because it is not safely editable. baseline=${meta.baselineValue} '
        'formula=${jsonEncode(meta.formula)}',
      );
      return _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason:
              'Parameter "${meta.name}" is dependent or formula-based and cannot be redefined safely for uncertainty propagation.',
          requiredCapability: 'Editable numeric baseline parameter in model_context',
        ),
      );
    }

    final uncertaintyBlock = parameter['uncertainty'];
    if (uncertaintyBlock is! Map) {
      controller._log(
        '[LCA][uncertainty] Rejecting parameter "${meta.name}" '
        'because uncertainty block is invalid: '
        '${jsonEncode(uncertaintyBlock)}',
      );
      return _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason: 'Parameter "${meta.name}" is missing an uncertainty object.',
          requiredCapability: 'Valid uncertainty definition for each parameter',
        ),
      );
    }
    final normalizedUncertainty = _normalizeUncertaintyDistribution(
      controller,
      uncertaintyBlock.cast<String, dynamic>(),
      parameterName: meta.name,
    );
    if (normalizedUncertainty == null) {
      controller._log(
        '[LCA][uncertainty] Rejecting parameter "${meta.name}" '
        'because uncertainty block could not be normalized: '
        '${jsonEncode(uncertaintyBlock)}',
      );
      return _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason:
              'Parameter "${meta.name}" has an invalid or unsupported uncertainty definition.',
          requiredCapability:
              'Supported uncertainty distribution with valid numeric bounds',
        ),
      );
    }

    final suppliedBaseline = controller._toFiniteDouble(parameter['baseline_value']);
    final baselineValue = meta.baselineValue!;
    if (parameter.containsKey('baseline_value') && suppliedBaseline == null) {
      controller._log(
        '[LCA][uncertainty] Rejecting parameter "${meta.name}" '
        'because supplied baseline_value is non-numeric: '
        '${jsonEncode(parameter['baseline_value'])}',
      );
      return _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason:
              'Parameter "${meta.name}" has a non-numeric baseline_value.',
          requiredCapability:
              'Numeric baseline_value for each uncertainty parameter',
        ),
      );
    }

    normalizedParameters.add({
      'scope': scope,
      'context': scope == 'global'
          ? null
          : {
              if ((meta.processName ?? '').trim().isNotEmpty)
                'process_name': meta.processName,
              if ((meta.processId ?? '').trim().isNotEmpty)
                'process_id': meta.processId,
            },
      'name': meta.name,
      'baseline_value': baselineValue,
      if ((meta.unit ?? '').trim().isNotEmpty) 'unit': meta.unit,
      if ((meta.note ?? '').trim().isNotEmpty) 'note': meta.note,
      if (suppliedBaseline != null &&
          (suppliedBaseline - baselineValue).abs() > 1e-9)
        'baseline_value_supplied': suppliedBaseline,
      'uncertainty': normalizedUncertainty,
    });
  }

  final payload = <String, dynamic>{
    'tool': 'uncertainty_propagation',
    'model_id': (uncertainty['model_id'] ?? '').toString().trim().isNotEmpty
        ? (uncertainty['model_id'] ?? '').toString().trim()
        : (productSystemName.isNotEmpty ? productSystemName : productSystemId),
    'product_system': productSystemName.isNotEmpty
        ? productSystemName
        : productSystemId,
    'product_system_id': productSystemId,
    'functional_unit': functionalUnit,
    'impact_method': resolvedMethod.methodName.isNotEmpty
        ? resolvedMethod.methodName
        : resolvedMethod.methodId,
    'impact_method_id': resolvedMethod.methodId,
    'impact_categories': normalizedImpactCategories,
    'sampling': sampling,
    'parameters': normalizedParameters,
    'outputs': outputs,
  };
  controller._log(
    '[LCA][uncertainty] Validation successful. '
    'impactCategories=${normalizedImpactCategories.length} '
    'parameters=${normalizedParameters.length} '
    'sampling=${jsonEncode(sampling)} '
    'payload=${jsonEncode(payload)}',
  );
  return _ValidatedScenarioChanges(uncertaintyPayload: payload);
}

String? _findUnsupportedUncertaintyStructuralEdit(
  dynamic value, {
  String path = r'$',
}) {
  if (path == r'$' && value is Map) {
    return _validateUncertaintyPayloadShape(
      value.cast<String, dynamic>(),
      path: path,
    );
  }
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().trim().toLowerCase();
      if (_uncertaintyUnsupportedStructuralKeys.contains(key)) {
        return '$path.${entry.key}';
      }
      final child = _findUnsupportedUncertaintyStructuralEdit(
        entry.value,
        path: '$path.${entry.key}',
      );
      if (child != null) {
        return child;
      }
    }
    return null;
  }
  if (value is List) {
    for (var i = 0; i < value.length; i += 1) {
      final child = _findUnsupportedUncertaintyStructuralEdit(
        value[i],
        path: '$path[$i]',
      );
      if (child != null) {
        return child;
      }
    }
  }
  return null;
}

String? _validateUncertaintyPayloadShape(
  Map<String, dynamic> payload, {
  required String path,
}) {
  final topLevelIssue = _findDisallowedStructuralKeyAtLevel(
    payload,
    allowedKeys: _uncertaintyTopLevelKeys,
    path: path,
  );
  if (topLevelIssue != null) return topLevelIssue;

  final functionalUnit = payload['functional_unit'];
  if (functionalUnit is Map) {
    final issue = _findDisallowedStructuralKeyAtLevel(
      functionalUnit.cast<String, dynamic>(),
      allowedKeys: _uncertaintyFunctionalUnitKeys,
      path: '$path.functional_unit',
    );
    if (issue != null) return issue;
  }

  final impactCategories = payload['impact_categories'];
  if (impactCategories is List) {
    for (var i = 0; i < impactCategories.length; i += 1) {
      final item = impactCategories[i];
      if (item is! Map) continue;
      final issue = _findDisallowedStructuralKeyAtLevel(
        item.cast<String, dynamic>(),
        allowedKeys: _uncertaintyImpactCategoryKeys,
        path: '$path.impact_categories[$i]',
      );
      if (issue != null) return issue;
    }
  }

  final sampling = payload['sampling'];
  if (sampling is Map) {
    final issue = _findDisallowedStructuralKeyAtLevel(
      sampling.cast<String, dynamic>(),
      allowedKeys: _uncertaintySamplingKeys,
      path: '$path.sampling',
    );
    if (issue != null) return issue;
  }

  final outputs = payload['outputs'];
  if (outputs is Map) {
    final issue = _findDisallowedStructuralKeyAtLevel(
      outputs.cast<String, dynamic>(),
      allowedKeys: _uncertaintyOutputsKeys,
      path: '$path.outputs',
    );
    if (issue != null) return issue;
  }

  final parameters = payload['parameters'];
  if (parameters is List) {
    for (var i = 0; i < parameters.length; i += 1) {
      final item = parameters[i];
      if (item is! Map) continue;
      final parameter = item.cast<String, dynamic>();
      final paramPath = '$path.parameters[$i]';
      final issue = _findDisallowedStructuralKeyAtLevel(
        parameter,
        allowedKeys: _uncertaintyParameterKeys,
        path: paramPath,
      );
      if (issue != null) return issue;
      final context = parameter['context'];
      if (context is Map) {
        final contextIssue = _findDisallowedStructuralKeyAtLevel(
          context.cast<String, dynamic>(),
          allowedKeys: _uncertaintyContextKeys,
          path: '$paramPath.context',
        );
        if (contextIssue != null) return contextIssue;
      }
      final uncertainty = parameter['uncertainty'];
      if (uncertainty is Map) {
        final uncertaintyIssue = _findDisallowedStructuralKeyAtLevel(
          uncertainty.cast<String, dynamic>(),
          allowedKeys: _uncertaintyDistributionKeys,
          path: '$paramPath.uncertainty',
        );
        if (uncertaintyIssue != null) return uncertaintyIssue;
      }
    }
  }

  for (final entry in payload.entries) {
    final key = entry.key.toString().trim().toLowerCase();
    final isKnown = _uncertaintyTopLevelKeys.any(
      (allowed) => allowed.toLowerCase() == key,
    );
    if (isKnown) continue;
    final child = _findUnsupportedUncertaintyStructuralEdit(
      entry.value,
      path: '$path.${entry.key}',
    );
    if (child != null) return child;
  }

  return null;
}

String? _findDisallowedStructuralKeyAtLevel(
  Map<String, dynamic> map, {
  required Set<String> allowedKeys,
  required String path,
}) {
  for (final entry in map.entries) {
    final rawKey = entry.key.toString().trim();
    final key = rawKey.toLowerCase();
    if (_uncertaintyUnsupportedStructuralKeys.contains(key)) {
      return '$path.$rawKey';
    }
    final isKnownHere = allowedKeys.any((allowed) => allowed.toLowerCase() == key);
    if (!isKnownHere) {
      continue;
    }
    final child = _findUnsupportedUncertaintyStructuralEdit(
      entry.value,
      path: '$path.$rawKey',
    );
    if (child != null) return child;
  }
  return null;
}

Map<String, dynamic>? _normalizeUncertaintyFunctionalUnit(
  LlmScenarioController controller,
  Map<String, dynamic> uncertainty,
) {
  final raw = uncertainty['functional_unit'];
  if (raw == null) {
    return const {'amount': 1.0};
  }
  if (raw is! Map) return null;
  final map = raw.cast<String, dynamic>();
  final amount = controller._toFiniteDouble(map['amount']);
  if (amount == null || amount <= 0) return null;
  final unit = (map['unit'] ?? '').toString().trim();
  return {
    'amount': amount,
    if (unit.isNotEmpty) 'unit': unit,
  };
}

Map<String, dynamic>? _normalizeUncertaintySampling(
  LlmScenarioController controller,
  Map<String, dynamic> uncertainty,
) {
  final raw = uncertainty['sampling'];
  final map = raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
  final method = (map['method'] ?? 'latin_hypercube')
      .toString()
      .trim()
      .toLowerCase();
  if (method != 'latin_hypercube' && method != 'monte_carlo') {
    return null;
  }
  final nSamples = controller._toInt(map['n_samples']) ?? 250;
  if (nSamples < 10 || nSamples > 5000) {
    return null;
  }
  final randomSeed = controller._toInt(map['random_seed']) ?? 42;
  return {
    'method': method,
    'n_samples': nSamples,
    'random_seed': randomSeed,
  };
}

Map<String, dynamic>? _normalizeUncertaintyOutputs(
  LlmScenarioController controller,
  Map<String, dynamic> uncertainty,
) {
  final raw = uncertainty['outputs'];
  final map = raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
  final rawPercentiles = map['percentiles'];
  final percentiles = <double>[];
  if (rawPercentiles is List) {
    for (final item in rawPercentiles) {
      final value = controller._toFiniteDouble(item);
      if (value == null || value < 0 || value > 100) {
        return null;
      }
      if (!percentiles.contains(value)) {
        percentiles.add(value);
      }
    }
  }
  if (percentiles.isEmpty) {
    percentiles.addAll(const [5.0, 50.0, 95.0]);
  }
  percentiles.sort();
  return {
    'percentiles': percentiles,
    'include_sample_matrix': map['include_sample_matrix'] != false,
    'include_failed_runs': map['include_failed_runs'] != false,
  };
}

Map<String, dynamic>? _normalizeUncertaintyDistribution(
  LlmScenarioController controller,
  Map<String, dynamic> uncertainty, {
  required String parameterName,
}) {
  final distributionType =
      (uncertainty['distributionType'] ?? '').toString().trim();
  switch (distributionType) {
    case 'UNIFORM_DISTRIBUTION':
      final minimum = controller._toFiniteDouble(uncertainty['minimum']);
      final maximum = controller._toFiniteDouble(uncertainty['maximum']);
      if (minimum == null || maximum == null || minimum >= maximum) {
        return null;
      }
      return {
        'distributionType': distributionType,
        'minimum': minimum,
        'maximum': maximum,
      };
    case 'TRIANGLE_DISTRIBUTION':
      final minimum = controller._toFiniteDouble(uncertainty['minimum']);
      final mode = controller._toFiniteDouble(uncertainty['mode']);
      final maximum = controller._toFiniteDouble(uncertainty['maximum']);
      if (minimum == null ||
          mode == null ||
          maximum == null ||
          minimum >= maximum ||
          mode < minimum ||
          mode > maximum) {
        return null;
      }
      return {
        'distributionType': distributionType,
        'minimum': minimum,
        'mode': mode,
        'maximum': maximum,
      };
    case 'NORMAL_DISTRIBUTION':
      final mean = controller._toFiniteDouble(uncertainty['mean']);
      final sd = controller._toFiniteDouble(uncertainty['sd']);
      final lowerBound = controller._toFiniteDouble(uncertainty['lower_bound']);
      final upperBound = controller._toFiniteDouble(uncertainty['upper_bound']);
      if (mean == null || sd == null || sd <= 0) {
        return null;
      }
      if (lowerBound != null &&
          upperBound != null &&
          lowerBound > upperBound) {
        return null;
      }
      return {
        'distributionType': distributionType,
        'mean': mean,
        'sd': sd,
        if (lowerBound != null) 'lower_bound': lowerBound,
        if (upperBound != null) 'upper_bound': upperBound,
      };
    case 'LOG_NORMAL_DISTRIBUTION':
      final geomMean = controller._toFiniteDouble(uncertainty['geomMean']);
      final geomSd = controller._toFiniteDouble(uncertainty['geomSd']);
      if (geomMean == null || geomSd == null || geomMean <= 0 || geomSd <= 1) {
        return null;
      }
      return {
        'distributionType': distributionType,
        'geomMean': geomMean,
        'geomSd': geomSd,
      };
    default:
      controller._log(
        '[LCA] Unsupported uncertainty distribution for $parameterName: '
        '$distributionType',
      );
      return null;
  }
}

_UncertaintyParameterRegistry _buildUncertaintyParameterRegistry({
  required LlmScenarioController controller,
  required Map<String, dynamic> baseModelFull,
}) {
  final parameterSet = controller._readParameterSetForValidation(baseModelFull);
  final globalByLower = <String, _UncertaintyParameterMeta>{};
  final processById = <String, Map<String, _UncertaintyParameterMeta>>{};
  final processNameById = <String, String>{};
  final processIdsByNameLower = <String, List<String>>{};

  void addProcessName(String processId, String processName) {
    final pid = processId.trim();
    final name = processName.trim();
    if (pid.isEmpty) return;
    if (name.isNotEmpty) {
      processNameById.putIfAbsent(pid, () => name);
      final key = name.toLowerCase();
      final bucket = processIdsByNameLower.putIfAbsent(key, () => <String>[]);
      if (!bucket.contains(pid)) {
        bucket.add(pid);
      }
    } else {
      processNameById.putIfAbsent(pid, () => pid);
    }
    processById.putIfAbsent(pid, () => <String, _UncertaintyParameterMeta>{});
  }

  _UncertaintyParameterMeta chooseBetter(
    _UncertaintyParameterMeta current,
    _UncertaintyParameterMeta next,
  ) {
    if (!current.isEditable && next.isEditable) return next;
    if (current.baselineValue == null && next.baselineValue != null) return next;
    if ((current.unit ?? '').trim().isEmpty && (next.unit ?? '').trim().isNotEmpty) {
      return next;
    }
    return current;
  }

  void addGlobal(Parameter parameter) {
    final name = parameter.name.trim();
    if (name.isEmpty) return;
    final meta = _UncertaintyParameterMeta(
      scope: 'global',
      name: name,
      baselineValue: parameter.value,
      formula: parameter.formula,
      unit: parameter.unit,
      note: parameter.note,
    );
    final key = name.toLowerCase();
    final existing = globalByLower[key];
    globalByLower[key] = existing == null ? meta : chooseBetter(existing, meta);
  }

  void addProcessParameter(String processId, Parameter parameter) {
    final pid = processId.trim();
    final name = parameter.name.trim();
    if (pid.isEmpty || name.isEmpty) return;
    addProcessName(pid, processNameById[pid] ?? pid);
    final meta = _UncertaintyParameterMeta(
      scope: 'process',
      name: name,
      processId: pid,
      processName: processNameById[pid],
      baselineValue: parameter.value,
      formula: parameter.formula,
      unit: parameter.unit,
      note: parameter.note,
    );
    final table = processById.putIfAbsent(pid, () => <String, _UncertaintyParameterMeta>{});
    final key = name.toLowerCase();
    final existing = table[key];
    table[key] = existing == null ? meta : chooseBetter(existing, meta);
  }

  for (final parameter in parameterSet.global) {
    addGlobal(parameter);
  }

  final rawProcesses = baseModelFull['processes'];
  if (rawProcesses is List) {
    for (final raw in rawProcesses) {
      if (raw is! Map) continue;
      final process = raw.cast<String, dynamic>();
      final processId = (process['id'] ?? '').toString().trim();
      final processName = (process['name'] ?? '').toString().trim();
      if (processId.isEmpty) continue;
      addProcessName(processId, processName);
      for (final parameter in parameterSet.processParamsFor(processId)) {
        addProcessParameter(processId, parameter);
      }
      final inlineParams = process['parameters'];
      if (inlineParams is List) {
        for (final rawParam in inlineParams) {
          if (rawParam is! Map) continue;
          addProcessParameter(
            processId,
            Parameter.fromJson(rawParam.cast<String, dynamic>()),
          );
        }
      }
    }
  }

  for (final entry in parameterSet.perProcess.entries) {
    addProcessName(entry.key, processNameById[entry.key] ?? entry.key);
    for (final parameter in entry.value) {
      addProcessParameter(entry.key, parameter);
    }
  }

  return _UncertaintyParameterRegistry(
    globalByLower: globalByLower,
    processById: processById,
    processNameById: processNameById,
    processIdsByNameLower: processIdsByNameLower,
  );
}

class _ResolvedUncertaintyParameter {
  final _UncertaintyParameterMeta? meta;
  final String? error;

  const _ResolvedUncertaintyParameter({this.meta, this.error});
}

_ResolvedUncertaintyParameter _resolveUncertaintyParameter({
  required _UncertaintyParameterRegistry registry,
  required String scope,
  required String name,
  required dynamic context,
}) {
  final key = name.trim().toLowerCase();
  if (scope == 'global') {
    final meta = registry.globalByLower[key];
    if (meta != null) {
      return _ResolvedUncertaintyParameter(meta: meta);
    }
    final inProcesses = registry.processById.values.any((table) => table.containsKey(key));
    return _ResolvedUncertaintyParameter(
      error: inProcesses
          ? 'Parameter "$name" exists only in process scope, not global scope.'
          : 'Global parameter "$name" does not exist in the current model.',
    );
  }

  Map<String, dynamic> contextMap = const <String, dynamic>{};
  if (context != null && context is! Map) {
    return const _ResolvedUncertaintyParameter(
      error: 'Process parameter context must be null or an object.',
    );
  }
  if (context is Map) {
    contextMap = context.cast<String, dynamic>();
  }

  String? resolvedProcessId;
  final processIdHint = ((contextMap['process_id'] ?? contextMap['id']) ?? '')
      .toString()
      .trim();
  final processNameHint = (contextMap['process_name'] ?? '')
      .toString()
      .trim();

  if (processIdHint.isNotEmpty) {
    resolvedProcessId = _resolveRegistryProcessId(registry, processIdHint);
    if (resolvedProcessId == null) {
      return _ResolvedUncertaintyParameter(
        error: 'Process context "$processIdHint" does not exist in the current model.',
      );
    }
  }

  if (resolvedProcessId == null && processNameHint.isNotEmpty) {
    final matches =
        registry.processIdsByNameLower[processNameHint.toLowerCase()] ?? const <String>[];
    if (matches.isEmpty) {
      return _ResolvedUncertaintyParameter(
        error:
            'Process name "$processNameHint" does not exist in the current model.',
      );
    }
    if (matches.length > 1) {
      return _ResolvedUncertaintyParameter(
        error:
            'Parameter "$name" is ambiguous because process name "$processNameHint" matches multiple processes. Provide process_id.',
      );
    }
    resolvedProcessId = matches.first;
  }

  if (resolvedProcessId == null) {
    final matches = <_UncertaintyParameterMeta>[];
    for (final table in registry.processById.values) {
      final meta = table[key];
      if (meta != null) {
        matches.add(meta);
      }
    }
    if (matches.isEmpty) {
      return _ResolvedUncertaintyParameter(
        error: 'Process parameter "$name" does not exist in the current model.',
      );
    }
    if (matches.length > 1) {
      final labels = matches
          .map(
            (item) => item.processName?.trim().isNotEmpty == true
                ? '${item.processName} (${item.processId})'
                : (item.processId ?? item.name),
          )
          .toList()
        ..sort();
      return _ResolvedUncertaintyParameter(
        error:
            'Parameter "$name" is ambiguous across multiple processes: ${labels.join(', ')}. Provide process context.',
      );
    }
    return _ResolvedUncertaintyParameter(meta: matches.first);
  }

  final table = registry.processById[resolvedProcessId];
  final meta = table?[key];
  if (meta == null) {
    return _ResolvedUncertaintyParameter(
      error:
          'Process parameter "$name" does not exist for process "$resolvedProcessId".',
    );
  }
  return _ResolvedUncertaintyParameter(meta: meta);
}

String? _resolveRegistryProcessId(
  _UncertaintyParameterRegistry registry,
  String raw,
) {
  final needle = raw.trim();
  if (needle.isEmpty) return null;
  for (final processId in registry.processById.keys) {
    if (processId.toLowerCase() == needle.toLowerCase()) {
      return processId;
    }
  }
  final matches = registry.processIdsByNameLower[needle.toLowerCase()];
  if (matches == null || matches.isEmpty) return null;
  if (matches.length == 1) return matches.first;
  return null;
}
