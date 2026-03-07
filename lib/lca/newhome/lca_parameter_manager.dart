// File: lib/lca/newhome/lca_parameter_manager.dart
//
// Parameter manager with two scopes:
//   • Global parameters
//   • Per-process parameters
//
// Works with your Parameter model:
//   name, value?: double, formula?: String, scope, unit?, note?
//
// Behaviour:
//   • The UI edits a single text field per parameter. If it parses as a number
//     we store to `value` and clear `formula`. Otherwise we store to `formula`
//     and clear `value`.
//   • Live preview uses `formula ?? value.toString()` for evaluation.
//   • Global rows are saved with scope=global, per-process rows with scope=process.

import 'package:flutter/material.dart';

import 'lca_models.dart';
import 'lca_flow_fields.dart'; // PickParameterSheet

typedef ParameterEntry = Parameter;

extension _ParameterCopyX on Parameter {
  Parameter copy({
    String? name,
    double? value,
    String? formula,
    ParameterScope? scope,
    String? unit,
    String? note,
  }) {
    return Parameter(
      name: name ?? this.name,
      value: value,
      formula: formula,
      scope: scope ?? this.scope,
      unit: unit ?? this.unit,
      note: note ?? this.note,
    );
  }
}

class ParameterManagerDialog extends StatefulWidget {
  final ParameterSet initial;
  final List<ProcessNode> processes;

  const ParameterManagerDialog({
    super.key,
    required this.initial,
    required this.processes,
  });

  @override
  State<ParameterManagerDialog> createState() => _ParameterManagerDialogState();
}

class _ParameterManagerDialogState extends State<ParameterManagerDialog> {
  // Working copies
  late List<ParameterEntry> _global;
  late Map<String, List<ParameterEntry>> _perProcess;

  // UI state
  late String _selectedProcessId;
  int _tabIndex = 0;

  // Evaluation state
  final _engine = ParameterEngine();
  String? _evalErrorGlobal;
  String? _evalErrorLocal;
  static final RegExp _identifierRe = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');
  static const Set<String> _formulaFnNames = {
    'min',
    'max',
    'abs',
    'round',
    'ceil',
    'floor',
  };

  @override
  void initState() {
    super.initState();

    // Deep-ish copies into working sets
    _global = widget.initial.global
        .map((e) => e.copy(
              name: e.name,
              value: e.value,
              formula: e.formula,
              scope: ParameterScope.global,
              unit: e.unit,
              note: e.note,
            ))
        .toList();

    _perProcess = {
      for (final kv in widget.initial.perProcess.entries)
        kv.key: kv.value
            .map((e) => e.copy(
                  name: e.name,
                  value: e.value,
                  formula: e.formula,
                  scope: ParameterScope.process,
                  unit: e.unit,
                  note: e.note,
                ))
            .toList(),
    };

    // Canonicalise process ids (case-insensitive) to ids that exist on the canvas.
    final idsByLower = <String, String>{
      for (final p in widget.processes) p.id.trim().toLowerCase(): p.id,
    };
    final remap = <String, String>{};
    for (final pid in _perProcess.keys.toList()) {
      final canonical = idsByLower[pid.trim().toLowerCase()];
      if (canonical != null && canonical != pid) {
        remap[pid] = canonical;
      }
    }
    for (final entry in remap.entries) {
      final from = entry.key;
      final to = entry.value;
      final moved = _perProcess.remove(from) ?? const <ParameterEntry>[];
      final existing = _perProcess[to] ?? const <ParameterEntry>[];
      _perProcess[to] = [...existing, ...moved];
    }

    // Merge embedded process parameters so imported models always appear here.
    final globalNames = <String>{
      for (final p in _global) p.name.trim().toLowerCase(),
    };
    for (final process in widget.processes) {
      final local = _perProcess.putIfAbsent(process.id, () => <ParameterEntry>[]);
      final names = <String>{
        for (final p in local) p.name.trim().toLowerCase(),
      };

      // 1) Embedded process parameters.
      for (final p in process.parameters) {
        final name = p.name.trim();
        if (name.isEmpty) continue;
        final key = name.toLowerCase();
        if (globalNames.contains(key) || names.contains(key)) continue;
        local.add(
          p.copy(
            name: name,
            value: p.value,
            formula: p.formula,
            scope: ParameterScope.process,
            unit: p.unit,
            note: p.note,
          ),
        );
        names.add(key);
      }

      // 2) Parameters implied by flow bindings / formulas.
      final flows = <FlowValue>[
        ...process.inputs,
        ...process.outputs,
        ...process.emissions,
      ];

      void ensureLocal(String rawName, double fallbackValue) {
        final name = rawName.trim();
        if (name.isEmpty) return;
        final key = name.toLowerCase();
        if (globalNames.contains(key) || names.contains(key)) return;
        local.add(
          Parameter(
            name: name,
            value: fallbackValue.isFinite ? fallbackValue : 1.0,
            scope: ParameterScope.process,
          ),
        );
        names.add(key);
      }

      for (final flow in flows) {
        final bound = (flow.boundParam ?? '').trim();
        if (bound.isNotEmpty) {
          ensureLocal(bound, flow.amount);
        }
        final expr = (flow.amountExpr ?? '').trim();
        if (expr.isEmpty) continue;
        final ids = _extractFormulaIdentifiers(expr);
        for (final id in ids) {
          final fallback = ids.length == 1 ? flow.amount : 1.0;
          ensureLocal(id, fallback);
        }
      }
    }

    _selectedProcessId = widget.processes.isNotEmpty ? widget.processes.first.id : '';

    _recomputeGlobal();
    _recomputeLocal();
  }

  Set<String> _extractFormulaIdentifiers(String expr) {
    final out = <String>{};
    for (final m in _identifierRe.allMatches(expr)) {
      final token = m.group(0);
      if (token == null) continue;
      final lower = token.toLowerCase();
      if (_formulaFnNames.contains(lower)) continue;
      out.add(token);
    }
    return out;
  }

  /// Evaluate globals for errors.
  void _recomputeGlobal() {
    try {
      _engine.evaluateParameterList(_global, allowedOuter: const {});
      _evalErrorGlobal = null;
    } on ParameterEvaluationException catch (e) {
      _evalErrorGlobal = e.message;
    } catch (e) {
      _evalErrorGlobal = 'Unexpected error: $e';
    }
    setState(() {});
  }

  /// Evaluate locals for the selected process for errors.
  void _recomputeLocal() {
    if (_selectedProcessId.isEmpty) {
      _evalErrorLocal = null;
      setState(() {});
      return;
    }
    final localList = List<ParameterEntry>.from(_perProcess[_selectedProcessId] ?? const <ParameterEntry>[]);
    try {
      final outer = _engine.evaluateParameterList(_global, allowedOuter: const {});
      _engine.evaluateParameterList(localList, allowedOuter: outer);
      _evalErrorLocal = null;
    } on ParameterEvaluationException catch (e) {
      _evalErrorLocal = e.message;
    } catch (e) {
      _evalErrorLocal = 'Unexpected error: $e';
    }
    setState(() {});
  }

  /// Build the final ParameterSet from cleaned working copies.
  ParameterSet _buildResult() {
    // Clean globals: trim names, convert text to value/formula already handled on edit
    final cleanedGlobal = _global
        .where((e) => e.name.trim().isNotEmpty)
        .map((e) => e.copy(
              name: e.name.trim(),
              value: e.value,
              formula: e.formula?.trim().isEmpty == true ? null : e.formula,
              scope: ParameterScope.global,
              unit: e.unit,
              note: e.note,
            ))
        .toList();

    // Clean locals
    final cleanedLocal = <String, List<ParameterEntry>>{};
    for (final pid in _perProcess.keys) {
      final list = (_perProcess[pid] ?? const <ParameterEntry>[])
          .where((e) => e.name.trim().isNotEmpty)
          .map((e) => e.copy(
                name: e.name.trim(),
                value: e.value,
                formula: e.formula?.trim().isEmpty == true ? null : e.formula,
                scope: ParameterScope.process,
                unit: e.unit,
                note: e.note,
              ))
          .toList();
      if (list.isNotEmpty) cleanedLocal[pid] = list;
    }

    return ParameterSet(global: cleanedGlobal, perProcess: cleanedLocal);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = const [Tab(text: 'Global'), Tab(text: 'Per process')];

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 900,
        height: 600,
        child: Column(
          children: [
            const SizedBox(height: 8),
            const Text('Parameter manager', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            DefaultTabController(
              length: tabs.length,
              initialIndex: _tabIndex,
              child: Expanded(
                child: Column(
                  children: [
                    TabBar(tabs: tabs, onTap: (i) => setState(() => _tabIndex = i)),
                    Expanded(
                      child: TabBarView(
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildGlobalTab(),
                          _buildPerProcessTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const Spacer(),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('Save'),
                    onPressed: () => Navigator.pop(context, _buildResult()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalTab() {
    return Column(
      children: [
        if (_evalErrorGlobal != null) _ErrorBanner(text: _evalErrorGlobal!),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add parameter'),
                onPressed: () => setState(() {
                  _global.add(ParameterEntry(
                    name: '',
                    value: 0, // default numeric
                    formula: null,
                    scope: ParameterScope.global,
                  ));
                  _recomputeGlobal();
                }),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Recompute'),
                onPressed: _recomputeGlobal,
              ),
              const Spacer(),
              _ParamHelpButton(),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _ParameterListEditor(
            entries: _global,
            onChanged: (idx, updated) {
              setState(() {
                _global[idx] = updated;
              });
              _recomputeGlobal();
            },
            onDelete: (idx) {
              setState(() {
                _global.removeAt(idx);
              });
              _recomputeGlobal();
            },
            outerNames: const [],
            evalPreview: (name, exprText) {
              try {
                final outer = _engine.evaluateParameterList(_global, allowedOuter: const {});
                final val = exprText.trim().isEmpty ? 0.0 : _engine.evaluateExpression(exprText, outer);
                return fmtAmount(val);
              } catch (_) {
                return '—';
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPerProcessTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              const Text('Process:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _selectedProcessId.isEmpty && widget.processes.isNotEmpty ? widget.processes.first.id : _selectedProcessId,
                items: widget.processes
                    .map((p) => DropdownMenuItem(
                          value: p.id,
                          child: SizedBox(width: 420, child: Text(p.name, overflow: TextOverflow.ellipsis)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _selectedProcessId = v);
                  _recomputeLocal();
                },
              ),
              const Spacer(),
              if (_evalErrorLocal != null) const SizedBox.shrink(),
            ],
          ),
        ),
        if (_evalErrorLocal != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _ErrorBanner(text: _evalErrorLocal!),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add parameter'),
                onPressed: _selectedProcessId.isEmpty
                    ? null
                    : () {
                        setState(() {
                          _perProcess.putIfAbsent(_selectedProcessId, () => <ParameterEntry>[]);
                          _perProcess[_selectedProcessId]!.add(ParameterEntry(
                            name: '',
                            value: 0,
                            formula: null,
                            scope: ParameterScope.process,
                          ));
                        });
                        _recomputeLocal();
                      },
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Recompute'),
                onPressed: _recomputeLocal,
              ),
              const Spacer(),
              _ParamHelpButton(),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _selectedProcessId.isEmpty
              ? const _EmptyHint(text: 'No processes available. Add a process first.')
              : _ParameterListEditor(
                  entries: _perProcess[_selectedProcessId] ?? const <ParameterEntry>[],
                  outerNames: _global.map((e) => e.name).toList(),
                  onChanged: (idx, updated) {
                    setState(() {
                      final list = _perProcess[_selectedProcessId];
                      if (list != null && idx >= 0 && idx < list.length) {
                        list[idx] = updated;
                      }
                    });
                    _recomputeLocal();
                  },
                  onDelete: (idx) {
                    setState(() {
                      final list = _perProcess[_selectedProcessId];
                      if (list != null && idx >= 0 && idx < list.length) {
                        list.removeAt(idx);
                      }
                    });
                    _recomputeLocal();
                  },
                  evalPreview: (name, exprText) {
                    try {
                      final outer = _engine.evaluateParameterList(_global, allowedOuter: const {});
                      final localList = _perProcess[_selectedProcessId] ?? const <ParameterEntry>[];
                      final localMap = _engine.evaluateParameterList(localList, allowedOuter: outer);
                      final val = exprText.trim().isEmpty ? 0.0 : _engine.evaluateExpression(exprText, {...outer, ...localMap});
                      return fmtAmount(val);
                    } catch (_) {
                      return '—';
                    }
                  },
                ),
        ),
      ],
    );
  }
}

/// Renders and edits a vertical list of parameters.
/// Edits as text. Converts to value/formula on change.
class _ParameterListEditor extends StatelessWidget {
  final List<ParameterEntry> entries;
  final List<String> outerNames;
  final void Function(int index, ParameterEntry updated) onChanged;
  final void Function(int index) onDelete;

  /// Passes the text interpretation to the preview function.
  final String Function(String name, String exprText) evalPreview;

  const _ParameterListEditor({
    required this.entries,
    required this.onChanged,
    required this.onDelete,
    required this.evalPreview,
    this.outerNames = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _EmptyHint(text: 'No parameters yet. Add one to get started.');
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final e = entries[i];
        // Build the editable text for this row from the model
        final exprText = e.formula ?? (e.value != null ? e.value!.toString() : '');
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _ParameterRow(
              index: i,
              entry: e,
              initialExprText: exprText,
              outerNames: outerNames,
              onChanged: (upd) => onChanged(i, upd),
              onDelete: () => onDelete(i),
              preview: evalPreview(e.name, exprText),
            ),
          ),
        );
      },
    );
  }
}

class _ParameterRow extends StatefulWidget {
  final int index;
  final ParameterEntry entry;
  final String initialExprText;
  final List<String> outerNames;
  final ValueChanged<ParameterEntry> onChanged;
  final VoidCallback onDelete;
  final String preview;

  const _ParameterRow({
    required this.index,
    required this.entry,
    required this.initialExprText,
    required this.outerNames,
    required this.onChanged,
    required this.onDelete,
    required this.preview,
  });

  @override
  State<_ParameterRow> createState() => _ParameterRowState();
}

class _ParameterRowState extends State<_ParameterRow> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _exprCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.entry.name);
    _exprCtrl = TextEditingController(text: widget.initialExprText);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _exprCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            // Name
            Expanded(
              flex: 2,
              child: TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. base_rate',
                  suffixIcon: IconButton(
                    tooltip: 'Insert name from list',
                    icon: const Icon(Icons.playlist_add),
                    onPressed: () async {
                      final picked = await showModalBottomSheet<String>(
                        context: context,
                        builder: (_) => PickParameterSheet(),
                      );
                      if (picked != null && picked.isNotEmpty) {
                        _nameCtrl.text = picked;
                        _notify();
                      }
                    },
                  ),
                ),
                onChanged: (_) => _notify(),
              ),
            ),
            const SizedBox(width: 8),
            // Expression text
            Expanded(
              flex: 3,
              child: TextField(
                controller: _exprCtrl,
                decoration: InputDecoration(
                  labelText: 'Expression',
                  hintText: 'number or formula, e.g. 1000 * efficiency',
                  suffixIcon: _outerNamesMenu(),
                ),
                onChanged: (_) => _notify(),
              ),
            ),
            const SizedBox(width: 8),
            // Preview
            SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Preview', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  Text(widget.preview, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Delete',
              onPressed: widget.onDelete,
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            )
          ],
        ),
      ],
    );
  }

  Widget _outerNamesMenu() {
    final names = widget.outerNames;
    if (names.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Insert outer parameter',
      icon: const Icon(Icons.link),
      onSelected: (n) {
        final t = _exprCtrl.text;
        final sel = _exprCtrl.selection;
        final before = t.substring(0, sel.start);
        final after = t.substring(sel.end);
        final next = '$before$n$after';
        _exprCtrl.text = next;
        final caret = before.length + n.length;
        _exprCtrl.selection = TextSelection.collapsed(offset: caret);
        _notify();
      },
      itemBuilder: (_) => names.map((n) => PopupMenuItem(value: n, child: Text(n))).toList(),
    );
  }

  void _notify() {
    final name = _nameCtrl.text;
    final raw = _exprCtrl.text.trim();
    final asNum = double.tryParse(raw);

    final updated = widget.entry.copy(
      name: name,
      value: asNum,               // numeric if parsable
      formula: asNum == null ? (raw.isEmpty ? null : raw) : null, // otherwise formula
      scope: widget.entry.scope,  // keep scope
      unit: widget.entry.unit,
      note: widget.entry.note,
    );

    widget.onChanged(updated);
  }
}

class _ErrorBanner extends StatelessWidget {
  final String text;
  const _ErrorBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: Colors.red.shade800))),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(text, style: const TextStyle(color: Colors.black54)));
  }
}

class _ParamHelpButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Parameters can reference earlier parameters. Avoid cycles. Examples:\n'
          '  • base_rate = 1000\n'
          '  • efficiency = 0.9\n'
          '  • output = base_rate * efficiency',
      child: const Icon(Icons.help_outline),
    );
  }
}
