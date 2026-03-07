// File: lib/lca/export.dart

import 'dart:convert';
import 'package:flutter/material.dart';

import 'newhome/lca_models.dart';
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
  final TextEditingController _scenarioCtrl = TextEditingController();

  bool _showParams = false;
  bool _showProcesses = false;
  bool _showFlows = false;

  @override
  void dispose() {
    _scenarioCtrl.dispose();
    super.dispose();
  }

  void _onNextPressed() {
    final prompt = _scenarioCtrl.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the scenario first')),
      );
      return;
    }

    final exportJson = {
      'parameters': widget.parameters?.toJson(),
      'processes': widget.processes.map((p) => p.toJson()).toList(),
      'flows': widget.flows,
    };

    // Debug print for developer check
    debugPrint(jsonEncode(exportJson));

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LLMScenarioPage(
          prompt: prompt,
          processes: widget.processes,
          flows: widget.flows,
          parameters: widget.parameters,
          openLcaProductSystem: widget.openLcaProductSystem,
        ),
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

  @override
  Widget build(BuildContext context) {
    final params = widget.parameters;
    final paramText = params != null ? const JsonEncoder.withIndent('  ').convert(params.toJson()) : 'No parameters';

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
                        hintText: 'e.g. Perform Monte Carlo experiment on energy inputs...',
                      ),
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                    ),
                    const SizedBox(height: 12),

                    _buildCollapsible(
                      title: 'Parameters (${params?.global.length ?? 0} global, '
    '${params?.perProcess.length ?? 0} process-specific)',

                      expanded: _showParams,
                      onToggle: () => setState(() => _showParams = !_showParams),
                      child: SelectableText(paramText, style: const TextStyle(fontFamily: 'monospace')),
                    ),

                    _buildCollapsible(
                      title: 'Processes (${widget.processes.length})',
                      expanded: _showProcesses,
                      onToggle: () => setState(() => _showProcesses = !_showProcesses),
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ')
                            .convert(widget.processes.map((p) => p.toJson()).toList()),
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),

                    _buildCollapsible(
                      title: 'Flows (${widget.flows.length})',
                      expanded: _showFlows,
                      onToggle: () => setState(() => _showFlows = !_showFlows),
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert(widget.flows),
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _onNextPressed,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
