
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lca_models.dart';

/// Same list as before, kept public in lca_models.dart.
List<String> unitItemsWithValue(String? value) {
  final items = List<String>.from(kFlowUnits);
  if (value != null && !items.contains(value)) items.add(value);
  return items;
}

enum FlowAmountMode { number, parameter, formula }

String modeLabel(FlowAmountMode m) {
  switch (m) {
    case FlowAmountMode.number:
      return 'Number';
    case FlowAmountMode.parameter:
      return 'Parameter';
    case FlowAmountMode.formula:
      return 'Formula';
  }
}

class FlowAmountModeSelector extends StatelessWidget {
  final FlowAmountMode value;
  final ValueChanged<FlowAmountMode> onChanged;

  const FlowAmountModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<FlowAmountMode>(
      value: value,
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
      items: FlowAmountMode.values
          .map((m) => DropdownMenuItem(
                value: m,
                child: Text(modeLabel(m)),
              ))
          .toList(),
    );
  }
}

class FlowAmountEditor extends StatelessWidget {
  final FlowAmountMode mode;
  final TextEditingController numberCtrl;
  final TextEditingController formulaCtrl;
  final String? boundParam;
  final ValueChanged<String?> onBoundParam;
  final ValueChanged<String?> onError;
  final String unitLabel;
  final List<String> availableParams;
  final Map<String, double> symbols;

  const FlowAmountEditor({
    super.key,
    required this.mode,
    required this.numberCtrl,
    required this.formulaCtrl,
    required this.boundParam,
    required this.onBoundParam,
    required this.onError,
    required this.unitLabel,
    required this.availableParams,
    required this.symbols,
  });

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case FlowAmountMode.number:
        onError(null);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: numberCtrl,
              decoration: const InputDecoration(
                hintText: 'Amount',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => onError(null),
            ),
            _previewText('Enter a numeric value'),
          ],
        );

      case FlowAmountMode.parameter:
        return _buildParameterMode(context);

      case FlowAmountMode.formula:
        return _buildFormulaMode(context);
    }
  }

  Widget _buildParameterMode(BuildContext context) {
    // Make sure the dropdown can show the current value even if it is not in the provided list.
    final current = boundParam;
    final names = <String>[
      ...availableParams,
      if (current != null && current.trim().isNotEmpty && !availableParams.contains(current)) current,
    ];

    // Preview is best-effort only; missing symbol should NOT be an error.
    double? val;
    String? previewText;

    if (current != null && current.trim().isNotEmpty) {
      final key = current.trim().toLowerCase();
      if (symbols.containsKey(key)) {
        val = symbols[key]!;
        previewText = '= ${fmtAmount(val)} $unitLabel';
      } else {
        previewText = 'No preview available in this scope';
      }
      onError(null); // never block saving for a missing preview
    } else {
      previewText = 'Choose a parameter';
      onError(null); // important: do NOT mark as error when empty
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: current,
          items: names.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
          onChanged: onBoundParam,
          decoration: const InputDecoration(
            hintText: 'Select',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
        ),
        _previewText(previewText!, error: false),
      ],
    );
  }


  Widget _buildFormulaMode(BuildContext context) {
    String? err;
    double? val;
    final expr = formulaCtrl.text.trim();
    if (expr.isEmpty) {
      err = 'Enter a formula';
    } else {
      try {
        val = ParameterEngine().evaluateExpression(expr, symbols);
      } on ParameterEvaluationException catch (e) {
        err = e.message;
      } catch (e) {
        err = 'Unexpected error: $e';
      }
    }
    onError(err);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: formulaCtrl,
          decoration: InputDecoration(
            hintText: 'e.g. base_rate * efficiency',
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            suffixIcon: IconButton(
              tooltip: 'Insert parameter',
              icon: const Icon(Icons.playlist_add),
              onPressed: () async {
                final name = await showModalBottomSheet<String>(
                  context: context,
                  builder: (ctx) => PickParameterSheet(),
                );
                if (name != null && name.isNotEmpty) {
                  final t = formulaCtrl.text;
                  final sel = formulaCtrl.selection;
                  final before = t.substring(0, sel.start);
                  final after = t.substring(sel.end);
                  final next = '$before$name$after';
                  formulaCtrl.text = next;
                  final caret = before.length + name.length;
                  formulaCtrl.selection = TextSelection.collapsed(offset: caret);
                }
              },
            ),
          ),
          onChanged: (_) => onError(null),
        ),
        _previewText(err != null ? err : '= ${fmtAmount(val ?? 0)} $unitLabel', error: err != null),
      ],
    );
  }

  Widget _previewText(String text, {bool error = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: error ? Colors.red.shade700 : Colors.black54),
      ),
    );
  }
}

/// Simple sheet to pick or insert a parameter name.
class PickParameterSheet extends StatelessWidget {
  PickParameterSheet({super.key});

  final TextEditingController _filterCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<String?>(
          future: Clipboard.getData(Clipboard.kTextPlain).then((d) => d?.text),
          builder: (ctx, snap) {
            final raw = snap.data ?? '';
            final names = _extractNamesFromClipboard(raw);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Insert parameter name', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _filterCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Filter',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => (ctx as Element).markNeedsBuild(),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: names
                        .where((n) => n.toLowerCase().contains(_filterCtrl.text.trim().toLowerCase()))
                        .map((n) => ListTile(
                              title: Text(n),
                              onTap: () => Navigator.pop(context, n),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tip: copy a JSON that contains "global_parameters" or "process_parameters" to the clipboard to populate this list.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<String> _extractNamesFromClipboard(String raw) {
    try {
      final jsonObj = jsonDecode(raw);
      final out = <String>{};
      if (jsonObj is Map) {
        final g = jsonObj['global_parameters'];
        if (g is List) {
          for (final e in g) {
            if (e is Map && e['name'] is String) out.add((e['name'] as String).trim());
          }
        }
        final pp = jsonObj['process_parameters'];
        if (pp is Map) {
          for (final list in pp.values) {
            if (list is List) {
              for (final e in list) {
                if (e is Map && e['name'] is String) out.add((e['name'] as String).trim());
              }
            }
          }
        }
      }
      final res = out.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return res;
    } catch (_) {
      return const <String>[];
    }
  }
}
