import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'canvas_page.dart';
import 'lca_models.dart';

class CanvasStartPage extends StatefulWidget {
  const CanvasStartPage({super.key});

  @override
  State<CanvasStartPage> createState() => _CanvasStartPageState();
}

class _CanvasStartPageState extends State<CanvasStartPage> {
  static const String _paperBaseModelAssetPath = 'basemodel/base model.json';
  static const String _openLcaBackendBaseUrl = String.fromEnvironment(
    'OPENLCA_BACKEND_BASE_URL',
    defaultValue: 'http://localhost:8001',
  );
  static const String _openLcaIpcUrl = String.fromEnvironment(
    'OPENLCA_IPC_URL',
    defaultValue: 'http://localhost:8080',
  );

  bool _isLoading = false;
  Map<String, dynamic>? _selectedProductSystem;

  void _guardWebMixedContent(Uri uri) {
    if (kIsWeb && Uri.base.scheme == 'https' && uri.scheme == 'http') {
      throw Exception(
        'Blocked by browser mixed-content policy. This web app is on HTTPS '
        'but backend URL is HTTP ($uri). Use an HTTPS backend URL or run the app locally over HTTP.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> _fetchOpenLcaProductSystems() async {
    final uri = Uri.parse(
      '$_openLcaBackendBaseUrl/openlca/product-systems',
    ).replace(
      queryParameters: {'ipc_url': _openLcaIpcUrl},
    );
    _guardWebMixedContent(uri);

    final response = await http.get(
      uri,
      headers: const {'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'OpenLCA backend error ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('OpenLCA backend returned invalid JSON.');
    }

    final rawSystems = decoded['product_systems'];
    if (rawSystems is! List) {
      return const [];
    }

    return rawSystems
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<Map<String, dynamic>> _fetchProjectBundle(
    String productSystemId,
  ) async {
    final uri = Uri.parse(
      '$_openLcaBackendBaseUrl/openlca/product-systems/$productSystemId/project-bundle',
    ).replace(
      queryParameters: {'ipc_url': _openLcaIpcUrl},
    );
    _guardWebMixedContent(uri);

    final response = await http.get(
      uri,
      headers: const {'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'OpenLCA backend error ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('OpenLCA backend returned invalid JSON.');
    }
    return decoded;
  }

  String _entitySearchBlob(Map<String, dynamic> item) {
    return [
      item['name'],
      item['id'],
      item['category'],
      item['library'],
      item['location'],
    ].where((e) => e != null).join(' ').toLowerCase();
  }

  String _entityDisplayName(
    Map<String, dynamic> item, {
    required String fallback,
  }) {
    final name = (item['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final id = (item['id'] ?? '').toString().trim();
    if (id.isNotEmpty) return id;
    return fallback;
  }

  Future<Map<String, dynamic>?> _showProductSystemDialog({
    required List<Map<String, dynamic>> items,
    Map<String, dynamic>? currentSelection,
  }) {
    String query = '';
    final initialId = (currentSelection?['id'] ?? '').toString();

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? items
                : items.where((item) => _entitySearchBlob(item).contains(q)).toList();

            return AlertDialog(
              title: const Text('Choose OpenLCA Product System'),
              content: SizedBox(
                width: 620,
                height: 460,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search by name, id, category, library, location',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setDialogState(() => query = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'No product systems match your search.',
                                style: TextStyle(color: Colors.black54),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final item = filtered[index];
                                final id = (item['id'] ?? '').toString();
                                final subtitleParts = <String>[
                                  if ((item['category'] ?? '').toString().trim().isNotEmpty)
                                    (item['category'] ?? '').toString().trim(),
                                  if ((item['library'] ?? '').toString().trim().isNotEmpty)
                                    (item['library'] ?? '').toString().trim(),
                                  if ((item['location'] ?? '').toString().trim().isNotEmpty)
                                    (item['location'] ?? '').toString().trim(),
                                  if (id.isNotEmpty) id,
                                ];
                                final isCurrent = id.isNotEmpty && id == initialId;

                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    isCurrent ? Icons.check_circle : Icons.circle_outlined,
                                    size: 18,
                                  ),
                                  title: Text(
                                    _entityDisplayName(
                                      item,
                                      fallback: '(unnamed)',
                                    ),
                                  ),
                                  subtitle: subtitleParts.isEmpty
                                      ? null
                                      : Text(subtitleParts.join(' | ')),
                                  onTap: () => Navigator.of(dialogContext).pop(item),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openNewEmpty() async {
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LCACanvasPage()),
    );
  }

  Future<void> _importFromOpenLca() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final systems = await _fetchOpenLcaProductSystems();
      if (!mounted) return;

      if (systems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No product systems were returned by OpenLCA IPC backend.'),
          ),
        );
        return;
      }

      final selected = await _showProductSystemDialog(
        items: systems,
        currentSelection: _selectedProductSystem,
      );
      if (!mounted || selected == null) return;

      final productSystemId = (selected['id'] ?? '').toString().trim();
      if (productSystemId.isEmpty) {
        throw Exception('Selected product system is missing an id.');
      }

      final payload = await _fetchProjectBundle(productSystemId);
      if (!mounted) return;

      final rawBundle = payload['project_bundle'];
      if (rawBundle is! Map) {
        throw Exception('OpenLCA backend did not return project_bundle.');
      }
      final bundle = Map<String, dynamic>.from(rawBundle);

      final rawProcesses = bundle['processes'];
      if (rawProcesses is! List) {
        throw Exception('project_bundle.processes is missing or invalid.');
      }
      final processes = rawProcesses
          .whereType<Map>()
          .map((entry) => ProcessNode.fromJson(Map<String, dynamic>.from(entry)))
          .toList();

      final parameters = ParameterSet.fromJson(bundle);

      final rawFlows = bundle['flows'];
      final flows = rawFlows is List
          ? rawFlows
              .whereType<Map>()
              .map((entry) {
                final item = Map<String, dynamic>.from(entry);
                final names = item['names'];
                if (names is List) {
                  item['names'] = names.map((e) => e.toString()).toList();
                }
                return item;
              })
              .toList()
          : <Map<String, dynamic>>[];

      if (processes.isEmpty) {
        throw Exception(
          'OpenLCA import returned no processes. Check the selected product system.',
        );
      }

      _selectedProductSystem = selected;
      final projectName = _entityDisplayName(
        selected,
        fallback: 'OpenLCA Import',
      );

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LCACanvasPage(
            initialProcesses: processes,
            initialParameters: parameters,
            initialFlows: flows,
            initialProjectName: projectName,
            initialOpenLcaProductSystem: selected,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OpenLCA import failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _importPaperBaseModel() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final rawJson = await rootBundle.loadString(_paperBaseModelAssetPath);
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) {
        throw Exception('Paper base model JSON is invalid.');
      }

      final bundle = Map<String, dynamic>.from(decoded);
      final rawProcesses = bundle['processes'];
      if (rawProcesses is! List) {
        throw Exception('Paper base model is missing processes.');
      }

      final processes = rawProcesses
          .whereType<Map>()
          .map((entry) => ProcessNode.fromJson(Map<String, dynamic>.from(entry)))
          .toList();
      final parameters = ParameterSet.fromJson(bundle);

      final rawFlows = bundle['flows'];
      final flows = rawFlows is List
          ? rawFlows
              .whereType<Map>()
              .map((entry) {
                final item = Map<String, dynamic>.from(entry);
                final names = item['names'];
                if (names is List) {
                  item['names'] = names.map((e) => e.toString()).toList();
                }
                return item;
              })
              .toList()
          : <Map<String, dynamic>>[];

      if (processes.isEmpty) {
        throw Exception('Paper base model has no processes.');
      }

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LCACanvasPage(
            initialProcesses: processes,
            initialParameters: parameters,
            initialFlows: flows,
            initialProjectName: 'Paper Base Model',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Paper model import failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE8F5E9), Color(0xFFFFFFFF)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              elevation: 10,
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Start LCA Project',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Create an empty canvas, import the paper base model, or import from OpenLCA.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _openNewEmpty,
                      icon: const Icon(Icons.add_box),
                      label: const Text('New Empty'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _importPaperBaseModel,
                      icon: const Icon(Icons.description),
                      label: const Text('Import Paper Base Model'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _importFromOpenLca,
                      icon: const Icon(Icons.cloud_download),
                      label: const Text('Import from OpenLCA'),
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: 18),
                      const Center(child: CircularProgressIndicator()),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
