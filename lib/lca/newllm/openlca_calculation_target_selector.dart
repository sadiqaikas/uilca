import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

String openLcaFunctionalUnitSummary(Map<String, dynamic>? functionalUnit) {
  if (functionalUnit == null) return 'Functional unit not resolved';
  final amount = functionalUnit['amount'];
  final unit = (functionalUnit['unit'] ?? '').toString().trim();
  final flowName = (functionalUnit['flow_name'] ?? '').toString().trim();
  final flowProperty = (functionalUnit['flow_property'] ?? '').toString().trim();
  final amountText =
      amount is num ? amount.toString() : amount?.toString().trim() ?? '1';
  final parts = <String>[
    '$amountText${unit.isEmpty ? '' : ' $unit'}',
    if (flowName.isNotEmpty) flowName,
    if (flowProperty.isNotEmpty) flowProperty,
  ];
  return parts.join(' | ');
}

String openLcaCalculationTargetLabel(Map<String, dynamic>? target) {
  if (target == null) return 'OpenLCA target not selected';
  final label = (target['label'] ?? '').toString().trim();
  if (label.isNotEmpty) return label;
  final processName = (target['process_name'] ?? '').toString().trim();
  if (processName.isNotEmpty) return processName;
  return (target['target_id'] ?? '').toString().trim();
}

List<String> _openLcaBackendCandidates(String configured) {
  final candidates = <String>[];

  void add(String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty && !candidates.contains(trimmed)) {
      candidates.add(trimmed);
    }
  }

  add(configured);
  add(configured.replaceAll('localhost', '127.0.0.1'));
  add(configured.replaceAll('127.0.0.1', 'localhost'));
  return candidates;
}

void _guardWebMixedContent(Uri uri) {
  if (kIsWeb && Uri.base.scheme == 'https' && uri.scheme == 'http') {
    throw Exception(
      'The app is running over HTTPS but the OpenLCA backend URL is HTTP.',
    );
  }
}

Future<Map<String, dynamic>> _fetchCalculationTargets({
  required String backendBaseUrl,
  required String ipcUrl,
  required String productSystemId,
}) async {
  Object? lastError;
  for (final base in _openLcaBackendCandidates(backendBaseUrl)) {
    final uri = Uri.parse(
      '$base/openlca/product-systems/$productSystemId/calculation-targets',
    ).replace(queryParameters: {'ipc_url': ipcUrl});
    _guardWebMixedContent(uri);
    try {
      final response = await http.get(
        uri,
        headers: const {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) {
        lastError = Exception(
          'OpenLCA backend error ${response.statusCode}: ${response.body}',
        );
        continue;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('OpenLCA backend returned invalid JSON.');
      }
      return decoded;
    } catch (error) {
      lastError = error;
    }
  }
  throw Exception(
    'OpenLCA bridge unreachable on ${_openLcaBackendCandidates(backendBaseUrl).join(', ')}. '
    'Last error: $lastError',
  );
}

Future<Map<String, dynamic>?> showOpenLcaCalculationTargetDialog({
  required BuildContext context,
  required String backendBaseUrl,
  required String ipcUrl,
  required Map<String, dynamic> productSystem,
  Map<String, dynamic>? currentSelection,
}) async {
  final productSystemId = (productSystem['id'] ?? '').toString().trim();
  if (productSystemId.isEmpty) {
    throw Exception('Selected product system is missing an id.');
  }

  final decoded = await _fetchCalculationTargets(
    backendBaseUrl: backendBaseUrl,
    ipcUrl: ipcUrl,
    productSystemId: productSystemId,
  );
  final productTarget = Map<String, dynamic>.from(
    decoded['product_system_target'] as Map,
  );
  final directTargets =
      ((decoded['direct_process_targets'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  final currentType = (currentSelection?['target_type'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  String selectedType =
      currentType == 'process' && directTargets.isNotEmpty
          ? 'process'
          : 'product_system';
  String? selectedProcessId = (currentSelection?['process_id'] ?? '')
      .toString()
      .trim();
  if (selectedProcessId.isEmpty ||
      !directTargets.any(
        (item) => (item['process_id'] ?? '').toString().trim() == selectedProcessId,
      )) {
    selectedProcessId =
        directTargets.isNotEmpty
            ? (directTargets.first['process_id'] ?? '').toString().trim()
            : null;
  }

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          final productFunctionalUnit =
              productTarget['functional_unit'] is Map
                  ? Map<String, dynamic>.from(productTarget['functional_unit'] as Map)
                  : null;
          Map<String, dynamic>? selectedProcessTarget;
          if (selectedType == 'process' && selectedProcessId != null) {
            for (final item in directTargets) {
              if ((item['process_id'] ?? '').toString().trim() == selectedProcessId) {
                selectedProcessTarget = item;
                break;
              }
            }
            selectedProcessTarget ??= directTargets.isEmpty ? null : directTargets.first;
          }
          final activeTarget =
              selectedType == 'process' && selectedProcessTarget != null
                  ? selectedProcessTarget
                  : productTarget;
          final activeFunctionalUnit =
              activeTarget['functional_unit'] is Map
                  ? Map<String, dynamic>.from(activeTarget['functional_unit'] as Map)
                  : null;
          final warningLines =
              ((decoded['warnings'] as List?) ?? const <dynamic>[])
                  .map((item) => item.toString().trim())
                  .where((item) => item.isNotEmpty)
                  .toList();

          return AlertDialog(
            title: const Text('Choose OpenLCA Calculation Target'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Product system: ${(productSystem['name'] ?? productSystemId).toString()}',
                    ),
                    const SizedBox(height: 12),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'product_system',
                      groupValue: selectedType,
                      onChanged:
                          (value) => setState(() => selectedType = value ?? 'product_system'),
                      title: Text(openLcaCalculationTargetLabel(productTarget)),
                      subtitle: Text(openLcaFunctionalUnitSummary(productFunctionalUnit)),
                    ),
                    const SizedBox(height: 8),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'process',
                      groupValue: selectedType,
                      onChanged:
                          directTargets.isEmpty
                              ? null
                              : (value) => setState(() => selectedType = value ?? 'process'),
                      title: const Text('Direct process run'),
                      subtitle: Text(
                        directTargets.isEmpty
                            ? 'No direct process targets with a safe quantitative reference were found.'
                            : 'Choose a process and run openLCA directly on that reference flow.',
                      ),
                    ),
                    if (directTargets.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedProcessId,
                        decoration: const InputDecoration(
                          labelText: 'Process',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final target in directTargets)
                            DropdownMenuItem<String>(
                              value: (target['process_id'] ?? '').toString().trim(),
                              child: Text(
                                '${(target['process_name'] ?? target['label']).toString()}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged:
                            selectedType == 'process'
                                ? (value) => setState(() => selectedProcessId = value)
                                : null,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(dialogContext).colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            openLcaCalculationTargetLabel(activeTarget),
                            style: Theme.of(dialogContext).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(openLcaFunctionalUnitSummary(activeFunctionalUnit)),
                        ],
                      ),
                    ),
                    if (warningLines.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Skipped process targets',
                        style: Theme.of(dialogContext).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        warningLines.take(3).join('\n'),
                        style: Theme.of(dialogContext).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final selected =
                      selectedType == 'process' && selectedProcessTarget != null
                          ? selectedProcessTarget
                          : productTarget;
                  Navigator.of(
                    dialogContext,
                  ).pop(Map<String, dynamic>.from(selected));
                },
                child: const Text('Use Target'),
              ),
            ],
          );
        },
      );
    },
  );
}
