import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../newhome/lca_models.dart';
import 'goal_seek_report_exporter.dart';
import 'openlca_calculation_target_selector.dart';
import 'pdf_download.dart';

class GoalSeekPage extends StatefulWidget {
  final List<ProcessNode> processes;
  final ParameterSet? parameters;
  final Map<String, dynamic>? openLcaProductSystem;
  final Map<String, dynamic>? initialCalculationTarget;
  final Map<String, dynamic>? initialImpactMethod;
  final String? userPrompt;
  final Map<String, dynamic>? initialPayload;
  final bool autoStart;

  const GoalSeekPage({
    super.key,
    required this.processes,
    required this.parameters,
    this.openLcaProductSystem,
    this.initialCalculationTarget,
    this.initialImpactMethod,
    this.userPrompt,
    this.initialPayload,
    this.autoStart = false,
  });

  @override
  State<GoalSeekPage> createState() => _GoalSeekPageState();
}

class _GoalSeekPageState extends State<GoalSeekPage> {
  static const double _displayZeroTolerance = 1e-12;
  static const String _openLcaBackendBaseUrl = String.fromEnvironment(
    'OPENLCA_BACKEND_BASE_URL',
    defaultValue: 'http://localhost:8001',
  );
  static const String _openLcaIpcUrl = String.fromEnvironment(
    'OPENLCA_IPC_URL',
    defaultValue: 'http://localhost:8080',
  );

  final TextEditingController _parameterSearchCtrl = TextEditingController();
  final TextEditingController _impactSearchCtrl = TextEditingController();
  final List<_GoalVariable> _variables = [];
  final List<_GoalConstraint> _constraints = [];
  final List<Map<String, dynamic>> _clientEvents = [];
  static const int _maxVisibleExecutionEvents = 8;
  static const int _maxVisibleEvaluationRows = 40;

  bool _isLoadingImpacts = false;
  bool _isStarting = false;
  bool _isExportingPdf = false;
  bool _isExportingCsv = false;
  bool _showSetupEditor = false;
  String? _impactError;
  String? _jobId;
  Timer? _pollTimer;
  Map<String, dynamic>? _job;
  Map<String, dynamic>? _activePayload;
  Map<String, dynamic>? _selectedCalculationTarget;
  List<Map<String, dynamic>> _impactMethods = const [];
  _ImpactChoice? _objective;
  String _goalMode = 'parameter';
  String _objectiveDirection = 'minimize';
  int _parameterObjectiveIndex = 0;

  @override
  void initState() {
    super.initState();
    _parameterSearchCtrl.addListener(() => setState(() {}));
    _impactSearchCtrl.addListener(() => setState(() {}));
    if (widget.initialCalculationTarget != null) {
      _selectedCalculationTarget = _deepCopyMap(widget.initialCalculationTarget!);
    }
    final payload = widget.initialPayload;
    if (payload != null) {
      _showSetupEditor = false;
      _activePayload = _deepCopyMap(payload);
      _selectedCalculationTarget ??= _calculationTargetFromPayload(payload);
      _applyPayloadToSetup(payload);
      _appendClientEvent(
        'llm_handoff',
        'Received optimization payload from the LLM and hydrated the goal-seek page.',
        details: {
          'mode': payload['mode'],
          'product_system_id': payload['product_system_id'],
          'impact_method_id': payload['impact_method_id'],
          'variable_count': ((payload['variables'] as List?) ?? const []).length,
          'constraint_count': ((payload['constraints'] as List?) ?? const []).length,
        },
      );
    } else {
      _showSetupEditor = true;
    }
    if (widget.autoStart && widget.initialPayload != null) {
      _appendClientEvent(
        'auto_start',
        'Auto-start is enabled; submitting the hydrated optimization payload.',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startGoalSeekWithPayload(widget.initialPayload!);
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _parameterSearchCtrl.dispose();
    _impactSearchCtrl.dispose();
    for (final variable in _variables) {
      variable.dispose();
    }
    for (final constraint in _constraints) {
      constraint.dispose();
    }
    super.dispose();
  }

  void _guardWebMixedContent(Uri uri) {
    if (kIsWeb && Uri.base.scheme == 'https' && uri.scheme == 'http') {
      throw Exception(
        'The app is running over HTTPS but the OpenLCA backend URL is HTTP.',
      );
    }
  }

  String _processNameForId(String processId) {
    final needle = processId.trim().toLowerCase();
    for (final process in widget.processes) {
      if (process.id.trim().toLowerCase() == needle) {
        return process.name.trim().isEmpty ? process.id : process.name;
      }
    }
    return processId;
  }

  List<_ParameterChoice> _parameterChoices() {
    final params = widget.parameters;
    if (params == null || params.isEmpty) return const [];

    final out = <_ParameterChoice>[
      for (final parameter in params.global)
        if (parameter.value != null)
          _ParameterChoice(
            label: 'Global: ${parameter.name} = ${parameter.value}${_unitSuffix(parameter.unit)}',
            field: 'parameters.global.${parameter.name}',
            processId: null,
            initial: parameter.value!,
          ),
      for (final entry in params.perProcess.entries)
        for (final parameter in entry.value)
          if (parameter.value != null)
            _ParameterChoice(
              label:
                  '${_processNameForId(entry.key)}: ${parameter.name} = ${parameter.value}${_unitSuffix(parameter.unit)}',
              field: 'parameters.process.${parameter.name}',
              processId: entry.key,
              initial: parameter.value!,
            ),
    ];
    out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return out;
  }

  String _unitSuffix(String? unit) {
    final value = unit?.trim() ?? '';
    return value.isEmpty ? '' : ' $value';
  }

  List<_ParameterChoice> _visibleParameterChoices() {
    final query = _parameterSearchCtrl.text.trim().toLowerCase();
    final selectedKeys = _variables.map((v) => v.key).toSet();
    return _parameterChoices()
        .where((choice) => !selectedKeys.contains(choice.key))
        .where((choice) => query.isEmpty || choice.label.toLowerCase().contains(query))
        .take(10)
        .toList();
  }

  String _impactMethodName(Map<String, dynamic> method) {
    final name = (method['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final id = (method['id'] ?? '').toString().trim();
    return id.isEmpty ? 'Unnamed impact method' : id;
  }

  List<_ImpactChoice> _impactChoices() {
    final out = <_ImpactChoice>[];
    for (final method in _impactMethods) {
      final methodId = (method['id'] ?? '').toString().trim();
      final methodName = _impactMethodName(method);
      final rawCategories = method['impact_categories'];
      if (rawCategories is List && rawCategories.isNotEmpty) {
        for (final raw in rawCategories) {
          if (raw is! Map) continue;
          final category = Map<String, dynamic>.from(raw);
          final impactCategoryId = (category['id'] ?? '').toString().trim();
          final name = (category['name'] ?? '').toString().trim();
          if (name.isEmpty) continue;
          out.add(
            _ImpactChoice(
              methodId: methodId,
              methodName: methodName,
              indicator: name,
              impactCategoryId: impactCategoryId,
            ),
          );
        }
      } else {
        out.add(
          _ImpactChoice(
            methodId: methodId,
            methodName: methodName,
            indicator: methodName,
            impactCategoryId: '',
          ),
        );
      }
    }
    out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return out;
  }

  List<_ImpactChoice> _visibleImpactChoices() {
    final query = _impactSearchCtrl.text.trim().toLowerCase();
    return _impactChoices()
        .where((choice) => query.isEmpty || choice.label.toLowerCase().contains(query))
        .take(10)
        .toList();
  }

  Map<String, dynamic> _deepCopyMap(Map<String, dynamic> input) {
    final decoded = jsonDecode(jsonEncode(input));
    return decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);
  }

  String get _goalModeLabel =>
      _goalMode == 'parameter'
          ? (_objectiveDirection == 'minimize' &&
                  _variables.length == 1 &&
                  _constraints.length == 1
              ? 'Parameter threshold'
              : 'Constrained optimisation')
          : 'Constrained optimisation';

  bool get _hasGeneratedPayload => widget.initialPayload != null;

  String _parameterLabelFromField(String field, String? processId, double initial) {
    if (field.startsWith('parameters.global.')) {
      final name = field.substring('parameters.global.'.length).trim();
      return 'Global: $name = ${initial.toStringAsPrecision(6)}';
    }
    if (field.startsWith('parameters.process.')) {
      final name = field.substring('parameters.process.'.length).trim();
      final processName = _processNameForId(processId ?? '');
      return '$processName: $name = ${initial.toStringAsPrecision(6)}';
    }
    return '$field = ${initial.toStringAsPrecision(6)}';
  }

  _ParameterChoice _parameterChoiceFromPayload(Map<String, dynamic> rawVariable) {
    final field = (rawVariable['field'] ?? '').toString().trim();
    final processIdRaw = (rawVariable['process_id'] ?? '').toString().trim();
    final processId = processIdRaw.isEmpty ? null : processIdRaw;
    for (final choice in _parameterChoices()) {
      if (choice.field == field && choice.processId == processId) {
        final initial =
            (rawVariable['initial'] as num?)?.toDouble() ?? choice.initial;
        if ((choice.initial - initial).abs() < 1e-9) return choice;
        return _ParameterChoice(
          label: choice.label,
          field: choice.field,
          processId: choice.processId,
          initial: initial,
        );
      }
    }
    final initial =
        (rawVariable['initial'] as num?)?.toDouble() ??
        (rawVariable['lower'] as num?)?.toDouble() ??
        (rawVariable['upper'] as num?)?.toDouble() ??
        0.0;
    return _ParameterChoice(
      label: _parameterLabelFromField(field, processId, initial),
      field: field,
      processId: processId,
      initial: initial,
    );
  }

  _ImpactChoice _impactChoiceFromPayload({
    required String indicator,
    required String impactCategoryId,
    required String methodId,
    required String methodName,
  }) {
    final fallbackMethodName =
        methodName.trim().isNotEmpty
            ? methodName.trim()
            : (methodId.trim().isNotEmpty ? methodId.trim() : 'Selected LCIA method');
    for (final choice in _impactChoices()) {
      final sameId =
          impactCategoryId.isNotEmpty &&
          choice.impactCategoryId.trim().toLowerCase() ==
              impactCategoryId.trim().toLowerCase();
      final sameIndicator =
          choice.indicator.trim().toLowerCase() == indicator.trim().toLowerCase();
      final sameMethod =
          methodId.isEmpty ||
          choice.methodId.trim().toLowerCase() == methodId.trim().toLowerCase();
      if ((sameId || sameIndicator) && sameMethod) {
        return choice;
      }
    }
    return _ImpactChoice(
      methodId: methodId,
      methodName: fallbackMethodName,
      indicator: indicator.trim().isEmpty ? impactCategoryId : indicator,
      impactCategoryId: impactCategoryId,
    );
  }

  void _disposeCurrentSetupState() {
    for (final variable in _variables) {
      variable.dispose();
    }
    for (final constraint in _constraints) {
      constraint.dispose();
    }
    _variables.clear();
    _constraints.clear();
    _objective = null;
  }

  void _applyPayloadToSetup(Map<String, dynamic> payload) {
    _disposeCurrentSetupState();
    final objective = payload['objective'];
    final mode = (payload['mode'] ?? '').toString().trim();
    final objectiveType = objective is Map
        ? (objective['type'] ?? '').toString().trim()
        : '';
    if (mode == 'indicator_optimization') {
      _goalMode = 'indicator';
    } else if (mode == 'constrained_optimization' && objectiveType == 'indicator') {
      _goalMode = 'indicator';
    } else if (mode == 'constrained_optimization' && objectiveType == 'parameter') {
      _goalMode = 'parameter';
    } else if (mode == 'parameter_threshold') {
      _goalMode = 'parameter';
    } else if (objectiveType == 'indicator') {
      _goalMode = 'indicator';
    } else {
      _goalMode = 'parameter';
    }

    if (objective is Map<String, dynamic>) {
      final direction = (objective['direction'] ?? '').toString().trim();
      if (direction == 'minimize' || direction == 'maximize') {
        _objectiveDirection = direction;
      }
    }

    final variablesAny = payload['variables'];
    if (variablesAny is List) {
      for (final raw in variablesAny.whereType<Map>()) {
        final variable = Map<String, dynamic>.from(raw);
        final choice = _parameterChoiceFromPayload(variable);
        final lower =
            (variable['lower'] as num?)?.toDouble() ?? choice.initial;
        final upper =
            (variable['upper'] as num?)?.toDouble() ?? choice.initial;
        _variables.add(
          _GoalVariable(
            choice: choice,
            lower: lower,
            upper: upper,
          ),
        );
      }
    }

    final methodId = (payload['impact_method_id'] ?? '').toString().trim();
    final methodName = (payload['impact_method_name'] ?? '').toString().trim();

    final constraintsAny = payload['constraints'];
    if (constraintsAny is List) {
      for (final raw in constraintsAny.whereType<Map>()) {
        final constraint = Map<String, dynamic>.from(raw);
        final choice = _impactChoiceFromPayload(
          indicator: (constraint['indicator'] ?? '').toString(),
          impactCategoryId:
              (constraint['impact_category_id'] ?? '').toString().trim(),
          methodId:
              (constraint['impact_method_id'] ?? methodId).toString().trim(),
          methodName:
              (constraint['impact_method_name'] ?? methodName).toString().trim(),
        );
        _constraints.add(
          _GoalConstraint(
            choice: choice,
            operator: (constraint['operator'] ?? '<=').toString(),
            target:
                (constraint['target'] as num?)?.toDouble() ?? 0,
          ),
        );
      }
    }

    if (objective is Map) {
      final objectiveMap = objective.cast<String, dynamic>();
      if (_goalMode == 'parameter') {
        _parameterObjectiveIndex =
            (((objectiveMap['variable_index'] as num?)?.toInt() ?? 0).clamp(
                  0,
                  _variables.isEmpty ? 0 : _variables.length - 1,
                )
                as num)
                .toInt();
      } else {
        final objectiveIndicator =
            (objectiveMap['indicator'] ?? '').toString();
        final objectiveCategoryId =
            (objectiveMap['impact_category_id'] ?? '').toString().trim();
        final objectiveMethodId =
            (objectiveMap['impact_method_id'] ?? methodId).toString().trim();
        final objectiveMethodName =
            (objectiveMap['impact_method_name'] ?? methodName)
                .toString()
                .trim();
        final match = _constraints.where((constraint) {
          final sameId =
              objectiveCategoryId.isNotEmpty &&
              constraint.choice.impactCategoryId.trim().toLowerCase() ==
                  objectiveCategoryId.toLowerCase();
          final sameIndicator =
              constraint.choice.indicator.trim().toLowerCase() ==
              objectiveIndicator.trim().toLowerCase();
          final sameMethod =
              objectiveMethodId.isEmpty ||
              constraint.choice.methodId.trim().toLowerCase() ==
                  objectiveMethodId.toLowerCase();
          return (sameId || sameIndicator) && sameMethod;
        });
        if (match.isNotEmpty) {
          _objective = match.first.choice;
        } else {
          _objective = _impactChoiceFromPayload(
            indicator: objectiveIndicator,
            impactCategoryId: objectiveCategoryId,
            methodId: objectiveMethodId,
            methodName: objectiveMethodName,
          );
        }
      }
    }
  }

  void _appendClientEvent(
    String stage,
    String message, {
    Map<String, dynamic>? details,
  }) {
    _clientEvents.add({
      'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
      'stage': stage,
      'message': message,
      'source': 'ui',
      if (details != null && details.isNotEmpty) 'details': details,
    });
  }

  List<Map<String, dynamic>> _jobEvents() {
    final raw = _job?['events'];
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
  }

  List<Map<String, dynamic>> _executionEvents() {
    final merged = <Map<String, dynamic>>[
      ..._clientEvents.map((event) => Map<String, dynamic>.from(event)),
      ..._jobEvents(),
    ];
    merged.sort((a, b) {
      final left = ((a['timestamp'] as num?) ?? 0).toDouble();
      final right = ((b['timestamp'] as num?) ?? 0).toDouble();
      return left.compareTo(right);
    });
    return merged;
  }

  String _formatEventTime(dynamic rawTimestamp) {
    final seconds = (rawTimestamp as num?)?.toDouble();
    if (seconds == null || !seconds.isFinite) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(
      (seconds * 1000).round(),
      isUtc: false,
    );
    final two = (int value) => value.toString().padLeft(2, '0');
    return '${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }

  String _formatNumber(dynamic value) {
    final number = (value as num?)?.toDouble();
    if (number == null || !number.isFinite) return value?.toString() ?? 'n/a';
    if (number.abs() <= _displayZeroTolerance) return '0';
    final absValue = number.abs();
    if (absValue >= 1000 || absValue < 0.001) {
      return number.toStringAsExponential(3);
    }
    return number.toStringAsPrecision(6);
  }

  String _formatCsvNumber(dynamic value) {
    final number = (value as num?)?.toDouble();
    if (number == null || !number.isFinite) return value?.toString() ?? 'n/a';
    if (number == 0) return '0';
    final absValue = number.abs();
    if (absValue >= 1e9 || absValue < 1e-9) {
      return number.toStringAsExponential(10);
    }
    return number.toStringAsPrecision(10);
  }

  String _objectiveSummary() {
    if (_goalMode == 'parameter') {
      if (_variables.isEmpty) return 'No parameter objective selected';
      final variable = _variables[_clampedParameterObjectiveIndex()];
      return _objectiveDirection == 'maximize'
          ? 'Maximise ${variable.choice.field}'
          : 'Minimise ${variable.choice.field}';
    }
    if (_objective == null) return 'No indicator objective selected';
    final direction =
        _objectiveDirection == 'maximize' ? 'Maximize' : 'Minimize';
    return '$direction ${_objective!.label}';
  }

  String _parameterSummary(Map<String, dynamic> parameter) {
    final field = (parameter['field'] ?? '').toString().trim();
    final processIdRaw = (parameter['process_id'] ?? '').toString().trim();
    final processId = processIdRaw.isEmpty ? null : processIdRaw;
    final value = _formatNumber(parameter['value']);
    if (field.startsWith('parameters.global.')) {
      final name = field.substring('parameters.global.'.length).trim();
      return '$name = $value';
    }
    if (field.startsWith('parameters.process.')) {
      final name = field.substring('parameters.process.'.length).trim();
      return '${_processNameForId(processId ?? '')}: $name = $value';
    }
    return '$field = $value';
  }

  String _constraintSummary(Map<String, dynamic> constraint) {
    final methodName = (constraint['impact_method_name'] ?? '').toString().trim();
    final indicator = (constraint['indicator'] ?? '').toString().trim();
    final operator = (constraint['operator'] ?? '').toString().trim();
    final target = _formatNumber(constraint['target']);
    final value = _formatNumber(constraint['value']);
    final satisfied = constraint['satisfied'] == true ? 'ok' : 'miss';
    final qualifiedIndicator =
        methodName.isEmpty ? indicator : '$methodName / $indicator';
    return '$qualifiedIndicator $operator $target; got $value ($satisfied)';
  }

  String _constraintDisplayName(Map<String, dynamic> constraint) {
    final method = (constraint['impact_method_name'] ?? '').toString().trim();
    final indicator = (constraint['indicator'] ?? '').toString().trim();
    if (method.isEmpty) return indicator;
    return '$method / $indicator';
  }

  Future<void> _loadImpactMethods() async {
    if (_isLoadingImpacts) return;
    setState(() {
      _isLoadingImpacts = true;
      _impactError = null;
    });
    try {
      final uri = Uri.parse('$_openLcaBackendBaseUrl/openlca/impact-methods')
          .replace(queryParameters: {'ipc_url': _openLcaIpcUrl});
      _guardWebMixedContent(uri);
      final response = await http.get(uri, headers: const {'Accept': 'application/json'});
      if (response.statusCode != 200) {
        throw Exception('OpenLCA backend error ${response.statusCode}: ${response.body}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('OpenLCA backend returned invalid JSON.');
      }
      final raw = decoded['impact_methods'];
      final methods = raw is List
          ? raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() => _impactMethods = methods);
    } catch (e) {
      if (!mounted) return;
      setState(() => _impactError = e.toString());
    } finally {
      if (mounted) setState(() => _isLoadingImpacts = false);
    }
  }

  void _addVariable(_ParameterChoice choice) {
    final base = choice.initial.abs() > 0 ? choice.initial.abs() : 1.0;
    setState(() {
      _variables.add(
        _GoalVariable(
          choice: choice,
          lower: choice.initial - base * 0.5,
          upper: choice.initial + base * 0.5,
        ),
      );
    });
  }

  void _addConstraint(_ImpactChoice choice) {
    setState(() {
      _constraints.add(_GoalConstraint(choice: choice));
      _objective ??= choice;
    });
  }

  Map<String, dynamic> _buildStartPayload() {
    final productSystemId =
        (widget.openLcaProductSystem?['id'] ?? '').toString().trim();
    final methodId = (_selectedImpactMethodId()).trim();
    final methodName = _selectedImpactMethodName().trim();
    final selectedTarget = _selectedCalculationTarget;
    final mode = _goalMode == 'parameter' &&
            _objectiveDirection == 'minimize' &&
            _variables.length == 1 &&
            _constraints.length == 1
        ? 'parameter_threshold'
        : 'constrained_optimization';
    return {
      'mode': mode,
      'product_system_id': productSystemId,
      'prompt': widget.userPrompt ?? '',
      'target_type':
          (selectedTarget?['target_type'] ?? 'product_system').toString().trim(),
      if ((selectedTarget?['process_id'] ?? '').toString().trim().isNotEmpty)
        'process_id': (selectedTarget?['process_id'] ?? '').toString().trim(),
      'ipc_url': _openLcaIpcUrl,
      if (methodId.isNotEmpty) 'impact_method_id': methodId,
      if (methodName.isNotEmpty) 'impact_method_name': methodName,
      'variables': [
        for (final variable in _variables)
          {
            'field': variable.choice.field,
            if (variable.choice.processId != null) 'process_id': variable.choice.processId,
            'initial': variable.choice.initial,
            'lower': double.tryParse(variable.lowerCtrl.text.trim()) ?? variable.lower,
            'upper': double.tryParse(variable.upperCtrl.text.trim()) ?? variable.upper,
          },
      ],
      'constraints': [
        for (final constraint in _constraints)
          {
            'indicator': constraint.choice.indicator,
            if (constraint.choice.methodId.isNotEmpty)
              'impact_method_id': constraint.choice.methodId,
            if (constraint.choice.methodName.isNotEmpty)
              'impact_method_name': constraint.choice.methodName,
            if (constraint.choice.impactCategoryId.isNotEmpty)
              'impact_category_id': constraint.choice.impactCategoryId,
            'operator': constraint.operator,
            'target': double.tryParse(constraint.targetCtrl.text.trim()) ?? 0.0,
          },
      ],
      'objective': _buildObjectivePayload(),
      'n': 256,
      'iters': 4,
      'sampling_method': 'sobol',
    };
  }

  Map<String, dynamic> _normalizeGoalSeekPayload(Map<String, dynamic> payload) {
    final next = _deepCopyMap(payload);
    final normalizedVariables = <Map<String, dynamic>>[];
    final variablesRaw = next['variables'];
    if (variablesRaw is List) {
      for (final raw in variablesRaw.whereType<Map>()) {
        final variable = Map<String, dynamic>.from(raw);
        final choice = _parameterChoiceFromPayload(variable);
        variable['initial'] =
            (variable['initial'] as num?)?.toDouble() ?? choice.initial;
        normalizedVariables.add(variable);
      }
      next['variables'] = normalizedVariables;
    }
    final objectiveRaw = next['objective'];
    final objective = objectiveRaw is Map
        ? Map<String, dynamic>.from(objectiveRaw)
        : <String, dynamic>{};
    final objectiveType = (objective['type'] ?? '').toString().trim();
    final direction = (objective['direction'] ?? '').toString().trim();
    if (objectiveType == 'parameter') {
      final variableCount = ((next['variables'] as List?) ?? const []).length;
      final constraintCount = ((next['constraints'] as List?) ?? const []).length;
      next['mode'] = direction == 'minimize' &&
              variableCount == 1 &&
              constraintCount == 1
          ? 'parameter_threshold'
          : 'constrained_optimization';
    } else if (objectiveType == 'indicator') {
      next['mode'] = 'constrained_optimization';
    }
    final rawN = next['n'];
    final normalizedN = rawN is num ? rawN.toInt() : int.tryParse('$rawN');
    next['n'] = normalizedN == null ? 256 : normalizedN.clamp(1, 512);
    final rawIters = next['iters'];
    final normalizedIters =
        rawIters is num ? rawIters.toInt() : int.tryParse('$rawIters');
    next['iters'] = normalizedIters == null ? 4 : normalizedIters.clamp(1, 8);
    final samplingMethod = (next['sampling_method'] ?? '').toString().trim();
    next['sampling_method'] =
        samplingMethod.isEmpty ? 'sobol' : samplingMethod;
    final prompt = (next['prompt'] ?? '').toString();
    if (prompt.trim().isEmpty && (widget.userPrompt ?? '').trim().isNotEmpty) {
      next['prompt'] = widget.userPrompt;
    }
    return next;
  }

  String _selectedImpactMethodId() {
    final ids = <String>{
      if (_objective?.methodId.trim().isNotEmpty == true)
        _objective!.methodId.trim(),
      for (final constraint in _constraints)
        if (constraint.choice.methodId.trim().isNotEmpty)
          constraint.choice.methodId.trim(),
    };
    if (ids.length == 1) return ids.first;
    final initialId = (widget.initialImpactMethod?['id'] ?? '').toString().trim();
    if (ids.isEmpty && initialId.isNotEmpty) return initialId;
    return '';
  }

  String _selectedImpactMethodName() {
    final names = <String>{
      if (_objective?.methodName.trim().isNotEmpty == true)
        _objective!.methodName.trim(),
      for (final constraint in _constraints)
        if (constraint.choice.methodName.trim().isNotEmpty)
          constraint.choice.methodName.trim(),
    };
    if (names.length == 1) return names.first;
    final initialName =
        (widget.initialImpactMethod?['name'] ?? '').toString().trim();
    if (names.isEmpty && initialName.isNotEmpty) return initialName;
    return (_activePayload?['impact_method_name'] ?? '').toString().trim();
  }

  String _selectedImpactMethodSummary() {
    final names = <String>{
      if (_objective?.methodName.trim().isNotEmpty == true)
        _objective!.methodName.trim(),
      for (final constraint in _constraints)
        if (constraint.choice.methodName.trim().isNotEmpty)
          constraint.choice.methodName.trim(),
    };
    if (names.isEmpty) {
      final fallback = _selectedImpactMethodName();
      return fallback.isEmpty ? 'Not resolved' : fallback;
    }
    if (names.length == 1) return names.first;
    return names.join(', ');
  }

  Map<String, dynamic> _buildObjectivePayload() {
    if (_goalMode == 'parameter') {
      final index = _clampedParameterObjectiveIndex();
      return {
        'type': 'parameter',
        'variable_index': index,
        'direction': _objectiveDirection,
      };
    }
    return {
      'type': 'indicator',
      if (_objective?.methodId.isNotEmpty == true)
        'impact_method_id': _objective!.methodId,
      if (_objective?.methodName.isNotEmpty == true)
        'impact_method_name': _objective!.methodName,
      'indicator': _objective?.indicator,
      if (_objective?.impactCategoryId.isNotEmpty == true)
        'impact_category_id': _objective!.impactCategoryId,
      'direction': _objectiveDirection,
    };
  }

  int _clampedParameterObjectiveIndex() {
    if (_variables.isEmpty) return 0;
    if (_parameterObjectiveIndex < 0) return 0;
    if (_parameterObjectiveIndex >= _variables.length) return _variables.length - 1;
    return _parameterObjectiveIndex;
  }

  Future<void> _startGoalSeek() async {
    final productSystemId =
        (widget.openLcaProductSystem?['id'] ?? '').toString().trim();
    if (productSystemId.isEmpty) {
      _showSnack('Import/select an OpenLCA product system before goal seek.');
      return;
    }
    if (_variables.isEmpty) {
      _showSnack('Add at least one variable parameter.');
      return;
    }
    if (_goalMode == 'parameter' &&
        _objectiveDirection == 'minimize' &&
        _constraints.isEmpty) {
      _showSnack('Add at least one LCIA constraint for parameter-threshold search.');
      return;
    }
    if (_goalMode == 'indicator' && _constraints.isEmpty && _objective == null) {
      _showSnack('Add at least one indicator constraint or indicator objective.');
      return;
    }

    await _startGoalSeekWithPayload(_buildStartPayload());
  }

  Future<void> _startGoalSeekWithPayload(Map<String, dynamic> payload) async {
    final selectedPayload = await _withSelectedCalculationTarget(payload);
    if (selectedPayload == null) return;
    final normalizedPayload = _normalizeGoalSeekPayload(selectedPayload);
    _applyPayloadToSetup(normalizedPayload);
    setState(() {
      _isStarting = true;
      _job = null;
      _jobId = null;
      _activePayload = normalizedPayload;
    });
    _appendClientEvent(
      'submit',
      'Submitting optimization run to the OpenLCA optimizer.',
      details: {
        'mode': normalizedPayload['mode'],
        'product_system_id': normalizedPayload['product_system_id'],
        'impact_method_id': normalizedPayload['impact_method_id'],
        'variable_count': ((normalizedPayload['variables'] as List?) ?? const []).length,
        'constraint_count': ((normalizedPayload['constraints'] as List?) ?? const []).length,
        'objective': normalizedPayload['objective'],
      },
    );
    try {
      final uri = Uri.parse('$_openLcaBackendBaseUrl/openlca/goal-seek/start');
      _guardWebMixedContent(uri);
      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          ...normalizedPayload,
          'ipc_url': (normalizedPayload['ipc_url'] ?? _openLcaIpcUrl).toString(),
        }),
      );
      if (response.statusCode != 200) {
        throw Exception('Goal seek start failed ${response.statusCode}: ${response.body}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Goal seek start returned invalid JSON.');
      }
      final jobId = (decoded['job_id'] ?? '').toString();
      if (jobId.isEmpty) throw Exception('Goal seek did not return a job id.');
      setState(() => _jobId = jobId);
      _appendClientEvent(
        'accepted',
        'Optimizer accepted the run and returned a job id.',
        details: {'job_id': jobId},
      );
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollJob());
      await _pollJob();
    } catch (e) {
      _appendClientEvent(
        'submit_failed',
        'Failed to start optimization.',
        details: {'error': e.toString()},
      );
      _showSnack('Goal seek failed to start: $e');
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<void> _pollJob() async {
    final jobId = _jobId;
    if (jobId == null || jobId.isEmpty) return;
    try {
      final uri = Uri.parse('$_openLcaBackendBaseUrl/openlca/goal-seek/$jobId');
      _guardWebMixedContent(uri);
      final response = await http.get(uri, headers: const {'Accept': 'application/json'});
      if (response.statusCode != 200) {
        throw Exception('Polling failed ${response.statusCode}: ${response.body}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return;
      if (!mounted) return;
      setState(() => _job = decoded);
      final status = (decoded['status'] ?? '').toString();
      if (status == 'completed' || status == 'failed' || status == 'cancelled') {
        _pollTimer?.cancel();
      }
    } catch (e) {
      _appendClientEvent(
        'poll_failed',
        'Polling the optimizer job failed.',
        details: {'error': e.toString()},
      );
      _showSnack('Goal seek polling error: $e');
      _pollTimer?.cancel();
    }
  }

  Future<void> _cancelJob() async {
    final jobId = _jobId;
    if (jobId == null) return;
    _appendClientEvent(
      'cancel_requested',
      'Cancellation requested for the optimizer job.',
      details: {'job_id': jobId},
    );
    final uri = Uri.parse('$_openLcaBackendBaseUrl/openlca/goal-seek/$jobId/cancel');
    await http.post(uri, headers: const {'Accept': 'application/json'});
    await _pollJob();
  }

  void _showPayload() {
    final payload = _normalizeGoalSeekPayload(
      _activePayload ?? _buildStartPayload(),
    );
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Optimization payload'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(payload),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Map<String, dynamic>? _calculationTargetFromPayload(Map<String, dynamic> payload) {
    final targetType = (payload['target_type'] ?? '').toString().trim();
    final processId = (payload['process_id'] ?? '').toString().trim();
    if (targetType.isEmpty && processId.isEmpty) return null;
    return {
      'target_type': targetType.isEmpty ? 'product_system' : targetType,
      if (processId.isNotEmpty) 'process_id': processId,
    };
  }

  Future<Map<String, dynamic>?> _withSelectedCalculationTarget(
    Map<String, dynamic> payload,
  ) async {
    final productSystem = widget.openLcaProductSystem;
    final productSystemId = (productSystem?['id'] ?? '').toString().trim();
    if (productSystem == null || productSystemId.isEmpty) {
      _showSnack('Import/select an OpenLCA product system before goal seek.');
      return null;
    }

    final selection = await showOpenLcaCalculationTargetDialog(
      context: context,
      backendBaseUrl: _openLcaBackendBaseUrl,
      ipcUrl: _openLcaIpcUrl,
      productSystem: productSystem,
      currentSelection:
          _selectedCalculationTarget ?? _calculationTargetFromPayload(payload),
    );
    if (!mounted || selection == null) return null;

    setState(() => _selectedCalculationTarget = Map<String, dynamic>.from(selection));
    final next = _deepCopyMap(payload);
    next['target_type'] = (selection['target_type'] ?? 'product_system')
        .toString()
        .trim();
    final processId = (selection['process_id'] ?? '').toString().trim();
    if (processId.isNotEmpty) {
      next['process_id'] = processId;
    } else {
      next.remove('process_id');
    }
    return next;
  }

  List<Map<String, dynamic>> _evaluations() {
    final raw = _job?['evaluations'];
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
  }

  Map<String, dynamic>? _best() {
    final raw = _job?['best'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  Future<void> _exportCsv() async {
    if (_job == null || _isExportingCsv) return;
    setState(() => _isExportingCsv = true);
    try {
      final bytes = Uint8List.fromList(utf8.encode(_buildCsv()));
      await downloadFile(
        bytes: bytes,
        filename: 'goal_seek_results.csv',
        mimeType: 'text/csv;charset=utf-8',
      );
    } finally {
      if (mounted) setState(() => _isExportingCsv = false);
    }
  }

  Future<void> _exportPdf() async {
    if (_job == null || _isExportingPdf) return;
    setState(() => _isExportingPdf = true);
    try {
      final bytes = await _buildPdf();
      await downloadPdf(bytes: bytes, filename: 'goal_seek_report.pdf');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Goal-seek PDF exported as goal_seek_report.pdf'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Goal-seek PDF export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  String _csvEscape(String value) {
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final escaped = normalized.replaceAll('"', '""');
    if (escaped.contains(',') || escaped.contains('"') || escaped.contains('\n')) {
      return '"$escaped"';
    }
    return escaped;
  }

  String _constraintColumnLabel(Map<String, dynamic> constraint) {
    return '${_constraintDisplayName(constraint)} '
        '${(constraint['operator'] ?? '').toString().trim()} '
        '${_formatCsvNumber(constraint['target'])}';
  }

  String _buildCsv() {
    final evaluations = _evaluations();
    final parameterLabels = <String>[];
    final constraintLabels = <String>[];
    final seenParameters = <String>{};
    final seenConstraints = <String>{};

    for (final evaluation in evaluations) {
      for (final rawParameter in ((evaluation['parameters'] as List?) ?? const []).whereType<Map>()) {
        final parameter = Map<String, dynamic>.from(rawParameter);
        final label = _parameterSummary(parameter).split(' = ').first.trim();
        if (seenParameters.add(label)) {
          parameterLabels.add(label);
        }
      }
      for (final rawConstraint in ((evaluation['constraints'] as List?) ?? const []).whereType<Map>()) {
        final constraint = Map<String, dynamic>.from(rawConstraint);
        final label = _constraintColumnLabel(constraint);
        if (seenConstraints.add(label)) {
          constraintLabels.add(label);
        }
      }
    }

    final header = <String>[
      'evaluation',
      'objective_label',
      'objective_value',
      'status',
      ...parameterLabels,
      for (final label in constraintLabels) '$label value',
      for (final label in constraintLabels) '$label status',
    ];
    final lines = <String>[header.map(_csvEscape).join(',')];

    for (final evaluation in evaluations) {
      final parameterValues = <String, String>{};
      final constraintValues = <String, String>{};
      final constraintStatuses = <String, String>{};

      for (final rawParameter in ((evaluation['parameters'] as List?) ?? const []).whereType<Map>()) {
        final parameter = Map<String, dynamic>.from(rawParameter);
        final label = _parameterSummary(parameter).split(' = ').first.trim();
        parameterValues[label] = _formatCsvNumber(parameter['value']);
      }
      for (final rawConstraint in ((evaluation['constraints'] as List?) ?? const []).whereType<Map>()) {
        final constraint = Map<String, dynamic>.from(rawConstraint);
        final label = _constraintColumnLabel(constraint);
        constraintValues[label] = _formatCsvNumber(constraint['value']);
        constraintStatuses[label] = constraint['satisfied'] == true ? 'pass' : 'miss';
      }

      final row = <String>[
        '#${evaluation['index'] ?? ''}',
        (evaluation['objective_label'] ?? '').toString(),
        _formatCsvNumber(evaluation['display_objective_value']),
        evaluation['feasible'] == true ? 'pass' : 'miss',
        for (final label in parameterLabels) parameterValues[label] ?? '',
        for (final label in constraintLabels) constraintValues[label] ?? '',
        for (final label in constraintLabels) constraintStatuses[label] ?? '',
      ];
      lines.add(row.map(_csvEscape).join(','));
    }

    return '${lines.join('\n')}\n';
  }

  String _exactUserPromptForExport() {
    final candidates = <dynamic>[
      _activePayload?['prompt'],
      widget.initialPayload?['prompt'],
      widget.userPrompt,
      _job?['request'] is Map ? (_job?['request'] as Map)['prompt'] : null,
    ];
    for (final candidate in candidates) {
      final text = candidate?.toString() ?? '';
      if (text.trim().isNotEmpty) return text;
    }
    return '';
  }

  Future<Uint8List> _buildPdf() async {
    final optimizer = _job?['optimizer'];
    final optimizerMethod = optimizer is Map
        ? (optimizer['method'] ?? '').toString().trim()
        : '';
    final toolName = optimizerMethod.isNotEmpty
        ? 'OpenLCA Goal Seek Optimizer ($optimizerMethod)'
        : 'OpenLCA Goal Seek Optimizer';
    final productSystemName =
        (widget.openLcaProductSystem?['name'] ?? '').toString().trim();
    return GoalSeekReportExporter.buildPdf(
      job: _job ?? const <String, dynamic>{},
      variables: [
        for (final variable in _variables)
          GoalSeekReportVariable(
            label: variable.choice.label,
            lower: variable.lowerCtrl.text.trim(),
            upper: variable.upperCtrl.text.trim(),
          ),
      ],
      constraints: [
        for (final constraint in _constraints)
          GoalSeekReportConstraint(
            label: _constraintDisplayName({
              'impact_method_name': constraint.choice.methodName,
              'indicator': constraint.choice.indicator,
            }),
            operator: constraint.operator,
            target: constraint.targetCtrl.text.trim(),
          ),
      ],
      productSystemName: productSystemName,
      toolName: toolName,
      goalModeLabel: _goalModeLabel,
      objectiveSummary: _objectiveSummary(),
      selectedImpactMethodSummary: _selectedImpactMethodSummary(),
      userPrompt: _exactUserPromptForExport(),
      parameterLabelBuilder: _parameterLabel,
      constraintLabelBuilder: _constraintColumnLabel,
      formatNumber: _formatCsvNumber,
      generatedAt: DateTime.now(),
    );
  }

  String _parameterLabel(Map<String, dynamic> parameter) {
    return _parameterSummary(parameter).split(' = ').first.trim();
  }

  @override
  Widget build(BuildContext context) {
    final status = (_job?['status'] ?? 'not started').toString();
    final evaluations = _evaluations();
    final best = _best();
    final error = (_job?['error'] ?? '').toString().trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Goal seek'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _job == null || _isExportingCsv ? null : _exportCsv,
            icon: _isExportingCsv
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.table_view),
          ),
          IconButton(
            tooltip: 'Export PDF',
            onPressed: _job == null || _isExportingPdf ? null : _exportPdf,
            icon: _isExportingPdf
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_hasGeneratedPayload) _buildGeneratedPlanCard(),
          if (!_hasGeneratedPayload || _showSetupEditor) ...[
            if (_hasGeneratedPayload) const SizedBox(height: 12),
            _buildSetupCard(),
          ],
          const SizedBox(height: 12),
          _buildRunCard(status, evaluations),
          if (error.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildErrorCard(error),
          ],
          if (evaluations.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildEvaluationTableCard(evaluations),
          ],
          if (_executionEvents().isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildActivityCard(),
          ],
          if (best != null) ...[
            const SizedBox(height: 12),
            _buildBestResultCard(best),
          ],
        ],
      ),
    );
  }

  Widget _buildGeneratedPlanCard() {
    final productName =
        (widget.openLcaProductSystem?['name'] ?? '').toString().trim();
    final methodName = _selectedImpactMethodSummary();
    final payload = _activePayload ?? widget.initialPayload;
    final selectedTarget =
        _selectedCalculationTarget ??
        _calculationTargetFromPayload(payload ?? const <String, dynamic>{});
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'LLM-generated optimization plan',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() => _showSetupEditor = !_showSetupEditor);
                  },
                  icon: Icon(
                    _showSetupEditor ? Icons.visibility_off : Icons.edit,
                  ),
                  label: Text(_showSetupEditor ? 'Hide editor' : 'Edit setup'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Product system: ${productName.isEmpty ? 'Not set' : productName}'),
            Text(
              'Calculation target: ${openLcaCalculationTargetLabel(selectedTarget).isEmpty ? 'Not set' : openLcaCalculationTargetLabel(selectedTarget)}',
            ),
            Text('Mode: $_goalModeLabel'),
            Text(
              'LCIA method: ${methodName.isEmpty ? 'Not resolved' : methodName}',
            ),
            Text('Objective: ${_objectiveSummary()}'),
            if (payload != null) ...[
              const SizedBox(height: 8),
              Text(
                'Variables: ${((payload['variables'] as List?) ?? const []).length}   '
                'Constraints: ${((payload['constraints'] as List?) ?? const []).length}',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSetupCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'parameter',
                  icon: Icon(Icons.tune),
                  label: Text('Parameter threshold'),
                ),
                ButtonSegment(
                  value: 'indicator',
                  icon: Icon(Icons.trending_down),
                  label: Text('Indicator optimisation'),
                ),
              ],
              selected: {_goalMode},
              onSelectionChanged: (values) {
                setState(() {
                  _goalMode = values.first;
                  if (_goalMode == 'parameter') {
                    _parameterObjectiveIndex = _clampedParameterObjectiveIndex();
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            const Text('Variables', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _parameterSearchCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.search),
                labelText: 'Search numeric parameters',
              ),
            ),
            const SizedBox(height: 8),
            for (final choice in _visibleParameterChoices())
              ListTile(
                dense: true,
                title: Text(choice.label),
                trailing: const Icon(Icons.add),
                onTap: () => _addVariable(choice),
              ),
            if (_variables.isNotEmpty) const Divider(),
            for (final variable in _variables)
              _VariableRow(
                variable: variable,
                onRemove: () => setState(() {
                  final index = _variables.indexOf(variable);
                  _variables.remove(variable);
                  if (index <= _parameterObjectiveIndex && _parameterObjectiveIndex > 0) {
                    _parameterObjectiveIndex -= 1;
                  }
                  if (_parameterObjectiveIndex >= _variables.length) {
                    _parameterObjectiveIndex = _variables.isEmpty ? 0 : _variables.length - 1;
                  }
                  variable.dispose();
                }),
              ),
            if (_goalMode == 'parameter' && _variables.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _clampedParameterObjectiveIndex(),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Parameter objective',
                ),
                items: [
                  for (var i = 0; i < _variables.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(_variables[i].choice.label),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _parameterObjectiveIndex = value);
                },
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text('Indicators', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  onPressed: _isLoadingImpacts ? null : _loadImpactMethods,
                  icon: const Icon(Icons.download),
                  label: const Text('Load'),
                ),
              ],
            ),
            if (_isLoadingImpacts) const LinearProgressIndicator(),
            if (_impactError != null)
              Text(_impactError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_impactMethods.isNotEmpty) ...[
              TextField(
                controller: _impactSearchCtrl,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search impact categories',
                ),
              ),
              const SizedBox(height: 8),
              for (final choice in _visibleImpactChoices())
                ListTile(
                  dense: true,
                  title: Text(choice.label),
                  trailing: const Icon(Icons.add),
                  onTap: () => _addConstraint(choice),
                ),
            ],
            if (_constraints.isNotEmpty) const Divider(),
            for (final constraint in _constraints)
              _ConstraintRow(
                constraint: constraint,
                canUseAsObjective: _goalMode == 'indicator',
                onObjective: () => setState(() => _objective = constraint.choice),
                onRemove: () => setState(() {
                  _constraints.remove(constraint);
                  if (_objective == constraint.choice) {
                    _objective = _constraints.isEmpty ? null : _constraints.first.choice;
                  }
                  constraint.dispose();
                }),
              ),
            if (_goalMode == 'indicator' && _objective != null) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _objectiveDirection,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Objective: ${_objective!.label}',
                ),
                items: const [
                  DropdownMenuItem(value: 'minimize', child: Text('Minimize')),
                  DropdownMenuItem(value: 'maximize', child: Text('Maximize')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _objectiveDirection = value);
                },
              ),
            ],
            if (_goalMode == 'parameter' && _variables.isNotEmpty) ...[
              const SizedBox(height: 8),
              const InputDecorator(
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Parameter threshold mode',
                ),
                child: Text('Minimum needed'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRunCard(String status, List<Map<String, dynamic>> evaluations) {
    final running = status == 'running' || status == 'queued' || _isStarting;
    final lastEvent = _executionEvents().isEmpty ? null : _executionEvents().last;
    final best = _best();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Run status',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Chip(label: Text('Status: $status')),
                Chip(label: Text('Mode: $_goalModeLabel')),
                Chip(label: Text('Evaluations: ${evaluations.length}')),
                if (best != null)
                  Chip(
                    label: Text(
                      'Best objective: ${_formatNumber(best['display_objective_value'])}',
                    ),
                  ),
              ],
            ),
            if (lastEvent != null) ...[
              const SizedBox(height: 8),
              Text(
                'Latest event: ${(lastEvent['message'] ?? '').toString()}',
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (running && _jobId != null)
                  OutlinedButton.icon(
                    onPressed: _cancelJob,
                    icon: const Icon(Icons.stop),
                    label: const Text('Cancel'),
                  ),
                OutlinedButton.icon(
                  onPressed: _showPayload,
                  icon: const Icon(Icons.data_object),
                  label: const Text('Payload'),
                ),
                OutlinedButton.icon(
                  onPressed: _job == null || _isExportingCsv ? null : _exportCsv,
                  icon: _isExportingCsv
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.table_view),
                  label: const Text('CSV'),
                ),
                OutlinedButton.icon(
                  onPressed: _job == null || _isExportingPdf ? null : _exportPdf,
                  icon: _isExportingPdf
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF'),
                ),
                ElevatedButton.icon(
                  onPressed: running ? null : _startGoalSeek,
                  icon: running
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(running ? 'Running' : 'Start'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityCard() {
    final allEvents = _executionEvents();
    final events = allEvents.length > _maxVisibleExecutionEvents
        ? allEvents.sublist(allEvents.length - _maxVisibleExecutionEvents)
        : allEvents;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Activity', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (allEvents.length > events.length)
              Text(
                'Showing the latest ${events.length} events out of ${allEvents.length}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (allEvents.length > events.length) const SizedBox(height: 8),
            if (events.isEmpty) const Text('No optimizer activity yet.'),
            for (final event in events)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${_formatEventTime(event['timestamp'])}  ${(event['message'] ?? '').toString()}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEvaluationTableCard(List<Map<String, dynamic>> evaluations) {
    final visible = evaluations.length > _maxVisibleEvaluationRows
        ? evaluations.sublist(evaluations.length - _maxVisibleEvaluationRows)
        : evaluations;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Evaluation results', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (evaluations.length > visible.length)
              Text(
                'Showing the latest ${visible.length} points out of ${evaluations.length}. Use CSV for the full run.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (evaluations.length > visible.length) const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Point')),
                  DataColumn(label: Text('Objective')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Parameter values')),
                  DataColumn(label: Text('Constraint checks')),
                ],
                rows: [
                  for (final evaluation in visible)
                    DataRow(
                      cells: [
                        DataCell(Text('#${evaluation['index'] ?? ''}')),
                        DataCell(Text(_formatNumber(evaluation['display_objective_value']))),
                        DataCell(_statusChip(evaluation['feasible'] == true)),
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: SelectableText(
                              [
                                for (final rawParameter
                                    in ((evaluation['parameters'] as List?) ?? const []).whereType<Map>())
                                  _parameterSummary(Map<String, dynamic>.from(rawParameter)),
                              ].join('\n'),
                            ),
                          ),
                        ),
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: SelectableText(
                              [
                                for (final rawConstraint
                                    in ((evaluation['constraints'] as List?) ?? const []).whereType<Map>())
                                  _constraintSummary(Map<String, dynamic>.from(rawConstraint)),
                              ].join('\n'),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Card(
      color: const Color(0xFFFFF7ED),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Run failed',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(error),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(bool passed) {
    final background = passed ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2);
    final foreground = passed ? const Color(0xFF166534) : const Color(0xFF991B1B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        passed ? 'Pass' : 'Miss',
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildBestResultCard(Map<String, dynamic> best) {
    final params = (best['parameters'] as List?)?.whereType<Map>().toList() ?? const [];
    final constraints =
        (best['constraints'] as List?)?.whereType<Map>().toList() ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Best feasible point', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Objective value: ${_formatNumber(best['display_objective_value'])}'),
            if (params.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Parameter values', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final raw in params)
                Text(_parameterSummary(Map<String, dynamic>.from(raw))),
            ],
            if (constraints.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Constraint checks', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final raw in constraints)
                Text(_constraintSummary(Map<String, dynamic>.from(raw))),
            ],
          ],
        ),
      ),
    );
  }
}

class _ParameterChoice {
  final String label;
  final String field;
  final String? processId;
  final double initial;

  const _ParameterChoice({
    required this.label,
    required this.field,
    required this.processId,
    required this.initial,
  });

  String get key => '$field|${processId ?? ''}';
}

class _ImpactChoice {
  final String methodId;
  final String methodName;
  final String indicator;
  final String impactCategoryId;

  const _ImpactChoice({
    required this.methodId,
    required this.methodName,
    required this.indicator,
    required this.impactCategoryId,
  });

  String get label => methodName == indicator ? indicator : '$methodName / $indicator';
}

class _GoalVariable {
  final _ParameterChoice choice;
  final double lower;
  final double upper;
  late final TextEditingController lowerCtrl;
  late final TextEditingController upperCtrl;

  _GoalVariable({
    required this.choice,
    required this.lower,
    required this.upper,
  }) {
    lowerCtrl = TextEditingController(text: lower.toStringAsPrecision(6));
    upperCtrl = TextEditingController(text: upper.toStringAsPrecision(6));
  }

  String get key => choice.key;

  void dispose() {
    lowerCtrl.dispose();
    upperCtrl.dispose();
  }
}

class _GoalConstraint {
  final _ImpactChoice choice;
  String operator;
  late final TextEditingController targetCtrl;

  _GoalConstraint({
    required this.choice,
    this.operator = '<=',
    double target = 0,
  }) {
    targetCtrl = TextEditingController(text: target.toStringAsPrecision(6));
  }

  void dispose() => targetCtrl.dispose();
}

class _VariableRow extends StatelessWidget {
  final _GoalVariable variable;
  final VoidCallback onRemove;

  const _VariableRow({required this.variable, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(variable.choice.label),
      subtitle: Row(
        children: [
          Expanded(
            child: TextField(
              controller: variable.lowerCtrl,
              decoration: const InputDecoration(labelText: 'Lower'),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: variable.upperCtrl,
              decoration: const InputDecoration(labelText: 'Upper'),
              keyboardType: TextInputType.number,
            ),
          ),
        ],
      ),
      trailing: IconButton(icon: const Icon(Icons.delete), onPressed: onRemove),
    );
  }
}

class _ConstraintRow extends StatefulWidget {
  final _GoalConstraint constraint;
  final bool canUseAsObjective;
  final VoidCallback onObjective;
  final VoidCallback onRemove;

  const _ConstraintRow({
    required this.constraint,
    required this.canUseAsObjective,
    required this.onObjective,
    required this.onRemove,
  });

  @override
  State<_ConstraintRow> createState() => _ConstraintRowState();
}

class _ConstraintRowState extends State<_ConstraintRow> {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(widget.constraint.choice.label),
      subtitle: Row(
        children: [
          DropdownButton<String>(
            value: widget.constraint.operator,
            items: const [
              DropdownMenuItem(value: '<=', child: Text('<= target')),
              DropdownMenuItem(value: '>=', child: Text('>= target')),
              DropdownMenuItem(value: '==', child: Text('= target')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => widget.constraint.operator = value);
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: widget.constraint.targetCtrl,
              decoration: const InputDecoration(labelText: 'Target'),
              keyboardType: TextInputType.number,
            ),
          ),
        ],
      ),
      trailing: Wrap(
        children: [
          if (widget.canUseAsObjective)
            IconButton(
              tooltip: 'Use as objective',
              icon: const Icon(Icons.flag),
              onPressed: widget.onObjective,
            ),
          IconButton(icon: const Icon(Icons.delete), onPressed: widget.onRemove),
        ],
      ),
    );
  }
}
