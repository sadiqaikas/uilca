// lib/layouts/grid_layout.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';

/// Simple longest‐path / median‐sweep grid layout for directed graphs.
class GridLayout {
  GridLayout({
    required this.flows,
    required this.nodeW,
    required this.nodeH,
    required this.hGap,
    required this.vGap,
  });

  /// List of flows, each like { 'from_process': ..., 'to_process': ..., ... }
  final List<Map<String, dynamic>> flows;

  /// Node box size & gaps
  final double nodeW, nodeH, hGap, vGap;

  /// Computed positions
  final Map<Node, Offset> _pos = {};

  /// Canvas dimensions after layout
  double canvasW = 0, canvasH = 0;

  /// Get the position of a node after calling [position].
  Offset? posOf(Node n) => _pos[n];

  /// Perform layout on [g], filling [_pos], [canvasW], and [canvasH].
  void position(Graph g) {
    _pos.clear();

    // Build adjacency maps
    final succ = <String, Set<String>>{}, pred = <String, Set<String>>{};
    for (final n in g.nodes) {
      final id = n.key!.value as String;
      succ[id] = {};
      pred[id] = {};
    }
    for (final e in g.edges) {
      final a = e.source.key!.value as String;
      final b = e.destination.key!.value as String;
      succ[a]!.add(b);
      pred[b]!.add(a);
    }

    // Longest‐path layering
    final level = <String, int>{}, q = <String>[];
    for (final id in succ.keys) {
      if (pred[id]!.isEmpty) {
        level[id] = 0;
        q.add(id);
      }
    }
    if (q.isEmpty) {
      // no roots? pick first
      final first = succ.keys.first;
      level[first] = 0;
      q.add(first);
    }
    while (q.isNotEmpty) {
      final u = q.removeAt(0), base = level[u]!;
      for (final v in succ[u]!) {
        final cand = base + 1;
        if (level[v] == null || cand > level[v]!) {
          level[v] = cand;
        }
        q.add(v);
      }
    }

    // Bucket nodes into columns by level
    final cols = <int, List<String>>{};
    level.forEach((id, l) => cols.putIfAbsent(l, () => []).add(id));

    // Two‐pass median crossing reduction
    void sweep(bool leftToRight) {
      for (final c in cols.keys.toList()..sort()) {
        final list = cols[c]!;
        list.sort((a, b) {
          double medianOf(String id) {
            final neighbors = leftToRight ? pred[id]! : succ[id]!;
            if (neighbors.isEmpty) return 0;
            final idxs = neighbors
                .map((n) => cols[level[n]!]!.indexOf(n).toDouble())
                .toList()
              ..sort();
            return idxs[idxs.length ~/ 2];
          }
          return medianOf(a).compareTo(medianOf(b));
        });
      }
    }
    sweep(true);
    sweep(false);

    // Assign actual positions
    double maxX = 0, maxY = 0;
    for (final c in cols.keys) {
      final list = cols[c]!;
      for (var r = 0; r < list.length; r++) {
        final node = g.getNodeUsingId(list[r])!;
        final x = c * (nodeW + hGap);
        final y = r * (nodeH + vGap);
        _pos[node] = Offset(x, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
    }

    canvasW = maxX + nodeW + hGap;
    canvasH = maxY + nodeH + vGap;
  }
}
