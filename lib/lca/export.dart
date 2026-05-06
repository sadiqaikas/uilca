// File: lib/lca/export.dart

import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'newhome/lca_models.dart';
import 'newllm/document_parameterisation.dart';
import 'newllm/llm_scenario_controller.dart';
import 'newllm/llm_scenario_page.dart';   // Relative import for LLMPage

class LCAJsonExportPage extends StatefulWidget {
  final List<ProcessNode> processes;
  final List<Map<String, dynamic>> flows;
  final ParameterSet? parameters;
  final Map<String, dynamic>? openLcaProductSystem;

  const LCAJsonExportPage({
    super.key,
    required this.processes,
    required this.flows,
    this.parameters,
    this.openLcaProductSystem,
  });

  @override
  State<LCAJsonExportPage> createState() => _LCAJsonExportPageState();
}

class _LCAJsonExportPageState extends State<LCAJsonExportPage> {
  static const String _openLcaBackendBaseUrl = String.fromEnvironment(
    'OPENLCA_BACKEND_BASE_URL',
    defaultValue: 'http://localhost:8001',
  );
  static const String _openLcaIpcUrl = String.fromEnvironment(
    'OPENLCA_IPC_URL',
    defaultValue: 'http://localhost:8080',
  );

  final TextEditingController _scenarioCtrl = TextEditingController();
  final TextEditingController _parameterSearchCtrl = TextEditingController();
  final TextEditingController _impactSearchCtrl = TextEditingController();
  final DocumentParameterisationService _documentService =
      const DocumentParameterisationService();

  bool _showPromptTools = true;
  bool _isLoadingImpactMethods = false;
  bool _isUploadingDocument = false;
  String? _impactMethodError;
  List<Map<String, dynamic>> _impactMethods = const [];
  List<LlmDocumentReference> _uploadedDocuments = const [];
  List<DocumentExtractionRecord> _documentProvenance = const [];

  @override
  void initState() {
    super.initState();
    _parameterSearchCtrl.addListener(() => setState(() {}));
    _impactSearchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _scenarioCtrl.dispose();
    _parameterSearchCtrl.dispose();
    _impactSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _onNextPressed() async {
    final prompt = _scenarioCtrl.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the scenario first')),
      );
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LLMScenarioPage(
          prompt: prompt,
          processes: widget.processes,
          flows: widget.flows,
          parameters: widget.parameters,
          openLcaProductSystem: widget.openLcaProductSystem,
          uploadedDocuments: _uploadedDocuments,
        ),
      ),
    );
    if (!mounted) return;
    if (result is List<DocumentExtractionRecord>) {
      setState(() {
        _documentProvenance = result;
      });
    }
  }

  void _guardWebMixedContent(Uri uri) {
    if (kIsWeb && Uri.base.scheme == 'https' && uri.scheme == 'http') {
      throw Exception(
        'The app is running over HTTPS but the OpenLCA backend URL is HTTP.',
      );
    }
  }

  List<String> _openLcaBackendCandidates() {
    final configured = _openLcaBackendBaseUrl.trim();
    final candidates = <String>[];
    void add(String value) {
      final v = value.trim();
      if (v.isNotEmpty && !candidates.contains(v)) {
        candidates.add(v);
      }
    }

    add(configured);
    add(configured.replaceAll('localhost', '127.0.0.1'));
    add(configured.replaceAll('127.0.0.1', 'localhost'));
    return candidates;
  }

  Future<http.Response> _getFromOpenLcaBridge(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    Object? lastError;
    for (final base in _openLcaBackendCandidates()) {
      final uri = Uri.parse('$base$path').replace(queryParameters: queryParameters);
      _guardWebMixedContent(uri);
      try {
        final response = await http.get(
          uri,
          headers: const {'Accept': 'application/json'},
        );
        if (response.statusCode == 200) {
          return response;
        }
        lastError = Exception(
          'OpenLCA backend error ${response.statusCode}: ${response.body}',
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw Exception(
      'OpenLCA bridge unreachable on ${_openLcaBackendCandidates().join(', ')}. '
      'Last error: $lastError',
    );
  }

  Future<void> _loadOpenLcaImpactMethods() async {
    if (_isLoadingImpactMethods) return;
    setState(() {
      _isLoadingImpactMethods = true;
      _impactMethodError = null;
    });

    try {
      final response = await _getFromOpenLcaBridge(
        '/openlca/impact-methods',
        queryParameters: {'ipc_url': _openLcaIpcUrl},
      );

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('OpenLCA backend returned invalid JSON.');
      }

      final count = (decoded['count'] as num?)?.toInt() ?? 0;
      final rawMethods = decoded['impact_methods'];
      final methods = rawMethods is List
          ? rawMethods
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      if (count == 0 || methods.isEmpty) {
        setState(() {
          _impactMethods = const [];
          _impactMethodError =
              'OpenLCA IPC backend returned 0 LCIA methods for $_openLcaIpcUrl.';
        });
        return;
      }
      setState(() => _impactMethods = methods);
    } catch (e) {
      if (!mounted) return;
      setState(() => _impactMethodError = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoadingImpactMethods = false);
      }
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

  String _parameterLabel(Parameter parameter, {String? processId}) {
    final value = parameter.formula?.trim().isNotEmpty == true
        ? parameter.formula!.trim()
        : parameter.value?.toString();
    final unit = parameter.unit?.trim();
    final details = [
      if (value != null && value.isNotEmpty) value,
      if (unit != null && unit.isNotEmpty) unit,
    ].join(' ');
    final scope = processId == null ? 'Global' : _processNameForId(processId);
    return details.isEmpty
        ? '$scope: ${parameter.name}'
        : '$scope: ${parameter.name} = $details';
  }

  String _impactMethodName(Map<String, dynamic> method) {
    final name = (method['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final id = (method['id'] ?? '').toString().trim();
    return id.isEmpty ? 'Unnamed impact method' : id;
  }

  List<_ParameterChoice> _parameterChoices(ParameterSet? params) {
    if (params == null || params.isEmpty) return const [];

    final choices = <_ParameterChoice>[
      for (final parameter in params.global)
        _ParameterChoice(
          label: _parameterLabel(parameter),
          insertText: 'parameters.global.${parameter.name}',
        ),
      for (final entry in params.perProcess.entries)
        for (final parameter in entry.value)
          _ParameterChoice(
            label: _parameterLabel(parameter, processId: entry.key),
            insertText:
                'parameters.process.${parameter.name} process_id=${entry.key}',
          ),
    ];
    choices.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return choices;
  }

  List<_ImpactCategoryChoice> _impactCategoryChoices() {
    final choices = <_ImpactCategoryChoice>[];
    for (final method in _impactMethods) {
      final methodName = _impactMethodName(method);
      final rawCategories = method['impact_categories'];
      if (rawCategories is List && rawCategories.isNotEmpty) {
        for (final rawCategory in rawCategories) {
          if (rawCategory is! Map) continue;
          final category = Map<String, dynamic>.from(rawCategory);
          final categoryName = (category['name'] ?? '').toString().trim();
          if (categoryName.isEmpty) continue;
          choices.add(
            _ImpactCategoryChoice(
              methodName: methodName,
              categoryName: categoryName,
            ),
          );
        }
      } else {
        choices.add(
          _ImpactCategoryChoice(
            methodName: methodName,
            categoryName: methodName,
          ),
        );
      }
    }
    choices.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return choices;
  }

  List<_ParameterChoice> _filterParameterChoices(ParameterSet? params) {
    final query = _parameterSearchCtrl.text.trim().toLowerCase();
    final choices = _parameterChoices(params);
    if (query.isEmpty) return choices.take(10).toList();
    return choices
        .where((choice) => choice.label.toLowerCase().contains(query))
        .take(10)
        .toList();
  }

  List<_ImpactCategoryChoice> _filterImpactCategoryChoices() {
    final query = _impactSearchCtrl.text.trim().toLowerCase();
    final choices = _impactCategoryChoices();
    if (query.isEmpty) return choices.take(10).toList();
    return choices
        .where((choice) => choice.label.toLowerCase().contains(query))
        .take(10)
        .toList();
  }

  void _insertIntoScenario(String text) {
    final current = _scenarioCtrl.text;
    final selection = _scenarioCtrl.selection;
    final insertion = text.trim();
    if (insertion.isEmpty) return;

    final prefix = current.isEmpty || RegExp(r'\s$').hasMatch(current) ? '' : ' ';
    final suffix = RegExp(r'[,.]$').hasMatch(insertion) ? ' ' : ', ';
    if (!selection.isValid) {
      final nextText = '$current$prefix$insertion$suffix';
      _scenarioCtrl.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
      return;
    }

    final nextText = current.replaceRange(
      selection.start,
      selection.end,
      '$prefix$insertion$suffix',
    );
    final nextOffset = selection.start + prefix.length + insertion.length + suffix.length;
    _scenarioCtrl.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
  }

  Future<void> _onUploadDocumentPressed() async {
    if (_isUploadingDocument) return;

    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The selected PDF could not be read. Try another file.'),
        ),
      );
      return;
    }

    setState(() => _isUploadingDocument = true);
    try {
      final uploaded = await _documentService.uploadPdf(
        bytes: bytes,
        filename: file.name,
      );
      final replacedDocuments = _uploadedDocuments
          .where(
            (document) =>
                document.name.trim().toLowerCase() ==
                uploaded.name.trim().toLowerCase(),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _uploadedDocuments = [
          for (final document in _uploadedDocuments)
            if (document.id != uploaded.id &&
                document.name.trim().toLowerCase() !=
                    uploaded.name.trim().toLowerCase())
              document,
          uploaded,
        ];
      });
      for (final document in replacedDocuments) {
        try {
          await _documentService.deleteDocument(document.id);
        } catch (_) {}
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Uploaded PDF: ${uploaded.displayName}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Document upload failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingDocument = false);
      }
    }
  }

  Future<void> _removeUploadedDocument(LlmDocumentReference document) async {
    setState(() {
      _uploadedDocuments = [
        for (final item in _uploadedDocuments)
          if (item.id != document.id) item,
      ];
    });
    try {
      await _documentService.deleteDocument(document.id);
    } catch (_) {}
  }

  Widget _buildDocumentTools() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reference documents',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Upload a PDF, then reference it explicitly in your prompt. Example: '
              '"From uploaded document lca_final.pdf Appendix C, use the table value for ..."',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _isUploadingDocument ? null : _onUploadDocumentPressed,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Upload PDF'),
                ),
                if (_uploadedDocuments.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () {
                      final names = _uploadedDocuments
                          .map((document) => document.promptInsertionText)
                          .join(' and ');
                      _insertIntoScenario(names);
                    },
                    icon: const Icon(Icons.add_comment),
                    label: const Text('Insert document reference'),
                  ),
                OutlinedButton.icon(
                  onPressed: _showDocumentPreview,
                  icon: const Icon(Icons.table_view),
                  label: const Text('Preview extracted tables'),
                ),
              ],
            ),
            if (_isUploadingDocument) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 10),
            if (_uploadedDocuments.isEmpty)
              const Text('No PDFs uploaded.')
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _uploadedDocuments.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final document = _uploadedDocuments[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.description_outlined),
                      title: Text(document.displayName),
                      subtitle: Text(document.summaryText),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Insert reference into prompt',
                            onPressed: () => _insertIntoScenario(
                              document.promptInsertionText,
                            ),
                            icon: const Icon(Icons.add, size: 20),
                          ),
                          IconButton(
                            tooltip: 'Remove document',
                            onPressed: () => _removeUploadedDocument(document),
                            icon: const Icon(Icons.delete_outline, size: 20),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptTools(ParameterSet? params) {
    final allParameters = _parameterChoices(params);
    final visibleParameters = _filterParameterChoices(params);
    final visibleImpacts = _filterImpactCategoryChoices();

    return _buildCollapsible(
      title: 'Prompt helpers',
      expanded: _showPromptTools,
      onToggle: () => setState(() => _showPromptTools = !_showPromptTools),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Parameters',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (allParameters.isEmpty)
            const Text('No editable parameters are available in this model.')
          else ...[
            TextField(
              controller: _parameterSearchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _parameterSearchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear parameter search',
                        icon: const Icon(Icons.close),
                        onPressed: _parameterSearchCtrl.clear,
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
                labelText: 'Search ${allParameters.length} parameters',
              ),
            ),
            const SizedBox(height: 8),
            _PromptChoiceList<_ParameterChoice>(
              items: visibleParameters,
              icon: Icons.tune,
              labelFor: (choice) => choice.label,
              onSelected: (choice) => _insertIntoScenario(choice.insertText),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'OpenLCA impact categories',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Refresh OpenLCA impact categories',
                onPressed:
                    _isLoadingImpactMethods ? null : _loadOpenLcaImpactMethods,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isLoadingImpactMethods)
            const LinearProgressIndicator()
          else if (_impactMethodError != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OpenLCA impact categories unavailable: $_impactMethodError',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton.icon(
                  onPressed: _loadOpenLcaImpactMethods,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            )
          else if (_impactMethods.isEmpty)
            OutlinedButton.icon(
              onPressed: _loadOpenLcaImpactMethods,
              icon: const Icon(Icons.download),
              label: const Text('Load OpenLCA impact categories'),
            )
          else ...[
            TextField(
              controller: _impactSearchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _impactSearchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear impact category search',
                        icon: const Icon(Icons.close),
                        onPressed: _impactSearchCtrl.clear,
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
                labelText:
                    'Search ${_impactCategoryChoices().length} impact categories',
              ),
            ),
            const SizedBox(height: 8),
            _PromptChoiceList<_ImpactCategoryChoice>(
              items: visibleImpacts,
              icon: Icons.insights,
              labelFor: (choice) => choice.label,
              onSelected: (choice) => _insertIntoScenario(
                choice.insertText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCollapsible({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          ListTile(
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            onTap: onToggle,
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: child,
            ),
        ],
      ),
    );
  }

  Map<String, dynamic> _buildLlmPayloadPreview() {
    return {
      'scenario_prompt': _scenarioCtrl.text.trim(),
      'model_context': LlmScenarioController.buildModelContextForLLM(
        widget.processes,
        widget.parameters,
      ),
      if (_uploadedDocuments.isNotEmpty)
        'document_context': {
          'documents': _uploadedDocuments
              .map((document) => document.toPromptContextJson())
              .toList(),
        },
    };
  }

  Future<void> _showPayloadPreview() async {
    final payloadText =
        const JsonEncoder.withIndent('  ').convert(_buildLlmPayloadPreview());
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('LLM payload'),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: SelectableText(
                payloadText,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
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

  Future<void> _showDocumentPreview() async {
    if (_documentProvenance.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Extracted table preview'),
            content: const Text(
              'No extracted table preview is available yet. Run a scenario and return to this page.',
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
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Extracted table preview'),
          content: SizedBox(
            width: 760,
            height: 520,
            child: ListView.separated(
              itemCount: _documentProvenance.length,
              separatorBuilder: (_, __) => const Divider(height: 20),
              itemBuilder: (context, index) {
                final record = _documentProvenance[index];
                return ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(record.sourceSummary),
                  subtitle: Text(
                    record.query.isEmpty ? 'No query captured' : record.query,
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        'Assumptions:\n'
                        '${record.assumptions.isEmpty ? '- none' : record.assumptions.map((item) => '- $item').join('\n')}',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        'Matches:\n${const JsonEncoder.withIndent('  ').convert(record.matches)}',
                      ),
                    ),
                    if (record.fallbackTextMatches.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          'Fallback text matches:\n${const JsonEncoder.withIndent('  ').convert(record.fallbackTextMatches)}',
                        ),
                      ),
                    ],
                  ],
                );
              },
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

  @override
  Widget build(BuildContext context) {
    final params = widget.parameters;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Describe Scenario & Export'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Text(
              'Describe your LCA scenario in detail. This description will be sent along with your model data.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: _scenarioCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Scenario description',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                        hintText: 'e.g. Reduce electricity demand by 10% and evaluate climate change.',
                      ),
                      maxLines: null,
                      minLines: 5,
                      keyboardType: TextInputType.multiline,
                    ),
                    const SizedBox(height: 12),

                    _buildDocumentTools(),
                    const SizedBox(height: 12),

                    _buildPromptTools(params),
                  ],
                ),
              ),
            ),

            SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _showPayloadPreview,
                    icon: const Icon(Icons.visibility),
                    label: const Text('Show payload'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _onNextPressed,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParameterChoice {
  final String label;
  final String insertText;

  const _ParameterChoice({
    required this.label,
    required this.insertText,
  });
}

class _ImpactCategoryChoice {
  final String methodName;
  final String categoryName;

  const _ImpactCategoryChoice({
    required this.methodName,
    required this.categoryName,
  });

  String get label {
    if (methodName == categoryName) return categoryName;
    return '$methodName / $categoryName';
  }

  String get insertText {
    if (methodName == categoryName) return categoryName;
    return '$methodName / $categoryName';
  }
}

class _PromptChoiceList<T> extends StatelessWidget {
  final List<T> items;
  final IconData icon;
  final String Function(T item) labelFor;
  final void Function(T item) onSelected;

  const _PromptChoiceList({
    required this.items,
    required this.icon,
    required this.labelFor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('No matches.');
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            dense: true,
            leading: Icon(icon, size: 20),
            title: Text(
              labelFor(item),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.add, size: 20),
            onTap: () => onSelected(item),
          );
        },
      ),
    );
  }
}
