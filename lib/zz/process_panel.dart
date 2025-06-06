import 'package:flutter/material.dart';

class ProcessPanel extends StatelessWidget {
  final VoidCallback onAddProcess;
  final VoidCallback onAddCanvas;

  const ProcessPanel({
    Key? key,
    required this.onAddProcess,
    required this.onAddCanvas,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: onAddProcess,
            child: const Text('Add Process'),
          ),
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: onAddCanvas,
            child: const Text('Add Canvas'),
          ),
        ],
      ),
    );
  }
}
