// lib/pages/parametric_lca_page.dart

import 'package:flutter/material.dart';

class ParametricLcaPage extends StatefulWidget {
  const ParametricLcaPage({Key? key}) : super(key: key);

  @override
  _ParametricLcaPageState createState() => _ParametricLcaPageState();
}

class _ParametricLcaPageState extends State<ParametricLcaPage> {
  final TextEditingController _chatController = TextEditingController();
  final List<String> _chatMessages = [];

  int _nextCanvasId = 1;
  final List<int> _canvasIds = [1];

  void _onSendChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _chatMessages.add(text);
      _chatController.clear();
    });
    // TODO: send to LLM/orchestrator
  }

  void _onAddProcess() {
    // TODO: open your process editor
  }

  void _onAddCanvas() {
    setState(() => _canvasIds.add(++_nextCanvasId));
  }

  void _onRunLca() {
    // TODO: trigger batch LCA run
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parametric LCA Studio'),
      ),
      body: Row(
        children: [
          // ─── Left: Chat Panel ───────────────────────────
          Container(
            width: MediaQuery.of(context).size.width * 0.3,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Column(
              children: [
                // Chat history
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _chatMessages.length,
                    itemBuilder: (_, i) => Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: Align(
                        alignment: i.isOdd
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: i.isOdd
                                ? Colors.blue.shade100
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(_chatMessages[i]),
                        ),
                      ),
                    ),
                  ),
                ),

                // Chat input
                SafeArea(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _chatController,
                            decoration: const InputDecoration(
                              hintText: 'Type a message…',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _onSendChat(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: _onSendChat,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ─── Right: Canvas + Controls ───────────────────
          Expanded(
            child: Column(
              children: [
                // Top: Process Panel
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      ElevatedButton(
                        onPressed: _onAddProcess,
                        child: const Text('Add Process'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _onAddCanvas,
                        child: const Text('New Canvas'),
                      ),
                      const Spacer(),
                      // Could add more buttons here later…
                    ],
                  ),
                ),

                // Middle: Canvas area
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: _canvasIds.map(_buildCanvas).toList(),
                    ),
                  ),
                ),

                // Bottom: Run LCA
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _onRunLca,
                      child: const Text(
                        'Run LCA',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(int id) {
    return Container(
      width: 300,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          'Canvas #$id',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
        ),
      ),
    );
  }
}
