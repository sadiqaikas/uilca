import 'package:flutter/material.dart';

class TextEditor extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final double freedom;
  final ValueChanged<double> onFreedomChanged;

  const TextEditor({
    Key? key,
    required this.controller,
    required this.onChanged,
    required this.freedom,
    required this.onFreedomChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext ctx) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              // 1) Prompt input
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(
                    hintText: 'Describe your LCA scenario…',
                    border: InputBorder.none,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 2) Creativity slider
              Row(
                children: [
                  const Text('Creativity'),
                  Expanded(
                    child: Slider(
                      value: freedom,
                      onChanged: onFreedomChanged,
                      min: 0,
                      max: 1,
                    ),
                  ),
                  Text(freedom.toStringAsFixed(2)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
