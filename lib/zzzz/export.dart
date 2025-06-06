// File: lib/zzzz/export.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'home.dart';       // Relative import of ProcessNode, etc.
import 'llm_page.dart';  // Relative import of LLMPage

class LCAJsonExportPage extends StatefulWidget {
  /// The list of processes and computed flows passed from home.dart
  final List<ProcessNode> processes;
  final List<Map<String, dynamic>> flows;

  const LCAJsonExportPage({
    super.key,
    required this.processes,
    required this.flows,
  });

  @override
  _LCAJsonExportPageState createState() => _LCAJsonExportPageState();
}

class _LCAJsonExportPageState extends State<LCAJsonExportPage> {
  // Controller for the large, multiline “scenario description” field:
  final TextEditingController _scenarioCtrl = TextEditingController();

  @override
  void dispose() {
    _scenarioCtrl.dispose();
    super.dispose();
  }

  /// When user taps “Next”, gather the prompt + process/flow data
  /// and push to the LLM‐handling page.
  void _onNextPressed() {
    final prompt = _scenarioCtrl.text.trim();
    if (prompt.isEmpty) {
      // Optionally show a message. For now, do nothing.
      return;
    }
print("promt");
print (prompt);
print("process");
print(widget.processes.map((p) => p.toJson()).toList())
;
print("flows");
print(widget.flows);

    // Navigate to the LLM page, passing along prompt + processes + flows:
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LLMPage(
          prompt: prompt,
          processes: widget.processes,
          flows: widget.flows,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Describe Scenario & Export'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 1) Instructions / label
            Text(
              'Please describe the scenario for your LCA analysis:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),

            SizedBox(height: 12),

            // 2) Large multiline TextField for scenario description:
            Expanded(
              child: TextField(
                controller: _scenarioCtrl,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText:
                      'e.g. “I want to evaluate the life cycle of producing 100 units of Widget X using electricity from Plant Y...”',
                ),
                maxLines: null, // allow vertical expansion
                expands: true,  // fill available space
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
              ),
            ),

            SizedBox(height: 16),

            // 3) “Next” button at bottom:
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _onNextPressed,
                child: Text('Next →'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
