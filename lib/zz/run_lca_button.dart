import 'package:flutter/material.dart';

class RunLcaButton extends StatelessWidget {
  final VoidCallback onRun;

  const RunLcaButton({Key? key, required this.onRun}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onRun,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text(
            'Run LCA',
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}
