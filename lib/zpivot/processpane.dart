import 'package:flutter/material.dart';

class ProcessPane extends StatelessWidget {
  final List<String> palette;
  final VoidCallback onAddCustomProcess;

  const ProcessPane({
    Key? key,
    required this.palette,
    required this.onAddCustomProcess,
  }) : super(key: key);

  @override
  Widget build(BuildContext ctx) {
    return Container(
      height: 80,
      color: Colors.grey[100],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // 1) Draggable predictions
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemCount: palette.length,
              itemBuilder: (c, i) {
                final label = palette[i];
                return Draggable<String>(
                  data: label,
                  feedback: _buildChip(label, opacity: 0.7),
                  childWhenDragging: _buildChip(label, opacity: 0.4),
                  child: _buildChip(label),
                );
              },
            ),
          ),

          // 2) Add custom
          IconButton(
            tooltip: 'Add Custom Process',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: onAddCustomProcess,
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, {double opacity = 1.0}) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade300,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 3)],
        ),
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
