// // lib/widgets/process_editor.dart

// import 'package:flutter/material.dart';
// import 'process_node.dart';
// import 'flow_link.dart';
// import 'uncertainty_level.dart';

// /// A panel for editing a single process and its flows.
// ///
// /// - [process]: the node being edited
// /// - [flowLinks]: all flows connected to this process
// /// - [onSave]: called with the updated ProcessNode when “Save” is tapped
// /// - [onFlowUpdate]: called for each FlowLink after “Save”
// /// - [onCancel]: optional; called if the user taps “Cancel”
// class ProcessEditor extends StatefulWidget {
//   final ProcessNode process;
//   final List<FlowLink> flowLinks;
//   final void Function(ProcessNode) onSave;
//   final void Function(FlowLink) onFlowUpdate;
//   final VoidCallback? onCancel;

//   const ProcessEditor({
//     Key? key,
//     required this.process,
//     required this.flowLinks,
//     required this.onSave,
//     required this.onFlowUpdate,
//     this.onCancel,
//   }) : super(key: key);

//   @override
//   _ProcessEditorState createState() => _ProcessEditorState();
// }

// class _ProcessEditorState extends State<ProcessEditor> {
//   final _formKey = GlobalKey<FormState>();

//   late TextEditingController _nameCtrl;
//   late UncertaintyLevel _uncertainty;

//   // For each flow, keep controllers for quantity & unit
//   late List<_FlowEditModel> _flowsEdits;

//   @override
//   void initState() {
//     super.initState();
//     _nameCtrl = TextEditingController(text: widget.process.name);
//     _uncertainty = widget.process.uncertainty;
//     _flowsEdits = widget.flowLinks.map((f) {
//       return _FlowEditModel(
//         original: f,
//         qtyCtrl: TextEditingController(text: f.quantity.toString()),
//         unitCtrl: TextEditingController(text: f.unit),
//       );
//     }).toList();
//   }

//   @override
//   void dispose() {
//     _nameCtrl.dispose();
//     for (var fe in _flowsEdits) {
//       fe.qtyCtrl.dispose();
//       fe.unitCtrl.dispose();
//     }
//     super.dispose();
//   }

//   void _handleSave() {
//     if (!_formKey.currentState!.validate()) return;

//     // 1) Update process
//     final updatedNode = widget.process.copyWith(
//       name: _nameCtrl.text.trim(),
//       uncertainty: _uncertainty,
//     );
//     widget.onSave(updatedNode);

//     // 2) Update each flow
//     for (var fe in _flowsEdits) {
//       final q = double.tryParse(fe.qtyCtrl.text) ?? fe.original.quantity;
//       final u = fe.unitCtrl.text.trim().isEmpty
//           ? fe.original.unit
//           : fe.unitCtrl.text.trim();
//       final updatedFlow = fe.original.copyWith(
//         quantity: q,
//         unit: u,
//       );
//       widget.onFlowUpdate(updatedFlow);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Card(
//       margin: const EdgeInsets.all(12),
//       elevation: 4,
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Form(
//           key: _formKey,
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               // Header
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Text(
//                     'Edit "${widget.process.name}"',
//                     style: Theme.of(context)
//                         .textTheme
//                         .titleMedium
//                         ?.copyWith(fontWeight: FontWeight.bold),
//                   ),
//                   if (widget.onCancel != null)
//                     IconButton(
//                       icon: const Icon(Icons.close),
//                       tooltip: 'Cancel',
//                       onPressed: widget.onCancel,
//                     ),
//                 ],
//               ),
//               const SizedBox(height: 12),

//               // Process name
//               TextFormField(
//                 controller: _nameCtrl,
//                 decoration: const InputDecoration(
//                   labelText: 'Process Name',
//                   border: OutlineInputBorder(),
//                 ),
//                 validator: (v) =>
//                     v == null || v.trim().isEmpty ? 'Required' : null,
//               ),
//               const SizedBox(height: 12),

//               // Uncertainty dropdown
//               DropdownButtonFormField<UncertaintyLevel>(
//                 value: _uncertainty,
//                 decoration: const InputDecoration(
//                   labelText: 'Uncertainty Level',
//                   border: OutlineInputBorder(),
//                 ),
//                 items: UncertaintyLevel.values.map((u) {
//                   return DropdownMenuItem(
//                     value: u,
//                     child: Text(u.name.toUpperCase()),
//                   );
//                 }).toList(),
//                 onChanged: (u) {
//                   if (u != null) setState(() => _uncertainty = u);
//                 },
//               ),
//               const SizedBox(height: 16),

//               // Flows table header
//               Text(
//                 'Flows',
//                 style: Theme.of(context).textTheme.titleSmall,
//               ),
//               const SizedBox(height: 8),

//               // Editable list of flows
//               Expanded(
//                 child: ListView.separated(
//                   itemCount: _flowsEdits.length,
//                   separatorBuilder: (_, __) => const Divider(),
//                   itemBuilder: (context, i) {
//                     final fe = _flowsEdits[i];
//                     return _FlowEditRow(edit: fe);
//                   },
//                 ),
//               ),

//               // Save button
//               Padding(
//                 padding: const EdgeInsets.only(top: 12),
//                 child: Align(
//                   alignment: Alignment.centerRight,
//                   child: ElevatedButton.icon(
//                     icon: const Icon(Icons.save),
//                     label: const Text('Save'),
//                     onPressed: _handleSave,
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// /// Helper model to keep controllers for one flow edit.
// class _FlowEditModel {
//   final FlowLink original;
//   final TextEditingController qtyCtrl;
//   final TextEditingController unitCtrl;
//   _FlowEditModel({
//     required this.original,
//     required this.qtyCtrl,
//     required this.unitCtrl,
//   });
// }

// /// A single row showing flow name + editable qty & unit.
// class _FlowEditRow extends StatelessWidget {
//   final _FlowEditModel edit;
//   const _FlowEditRow({Key? key, required this.edit}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       children: [
//         // Flow name
//         Expanded(
//           flex: 3,
//           child: Text(edit.original.name),
//         ),

//         // Quantity
//         Expanded(
//           flex: 2,
//           child: TextFormField(
//             controller: edit.qtyCtrl,
//             keyboardType:
//                 const TextInputType.numberWithOptions(decimal: true),
//             decoration: const InputDecoration(
//               labelText: 'Qty',
//               border: OutlineInputBorder(),
//             ),
//             validator: (v) =>
//                 double.tryParse(v ?? '') == null ? 'Invalid' : null,
//           ),
//         ),

//         const SizedBox(width: 8),

//         // Unit
//         Expanded(
//           flex: 2,
//           child: TextFormField(
//             controller: edit.unitCtrl,
//             decoration: const InputDecoration(
//               labelText: 'Unit',
//               border: OutlineInputBorder(),
//             ),
//           ),
//         ),
//       ],
//     );
//   }
// }

// lib/widgets/process_editor.dart
// lib/widgets/process_editor.dart

import 'package:flutter/material.dart';
import 'process_node.dart';
import 'flow_link.dart';
import 'uncertainty_level.dart';

/// Callback for reconnecting a flow: (flow, newFrom, newTo).
typedef ReconnectCallback = void Function(
  FlowLink flow,
  String newFrom,
  String newTo,
);

/// A panel for editing a single process and its flows.
///
/// - [process]: the node being edited
/// - [flowLinks]: all flows connected to this process
/// - [onSave]: commit name & uncertainty
/// - [onFlowUpdate]: commit qty/unit
/// - [onDeleteProcess]: remove this process entirely
/// - [onDeleteFlow]: remove one flow
/// - [onReconnectFlow]: rewire one flow
/// - [onCancel]: close without saving
class ProcessEditor extends StatefulWidget {
  final ProcessNode process;
  final List<FlowLink> flowLinks;
  final ValueChanged<ProcessNode> onSave;
  final ValueChanged<FlowLink> onFlowUpdate;
  final ValueChanged<ProcessNode>? onDeleteProcess;
  final ValueChanged<FlowLink>? onDeleteFlow;
  final ReconnectCallback? onReconnectFlow;
  final VoidCallback? onCancel;

  const ProcessEditor({
    Key? key,
    required this.process,
    required this.flowLinks,
    required this.onSave,
    required this.onFlowUpdate,
    this.onDeleteProcess,
    this.onDeleteFlow,
    this.onReconnectFlow,
    this.onCancel,
  }) : super(key: key);

  @override
  _ProcessEditorState createState() => _ProcessEditorState();
}

class _ProcessEditorState extends State<ProcessEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late UncertaintyLevel _uncertainty;
  late final List<_FlowEditModel> _flowsEdits;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.process.name);
    _uncertainty = widget.process.uncertainty;
    _flowsEdits = widget.flowLinks
        .map((f) => _FlowEditModel(
              original: f,
              qtyCtrl:
                  TextEditingController(text: f.quantity.toStringAsFixed(3)),
              unitCtrl: TextEditingController(text: f.unit),
            ))
        .toList();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final fe in _flowsEdits) {
      fe.qtyCtrl.dispose();
      fe.unitCtrl.dispose();
    }
    super.dispose();
  }

  /// Validate and send all edits upstream.
  void _saveAll() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // 1) commit process edits
    final updatedNode = widget.process.copyWith(
      name: _nameCtrl.text.trim(),
      uncertainty: _uncertainty,
    );
    widget.onSave(updatedNode);

    // 2) commit flow edits
    for (final fe in _flowsEdits) {
      final qty = double.tryParse(fe.qtyCtrl.text) ?? fe.original.quantity;
      final unit = fe.unitCtrl.text.trim().isEmpty
          ? fe.original.unit
          : fe.unitCtrl.text.trim();
      final updatedFlow = fe.original.copyWith(quantity: qty, unit: unit);
      widget.onFlowUpdate(updatedFlow);
    }
  }

  /// Pops a dialog to choose new endpoints for a flow.
  Future<void> _promptReconnect(_FlowEditModel fe) async {
    if (widget.onReconnectFlow == null) return;

    // Collect all possible process IDs
    final choices = widget.flowLinks
        .expand((f) => [f.from, f.to])
        .toSet()
        .toList();

    String newFrom = fe.original.from;
    String newTo = fe.original.to;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reconnect Flow'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: newFrom,
              decoration: const InputDecoration(labelText: 'From process'),
              items: choices
                  .map((c) => DropdownMenuItem<String>(
                        value: c,
                        child: Text(c),
                      ))
                  .toList(),
              onChanged: (v) => v != null ? newFrom = v : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: newTo,
              decoration: const InputDecoration(labelText: 'To process'),
              items: choices
                  .map((c) => DropdownMenuItem<String>(
                        value: c,
                        child: Text(c),
                      ))
                  .toList(),
              onChanged: (v) => v != null ? newTo = v : null,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onReconnectFlow!(fe.original, newFrom, newTo);
            },
            child: const Text('Reconnect'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 4,
      child: SizedBox(
        height: double.infinity,
        child: Column(
          children: [
            // ─── Header ──────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit "${widget.process.name}"',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (widget.onDeleteProcess != null)
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      tooltip: 'Delete process',
                      onPressed: () =>
                          widget.onDeleteProcess!(widget.process),
                    ),
                  if (widget.onCancel != null)
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Cancel',
                      onPressed: widget.onCancel,
                    ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ─── Body ────────────────────────
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Process name
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Process Name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 12),

                      // Uncertainty
                      DropdownButtonFormField<UncertaintyLevel>(
                        value: _uncertainty,
                        decoration: const InputDecoration(
                          labelText: 'Uncertainty Level',
                          border: OutlineInputBorder(),
                        ),
                        items: UncertaintyLevel.values
                            .map((u) => DropdownMenuItem<UncertaintyLevel>(
                                  value: u,
                                  child: Text(u.label),
                                ))
                            .toList(),
                        onChanged: (u) =>
                            u != null ? setState(() => _uncertainty = u) : null,
                      ),
                      const SizedBox(height: 16),

                      // Flows header
                      Text(
                        'Flows',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),

                      // Flow rows
                      ..._flowsEdits.map((fe) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              // Flow name
                              Expanded(flex: 3, child: Text(fe.original.name)),

                              // Quantity
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: fe.qtyCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                    labelText: 'Qty',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (v) => double.tryParse(v ?? '') ==
                                          null
                                      ? 'Invalid'
                                      : null,
                                ),
                              ),

                              const SizedBox(width: 8),

                              // Unit
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: fe.unitCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Unit',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),

                              // Reconnect
                              if (widget.onReconnectFlow != null)
                                IconButton(
                                  icon: const Icon(Icons.swap_horiz),
                                  tooltip: 'Reconnect',
                                  onPressed: () => _promptReconnect(fe),
                                ),

                              // Delete flow
                              if (widget.onDeleteFlow != null)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.redAccent),
                                  tooltip: 'Delete flow',
                                  onPressed: () => widget.onDeleteFlow!(
                                      fe.original),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
            ),

            // ─── Footer: Save Button ───────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  if (widget.onCancel != null)
                    TextButton(
                      onPressed: widget.onCancel,
                      child: const Text('Cancel'),
                    ),
                  const Spacer(),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('Save Changes'),
                    onPressed: _saveAll,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Internal model holding controllers for one flow edit
class _FlowEditModel {
  final FlowLink original;
  final TextEditingController qtyCtrl;
  final TextEditingController unitCtrl;

  _FlowEditModel({
    required this.original,
    required this.qtyCtrl,
    required this.unitCtrl,
  });
}
