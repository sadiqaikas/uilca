import 'package:flutter/material.dart';

import 'tool_description.dart';

class TipsSection extends StatelessWidget {
  final VoidCallback onFillExample;
  const TipsSection({super.key, required this.onFillExample});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 24, 24, 24),
      child: Column(
        children: [
          // Tips Card.
          Expanded(
            child: Card(
              color: Colors.white,
              elevation: 10,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              shadowColor: Colors.blueGrey.withOpacity(0.1),
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Icon(Icons.lightbulb,
                              color: Colors.green.shade600, size: 22),
                          const SizedBox(width: 8),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Methodologies & Databases',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                      color: Colors.green.shade600,
                                    ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const Divider(height: 20, thickness: 1.2),
                      const SizedBox(height: 4),

                      // Main body text that can grow
                      Expanded(
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                // _buildTip('Greet.'),
                                // _buildTip('US eGrid2023.'),
                                // _buildTip('Brightway2 for LCIA.'),
                                //  _buildTip('Open AI- LLM'),
_buildTip('Brightway2 (LCA engine)'),
_buildTip('IPCC 2021 (Climate method)'),
_buildTip('Greet Database, Coming soon...'),
_buildTip('OpenAI LLM (Natural language understanding)'),
_buildTip('Custom user-defined processes, Coming soon..'),


                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      WhatPowersThisTool(),
                      
                      // Footer message pinned at bottom
                      // Center(
                      //   child: FittedBox(
                      //     fit: BoxFit.scaleDown,
                      //     child: Text(
                      //       'Just describe it — we’ll handle the complexity.',
                      //       style: TextStyle(
                      //         fontSize: 14,
                      //         fontStyle: FontStyle.italic,
                      //         color: Colors.blueGrey.shade400,
                      //       ),
                      //       textAlign: TextAlign.center,
                      //     ),
                      //   ),
                      // ),
                    ],
                  )),
            ),
          ),

          const SizedBox(height: 20),

          // Example Generator Card.
          Card(
            color: Colors.green.shade50,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome,
                          color: Colors.green.shade700, size: 22),
                      const SizedBox(width: 8),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Example',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                  color: Colors.green.shade700,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20, thickness: 1.2),
                  Text(
                    'Quickly get a realistic example for inspiration.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: onFillExample,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text(
                      'Example LCA',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildTip(String text) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.circle, size: 6, color: Colors.green),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.grey.shade800,
            ),
          ),
        ),
      ],
    ),
  );
}
