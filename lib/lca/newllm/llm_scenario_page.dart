// File: lib/lca/llm_scenario_page.dart

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../api/openai_api_key_storage.dart';

import '../newhome/lca_models.dart';
import '../results.dart';
import 'llm_scenario_controller.dart';
import 'pdf_download.dart';
import 'report_exporter.dart';
import 'scenario_graph_view.dart';

// Main UI page for generating scenarios with the LLM using the controller.
// Keeps the delicate parts separated: this file is UI only.
class LLMScenarioPage extends StatefulWidget {
  final String prompt;
  final List<ProcessNode> processes;
  final List<Map<String, dynamic>> flows;
  final ParameterSet? parameters;
  final Map<String, dynamic>? openLcaProductSystem;

  const LLMScenarioPage({
    super.key,
    required this.prompt,
    required this.processes,
    required this.flows,
    this.parameters,
    this.openLcaProductSystem,
  });

  @override
  State<LLMScenarioPage> createState() => _LLMScenarioPageState();
}

enum _LcaRunMode {
  openLcaIpc,
  brightway2,
}

enum _PostRunAction {
  downloadPdf,
  seeGraphs,
}

class _LLMScenarioPageState extends State<LLMScenarioPage> {
  static const String _gpt5ModelName = 'gpt-5';
  static const String _defaultOpenAiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );
  static const String _defaultOpenAiBase = String.fromEnvironment(
    'OPENAI_API_BASE',
    defaultValue: 'https://api.openai.com/v1',
  );
  static const String _defaultTogetherApiKey = String.fromEnvironment(
    'TOGETHER_API_KEY',
    defaultValue: '',
  );
  static const String _defaultTogetherApiBase = String.fromEnvironment(
    'TOGETHER_API_BASE',
    defaultValue: 'https://api.together.xyz/v1',
  );
  static const List<String> _openWeightModels = [
    'Qwen/Qwen3.5-397B-A17B',
    'zai-org/GLM-5',
    'moonshotai/Kimi-K2.5',
    'MiniMaxAI/MiniMax-M2.5',
    'meta-llama/Llama-4-Maverick-17B-128E-Instruct-FP8',
  ];
  static const String _brightwayBackendBaseUrl = String.fromEnvironment(
    'BRIGHTWAY_BACKEND_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
  static const String _openLcaBackendBaseUrl = String.fromEnvironment(
    'OPENLCA_BACKEND_BASE_URL',
    defaultValue: 'http://localhost:8001',
  );
  static const String _openLcaIpcUrl = String.fromEnvironment(
    'OPENLCA_IPC_URL',
    defaultValue: 'http://localhost:8080',
  );

  Map<String, dynamic>? _selectedOpenLcaProductSystem;
  Map<String, dynamic>? _selectedOpenLcaImpactMethod;

  bool _isLoading = false;
  String? _openAiApiKey;
  String? _togetherApiKey;
  Map<String, dynamic>? _mergedScenarios; // scenarioName -> { model, meta? }
  Map<String, List<Map<String, dynamic>>>? _rawDeltasByScenario;
  Map<String, String> _scenarioModelByName = const {};
  Map<String, Map<String, dynamic>> _generationByModel = const {};
  List<String> _functionsUsed = const [];
  LlmScenarioAbstention? _abstention;
  bool _isOpenWeightMegaRun = false;
  int _generationRunSeq = 0;

  void _debugLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    debugPrint('[LCA][UI][$timestamp] $message');
  }

  String _oneLine(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _previewPrompt(String text, {int maxChars = 200}) {
    final compact = _oneLine(text);
    if (compact.length <= maxChars) return compact;
    return '${compact.substring(0, maxChars)}...';
  }

  Map<String, int> _collectScenarioInputStats() {
    final globalCount = widget.parameters?.global.length ?? 0;
    final processSetCount = widget.parameters?.perProcess.length ?? 0;
    final processParamCount = widget.parameters?.perProcess.values
            .fold<int>(0, (sum, params) => sum + params.length) ??
        0;

    final baseModelForLlm = {
      'processes': widget.processes
          .map((p) => p.copyWithFields(emissions: const <FlowValue>[]).toJson())
          .toList(),
      'flows': widget.flows,
      if (widget.parameters != null) 'parameters': widget.parameters!.toJson(),
    };
    final userPayload = {
      'scenario_prompt': widget.prompt,
      'baseModel': baseModelForLlm,
    };

    final baseModelFull = {
      'processes': widget.processes.map((p) => p.toJson()).toList(),
      'flows': widget.flows,
      if (widget.parameters != null) 'parameters': widget.parameters!.toJson(),
    };

    return {
      'promptChars': widget.prompt.length,
      'processes': widget.processes.length,
      'flows': widget.flows.length,
      'globalParameters': globalCount,
      'processParameterSets': processSetCount,
      'processParameters': processParamCount,
      'userPayloadBytes': utf8.encode(jsonEncode(userPayload)).length,
      'fullModelBytes': utf8.encode(jsonEncode(baseModelFull)).length,
    };
  }

  void _guardWebMixedContent(Uri uri) {
    if (kIsWeb && Uri.base.scheme == 'https' && uri.scheme == 'http') {
      throw Exception(
        'Blocked by browser mixed-content policy. This web app is on HTTPS '
        'but backend URL is HTTP ($uri). Use an HTTPS backend URL or run the app locally over HTTP.',
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _primeApiKeys();
    final selected = widget.openLcaProductSystem;
    if (selected != null) {
      _selectedOpenLcaProductSystem = Map<String, dynamic>.from(selected);
    }
  }

  Future<void> _primeApiKeys() async {
    final openAiFromDefine = _defaultOpenAiKey.trim();
    if (openAiFromDefine.isNotEmpty) {
      await saveStoredOpenAiApiKey(openAiFromDefine);
    }
    final togetherFromDefine = _defaultTogetherApiKey.trim();
    if (togetherFromDefine.isNotEmpty) {
      await saveStoredTogetherApiKey(togetherFromDefine);
    }

    final openAi =
        openAiFromDefine.isNotEmpty ? openAiFromDefine : (await loadStoredOpenAiApiKey())?.trim();
    final together = togetherFromDefine.isNotEmpty
        ? togetherFromDefine
        : (await loadStoredTogetherApiKey())?.trim();

    if (!mounted) return;
    setState(() {
      _openAiApiKey = (openAi != null && openAi.isNotEmpty) ? openAi : null;
      _togetherApiKey =
          (together != null && together.isNotEmpty) ? together : null;
    });
  }

  String _maskApiKey(String? key) {
    final value = key?.trim() ?? '';
    if (value.isEmpty) return 'not set';
    if (value.length <= 10) return 'set';
    return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
  }

  String? _validateOpenAiApiKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('sk-')) {
      return 'OpenAI API keys usually start with "sk-".';
    }
    return null;
  }

  Future<void> _saveKeysFromDialogResult(_ApiKeyDialogResult result) async {
    final openAi = result.openAiKey.trim();
    if (openAi.isEmpty) {
      await clearStoredOpenAiApiKey();
    } else {
      await saveStoredOpenAiApiKey(openAi);
    }

    final together = result.togetherApiKey.trim();
    if (together.isEmpty) {
      await clearStoredTogetherApiKey();
    } else {
      await saveStoredTogetherApiKey(together);
    }

    if (!mounted) return;
    setState(() {
      _openAiApiKey = openAi.isEmpty ? null : openAi;
      _togetherApiKey = together.isEmpty ? null : together;
    });
  }

  Future<_ApiKeyDialogResult?> _showApiKeyDialog({
    String initialOpenAi = '',
    String initialTogether = '',
  }) async {
    final openAiController = TextEditingController(text: initialOpenAi);
    final togetherController = TextEditingController(text: initialTogether);
    bool obscureOpenAi = true;
    bool obscureTogether = true;
    String? openAiError;

    final selected = await showDialog<_ApiKeyDialogResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('LLM API keys'),
              content: SizedBox(
                width: 620,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Stored locally on this device/browser only. Keys are sent only to the selected LLM API endpoint.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: openAiController,
                      obscureText: obscureOpenAi,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: 'OpenAI API key (for GPT-5)',
                        border: const OutlineInputBorder(),
                        errorText: openAiError,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: !obscureOpenAi,
                          onChanged: (value) {
                            setDialogState(() => obscureOpenAi = value != true);
                          },
                        ),
                        const Text('Show OpenAI key'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: togetherController,
                      obscureText: obscureTogether,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Together AI API key (for open-weight models)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: !obscureTogether,
                          onChanged: (value) {
                            setDialogState(
                                () => obscureTogether = value != true);
                          },
                        ),
                        const Text('Show Together key'),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(
                    const _ApiKeyDialogResult(
                      openAiKey: '',
                      togetherApiKey: '',
                    ),
                  ),
                  child: const Text('Clear stored keys'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final openAi = openAiController.text.trim();
                    final together = togetherController.text.trim();
                    final validation = _validateOpenAiApiKey(openAi);
                    if (validation != null) {
                      setDialogState(() => openAiError = validation);
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _ApiKeyDialogResult(
                        openAiKey: openAi,
                        togetherApiKey: together,
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    openAiController.dispose();
    togetherController.dispose();
    return selected;
  }

  Future<String?> _ensureOpenAiApiKey() async {
    final inMemory = _openAiApiKey?.trim();
    if (inMemory != null && inMemory.isNotEmpty) {
      return inMemory;
    }

    final fromStorage = (await loadStoredOpenAiApiKey())?.trim();
    if (fromStorage != null && fromStorage.isNotEmpty) {
      if (mounted) setState(() => _openAiApiKey = fromStorage);
      return fromStorage;
    }

    if (!mounted) return null;
    final entered = await _showApiKeyDialog(
      initialOpenAi: _openAiApiKey ?? '',
      initialTogether: _togetherApiKey ?? '',
    );
    if (entered == null) return null;
    await _saveKeysFromDialogResult(entered);
    final normalized = entered.openAiKey.trim();
    return normalized.isEmpty ? null : normalized;
  }

  Future<String?> _ensureTogetherApiKey() async {
    final inMemory = _togetherApiKey?.trim();
    if (inMemory != null && inMemory.isNotEmpty) {
      return inMemory;
    }

    final fromStorage = (await loadStoredTogetherApiKey())?.trim();
    if (fromStorage != null && fromStorage.isNotEmpty) {
      if (mounted) setState(() => _togetherApiKey = fromStorage);
      return fromStorage;
    }

    if (!mounted) return null;
    final entered = await _showApiKeyDialog(
      initialOpenAi: _openAiApiKey ?? '',
      initialTogether: _togetherApiKey ?? '',
    );
    if (entered == null) return null;
    await _saveKeysFromDialogResult(entered);
    final normalized = entered.togetherApiKey.trim();
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> _onSetApiKeyPressed() async {
    final entered = await _showApiKeyDialog(
      initialOpenAi: _openAiApiKey ?? '',
      initialTogether: _togetherApiKey ?? '',
    );
    if (entered == null) return;
    await _saveKeysFromDialogResult(entered);
  }

  Future<void> _onGeneratePressed() async {
    final runId = ++_generationRunSeq;
    final runTimer = Stopwatch()..start();
    _debugLog('GEN[$runId] Generate GPT-5 scenarios pressed');

    final apiKey = await _ensureOpenAiApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      _debugLog('GEN[$runId] Missing API key, aborting');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'OpenAI API key is required before generating scenarios.')),
      );
      return;
    }

    final stats = _collectScenarioInputStats();
    _debugLog(
        'GEN[$runId] Inputs: promptChars=${stats['promptChars']} '
        'processes=${stats['processes']} flows=${stats['flows']} '
        'globalParams=${stats['globalParameters']} '
        'processParamSets=${stats['processParameterSets']} '
        'processParams=${stats['processParameters']} '
        'userPayloadBytes=${stats['userPayloadBytes']} '
        'fullModelBytes=${stats['fullModelBytes']} '
        'apiBase=$_defaultOpenAiBase model=$_gpt5ModelName '
        'apiKey=${_maskApiKey(apiKey)}',
    );
    _debugLog('GEN[$runId] Prompt preview: "${_previewPrompt(widget.prompt)}"');

    setState(() {
      _isLoading = true;
      _mergedScenarios = null;
      _rawDeltasByScenario = null;
      _scenarioModelByName = const {};
      _generationByModel = const {};
      _functionsUsed = const [];
      _abstention = null;
      _isOpenWeightMegaRun = false;
    });

    try {
      _debugLog('GEN[$runId] Creating controller');
      final controller = LlmScenarioController(
        apiKey: apiKey,
        model: _gpt5ModelName,
        apiBase: _defaultOpenAiBase,
        providerLabel: 'OpenAI',
        log: (message) => _debugLog('GEN[$runId] $message'),
      );
      _debugLog('GEN[$runId] Calling generateAndMergeScenarios');
      final result = await controller.generateAndMergeScenarios(
        prompt: widget.prompt,
        processes: widget.processes,
        flows: widget.flows,
        parameters: widget.parameters,
      );
      _debugLog(
        'GEN[$runId] Completed in ${runTimer.elapsedMilliseconds}ms '
        'scenarios=${result.mergedScenarios.length} '
        'functionsUsed=${result.functionsUsed.join(',')} '
        'unsupported=${result.isUnsupported}',
      );

      if (result.abstention != null) {
        if (!mounted) return;
        setState(() {
          _mergedScenarios = null;
          _rawDeltasByScenario = null;
          _scenarioModelByName = const {};
          _generationByModel = {
            _gpt5ModelName: {
              'status': 'unsupported',
              'scenario_count': 0,
              'reason': result.abstention!.reason,
              if (result.abstention!.requiredCapability != null)
                'required_capability': result.abstention!.requiredCapability,
            },
          };
          _functionsUsed = result.functionsUsed;
          _abstention = result.abstention;
          _isOpenWeightMegaRun = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Request unsupported: ${result.abstention!.reason}',
            ),
            duration: const Duration(seconds: 7),
          ),
        );
        return;
      }

      if (!mounted) return;
      final scenarioModelByName = <String, String>{
        for (final scenarioName in result.mergedScenarios.keys)
          scenarioName.toString(): _gpt5ModelName,
      };
      setState(() {
        _mergedScenarios = result.mergedScenarios;
        _rawDeltasByScenario = result.rawDeltasByScenario;
        _scenarioModelByName = scenarioModelByName;
        _generationByModel = {
          _gpt5ModelName: {
            'status': 'success',
            'scenario_count': result.mergedScenarios.length,
          },
        };
        _functionsUsed = result.functionsUsed;
        _abstention = null;
        _isOpenWeightMegaRun = false;
      });
      final mergeWarnings = _collectMergeWarnings(result.mergedScenarios);
      if (mergeWarnings.isNotEmpty) {
        debugPrint(
          '[LCA] merge warnings:\n${mergeWarnings.map((w) => ' - $w').join('\n')}',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Scenario generation completed with ${mergeWarnings.length} warning(s). '
              'See console for details.',
            ),
          ),
        );
      }
    } catch (e, st) {
      _debugLog(
        'GEN[$runId] Failed after ${runTimer.elapsedMilliseconds}ms: $e',
      );
      _debugLog('GEN[$runId] StackTrace:\n$st');
      if (!mounted) return;
      setState(() {
        _generationByModel = {
          _gpt5ModelName: {
            'status': 'error',
            'scenario_count': 0,
            'error': e.toString(),
          },
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scenario generation failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _debugLog(
        'GEN[$runId] Finished. totalElapsedMs=${runTimer.elapsedMilliseconds}',
      );
    }
  }

  String _shortModelName(String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return 'unknown-model';
    final slash = trimmed.lastIndexOf('/');
    if (slash < 0 || slash >= trimmed.length - 1) {
      return trimmed;
    }
    return trimmed.substring(slash + 1);
  }

  String _toScopedScenarioName(String model, String scenarioName) {
    final cleanedScenario =
        scenarioName.trim().isEmpty ? 'Scenario' : scenarioName.trim();
    return '[${_shortModelName(model)}] $cleanedScenario';
  }

  String _ensureUniqueScenarioName(String preferred, Set<String> existing) {
    if (!existing.contains(preferred)) return preferred;
    var n = 2;
    var candidate = '$preferred (#$n)';
    while (existing.contains(candidate)) {
      n += 1;
      candidate = '$preferred (#$n)';
    }
    return candidate;
  }

  Future<void> _onGenerateOpenWeightsPressed() async {
    final runId = ++_generationRunSeq;
    final runTimer = Stopwatch()..start();
    _debugLog('OW[$runId] Run open-weight models pressed');

    final apiKey = await _ensureTogetherApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      _debugLog('OW[$runId] Missing Together AI key, aborting');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Together AI API key is required before running open-weight models.',
          ),
        ),
      );
      return;
    }

    final stats = _collectScenarioInputStats();
    _debugLog(
      'OW[$runId] Inputs: promptChars=${stats['promptChars']} '
      'processes=${stats['processes']} flows=${stats['flows']} '
      'globalParams=${stats['globalParameters']} '
      'processParamSets=${stats['processParameterSets']} '
      'processParams=${stats['processParameters']} '
      'userPayloadBytes=${stats['userPayloadBytes']} '
      'fullModelBytes=${stats['fullModelBytes']} '
      'apiBase=$_defaultTogetherApiBase '
      'models=${_openWeightModels.length} apiKey=${_maskApiKey(apiKey)}',
    );
    _debugLog('OW[$runId] Prompt preview: "${_previewPrompt(widget.prompt)}"');

    setState(() {
      _isLoading = true;
      _mergedScenarios = null;
      _rawDeltasByScenario = null;
      _scenarioModelByName = const {};
      _generationByModel = const {};
      _functionsUsed = const [];
      _abstention = null;
      _isOpenWeightMegaRun = true;
    });

    final mergedAll = <String, dynamic>{};
    final rawAll = <String, List<Map<String, dynamic>>>{};
    final scenarioModelByName = <String, String>{};
    final generationByModel = <String, Map<String, dynamic>>{};
    final functionsUsed = <String>{};
    final unsupportedModels = <String>[];
    final failedModels = <String>[];

    for (final modelName in _openWeightModels) {
      final modelTimer = Stopwatch()..start();
      _debugLog('OW[$runId] Starting model="$modelName"');
      try {
        final controller = LlmScenarioController(
          apiKey: apiKey,
          model: modelName,
          apiBase: _defaultTogetherApiBase,
          providerLabel: 'Together AI',
          log: (message) => _debugLog('OW[$runId][$modelName] $message'),
        );
        final result = await controller.generateAndMergeScenarios(
          prompt: widget.prompt,
          processes: widget.processes,
          flows: widget.flows,
          parameters: widget.parameters,
        );

        modelTimer.stop();
        _debugLog(
          'OW[$runId] model="$modelName" finished in ${modelTimer.elapsedMilliseconds}ms '
          'scenarios=${result.mergedScenarios.length} unsupported=${result.isUnsupported}',
        );

        functionsUsed.addAll(result.functionsUsed);

        if (result.abstention != null) {
          generationByModel[modelName] = {
            'status': 'unsupported',
            'scenario_count': 0,
            'reason': result.abstention!.reason,
            if (result.abstention!.requiredCapability != null)
              'required_capability': result.abstention!.requiredCapability,
          };
          unsupportedModels
              .add('${_shortModelName(modelName)}: ${result.abstention!.reason}');
          continue;
        }

        for (final entry in result.mergedScenarios.entries) {
          final sourceScenario = entry.key.toString();
          final preferredName = _toScopedScenarioName(modelName, sourceScenario);
          final scopedName =
              _ensureUniqueScenarioName(preferredName, mergedAll.keys.toSet());
          mergedAll[scopedName] = entry.value;
          rawAll[scopedName] = result.rawDeltasByScenario[sourceScenario] ??
              const <Map<String, dynamic>>[];
          scenarioModelByName[scopedName] = modelName;
        }
        generationByModel[modelName] = {
          'status': 'success',
          'scenario_count': result.mergedScenarios.length,
        };
      } catch (e, st) {
        modelTimer.stop();
        _debugLog(
          'OW[$runId] model="$modelName" failed after ${modelTimer.elapsedMilliseconds}ms: $e',
        );
        _debugLog('OW[$runId] model="$modelName" StackTrace:\n$st');
        generationByModel[modelName] = {
          'status': 'error',
          'scenario_count': 0,
          'error': e.toString(),
        };
        failedModels.add('${_shortModelName(modelName)}: $e');
      }
    }

    if (!mounted) return;

    if (mergedAll.isEmpty) {
      final summaryParts = <String>[];
      if (unsupportedModels.isNotEmpty) {
        summaryParts.add('Unsupported: ${unsupportedModels.join(' | ')}');
      }
      if (failedModels.isNotEmpty) {
        summaryParts.add('Failed: ${failedModels.join(' | ')}');
      }
      final summary = summaryParts.isEmpty
          ? 'No scenarios were produced.'
          : summaryParts.join(' ');

      setState(() {
        _isLoading = false;
        _mergedScenarios = null;
        _rawDeltasByScenario = null;
        _scenarioModelByName = const {};
        _generationByModel = generationByModel;
        _functionsUsed = const [];
        _isOpenWeightMegaRun = false;
        _abstention = LlmScenarioAbstention(
          reason: 'No open-weight model produced scenarios. $summary',
          requiredCapability:
              'At least one Together-hosted model must return a supported scenario delta response.',
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open-weight run completed with no usable scenarios. Check logs for details.',
          ),
          duration: Duration(seconds: 8),
        ),
      );
      return;
    }

    final mergedWarnings = _collectMergeWarnings(mergedAll);
    final sortedFunctions = functionsUsed.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    setState(() {
      _mergedScenarios = mergedAll;
      _rawDeltasByScenario = rawAll;
      _scenarioModelByName = scenarioModelByName;
      _generationByModel = generationByModel;
      _functionsUsed = sortedFunctions;
      _abstention = null;
      _isOpenWeightMegaRun = true;
    });

    if (mergedWarnings.isNotEmpty) {
      debugPrint(
        '[LCA] open-weight merge warnings:\n${mergedWarnings.map((w) => ' - $w').join('\n')}',
      );
    }

    final noteParts = <String>[
      'Open-weight generation finished: ${mergedAll.length} scenario(s)',
      'from ${scenarioModelByName.values.toSet().length} model(s).',
    ];
    if (unsupportedModels.isNotEmpty) {
      noteParts.add('Unsupported models: ${unsupportedModels.length}.');
    }
    if (failedModels.isNotEmpty) {
      noteParts.add('Failed models: ${failedModels.length}.');
    }
    if (mergedWarnings.isNotEmpty) {
      noteParts.add('Merge warnings: ${mergedWarnings.length}.');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(noteParts.join(' ')),
        duration: const Duration(seconds: 8),
      ),
    );

    _debugLog(
      'OW[$runId] Finished. totalElapsedMs=${runTimer.elapsedMilliseconds} '
      'scenarioCount=${mergedAll.length} '
      'modelsWithScenarios=${scenarioModelByName.values.toSet().length} '
      'unsupportedModels=${unsupportedModels.length} failedModels=${failedModels.length}',
    );

    if (failedModels.isNotEmpty) {
      _debugLog('OW[$runId] Failed models detail: ${failedModels.join(' | ')}');
    }
    if (unsupportedModels.isNotEmpty) {
      _debugLog(
        'OW[$runId] Unsupported models detail: ${unsupportedModels.join(' | ')}',
      );
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>> _runLCAForAllScenarios() async {
    final runId = DateTime.now().millisecondsSinceEpoch;
    _debugLog(
      'BW[$runId] _runLCAForAllScenarios start. scenarioCount=${_mergedScenarios?.length ?? 0}',
    );
    final Map<String, dynamic> allResults = {};
    if (_mergedScenarios == null || _mergedScenarios!.isEmpty) {
      _debugLog('BW[$runId] No merged scenarios available; returning empty');
      return allResults;
    }

    for (final entry in _mergedScenarios!.entries) {
      final scenarioName = entry.key;
      final model = entry.value['model'];

      final uri = Uri.parse('$_brightwayBackendBaseUrl/run_lca_all');
      _guardWebMixedContent(uri);
      final body = jsonEncode({
        'scenarios': {
          scenarioName: {'model': model},
        },
      });
      final requestBytes = utf8.encode(body).length;
      final timer = Stopwatch()..start();
      _debugLog(
        'BW[$runId] POST /run_lca_all scenario="$scenarioName" bytes=$requestBytes',
      );

      try {
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        );
        timer.stop();
        _debugLog(
          'BW[$runId] scenario="$scenarioName" status=${response.statusCode} '
          'elapsedMs=${timer.elapsedMilliseconds} '
          'responseBytes=${utf8.encode(response.body).length}',
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          allResults[scenarioName] = data[scenarioName];
        } else {
          allResults[scenarioName] = {
            'success': false,
            'error': 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          };
        }
      } catch (e, st) {
        timer.stop();
        _debugLog(
          'BW[$runId] scenario="$scenarioName" failed after ${timer.elapsedMilliseconds}ms: $e',
        );
        _debugLog('BW[$runId] scenario="$scenarioName" StackTrace:\n$st');
        allResults[scenarioName] = {
          'success': false,
          'error': e.toString(),
        };
      }
    }

    _debugLog('BW[$runId] _runLCAForAllScenarios done');
    return allResults;
  }

  Future<_LcaRunMode?> _showRunModeDialog() {
    return showDialog<_LcaRunMode>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Choose LCA Runner'),
          content: const Text(
            'Run this analysis via OpenLCA IPC or Brightway2.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_LcaRunMode.openLcaIpc),
              child: const Text('OpenLCA IPC'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_LcaRunMode.brightway2),
              child: const Text('Brightway2'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runViaBrightway2() async {
    final results = await _runLCAForAllScenarios();
    final failures = results.entries.where((entry) {
      final payload = entry.value;
      if (payload is! Map) return true;
      final success = payload['success'];
      return success != true;
    }).toList();

    // Print to console so you can inspect the returned JSON in Flutter logs.
    debugPrint(const JsonEncoder.withIndent('  ').convert(results));

    if (!mounted) return;

    if (failures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('LCA finished for ${results.length} scenario(s).'),
        ),
      );
    } else {
      final first = failures.first.value;
      String firstError = 'Unknown error';
      if (first is Map && first['error'] != null) {
        firstError = first['error'].toString();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'LCA completed with ${failures.length} failed scenario(s). '
            'First error: $firstError',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
    await _handlePostRunActions(
      results: results,
      productSystemName: _entityDisplayName(
        _selectedOpenLcaProductSystem ?? const <String, dynamic>{},
        fallback: '',
      ),
      impactMethodName: _entityDisplayName(
        _selectedOpenLcaImpactMethod ?? const <String, dynamic>{},
        fallback: '',
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchOpenLcaProductSystems() async {
    final uri = Uri.parse(
      '$_openLcaBackendBaseUrl/openlca/product-systems',
    ).replace(
      queryParameters: {'ipc_url': _openLcaIpcUrl},
    );
    _guardWebMixedContent(uri);

    final response = await http.get(
      uri,
      headers: const {'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'OpenLCA backend error ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('OpenLCA backend returned invalid JSON.');
    }

    final rawSystems = decoded['product_systems'];
    if (rawSystems is! List) {
      return const [];
    }

    return rawSystems
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchOpenLcaImpactMethods() async {
    final uri = Uri.parse(
      '$_openLcaBackendBaseUrl/openlca/impact-methods',
    ).replace(
      queryParameters: {'ipc_url': _openLcaIpcUrl},
    );
    _guardWebMixedContent(uri);

    final response = await http.get(
      uri,
      headers: const {'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'OpenLCA backend error ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('OpenLCA backend returned invalid JSON.');
    }

    final rawMethods = decoded['impact_methods'];
    if (rawMethods is! List) {
      return const [];
    }

    return rawMethods
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<Map<String, dynamic>> _runOpenLcaForAllScenarios({
    required String productSystemId,
    required String impactMethodId,
  }) async {
    final scenarioPayload = _buildOpenLcaScenarioPayload();
    if (scenarioPayload.isEmpty) {
      return <String, dynamic>{};
    }

    final uri = Uri.parse('$_openLcaBackendBaseUrl/openlca/run-scenarios');
    _guardWebMixedContent(uri);
    final body = jsonEncode({
      'product_system_id': productSystemId,
      'impact_method_id': impactMethodId,
      'ipc_url': _openLcaIpcUrl,
      'scenarios': scenarioPayload,
    });

    final response = await http.post(
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'OpenLCA backend error ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('OpenLCA backend returned invalid JSON.');
    }

    final rawResults = decoded['results'];
    if (rawResults is Map) {
      return rawResults.map(
        (key, value) => MapEntry(
          key.toString(),
          value is Map<String, dynamic>
              ? value
              : Map<String, dynamic>.from(value as Map),
        ),
      );
    }

    throw Exception('OpenLCA backend response did not contain "results".');
  }

  Map<String, dynamic> _buildOpenLcaScenarioPayload() {
    final raw = _rawDeltasByScenario;
    if (raw != null && raw.isNotEmpty) {
      return raw.map(
        (name, changes) =>
            MapEntry(name, <String, dynamic>{'changes': changes}),
      );
    }
    final merged = _mergedScenarios;
    if (merged != null && merged.isNotEmpty) {
      return merged;
    }
    return const <String, dynamic>{};
  }

  List<String> _collectMergeWarnings(Map<String, dynamic> mergedScenarios) {
    final out = <String>[];
    mergedScenarios.forEach((scenario, payload) {
      if (payload is! Map) return;
      final raw = payload['merge_warnings'];
      if (raw is! List) return;
      for (final item in raw) {
        final text = item.toString().trim();
        if (text.isEmpty) continue;
        out.add('$scenario: $text');
      }
    });
    return out;
  }

  List<String> _collectOpenLcaWarnings(Map<String, dynamic> results) {
    final out = <String>[];
    results.forEach((scenario, payload) {
      if (payload is! Map) return;
      final result = payload['result'];
      if (result is! Map) return;
      final warnings = result['warnings'];
      if (warnings is! List) return;
      for (final warning in warnings) {
        final text = warning.toString().trim();
        if (text.isEmpty) continue;
        out.add('$scenario: $text');
      }
    });
    return out;
  }

  Future<_PostRunAction?> _showPostRunActionsDialog({
    required int scenarioCount,
  }) {
    return showDialog<_PostRunAction>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Results ready'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Calculated $scenarioCount scenario(s). Choose what to do next.',
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(dialogContext)
                      .pop(_PostRunAction.downloadPdf),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Download PDF'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(_PostRunAction.seeGraphs),
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('See Graphs'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadResultsPdf({
    required Map<String, dynamic> results,
    String? productSystemName,
    String? impactMethodName,
  }) async {
    final pdfBytes = await ReportExporter.buildPdf(
      prompt: widget.prompt,
      functionsUsed: _functionsUsed,
      rawDeltasByScenario: _rawDeltasByScenario ?? const {},
      graphPngByScenario: const {},
      lcaResults: results,
      productSystemName: productSystemName,
      impactMethodName: impactMethodName,
      scenarioModelByName: _scenarioModelByName,
      generationRouteLabel:
          _isOpenWeightMegaRun ? 'Together AI open-weight mega run' : 'GPT-5',
      generationByModel: _generationByModel,
    );
    await downloadPdf(
      bytes: pdfBytes,
      filename: _isOpenWeightMegaRun
          ? 'lca_results_mega_run_report.pdf'
          : 'lca_results_report.pdf',
    );
  }

  Future<void> _handlePostRunActions({
    required Map<String, dynamic> results,
    required String productSystemName,
    required String impactMethodName,
  }) async {
    final action = await _showPostRunActionsDialog(
      scenarioCount: results.length,
    );
    if (!mounted || action == null) return;

    if (action == _PostRunAction.downloadPdf) {
      try {
        await _downloadResultsPdf(
          results: results,
          productSystemName:
              productSystemName.trim().isEmpty ? null : productSystemName,
          impactMethodName:
              impactMethodName.trim().isEmpty ? null : impactMethodName,
        );
        if (!mounted) return;
        final exportedName = _isOpenWeightMegaRun
            ? 'lca_results_mega_run_report.pdf'
            : 'lca_results_report.pdf';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF exported as $exportedName'),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF export failed: $e')),
        );
      }
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultsPage(
          results: results,
          scenariosMap: _mergedScenarios,
          functionsUsed: _functionsUsed,
          prompt: widget.prompt,
          rawDeltasByScenario: _rawDeltasByScenario,
          productSystemName: productSystemName,
          impactMethodName: impactMethodName,
          scenarioModelByName: _scenarioModelByName,
          generationRouteLabel:
              _isOpenWeightMegaRun ? 'Together AI open-weight mega run' : 'GPT-5',
          generationByModel: _generationByModel,
        ),
      ),
    );
  }

  String _entitySearchBlob(Map<String, dynamic> item) {
    return [
      item['name'],
      item['id'],
      item['category'],
      item['library'],
      item['location'],
    ].where((e) => e != null).join(' ').toLowerCase();
  }

  String _entityDisplayName(
    Map<String, dynamic> item, {
    required String fallback,
  }) {
    final name = (item['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final id = (item['id'] ?? '').toString().trim();
    if (id.isNotEmpty) return id;
    return fallback;
  }

  Future<Map<String, dynamic>?> _showOpenLcaEntityDialog({
    required String title,
    required List<Map<String, dynamic>> items,
    required String emptyHint,
    Map<String, dynamic>? currentSelection,
  }) {
    String query = '';
    final initialId = (currentSelection?['id'] ?? '').toString();

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? items
                : items
                    .where((item) => _entitySearchBlob(item).contains(q))
                    .toList();

            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 620,
                height: 460,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText:
                            'Search by name, id, category, library, location',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setDialogState(() => query = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                emptyHint,
                                style: const TextStyle(color: Colors.black54),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final item = filtered[index];
                                final id = (item['id'] ?? '').toString();
                                final subtitleParts = <String>[
                                  if ((item['category'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                    (item['category'] ?? '').toString().trim(),
                                  if ((item['library'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                    (item['library'] ?? '').toString().trim(),
                                  if ((item['location'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                    (item['location'] ?? '').toString().trim(),
                                  if (id.isNotEmpty) id,
                                ];

                                final isCurrent =
                                    id.isNotEmpty && id == initialId;
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    isCurrent
                                        ? Icons.check_circle
                                        : Icons.circle_outlined,
                                    size: 18,
                                  ),
                                  title: Text(
                                    _entityDisplayName(
                                      item,
                                      fallback: '(unnamed)',
                                    ),
                                  ),
                                  subtitle: subtitleParts.isEmpty
                                      ? null
                                      : Text(subtitleParts.join(' | ')),
                                  onTap: () =>
                                      Navigator.of(dialogContext).pop(item),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _runViaOpenLcaIpc() async {
    final loaded = await Future.wait<List<Map<String, dynamic>>>([
      _fetchOpenLcaProductSystems(),
      _fetchOpenLcaImpactMethods(),
    ]);
    if (!mounted) return;

    final productSystems = loaded[0];
    final impactMethods = loaded[1];

    if (productSystems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('No product systems were returned by OpenLCA IPC backend.'),
        ),
      );
      return;
    }
    if (impactMethods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('No LCIA methods were returned by OpenLCA IPC backend.'),
        ),
      );
      return;
    }

    Map<String, dynamic>? selectedProduct = _selectedOpenLcaProductSystem;
    final rememberedId = (selectedProduct?['id'] ?? '').toString().trim();
    if (rememberedId.isNotEmpty) {
      final matched = productSystems.where(
        (item) => (item['id'] ?? '').toString().trim() == rememberedId,
      );
      if (matched.isNotEmpty) {
        selectedProduct = matched.first;
      } else {
        selectedProduct = await _showOpenLcaEntityDialog(
          title: 'Choose OpenLCA Product System',
          items: productSystems,
          emptyHint: 'No product systems match your search.',
          currentSelection: _selectedOpenLcaProductSystem,
        );
      }
    } else {
      selectedProduct = await _showOpenLcaEntityDialog(
        title: 'Choose OpenLCA Product System',
        items: productSystems,
        emptyHint: 'No product systems match your search.',
        currentSelection: _selectedOpenLcaProductSystem,
      );
    }
    if (!mounted || selectedProduct == null) return;

    final selectedImpactMethod = await _showOpenLcaEntityDialog(
      title: 'Choose LCIA Method',
      items: impactMethods,
      emptyHint: 'No LCIA methods match your search.',
      currentSelection: _selectedOpenLcaImpactMethod,
    );
    if (!mounted || selectedImpactMethod == null) return;

    final productSystemId = (selectedProduct['id'] ?? '').toString().trim();
    final impactMethodId = (selectedImpactMethod['id'] ?? '').toString().trim();
    if (productSystemId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Selected product system is missing an id.')),
      );
      return;
    }
    if (impactMethodId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected LCIA method is missing an id.')),
      );
      return;
    }

    final results = await _runOpenLcaForAllScenarios(
      productSystemId: productSystemId,
      impactMethodId: impactMethodId,
    );
    if (!mounted) return;

    setState(() {
      _selectedOpenLcaProductSystem = selectedProduct;
      _selectedOpenLcaImpactMethod = selectedImpactMethod;
    });

    final successCount = results.values
        .whereType<Map<String, dynamic>>()
        .where((entry) => entry['success'] == true)
        .length;

    final selectedProductName = _entityDisplayName(
      _selectedOpenLcaProductSystem ?? const <String, dynamic>{},
      fallback: '(unnamed product system)',
    );
    final selectedMethodName = _entityDisplayName(
      _selectedOpenLcaImpactMethod ?? const <String, dynamic>{},
      fallback: '(unnamed LCIA method)',
    );
    final warningLines = _collectOpenLcaWarnings(results);
    if (warningLines.isNotEmpty) {
      debugPrint(
        '[OpenLCA warnings]\n${warningLines.map((w) => ' - $w').join('\n')}',
      );
    }

    debugPrint(const JsonEncoder.withIndent('  ').convert(results));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'OpenLCA finished for ${results.length} scenario(s), '
          '$successCount succeeded. '
          '${warningLines.isEmpty ? '' : 'Warnings: ${warningLines.length}. '}'
          'Product system: $selectedProductName. '
          'Method: $selectedMethodName.',
        ),
      ),
    );

    if (successCount == 0) return;

    if (mounted) {
      setState(() => _isLoading = false);
    }
    await _handlePostRunActions(
      results: results,
      productSystemName: selectedProductName,
      impactMethodName: selectedMethodName,
    );
  }

  Future<void> _onRunLcaPressed() async {
    final mode = await _showRunModeDialog();
    if (mode == null) return;

    setState(() => _isLoading = true);
    try {
      if (mode == _LcaRunMode.brightway2) {
        await _runViaBrightway2();
      } else {
        await _runViaOpenLcaIpc();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('LCA error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _mergedScenarios != null;
    final abstention = _abstention;

    return Scaffold(
      appBar: AppBar(title: const Text('LLM Scenario Generator')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : (!hasResults
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'OpenAI key: ${_maskApiKey(_openAiApiKey)}',
                          style: const TextStyle(
                              fontSize: 13, fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Together key: ${_maskApiKey(_togetherApiKey)}',
                          style: const TextStyle(
                              fontSize: 13, fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: _onGeneratePressed,
                              child:
                                  const Text('Generate scenarios using GPT-5'),
                            ),
                            OutlinedButton(
                              onPressed: _onGenerateOpenWeightsPressed,
                              child: const Text(
                                'Run open-weight models (Together AI)',
                              ),
                            ),
                            OutlinedButton(
                              onPressed: _onSetApiKeyPressed,
                              child: const Text('Set API keys'),
                            ),
                          ],
                        ),
                        if (abstention != null) ...[
                          const SizedBox(height: 14),
                          _UnsupportedResultCard(abstention: abstention),
                        ],
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Summary bar
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _SummaryTile(
                                    title: 'User prompt',
                                    child: Text(widget.prompt,
                                        style: const TextStyle(fontSize: 14)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                _SummaryTile(
                                  title: 'Functions called',
                                  child: Text(
                                    _functionsUsed.isEmpty
                                        ? 'none'
                                        : _functionsUsed.join(', '),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Changes table
                        _ChangesTable(
                            rawDeltasByScenario: _rawDeltasByScenario),

                        const SizedBox(height: 16),

                        // Graph previews
                        if (_mergedScenarios != null &&
                            _mergedScenarios!.isNotEmpty) ...[
                          const Text('Scenario graphs',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 420,
                            child: ScenarioGraphView(
                              scenariosMap: _mergedScenarios!,
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),

                        // Actions
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _onRunLcaPressed,
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Run LCA'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _onGeneratePressed,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Regenerate using GPT-5'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _onGenerateOpenWeightsPressed,
                              icon: const Icon(Icons.auto_awesome),
                              label: const Text('Run Open-Weight Models'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _onSetApiKeyPressed,
                              icon: const Icon(Icons.key),
                              label: const Text('API keys'),
                            ),
                          ],
                        ),
                        if (_isOpenWeightMegaRun) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Current scenario set is a Together AI open-weight mega run '
                            '(${_scenarioModelByName.values.toSet().length} model(s)).',
                            style: const TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        if (_selectedOpenLcaProductSystem != null ||
                            _selectedOpenLcaImpactMethod != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'OpenLCA selection: '
                            'Product system = ${_entityDisplayName(_selectedOpenLcaProductSystem ?? const <String, dynamic>{}, fallback: "(not selected)")}; '
                            'LCIA method = ${_entityDisplayName(_selectedOpenLcaImpactMethod ?? const <String, dynamic>{}, fallback: "(not selected)")}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  )),
      ),
    );
  }
}

class _ApiKeyDialogResult {
  final String openAiKey;
  final String togetherApiKey;

  const _ApiKeyDialogResult({
    required this.openAiKey,
    required this.togetherApiKey,
  });
}

// small summary tile used in the header card
class _SummaryTile extends StatelessWidget {
  final String title;
  final Widget child;

  const _SummaryTile({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _UnsupportedResultCard extends StatelessWidget {
  final LlmScenarioAbstention abstention;

  const _UnsupportedResultCard({required this.abstention});

  @override
  Widget build(BuildContext context) {
    final requiredCapability = abstention.requiredCapability?.trim() ?? '';
    return Card(
      color: const Color(0xFFFFF3CD),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Request unsupported',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text('Reason: ${abstention.reason}'),
            if (requiredCapability.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Required capability: $requiredCapability'),
            ],
          ],
        ),
      ),
    );
  }
}

// changes table widget
class _ChangesTable extends StatelessWidget {
  final Map<String, List<Map<String, dynamic>>>? rawDeltasByScenario;

  const _ChangesTable({required this.rawDeltasByScenario});

  @override
  Widget build(BuildContext context) {
    if (rawDeltasByScenario == null) return const SizedBox.shrink();

    final rows = <DataRow>[];
    rawDeltasByScenario!.forEach((scenarioName, changes) {
      if (changes.isEmpty) {
        rows.add(
          const DataRow(
            cells: [
              DataCell(Text('(empty)')),
              DataCell(Text('(no changes)',
                  style: TextStyle(fontStyle: FontStyle.italic))),
              DataCell(
                  Text('-', style: TextStyle(fontStyle: FontStyle.italic))),
              DataCell(
                  Text('-', style: TextStyle(fontStyle: FontStyle.italic))),
            ],
          ),
        );
      } else {
        for (final change in changes) {
          final field = change['field']?.toString() ?? '(field missing)';

          final idText = change.containsKey('process_id')
              ? change['process_id'].toString()
              : change.containsKey('flow_id')
                  ? change['flow_id'].toString()
                  : (field.startsWith('parameters.global.'))
                      ? '(global)'
                      : '(unknown)';

          final newVal = change.containsKey('new_value')
              ? change['new_value'].toString()
              : '-';

          rows.add(
            DataRow(
              cells: [
                DataCell(Text(scenarioName)),
                DataCell(Text(idText)),
                DataCell(Text(field)),
                DataCell(Text(newVal)),
              ],
            ),
          );
        }
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Scenario changes',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Scenario')),
              DataColumn(label: Text('Process/Flow ID')),
              DataColumn(label: Text('Field')),
              DataColumn(label: Text('New value')),
            ],
            rows: rows,
          ),
        ),
      ],
    );
  }
}
