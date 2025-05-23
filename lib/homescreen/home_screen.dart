import 'package:flutter/material.dart';
import 'lca_textfield.dart';
import 'tips.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.title});

  final String title;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _textController = TextEditingController();

  // More natural and engaging example
  void _fillExampleText() {
_textController.text =
    'Perform an LCA for producing 1 liter of bottled water.\n\n'
    'Start from the beginning:\n'
    '- PET resin is produced (0.06 kg), releasing about 0.02 kg of CO₂.\n'
    '- That resin is used in bottle molding to make one plastic bottle, which emits 0.5 kg of CO₂.\n'
    '- Finally, the bottle is labeled and finished, adding another 0.1 kg of CO₂.\n\n'
    'The materials move like this:\n'
    '- PET resin goes to bottle molding (0.06 kg)\n'
    '- The molded bottle goes to labeling (1 unit)\n\n'
    'Let’s assume we want the environmental impact for one labeled bottle — that’s our functional unit.\n\n'
    'Can you calculate the total impact?';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Colors.green.shade50],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            // LCA Input area
            Expanded(
              flex: 2,
              child: LCATextField(textController: _textController),
            ),
            // Tips and Example section
            Expanded(
              flex: 1,
              child: TipsSection(onFillExample: _fillExampleText),
            ),
          ],
        ),
      ),
    );
  }
}
