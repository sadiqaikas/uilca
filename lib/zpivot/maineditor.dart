import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart'; // for LlmService
import 'llm_service.dart';
import 'texteditor.dart';
import 'processpane.dart';
import 'canvas.dart';

class MainEditorPage extends StatefulWidget {
  const MainEditorPage({Key? key}) : super(key: key);

  @override
  _MainEditorPageState createState() => _MainEditorPageState();
}

class _MainEditorPageState extends State<MainEditorPage> {
  final TextEditingController _promptController = TextEditingController();
  final GlobalKey _canvasKey = GlobalKey();

  late final LlmService _llmService;
  List<String> _palette = [];
  List<ProcessNode> _nodes = [];
  List<Connection> _connections = [];
  double _freedom = 0.5;
  Timer? _debounce;
  int _nextNodeId = 1;

  @override
  void initState() {
    super.initState();
    _llmService = LlmService(endpoint: Uri.parse('https://instantlca.duckdns.org/runLCA'));
    _promptController.addListener(_onPromptOrFreedomChanged);
    // initial default palette
    _palette = ['Stage 1', 'Stage 2', 'Stage 3'];
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _promptController.dispose();
    super.dispose();
  }

  void _onPromptOrFreedomChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _runAutoPredict);
  }

  Future<void> _runAutoPredict() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty && _nodes.isEmpty) {
      // fallback default
      setState(() => _palette = ['Stage A', 'Stage B', 'Stage C']);
      return;
    }

    try {
      final pred = await _llmService.predictCanvas(
        prompt: prompt,
        freedom: _freedom,
        existingNodes: _nodes,
        existingConnections: _connections,
      );

      // layout new nodes
      final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      final size = box.size;
      final gap = size.width / (pred.processes.length + 1);
      final cy = size.height / 2 - ProcessNode.height / 2;

      List<ProcessNode> newNodes = [];
      for (var i = 0; i < pred.processes.length; i++) {
        newNodes.add(ProcessNode(
          id: _nextNodeId++,
          label: pred.processes[i],
          position: Offset(gap * (i + 1) - ProcessNode.width / 2, cy),
        ));
      }

      List<Connection> newConns = [];
      for (var f in pred.flows) {
        newConns.add(Connection(
          fromId: newNodes[f.fromIndex].id,
          toId: newNodes[f.toIndex].id,
          label: f.label,
        ));
      }

      setState(() {
        _palette = pred.processes;
        _nodes = newNodes;
        _connections = newConns;
      });
    } catch (e) {
      // on error, leave previous state
      debugPrint('Auto-predict error: $e');
    }
  }

  /// Add a custom process
  Future<void> _addCustomProcess() async {
    final formKey = GlobalKey<FormState>();
    String? name;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Process'),
        content: Form(
          key: formKey,
          child: TextFormField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Process name'),
            validator: (v) => v == null || v.trim().isEmpty ? 'Enter a name' : null,
            onSaved: (v) => name = v?.trim(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                formKey.currentState!.save();
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name != null) {
      setState(() => _palette.add(name!));
    }
  }

  /// Handle a node tap: rename, delete, or link
  Future<void> _onNodeTap(ProcessNode node) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(node.label),
        content: const Text('Choose:'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'close'), child: const Text('Close')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'rename'), child: const Text('Rename')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'link'), child: const Text('Link')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    switch (action) {
      case 'rename':
        await _renameNode(node);
        break;
      case 'delete':
        _removeNode(node.id);
        break;
      case 'link':
        await _linkNode(node);
        break;
      default:
        break;
    }
  }

  Future<void> _renameNode(ProcessNode node) async {
    final ctl = TextEditingController(text: node.label);
    final newLabel = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: ctl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    if (newLabel != null && newLabel.isNotEmpty) {
      setState(() => node.label = newLabel);
    }
  }

  Future<void> _linkNode(ProcessNode from) async {
    final targetId = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Link to…'),
        children: [
          for (var n in _nodes.where((n) => n.id != from.id))
            SimpleDialogOption(
              child: Text(n.label),
              onPressed: () => Navigator.pop(ctx, n.id),
            )
        ],
      ),
    );
    if (targetId == null) return;
    final to = _nodes.firstWhere((n) => n.id == targetId);
    final ctl = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Flow name'),
        content: TextField(controller: ctl, decoration: const InputDecoration(hintText: 'e.g. “Transport”')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    if (label != null && label.isNotEmpty) {
      setState(() {
        _connections.add(Connection(fromId: from.id, toId: to.id, label: label));
      });
    }
  }

  void _removeNode(int id) {
    setState(() {
      _nodes.removeWhere((n) => n.id == id);
      _connections.removeWhere((c) => c.fromId == id || c.toId == id);
    });
  }

  void _removeLink(Connection conn) {
    setState(() => _connections.remove(conn));
  }

  /// Add a node from palette
  void _onAddNode(String label, Offset global) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(global);
    setState(() {
      _nodes.add(ProcessNode(id: _nextNodeId++, label: label, position: local));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LCA Editor')),
      body: Column(
        children: [
          ProcessPane(
            palette: _palette,
            onAddCustomProcess: _addCustomProcess,
          ),

          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: TextEditor(
                    controller: _promptController,
                    onChanged: (_) => _onPromptOrFreedomChanged(),
                    freedom: _freedom,
                    onFreedomChanged: (v) {
                      setState(() => _freedom = v);
                      _onPromptOrFreedomChanged();
                    },
                  ),
                ),

                const VerticalDivider(width: 1),

                Expanded(
                  flex: 2,
                  child: EditorCanvas(
                    key: _canvasKey,
                    nodes: _nodes,
                    connections: _connections,
                    onAddNode: _onAddNode,
                    onNodePanUpdate: (n, d) {
                      setState(() => n.position += d.delta);
                    },
                    onNodeTap: _onNodeTap,
                    onLinkTap: _removeLink,
                  ),
                ),
              ],
            ),
          ),

          Container(
            color: Colors.grey[50],
            padding: const EdgeInsets.all(16),
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: () {/* TODO: Run LCA analysis */},
              child: const Text('Run Analysis'),
            ),
          ),
        ],
      ),
    );
  }
}
