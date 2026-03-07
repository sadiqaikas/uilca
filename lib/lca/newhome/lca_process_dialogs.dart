// File: lib/lca/lca_process_dialogs.dart
//
// Add and Edit dialogs for process nodes.
// - Inputs and outputs: Number | Parameter | Formula via FlowAmountEditor.
// - Emissions: numeric-only for performance.
// - Uses ParameterSet for previews and evaluation.
// - Preserves your biosphere search and selection UX.
//
// Depends on:
//   lca_models.dart        (FlowValue, ProcessNode, ParameterSet, ParameterEngine, fmtAmount, kFlowUnits)
//   lca_flow_fields.dart   (FlowAmountMode, FlowAmountModeSelector, FlowAmountEditor, unitItemsWithValue, PickParameterSheet)
//   biosphere_repo.dart / biosphere_flow.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';



import '../biosphere_flow.dart';
import '../biosphere_repo.dart';
import 'lca_models.dart';
import 'lca_flow_fields.dart';

/// ===== Add Process =====

class AddProcessDialog extends StatefulWidget {
  final Offset initialPosition;
  final ParameterSet? parameters; // global symbols used for previews

  const AddProcessDialog({
    super.key,
    required this.initialPosition,
    this.parameters,
  });

  @override
  State<AddProcessDialog> createState() => _AddProcessDialogState();
}

class _AddProcessDialogState extends State<AddProcessDialog> {
  final _nameCtrl = TextEditingController();

  // Inputs
  final _inputNameCtrls = <TextEditingController>[TextEditingController()];
  final _inputAmtCtrls = <TextEditingController>[TextEditingController()];
  final _inputUnitSelections = <String>[kFlowUnits[0]];
  final _inputModes = <FlowAmountMode>[FlowAmountMode.number];
  final _inputExprCtrls = <TextEditingController>[TextEditingController()];
  final _inputBoundParams = <String?>[null];
  final _inputErrors = <String?>[null];

  // Outputs
  final _outputNameCtrls = <TextEditingController>[TextEditingController()];
  final _outputAmtCtrls = <TextEditingController>[TextEditingController()];
  final _outputUnitSelections = <String>[kFlowUnits[0]];
  final _outputModes = <FlowAmountMode>[FlowAmountMode.number];
  final _outputExprCtrls = <TextEditingController>[TextEditingController()];
  final _outputBoundParams = <String?>[null];
  final _outputErrors = <String?>[null];

  // Manual emissions (numeric-only)
  final _emissionNameCtrls = <TextEditingController>[TextEditingController()];
  final _emissionAmtCtrlsManual = <TextEditingController>[TextEditingController()];
  final _emissionUnitSelectionsManual = <String>['kg'];

  void _addEmissionField() {
    setState(() {
      _emissionNameCtrls.add(TextEditingController());
      _emissionAmtCtrlsManual.add(TextEditingController());
      _emissionUnitSelectionsManual.add('kg');
    });
  }

  // Biosphere-selected emissions (numeric-only)
  final List<FlowValue> _selectedEmissions = [];
  final Map<String, TextEditingController> _selectedEmissionAmtCtrls = {};

  // Biosphere search
  List<BiosphereFlow>? _allFlows;
  String _searchTerm = '';
  bool _searching = false;
  final _searchCtrl = TextEditingController();

  ParameterEngine get _engine => ParameterEngine();

  Map<String, double> get _globalSymbols {
    final p = widget.parameters;
    if (p == null) return const {};
    return p.evaluateGlobalSymbolsLenient();
  }

  List<String> get _globalParamNames {
    final p = widget.parameters;
    if (p == null) return const [];
    final names = p.global.map((e) => e.name).where((n) => n.trim().isNotEmpty).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  @override
  void initState() {
    super.initState();
    BiosphereRepository.instance.load().then((list) {
      if (!mounted) return;
      setState(() => _allFlows = list);
    }).catchError((e, st) {
      debugPrint('[Error] loading biosphere flows: $e\n$st');
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();

    for (final c in _inputNameCtrls) c.dispose();
    for (final c in _inputAmtCtrls) c.dispose();
    for (final c in _inputExprCtrls) c.dispose();

    for (final c in _outputNameCtrls) c.dispose();
    for (final c in _outputAmtCtrls) c.dispose();
    for (final c in _outputExprCtrls) c.dispose();

    for (final c in _emissionNameCtrls) c.dispose();
    for (final c in _emissionAmtCtrlsManual) c.dispose();

    for (final c in _selectedEmissionAmtCtrls.values) c.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _performSearch() {
    final term = _searchCtrl.text.trim().toLowerCase();
    if (term.isEmpty) return;
    setState(() {
      _searchTerm = term;
      _searching = true;
    });
  }

  List<BiosphereFlow> get _filteredFlows {
    if (_allFlows == null || !_searching) return [];
    return _allFlows!
        .where((f) =>
            f.name.toLowerCase().contains(_searchTerm) ||
            f.categories.any((c) => c.toLowerCase().contains(_searchTerm)))
        .take(50)
        .toList();
  }

  void _addEmissionFromFlow(BiosphereFlow flow) {
    if (_selectedEmissions.any((e) => e.flowUuid == flow.id)) return;
    setState(() {
      final fv = FlowValue(name: flow.name, amount: 0.0, unit: flow.unit, flowUuid: flow.id);
      _selectedEmissions.add(fv);
      _selectedEmissionAmtCtrls[flow.id] = TextEditingController(text: '0');
    });
  }

  void _removeSelectedEmission(FlowValue fv) {
    setState(() {
      _selectedEmissions.remove(fv);
      _selectedEmissionAmtCtrls.remove(fv.flowUuid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final symbols = _globalSymbols;
    final paramNames = _globalParamNames;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(50.0),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Name
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Process name'),
              ),

              const SizedBox(height: 16),
              // Inputs
              Row(children: [
                const Text('Inputs', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _inputNameCtrls.add(TextEditingController());
                      _inputAmtCtrls.add(TextEditingController());
                      _inputUnitSelections.add(kFlowUnits[0]);
                      _inputModes.add(FlowAmountMode.number);
                      _inputExprCtrls.add(TextEditingController());
                      _inputBoundParams.add(null);
                      _inputErrors.add(null);
                    });
                  },
                  icon: const Icon(Icons.add_circle_outline, color: Colors.teal),
                ),
              ]),
              ...List.generate(_inputNameCtrls.length, (i) {
                final unit = _inputUnitSelections[i];
                final items = unitItemsWithValue(unit);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _inputNameCtrls[i],
                        decoration: const InputDecoration(
                          hintText: 'Input name',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: FlowAmountModeSelector(
                              value: _inputModes[i],
                              onChanged: (m) => setState(() {
                                _inputModes[i] = m;
                                _inputErrors[i] = null;
                              }),
                            ),
                          ),
                          FlowAmountEditor(
                            mode: _inputModes[i],
                            numberCtrl: _inputAmtCtrls[i],
                            formulaCtrl: _inputExprCtrls[i],
                            boundParam: _inputBoundParams[i],
                            onBoundParam: (v) => setState(() => _inputBoundParams[i] = v),
                            onError: (e) => _inputErrors[i] = e,
                            unitLabel: unit,
                            availableParams: paramNames,
                            symbols: symbols,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: DropdownButton<String>(
                        value: unit,
                        items: items.map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 12)))).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _inputUnitSelections[i] = val);
                        },
                        underline: const SizedBox.shrink(),
                        isDense: true,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Remove',
                      onPressed: () {
                        setState(() {
                          _inputNameCtrls.removeAt(i);
                          _inputAmtCtrls.removeAt(i);
                          _inputUnitSelections.removeAt(i);
                          _inputModes.removeAt(i);
                          _inputExprCtrls.removeAt(i);
                          _inputBoundParams.removeAt(i);
                          _inputErrors.removeAt(i);
                        });
                      },
                    ),
                  ]),
                );
              }),

              const SizedBox(height: 16),
              // Outputs
              Row(children: [
                const Text('Outputs', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _outputNameCtrls.add(TextEditingController());
                      _outputAmtCtrls.add(TextEditingController());
                      _outputUnitSelections.add(kFlowUnits[0]);
                      _outputModes.add(FlowAmountMode.number);
                      _outputExprCtrls.add(TextEditingController());
                      _outputBoundParams.add(null);
                      _outputErrors.add(null);
                    });
                  },
                  icon: const Icon(Icons.add_circle_outline, color: Colors.teal),
                ),
              ]),
              ...List.generate(_outputNameCtrls.length, (i) {
                final unit = _outputUnitSelections[i];
                final items = unitItemsWithValue(unit);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _outputNameCtrls[i],
                        decoration: const InputDecoration(
                          hintText: 'Output name',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: FlowAmountModeSelector(
                              value: _outputModes[i],
                              onChanged: (m) => setState(() {
                                _outputModes[i] = m;
                                _outputErrors[i] = null;
                              }),
                            ),
                          ),
                          FlowAmountEditor(
                            mode: _outputModes[i],
                            numberCtrl: _outputAmtCtrls[i],
                            formulaCtrl: _outputExprCtrls[i],
                            boundParam: _outputBoundParams[i],
                            onBoundParam: (v) => setState(() => _outputBoundParams[i] = v),
                            onError: (e) => _outputErrors[i] = e,
                            unitLabel: unit,
                            availableParams: paramNames,
                            symbols: symbols,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: DropdownButton<String>(
                        value: unit,
                        items: items.map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 12)))).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _outputUnitSelections[i] = val);
                        },
                        underline: const SizedBox.shrink(),
                        isDense: true,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Remove',
                      onPressed: () {
                        setState(() {
                          _outputNameCtrls.removeAt(i);
                          _outputAmtCtrls.removeAt(i);
                          _outputUnitSelections.removeAt(i);
                          _outputModes.removeAt(i);
                          _outputExprCtrls.removeAt(i);
                          _outputBoundParams.removeAt(i);
                          _outputErrors.removeAt(i);
                        });
                      },
                    ),
                  ]),
                );
              }),

              const SizedBox(height: 16),
              // Emissions header + manual add
              Row(children: [
                const Text('Emissions', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Colors.teal),
                  tooltip: 'Add emission field',
                  onPressed: _addEmissionField,
                ),
              ]),

              // Manual emission fields (numeric-only)
              ...List.generate(_emissionNameCtrls.length, (i) {
                final value = _emissionUnitSelectionsManual[i];
                final items = unitItemsWithValue(value);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 5,
                      child: TextField(
                        controller: _emissionNameCtrls[i],
                        decoration: const InputDecoration(
                          hintText: 'Emission name',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _emissionAmtCtrlsManual[i],
                        decoration: const InputDecoration(
                          hintText: 'Amount',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: DropdownButton<String>(
                        value: value,
                        items: items.map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 12)))).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _emissionUnitSelectionsManual[i] = val);
                        },
                        underline: const SizedBox.shrink(),
                        isDense: true,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Remove',
                      onPressed: () {
                        setState(() {
                          _emissionNameCtrls.removeAt(i);
                          _emissionAmtCtrlsManual.removeAt(i);
                          _emissionUnitSelectionsManual.removeAt(i);
                        });
                      },
                    ),
                  ]),
                );
              }),

              const SizedBox(height: 12),
              // Biosphere search
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Enter term to search biosphere flows',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    ),
                    onSubmitted: (_) => _performSearch(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.teal),
                  tooltip: 'Search',
                  onPressed: _performSearch,
                ),
              ]),

              if (_searching && _allFlows == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: const [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('Loading biosphere list…'),
                    ],
                  ),
                ),

              if (_allFlows != null && _filteredFlows.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ListView.builder(
                    itemCount: _filteredFlows.length,
                    itemBuilder: (_, i) {
                      final f = _filteredFlows[i];
                      final cat = f.categories.join(' / ');
                      return ListTile(
                        dense: true,
                        title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('[${f.unit}] ($cat)', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: Colors.teal),
                          onPressed: () => _addEmissionFromFlow(f),
                        ),
                      );
                    },
                  ),
                )
              else if (_allFlows != null && _searching)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('No biosphere flows found for that term.'),
                ),

              // Selected biosphere emissions (numeric-only)
              const SizedBox(height: 8),
              ..._selectedEmissions.map((e) {
                final key = e.flowUuid!;
                final unit = e.unit;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 5, child: Tooltip(message: key, child: Text(e.name, overflow: TextOverflow.ellipsis))),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _selectedEmissionAmtCtrls[key]!,
                        decoration: const InputDecoration(
                          hintText: 'Amount',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(unit, style: const TextStyle(fontSize: 13)),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Remove',
                      onPressed: () => _removeSelectedEmission(e),
                    ),
                  ]),
                );
              }),

              Row(children: [
                TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
                ElevatedButton(
                  child: const Text('Add'),
                  onPressed: _onAddPressed,
                ),
              ])
            ]),
          ),
        ),
      ),
    );
  }

  void _onAddPressed() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    // Only check input/output errors
    final hasErrors = [
      ..._inputErrors,
      ..._outputErrors,
    ].any((e) => e != null);

    if (hasErrors) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix invalid flow entries before adding.')),
      );
      return;
    }

    final symbols = _globalSymbols;
    final engine = _engine;

    // Inputs
    final inputs = <FlowValue>[];
    for (var i = 0; i < _inputNameCtrls.length; i++) {
      final n = _inputNameCtrls[i].text.trim();
      final u = _inputUnitSelections[i];
      if (n.isEmpty) continue;

      final mode = _inputModes[i];
      String? expr;
      String? param;
      double amount = 0;

      switch (mode) {
        case FlowAmountMode.number:
          amount = double.tryParse(_inputAmtCtrls[i].text.trim()) ?? 0.0;
          break;
        case FlowAmountMode.parameter:
          param = _inputBoundParams[i];
          expr = param;
          amount = param != null && symbols.containsKey(param.toLowerCase()) ? symbols[param.toLowerCase()]! : 0.0;
          break;
        case FlowAmountMode.formula:
          expr = _inputExprCtrls[i].text.trim();
          amount = expr.isNotEmpty ? engine.evaluateExpression(expr, symbols) : 0.0;
          break;
      }

      inputs.add(FlowValue(name: n, amount: amount, unit: u, amountExpr: expr, boundParam: param));
    }

    // Outputs
    final outputs = <FlowValue>[];
    for (var i = 0; i < _outputNameCtrls.length; i++) {
      final n = _outputNameCtrls[i].text.trim();
      final u = _outputUnitSelections[i];
      if (n.isEmpty) continue;

      final mode = _outputModes[i];
      String? expr;
      String? param;
      double amount = 0;

      switch (mode) {
        case FlowAmountMode.number:
          amount = double.tryParse(_outputAmtCtrls[i].text.trim()) ?? 0.0;
          break;
        case FlowAmountMode.parameter:
          param = _outputBoundParams[i];
          expr = param;
          amount = param != null && symbols.containsKey(param.toLowerCase()) ? symbols[param.toLowerCase()]! : 0.0;
          break;
        case FlowAmountMode.formula:
          expr = _outputExprCtrls[i].text.trim();
          amount = expr.isNotEmpty ? engine.evaluateExpression(expr, symbols) : 0.0;
          break;
      }

      outputs.add(FlowValue(name: n, amount: amount, unit: u, amountExpr: expr, boundParam: param));
    }

    // Manual emissions (numeric-only)
    final manualEm = <FlowValue>[];
    for (var i = 0; i < _emissionNameCtrls.length; i++) {
      final n = _emissionNameCtrls[i].text.trim();
      final u = _emissionUnitSelectionsManual[i];
      if (n.isEmpty) continue;
      final amount = double.tryParse(_emissionAmtCtrlsManual[i].text.trim()) ?? 0.0;
      manualEm.add(FlowValue(name: n, amount: amount, unit: u));
    }

    // Biosphere emissions (numeric-only)
    final selectedEm = _selectedEmissions.map((e) {
      final key = e.flowUuid!;
      final amount = double.tryParse(_selectedEmissionAmtCtrls[key]!.text.trim()) ?? 0.0;
      return e.copyWith(amount: amount, amountExpr: null, boundParam: null);
    }).toList();

    final node = ProcessNode(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      inputs: inputs,
      outputs: outputs,
      emissions: [...manualEm, ...selectedEm],
      position: widget.initialPosition,
    );

    Navigator.pop(context, node);
  }
}

/// ===== Edit Process =====

class EditProcessDialog extends StatefulWidget {
  final ProcessNode original;
  final ParameterSet? parameters; // global + per-process for previews

  const EditProcessDialog({
    super.key,
    required this.original,
    this.parameters,
  });

  @override
  State<EditProcessDialog> createState() => _EditProcessDialogState();
}

class _EditProcessDialogState extends State<EditProcessDialog> {
  late final TextEditingController _nameCtrl;

  // Inputs
  late final List<TextEditingController> _inputNameCtrls;
  late final List<TextEditingController> _inputAmtCtrls;
  late final List<String> _inputUnitSelections;
  late final List<FlowAmountMode> _inputModes;
  late final List<TextEditingController> _inputExprCtrls;
  late final List<String?> _inputBoundParams;
  late final List<String?> _inputErrors;

  // Outputs
  late final List<TextEditingController> _outputNameCtrls;
  late final List<TextEditingController> _outputAmtCtrls;
  late final List<String> _outputUnitSelections;
  late final List<FlowAmountMode> _outputModes;
  late final List<TextEditingController> _outputExprCtrls;
  late final List<String?> _outputBoundParams;
  late final List<String?> _outputErrors;

  // Manual emissions (numeric-only)
  late final List<TextEditingController> _emissionNameCtrls;
  late final List<TextEditingController> _emissionAmtCtrlsManual;
  late final List<String> _emissionUnitSelectionsManual;

  // Biosphere emissions (numeric-only)
  late List<FlowValue> _selectedEmissions;
  final Map<String, TextEditingController> _selectedEmissionAmtCtrls = {};

  // Multiplier
  final TextEditingController _multiplierCtrl = TextEditingController(text: '1');

  // Biosphere search
  List<BiosphereFlow>? _allFlows;
  String _searchTerm = '';
  bool _searching = false;
  final _searchCtrl = TextEditingController();

  ParameterEngine get _engine => ParameterEngine();

  Map<String, double> get _symbolsForThisProcess {
    final fromEmbedded = widget.original.parameters.isEmpty
        ? const <String, double>{}
        : ParameterSet(
            perProcess: {widget.original.id: widget.original.parameters},
          ).evaluateSymbolsForProcessLenient(widget.original.id);

    final ps = widget.parameters;
    if (ps == null) return fromEmbedded;

    final fromSet = ps.evaluateSymbolsForProcessLenient(widget.original.id);
    return {
      ...fromSet,
      ...fromEmbedded,
    };
  }

  List<String> get _paramNamesForThisProcess {
    final ps = widget.parameters;
    final g = ps?.global.map((e) => e.name) ?? const Iterable<String>.empty();
    final local = ps?.processParamsFor(widget.original.id).map((e) => e.name) ??
        const Iterable<String>.empty();
    final embedded = widget.original.parameters.map((e) => e.name);

    final set = {...g, ...local, ...embedded}.where((n) => n.trim().isNotEmpty).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return set;
  }

  @override
  void initState() {
    super.initState();
    final o = widget.original;
    _nameCtrl = TextEditingController(text: o.name);

    // Inputs
    _inputNameCtrls = o.inputs.map((f) => TextEditingController(text: f.name)).toList();
    _inputAmtCtrls = o.inputs.map((f) => TextEditingController(text: f.amount.toString())).toList();
    _inputUnitSelections = o.inputs.map((f) => f.unit).toList();
    _inputModes = o.inputs
        .map((f) => f.amountExpr != null || f.boundParam != null
            ? (f.boundParam != null && (f.amountExpr == null || f.amountExpr == f.boundParam)
                ? FlowAmountMode.parameter
                : FlowAmountMode.formula)
            : FlowAmountMode.number)
        .toList();
    _inputExprCtrls = o.inputs.map((f) => TextEditingController(text: f.amountExpr ?? '')).toList();
    _inputBoundParams = o.inputs.map((f) => f.boundParam).toList();
_inputErrors  = List<String?>.filled(_inputNameCtrls.length, null, growable: true);

    if (_inputNameCtrls.isEmpty) {
      _inputNameCtrls.add(TextEditingController());
      _inputAmtCtrls.add(TextEditingController());
      _inputUnitSelections.add(kFlowUnits[0]);
      _inputModes.add(FlowAmountMode.number);
      _inputExprCtrls.add(TextEditingController());
      _inputBoundParams.add(null);
      _inputErrors.add(null);
    }

    // Outputs
    _outputNameCtrls = o.outputs.map((f) => TextEditingController(text: f.name)).toList();
    _outputAmtCtrls = o.outputs.map((f) => TextEditingController(text: f.amount.toString())).toList();
    _outputUnitSelections = o.outputs.map((f) => f.unit).toList();
    _outputModes = o.outputs
        .map((f) => f.amountExpr != null || f.boundParam != null
            ? (f.boundParam != null && (f.amountExpr == null || f.amountExpr == f.boundParam)
                ? FlowAmountMode.parameter
                : FlowAmountMode.formula)
            : FlowAmountMode.number)
        .toList();
    _outputExprCtrls = o.outputs.map((f) => TextEditingController(text: f.amountExpr ?? '')).toList();
    _outputBoundParams = o.outputs.map((f) => f.boundParam).toList();
_outputErrors = List<String?>.filled(_outputNameCtrls.length, null, growable: true);

    if (_outputNameCtrls.isEmpty) {
      _outputNameCtrls.add(TextEditingController());
      _outputAmtCtrls.add(TextEditingController());
      _outputUnitSelections.add(kFlowUnits[0]);
      _outputModes.add(FlowAmountMode.number);
      _outputExprCtrls.add(TextEditingController());
      _outputBoundParams.add(null);
      _outputErrors.add(null);
    }

    // Manual emissions (numeric-only)
    final manualEm = o.emissions.where((e) => e.flowUuid == null).toList();
    _emissionNameCtrls = manualEm.map((f) => TextEditingController(text: f.name)).toList();
    _emissionAmtCtrlsManual = manualEm.map((f) => TextEditingController(text: f.amount.toString())).toList();
    _emissionUnitSelectionsManual = manualEm.map((f) => f.unit).toList();

    if (_emissionNameCtrls.isEmpty) {
      _emissionNameCtrls.add(TextEditingController());
      _emissionAmtCtrlsManual.add(TextEditingController());
      _emissionUnitSelectionsManual.add('kg');
    }

    // Biosphere emissions (numeric-only)
    final sel = o.emissions.where((e) => e.flowUuid != null).toList();
    _selectedEmissions = sel;
    for (final e in sel) {
      final id = e.flowUuid!;
      _selectedEmissionAmtCtrls[id] = TextEditingController(text: e.amount.toString());
    }

    // // Load flows
    // BiosphereRepository.instance.load().then((list) {
    //   if (!mounted) return;
    //   setState(() => _allFlows = list);
    // }).catchError((e, st) {
    //   debugPrint('[Error] EditProcessDialog: failed to load flows: $e');
    // });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();

    for (final c in _inputNameCtrls) c.dispose();
    for (final c in _inputAmtCtrls) c.dispose();
    for (final c in _inputExprCtrls) c.dispose();

    for (final c in _outputNameCtrls) c.dispose();
    for (final c in _outputAmtCtrls) c.dispose();
    for (final c in _outputExprCtrls) c.dispose();

    for (final c in _emissionNameCtrls) c.dispose();
    for (final c in _emissionAmtCtrlsManual) c.dispose();

    for (final c in _selectedEmissionAmtCtrls.values) c.dispose();

    _searchCtrl.dispose();
    _multiplierCtrl.dispose();
    super.dispose();
  }

  void _performSearch() {
    final term = _searchCtrl.text.trim().toLowerCase();
    if (term.isEmpty) return;
    setState(() {
      _searchTerm = term;
      _searching = true;
    });
  }

  List<BiosphereFlow> get _filteredFlows {
    if (_allFlows == null || !_searching) return [];
    return _allFlows!
        .where((f) =>
            f.name.toLowerCase().contains(_searchTerm) ||
            f.categories.any((c) => c.toLowerCase().contains(_searchTerm)))
        .take(50)
        .toList();
  }

  void _addEmissionFromFlow(BiosphereFlow flow) {
    if (_selectedEmissions.any((e) => e.flowUuid == flow.id)) return;
    setState(() {
      final fv = FlowValue(name: flow.name, amount: 0.0, unit: flow.unit, flowUuid: flow.id);
      _selectedEmissions.add(fv);
      _selectedEmissionAmtCtrls[flow.id] = TextEditingController(text: '0');
    });
  }

  @override
  Widget build(BuildContext context) {
    final symbols = _symbolsForThisProcess;
    final paramNames = _paramNamesForThisProcess;

    return AlertDialog(
      title: const Text('Edit process node'),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Process name')),

          const SizedBox(height: 12),
          TextField(
            controller: _multiplierCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Multiplier',
              helperText: 'Scale all amounts on save',
            ),
          ),

          const SizedBox(height: 16),
          // Inputs
          Row(children: [
            const Text('Inputs', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.teal),
              tooltip: 'Add input',
              onPressed: () {
                setState(() {
                  _inputNameCtrls.add(TextEditingController());
                  _inputAmtCtrls.add(TextEditingController());
                  _inputUnitSelections.add(kFlowUnits[0]);
                  _inputModes.add(FlowAmountMode.number);
                  _inputExprCtrls.add(TextEditingController());
                  _inputBoundParams.add(null);
                  _inputErrors.add(null);
                });
              },
            ),
          ]),
          ...List.generate(_inputNameCtrls.length, (i) {
            final unit = _inputUnitSelections[i];
            final items = unitItemsWithValue(unit);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _inputNameCtrls[i],
                    decoration: const InputDecoration(
                      hintText: 'Input name',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: FlowAmountModeSelector(
                          value: _inputModes[i],
                          onChanged: (m) => setState(() {
                            _inputModes[i] = m;
                            _inputErrors[i] = null;
                          }),
                        ),
                      ),
                      FlowAmountEditor(
                        mode: _inputModes[i],
                        numberCtrl: _inputAmtCtrls[i],
                        formulaCtrl: _inputExprCtrls[i],
                        boundParam: _inputBoundParams[i],
                        onBoundParam: (v) => setState(() => _inputBoundParams[i] = v),
                        onError: (e) => _inputErrors[i] = e,
                        unitLabel: unit,
                        availableParams: paramNames,
                        symbols: symbols,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButton<String>(
                    value: unit,
                    items: items.map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 12)))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _inputUnitSelections[i] = val);
                    },
                    underline: const SizedBox.shrink(),
                    isDense: true,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Remove',
                  onPressed: () {
                    setState(() {
                      _inputNameCtrls.removeAt(i);
                      _inputAmtCtrls.removeAt(i);
                      _inputUnitSelections.removeAt(i);
                      _inputModes.removeAt(i);
                      _inputExprCtrls.removeAt(i);
                      _inputBoundParams.removeAt(i);
                      _inputErrors.removeAt(i);
                    });
                  },
                ),
              ]),
            );
          }),

          const SizedBox(height: 16),
          // Outputs
          Row(children: [
            const Text('Outputs', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.teal),
              tooltip: 'Add output',
              onPressed: () {
                setState(() {
                  _outputNameCtrls.add(TextEditingController());
                  _outputAmtCtrls.add(TextEditingController());
                  _outputUnitSelections.add(kFlowUnits[0]);
                  _outputModes.add(FlowAmountMode.number);
                  _outputExprCtrls.add(TextEditingController());
                  _outputBoundParams.add(null);
                  _outputErrors.add(null);
                });
              },
            ),
          ]),
          ...List.generate(_outputNameCtrls.length, (i) {
            final unit = _outputUnitSelections[i];
            final items = unitItemsWithValue(unit);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _outputNameCtrls[i],
                    decoration: const InputDecoration(
                      hintText: 'Output name',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: FlowAmountModeSelector(
                          value: _outputModes[i],
                          onChanged: (m) => setState(() {
                            _outputModes[i] = m;
                            _outputErrors[i] = null;
                          }),
                        ),
                      ),
                      FlowAmountEditor(
                        mode: _outputModes[i],
                        numberCtrl: _outputAmtCtrls[i],
                        formulaCtrl: _outputExprCtrls[i],
                        boundParam: _outputBoundParams[i],
                        onBoundParam: (v) => setState(() => _outputBoundParams[i] = v),
                        onError: (e) => _outputErrors[i] = e,
                        unitLabel: unit,
                        availableParams: _paramNamesForThisProcess,
                        symbols: symbols,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButton<String>(
                    value: unit,
                    items: items.map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 12)))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _outputUnitSelections[i] = val);
                    },
                    underline: const SizedBox.shrink(),
                    isDense: true,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Remove',
                  onPressed: () {
                    setState(() {
                      _outputNameCtrls.removeAt(i);
                      _outputAmtCtrls.removeAt(i);
                      _outputUnitSelections.removeAt(i);
                      _outputModes.removeAt(i);
                      _outputExprCtrls.removeAt(i);
                      _outputBoundParams.removeAt(i);
                      _outputErrors.removeAt(i);
                    });
                  },
                ),
              ]),
            );
          }),

      
        ]),
      ),
      actions: [
        TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
        ElevatedButton(
          child: const Text('Save'),
          onPressed: _onSavePressed,
        ),
      ],
    );
  }

  void _onSavePressed() {
    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty) return;

    final m = double.tryParse(_multiplierCtrl.text.trim()) ?? 1.0;

    final hasErrors = [
      ..._inputErrors,
      ..._outputErrors,
    ].any((e) => e != null);

    if (hasErrors) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix invalid flow entries before saving.')),
      );
      return;
    }

    final symbols = _symbolsForThisProcess;
    final engine = _engine;

    // Inputs
    final newInputs = <FlowValue>[];
    for (var i = 0; i < _inputNameCtrls.length; i++) {
      final n = _inputNameCtrls[i].text.trim();
      final u = _inputUnitSelections[i];
      if (n.isEmpty) continue;

      final mode = _inputModes[i];
      String? expr;
      String? param;
      double amount = 0;

      switch (mode) {
        case FlowAmountMode.number:
          amount = double.tryParse(_inputAmtCtrls[i].text.trim()) ?? 0.0;
          break;
        case FlowAmountMode.parameter:
          param = _inputBoundParams[i];
          expr = param;
          amount = param != null && symbols.containsKey(param.toLowerCase()) ? symbols[param.toLowerCase()]! : 0.0;
          break;
        case FlowAmountMode.formula:
          expr = _inputExprCtrls[i].text.trim();
          amount = expr.isNotEmpty ? engine.evaluateExpression(expr, symbols) : 0.0;
          break;
      }

      newInputs.add(FlowValue(name: n, amount: amount * m, unit: u, amountExpr: expr, boundParam: param));
    }

    // Outputs
    final newOutputs = <FlowValue>[];
    for (var i = 0; i < _outputNameCtrls.length; i++) {
      final n = _outputNameCtrls[i].text.trim();
      final u = _outputUnitSelections[i];
      if (n.isEmpty) continue;

      final mode = _outputModes[i];
      String? expr;
      String? param;
      double amount = 0;

      switch (mode) {
        case FlowAmountMode.number:
          amount = double.tryParse(_outputAmtCtrls[i].text.trim()) ?? 0.0;
          break;
        case FlowAmountMode.parameter:
          param = _outputBoundParams[i];
          expr = param;
          amount = param != null && symbols.containsKey(param.toLowerCase()) ? symbols[param.toLowerCase()]! : 0.0;
          break;
        case FlowAmountMode.formula:
          expr = _outputExprCtrls[i].text.trim();
          amount = expr.isNotEmpty ? engine.evaluateExpression(expr, symbols) : 0.0;
          break;
      }

      newOutputs.add(FlowValue(name: n, amount: amount * m, unit: u, amountExpr: expr, boundParam: param));
    }

    // // Manual emissions (numeric-only)
    // final manualEm = <FlowValue>[];
    // for (var i = 0; i < _emissionNameCtrls.length; i++) {
    //   final n = _emissionNameCtrls[i].text.trim();
    //   final u = _emissionUnitSelectionsManual[i];
    //   if (n.isEmpty) continue;
    //   final amount = double.tryParse(_emissionAmtCtrlsManual[i].text.trim()) ?? 0.0;
    //   manualEm.add(FlowValue(name: n, amount: amount * m, unit: u));
    // }

    // // Biosphere emissions (numeric-only)
    // final selectedEm = _selectedEmissions.map((e) {
    //   final key = e.flowUuid!;
    //   final amount = double.tryParse(_selectedEmissionAmtCtrls[key]!.text.trim()) ?? 0.0;
    //   return e.copyWith(amount: amount * m, amountExpr: null, boundParam: null);
    // }).toList();

    // final updatedNode = widget.original.copyWithFields(
    //   name: newName,
    //   inputs: newInputs,
    //   outputs: newOutputs,
    //   emissions: [...manualEm, ...selectedEm],
    // );
// Keep existing emissions, scaled by multiplier for consistency
final keptEmissions = widget.original.emissions
    .map((e) => e.copyWith(amount: e.amount * m))
    .toList();

final updatedNode = widget.original.copyWithFields(
  name: newName,
  inputs: newInputs,
  outputs: newOutputs,
  emissions: keptEmissions,
);

    Navigator.pop(context, updatedNode);
  }
}
