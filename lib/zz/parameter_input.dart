import 'package:flutter/material.dart';

class ParameterInput extends StatelessWidget {
  final TextEditingController controller;

  const ParameterInput({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: 'Enter your parameters or prompt',
          border: OutlineInputBorder(),
        ),
      ),
    );
  }
}
