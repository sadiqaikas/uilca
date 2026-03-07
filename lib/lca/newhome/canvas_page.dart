


// lib/lca/LCACanvasPage.dart

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:earlylca/lca/export.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lca_models.dart';
import 'lca_parameter_manager.dart';
import 'lca_process_dialogs.dart';
import 'lca_widgets.dart';
import 'lca_painters.dart';

// Use the io utils with the new uploadProjectBundle helper
import 'package:earlylca/lca/io_utils.dart';

class LCACanvasPage extends StatefulWidget {
  final List<ProcessNode> initialProcesses;
  final ParameterSet initialParameters;
  final List<Map<String, dynamic>>? initialFlows;
  final String? initialProjectName;
  final Map<String, dynamic>? initialOpenLcaProductSystem;

  const LCACanvasPage({
    super.key,
    this.initialProcesses = const [],
    this.initialParameters = const ParameterSet(),
    this.initialFlows,
    this.initialProjectName,
    this.initialOpenLcaProductSystem,
  });

  @override
  State<LCACanvasPage> createState() => _LCACanvasPageState();
}

class _LCACanvasPageState extends State<LCACanvasPage> {
  final List<ProcessNode> _processes = [];
  final Map<String, bool> _collapsed = {}; // nodeId -> true if collapsed
  final GlobalKey _viewportKey = GlobalKey();

  String? _draggedNodeId;
  Offset? _dragOffsetFromOrigin; // in canvas space
  String? _selectedNodeId;
  bool _isCanvasPanning = false;

  // Zoom
  double _scale = 1.0;
  Offset _pan = Offset.zero; // kept for future panning

  // Per-node height scaling
  final Map<String, double> _nodeHeightScale = {}; // default 1.0

  // Parameters for the whole project
  ParameterSet _parameters = const ParameterSet();

  // Cached directed flows between processes (from upstream provider -> downstream consumer).
  List<Map<String, dynamic>> _flows = [];
  bool _upstreamExplorerMode = true;
  String? _finalProcessId;
  final Set<String> _expandedUpstreamNodes = <String>{};
  bool _isScaling = false;
  double _gestureStartScale = 1.0;
  Offset _gestureFocalCanvas = Offset.zero;

  static final RegExp _identifierRe = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');
  static const Set<String> _formulaFnNames = {
    'min',
    'max',
    'abs',
    'round',
    'ceil',
    'floor',
  };
  static const double _minScale = 0.1;
  static const double _maxScale = 3.0;
  static const Color _brandTeal = Color(0xFF0B6E63);
  static const Color _brandTealDark = Color(0xFF095C53);
  static const Color _selectionColor = Color(0xFF14B8A6);

  @override
  void initState() {
    super.initState();
    _processes.addAll(widget.initialProcesses);
    _normaliseProcessPositions();
    _parameters = _hydrateParameterSet(
      base: widget.initialParameters,
      processes: _processes,
    );
    if (widget.initialFlows != null && widget.initialFlows!.isNotEmpty) {
      _flows = widget.initialFlows!
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } else {
      _recomputeFlows();
    }
    _refreshUpstreamExplorer(resetExpansions: true);
    _upstreamExplorerMode = _finalProcessId != null;
    _primeUpstreamExplorer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _frameAllNodes();
    });
  }

  List<ProcessNode> get _activeProcesses {
    if (!_upstreamExplorerMode) return _processes;
    final ids = _visibleUpstreamNodeIds;
    if (ids.isEmpty) return _processes;
    final nodes = _processes.where((p) => ids.contains(p.id)).toList();
    return nodes.isEmpty ? _processes : nodes;
  }

  List<Map<String, dynamic>> get _activeFlows {
    if (!_upstreamExplorerMode) return _flows;
    final ids = _visibleUpstreamNodeIds;
    if (ids.isEmpty) return _flows;
    return _flows.where((raw) {
      final flow = Map<String, dynamic>.from(raw);
      final fromId = (flow['from'] ?? '').toString();
      final toId = (flow['to'] ?? '').toString();
      return ids.contains(fromId) && ids.contains(toId);
    }).toList();
  }

  Set<String> get _visibleUpstreamNodeIds {
    if (!_upstreamExplorerMode || _finalProcessId == null) {
      return {for (final p in _processes) p.id};
    }
    final visible = <String>{_finalProcessId!};
    bool changed;
    do {
      changed = false;
      final snapshot = visible.toList(growable: false);
      for (final nodeId in snapshot) {
        if (!_expandedUpstreamNodes.contains(nodeId)) continue;
        for (final upstreamId in _upstreamForProcess(nodeId)) {
          if (visible.add(upstreamId)) {
            changed = true;
          }
        }
      }
    } while (changed);
    return visible;
  }

  Map<String, Set<String>> _incomingByNode() {
    final incoming = <String, Set<String>>{
      for (final p in _processes) p.id: <String>{},
    };
    for (final raw in _flows) {
      final flow = Map<String, dynamic>.from(raw);
      final fromId = (flow['from'] ?? '').toString();
      final toId = (flow['to'] ?? '').toString();
      if (fromId.isEmpty || toId.isEmpty || fromId == toId) continue;
      if (!incoming.containsKey(toId) || !incoming.containsKey(fromId)) continue;
      incoming[toId]!.add(fromId);
    }
    return incoming;
  }

  Map<String, Set<String>> _outgoingByNode() {
    final outgoing = <String, Set<String>>{
      for (final p in _processes) p.id: <String>{},
    };
    for (final raw in _flows) {
      final flow = Map<String, dynamic>.from(raw);
      final fromId = (flow['from'] ?? '').toString();
      final toId = (flow['to'] ?? '').toString();
      if (fromId.isEmpty || toId.isEmpty || fromId == toId) continue;
      if (!outgoing.containsKey(toId) || !outgoing.containsKey(fromId)) continue;
      outgoing[fromId]!.add(toId);
    }
    return outgoing;
  }

  Set<String> _upstreamForProcess(String processId) {
    final incoming = _incomingByNode();
    return incoming[processId] ?? const <String>{};
  }

  bool _hasUpstream(String processId) {
    return _upstreamForProcess(processId).isNotEmpty;
  }

  String? _detectFinalProcessId() {
    if (_processes.isEmpty) return null;

    final incoming = _incomingByNode();
    final outgoing = _outgoingByNode();

    final candidates = _processes.where((p) {
      final inCount = incoming[p.id]?.length ?? 0;
      final outCount = outgoing[p.id]?.length ?? 0;
      return inCount > 0 && outCount == 0;
    }).toList();

    if (candidates.isNotEmpty) {
      candidates.sort((a, b) {
        final aIn = incoming[a.id]?.length ?? 0;
        final bIn = incoming[b.id]?.length ?? 0;
        if (aIn != bIn) return bIn.compareTo(aIn);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return candidates.first.id;
    }

    for (final p in _processes) {
      if (p.isFunctional) return p.id;
    }

    final fallback = _processes.toList()
      ..sort((a, b) {
        final aOut = outgoing[a.id]?.length ?? 0;
        final bOut = outgoing[b.id]?.length ?? 0;
        if (aOut != bOut) return aOut.compareTo(bOut);
        final aIn = incoming[a.id]?.length ?? 0;
        final bIn = incoming[b.id]?.length ?? 0;
        if (aIn != bIn) return bIn.compareTo(aIn);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return fallback.first.id;
  }

  void _refreshUpstreamExplorer({bool resetExpansions = false}) {
    final before = _finalProcessId;
    _finalProcessId = _detectFinalProcessId();

    final validIds = {for (final p in _processes) p.id};
    _expandedUpstreamNodes.removeWhere((id) => !validIds.contains(id));

    if (resetExpansions || before != _finalProcessId) {
      _expandedUpstreamNodes.clear();
    }

    if (_finalProcessId == null) {
      _upstreamExplorerMode = false;
      _expandedUpstreamNodes.clear();
    }
  }

  void _primeUpstreamExplorer() {
    if (!_upstreamExplorerMode || _finalProcessId == null) return;
    if (_expandedUpstreamNodes.isNotEmpty) return;
    _expandedUpstreamNodes.add(_finalProcessId!);
  }

  void _toggleNodeUpstream(String nodeId) {
    setState(() {
      if (_expandedUpstreamNodes.contains(nodeId)) {
        _expandedUpstreamNodes.remove(nodeId);
      } else {
        _expandedUpstreamNodes.add(nodeId);
      }
    });
  }

  void _syncDerivedStateAfterModelChange({
    bool recomputeFlows = true,
    bool resetUpstreamExpansion = false,
  }) {
    _normaliseProcessPositions();
    _parameters = _hydrateParameterSet(base: _parameters, processes: _processes);
    if (recomputeFlows) {
      _recomputeFlows();
    }
    _refreshUpstreamExplorer(resetExpansions: resetUpstreamExpansion);
    _primeUpstreamExplorer();
    _pan = _clampPan(_pan);
  }

  ParameterSet _hydrateParameterSet({
    required ParameterSet base,
    required List<ProcessNode> processes,
  }) {
    final global = List<Parameter>.from(base.global);
    final perProcess = <String, List<Parameter>>{
      for (final entry in base.perProcess.entries)
        entry.key: List<Parameter>.from(entry.value),
    };

    // Canonicalise keys to actual process ids (case-insensitive match).
    final idsByLower = <String, String>{
      for (final p in processes) p.id.trim().toLowerCase(): p.id,
    };
    final remap = <String, String>{};
    for (final key in perProcess.keys.toList()) {
      final canonical = idsByLower[key.trim().toLowerCase()];
      if (canonical != null && canonical != key) {
        remap[key] = canonical;
      }
    }
    for (final entry in remap.entries) {
      final from = entry.key;
      final to = entry.value;
      final moved = perProcess.remove(from) ?? const <Parameter>[];
      final existing = perProcess[to] ?? const <Parameter>[];
      perProcess[to] = [...existing, ...moved];
    }

    final globalNames = <String>{
      for (final p in global) p.name.trim().toLowerCase(),
    };

    for (final process in processes) {
      final pid = process.id;
      final local = perProcess.putIfAbsent(pid, () => <Parameter>[]);
      final localNames = <String>{
        for (final p in local) p.name.trim().toLowerCase(),
      };

      void ensureLocal(String name, double fallbackValue) {
        final clean = name.trim();
        if (clean.isEmpty) return;
        final key = clean.toLowerCase();
        if (globalNames.contains(key) || localNames.contains(key)) return;
        local.add(
          Parameter(
            name: clean,
            value: fallbackValue.isFinite ? fallbackValue : 1.0,
            scope: ParameterScope.process,
          ),
        );
        localNames.add(key);
      }

      // Merge embedded process parameters if present.
      for (final p in process.parameters) {
        final name = p.name.trim();
        if (name.isEmpty) continue;
        final key = name.toLowerCase();
        if (globalNames.contains(key) || localNames.contains(key)) continue;
        local.add(
          Parameter(
            name: name,
            value: p.value,
            formula: p.formula,
            scope: ParameterScope.process,
            unit: p.unit,
            note: p.note,
          ),
        );
        localNames.add(key);
      }

      final allFlows = <FlowValue>[
        ...process.inputs,
        ...process.outputs,
        ...process.emissions,
      ];
      for (final flow in allFlows) {
        final bound = (flow.boundParam ?? '').trim();
        if (bound.isNotEmpty) {
          ensureLocal(bound, flow.amount);
        }

        final expr = (flow.amountExpr ?? '').trim();
        if (expr.isEmpty) continue;
        final ids = _extractFormulaIdentifiers(expr);
        for (final id in ids) {
          // Use observed amount for one-variable expressions, otherwise neutral 1.0.
          final fallback = ids.length == 1 ? flow.amount : 1.0;
          ensureLocal(id, fallback);
        }
      }
    }

    final compactPerProcess = <String, List<Parameter>>{};
    for (final entry in perProcess.entries) {
      if (entry.value.isEmpty) continue;
      compactPerProcess[entry.key] = entry.value;
    }

    return ParameterSet(global: global, perProcess: compactPerProcess);
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

  Size _viewportSize() {
    final ctx = _viewportKey.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) return box.size;
    return MediaQuery.of(context).size;
  }

  Size _nodeSize(ProcessNode node) {
    return ProcessNodeWidget.sizeFor(
      node,
      heightScale: _nodeHeightScale[node.id] ?? 1.0,
      collapsed: _collapsed[node.id] ?? false,
    );
  }

  Rect _allProcessBounds() {
    if (_processes.isEmpty) {
      final viewport = _viewportSize();
      return Rect.fromLTWH(0, 0, viewport.width, viewport.height);
    }

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;

    for (final node in _processes) {
      final size = _nodeSize(node);
      minX = math.min(minX, node.position.dx);
      minY = math.min(minY, node.position.dy);
      maxX = math.max(maxX, node.position.dx + size.width);
      maxY = math.max(maxY, node.position.dy + size.height);
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void _normaliseProcessPositions() {
    if (_processes.isEmpty) return;

    final bounds = _allProcessBounds();
    const minVisibleCoord = 24.0;
    final shiftX = bounds.left < minVisibleCoord ? (minVisibleCoord - bounds.left) : 0.0;
    final shiftY = bounds.top < minVisibleCoord ? (minVisibleCoord - bounds.top) : 0.0;

    if (shiftX == 0 && shiftY == 0) return;
    for (var i = 0; i < _processes.length; i++) {
      final node = _processes[i];
      _processes[i] = node.copyWith(
        position: Offset(node.position.dx + shiftX, node.position.dy + shiftY),
      );
    }
  }

  Offset _toCanvas(Offset localPoint) {
    final p = localPoint - _pan;
    return Offset(p.dx / _scale, p.dy / _scale);
  }

  Size _calcCanvasSize(BuildContext context) {
    final screen = _viewportSize();
    double maxX = screen.width, maxY = screen.height;
    for (final n in _processes) {
      final sz = _nodeSize(n);
      maxX = math.max(maxX, n.position.dx + sz.width + 400);
      maxY = math.max(maxY, n.position.dy + sz.height + 400);
    }
    return Size(maxX, maxY);
  }

  void _recomputeFlows() {
    final namesByPair = <String, Set<String>>{};
    final ids = _processes.map((n) => n.id).toList();

    String norm(String s) => s.trim().toLowerCase();

    void addDirectional(String fromId, String toId, Set<String> names) {
      if (fromId.isEmpty || toId.isEmpty || fromId == toId || names.isEmpty) return;
      final key = '$fromId|$toId';
      final existing = namesByPair.putIfAbsent(key, () => <String>{});
      existing.addAll(names);
    }

    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final iOut = _processes[i].outputs.map((f) => norm(f.name)).toSet();
        final jIn = _processes[j].inputs.map((f) => norm(f.name)).toSet();

        final jOut = _processes[j].outputs.map((f) => norm(f.name)).toSet();
        final iIn = _processes[i].inputs.map((f) => norm(f.name)).toSet();

        addDirectional(ids[i], ids[j], iOut.intersection(jIn));
        addDirectional(ids[j], ids[i], jOut.intersection(iIn));
      }
    }

    final out = <Map<String, dynamic>>[];
    for (final entry in namesByPair.entries) {
      final parts = entry.key.split('|');
      if (parts.length != 2) continue;
      final names = entry.value.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      out.add({'from': parts[0], 'to': parts[1], 'names': names});
    }
    out.sort((a, b) {
      final fa = (a['from'] ?? '').toString();
      final fb = (b['from'] ?? '').toString();
      final t = fa.compareTo(fb);
      if (t != 0) return t;
      final ta = (a['to'] ?? '').toString();
      final tb = (b['to'] ?? '').toString();
      return ta.compareTo(tb);
    });

    _flows = out;
  }

  Offset _nextInitialPosition() {
    final screen = _viewportSize();
    const baseX = 80.0;
    const baseY = 80.0;
    const stepX = 280.0;
    const stepY = 120.0;

    final idx = _processes.length;
    final cols = (screen.width ~/ stepX).clamp(1, 5);
    final row = idx ~/ cols;
    final col = idx % cols;

    final usableHeight = math.max(240.0, screen.height - 200.0);
    return Offset(
      baseX + col * stepX,
      baseY + (row * stepY) % usableHeight,
    );
  }

  void _importProcessAppend() {
    final initial = _nextInitialPosition();

    uploadSingleProcessJson((map) {
      final incomingId = (map['id'] as String?)?.trim();
      if (incomingId == null || incomingId.isEmpty) {
        map['id'] = DateTime.now().microsecondsSinceEpoch.toString();
      } else {
        final clash = _processes.any((p) => p.id == incomingId);
        if (clash) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Import cancelled. A process with id "$incomingId" already exists.')),
          );
          return;
        }
      }

      if (map['position'] == null ||
          map['position'] is! Map ||
          (map['position']['x'] == null || map['position']['y'] == null)) {
        map['position'] = {'x': initial.dx, 'y': initial.dy};
      }

      try {
        final node = ProcessNode.fromJson(map as Map<String, dynamic>);
        setState(() {
          _processes.add(node);
          _selectedNodeId = node.id;
          _syncDerivedStateAfterModelChange();
        });
        _focusNode(node.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported process: ${node.name}')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not build ProcessNode: $e')),
        );
      }
    }, context);
  }

  Future<void> _openParameterManager() async {
    final updated = await showDialog<ParameterSet>(
      context: context,
      builder: (_) => ParameterManagerDialog(
        initial: _parameters,
        processes: _processes,
      ),
    );
    if (updated != null) {
      setState(() {
        _parameters = _hydrateParameterSet(base: updated, processes: _processes);
      });
    }
  }

  Future<void> _addProcess() async {
    final initial = _nextInitialPosition();

    final newNode = await Navigator.push<ProcessNode>(
      context,
      MaterialPageRoute(
        builder: (_) => AddProcessDialog(
          initialPosition: initial,
          parameters: _parameters, // global params used for previews
        ),
      ),
    );

    if (newNode != null) {
      setState(() {
        _processes.add(newNode);
        _selectedNodeId = newNode.id;
        _syncDerivedStateAfterModelChange();
      });
      _focusNode(newNode.id);
    }
  }

  void _exportJson() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LCAJsonExportPage(
          processes: _processes,
          flows: _flows,
          parameters: _parameters,
          openLcaProductSystem: widget.initialOpenLcaProductSystem,
        ),
      ),
    );
  }

  void _downloadProjectJson() {
    // Compose a project bundle so parameters are preserved alongside processes.
    final bundle = {
      ..._parameters.toJson(),
      'processes': _processes.map((p) => p.toJson()).toList(),
      'flows': _flows,
    };
    promptAndDownloadProjectBundle(bundle, context);
  }

  Future<void> _editNode(ProcessNode node) async {
    final updated = await showDialog<ProcessNode>(
      context: context,
      builder: (_) => EditProcessDialog(
        original: node,
        parameters: _parameters,
      ),
    );
    if (updated != null) {
      setState(() {
        final idx = _processes.indexWhere((p) => p.id == updated.id);
        if (idx >= 0) _processes[idx] = updated;
        _syncDerivedStateAfterModelChange();
      });
    }
  }

  Offset _clampPan(Offset nextPan) {
    final viewport = _viewportSize();
    final bounds = _allProcessBounds().inflate(220.0);

    final minX = viewport.width - (bounds.right * _scale);
    final maxX = -(bounds.left * _scale);
    final minY = viewport.height - (bounds.bottom * _scale);
    final maxY = -(bounds.top * _scale);

    final dx = minX > maxX
        ? (viewport.width - bounds.width * _scale) / 2 - bounds.left * _scale
        : nextPan.dx.clamp(minX, maxX).toDouble();
    final dy = minY > maxY
        ? (viewport.height - bounds.height * _scale) / 2 - bounds.top * _scale
        : nextPan.dy.clamp(minY, maxY).toDouble();

    return Offset(dx, dy);
  }

  void _frameAllNodes() {
    if (_processes.isEmpty) {
      setState(() {
        _scale = 1.0;
        _pan = Offset.zero;
        _selectedNodeId = null;
      });
      return;
    }

    final viewport = _viewportSize();
    if (viewport.width <= 1 || viewport.height <= 1) return;

    final bounds = _allProcessBounds().inflate(120.0);
    final fitScaleX = viewport.width / bounds.width;
    final fitScaleY = viewport.height / bounds.height;
    final targetScale = math.min(fitScaleX, fitScaleY).clamp(_minScale, _maxScale).toDouble();
    final targetPan = Offset(
      (viewport.width - bounds.width * targetScale) / 2 - bounds.left * targetScale,
      (viewport.height - bounds.height * targetScale) / 2 - bounds.top * targetScale,
    );

    setState(() {
      _scale = targetScale;
      _pan = _clampPan(targetPan);
    });
  }

  void _focusNode(String nodeId, {double? scaleOverride}) {
    ProcessNode? node;
    for (final p in _processes) {
      if (p.id == nodeId) {
        node = p;
        break;
      }
    }
    if (node == null) return;

    final viewport = _viewportSize();
    if (viewport.width <= 1 || viewport.height <= 1) return;

    final nodeSize = _nodeSize(node);
    final nodeCenter = Offset(
      node.position.dx + nodeSize.width / 2,
      node.position.dy + nodeSize.height / 2,
    );
    final targetScale =
        (scaleOverride ?? math.max(_scale, 1.0)).clamp(_minScale, _maxScale).toDouble();
    final targetPan = Offset(
      viewport.width / 2 - nodeCenter.dx * targetScale,
      viewport.height / 2 - nodeCenter.dy * targetScale,
    );

    setState(() {
      if (_upstreamExplorerMode && !_visibleUpstreamNodeIds.contains(nodeId)) {
        // Keep explorer active but reveal full upstream graph for continuous navigation.
        _expandedUpstreamNodes
          ..clear()
          ..addAll(_processes.map((p) => p.id));
      }
      _selectedNodeId = nodeId;
      _scale = targetScale;
      _pan = _clampPan(targetPan);
    });
  }

  void _zoomAt(Offset viewportPoint, double zoomFactor) {
    final nextScale = (_scale * zoomFactor).clamp(_minScale, _maxScale).toDouble();
    if ((nextScale - _scale).abs() < 0.0001) return;

    final canvasPoint = _toCanvas(viewportPoint);
    final nextPan = viewportPoint - Offset(canvasPoint.dx * nextScale, canvasPoint.dy * nextScale);

    _scale = nextScale;
    _pan = _clampPan(nextPan);
  }

  Future<void> _openFindProcessDialog() async {
    if (_processes.isEmpty) return;

    String query = '';
    final sorted = _processes.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final pickedId = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? sorted
                : sorted.where((p) {
                    return p.name.toLowerCase().contains(q) ||
                        p.id.toLowerCase().contains(q);
                  }).toList();

            return AlertDialog(
              title: const Text('Find process'),
              content: SizedBox(
                width: 460,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search process name or id',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) => setDialogState(() => query = value),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'No matching process',
                                style: TextStyle(color: Colors.black54),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final node = filtered[index];
                                final isSelected = node.id == _selectedNodeId;
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    isSelected
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_unchecked,
                                    size: 18,
                                  ),
                                  title: Text(node.name),
                                  subtitle: Text(node.id),
                                  onTap: () => Navigator.of(dialogContext).pop(node.id),
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

    if (pickedId == null) return;
    _focusNode(pickedId, scaleOverride: math.max(_scale, 1.0));
  }

  void _autoPanWhileDragging(Offset localPosition) {
    final viewport = _viewportSize();
    if (viewport.width <= 1 || viewport.height <= 1) return;

    const edge = 72.0;
    const step = 18.0;
    double dx = 0;
    double dy = 0;

    if (localPosition.dx < edge) {
      dx = step;
    } else if (localPosition.dx > viewport.width - edge) {
      dx = -step;
    }
    if (localPosition.dy < edge) {
      dy = step;
    } else if (localPosition.dy > viewport.height - edge) {
      dy = -step;
    }

    if (dx == 0 && dy == 0) return;
    _pan = _clampPan(_pan + Offset(dx, dy));
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    setState(() {
      final pressed = HardwareKeyboard.instance.logicalKeysPressed;
      final zoomIntent = pressed.contains(LogicalKeyboardKey.controlLeft) ||
          pressed.contains(LogicalKeyboardKey.controlRight) ||
          pressed.contains(LogicalKeyboardKey.metaLeft) ||
          pressed.contains(LogicalKeyboardKey.metaRight);

      if (zoomIntent) {
        final dy = event.scrollDelta.dy;
        final zoomFactor = dy > 0 ? (1 / 1.08) : 1.08;
        _zoomAt(event.localPosition, zoomFactor);
      } else {
        _pan = _clampPan(_pan - Offset(event.scrollDelta.dx, event.scrollDelta.dy));
      }
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _isScaling = false;
    _isCanvasPanning = false;
    _draggedNodeId = null;
    _dragOffsetFromOrigin = null;

    final local = _toCanvas(details.localFocalPoint);
    for (final node in _activeProcesses.reversed) {
      final size = _nodeSize(node);
      final rect = Rect.fromLTWH(node.position.dx, node.position.dy, size.width, size.height);
      if (rect.contains(local)) {
        _draggedNodeId = node.id;
        _selectedNodeId = node.id;
        _dragOffsetFromOrigin = local - node.position;
        return;
      }
    }
    _isCanvasPanning = true;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2 || _isScaling) {
      if (!_isScaling) {
        _isScaling = true;
        _isCanvasPanning = false;
        _draggedNodeId = null;
        _dragOffsetFromOrigin = null;
        _gestureStartScale = _scale;
        _gestureFocalCanvas = _toCanvas(details.localFocalPoint);
      }
      setState(() {
        final nextScale = (_gestureStartScale * details.scale).clamp(_minScale, _maxScale).toDouble();
        _scale = nextScale;
        final nextPan = details.localFocalPoint -
            Offset(_gestureFocalCanvas.dx * nextScale, _gestureFocalCanvas.dy * nextScale);
        _pan = _clampPan(nextPan);
      });
      return;
    }

    if (_draggedNodeId != null && _dragOffsetFromOrigin != null) {
      final idx = _processes.indexWhere((n) => n.id == _draggedNodeId);
      if (idx < 0) return;
      setState(() {
        _autoPanWhileDragging(details.localFocalPoint);
        final local = _toCanvas(details.localFocalPoint);
        final next = local - _dragOffsetFromOrigin!;
        const minCoord = 24.0;
        _processes[idx] = _processes[idx].copyWith(
          position: Offset(
            math.max(minCoord, next.dx),
            math.max(minCoord, next.dy),
          ),
        );
      });
      return;
    }

    if (!_isCanvasPanning) return;
    setState(() {
      _pan = _clampPan(_pan + details.focalPointDelta);
    });
  }

  void _onScaleEnd(ScaleEndDetails _) {
    _draggedNodeId = null;
    _dragOffsetFromOrigin = null;
    _isCanvasPanning = false;
    _isScaling = false;
  }

  void _onNodeLongPress(ProcessNode node) async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.teal),
            title: const Text('Edit'),
            onTap: () async {
              Navigator.pop(ctx);
              await _editNode(node);
            },
          ),
          ListTile(
            leading: const Icon(Icons.height, color: Colors.indigo),
            title: const Text('Resize'),
            subtitle: const Text('Make the process box longer or shorter'),
            onTap: () {
              Navigator.pop(ctx);
              _showResizeDialog(node);
            },
          ),
          ListTile(
            leading: const Icon(Icons.check_circle_outline, color: Colors.green),
            title: const Text('Set as functional unit'),
            onTap: () {
              Navigator.pop(ctx);
              setState(() {
                for (var i = 0; i < _processes.length; i++) {
                  _processes[i] = _processes[i].copyWith(isFunctional: _processes[i].id == node.id);
                }
                _syncDerivedStateAfterModelChange(recomputeFlows: false);
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.redAccent),
            title: const Text('Delete'),
            onTap: () {
              Navigator.pop(ctx);
              setState(() {
                _processes.removeWhere((p) => p.id == node.id);
                _syncDerivedStateAfterModelChange();
              });
            },
          ),
        ]),
      ),
    );
  }

  void _showResizeDialog(ProcessNode node) async {
    final current = _nodeHeightScale[node.id] ?? 1.0;
    double temp = current;
    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Resize process'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Adjust height scale'),
              Slider(
                value: temp,
                min: 0.6,
                max: 2.4,
                divisions: 18,
                label: '${temp.toStringAsFixed(2)}×',
                onChanged: (v) => setLocal(() => temp = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                setState(() => _nodeHeightScale[node.id] = temp);
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  void _zoomIn() => setState(() {
        _scale = (_scale * 1.2).clamp(_minScale, _maxScale);
        _pan = _clampPan(_pan);
      });
  void _zoomOut() => setState(() {
        _scale = (_scale / 1.2).clamp(_minScale, _maxScale);
        _pan = _clampPan(_pan);
      });
  void _zoomReset() => _frameAllNodes();

  @override
  Widget build(BuildContext context) {
    final activeProcesses = _activeProcesses;
    final activeFlows = _activeFlows;
    ProcessNode? finalNode;
    if (_finalProcessId != null) {
      for (final p in _processes) {
        if (p.id == _finalProcessId) {
          finalNode = p;
          break;
        }
      }
    }

    final painter = UndirectedConnectionPainter(
      activeProcesses,
      activeFlows,
      nodeHeightScale: _nodeHeightScale,
      collapsed: _collapsed,
    );
    final canvasSize = _calcCanvasSize(context);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        backgroundColor: _brandTeal,
        foregroundColor: Colors.white,
        title: Text(
          widget.initialProjectName == null || widget.initialProjectName!.trim().isEmpty
              ? 'Instant LCA v1.0'
              : 'Instant LCA v1.0 - ${widget.initialProjectName}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, size: 34),
            tooltip: 'Parameters',
            onPressed: _openParameterManager,
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload, size: 40),
            tooltip: 'Load project JSON (replaces, with parameters)',
            onPressed: () => uploadProjectBundle((loadedProcesses, loadedParams) {
              setState(() {
                _processes
                  ..clear()
                  ..addAll(loadedProcesses);
                _selectedNodeId = null;
                _parameters = _hydrateParameterSet(
                  base: loadedParams,
                  processes: _processes,
                );
                _syncDerivedStateAfterModelChange(resetUpstreamExpansion: true);
                _upstreamExplorerMode = _finalProcessId != null;
                _primeUpstreamExplorer();
              });
              _frameAllNodes();
            }, context),
          ),
          IconButton(
            icon: const Icon(Icons.add_link, size: 40),
            tooltip: 'Import single process JSON (append)',
            onPressed: _importProcessAppend,
          ),
          IconButton(
            icon: const Icon(Icons.download, size: 40),
            tooltip: 'Save project JSON',
            onPressed: _downloadProjectJson,
          ),
          IconButton(
            icon: const Icon(Icons.autorenew, size: 34),
            tooltip: 'Update links',
            onPressed: () => setState(() {
              _syncDerivedStateAfterModelChange();
            }),
          ),
          IconButton(
            icon: const Icon(Icons.search, size: 32),
            tooltip: 'Find process',
            onPressed: _openFindProcessDialog,
          ),
          IconButton(
            icon: const Icon(Icons.fit_screen, size: 32),
            tooltip: 'Frame all processes',
            onPressed: _frameAllNodes,
          ),
          IconButton(
            icon: Icon(
              _upstreamExplorerMode ? Icons.account_tree : Icons.account_tree_outlined,
              size: 30,
            ),
            tooltip: _upstreamExplorerMode
                ? 'Disable upstream explorer'
                : 'Enable upstream explorer',
            onPressed: _finalProcessId == null
                ? null
                : () {
                    setState(() {
                      _upstreamExplorerMode = !_upstreamExplorerMode;
                      _primeUpstreamExplorer();
                    });
                  },
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF7FBFF), Color(0xFFEAF6F3)],
          ),
        ),
        child: Listener(
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            key: _viewportKey,
            behavior: HitTestBehavior.translucent,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Transform(
                  alignment: Alignment.topLeft,
                  transform: Matrix4.identity()
                    ..translate(_pan.dx, _pan.dy)
                    ..scale(_scale, _scale),
                  child: SizedBox(
                    width: canvasSize.width,
                    height: canvasSize.height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(painter: painter),
                        ),
                        for (var node in activeProcesses)
                          Positioned(
                            left: node.position.dx,
                            top: node.position.dy,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                GestureDetector(
                                  onTap: () => setState(() => _selectedNodeId = node.id),
                                  onDoubleTap: () => _editNode(node),
                                  onLongPress: () => _onNodeLongPress(node),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 140),
                                    decoration: _selectedNodeId == node.id
                                        ? BoxDecoration(
                                            border: Border.all(
                                              color: _selectionColor,
                                              width: 2,
                                            ),
                                            borderRadius: BorderRadius.circular(12),
                                          )
                                        : null,
                                    child: ProcessNodeWidget(
                                      node: node,
                                      heightScale: _nodeHeightScale[node.id] ?? 1.0,
                                      collapsed: _collapsed[node.id] ?? false,
                                      onToggleCollapse: () {
                                        setState(() {
                                          _collapsed[node.id] = !(_collapsed[node.id] ?? false);
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                if (_upstreamExplorerMode && _hasUpstream(node.id))
                                  Positioned(
                                    right: -10,
                                    top: -10,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: IconButton(
                                        tooltip: _expandedUpstreamNodes.contains(node.id)
                                            ? 'Hide upstream inputs'
                                            : 'Show upstream inputs',
                                        style: IconButton.styleFrom(
                                          backgroundColor: _expandedUpstreamNodes.contains(node.id)
                                              ? _brandTeal
                                              : Colors.white,
                                          side: const BorderSide(color: _brandTeal, width: 1.2),
                                          minimumSize: const Size(28, 28),
                                          padding: const EdgeInsets.all(2),
                                        ),
                                        icon: Icon(
                                          _expandedUpstreamNodes.contains(node.id)
                                              ? Icons.unfold_less
                                              : Icons.account_tree_outlined,
                                          size: 16,
                                          color: _expandedUpstreamNodes.contains(node.id)
                                              ? Colors.white
                                              : _brandTeal,
                                        ),
                                        onPressed: () => _toggleNodeUpstream(node.id),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                right: 12,
                top: 12,
                child: Card(
                  elevation: 4,
                  color: const Color(0xF2FFFFFF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Zoom in',
                        onPressed: _zoomIn,
                        icon: const Icon(Icons.zoom_in),
                      ),
                      Text('${(_scale * 100).round()}%', style: const TextStyle(fontSize: 12)),
                      IconButton(
                        tooltip: 'Zoom out',
                        onPressed: _zoomOut,
                        icon: const Icon(Icons.zoom_out),
                      ),
                      IconButton(
                        tooltip: 'Reset zoom',
                        onPressed: _zoomReset,
                        icon: const Icon(Icons.center_focus_strong),
                      ),
                      IconButton(
                        tooltip: 'Frame all processes',
                        onPressed: _frameAllNodes,
                        icon: const Icon(Icons.fit_screen),
                      ),
                    ],
                  ),
                ),
              ),
              if (_upstreamExplorerMode)
                Positioned(
                  left: 12,
                  top: 12,
                  child: Card(
                    elevation: 3,
                    color: const Color(0xF2FFFFFF),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Text(
                        finalNode == null
                            ? 'Upstream explorer'
                            : 'Final: ${finalNode.name}  |  showing ${activeProcesses.length}/${_processes.length}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'add',
            onPressed: _addProcess,
            icon: const Icon(Icons.add_box),
            label: const Text('Add process'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'export',
            backgroundColor: _brandTealDark,
            onPressed: _exportJson,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Run / Export'),
          ),
        ],
      ),
    );
  }
}
