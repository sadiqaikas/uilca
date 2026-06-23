// File: lib/lca/llm_scenario_controller.dart

import 'dart:async';
import 'dart:convert';
import 'package:earlylca/lca/newmerge/merge_scenarios.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../lca_functions.dart';
import '../newhome/lca_models.dart';
import 'document_parameterisation.dart';
import 'llm_system_prompt.dart';

part 'llm_scenario_optimization.dart';
part 'llm_scenario_uncertainty.dart';

/// Holds results from an LLM scenario generation run
class LlmScenarioResult {
  final Map<String, dynamic> mergedScenarios;
  final Map<String, List<Map<String, dynamic>>> rawDeltasByScenario;
  final Map<String, dynamic>? optimizationPayload;
  final Map<String, dynamic>? uncertaintyPayload;
  final List<String> functionsUsed;
  final List<DocumentExtractionRecord> documentProvenance;
  final Map<String, dynamic> diagnostics;
  final LlmScenarioAbstention? abstention;

  bool get isUnsupported => abstention != null;
  bool get isOptimization => optimizationPayload != null;
  bool get isUncertaintyPropagation => uncertaintyPayload != null;

  const LlmScenarioResult({
    required this.mergedScenarios,
    required this.rawDeltasByScenario,
    this.optimizationPayload,
    this.uncertaintyPayload,
    required this.functionsUsed,
    this.documentProvenance = const [],
    this.diagnostics = const <String, dynamic>{},
    this.abstention,
  });
}

/// Structured abstention returned when a request is unsupported or blocked.
class LlmScenarioAbstention {
  final String status;
  final String reason;
  final String? requiredCapability;

  const LlmScenarioAbstention({
    this.status = 'unsupported',
    required this.reason,
    this.requiredCapability,
  });

  Map<String, dynamic> toJson() => {
        'status': status,
        'reason': reason,
        if (requiredCapability != null &&
            requiredCapability!.trim().isNotEmpty)
          'required_capability': requiredCapability,
      };
}

/// Handles building LCA models for LLM, calling a chat-completions API,
/// and merging scenarios.
class LlmScenarioController {
  static const String _defaultOpenAiBase = 'https://api.openai.com/v1';
  static const String _controllerRevision =
      'rev-2026-05-01-optimization-memory';
  static const Duration _openAiRequestTimeout = Duration(seconds: 150);
  static const int _maxToolCallsPerTurn = 4;
  static const int _maxIndicatorSearchCallsPerTurn = 1;
  static const int _maxDocumentToolCallsPerTurn = 1;
  static const int _maxDocumentMatchesPerQueryForFollowup = 3;
  static const int _maxDocumentRowsPerMatchForFollowup = 12;
  static const int _maxDocumentFallbackTextMatchesForFollowup = 3;
  static const int _maxDocumentValueCharsForFollowup = 180;
  static const String _defaultApiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );
  static final RegExp _structuralKeywordPattern = RegExp(
    r'"(?:processes|flows|inputs|outputs|emissions|biosphere|biosphere_flows|exchanges|exchange|datasets?|background_dataset|background_datasets|technosphere|flow_id|add_process|remove_process|replace_process)"',
    caseSensitive: false,
  );

  final String apiKey;
  final String model;
  final String apiBase;
  final String providerLabel;
  final bool formulaCalculatorEnabled;
  final DocumentParameterisationService documentService;

  /// Optional logger. If null, prints are used.
  final void Function(String message)? log;

  const LlmScenarioController({
    this.apiKey = _defaultApiKey,
    this.model = 'gpt-5', // default to GPT-5
    this.apiBase = 'https://api.openai.com/v1',
    this.providerLabel = 'OpenAI',
    this.formulaCalculatorEnabled = false,
    this.documentService = const DocumentParameterisationService(),
    this.log,
  });

  void _log(String message) {
    if (log != null) {
      log!(message);
    } else {
      // ignore: avoid_print
      print(message);
    }
  }

  void _logModelText(String label, String? text) {
    if (text == null) {
      _log('[LCA] $label: <null>');
      return;
    }
    final len = text.length;
    const maxChars = 12000;
    if (len <= maxChars) {
      _log('[LCA] $label chars=$len <<BEGIN>>\n$text\n<<END>>');
      return;
    }
    const head = 6000;
    const tail = 6000;
    final preview =
        '${text.substring(0, head)}\n...[TRUNCATED ${len - maxChars} chars]...\n${text.substring(len - tail)}';
    _log(
      '[LCA] $label chars=$len (truncated to $maxChars chars) <<BEGIN>>\n$preview\n<<END>>',
    );
  }

  Uri _resolveChatCompletionsUri() {
    const fallback = '$_defaultOpenAiBase/chat/completions';
    final raw = apiBase.trim();

    if (raw.isEmpty) {
      return Uri.parse(fallback);
    }

    // If a full endpoint is already provided, use it as-is.
    if (raw.endsWith('/chat/completions')) {
      final uri = Uri.tryParse(raw);
      return uri ?? Uri.parse(fallback);
    }

    final parsed = Uri.tryParse(raw);
    if (parsed == null ||
        !parsed.hasScheme ||
        parsed.host.isEmpty ||
        parsed.host == 'v1') {
      return Uri.parse(fallback);
    }

    // For OpenAI hosts, normalize bare host roots to include /v1.
    String normalized =
        raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    if ((parsed.host == 'api.openai.com' ||
            parsed.host.endsWith('.openai.com') ||
            parsed.host == 'api.together.xyz' ||
            parsed.host.endsWith('.together.xyz')) &&
        (parsed.path.isEmpty || parsed.path == '/')) {
      normalized = '$normalized/v1';
    }

    return Uri.parse('$normalized/chat/completions');
  }

  bool _shouldRetryClientException(http.ClientException error, int attempt) {
    if (attempt >= 2) return false;
    final msg = error.message.toLowerCase();
    return msg.contains('failed to fetch') ||
        msg.contains('connection closed') ||
        msg.contains('network');
  }

  bool _shouldRetryHttpResponse(http.Response response, int attempt) {
    if (attempt >= 2) return false;
    if (response.statusCode == 429) return true;
    return response.statusCode == 502 ||
        response.statusCode == 503 ||
        response.statusCode == 504;
  }

  Duration _retryDelayForResponse(http.Response response) {
    final retryAfter = response.headers['retry-after']?.trim() ?? '';
    final seconds = int.tryParse(retryAfter);
    if (seconds != null && seconds > 0 && seconds <= 10) {
      return Duration(seconds: seconds);
    }
    if (response.statusCode == 429) {
      return const Duration(milliseconds: 1200);
    }
    return const Duration(milliseconds: 600);
  }

  String _webFailedToFetchHint(Uri uri, http.ClientException error) {
    if (!kIsWeb || !error.message.toLowerCase().contains('failed to fetch')) {
      return '';
    }
    return ' Browser blocked the request before $providerLabel returned a response. '
        'Check browser Network tab for blocked OPTIONS/POST, disable VPN/ad-block extensions, '
        'verify DNS can resolve ${uri.host}, and verify your API key is valid and not restricted.';
  }

  bool _errorSuggestsUnsupportedJsonResponseFormat(String body) {
    final msg = body.toLowerCase();
    if (!msg.contains('response_format')) return false;
    return msg.contains('unsupported') ||
        msg.contains('not supported') ||
        msg.contains('invalid') ||
        msg.contains('unknown') ||
        msg.contains('unrecognized');
  }

  String _finalJsonOnlyReminder({bool formulaResultsAvailable = false}) {
    final reminder = 'Return only the final JSON object in one supported schema. '
        'Do not repeat tool output, extracted tables, document metadata, or explanations. '
        'Convert the extracted values into final scenario, optimization, uncertainty, or structured unsupported JSON. '
        'After tool use, copy only change entries produced by the tool; do not add extra fields or parameters. '
        'Every change.new_value must be a numeric literal; omit any change whose value is unknown or null. '
        'Keep scenario names short and do not copy process or dataset names into scenario names.';
    if (!formulaResultsAvailable) return reminder;
    return '$reminder '
        'Because formulaCalculator was used, any formula value in a scenario name must be copied from the matching formulaCalculator result.id and numeric outputs exactly; do not recalculate, reorder, regroup, or assign one result to a different candidate. If the matching calculator result is unclear, omit the formula value from the scenario name.';
  }

  String _formulaCalculatorFollowupReminder(
    _OptimizationToolMemory toolMemory,
  ) {
    final candidateCount = toolMemory.simplexChangeListCount;
    final expectedIds = candidateCount == null
        ? 'every candidate_summaries[].id'
        : List.generate(candidateCount, (i) => 'candidate_${i + 1}').join(', ');
    final countSentence = candidateCount == null
        ? 'Use one calculation per candidate_summaries item.'
        : 'The calculations array must contain exactly $candidateCount items, with ids: $expectedIds.';
    return 'If supported formula calculations are needed from the simplexLatticeDesign output, call formulaCalculator once with a batched calculations list. '
        '$countSentence '
        'Each calculation id is required and must equal the matching candidate_summaries[].id. '
        'Formula arguments derived from the lattice must come from that same candidate_summaries[].parameter_values object. '
        'Do not group candidates in a way that loses candidate identity. '
        'Otherwise output the final JSON object only. Final scenarios must use only change entries from the matching changeLists entry; do not add extra parameters or null values.';
  }

  /// Builds the model for local merging (includes emissions and parameters)
  Map<String, dynamic> _buildBaseModelFull(
    List<ProcessNode> processes,
    List<Map<String, dynamic>> flows,
    ParameterSet? parameters,
  ) {
    _log('[LCA] Building full base model');
    final out = {
      'processes': processes.map((p) => p.toJson()).toList(),
      'flows': flows,
      if (parameters != null) 'parameters': parameters.toJson(),
    };
    _log(
        '[LCA] Full base model built: processes=${processes.length}, flows=${flows.length}, hasParameters=${parameters != null}');
    return out;
  }

  /// Builds compact context for the LLM. Full flows/emissions stay local.
  static Map<String, dynamic> buildModelContextForLLM(
    List<ProcessNode> processes,
    ParameterSet? parameters,
  ) {
    final functionalProcesses = processes.where((p) => p.isFunctional).toList();
    final functionalProcessId =
        functionalProcesses.length == 1 ? functionalProcesses.first.id : null;

    Map<String, dynamic>? referenceOutputFor(ProcessNode process) {
      if (process.outputs.isEmpty) return null;
      final output = process.outputs.first;
      return {
        'name': output.name,
        'amount': output.amount,
        'unit': output.unit,
      };
    }

    return {
      if (functionalProcessId != null) 'functional_process_id': functionalProcessId,
      'number_functional_units': 1,
      'processes': [
        for (final process in processes)
          {
            'id': process.id,
            'name': process.name,
            if (referenceOutputFor(process) != null)
              'reference_output': referenceOutputFor(process),
            if (parameters != null &&
                parameters.processParamsFor(process.id).isNotEmpty)
              'parameters': parameters
                  .processParamsFor(process.id)
                  .map((p) => p.toJson())
                  .toList(),
          },
      ],
      if (parameters != null && parameters.global.isNotEmpty)
        'global_parameters': parameters.global.map((p) => p.toJson()).toList(),
    };
  }

  Map<String, dynamic> _buildModelContextForLLM(
    List<ProcessNode> processes,
    ParameterSet? parameters,
  ) {
    _log('[LCA] Building compact model context for LLM');
    final out = buildModelContextForLLM(processes, parameters);
    _log(
        '[LCA] Compact model context built: processes=${processes.length}, hasParameters=${parameters != null}');
    return out;
  }

  Map<String, dynamic> _buildOptimizationContextForPrompt(
    Map<String, dynamic> optimizationContext,
  ) => _buildOptimizationContextForPromptImpl(
        optimizationContext: optimizationContext,
      );

  /// Runs the LLM flow: send prompt and base model, handle tools or functions, merge results.
  Future<LlmScenarioResult> generateAndMergeScenarios({
    required String prompt,
    required List<ProcessNode> processes,
    required List<Map<String, dynamic>> flows,
    ParameterSet? parameters,
    Map<String, dynamic>? optimizationContext,
    List<LlmDocumentReference> uploadedDocuments = const [],
  }) async {
    _log('[LCA] === generateAndMergeScenarios START ===');

    final baseModelFull = _buildBaseModelFull(processes, flows, parameters);
    final modelContextForLLM = _buildModelContextForLLM(processes, parameters);

    final userPayload = jsonEncode({
      'scenario_prompt': prompt,
      'model_context': modelContextForLLM,
      if (uploadedDocuments.isNotEmpty)
        'document_context': {
          'documents': uploadedDocuments
              .map((document) => document.toPromptContextJson())
              .toList(),
        },
      if (optimizationContext != null && optimizationContext.isNotEmpty)
        'optimization_context': _buildOptimizationContextForPrompt(
          optimizationContext,
        ),
    });

    final systemPrompt = llmSystemPromptForVariant(
      formulaCalculatorEnabled: formulaCalculatorEnabled,
    );
    final functions = llmFunctionsForVariant(
      formulaCalculatorEnabled: formulaCalculatorEnabled,
    );
    final firstCallJsonOnly = functions.isEmpty;
    final diagnostics = <String, dynamic>{
      'provider': providerLabel,
      'model': model,
      'api_base': apiBase,
      'controller_revision': _controllerRevision,
      'system_prompt_variant': llmSystemPromptVariantName(
        formulaCalculatorEnabled: formulaCalculatorEnabled,
      ),
      'formula_calculator_enabled': formulaCalculatorEnabled,
      'request': {
        'system_prompt_bytes': utf8.encode(systemPrompt).length,
        'user_payload_bytes': utf8.encode(userPayload).length,
        'first_call_json_response_format_requested': firstCallJsonOnly,
        'final_json_response_format_requested': true,
        'tool_choice': functions.isEmpty ? 'none' : 'auto',
        'tools_offered': functions
            .map((f) => (f['name'] ?? '').toString())
            .where((name) => name.trim().isNotEmpty)
            .toList(),
      },
    };

    // Step 1: initial call
    _log('[LCA] First $providerLabel call. model=$model');
    final firstResp = await _callOpenAI(
      systemPrompt: systemPrompt,
      userPayload: userPayload,
      functions: functions,
      jsonOnly: firstCallJsonOnly,
      callLabel: 'first_call',
    );
    diagnostics['first_response'] = _chatResponseDiagnostics(firstResp);
    _log('[LCA] First call returned. Parsing for tools or direct JSON');

    // Parse for tool/function calls or direct scenarios
    final parsed = await _handleToolOrScenarios(
      firstResp,
      baseModelFull,
      systemPrompt,
      userPayload,
      prompt,
      optimizationContext ?? const <String, dynamic>{},
      uploadedDocuments,
      diagnostics,
      functions,
    );
    _log(
        '[LCA] Parsed assistant output. functionsUsed=${parsed.functionsUsed.join(', ')}');

    if (parsed.abstention != null) {
      final abstention = parsed.abstention!;
      _log(
        '[LCA] Blocking merge with abstention. '
        'status=${abstention.status} reason="${abstention.reason}"',
      );
      _log('[LCA] === generateAndMergeScenarios END (unsupported) ===');
      return LlmScenarioResult(
        mergedScenarios: const <String, dynamic>{},
        rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
        optimizationPayload: null,
        uncertaintyPayload: null,
        functionsUsed: parsed.functionsUsed,
        documentProvenance: parsed.documentProvenance,
        diagnostics: diagnostics,
        abstention: abstention,
      );
    }

    if (parsed.optimizationPayload != null) {
      _log('[LCA] === generateAndMergeScenarios END (optimization) ===');
      return LlmScenarioResult(
        mergedScenarios: const <String, dynamic>{},
        rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
        optimizationPayload: parsed.optimizationPayload,
        uncertaintyPayload: null,
        functionsUsed: parsed.functionsUsed,
        documentProvenance: parsed.documentProvenance,
        diagnostics: diagnostics,
        abstention: null,
      );
    }

    if (parsed.uncertaintyPayload != null) {
      _log('[LCA] === generateAndMergeScenarios END (uncertainty) ===');
      return LlmScenarioResult(
        mergedScenarios: const <String, dynamic>{},
        rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
        optimizationPayload: null,
        uncertaintyPayload: parsed.uncertaintyPayload,
        functionsUsed: parsed.functionsUsed,
        documentProvenance: parsed.documentProvenance,
        diagnostics: diagnostics,
        abstention: null,
      );
    }

    // Merge scenarios locally
    _log('[LCA] Merging scenarios locally');
    final mergedFull =
        mergeScenarios(baseModelFull, parsed.rawDeltasByScenario);

    _log('[LCA] === generateAndMergeScenarios END ===');

    return LlmScenarioResult(
      mergedScenarios: mergedFull['scenarios'] as Map<String, dynamic>,
      rawDeltasByScenario: parsed.rawDeltasByScenario,
      optimizationPayload: null,
      uncertaintyPayload: null,
      functionsUsed: parsed.functionsUsed,
      documentProvenance: parsed.documentProvenance,
      diagnostics: diagnostics,
      abstention: null,
    );
  }

  /// Calls a Chat Completions endpoint with modern tool-calling shape.
  /// Keeps behaviour compatible with legacy function calling.
  Future<Map<String, dynamic>> _callOpenAI({
    required String systemPrompt,
    required String userPayload,
    List<Map<String, dynamic>>? functions, // legacy schema
    String functionCallMode = 'auto', // 'auto' | 'none' or a function name
    List<Map<String, dynamic>>? messagesOverride,
    bool jsonOnly = false,
    String callLabel = 'default',
    bool allowJsonResponseFormatFallback = true,
  }) async {
    // Convert legacy functions -> tools
    List<Map<String, dynamic>>? tools;
    if (functions != null) {
      tools = functions.map((f) {
        return {
          'type': 'function',
          'function': {
            'name': f['name'],
            'description': f['description'],
            'parameters': f['parameters'],
          },
        };
      }).toList();
      _log('[LCA] Prepared ${tools.length} tools');
    }

    dynamic toolChoice;
    if (functionCallMode == 'auto' || functionCallMode == 'none') {
      toolChoice = functionCallMode;
    } else {
      toolChoice = {
        'type': 'function',
        'function': {'name': functionCallMode},
      };
    }

    final isGptModel = model.toLowerCase().startsWith('gpt-');
    final body = <String, dynamic>{
      'model': model,
      'messages': messagesOverride ??
          [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPayload},
          ],
      if (tools != null) 'tools': tools,
      if (tools != null) 'tool_choice': toolChoice,
      if (jsonOnly) 'response_format': {'type': 'json_object'},
      if (isGptModel)
        'max_completion_tokens': 8192
      else
        'max_tokens': 4096,
    };

    final uri = _resolveChatCompletionsUri();
    final trimmedApiKey = apiKey.trim();
    if (trimmedApiKey.isEmpty) {
      throw Exception(
        'Missing $providerLabel API key. Set it in-app before running.',
      );
    }

    final encodedBody = jsonEncode(body);
    final bodyBytes = utf8.encode(encodedBody).length;
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $trimmedApiKey',
    };
    _log(
      '[LCA][$_controllerRevision] POST $uri (apiBaseRaw="$apiBase") '
      'callLabel=$callLabel jsonOnly=$jsonOnly '
      'messages=${(body['messages'] as List).length} bodyBytes=$bodyBytes',
    );

    http.Response? resp;
    for (var attempt = 1; attempt <= 2; attempt += 1) {
      final sw = Stopwatch()..start();
      try {
        resp = await http
            .post(
              uri,
              headers: headers,
              body: encodedBody,
            )
            .timeout(_openAiRequestTimeout);
        sw.stop();
        _log(
          '[LCA] $providerLabel response received. '
          'callLabel=$callLabel attempt=$attempt elapsedMs=${sw.elapsedMilliseconds}',
        );
        if (_shouldRetryHttpResponse(resp, attempt)) {
          final delay = _retryDelayForResponse(resp);
          _log(
            '[LCA] $providerLabel returned HTTP ${resp.statusCode}. '
            'callLabel=$callLabel attempt=$attempt. Retrying once after '
            '${delay.inMilliseconds}ms...',
          );
          await Future<void>.delayed(delay);
          resp = null;
          continue;
        }
        break;
      } on TimeoutException catch (e) {
        sw.stop();
        if (attempt >= 2) {
          throw Exception(
            '$providerLabel request timed out [$_controllerRevision]: $e '
            '(attempts=$attempt, callLabel=$callLabel, bodyBytes=$bodyBytes, '
            'resolvedUri=$uri, apiBaseRaw="$apiBase")',
          );
        }
        _log(
          '[LCA] Timeout talking to $providerLabel. '
          'callLabel=$callLabel attempt=$attempt bodyBytes=$bodyBytes '
          'elapsedMs=${sw.elapsedMilliseconds}. Retrying once...',
        );
      } on http.ClientException catch (e) {
        sw.stop();
        if (_shouldRetryClientException(e, attempt)) {
          _log(
              '[LCA] $providerLabel network error. callLabel=$callLabel attempt=$attempt '
              'elapsedMs=${sw.elapsedMilliseconds}. Retrying once...');
          await Future<void>.delayed(const Duration(milliseconds: 300));
          continue;
        }
        throw Exception(
          '$providerLabel network failure [$_controllerRevision]: $e '
          '(resolvedUri=$uri, apiBaseRaw="$apiBase").'
          '${_webFailedToFetchHint(uri, e)}',
        );
      } catch (e) {
        throw Exception(
          '$providerLabel request failed [$_controllerRevision]: $e '
          '(resolvedUri=$uri, apiBaseRaw="$apiBase")',
        );
      }
    }

    if (resp == null) {
      throw Exception(
        '$providerLabel request failed [$_controllerRevision]: no response '
        '(resolvedUri=$uri, apiBaseRaw="$apiBase")',
      );
    }

    _log('[LCA] HTTP status ${resp.statusCode}');
    if (resp.statusCode != 200) {
      _log('[LCA] Error body: ${resp.body}');
      if (jsonOnly &&
          allowJsonResponseFormatFallback &&
          _errorSuggestsUnsupportedJsonResponseFormat(resp.body)) {
        _log(
          '[LCA] $providerLabel rejected response_format=json_object; retrying without response_format',
        );
        return _callOpenAI(
          systemPrompt: systemPrompt,
          userPayload: userPayload,
          functions: functions,
          functionCallMode: functionCallMode,
          messagesOverride: messagesOverride,
          jsonOnly: false,
          callLabel: '${callLabel}_without_response_format',
          allowJsonResponseFormatFallback: false,
        );
      }
      throw Exception('$providerLabel error ${resp.statusCode}: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw Exception('$providerLabel response missing choices');
    }
    _log('[LCA] Response has ${choices.length} choice(s)');
    return decoded;
  }

  Map<String, dynamic> _chatResponseDiagnostics(Map<String, dynamic> response) {
    final out = <String, dynamic>{
      if (response['id'] != null) 'id': response['id'],
      if (response['model'] != null) 'model': response['model'],
      if (response['created'] != null) 'created': response['created'],
      if (response['usage'] is Map) 'usage': response['usage'],
    };
    final choices = response['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final choice = (choices.first as Map).cast<String, dynamic>();
      final message = choice['message'];
      final messageMap =
          message is Map ? message.cast<String, dynamic>() : const <String, dynamic>{};
      final contentText = _extractContentText(messageMap['content']);
      final toolCalls = messageMap['tool_calls'];
      out['choice'] = {
        if (choice['finish_reason'] != null)
          'finish_reason': choice['finish_reason'],
        if (choice['index'] != null) 'index': choice['index'],
        'message_role': messageMap['role']?.toString() ?? '',
        'content_chars': contentText?.length ?? 0,
        'content': contentText ?? '',
        'tool_calls': toolCalls is List
            ? toolCalls.map(_sanitizedToolCallDiagnostics).toList()
            : const <Map<String, dynamic>>[],
      };
    }
    return out;
  }

  Map<String, dynamic> _sanitizedToolCallDiagnostics(dynamic raw) {
    if (raw is! Map) return {'malformed': raw.toString()};
    final tool = raw.cast<String, dynamic>();
    final fnRaw = tool['function'];
    final fn = fnRaw is Map ? fnRaw.cast<String, dynamic>() : const <String, dynamic>{};
    return {
      if (tool['id'] != null) 'id': tool['id'].toString(),
      if (tool['type'] != null) 'type': tool['type'].toString(),
      'function': {
        'name': (fn['name'] ?? '').toString(),
        'arguments': (fn['arguments'] ?? '').toString(),
      },
    };
  }

  List<Map<String, dynamic>> _extractInlineToolCallsFromContent(String? content) {
    if (content == null || content.trim().isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final pattern = RegExp(
      r'<\|tool_call_begin\|>\s*(?:functions\.)?([A-Za-z_][A-Za-z0-9_]*)(?::[0-9]+)?\s*<\|tool_call_argument_begin\|>(.*?)<\|tool_call_end\|>',
      dotAll: true,
    );
    final out = <Map<String, dynamic>>[];
    var index = 0;
    for (final match in pattern.allMatches(content)) {
      final name = (match.group(1) ?? '').trim();
      final arguments = (match.group(2) ?? '').trim();
      if (name.isEmpty || arguments.isEmpty) continue;
      out.add({
        'id': 'recovered_inline_tool_call_$index',
        'type': 'function',
        'function': {
          'name': name,
          'arguments': arguments,
        },
      });
      index += 1;
    }
    return out;
  }

  /// Parses GPT output for tool/function calls or direct scenarios.
  /// Supports multiple tool calls in a single assistant turn.
  Future<_ParsedLLMOutput> _handleToolOrScenarios(
    Map<String, dynamic> firstResp,
    Map<String, dynamic> baseModelFull,
    String systemPrompt,
    String userPayload,
    String prompt,
    Map<String, dynamic> optimizationContext,
    List<LlmDocumentReference> uploadedDocuments,
    Map<String, dynamic> diagnostics,
    List<Map<String, dynamic>> functions,
  ) async {
    final firstChoice =
        (firstResp['choices'] as List).first as Map<String, dynamic>;
    final message = firstChoice['message'] as Map<String, dynamic>;

    final functionsUsed = <String>[];
    Map<String, List<Map<String, dynamic>>> rawDeltasByScenario = {};
    final documentProvenance = <DocumentExtractionRecord>[];
    final initialContentText = _extractContentText(message['content']);
    _logModelText('first_call_assistant_content', initialContentText);
    diagnostics['parser'] = <String, dynamic>{
      'path': 'first_response',
      'initial_content_chars': initialContentText?.length ?? 0,
      'initial_has_tool_calls':
          message['tool_calls'] is List && (message['tool_calls'] as List).isNotEmpty,
      'initial_has_legacy_function_call': message['function_call'] != null,
    };

    // Defensive check for an empty assistant message
    if ((message['tool_calls'] == null ||
            (message['tool_calls'] as List?)?.isEmpty == true) &&
        (message['function_call'] == null) &&
        (initialContentText == null || initialContentText.trim().isEmpty)) {
      _log('[LCA] Assistant returned empty content and no tool calls');
      diagnostics['parser'] = {
        ...((diagnostics['parser'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{}),
        'rejection_stage': 'empty_assistant_message',
      };
      throw Exception(
          'Assistant returned an empty message. Check model, prompt, or function specs.');
    }

    // Newer tool_calls path
    if (message.containsKey('tool_calls') && message['tool_calls'] != null) {
      final List toolCalls = message['tool_calls'] as List;
      _log('[LCA] tool_calls count=${toolCalls.length}');
      if (toolCalls.length > _maxToolCallsPerTurn) {
        return _ParsedLLMOutput(
          functionsUsed: functionsUsed,
          rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
          documentProvenance: documentProvenance,
          abstention: LlmScenarioAbstention(
            reason:
                'Model requested ${toolCalls.length} tool calls, exceeding the hard limit of $_maxToolCallsPerTurn.',
            requiredCapability: 'Use fewer tool calls in one generation',
          ),
        );
      }

      if (toolCalls.isEmpty) {
        final payload = _extractAssistantPayloadFromMessage(
          message,
          diagnostics: diagnostics,
          label: 'first_response',
        );
        _log('[LCA] No tool calls. Parsed assistant payload directly');
        final validated = _mapChangesWithValidation(
          payload,
          baseModelFull: baseModelFull,
          optimizationContext: optimizationContext,
          requestedTools: functionsUsed,
          toolMemory: _OptimizationToolMemory(),
        );
        _recordValidationDiagnostics(diagnostics, validated);
        return _ParsedLLMOutput(
          functionsUsed: functionsUsed,
          rawDeltasByScenario:
              validated.rawDeltasByScenario ??
                  const <String, List<Map<String, dynamic>>>{},
          optimizationPayload: validated.optimizationPayload,
          uncertaintyPayload: validated.uncertaintyPayload,
          documentProvenance: documentProvenance,
          abstention: validated.abstention,
        );
      }

      if (formulaCalculatorEnabled) {
        final firstRoundToolNames = <String>{};
        for (final tc in toolCalls) {
          if (tc is! Map) continue;
          final fnRaw = tc['function'];
          if (fnRaw is! Map) continue;
          final name = (fnRaw['name'] ?? '').toString().trim();
          if (name.isNotEmpty) firstRoundToolNames.add(name);
        }
        if (firstRoundToolNames.contains('simplexLatticeDesign') &&
            firstRoundToolNames.contains('formulaCalculator')) {
          _log(
            '[LCA] Formula sequencing warning: formulaCalculator was requested in the same tool round as simplexLatticeDesign.',
          );
        }
      }

      final followup = <Map<String, dynamic>>[
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPayload},
        {
          'role': 'assistant',
          'content': message['content'],
          'tool_calls': toolCalls,
        },
      ];

      var idx = 0;
      var indicatorSearchCalls = 0;
      var documentToolCalls = 0;
      final toolMemory = _OptimizationToolMemory();
      for (final tc in toolCalls) {
        final tool = (tc as Map).cast<String, dynamic>();
        final toolId = tool['id']?.toString() ?? 'tool_call_$idx';
        final fnRaw = tool['function'];
        if (fnRaw is! Map) {
          return _ParsedLLMOutput(
            functionsUsed: functionsUsed,
            rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
            documentProvenance: documentProvenance,
            abstention: const LlmScenarioAbstention(
              reason: 'Tool call payload is malformed (missing function object).',
              requiredCapability: 'Valid tool call schema from the model',
            ),
          );
        }
        final fn = fnRaw.cast<String, dynamic>();
        final name = (fn['name'] ?? '').toString().trim();
        if (name.isEmpty) {
          return _ParsedLLMOutput(
            functionsUsed: functionsUsed,
            rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
            documentProvenance: documentProvenance,
            abstention: const LlmScenarioAbstention(
              reason: 'Tool call payload is malformed (missing function name).',
              requiredCapability: 'Valid tool call schema from the model',
            ),
          );
        }
        functionsUsed.add(name);
        if (name == 'searchOpenLcaIndicators') {
          indicatorSearchCalls += 1;
          if (indicatorSearchCalls > _maxIndicatorSearchCallsPerTurn) {
            return _ParsedLLMOutput(
              functionsUsed: functionsUsed,
              rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
              documentProvenance: documentProvenance,
              abstention: LlmScenarioAbstention(
                reason:
                    'searchOpenLcaIndicators exceeded the hard limit of $_maxIndicatorSearchCallsPerTurn call per generation.',
                requiredCapability:
                    'Resolve indicators with one search call or direct IDs',
              ),
            );
          }
        }
        if (name == 'DocumentParameterisation') {
          documentToolCalls += 1;
          if (documentToolCalls > _maxDocumentToolCallsPerTurn) {
            return _ParsedLLMOutput(
              functionsUsed: functionsUsed,
              rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
              documentProvenance: documentProvenance,
              abstention: LlmScenarioAbstention(
                reason:
                    'DocumentParameterisation exceeded the hard limit of $_maxDocumentToolCallsPerTurn call per generation.',
                requiredCapability:
                    'Resolve document values with one document query call',
              ),
            );
          }
        }
        if (!_isAllowedToolName(name)) {
          _log('[LCA] Blocking non-allow-listed tool request: "$name"');
          return _ParsedLLMOutput(
            functionsUsed: functionsUsed,
            rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
            documentProvenance: documentProvenance,
            abstention: LlmScenarioAbstention(
              reason: 'Tool "$name" is not allow-listed for this workflow.',
              requiredCapability: 'Implement and allow-list tool "$name"',
            ),
          );
        }
        final argsRaw = fn['arguments'];
        Map<String, dynamic> args;
        try {
          final decodedArgs =
              (argsRaw is String) ? jsonDecode(argsRaw) : argsRaw;
          if (decodedArgs is! Map) {
            return _ParsedLLMOutput(
              functionsUsed: functionsUsed,
              rawDeltasByScenario:
                  const <String, List<Map<String, dynamic>>>{},
              documentProvenance: documentProvenance,
              abstention: LlmScenarioAbstention(
                reason:
                    'Tool "$name" arguments must be a JSON object and were rejected.',
                requiredCapability: 'Valid JSON arguments for "$name"',
              ),
            );
          }
          args = decodedArgs.cast<String, dynamic>();
        } on FormatException {
          return _ParsedLLMOutput(
            functionsUsed: functionsUsed,
            rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
            documentProvenance: documentProvenance,
            abstention: LlmScenarioAbstention(
              reason:
                  'Tool "$name" arguments were invalid JSON and execution was blocked.',
              requiredCapability: 'Valid JSON arguments for "$name"',
            ),
          );
        }
        final documentToolAbstention = _validateDocumentToolRequest(
          name: name,
          args: args,
          prompt: prompt,
          uploadedDocuments: uploadedDocuments,
        );
        if (documentToolAbstention != null) {
          return _ParsedLLMOutput(
            functionsUsed: functionsUsed,
            rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
            documentProvenance: documentProvenance,
            abstention: documentToolAbstention,
          );
        }
        _log(
            '[LCA] Executing tool[$idx] name=$name id=$toolId args=${jsonEncode(args)}');

        final localResult = await _runLocalFunction(
          name,
          args,
          baseModelFull,
          optimizationContext,
          prompt: prompt,
          uploadedDocuments: uploadedDocuments,
        );
        final Map<String, dynamic> toolReturn =
            _wrapToolResult(name, localResult);
        _captureDocumentProvenance(
          name: name,
          toolReturn: toolReturn,
          documentProvenance: documentProvenance,
        );
        _recordToolResult(
          controller: this,
          name: name,
          args: args,
          toolReturn: toolReturn,
          toolMemory: toolMemory,
        );
        final rawToolContent = jsonEncode(toolReturn);
        final toolContent = _toolContentForFollowup(name, toolReturn);
        _log(
            '[LCA] Tool[$idx] result keys=${toolReturn.keys.join(', ')} '
            'rawBytes=${utf8.encode(rawToolContent).length} '
            'followupBytes=${utf8.encode(toolContent).length}');

        followup.add({
          'role': 'tool',
          'tool_call_id': toolId,
          'content': toolContent,
        });
        idx += 1;
      }

      followup.add({
        'role': 'user',
        'content': formulaCalculatorEnabled &&
                functionsUsed.contains('simplexLatticeDesign') &&
                !functionsUsed.contains('formulaCalculator')
            ? _formulaCalculatorFollowupReminder(toolMemory)
            : _finalJsonOnlyReminder(),
      });

      _log('[LCA] Second $providerLabel call for final scenarios (JSON only)');
      final secondResp = await _callOpenAI(
        systemPrompt: systemPrompt,
        userPayload: userPayload,
        functions: formulaCalculatorEnabled &&
                functionsUsed.contains('simplexLatticeDesign') &&
                !functionsUsed.contains('formulaCalculator')
            ? functions
            : null,
        functionCallMode: formulaCalculatorEnabled &&
                functionsUsed.contains('simplexLatticeDesign') &&
                !functionsUsed.contains('formulaCalculator')
            ? 'formulaCalculator'
            : 'auto',
        messagesOverride: followup,
        jsonOnly: !(formulaCalculatorEnabled &&
            functionsUsed.contains('simplexLatticeDesign') &&
            !functionsUsed.contains('formulaCalculator')),
        callLabel: 'second_call_after_tools',
      );
      diagnostics['second_response'] = _chatResponseDiagnostics(secondResp);

      final secondMessage =
          (secondResp['choices'] as List).first['message'] as Map<String, dynamic>;
      final rawSecondToolCalls = secondMessage['tool_calls'];
      final recoveredSecondToolCalls =
          rawSecondToolCalls is List && rawSecondToolCalls.isNotEmpty
              ? const <Map<String, dynamic>>[]
              : _extractInlineToolCallsFromContent(
                  _extractContentText(secondMessage['content']),
                );
      final secondToolCalls =
          rawSecondToolCalls is List && rawSecondToolCalls.isNotEmpty
              ? rawSecondToolCalls
              : recoveredSecondToolCalls;
      if (recoveredSecondToolCalls.isNotEmpty) {
        _log(
          '[LCA] Recovered ${recoveredSecondToolCalls.length} inline second-round tool call(s) from assistant content',
        );
      }
      if (secondToolCalls.isNotEmpty) {
        _log('[LCA] second tool_calls count=${secondToolCalls.length}');
        if (secondToolCalls.length > _maxToolCallsPerTurn) {
          return _ParsedLLMOutput(
            functionsUsed: functionsUsed,
            rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
            documentProvenance: documentProvenance,
            abstention: LlmScenarioAbstention(
              reason:
                  'Model requested ${secondToolCalls.length} second-round tool calls, exceeding the hard limit of $_maxToolCallsPerTurn.',
              requiredCapability: 'Use fewer tool calls in one generation',
            ),
          );
        }

        followup.add({
          'role': 'assistant',
          'content': secondMessage['content'],
          'tool_calls': secondToolCalls,
        });

        var secondIdx = 0;
        for (final tc in secondToolCalls) {
          final tool = (tc as Map).cast<String, dynamic>();
          final toolId = tool['id']?.toString() ?? 'second_tool_call_$secondIdx';
          final fnRaw = tool['function'];
          if (fnRaw is! Map) {
            return _ParsedLLMOutput(
              functionsUsed: functionsUsed,
              rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
              documentProvenance: documentProvenance,
              abstention: const LlmScenarioAbstention(
                reason:
                    'Second-round tool call payload is malformed (missing function object).',
                requiredCapability: 'Valid tool call schema from the model',
              ),
            );
          }
          final fn = fnRaw.cast<String, dynamic>();
          final name = (fn['name'] ?? '').toString().trim();
          if (name != 'formulaCalculator') {
            return _ParsedLLMOutput(
              functionsUsed: functionsUsed,
              rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
              documentProvenance: documentProvenance,
              abstention: LlmScenarioAbstention(
                reason:
                    'Only formulaCalculator is allowed in the second tool round; model requested "$name".',
                requiredCapability:
                    'Use formulaCalculator or output final JSON directly',
              ),
            );
          }
          functionsUsed.add(name);

          final argsRaw = fn['arguments'];
          Map<String, dynamic> args;
          try {
            final decodedArgs =
                (argsRaw is String) ? jsonDecode(argsRaw) : argsRaw;
            if (decodedArgs is! Map) {
              return _ParsedLLMOutput(
                functionsUsed: functionsUsed,
                rawDeltasByScenario:
                    const <String, List<Map<String, dynamic>>>{},
                documentProvenance: documentProvenance,
                abstention: const LlmScenarioAbstention(
                  reason:
                      'formulaCalculator arguments must be a JSON object and were rejected.',
                  requiredCapability: 'Valid JSON arguments for formulaCalculator',
                ),
              );
            }
            args = decodedArgs.cast<String, dynamic>();
          } on FormatException {
            return _ParsedLLMOutput(
              functionsUsed: functionsUsed,
              rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
              documentProvenance: documentProvenance,
              abstention: const LlmScenarioAbstention(
                reason:
                    'formulaCalculator arguments were invalid JSON and execution was blocked.',
                requiredCapability: 'Valid JSON arguments for formulaCalculator',
              ),
            );
          }

          _log(
              '[LCA] Executing second-round tool[$secondIdx] name=$name id=$toolId args=${jsonEncode(args)}');
          final localResult = await _runLocalFunction(
            name,
            args,
            baseModelFull,
            optimizationContext,
            prompt: prompt,
            uploadedDocuments: uploadedDocuments,
          );
          final Map<String, dynamic> toolReturn =
              _wrapToolResult(name, localResult);
          _recordToolResult(
            controller: this,
            name: name,
            args: args,
            toolReturn: toolReturn,
            toolMemory: toolMemory,
          );
          final rawToolContent = jsonEncode(toolReturn);
          final toolContent = _toolContentForFollowup(name, toolReturn);
          _log(
              '[LCA] Second-round tool[$secondIdx] result keys=${toolReturn.keys.join(', ')} '
              'rawBytes=${utf8.encode(rawToolContent).length} '
              'followupBytes=${utf8.encode(toolContent).length}');

          followup.add({
            'role': 'tool',
            'tool_call_id': toolId,
            'content': toolContent,
          });
          secondIdx += 1;
        }

        followup.add({
          'role': 'user',
          'content': _finalJsonOnlyReminder(formulaResultsAvailable: true),
        });

        _log('[LCA] Third $providerLabel call for final scenarios (JSON only)');
        final thirdResp = await _callOpenAI(
          systemPrompt: systemPrompt,
          userPayload: userPayload,
          messagesOverride: followup,
          jsonOnly: true,
          callLabel: 'third_call_after_formula_tool',
        );
        diagnostics['third_response'] = _chatResponseDiagnostics(thirdResp);

        final payload = _extractAssistantPayloadFromMessage(
          (thirdResp['choices'] as List).first['message'],
          diagnostics: diagnostics,
          label: 'third_response',
        );
        _log('[LCA] Final payload received. Validating and mapping changes');
        final validated = _mapChangesWithValidation(
          payload,
          baseModelFull: baseModelFull,
          optimizationContext: optimizationContext,
          requestedTools: functionsUsed,
          toolMemory: toolMemory,
        );
        _recordValidationDiagnostics(diagnostics, validated);
        return _ParsedLLMOutput(
          functionsUsed: functionsUsed,
          rawDeltasByScenario: validated.rawDeltasByScenario ??
              const <String, List<Map<String, dynamic>>>{},
          optimizationPayload: validated.optimizationPayload,
          uncertaintyPayload: validated.uncertaintyPayload,
          documentProvenance: documentProvenance,
          abstention: validated.abstention,
        );
      }

      final payload = _extractAssistantPayloadFromMessage(
        secondMessage,
        diagnostics: diagnostics,
        label: 'second_response',
      );
      _log('[LCA] Final payload received. Validating and mapping changes');
      final validated = _mapChangesWithValidation(
        payload,
        baseModelFull: baseModelFull,
        optimizationContext: optimizationContext,
        requestedTools: functionsUsed,
        toolMemory: toolMemory,
      );
      _recordValidationDiagnostics(diagnostics, validated);
      return _ParsedLLMOutput(
        functionsUsed: functionsUsed,
        rawDeltasByScenario: validated.rawDeltasByScenario ??
            const <String, List<Map<String, dynamic>>>{},
        optimizationPayload: validated.optimizationPayload,
        uncertaintyPayload: validated.uncertaintyPayload,
        documentProvenance: documentProvenance,
        abstention: validated.abstention,
      );
    }
    // Legacy function_call path
    else if (message.containsKey('function_call') &&
        message['function_call'] != null) {
      final functionCall =
          (message['function_call'] as Map).cast<String, dynamic>();
      final name = (functionCall['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        return _ParsedLLMOutput(
          functionsUsed: functionsUsed,
          rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
          documentProvenance: documentProvenance,
          abstention: const LlmScenarioAbstention(
            reason:
                'Legacy function_call payload is malformed (missing function name).',
            requiredCapability: 'Valid tool call schema from the model',
          ),
        );
      }
      functionsUsed.add(name);
      if (!_isAllowedToolName(name)) {
        _log('[LCA] Blocking non-allow-listed legacy function call: "$name"');
        return _ParsedLLMOutput(
          functionsUsed: functionsUsed,
          rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
          documentProvenance: documentProvenance,
          abstention: LlmScenarioAbstention(
            reason: 'Tool "$name" is not allow-listed for this workflow.',
            requiredCapability: 'Implement and allow-list tool "$name"',
          ),
        );
      }
      final argsRaw = functionCall['arguments'];
      Map<String, dynamic> args;
      try {
        final decodedArgs = (argsRaw is String) ? jsonDecode(argsRaw) : argsRaw;
        if (decodedArgs is! Map) {
          return _ParsedLLMOutput(
            functionsUsed: functionsUsed,
            rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
            documentProvenance: documentProvenance,
            abstention: LlmScenarioAbstention(
              reason:
                  'Tool "$name" arguments must be a JSON object and were rejected.',
              requiredCapability: 'Valid JSON arguments for "$name"',
            ),
          );
        }
        args = decodedArgs.cast<String, dynamic>();
      } on FormatException {
        return _ParsedLLMOutput(
          functionsUsed: functionsUsed,
          rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
          documentProvenance: documentProvenance,
          abstention: LlmScenarioAbstention(
            reason:
                'Tool "$name" arguments were invalid JSON and execution was blocked.',
            requiredCapability: 'Valid JSON arguments for "$name"',
          ),
        );
      }
      _log('[LCA] Legacy function_call name=$name args=${jsonEncode(args)}');

      final documentToolAbstention = _validateDocumentToolRequest(
        name: name,
        args: args,
        prompt: prompt,
        uploadedDocuments: uploadedDocuments,
      );
      if (documentToolAbstention != null) {
        return _ParsedLLMOutput(
          functionsUsed: functionsUsed,
          rawDeltasByScenario: const <String, List<Map<String, dynamic>>>{},
          documentProvenance: documentProvenance,
          abstention: documentToolAbstention,
        );
      }

      final localResult = await _runLocalFunction(
        name,
        args,
        baseModelFull,
        optimizationContext,
        prompt: prompt,
        uploadedDocuments: uploadedDocuments,
      );
      final toolMemory = _OptimizationToolMemory();
      final Map<String, dynamic> toolReturn =
          _wrapToolResult(name, localResult);
      _captureDocumentProvenance(
        name: name,
        toolReturn: toolReturn,
        documentProvenance: documentProvenance,
      );
      _recordToolResult(
        controller: this,
        name: name,
        args: args,
        toolReturn: toolReturn,
        toolMemory: toolMemory,
      );
      final rawToolContent = jsonEncode(toolReturn);
      final toolContent = _toolContentForFollowup(name, toolReturn);
      _log(
          '[LCA] Legacy function_call local result keys=${toolReturn.keys.join(', ')} '
          'rawBytes=${utf8.encode(rawToolContent).length} '
          'followupBytes=${utf8.encode(toolContent).length}');

      final secondMessages = [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPayload},
        {
          'role': 'assistant',
          'content': null,
          'function_call': {'name': name, 'arguments': jsonEncode(args)},
        },
        {'role': 'function', 'name': name, 'content': toolContent},
        {
          'role': 'user',
          'content': _finalJsonOnlyReminder(
            formulaResultsAvailable: name == 'formulaCalculator',
          ),
        },
      ];

      _log('[LCA] Second $providerLabel call for final scenarios (JSON only)');
      final secondResp = await _callOpenAI(
        systemPrompt: systemPrompt,
        userPayload: userPayload,
        messagesOverride: secondMessages,
        jsonOnly: true,
        callLabel: 'second_call_after_legacy_function',
      );
      diagnostics['second_response'] = _chatResponseDiagnostics(secondResp);

      final payload = _extractAssistantPayloadFromMessage(
        (secondResp['choices'] as List).first['message'],
        diagnostics: diagnostics,
        label: 'second_response',
      );
      _log('[LCA] Final payload received. Validating and mapping changes');
      final validated = _mapChangesWithValidation(
        payload,
        baseModelFull: baseModelFull,
        optimizationContext: optimizationContext,
        requestedTools: functionsUsed,
        toolMemory: toolMemory,
      );
      _recordValidationDiagnostics(diagnostics, validated);
      return _ParsedLLMOutput(
        functionsUsed: functionsUsed,
        rawDeltasByScenario: validated.rawDeltasByScenario ??
            const <String, List<Map<String, dynamic>>>{},
        optimizationPayload: validated.optimizationPayload,
        uncertaintyPayload: validated.uncertaintyPayload,
        documentProvenance: documentProvenance,
        abstention: validated.abstention,
      );
    }
    // Direct scenarios
    else {
      _log('[LCA] No tools. Attempting to parse assistant payload directly');
      final payload = _extractAssistantPayloadFromMessage(
        message,
        diagnostics: diagnostics,
        label: 'first_response',
      );
      final validated = _mapChangesWithValidation(
        payload,
        baseModelFull: baseModelFull,
        optimizationContext: optimizationContext,
        requestedTools: functionsUsed,
        toolMemory: _OptimizationToolMemory(),
      );
      _recordValidationDiagnostics(diagnostics, validated);
      rawDeltasByScenario = validated.rawDeltasByScenario ??
          const <String, List<Map<String, dynamic>>>{};
      if (validated.abstention == null) {
        _log('[LCA] Direct scenarios validated and mapped');
      }
      return _ParsedLLMOutput(
        functionsUsed: functionsUsed,
        rawDeltasByScenario: rawDeltasByScenario,
        optimizationPayload: validated.optimizationPayload,
        uncertaintyPayload: validated.uncertaintyPayload,
        documentProvenance: documentProvenance,
        abstention: validated.abstention,
      );
    }

    return _ParsedLLMOutput(
      functionsUsed: functionsUsed,
      rawDeltasByScenario: rawDeltasByScenario,
      documentProvenance: documentProvenance,
      abstention: null,
    );
  }

  void _recordValidationDiagnostics(
    Map<String, dynamic> diagnostics,
    _ValidatedScenarioChanges validated,
  ) {
    diagnostics['validation'] = {
      'status': validated.abstention == null ? 'accepted' : 'rejected',
      if (validated.abstention != null)
        'abstention': validated.abstention!.toJson(),
      'scenario_count': validated.rawDeltasByScenario?.length ?? 0,
      'change_count': validated.rawDeltasByScenario?.values.fold<int>(
            0,
            (sum, changes) => sum + changes.length,
          ) ??
          0,
      'has_optimization_payload': validated.optimizationPayload != null,
      'has_uncertainty_payload': validated.uncertaintyPayload != null,
    };
  }

  /// Wrap local tool output in a shape the LLM prompt expects.
  Map<String, dynamic> _wrapToolResult(String name, dynamic localResult) {
    switch (name) {
      case 'DocumentParameterisation':
      case 'searchOpenLcaIndicators':
        return localResult is Map<String, dynamic>
            ? localResult
            : {'matches': localResult};
      case 'simplexLatticeDesign':
        return _simplexToolResult(localResult);
      case 'oneAtATimeSensitivity':
        return {'changeLists': localResult};
      case 'formulaCalculator':
        return localResult is Map<String, dynamic>
            ? localResult
            : {'result': localResult};
      default:
        return {'result': localResult};
    }
  }

  Map<String, dynamic> _simplexToolResult(dynamic localResult) {
    return {
      'changeLists': localResult,
      if (localResult is List)
        'candidate_summaries': _simplexCandidateSummaries(localResult),
      if (localResult is List)
        'candidate_usage': {
          'id_rule': 'Use candidate_summaries[].id as formulaCalculator id.',
          'argument_source':
              'Use candidate_summaries[].parameter_values for formula arguments derived from lattice candidates.',
          'final_json_rule':
              'Final scenarios must copy the matching changeLists entry for the same candidate id/order.',
        },
    };
  }

  List<Map<String, dynamic>> _simplexCandidateSummaries(List<dynamic> changeLists) {
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < changeLists.length; i += 1) {
      final changes = changeLists[i];
      final parameterValues = <String, double>{};
      if (changes is List) {
        for (final rawChange in changes) {
          if (rawChange is! Map) continue;
          final change = rawChange.cast<String, dynamic>();
          final field = (change['field'] ?? '').toString().trim();
          final value = _toFiniteDouble(change['new_value']);
          if (value == null) continue;
          final paramName = _parameterNameFromChangeField(field);
          if (paramName != null) parameterValues[paramName] = value;
        }
      }
      out.add({
        'id': 'candidate_${i + 1}',
        'change_list_index': i,
        'parameter_values': parameterValues,
      });
    }
    return out;
  }

  String? _parameterNameFromChangeField(String field) {
    if (field.startsWith('parameters.global.')) {
      final name = field.substring('parameters.global.'.length).trim();
      return name.isEmpty ? null : name;
    }
    if (field.startsWith('parameters.process.')) {
      final name = field.substring('parameters.process.'.length).trim();
      return name.isEmpty ? null : name;
    }
    if (field.startsWith('parameters.process:')) {
      final rest = field.substring('parameters.process:'.length);
      final dot = rest.indexOf('.');
      if (dot <= 0 || dot >= rest.length - 1) return null;
      final name = rest.substring(dot + 1).trim();
      return name.isEmpty ? null : name;
    }
    return null;
  }

  String _toolContentForFollowup(String name, Map<String, dynamic> toolReturn) {
    final payload = _followupToolPayload(name, toolReturn);
    return jsonEncode(payload);
  }

  Map<String, dynamic> _followupToolPayload(
    String name,
    Map<String, dynamic> toolReturn,
  ) {
    if (name == 'DocumentParameterisation') {
      return _compactDocumentToolPayload(toolReturn);
    }
    if (name == 'formulaCalculator') {
      return _formulaToolPayload(toolReturn);
    }
    return toolReturn;
  }

  Map<String, dynamic> _formulaToolPayload(Map<String, dynamic> toolReturn) {
    return {
      ...toolReturn,
      'final_json_usage': {
        'formula_value_source': 'formulaCalculator.results only',
        'candidate_mapping':
            'Match each final scenario only to the formula result with the same candidate id/order.',
        'if_unclear':
            'Omit formula values from scenario names rather than recalculating or guessing.',
      },
    };
  }

  Map<String, dynamic> _compactDocumentToolPayload(
    Map<String, dynamic> toolReturn,
  ) {
    final out = <String, dynamic>{
      if (toolReturn['success'] != null) 'success': toolReturn['success'] == true,
      'followup_note':
          'Use the extracted values below to build the final JSON. '
              'Do not return this document payload or document metadata.',
    };

    final rawDocument = toolReturn['document'];
    if (rawDocument is Map) {
      out['document'] = _compactDocumentMetadata(
        rawDocument.cast<String, dynamic>(),
      );
    }

    if (toolReturn['total_results'] != null) {
      out['total_results'] =
          _toInt(toolReturn['total_results']) ?? toolReturn['total_results'];
    }
    if (toolReturn['total_matches'] != null) {
      out['total_matches'] =
          _toInt(toolReturn['total_matches']) ?? toolReturn['total_matches'];
    }

    final results = toolReturn['results'];
    if (results is List) {
      final compactResults = <Map<String, dynamic>>[];
      for (final item in results) {
        if (item is! Map) continue;
        compactResults.add(
          _compactDocumentQueryRecord(item.cast<String, dynamic>()),
        );
      }
      out['results'] = compactResults;
      return out;
    }

    final compactSingle = _compactDocumentQueryRecord(toolReturn);
    out.addAll(compactSingle);
    return out;
  }

  Map<String, dynamic> _compactDocumentMetadata(Map<String, dynamic> raw) {
    return {
      if ((raw['id'] ?? '').toString().trim().isNotEmpty) 'id': raw['id'],
      if ((raw['name'] ?? '').toString().trim().isNotEmpty) 'name': raw['name'],
      if ((raw['kind'] ?? '').toString().trim().isNotEmpty) 'kind': raw['kind'],
      if (_toInt(raw['page_count']) != null) 'page_count': _toInt(raw['page_count']),
      if (_toInt(raw['detected_table_count']) != null)
        'detected_table_count': _toInt(raw['detected_table_count']),
      if (_coercePositiveIntList(raw['detected_table_pages']).isNotEmpty)
        'detected_table_pages': _coercePositiveIntList(raw['detected_table_pages']),
    };
  }

  Map<String, dynamic> _compactDocumentQueryRecord(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    final query = (raw['query'] ?? '').toString().trim();
    if (query.isNotEmpty) out['query'] = query;

    final pageNumbers = _coercePositiveIntList(raw['page_numbers']);
    if (pageNumbers.isNotEmpty) out['page_numbers'] = pageNumbers;

    final assumptions = _documentStringList(raw['assumptions']);
    if (assumptions.isNotEmpty) out['assumptions'] = assumptions.take(5).toList();

    final matches = _documentMapList(raw['matches']);
    final selectedMatches = _selectDocumentMatchesForFollowup(matches);
    if (selectedMatches.isNotEmpty) {
      out['matches'] = [
        for (final match in selectedMatches) _compactDocumentMatchForFollowup(match),
      ];
      if (matches.length > selectedMatches.length) {
        out['omitted_match_count'] = matches.length - selectedMatches.length;
      }
    }

    final fallbackMatches = _documentMapList(raw['fallback_text_matches']);
    if (fallbackMatches.isNotEmpty) {
      out['fallback_text_matches'] = _compactDocumentFallbackTextMatches(
        fallbackMatches,
      );
      if (fallbackMatches.length > _maxDocumentFallbackTextMatchesForFollowup) {
        out['omitted_fallback_text_match_count'] =
            fallbackMatches.length - _maxDocumentFallbackTextMatchesForFollowup;
      }
    }

    if (_toInt(raw['total_matches']) != null) {
      out['total_matches'] = _toInt(raw['total_matches']);
    } else if (matches.isNotEmpty) {
      out['total_matches'] = matches.length;
    }
    return out;
  }

  List<Map<String, dynamic>> _selectDocumentMatchesForFollowup(
    List<Map<String, dynamic>> matches,
  ) {
    if (matches.isEmpty) return const <Map<String, dynamic>>[];
    final sorted = matches.toList()
      ..sort((left, right) {
        final priorityDelta = _documentMatchPriorityScore(right) -
            _documentMatchPriorityScore(left);
        if (priorityDelta != 0) return priorityDelta;
        final scoreLeft = _toFiniteDouble(left['score']) ?? 0;
        final scoreRight = _toFiniteDouble(right['score']) ?? 0;
        return scoreRight.compareTo(scoreLeft);
      });
    return sorted.take(_maxDocumentMatchesPerQueryForFollowup).toList();
  }

  int _documentMatchPriorityScore(Map<String, dynamic> match) {
    final normalizedHeaders = _documentStringList(match['headers'])
        .map(_normalizeReferenceText)
        .toSet();
    var score = 0;
    if (normalizedHeaders.contains('parameter')) score += 300;
    if (normalizedHeaders.contains('scenario value')) score += 240;
    if (normalizedHeaders.contains('baseline')) score += 120;
    if (normalizedHeaders.contains('unit')) score += 40;
    if (normalizedHeaders.contains('scenario') &&
        normalizedHeaders.contains('short name')) {
      score += 25;
    }
    final rows = match['rows'];
    if (rows is List) {
      final rowCount = rows.length;
      score += rowCount > 20 ? 20 : rowCount;
    }
    return score;
  }

  Map<String, dynamic> _compactDocumentMatchForFollowup(
    Map<String, dynamic> raw,
  ) {
    final out = <String, dynamic>{};
    if (_toInt(raw['page_number']) != null) {
      out['page_number'] = _toInt(raw['page_number']);
    }
    if (_toInt(raw['table_index']) != null) {
      out['table_index'] = _toInt(raw['table_index']);
    }
    final score = _toFiniteDouble(raw['score']);
    if (score != null) out['score'] = score;

    final headers = _documentStringList(raw['headers']);
    if (headers.isNotEmpty) out['headers'] = headers;

    final rowMaps = _documentMapList(raw['rows']);
    if (rowMaps.isNotEmpty) {
      out['rows'] = [
        for (final row in rowMaps.take(_maxDocumentRowsPerMatchForFollowup))
          _compactDocumentRowForFollowup(row, headers),
      ];
      if (rowMaps.length > _maxDocumentRowsPerMatchForFollowup) {
        out['omitted_row_count'] =
            rowMaps.length - _maxDocumentRowsPerMatchForFollowup;
      }
    }
    return out;
  }

  Map<String, dynamic> _compactDocumentRowForFollowup(
    Map<String, dynamic> raw,
    List<String> headers,
  ) {
    final out = <String, dynamic>{};
    if (_toInt(raw['row_index']) != null) {
      out['row_index'] = _toInt(raw['row_index']);
    }

    final rowObject = raw['row_object'];
    final compactObject = <String, dynamic>{};
    if (rowObject is Map) {
      for (final entry in rowObject.entries) {
        final key = entry.key.toString().trim();
        if (key.isEmpty) continue;
        compactObject[key] = _compactDocumentScalar(entry.value);
      }
    }

    if (compactObject.isEmpty) {
      final values = _documentStringList(raw['values']);
      final limit = headers.length < values.length ? headers.length : values.length;
      for (var i = 0; i < limit; i += 1) {
        final key = headers[i].trim();
        if (key.isEmpty) continue;
        compactObject[key] = _compactDocumentScalar(values[i]);
      }
      if (compactObject.isEmpty && values.isNotEmpty) {
        out['values'] = values.map(_compactDocumentString).toList();
      }
    }

    if (compactObject.isNotEmpty) {
      out['row_object'] = compactObject;
    }
    return out;
  }

  List<Map<String, dynamic>> _compactDocumentFallbackTextMatches(
    List<Map<String, dynamic>> matches,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final item in matches.take(_maxDocumentFallbackTextMatchesForFollowup)) {
      final entry = <String, dynamic>{};
      if (_toInt(item['page_number']) != null) {
        entry['page_number'] = _toInt(item['page_number']);
      }
      final text = (item['text'] ?? item['snippet'] ?? '').toString().trim();
      if (text.isNotEmpty) {
        entry['text'] = _compactDocumentString(text);
      }
      if (entry.isNotEmpty) out.add(entry);
    }
    return out;
  }

  dynamic _compactDocumentScalar(dynamic value) {
    if (value == null || value is num || value is bool) return value;
    return _compactDocumentString(value.toString());
  }

  String _compactDocumentString(String value) {
    final compact = value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (compact.length <= _maxDocumentValueCharsForFollowup) {
      return compact;
    }
    return '${compact.substring(0, _maxDocumentValueCharsForFollowup)}...';
  }

  List<Map<String, dynamic>> _documentMapList(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final item in value) {
      if (item is Map) {
        out.add(item.cast<String, dynamic>());
      }
    }
    return out;
  }

  List<String> _documentStringList(dynamic value) {
    if (value is! List) return const <String>[];
    final out = <String>[];
    for (final item in value) {
      final text = item.toString().trim();
      if (text.isNotEmpty) out.add(text);
    }
    return out;
  }

  /// Local numeric or data function execution.
  Future<dynamic> _runLocalFunction(
    String name,
    Map<String, dynamic> args,
    Map<String, dynamic> baseModelFull,
    Map<String, dynamic> optimizationContext,
    {
    required String prompt,
    required List<LlmDocumentReference> uploadedDocuments,
  }) async {
    _log('[LCA] _runLocalFunction dispatch name=$name');
    switch (name) {
      case 'DocumentParameterisation':
        final resolvedDocument = _resolveDocumentForToolCall(
          args: args,
          prompt: prompt,
          uploadedDocuments: uploadedDocuments,
        );
        if (resolvedDocument == null) {
          throw Exception('DocumentParameterisation requires a valid uploaded document.');
        }
        final rawQueries = args['queries'];
        if (rawQueries is List && rawQueries.isNotEmpty) {
          final batchArgs = <Map<String, dynamic>>[];
          for (final item in rawQueries.take(5)) {
            if (item is! Map) continue;
            final itemArgs = item.cast<String, dynamic>();
            final itemQuery = (itemArgs['query'] ?? '').toString().trim();
            if (itemQuery.isEmpty) continue;
            final itemPages = _coercePositiveIntList(itemArgs['page_numbers']);
            batchArgs.add({
              'query': itemQuery,
              if (itemPages.isNotEmpty) 'page_numbers': itemPages,
              if (itemArgs['max_tables'] != null)
                'max_tables': itemArgs['max_tables'],
              if (itemArgs['max_rows'] != null) 'max_rows': itemArgs['max_rows'],
            });
          }
          final batchResult = await documentService.queryDocumentBatch(
            documentId: resolvedDocument.id,
            queries: batchArgs,
            maxTables: _toInt(args['max_tables']),
            maxRows: _toInt(args['max_rows']),
          );
          final totalMatches = _toInt(batchResult['total_matches']) ??
              ((batchResult['results'] as List?)?.fold<int>(
                    0,
                    (sum, item) =>
                        sum +
                        (((item as Map?)?['matches'] as List?)?.length ?? 0),
                  ) ??
                  0);
          _log(
            '[LCA] DocumentParameterisation batch returned '
            '${_toInt(batchResult['total_results']) ?? (batchResult['results'] as List?)?.length ?? 0} result(s), '
            '$totalMatches total match(es)',
          );
          return batchResult;
        }

        final pageNumbers = _coercePositiveIntList(args['page_numbers']);
        final result = await documentService.queryDocument(
          documentId: resolvedDocument.id,
          query: (args['query'] ?? '').toString().trim(),
          pageNumbers: pageNumbers.isEmpty ? null : pageNumbers,
          maxTables: ((_toInt(args['max_tables']) ?? 5).clamp(1, 5)).toInt(),
          maxRows: ((_toInt(args['max_rows']) ?? 15).clamp(1, 25)).toInt(),
        );
        _log(
          '[LCA] DocumentParameterisation returned '
          '${((result['matches'] as List?)?.length ?? 0)} table match(es)',
        );
        return result;
      case 'searchOpenLcaIndicators':
        final queriesRaw = args['queries'];
        List<Map<String, dynamic>>? queries;
        if (queriesRaw is List) {
          queries = <Map<String, dynamic>>[];
          for (final item in queriesRaw) {
            if (item is! Map) continue;
            queries.add(item.cast<String, dynamic>());
          }
        }
        final result = _searchOpenLcaIndicators(
          query: (args['query'] ?? '').toString(),
          methodHint: (args['method_hint'] ?? '').toString(),
          limit: _toInt(args['limit']) ?? 5,
          queries: queries,
          optimizationContext: optimizationContext,
        );
        final totalMatches = _toInt(result['total_matches']) ??
            ((result['matches'] as List?)?.length ?? 0);
        _log('[LCA] searchOpenLcaIndicators returned $totalMatches match(es)');
        return result;
      case 'oneAtATimeSensitivity':
        final ofat = oneAtATimeSensitivity(
          baseModel: baseModelFull,
          parameterNames: (args['parameterNames'] as List).cast<String>(),
          percent: (args['percent'] as num).toDouble(),
          levels: (args['levels'] as List?)
              ?.cast<num>()
              .map((n) => n.toDouble())
              .toList(),
        );
        _log('[LCA] oneAtATimeSensitivity produced ${ofat.length} change-list(s)');
        return ofat;
      case 'simplexLatticeDesign':
        final simplex = simplexLatticeDesign(
          baseModel: baseModelFull,
          parameterNames: (args['parameterNames'] as List).cast<String>(),
          m: (args['m'] as num).toInt(),
          removeEdges: args['removeEdges'] == true,
        );
        _log('[LCA] simplexLatticeDesign produced ${simplex.length} change-list(s)');
        return simplex;
      case 'formulaCalculator':
        final rawCalculations = args['calculations'];
        if (rawCalculations is! List || rawCalculations.isEmpty) {
          throw Exception('formulaCalculator requires a non-empty calculations list.');
        }
        final calculations = <Map<String, dynamic>>[];
        for (final item in rawCalculations.take(120)) {
          if (item is! Map) continue;
          calculations.add(item.cast<String, dynamic>());
        }
        final result = formulaCalculator(calculations: calculations);
        _log(
          '[LCA] formulaCalculator produced '
          '${((result['results'] as List?)?.length ?? 0)} result(s)',
        );
        return result;
      default:
        _log('[LCA] Unknown function or tool: $name');
        throw Exception('Unknown function or tool: $name');
    }
  }

  bool _isAllowedToolName(String name) {
    return llmFunctionsForVariant(
      formulaCalculatorEnabled: formulaCalculatorEnabled,
    )
        .map((f) => (f['name'] ?? '').toString().trim())
        .where((toolName) => toolName.isNotEmpty)
        .contains(name.trim());
  }

  void _captureDocumentProvenance({
    required String name,
    required Map<String, dynamic> toolReturn,
    required List<DocumentExtractionRecord> documentProvenance,
  }) {
    if (name != 'DocumentParameterisation') return;
    try {
      final rawResults = toolReturn['results'];
      if (rawResults is List) {
        for (final item in rawResults) {
          if (item is! Map) continue;
          final merged = <String, dynamic>{
            'document': toolReturn['document'],
            ...item.cast<String, dynamic>(),
          };
          final record = DocumentExtractionRecord.fromToolResult(merged);
          documentProvenance.add(record);
          _log(
            '[LCA] DocumentParameterisation source="${record.sourceLabel}" '
            'query="${record.query}"',
          );
        }
        return;
      }

      final record = DocumentExtractionRecord.fromToolResult(toolReturn);
      documentProvenance.add(record);
      _log(
        '[LCA] DocumentParameterisation source="${record.sourceLabel}" '
        'query="${record.query}"',
      );
    } catch (e) {
      _log('[LCA] Failed to capture document provenance: $e');
    }
  }

  LlmScenarioAbstention? _validateDocumentToolRequest({
    required String name,
    required Map<String, dynamic> args,
    required String prompt,
    required List<LlmDocumentReference> uploadedDocuments,
  }) {
    if (name != 'DocumentParameterisation') return null;
    if (uploadedDocuments.isEmpty) {
      return const LlmScenarioAbstention(
        reason:
            'DocumentParameterisation was requested but no PDF has been uploaded.',
        requiredCapability: 'Upload a PDF before requesting document-derived values',
      );
    }
    final query = (args['query'] ?? '').toString().trim();
    final rawQueries = args['queries'];
    final hasBatchQueries = rawQueries is List && rawQueries.isNotEmpty;
    if (query.isEmpty && !hasBatchQueries) {
      return const LlmScenarioAbstention(
        reason:
            'DocumentParameterisation requires either a non-empty "query" or a non-empty "queries" array.',
        requiredCapability: 'Valid document tool query arguments',
      );
    }
    if (hasBatchQueries) {
      if (rawQueries.length > 5) {
        return const LlmScenarioAbstention(
          reason:
              'DocumentParameterisation "queries" may include at most 5 items.',
          requiredCapability: 'Document tool batch limit (<=5 queries)',
        );
      }
      for (final item in rawQueries) {
        if (item is! Map) {
          return const LlmScenarioAbstention(
            reason:
                'DocumentParameterisation "queries" must be an array of objects.',
            requiredCapability: 'Valid document tool batch query arguments',
          );
        }
        final itemQuery = (item['query'] ?? '').toString().trim();
        if (itemQuery.isEmpty) {
          return const LlmScenarioAbstention(
            reason:
                'DocumentParameterisation batch items require a non-empty "query".',
            requiredCapability: 'Valid document tool batch query arguments',
          );
        }
      }
    }
    final promptReferencesDocument = _promptReferencesDocument(prompt);
    if (!promptReferencesDocument) {
      return const LlmScenarioAbstention(
        reason:
            'DocumentParameterisation may only be used when the prompt clearly refers to an uploaded document, appendix, table, section, or source material.',
        requiredCapability:
            'Clear document reference in the user prompt before using document extraction',
      );
    }
    final requestedDocument = _resolveDocumentForToolCall(
      args: args,
      prompt: prompt,
      uploadedDocuments: uploadedDocuments,
    );
    if (requestedDocument == null) {
      return const LlmScenarioAbstention(
        reason:
            'DocumentParameterisation could not determine a reasonable uploaded PDF to query.',
        requiredCapability:
            'Provide a clearer document cue or upload only the relevant PDF',
      );
    }
    return null;
  }

  bool _promptReferencesDocument(String prompt) {
    final normalizedPrompt = _normalizeReferenceText(prompt);
    final genericCuePatterns = <RegExp>[
      RegExp(r'\bfrom the document\b'),
      RegExp(r'\bfrom document\b'),
      RegExp(r'\buploaded document\b'),
      RegExp(r'\bsource document\b'),
      RegExp(r'\bthe document\b'),
      RegExp(r'\bthis document\b'),
      RegExp(r'\bpdf\b'),
      RegExp(r'\bappendix\b'),
      RegExp(r'\btable\b'),
      RegExp(r'\bsection\b'),
      RegExp(r'\bannex\b'),
      RegExp(r'\bschedule\b'),
      RegExp(r'\bas shown (?:in|above|below)\b'),
      RegExp(r'\bas stated (?:in|above|below)\b'),
    ];
    for (final pattern in genericCuePatterns) {
      if (pattern.hasMatch(normalizedPrompt)) {
        return true;
      }
    }
    return false;
  }

  LlmDocumentReference? _resolveDocumentForToolCall({
    required Map<String, dynamic> args,
    required String prompt,
    required List<LlmDocumentReference> uploadedDocuments,
  }) {
    final requestedId = (args['document_id'] ?? '').toString().trim();
    if (requestedId.isNotEmpty) {
      for (final document in uploadedDocuments) {
        if (document.id == requestedId) return document;
        if (_normalizeReferenceText(document.displayName) ==
            _normalizeReferenceText(requestedId)) {
          return document;
        }
      }
      return null;
    }

    if (uploadedDocuments.length == 1) {
      return uploadedDocuments.first;
    }

    for (final document in uploadedDocuments) {
      if (_promptMentionsDocument(prompt, document)) {
        return document;
      }
    }
    final promptReferencesDocument = _promptReferencesDocument(prompt);
    if (!promptReferencesDocument) {
      return null;
    }

    final sortedDocuments = uploadedDocuments.toList()
      ..sort((left, right) {
        final rightScore = _documentSelectionScore(right);
        final leftScore = _documentSelectionScore(left);
        return rightScore.compareTo(leftScore);
      });
    return sortedDocuments.first;
  }

  bool _promptMentionsDocument(
    String prompt,
    LlmDocumentReference document,
  ) {
    final normalizedPrompt = _normalizeReferenceText(prompt);
    final normalizedName = _normalizeReferenceText(document.displayName);
    if (normalizedName.isNotEmpty && normalizedPrompt.contains(normalizedName)) {
      return true;
    }

    final name = document.displayName.trim();
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final normalizedStem = _normalizeReferenceText(stem);
    return normalizedStem.isNotEmpty &&
        normalizedPrompt.contains(normalizedStem);
  }

  int _documentSelectionScore(LlmDocumentReference document) {
    var score = 0;
    if (document.detectedTableCount > 0) score += 20;
    if (document.detectedTablePages.isNotEmpty) score += 10;
    if (document.pageCount > 0) score += 1;
    final uploadedAt = document.uploadedAt;
    if (uploadedAt != null && uploadedAt.trim().isNotEmpty) score += 5;
    return score;
  }

  String _normalizeReferenceText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<int> _coercePositiveIntList(dynamic raw) {
    if (raw is! List) return const <int>[];
    final out = <int>[];
    for (final item in raw) {
      final value = _toInt(item);
      if (value != null && value > 0) {
        out.add(value);
      }
    }
    return out;
  }

  _AssistantPayload _extractAssistantPayloadFromMessage(
    dynamic message, {
    Map<String, dynamic>? diagnostics,
    String label = 'assistant',
  }) {
    final contentText = _extractContentText(message['content']);
    _logModelText('assistant_content_raw', contentText);
    if (contentText == null) {
      _log(
        '[LCA] Unexpected message content type: ${message['content']?.runtimeType}',
      );
      return const _AssistantPayload(
        abstention: LlmScenarioAbstention(
          reason:
              'Model response was not a valid JSON string and execution was blocked.',
          requiredCapability: 'Strict JSON response from the model',
        ),
      );
    }
    final cleaned = _normaliseJsonText(contentText.trim());
    _logModelText('assistant_content_normalized_for_json', cleaned);
    final parseDiagnostics = <String, dynamic>{
      'label': label,
      'raw_content_chars': contentText.length,
      'raw_content': contentText,
      'normalized_content_chars': cleaned.length,
      'normalized_content': cleaned,
    };

    final selected = _selectBestPayloadMap(cleaned);
    if (selected == null) {
      _logModelText('assistant_content_parse_error_raw', contentText);
      _logModelText('assistant_content_parse_error_cleaned', cleaned);
      parseDiagnostics['result'] = 'invalid_json';
      parseDiagnostics['failure_reason'] =
          'No JSON object could be decoded from assistant content.';
      diagnostics?['payload_parse'] = parseDiagnostics;
      return const _AssistantPayload(
        abstention: LlmScenarioAbstention(
          reason: 'Model returned invalid JSON and execution was blocked.',
          requiredCapability: 'Strict JSON output in the required schema',
        ),
      );
    }

    if (selected.recoveredText != null) {
      _logModelText(
        'assistant_content_recovered_balanced_json',
        selected.recoveredText,
      );
    }
    parseDiagnostics['result'] = 'json_object_selected';
    parseDiagnostics['selected_payload'] = selected.payload;
    parseDiagnostics['selected_payload_score'] = selected.score;
    parseDiagnostics['selected_payload_keys'] = selected.payload.keys.toList();
    if (selected.recoveredText != null) {
      parseDiagnostics['recovered_text'] = selected.recoveredText;
    }

    final parsed = selected.payload;
    final status = (parsed['status'] ?? '').toString().trim().toLowerCase();
    final topLevelMode = (parsed['mode'] ?? '').toString().trim().toLowerCase();
    parseDiagnostics['selected_status'] = status;
    parseDiagnostics['selected_mode'] = topLevelMode;
    if (status == 'unsupported') {
      final abstention = LlmScenarioAbstention(
        status: 'unsupported',
        reason: (parsed['reason'] ?? '').toString().trim().isEmpty
            ? 'The request is unsupported for this parameter-only system.'
            : (parsed['reason'] ?? '').toString().trim(),
        requiredCapability:
            (parsed['required_capability'] ?? '').toString().trim().isEmpty
                ? null
                : (parsed['required_capability'] ?? '').toString().trim(),
      );
      _log(
        '[LCA] Structured abstention received: ${jsonEncode(abstention.toJson())}',
      );
      parseDiagnostics['accepted_as'] = 'unsupported';
      diagnostics?['payload_parse'] = parseDiagnostics;
      return _AssistantPayload(abstention: abstention);
    }
    if (_looksLikeDocumentToolPayloadEcho(parsed)) {
      parseDiagnostics['result'] = 'schema_rejected';
      parseDiagnostics['accepted_as'] = 'document_tool_echo';
      parseDiagnostics['failure_reason'] =
          'Model repeated document extraction content instead of returning final structured JSON.';
      diagnostics?['payload_parse'] = parseDiagnostics;
      return const _AssistantPayload(
        abstention: LlmScenarioAbstention(
          reason:
              'Model repeated document extraction output instead of converting it into final scenario, optimization, or uncertainty JSON.',
          requiredCapability: 'Final structured JSON after document tool use',
        ),
      );
    }
    if (_looksLikeDirectOptimizationPayload(parsed) ||
        topLevelMode == 'parameter_threshold' ||
        topLevelMode == 'indicator_optimization') {
      _log('[LCA] Direct optimization payload parsed successfully');
      parseDiagnostics['accepted_as'] = 'direct_optimization_payload';
      diagnostics?['payload_parse'] = parseDiagnostics;
      return _AssistantPayload(optimizationJson: parsed);
    }
    if (_looksLikeDirectUncertaintyPayload(parsed) ||
        topLevelMode == 'uncertainty_propagation' ||
        topLevelMode == 'uncertainty') {
      _log(
        '[LCA] Direct uncertainty payload parsed successfully. '
        'tool=${parsed['tool']} mode=$topLevelMode keys=${parsed.keys.join(', ')}',
      );
      parseDiagnostics['accepted_as'] = 'direct_uncertainty_payload';
      diagnostics?['payload_parse'] = parseDiagnostics;
      return _AssistantPayload(uncertaintyJson: parsed);
    }
    final optimizationAny = parsed['optimization'] ??
        parsed['optimization_json'] ??
        parsed['optimizationjson'];
    if (optimizationAny is Map) {
      _log('[LCA] Optimization JSON parsed successfully');
      parseDiagnostics['accepted_as'] = 'wrapped_optimization_payload';
      diagnostics?['payload_parse'] = parseDiagnostics;
      return _AssistantPayload(
        optimizationJson: optimizationAny.cast<String, dynamic>(),
      );
    }
    if (topLevelMode == 'optimization' && optimizationAny == null) {
      parseDiagnostics['result'] = 'schema_rejected';
      parseDiagnostics['failure_reason'] =
          'Mode was optimization but no optimization object was present.';
      diagnostics?['payload_parse'] = parseDiagnostics;
      return const _AssistantPayload(
        abstention: LlmScenarioAbstention(
          reason:
              'Model selected optimization mode but did not include an "optimization" object.',
          requiredCapability: 'Wrapped optimization JSON in the required schema',
        ),
      );
    }
    final uncertaintyAny = parsed['uncertainty_propagation'] ??
        parsed['uncertainty'] ??
        parsed['uncertaintyPropagation'] ??
        parsed['uncertainty_payload'];
    if (uncertaintyAny is Map) {
      _log(
        '[LCA] Wrapped uncertainty JSON parsed successfully. '
        'wrapperKeys=${parsed.keys.join(', ')}',
      );
      parseDiagnostics['accepted_as'] = 'wrapped_uncertainty_payload';
      diagnostics?['payload_parse'] = parseDiagnostics;
      return _AssistantPayload(
        uncertaintyJson: uncertaintyAny.cast<String, dynamic>(),
      );
    }
    if (topLevelMode == 'scenario_delta' || parsed['scenarios'] is Map) {
      _log('[LCA] Scenarios JSON parsed successfully');
      parseDiagnostics['accepted_as'] = 'scenario_delta_payload';
      diagnostics?['payload_parse'] = parseDiagnostics;
      return _AssistantPayload(scenariosJson: parsed);
    }
    parseDiagnostics['result'] = 'schema_rejected';
    parseDiagnostics['failure_reason'] =
        'JSON object did not match scenario, optimization, uncertainty, or unsupported envelopes.';
    diagnostics?['payload_parse'] = parseDiagnostics;
    return const _AssistantPayload(
      abstention: LlmScenarioAbstention(
        reason:
            'Model response did not match scenario, optimization, or uncertainty JSON schema.',
        requiredCapability: 'Valid schema for selected output mode',
      ),
    );
  }

  _PayloadCandidate? _selectBestPayloadMap(String cleaned) {
    final candidates = <_PayloadCandidate>[];
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is Map) {
        candidates.add(
          _PayloadCandidate(
            payload: decoded.cast<String, dynamic>(),
            score: _payloadScore(decoded.cast<String, dynamic>()),
            recoveredText: null,
          ),
        );
      }
    } catch (_) {}

    for (final objectText in _extractBalancedJsonObjects(cleaned)) {
      try {
        final decoded = jsonDecode(objectText);
        if (decoded is! Map) continue;
        final payload = decoded.cast<String, dynamic>();
        candidates.add(
          _PayloadCandidate(
            payload: payload,
            score: _payloadScore(payload),
            recoveredText: objectText == cleaned ? null : objectText,
          ),
        );
      } catch (_) {
        continue;
      }
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.first;
  }

  int _payloadScore(Map<String, dynamic> payload) {
    var score = 0;
    final mode = (payload['mode'] ?? '').toString().trim().toLowerCase();
    final status = (payload['status'] ?? '').toString().trim().toLowerCase();
    if (status == 'unsupported') score += 1000;
    if (mode == 'optimization') score += 900;
    if (_looksLikeDirectOptimizationPayload(payload)) score += 900;
    if (payload['optimization'] is Map) score += 900;
    if (_looksLikeDirectUncertaintyPayload(payload)) score += 950;
    if (payload['uncertainty_propagation'] is Map) score += 950;
    if (payload['uncertainty'] is Map) score += 940;
    if (payload['uncertainty_payload'] is Map) score += 930;
    if (mode == 'scenario_delta') score += 800;
    if (payload['scenarios'] is Map) score += 800;
    if (_looksLikeDocumentToolPayloadEcho(payload)) score -= 500;
    if (payload.containsKey('query') && payload.containsKey('limit')) score -= 200;
    return score;
  }

  String? _extractContentText(dynamic content) {
    if (content == null) return null;
    if (content is String) return content;
    if (content is Map) {
      final direct = content['text'];
      if (direct is String) return direct;
    }
    if (content is List) {
      final parts = <String>[];
      for (final item in content) {
        if (item is String) {
          if (item.trim().isNotEmpty) {
            parts.add(item);
          }
          continue;
        }
        if (item is! Map) continue;
        final map = item.cast<dynamic, dynamic>();
        final type = (map['type'] ?? '').toString().toLowerCase().trim();
        if (type.isNotEmpty && type != 'text' && type != 'output_text') {
          continue;
        }
        final text = map['text'];
        if (text is String && text.trim().isNotEmpty) {
          parts.add(text);
          continue;
        }
        if (text is Map) {
          final value = text['value'];
          if (value is String && value.trim().isNotEmpty) {
            parts.add(value);
          }
        }
      }
      if (parts.isEmpty) return null;
      return parts.join('\n');
    }
    return null;
  }

  _ValidatedScenarioChanges _mapChangesWithValidation(
    _AssistantPayload payload, {
    required Map<String, dynamic> baseModelFull,
    required Map<String, dynamic> optimizationContext,
    required List<String> requestedTools,
    required _OptimizationToolMemory toolMemory,
  }) {
    if (payload.abstention != null) {
      return _ValidatedScenarioChanges(abstention: payload.abstention);
    }

    if (payload.optimizationJson != null) {
      return _validateOptimizationPayload(
        payload.optimizationJson!,
        baseModelFull: baseModelFull,
        optimizationContext: optimizationContext,
        toolMemory: toolMemory,
      );
    }

    if (payload.uncertaintyJson != null) {
      return _validateUncertaintyPayload(
        payload.uncertaintyJson!,
        baseModelFull: baseModelFull,
        optimizationContext: optimizationContext,
        toolMemory: toolMemory,
      );
    }

    final scenariosJson = payload.scenariosJson;
    if (scenariosJson == null) {
      return const _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason:
              'Model response did not match a supported scenario, optimization, or uncertainty schema.',
          requiredCapability: 'Valid structured JSON for selected mode',
        ),
      );
    }

    final scenariosAny = scenariosJson['scenarios'];
    if (scenariosAny is! Map) {
      return const _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason:
              'Model response must include a "scenarios" object or a structured unsupported abstention.',
          requiredCapability: 'Supported scenario delta output schema',
        ),
      );
    }

    for (final toolName in requestedTools) {
      if (_isAllowedToolName(toolName)) continue;
      return _ValidatedScenarioChanges(
        abstention: LlmScenarioAbstention(
          reason:
              'Tool "$toolName" is not allow-listed and execution was blocked.',
          requiredCapability: 'Implement and allow-list tool "$toolName"',
        ),
      );
    }

    final formulaTraceAbstention = _validateFormulaToolTrace(toolMemory);
    if (formulaTraceAbstention != null) {
      _log('[LCA] Formula trace warning: ${formulaTraceAbstention.reason}');
    }

    final index = _buildModelValidationIndex(baseModelFull);
    final scenariosMap = scenariosAny.cast<dynamic, dynamic>();
    final out = <String, List<Map<String, dynamic>>>{};
    _log('[LCA] Validating scenarios. Count=${scenariosMap.length}');

    for (final entry in scenariosMap.entries) {
      final scenarioName = entry.key.toString().trim();
      if (scenarioName.isEmpty) {
        return const _ValidatedScenarioChanges(
          abstention: LlmScenarioAbstention(
            reason: 'Scenario name cannot be empty.',
            requiredCapability: 'Valid scenario naming in output schema',
          ),
        );
      }

      final scenarioRaw = entry.value;
      final Map<String, dynamic> scenarioData;
      if (scenarioRaw is List) {
        _log(
          '[LCA] Wrapping shorthand scenario "$scenarioName" list as {"changes": [...]}',
        );
        scenarioData = {'changes': scenarioRaw};
      } else if (scenarioRaw is Map) {
        scenarioData = scenarioRaw.cast<String, dynamic>();
      } else {
        return _ValidatedScenarioChanges(
          abstention: LlmScenarioAbstention(
            reason: 'Scenario "$scenarioName" must be a JSON object.',
            requiredCapability: 'Valid scenario object in output schema',
          ),
        );
      }
      final changesAny = scenarioData['changes'];
      if (changesAny is! List) {
        return _ValidatedScenarioChanges(
          abstention: LlmScenarioAbstention(
            reason: 'Scenario "$scenarioName" is missing a valid changes list.',
            requiredCapability: 'Valid changes list in scenario output',
          ),
        );
      }

      final rawActionBlob = jsonEncode(changesAny);
      if (_structuralKeywordPattern.hasMatch(rawActionBlob)) {
        return _ValidatedScenarioChanges(
          abstention: LlmScenarioAbstention(
            reason:
                'Scenario "$scenarioName" includes structural edit keywords, which are unsupported.',
            requiredCapability:
                'Structural model-edit capability (process/flow/exchange/dataset edits)',
          ),
        );
      }

      final normalized = <Map<String, dynamic>>[];
      for (final rawChange in changesAny) {
        if (rawChange is! Map) {
          return _ValidatedScenarioChanges(
            abstention: LlmScenarioAbstention(
              reason:
                  'Scenario "$scenarioName" contains a malformed change entry.',
              requiredCapability: 'Valid change object in output schema',
            ),
          );
        }

        final change = rawChange.cast<String, dynamic>();
        final field = (change['field'] ?? '').toString().trim();
        if (field.isEmpty) {
          return _ValidatedScenarioChanges(
            abstention: LlmScenarioAbstention(
              reason:
                  'Scenario "$scenarioName" contains a change with missing field.',
              requiredCapability: 'Valid field value in each change',
            ),
          );
        }
        if (change['new_value'] == null) {
          _log(
            '[LCA] Dropping null-valued change in scenario "$scenarioName": field="$field"',
          );
          continue;
        }
        final newValue = _toFiniteDouble(change['new_value']);
        if (newValue == null) {
          return _ValidatedScenarioChanges(
            abstention: LlmScenarioAbstention(
              reason:
                  'Scenario "$scenarioName" has non-numeric new_value for "$field".',
              requiredCapability: 'Numeric literal new_value for each change',
            ),
          );
        }

        if (field == 'number_functional_units') {
          normalized.add({
            'field': 'number_functional_units',
            'new_value': newValue,
          });
          continue;
        }

        if (field.startsWith('parameters.global.')) {
          final paramName = field.substring('parameters.global.'.length).trim();
          if (paramName.isEmpty) {
            return _ValidatedScenarioChanges(
              abstention: LlmScenarioAbstention(
                reason:
                    'Scenario "$scenarioName" has an invalid global parameter field.',
                requiredCapability: 'Valid global parameter field syntax',
              ),
            );
          }
          final key = paramName.toLowerCase();
          if (!index.globalParamNames.contains(key)) {
            final scopeReason = index.allProcessParamNames.contains(key)
                ? 'Parameter "$paramName" is not editable in global scope.'
                : 'Global parameter "$paramName" does not exist in the loaded model.';
            return _ValidatedScenarioChanges(
              abstention: LlmScenarioAbstention(
                reason: scopeReason,
                requiredCapability:
                    'Expose "$paramName" as an editable global parameter',
              ),
            );
          }
          normalized.add({
            'field': 'parameters.global.$paramName',
            'new_value': newValue,
          });
          continue;
        }

        if (field.startsWith('parameters.process.') ||
            field.startsWith('parameters.process:')) {
          String processIdRaw = (change['process_id'] ?? '').toString().trim();
          String processParamName = '';

          if (field.startsWith('parameters.process.')) {
            processParamName =
                field.substring('parameters.process.'.length).trim();
          } else {
            final rest = field.substring('parameters.process:'.length);
            final dot = rest.indexOf('.');
            if (dot <= 0 || dot >= rest.length - 1) {
              return _ValidatedScenarioChanges(
                abstention: LlmScenarioAbstention(
                  reason:
                      'Scenario "$scenarioName" has malformed process parameter field "$field".',
                  requiredCapability: 'Valid process parameter field syntax',
                ),
              );
            }
            processIdRaw = rest.substring(0, dot).trim();
            processParamName = rest.substring(dot + 1).trim();
          }

          if (processIdRaw.isEmpty) {
            return _ValidatedScenarioChanges(
              abstention: LlmScenarioAbstention(
                reason:
                    'Scenario "$scenarioName" process parameter edit "$field" is missing process_id.',
                requiredCapability: 'Process parameter edits with process_id',
              ),
            );
          }
          if (processParamName.isEmpty) {
            return _ValidatedScenarioChanges(
              abstention: LlmScenarioAbstention(
                reason:
                    'Scenario "$scenarioName" has empty process parameter name in "$field".',
                requiredCapability: 'Valid process parameter field syntax',
              ),
            );
          }

          final resolvedProcessId =
              _resolveProcessId(processIdRaw, index.processIdByLower);
          if (resolvedProcessId == null) {
            return _ValidatedScenarioChanges(
              abstention: LlmScenarioAbstention(
                reason:
                    'Process "$processIdRaw" does not exist in the loaded model.',
                requiredCapability:
                    'Valid process_id that exists in the loaded model',
              ),
            );
          }

          final processParamKey = processParamName.toLowerCase();
          final editableParams =
              index.processParamNamesById[resolvedProcessId] ?? const <String>{};
          if (!editableParams.contains(processParamKey)) {
            final scopeReason = index.globalParamNames.contains(processParamKey)
                ? 'Parameter "$processParamName" is not editable in process scope.'
                : index.allProcessParamNames.contains(processParamKey)
                    ? 'Parameter "$processParamName" is not editable for process "$resolvedProcessId".'
                    : 'Process parameter "$processParamName" does not exist for process "$resolvedProcessId".';
            return _ValidatedScenarioChanges(
              abstention: LlmScenarioAbstention(
                reason: scopeReason,
                requiredCapability:
                    'Expose "$processParamName" as an editable parameter for "$resolvedProcessId"',
              ),
            );
          }

          normalized.add({
            'process_id': resolvedProcessId,
            'field': 'parameters.process.$processParamName',
            'new_value': newValue,
          });
          continue;
        }

        return _ValidatedScenarioChanges(
          abstention: LlmScenarioAbstention(
            reason:
                'Field "$field" is not an allowed edit type. Allowed types are global parameter, process parameter, or number_functional_units.',
            requiredCapability:
                'Parameter-only scenario editing in the supported schema',
          ),
        );
      }

      final deduped = _preferGlobalParameterWhenDuplicate(
        normalized,
        scenarioName: scenarioName,
      );
      final formulaNameAbstention = _validateFormulaValuesInScenarioName(
        scenarioName: scenarioName,
        toolMemory: toolMemory,
      );
      if (formulaNameAbstention != null) {
        _log(
          '[LCA] Formula scenario-name warning: ${formulaNameAbstention.reason}',
        );
      }
      final finalActionBlob = jsonEncode(deduped);
      if (_structuralKeywordPattern.hasMatch(finalActionBlob)) {
        return _ValidatedScenarioChanges(
          abstention: LlmScenarioAbstention(
            reason:
                'Scenario "$scenarioName" includes structural edit content after parsing and was blocked.',
            requiredCapability:
                'Structural model-edit capability (process/flow/exchange/dataset edits)',
          ),
        );
      }
      out[scenarioName] = deduped;
    }

    _log('[LCA] Validation and mapping complete');
    return _ValidatedScenarioChanges(rawDeltasByScenario: out);
  }

  LlmScenarioAbstention? _validateFormulaToolTrace(
    _OptimizationToolMemory toolMemory,
  ) {
    if (!toolMemory.formulaToolUsed) return null;
    if (toolMemory.formulaResultCount == 0) {
      return const LlmScenarioAbstention(
        reason:
            'formulaCalculator was used but returned no usable result records.',
        requiredCapability:
            'Successful formulaCalculator results before final scenario JSON',
      );
    }
    if (!toolMemory.formulaResultsAllSuccessful) {
      return const LlmScenarioAbstention(
        reason:
            'formulaCalculator returned at least one failed result, so formula-derived scenarios were not merged.',
        requiredCapability:
            'Valid formulaCalculator arguments for every requested calculation',
      );
    }
    final simplexCount = toolMemory.simplexChangeListCount;
    if (simplexCount != null && toolMemory.formulaResultCount != simplexCount) {
      return LlmScenarioAbstention(
        reason:
            'formulaCalculator returned ${toolMemory.formulaResultCount} result(s) for $simplexCount simplex-lattice candidate(s).',
        requiredCapability:
            'One successful formulaCalculator calculation per simplex-lattice candidate',
      );
    }
    if (simplexCount != null) {
      final expectedIds = {
        for (var i = 0; i < simplexCount; i += 1) 'candidate_${i + 1}',
      };
      final actualIds = toolMemory.formulaResultIds.toSet();
      if (!actualIds.containsAll(expectedIds)) {
        return LlmScenarioAbstention(
          reason:
              'formulaCalculator result ids did not match the simplex-lattice candidate ids.',
          requiredCapability:
              'Formula calculation ids must be ${expectedIds.join(', ')}',
        );
      }
    }
    return null;
  }

  LlmScenarioAbstention? _validateFormulaValuesInScenarioName({
    required String scenarioName,
    required _OptimizationToolMemory toolMemory,
  }) {
    if (!toolMemory.formulaToolUsed) return null;
    final numericUnitPattern = RegExp(
      r'(^|[^A-Za-z0-9_])([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)\s*(?:MPa|GPa|kPa|Pa|W|kW|MW|J|kJ|MJ|%|ohm|Ohm|USD|EUR|GBP)\b',
    );
    final labelledValues = <double>[];
    for (final match in numericUnitPattern.allMatches(scenarioName)) {
      final value = _toFiniteDouble(match.group(2));
      if (value != null) labelledValues.add(value);
    }
    if (labelledValues.isEmpty) return null;
    if (toolMemory.formulaOutputValues.isEmpty) {
      return LlmScenarioAbstention(
        reason:
            'Scenario "$scenarioName" includes a formula-like numeric unit label, but formulaCalculator returned no numeric outputs.',
        requiredCapability:
            'Traceable formulaCalculator numeric output for formula-labelled scenario names',
      );
    }
    for (final labelledValue in labelledValues) {
      if (_matchesFormulaOutput(labelledValue, toolMemory.formulaOutputValues)) {
        continue;
      }
      return LlmScenarioAbstention(
        reason:
            'Scenario "$scenarioName" includes formula value $labelledValue that is not traceable to formulaCalculator outputs.',
        requiredCapability:
            'Copy formula values from matching formulaCalculator results, or omit formula values from scenario names',
      );
    }
    return null;
  }

  bool _matchesFormulaOutput(double labelledValue, List<double> outputValues) {
    for (final outputValue in outputValues) {
      final relativeTolerance = outputValue.abs() * 0.001;
      final tolerance = relativeTolerance > 0.05 ? relativeTolerance : 0.05;
      if ((labelledValue - outputValue).abs() <= tolerance) return true;
    }
    return false;
  }

  _ValidatedScenarioChanges _validateOptimizationPayload(
    Map<String, dynamic> optimization, {
    required Map<String, dynamic> baseModelFull,
    required Map<String, dynamic> optimizationContext,
    required _OptimizationToolMemory toolMemory,
  }) => _validateOptimizationPayloadImpl(
        controller: this,
        optimization: optimization,
        baseModelFull: baseModelFull,
        optimizationContext: optimizationContext,
        toolMemory: toolMemory,
      );

  _ValidatedScenarioChanges _validateUncertaintyPayload(
    Map<String, dynamic> uncertainty, {
    required Map<String, dynamic> baseModelFull,
    required Map<String, dynamic> optimizationContext,
    required _OptimizationToolMemory toolMemory,
  }) => _validateUncertaintyPayloadImpl(
        controller: this,
        uncertainty: uncertainty,
        baseModelFull: baseModelFull,
        optimizationContext: optimizationContext,
        toolMemory: toolMemory,
      );

  _ModelValidationIndex _buildModelValidationIndex(
    Map<String, dynamic> baseModelFull,
  ) {
    final parameterSet = _readParameterSetForValidation(baseModelFull);
    final globalParamNames = <String>{
      for (final p in parameterSet.global)
        if (p.name.trim().isNotEmpty) p.name.trim().toLowerCase(),
    };
    final processParamNamesById = <String, Set<String>>{};
    final processIdByLower = <String, String>{};
    final allProcessParamNames = <String>{};

    final rawProcesses = baseModelFull['processes'];
    if (rawProcesses is List) {
      for (final rawProcess in rawProcesses) {
        if (rawProcess is! Map) continue;
        final process = rawProcess.cast<String, dynamic>();
        final pid = (process['id'] ?? '').toString().trim();
        if (pid.isEmpty) continue;
        processIdByLower[pid.toLowerCase()] = pid;
        final names = processParamNamesById.putIfAbsent(pid, () => <String>{});

        for (final p in parameterSet.processParamsFor(pid)) {
          final key = p.name.trim().toLowerCase();
          if (key.isEmpty) continue;
          names.add(key);
          allProcessParamNames.add(key);
        }

        final inlineParams = process['parameters'];
        if (inlineParams is List) {
          for (final paramRaw in inlineParams) {
            if (paramRaw is! Map) continue;
            final name = (paramRaw['name'] ?? '').toString().trim().toLowerCase();
            if (name.isEmpty) continue;
            names.add(name);
            allProcessParamNames.add(name);
          }
        }
      }
    }

    for (final entry in parameterSet.perProcess.entries) {
      final pid = entry.key.trim();
      if (pid.isEmpty) continue;
      processIdByLower.putIfAbsent(pid.toLowerCase(), () => pid);
      final names = processParamNamesById.putIfAbsent(pid, () => <String>{});
      for (final p in entry.value) {
        final key = p.name.trim().toLowerCase();
        if (key.isEmpty) continue;
        names.add(key);
        allProcessParamNames.add(key);
      }
    }

    return _ModelValidationIndex(
      globalParamNames: globalParamNames,
      processParamNamesById: processParamNamesById,
      processIdByLower: processIdByLower,
      allProcessParamNames: allProcessParamNames,
    );
  }

  ParameterSet _readParameterSetForValidation(Map<String, dynamic> model) {
    final params = model['parameters'];
    if (params is Map) {
      return ParameterSet.fromJson(params.cast<String, dynamic>());
    }

    final fallback = <String, dynamic>{};
    final globals = model['global_parameters'];
    if (globals is List) {
      fallback['global_parameters'] = globals;
    }
    final process = model['process_parameters'];
    if (process is Map) {
      fallback['process_parameters'] = process;
    }
    if (fallback.isNotEmpty) {
      return ParameterSet.fromJson(fallback);
    }

    final perProcess = <String, List<Parameter>>{};
    final rawProcesses = model['processes'];
    if (rawProcesses is List) {
      for (final raw in rawProcesses) {
        if (raw is! Map) continue;
        final processMap = raw.cast<String, dynamic>();
        final pid = (processMap['id'] ?? '').toString().trim();
        if (pid.isEmpty) continue;
        final rawParams = processMap['parameters'];
        if (rawParams is! List) continue;
        final parsed = rawParams
            .whereType<Map>()
            .map((p) => Parameter.fromJson(p.cast<String, dynamic>()))
            .toList();
        if (parsed.isNotEmpty) {
          perProcess[pid] = parsed;
        }
      }
    }
    return ParameterSet(perProcess: perProcess);
  }

  String? _resolveProcessId(String raw, Map<String, String> processIdByLower) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return processIdByLower[trimmed.toLowerCase()];
  }

  double? _toFiniteDouble(dynamic value) {
    double? out;
    if (value is num) {
      out = value.toDouble();
    } else if (value is String) {
      out = double.tryParse(value.trim());
    }
    if (out == null || out.isNaN || out.isInfinite) return null;
    return out;
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  Map<String, dynamic> _searchOpenLcaIndicators({
    required String query,
    required String methodHint,
    required int limit,
    required List<Map<String, dynamic>>? queries,
    required Map<String, dynamic> optimizationContext,
  }) => _searchOpenLcaIndicatorsImpl(
        controller: this,
        query: query,
        methodHint: methodHint,
        limit: limit,
        queries: queries,
        optimizationContext: optimizationContext,
      );

  Map<String, dynamic> _searchOpenLcaIndicatorsSingle({
    required String query,
    required String methodHint,
    required int limit,
    required Map<String, dynamic> optimizationContext,
  }) {
    final normalizedQuery = _normalizeImpactText(query);
    final normalizedMethodHint = _normalizeImpactText(methodHint);
    final cappedLimit = (limit.clamp(1, 5) as num).toInt();
    final index = _buildImpactValidationIndex(optimizationContext);
    if (normalizedQuery.isEmpty || index.isEmpty) {
      return {
        'query': query,
        'method_hint': methodHint,
        'matches': const <Map<String, dynamic>>[],
      };
    }

    final needles = _expandedImpactNeedles(query);
    final scored = <_ImpactCandidateScore>[];
    for (final item in index) {
      final indicator = _normalizeImpactText(item.indicator);
      final methodName = _normalizeImpactText(item.methodName);
      final methodId = _normalizeImpactText(item.methodId);
      final qualified = '$methodName $indicator'.trim();

      var score = 0;
      for (final needle in needles) {
        if (needle.isEmpty) continue;
        if (indicator == needle || qualified == needle) {
          score += 100;
        } else if (indicator.contains(needle)) {
          score += 70;
        } else if (needle.contains(indicator)) {
          score += 55;
        } else if (qualified.contains(needle)) {
          score += 35;
        } else {
          final overlap = _tokenOverlap(needle, indicator);
          if (overlap >= 0.67) score += (overlap * 30).round();
        }
      }

      if (normalizedMethodHint.isNotEmpty) {
        if (methodId == normalizedMethodHint || methodName == normalizedMethodHint) {
          score += 30;
        } else if (methodName.contains(normalizedMethodHint) ||
            normalizedMethodHint.contains(methodName)) {
          score += 15;
        } else {
          score -= 20;
        }
      }

      if (score > 0) {
        scored.add(_ImpactCandidateScore(item: item, score: score));
      }
    }

    scored.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      final methodCompare =
          a.item.methodName.toLowerCase().compareTo(b.item.methodName.toLowerCase());
      if (methodCompare != 0) return methodCompare;
      return a.item.indicator.toLowerCase().compareTo(b.item.indicator.toLowerCase());
    });

    final best = scored.isNotEmpty ? scored.first : null;
    final runnerUp = scored.length > 1 ? scored[1] : null;
    final disambiguationNeeded =
        best != null && runnerUp != null ? (best.score - runnerUp.score) < 10 : false;

    return {
      'query': query,
      'method_hint': methodHint,
      'matches': [
        for (final scoredItem in scored.take(cappedLimit))
          {
            'method_id': scoredItem.item.methodId,
            'method_name': scoredItem.item.methodName,
            if (scoredItem.item.impactCategoryId.isNotEmpty)
              'impact_category_id': scoredItem.item.impactCategoryId,
            'indicator': scoredItem.item.indicator,
            'score': scoredItem.score,
          },
      ],
      if (best != null)
        'best_match': {
          'method_id': best.item.methodId,
          'method_name': best.item.methodName,
          if (best.item.impactCategoryId.isNotEmpty)
            'impact_category_id': best.item.impactCategoryId,
          'indicator': best.item.indicator,
          'score': best.score,
        },
      'disambiguation_needed': disambiguationNeeded,
    };
  }

  List<_ResolvedImpactCategory> _buildImpactValidationIndex(
    Map<String, dynamic> optimizationContext,
  ) {
    final out = <_ResolvedImpactCategory>[];
    final raw = optimizationContext['impact_categories'];
    if (raw is! List) return out;
    for (final item in raw) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final methodId = (map['method_id'] ?? '').toString().trim();
      final methodName = (map['method_name'] ?? '').toString().trim();
      final impactCategoryId =
          (map['impact_category_id'] ?? '').toString().trim();
      final rawIndicator = (map['indicator'] ?? '').toString().trim();
      final indicator =
          rawIndicator.isNotEmpty ? rawIndicator : (impactCategoryId.isNotEmpty ? impactCategoryId : methodName);
      if (methodId.isEmpty || indicator.isEmpty) continue;
      out.add(
        _ResolvedImpactCategory(
          methodId: methodId,
          methodName: methodName,
          impactCategoryId: impactCategoryId,
          indicator: indicator,
        ),
      );
    }
    return out;
  }

  _ResolvedImpactCategory? _resolveImpactCategory(
    String rawIndicator,
    String rawImpactCategoryId,
    String methodIdHint,
    List<_ResolvedImpactCategory> index,
  ) {
    if (index.isEmpty) return null;
    final impactCategoryId = rawImpactCategoryId.trim();
    final methodIdHintTrimmed = methodIdHint.trim();
    final impactCategoryIdLower = impactCategoryId.toLowerCase();
    final methodIdHintLower = methodIdHintTrimmed.toLowerCase();

    if (impactCategoryId.isNotEmpty) {
      final byId = index
          .where((item) =>
              item.impactCategoryId.toLowerCase() == impactCategoryIdLower)
          .toList();
      final preferredByMethod = methodIdHintTrimmed.isNotEmpty
          ? byId
              .where((item) => item.methodId.toLowerCase() == methodIdHintLower)
              .toList()
          : byId;
      if (preferredByMethod.length == 1) return preferredByMethod.first;
      if (byId.length == 1) return byId.first;
      if (preferredByMethod.isNotEmpty) return preferredByMethod.first;
      if (byId.isNotEmpty) return byId.first;
    }

    final needle = _normalizeImpactText(rawIndicator);
    if (needle.isEmpty) return null;
    final needles = _expandedImpactNeedles(rawIndicator);
    final normalizedMethodHint = methodIdHintTrimmed.isNotEmpty
        ? _normalizeImpactText(methodIdHintTrimmed)
        : '';
    final scored = <_ImpactCandidateScore>[];
    for (final item in index) {
      final indicator = _normalizeImpactText(item.indicator);
      final methodName = _normalizeImpactText(item.methodName);
      final methodId = _normalizeImpactText(item.methodId);
      final qualified = '$methodName $indicator'.trim();

      var score = 0;
      for (final expandedNeedle in needles) {
        if (expandedNeedle.isEmpty) continue;
        if (indicator == expandedNeedle || qualified == expandedNeedle) {
          score += 120;
        } else if (indicator.contains(expandedNeedle)) {
          score += 80;
        } else if (expandedNeedle.contains(indicator)) {
          score += 60;
        } else if (qualified.contains(expandedNeedle)) {
          score += 35;
        } else {
          final overlap = _tokenOverlap(expandedNeedle, indicator);
          if (overlap >= 0.67) score += (overlap * 28).round();
        }
      }

      if (methodIdHintTrimmed.isNotEmpty) {
        if (methodId == normalizedMethodHint ||
            methodName == normalizedMethodHint) {
          score += 30;
        } else if (methodName.contains(normalizedMethodHint) ||
            normalizedMethodHint.contains(methodName)) {
          score += 12;
        } else {
          score -= 12;
        }
      }

      if (score > 0) {
        scored.add(_ImpactCandidateScore(item: item, score: score));
      }
    }

    if (scored.isEmpty) return null;
    scored.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      final methodCompare =
          a.item.methodName.toLowerCase().compareTo(b.item.methodName.toLowerCase());
      if (methodCompare != 0) return methodCompare;
      return a.item.indicator
          .toLowerCase()
          .compareTo(b.item.indicator.toLowerCase());
    });

    final best = scored.first;
    if (scored.length == 1) return best.item;
    final runnerUp = scored[1];
    final scoreDelta = best.score - runnerUp.score;
    if (scoreDelta >= 10) return best.item;
    if (_normalizeImpactText(best.item.indicator) == needle &&
        scoreDelta >= 1) {
      return best.item;
    }
    return null;
  }

  Set<String> _expandedImpactNeedles(String raw) {
    final normalized = _normalizeImpactText(raw);
    if (normalized.isEmpty) return const <String>{};
    final needles = <String>{normalized};

    void addIfMentioned(List<String> triggers, List<String> aliases) {
      if (triggers.any((term) => normalized.contains(term))) {
        needles.addAll(aliases.map(_normalizeImpactText));
      }
    }

    addIfMentioned(
      const ['gwp', 'global warming', 'climate', 'co2', 'carbon'],
      const ['global warming', 'climate change', 'global warming potential', 'gwp100a'],
    );
    addIfMentioned(
      const ['acid', 'acidification'],
      const ['acidification', 'terrestrial acidification'],
    );
    addIfMentioned(
      const ['eutrophication', 'eutrophic', 'nutrient'],
      const ['eutrophication', 'freshwater eutrophication', 'marine eutrophication'],
    );
    addIfMentioned(
      const ['water'],
      const ['water use', 'water consumption', 'freshwater consumption'],
    );
    addIfMentioned(
      const ['fossil', 'energy', 'fuel'],
      const ['fossil resource scarcity', 'fossil fuel depletion', 'abiotic depletion fossil fuels'],
    );
    addIfMentioned(
      const ['ozone'],
      const ['ozone depletion', 'ozone layer depletion', 'photochemical ozone formation'],
    );
    addIfMentioned(
      const ['particulate', 'pm2', 'pm10', 'respiratory'],
      const ['particulate matter formation', 'fine particulate matter formation', 'respiratory effects'],
    );
    addIfMentioned(
      const ['toxicity', 'toxic'],
      const ['human toxicity', 'ecotoxicity', 'freshwater ecotoxicity'],
    );
    addIfMentioned(
      const ['land'],
      const ['land use', 'land occupation'],
    );

    return needles.where((item) => item.isNotEmpty).toSet();
  }

  String _normalizeImpactText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _tokenOverlap(String a, String b) {
    final aTokens = a.split(' ').where((token) => token.length > 2).toSet();
    final bTokens = b.split(' ').where((token) => token.length > 2).toSet();
    if (aTokens.isEmpty || bTokens.isEmpty) return 0;
    final shared = aTokens.intersection(bTokens).length;
    final smaller = aTokens.length < bTokens.length ? aTokens.length : bTokens.length;
    return shared / smaller;
  }

  String _methodNameForId(
    String methodId,
    List<_ResolvedImpactCategory> index,
  ) {
    final needle = methodId.trim().toLowerCase();
    if (needle.isEmpty) return '';
    for (final item in index) {
      if (item.methodId.toLowerCase() == needle) return item.methodName;
    }
    return '';
  }

  List<Map<String, dynamic>> _preferGlobalParameterWhenDuplicate(
    List<Map<String, dynamic>> changes, {
    required String scenarioName,
  }) {
    final globalNames = <String>{};
    for (final c in changes) {
      final field = (c['field'] ?? '').toString();
      final g = _extractGlobalParamName(field);
      if (g != null) globalNames.add(g);
    }
    if (globalNames.isEmpty) return changes;

    final filtered = <Map<String, dynamic>>[];
    for (final c in changes) {
      final field = (c['field'] ?? '').toString();
      final processName = _extractProcessParamName(field);
      if (processName != null && globalNames.contains(processName)) {
        _log(
          '[LCA] Dropping process parameter change in scenario "$scenarioName": '
          'field="$field" because parameters.global.$processName is also edited',
        );
        continue;
      }
      filtered.add(c);
    }
    return filtered;
  }

  String? _extractGlobalParamName(String field) {
    const prefix = 'parameters.global.';
    if (!field.startsWith(prefix)) return null;
    final raw = field.substring(prefix.length).trim().toLowerCase();
    if (raw.isEmpty) return null;
    return raw;
  }

  String? _extractProcessParamName(String field) {
    const prefixNew = 'parameters.process.';
    if (field.startsWith(prefixNew)) {
      final raw = field.substring(prefixNew.length).trim().toLowerCase();
      if (raw.isEmpty) return null;
      return raw;
    }

    const prefixLegacy = 'parameters.process:';
    if (field.startsWith(prefixLegacy)) {
      final rest = field.substring(prefixLegacy.length);
      final dot = rest.indexOf('.');
      if (dot <= 0 || dot >= rest.length - 1) return null;
      final raw = rest.substring(dot + 1).trim().toLowerCase();
      if (raw.isEmpty) return null;
      return raw;
    }
    return null;
  }

  /// Strip code fences and any stray preamble so jsonDecode sees a clean object
  String _normaliseJsonText(String s) {
    final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$', multiLine: true);
    final m = fence.firstMatch(s);
    if (m != null) {
      s = m.group(1)!.trim();
    }
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start != -1 && end != -1 && end >= start) {
      s = s.substring(start, end + 1).trim();
    }
    return s;
  }

  bool _looksLikeDirectOptimizationPayload(Map<String, dynamic> parsed) {
    final innerMode = (parsed['mode'] ?? '').toString().trim().toLowerCase();
    final variables = parsed['variables'];
    final objective = parsed['objective'];
    return (innerMode == 'parameter_threshold' ||
            innerMode == 'indicator_optimization') &&
        variables is List &&
        objective is Map;
  }

  bool _looksLikeDirectUncertaintyPayload(Map<String, dynamic> parsed) {
    final tool = (parsed['tool'] ?? '').toString().trim();
    if (tool == 'uncertainty_propagation') return true;
    return parsed['sampling'] is Map &&
        parsed['parameters'] is List &&
        parsed['impact_categories'] is List;
  }

  bool _looksLikeDocumentToolPayloadEcho(Map<String, dynamic> payload) {
    final hasDocument = payload['document'] is Map;
    final hasResults = payload['results'] is List;
    final hasMatches = payload['matches'] is List;
    final hasQuery = (payload['query'] ?? '').toString().trim().isNotEmpty;
    if (hasDocument && (hasResults || hasMatches)) return true;
    if (hasQuery && hasMatches && payload.containsKey('success')) return true;
    final hasTableShape =
        payload['headers'] is List && payload['rows'] is List;
    if (hasTableShape &&
        (_toInt(payload['page_number']) != null ||
            _toInt(payload['table_index']) != null)) {
      return true;
    }
    return false;
  }

  List<String> _extractBalancedJsonObjects(String s) {
    final out = <String>[];
    for (var start = 0; start < s.length; start += 1) {
      if (s[start] != '{') continue;
      var depth = 0;
      var inString = false;
      var escaped = false;
      for (var i = start; i < s.length; i += 1) {
        final ch = s[i];
        if (escaped) {
          escaped = false;
          continue;
        }
        if (ch == '\\') {
          escaped = true;
          continue;
        }
        if (ch == '"') {
          inString = !inString;
          continue;
        }
        if (inString) continue;
        if (ch == '{') {
          depth += 1;
        } else if (ch == '}') {
          depth -= 1;
          if (depth == 0) {
            out.add(s.substring(start, i + 1).trim());
            start = i;
            break;
          }
        }
      }
    }
    return out;
  }

}

/// Internal struct for returning parsed LLM output
class _ParsedLLMOutput {
  final List<String> functionsUsed;
  final Map<String, List<Map<String, dynamic>>> rawDeltasByScenario;
  final Map<String, dynamic>? optimizationPayload;
  final Map<String, dynamic>? uncertaintyPayload;
  final List<DocumentExtractionRecord> documentProvenance;
  final LlmScenarioAbstention? abstention;

  _ParsedLLMOutput({
    required this.functionsUsed,
    required this.rawDeltasByScenario,
    this.optimizationPayload,
    this.uncertaintyPayload,
    this.documentProvenance = const [],
    this.abstention,
  });
}

class _AssistantPayload {
  final Map<String, dynamic>? scenariosJson;
  final Map<String, dynamic>? optimizationJson;
  final Map<String, dynamic>? uncertaintyJson;
  final LlmScenarioAbstention? abstention;

  const _AssistantPayload({
    this.scenariosJson,
    this.optimizationJson,
    this.uncertaintyJson,
    this.abstention,
  });
}

class _PayloadCandidate {
  final Map<String, dynamic> payload;
  final int score;
  final String? recoveredText;

  const _PayloadCandidate({
    required this.payload,
    required this.score,
    required this.recoveredText,
  });
}

class _ValidatedScenarioChanges {
  final Map<String, List<Map<String, dynamic>>>? rawDeltasByScenario;
  final Map<String, dynamic>? optimizationPayload;
  final Map<String, dynamic>? uncertaintyPayload;
  final LlmScenarioAbstention? abstention;

  const _ValidatedScenarioChanges({
    this.rawDeltasByScenario,
    this.optimizationPayload,
    this.uncertaintyPayload,
    this.abstention,
  });
}

class _ModelValidationIndex {
  final Set<String> globalParamNames;
  final Map<String, Set<String>> processParamNamesById;
  final Map<String, String> processIdByLower;
  final Set<String> allProcessParamNames;

  const _ModelValidationIndex({
    required this.globalParamNames,
    required this.processParamNamesById,
    required this.processIdByLower,
    required this.allProcessParamNames,
  });
}

class _ResolvedImpactCategory {
  final String methodId;
  final String methodName;
  final String impactCategoryId;
  final String indicator;

  const _ResolvedImpactCategory({
    required this.methodId,
    required this.methodName,
    required this.impactCategoryId,
    required this.indicator,
  });
}

class _ImpactCandidateScore {
  final _ResolvedImpactCategory item;
  final int score;

  const _ImpactCandidateScore({
    required this.item,
    required this.score,
  });
}
