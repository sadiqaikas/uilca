// File: lib/lca/llm_scenario_controller.dart

import 'dart:async';
import 'dart:convert';
import 'package:earlylca/lca/newmerge/merge_scenarios.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
// if pubspec has: name: earlylca
import 'package:earlylca/lca/newllm/distance_one_to_many.dart'
    as distance_tool;

import '../lca_functions.dart';
import '../newhome/lca_models.dart';
import 'llm_system_prompt.dart';

/// Holds results from an LLM scenario generation run
class LlmScenarioResult {
  final Map<String, dynamic> mergedScenarios;
  final Map<String, List<Map<String, dynamic>>> rawDeltasByScenario;
  final List<String> functionsUsed;

  const LlmScenarioResult({
    required this.mergedScenarios,
    required this.rawDeltasByScenario,
    required this.functionsUsed,
  });
}

/// Signature for an injectable one-to-many distance handler:
typedef DistanceOneToManyHandler = Map<String, dynamic> Function(
  Map<String, dynamic> args,
);

/// Handles building LCA models for LLM, calling OpenAI, and merging scenarios.
class LlmScenarioController {
  static const String _defaultOpenAiBase = 'https://api.openai.com/v1';
  static const String _controllerRevision = 'rev-2026-03-03-a';
  static const String _defaultApiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );

  final String apiKey;
  final String model;
  final String apiBase;

  /// Optional logger. If null, prints are used.
  final void Function(String message)? log;

  /// Optional injection point for your distance one-to-many implementation.
  /// If not provided, we will fall back to the built-in tool.
  final DistanceOneToManyHandler? distanceOneToManyHandler;

  const LlmScenarioController({
    this.apiKey = _defaultApiKey,
    this.model = 'gpt-5', // default to GPT-5
    this.apiBase = 'https://api.openai.com/v1',
    this.log,
    this.distanceOneToManyHandler,
  });

  void _log(String message) {
    if (log != null) {
      log!(message);
    } else {
      // ignore: avoid_print
      print(message);
    }
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
            parsed.host.endsWith('.openai.com')) &&
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

  String _webFailedToFetchHint(Uri uri, http.ClientException error) {
    if (!kIsWeb || !error.message.toLowerCase().contains('failed to fetch')) {
      return '';
    }
    return ' Browser blocked the request before OpenAI returned a response. '
        'Check browser Network tab for blocked OPTIONS/POST, disable VPN/ad-block extensions, '
        'verify DNS can resolve ${uri.host}, and verify your API key is valid and not restricted.';
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

  /// Builds the model for LLM (no emissions, no biosphere flows)
  Map<String, dynamic> _buildBaseModelForLLM(
    List<ProcessNode> processes,
    List<Map<String, dynamic>> flows,
    ParameterSet? parameters,
  ) {
    _log('[LCA] Building stripped model for LLM');
    final strippedProcesses = processes
        .map((p) => p.copyWithFields(emissions: [])) // remove emissions
        .map((p) => p.toJson())
        .toList();

    final out = {
      'processes': strippedProcesses,
      'flows': flows,
      if (parameters != null) 'parameters': parameters.toJson(),
    };
    _log(
        '[LCA] Stripped model built: processes=${strippedProcesses.length}, flows=${flows.length}, hasParameters=${parameters != null}');
    return out;
  }

  /// Runs the LLM flow: send prompt and base model, handle tools or functions, merge results.
  Future<LlmScenarioResult> generateAndMergeScenarios({
    required String prompt,
    required List<ProcessNode> processes,
    required List<Map<String, dynamic>> flows,
    ParameterSet? parameters,
  }) async {
    _log('[LCA] === generateAndMergeScenarios START ===');

    final baseModelFull = _buildBaseModelFull(processes, flows, parameters);
    final baseModelForLLM = _buildBaseModelForLLM(processes, flows, parameters);

    final userPayload = jsonEncode({
      'scenario_prompt': prompt,
      'baseModel': baseModelForLLM,
    });

    const systemPrompt =
        llmSystemPromptParametersOnly; // from llm_system_prompt.dart
    final functions = llmFunctions; // defined alongside prompt

    // Step 1: initial call
    _log('[LCA] First OpenAI call. model=$model');
    final firstResp = await _callOpenAI(
      systemPrompt: systemPrompt,
      userPayload: userPayload,
      functions: functions,
      jsonOnly: false, // may receive tool/function calls
    );
    _log('[LCA] First call returned. Parsing for tools or direct JSON');

    // Parse for tool/function calls or direct scenarios
    final parsed = await _handleToolOrScenarios(
      firstResp,
      baseModelFull,
      systemPrompt,
      userPayload,
    );
    _log(
        '[LCA] Parsed assistant output. functionsUsed=${parsed.functionsUsed.join(', ')}');

    // Merge scenarios locally
    _log('[LCA] Merging scenarios locally');
    final mergedFull =
        mergeScenarios(baseModelFull, parsed.rawDeltasByScenario);

    _log('[LCA] === generateAndMergeScenarios END ===');

    return LlmScenarioResult(
      mergedScenarios: mergedFull['scenarios'] as Map<String, dynamic>,
      rawDeltasByScenario: parsed.rawDeltasByScenario,
      functionsUsed: parsed.functionsUsed,
    );
  }

  /// Calls OpenAI using Chat Completions with modern tool-calling shape.
  /// Keeps behaviour compatible with legacy function calling.
  Future<Map<String, dynamic>> _callOpenAI({
    required String systemPrompt,
    required String userPayload,
    List<Map<String, dynamic>>? functions, // legacy schema
    String functionCallMode = 'auto', // 'auto' | 'none' or a function name
    List<Map<String, dynamic>>? messagesOverride,
    bool jsonOnly = false,
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
    };

    final uri = _resolveChatCompletionsUri();
    final trimmedApiKey = apiKey.trim();
    if (trimmedApiKey.isEmpty) {
      throw Exception(
        'Missing OpenAI API key. Set it in-app or pass '
        '--dart-define=OPENAI_API_KEY=...',
      );
    }

    final encodedBody = jsonEncode(body);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $trimmedApiKey',
    };
    _log(
      '[LCA][$_controllerRevision] POST $uri (apiBaseRaw="$apiBase") '
      'jsonOnly=$jsonOnly messages=${(body['messages'] as List).length}',
    );

    http.Response? resp;
    for (var attempt = 1; attempt <= 2; attempt += 1) {
      try {
        resp = await http
            .post(
              uri,
              headers: headers,
              body: encodedBody,
            )
            .timeout(const Duration(seconds: 70));
        break;
      } on TimeoutException catch (e) {
        if (attempt >= 2) {
          throw Exception(
            'OpenAI request timed out [$_controllerRevision]: $e '
            '(attempts=$attempt, resolvedUri=$uri, apiBaseRaw="$apiBase")',
          );
        }
        _log('[LCA] Timeout talking to OpenAI. Retrying once...');
      } on http.ClientException catch (e) {
        if (_shouldRetryClientException(e, attempt)) {
          _log(
              '[LCA] OpenAI network error on attempt $attempt. Retrying once...');
          await Future<void>.delayed(const Duration(milliseconds: 300));
          continue;
        }
        throw Exception(
          'OpenAI network failure [$_controllerRevision]: $e '
          '(resolvedUri=$uri, apiBaseRaw="$apiBase").'
          '${_webFailedToFetchHint(uri, e)}',
        );
      } catch (e) {
        throw Exception(
          'OpenAI request failed [$_controllerRevision]: $e '
          '(resolvedUri=$uri, apiBaseRaw="$apiBase")',
        );
      }
    }

    if (resp == null) {
      throw Exception(
        'OpenAI request failed [$_controllerRevision]: no response '
        '(resolvedUri=$uri, apiBaseRaw="$apiBase")',
      );
    }

    _log('[LCA] HTTP status ${resp.statusCode}');
    if (resp.statusCode != 200) {
      _log('[LCA] Error body: ${resp.body}');
      throw Exception('OpenAI error ${resp.statusCode}: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw Exception('OpenAI response missing choices');
    }
    _log('[LCA] Response has ${choices.length} choice(s)');
    return decoded;
  }

  /// Parses GPT output for tool/function calls or direct scenarios.
  /// Supports multiple tool calls in a single assistant turn.
  Future<_ParsedLLMOutput> _handleToolOrScenarios(
    Map<String, dynamic> firstResp,
    Map<String, dynamic> baseModelFull,
    String systemPrompt,
    String userPayload,
  ) async {
    final firstChoice =
        (firstResp['choices'] as List).first as Map<String, dynamic>;
    final message = firstChoice['message'] as Map<String, dynamic>;

    final functionsUsed = <String>[];
    Map<String, List<Map<String, dynamic>>> rawDeltasByScenario = {};

    // Defensive check for an empty assistant message
    if ((message['tool_calls'] == null ||
            (message['tool_calls'] as List?)?.isEmpty == true) &&
        (message['function_call'] == null) &&
        (message['content'] == null ||
            (message['content'] as String?)?.trim().isEmpty == true)) {
      _log('[LCA] Assistant returned empty content and no tool calls');
      throw Exception(
          'Assistant returned an empty message. Check model, prompt, or function specs.');
    }

    // Newer tool_calls path
    if (message.containsKey('tool_calls') && message['tool_calls'] != null) {
      final List toolCalls = message['tool_calls'] as List;
      _log('[LCA] tool_calls count=${toolCalls.length}');

      if (toolCalls.isEmpty) {
        final scenarios = _extractScenariosFromMessage(message);
        _log('[LCA] No tool calls. Parsed scenarios directly');
        rawDeltasByScenario = _mapChanges(scenarios);
        return _ParsedLLMOutput(
            functionsUsed: functionsUsed,
            rawDeltasByScenario: rawDeltasByScenario);
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
      for (final tc in toolCalls) {
        final tool = (tc as Map<String, dynamic>);
        final toolId = tool['id'] as String? ?? 'tool_call_$idx';
        final fn = tool['function'] as Map<String, dynamic>;
        final name = fn['name'] as String;
        final argsRaw = fn['arguments'];
        final Map<String, dynamic> args = (argsRaw is String)
            ? jsonDecode(argsRaw)
            : (argsRaw as Map).cast<String, dynamic>();
        functionsUsed.add(name);
        _log(
            '[LCA] Executing tool[$idx] name=$name id=$toolId args=${jsonEncode(args)}');

        final localResult = _runLocalFunction(name, args, baseModelFull);
        final Map<String, dynamic> toolReturn =
            _wrapToolResult(name, localResult);
        _log('[LCA] Tool[$idx] result keys=${toolReturn.keys.join(', ')}');

        followup.add({
          'role': 'tool',
          'tool_call_id': toolId,
          'content': jsonEncode(toolReturn),
        });
        idx += 1;
      }

      _log('[LCA] Second OpenAI call for final scenarios (JSON only)');
      final secondResp = await _callOpenAI(
        systemPrompt: systemPrompt,
        userPayload: userPayload,
        messagesOverride: followup,
        jsonOnly: true,
      );

      final scenarios = _extractScenariosFromMessage(
        (secondResp['choices'] as List).first['message'],
      );
      _log('[LCA] Final scenarios received. Mapping changes');
      rawDeltasByScenario = _mapChanges(scenarios);
    }
    // Legacy function_call path
    else if (message.containsKey('function_call') &&
        message['function_call'] != null) {
      final name = message['function_call']['name'] as String;
      final argsRaw = message['function_call']['arguments'];
      final Map<String, dynamic> args = (argsRaw is String)
          ? jsonDecode(argsRaw)
          : (argsRaw as Map).cast<String, dynamic>();
      functionsUsed.add(name);
      _log('[LCA] Legacy function_call name=$name args=${jsonEncode(args)}');

      final localResult = _runLocalFunction(name, args, baseModelFull);
      final Map<String, dynamic> toolReturn =
          _wrapToolResult(name, localResult);
      _log(
          '[LCA] Legacy function_call local result keys=${toolReturn.keys.join(', ')}');

      final secondMessages = [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPayload},
        {
          'role': 'assistant',
          'content': null,
          'function_call': {'name': name, 'arguments': jsonEncode(args)},
        },
        {'role': 'function', 'name': name, 'content': jsonEncode(toolReturn)},
      ];

      _log('[LCA] Second OpenAI call for final scenarios (JSON only)');
      final secondResp = await _callOpenAI(
        systemPrompt: systemPrompt,
        userPayload: userPayload,
        messagesOverride: secondMessages,
        jsonOnly: true,
      );

      final scenarios = _extractScenariosFromMessage(
        (secondResp['choices'] as List).first['message'],
      );
      _log('[LCA] Final scenarios received. Mapping changes');
      rawDeltasByScenario = _mapChanges(scenarios);
    }
    // Direct scenarios
    else {
      _log('[LCA] No tools. Attempting to parse scenarios directly');
      final scenarios = _extractScenariosFromMessage(message);
      rawDeltasByScenario = _mapChanges(scenarios);
      _log('[LCA] Direct scenarios parsed and mapped');
    }

    return _ParsedLLMOutput(
      functionsUsed: functionsUsed,
      rawDeltasByScenario: rawDeltasByScenario,
    );
  }

  /// Wrap local tool output in a shape the LLM prompt expects.
  Map<String, dynamic> _wrapToolResult(String name, dynamic localResult) {
    switch (name) {
      case 'oneAtATimeSensitivity':
      case 'fullSystemUncertainty':
      case 'simplexLatticeDesign':
        return {'changeLists': localResult};
      case 'distanceOneToMany':
        // Normalise to a generic wrapper so the prompt can describe it clearly
        return {'result': localResult};
      default:
        return {'result': localResult};
    }
  }

  /// Local numeric or data function execution.
  dynamic _runLocalFunction(
    String name,
    Map<String, dynamic> args,
    Map<String, dynamic> baseModelFull,
  ) {
    _log('[LCA] _runLocalFunction dispatch name=$name');
    switch (name) {
      case 'oneAtATimeSensitivity':
        return oneAtATimeSensitivity(
          baseModel: baseModelFull,
          parameterNames: (args['parameterNames'] as List).cast<String>(),
          percent: (args['percent'] as num).toDouble(),
          levels: (args['levels'] as List?)
              ?.cast<num>()
              .map((n) => n.toDouble())
              .toList(),
        );
      case 'fullSystemUncertainty':
        return fullSystemUncertainty(
          baseModel: baseModelFull,
          percent: (args['percent'] as num).toDouble(),
          levels: (args['levels'] as List?)
              ?.cast<num>()
              .map((n) => n.toDouble())
              .toList(),
        );
      case 'simplexLatticeDesign':
        return simplexLatticeDesign(
          baseModel: baseModelFull,
          parameterNames: (args['parameterNames'] as List).cast<String>(),
          m: (args['m'] as num).toInt(),
        );
      case 'distanceOneToMany':
        // Use injected handler if provided, otherwise fall back to the built-in.
        // Never let this tool crash the whole scenario run.
        try {
          final handler =
              distanceOneToManyHandler ?? distance_tool.distanceOneToMany;
          if (distanceOneToManyHandler == null) {
            _log('[LCA] distanceOneToMany using built-in handler fallback');
          }
          return handler(args);
        } catch (e, st) {
          _log('[LCA] distanceOneToMany error: $e\n$st');
          // Provide a structured fallback so the LLM can still produce scenarios
          final Map md = (args['maxDistance'] as Map?) ?? const {};
          final String units =
              (md['units'] is String) ? (md['units'] as String) : 'km';
          final String destCode = (args['destination'] is String)
              ? (args['destination'] as String).toUpperCase()
              : 'UNKNOWN';
          return {
            'destination': {'code': destCode, 'name': destCode},
            'units': units,
            'results': const [],
            'filtered_out': const [],
            'meta': {'error': 'tool_failed', 'message': e.toString()}
          };
        }
      default:
        _log('[LCA] Unknown function or tool: $name');
        throw Exception('Unknown function or tool: $name');
    }
  }

  /// Extracts scenarios object from GPT message
  Map<String, dynamic> _extractScenariosFromMessage(dynamic message) {
    final content = message['content'];
    if (content is! String) {
      _log('[LCA] Unexpected message content type: ${content.runtimeType}');
      throw Exception('Unexpected message format: missing string content.');
    }
    final cleaned = _normaliseJsonText(content.trim());
    try {
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
      _log('[LCA] Scenarios JSON parsed successfully');
      return parsed;
    } on FormatException catch (e) {
      final preview =
          cleaned.length > 200 ? '${cleaned.substring(0, 200)}…' : cleaned;
      _log(
          '[LCA] Failed to parse scenarios JSON: ${e.message}. Preview: $preview');
      throw Exception(
          'Failed to parse scenarios JSON: ${e.message}. Preview: $preview');
    }
  }

  /// Converts scenarios JSON into rawDeltasByScenario map
  Map<String, List<Map<String, dynamic>>> _mapChanges(
      Map<String, dynamic> scenariosJson) {
    final scenariosMap = scenariosJson['scenarios'] as Map<String, dynamic>;
    final out = <String, List<Map<String, dynamic>>>{};
    _log(
        '[LCA] Mapping scenarios to change lists. Count=${scenariosMap.length}');
    scenariosMap.forEach((name, data) {
      final raw = (data['changes'] as List).cast<Map<String, dynamic>>();
      out[name] = _preferGlobalParameterWhenDuplicate(raw, scenarioName: name);
    });
    _log('[LCA] Mapping complete');
    return out;
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
}

/// Internal struct for returning parsed LLM output
class _ParsedLLMOutput {
  final List<String> functionsUsed;
  final Map<String, List<Map<String, dynamic>>> rawDeltasByScenario;

  _ParsedLLMOutput({
    required this.functionsUsed,
    required this.rawDeltasByScenario,
  });
}
