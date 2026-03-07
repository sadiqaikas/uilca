// File: lib/lca/llm_scenario_page.dart

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
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
  static const String _defaultOpenAiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );
  static const String _defaultOpenAiBase = String.fromEnvironment(
    'OPENAI_API_BASE',
    defaultValue: 'https://api.openai.com/v1',
  );
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
  Map<String, dynamic>? _mergedScenarios; // scenarioName -> { model, meta? }
  Map<String, List<Map<String, dynamic>>>? _rawDeltasByScenario;
  List<String> _functionsUsed = const [];

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
    _primeApiKey();
    final selected = widget.openLcaProductSystem;
    if (selected != null) {
      _selectedOpenLcaProductSystem = Map<String, dynamic>.from(selected);
    }
  }

  Future<void> _primeApiKey() async {
    final fromDefine = _defaultOpenAiKey.trim();
    if (fromDefine.isNotEmpty) {
      await saveStoredOpenAiApiKey(fromDefine);
      if (!mounted) return;
      setState(() => _openAiApiKey = fromDefine);
      return;
    }

    final fromStorage = (await loadStoredOpenAiApiKey())?.trim();
    if (!mounted) return;
    if (fromStorage != null && fromStorage.isNotEmpty) {
      setState(() => _openAiApiKey = fromStorage);
    }
  }

  String _maskApiKey(String? key) {
    final value = key?.trim() ?? '';
    if (value.isEmpty) return 'not set';
    if (value.length <= 10) return 'set';
    return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
  }

  String? _validateApiKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return 'Enter an OpenAI API key.';
    if (!trimmed.startsWith('sk-')) {
      return 'OpenAI API keys usually start with "sk-".';
    }
    return null;
  }

  Future<String?> _showApiKeyDialog({String initialValue = ''}) async {
    final keyController = TextEditingController(text: initialValue);
    bool obscureText = true;
    String? validationMessage;

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('OpenAI API key'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Stored locally on this device/browser only. It is never sent to your OpenLCA backend.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keyController,
                      obscureText: obscureText,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: 'API key',
                        border: const OutlineInputBorder(),
                        errorText: validationMessage,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: !obscureText,
                          onChanged: (value) {
                            setDialogState(() => obscureText = value != true);
                          },
                        ),
                        const Text('Show key'),
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
                  onPressed: () => Navigator.of(dialogContext).pop(''),
                  child: const Text('Clear stored key'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final trimmed = keyController.text.trim();
                    final error = _validateApiKey(trimmed);
                    if (error != null) {
                      setDialogState(() => validationMessage = error);
                      return;
                    }
                    Navigator.of(dialogContext).pop(trimmed);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    keyController.dispose();
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
    final entered = await _showApiKeyDialog();
    if (entered == null) return null;
    if (entered.isEmpty) {
      await clearStoredOpenAiApiKey();
      if (mounted) setState(() => _openAiApiKey = null);
      return null;
    }

    final normalized = entered.trim();
    await saveStoredOpenAiApiKey(normalized);
    if (mounted) setState(() => _openAiApiKey = normalized);
    return normalized;
  }

  Future<void> _onSetApiKeyPressed() async {
    final current = _openAiApiKey ?? '';
    final entered = await _showApiKeyDialog(initialValue: current);
    if (entered == null) return;

    if (entered.isEmpty) {
      await clearStoredOpenAiApiKey();
      if (!mounted) return;
      setState(() => _openAiApiKey = null);
      return;
    }

    final normalized = entered.trim();
    await saveStoredOpenAiApiKey(normalized);
    if (!mounted) return;
    setState(() => _openAiApiKey = normalized);
  }

  Future<void> _onGeneratePressed() async {
    final apiKey = await _ensureOpenAiApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'OpenAI API key is required before generating scenarios.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _mergedScenarios = null;
      _rawDeltasByScenario = null;
      _functionsUsed = const [];
    });

    try {
      final controller = LlmScenarioController(
        apiKey: apiKey,
        apiBase: _defaultOpenAiBase,
      );
      final result = await controller.generateAndMergeScenarios(
        prompt: widget.prompt,
        processes: widget.processes,
        flows: widget.flows,
        parameters: widget.parameters,
      );

      if (!mounted) return;
      setState(() {
        _mergedScenarios = result.mergedScenarios;
        _rawDeltasByScenario = result.rawDeltasByScenario;
        _functionsUsed = result.functionsUsed;
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scenario generation failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>> _runLCAForAllScenarios() async {
    final Map<String, dynamic> allResults = {};
    if (_mergedScenarios == null || _mergedScenarios!.isEmpty) {
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

      try {
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
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
      } catch (e) {
        allResults[scenarioName] = {
          'success': false,
          'error': e.toString(),
        };
      }
    }

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
    );
    await downloadPdf(
      bytes: pdfBytes,
      filename: 'lca_results_report.pdf',
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF exported as lca_results_report.pdf'),
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
                        const SizedBox(height: 12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              onPressed: _onGeneratePressed,
                              child: const Text('Generate scenarios'),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: _onSetApiKeyPressed,
                              child: const Text('Set API key'),
                            ),
                          ],
                        ),
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
                              label: const Text('Regenerate scenarios'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _onSetApiKeyPressed,
                              icon: const Icon(Icons.key),
                              label: const Text('API key'),
                            ),
                          ],
                        ),
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
