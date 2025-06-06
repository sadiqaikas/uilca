import 'package:flutter/material.dart';

class CanvasContainer extends StatelessWidget {
  final List<int> canvasIds;

  const CanvasContainer({Key? key, required this.canvasIds}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          children: canvasIds.map((id) {
            return Container(
              width: 250,
              height: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  'Canvas #$id',
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
