// // lib/io_utils.dart
// import 'dart:convert';
// import 'dart:html' as html;
// import 'package:earlylca/lca/newhome/lca_models.dart';
// import 'package:flutter/material.dart';
// import 'home.dart'; // for ProcessNode and FlowValue

// /// Prompts the user for a filename, then triggers a download of the given
// /// list of ProcessNode as JSON. Shows a SnackBar on completion.
// Future<void> promptAndDownloadProcesses(
//     List<ProcessNode> processes, BuildContext context) async {
//   final controller = TextEditingController(text: 'processes.json');

//   final filename = await showDialog<String>(
//     context: context,
//     builder: (context) {
//       return AlertDialog(
//         title: Text('Save As', style: TextStyle(fontSize: 20)),
//         content: TextField(
//           controller: controller,
//           decoration: InputDecoration(
//             labelText: 'Filename',
//             hintText: 'e.g. my_model.json',
//           ),
//           autofocus: true,
//           style: TextStyle(fontSize: 18),
//         ),
//         actions: [
//           TextButton(
//             child: Text('Cancel', style: TextStyle(fontSize: 16)),
//             onPressed: () => Navigator.pop(context),
//           ),
//           ElevatedButton(
//             child: Text('Save', style: TextStyle(fontSize: 16)),
//             onPressed: () {
//               final name = controller.text.trim();
//               if (name.isNotEmpty) Navigator.pop(context, name);
//             },
//           ),
//         ],
//       );
//     },
//   );

//   if (filename == null) return;

//   final jsonList = processes.map((p) => p.toJson()).toList();
//   final bytes = utf8.encode(jsonEncode(jsonList));
//   final blob = html.Blob([bytes], 'application/json');
//   final url = html.Url.createObjectUrlFromBlob(blob);
//   final anchor = html.document.createElement('a') as html.AnchorElement
//     ..href = url
//     ..download = filename;
//   html.document.body?.append(anchor);
//   anchor.click();
//   anchor.remove();
//   html.Url.revokeObjectUrl(url);

//   ScaffoldMessenger.of(context).showSnackBar(
//     SnackBar(content: Text('Downloaded as "$filename"')),
//   );
// }

// /// Opens a file‐picker, reads the selected JSON file, parses it into a
// /// List<ProcessNode>, and invokes [onLoaded] with that list. Shows a SnackBar
// /// upon success or failure.


// /// Opens a file picker, reads JSON, and returns a single process JSON object
// /// to the callback. Accepts either a single object, or a list and takes the first.
// /// Shows a SnackBar on success or failure.


// File: lib/lca/io_utils.dart
//
// Non-invasive addition: download a full LCA project bundle as JSON.
// Includes global_parameters, process_parameters, processes, and flows.
//
// Usage from canvas_page.dart:
//   promptAndDownloadProjectBundle(bundle, context);
//
// This does not modify existing functions like promptAndDownloadProcesses.

// import 'dart:convert';
// import 'package:earlylca/lca/newhome/lca_models.dart';
// import 'package:flutter/foundation.dart' show kIsWeb;
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'dart:html' as html;
// /// Prompts the user for a filename and downloads the given JSON-able [bundle].
// /// On web: triggers a file download.
// /// On non-web: shows the JSON with a Copy button so the user can save it externally.
// Future<void> promptAndDownloadProjectBundle(
//   Map<String, dynamic> bundle,
//   BuildContext context, {
//   String suggestedFileName = 'lca_project.json',
// }) async {
//   final fileNameCtrl = TextEditingController(text: suggestedFileName);

//   String? chosen;
//   await showDialog<void>(
//     context: context,
//     builder: (_) => AlertDialog(
//       title: const Text('Save project JSON'),
//       content: TextField(
//         controller: fileNameCtrl,
//         decoration: const InputDecoration(
//           labelText: 'File name',
//           hintText: 'lca_project.json',
//         ),
//       ),
//       actions: [
//         TextButton(
//           onPressed: () => Navigator.pop(context),
//           child: const Text('Cancel'),
//         ),
//         ElevatedButton(
//           onPressed: () {
//             chosen = fileNameCtrl.text.trim().isEmpty
//                 ? suggestedFileName
//                 : fileNameCtrl.text.trim();
//             Navigator.pop(context);
//           },
//           child: const Text('Save'),
//         ),
//       ],
//     ),
//   );

//   if (chosen == null) return;

//   final jsonStr = const JsonEncoder.withIndent('  ').convert(bundle);

//   if (kIsWeb) {
//     // Web download using a data URL.
//     await _downloadTextWeb(jsonStr, chosen!);
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text('Saved "$chosen"')),
//     );
//     return;
//   }

//   // Non-web fallback: present a copy dialog so nothing breaks.
//   await showDialog<void>(
//     context: context,
//     builder: (_) => AlertDialog(
//       title: const Text('Project JSON'),
//       content: ConstrainedBox(
//         constraints: const BoxConstraints(maxWidth: 720, maxHeight: 420),
//         child: Scrollbar(
//           thumbVisibility: true,
//           child: SingleChildScrollView(
//             child: SelectableText(jsonStr, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
//           ),
//         ),
//       ),
//       actions: [
//         TextButton(
//           onPressed: () async {
//             await Clipboard.setData(ClipboardData(text: jsonStr));
//             if (Navigator.canPop(context)) Navigator.pop(context);
//             ScaffoldMessenger.of(context).showSnackBar(
//               const SnackBar(content: Text('JSON copied to clipboard')),
//             );
//           },
//           child: const Text('Copy to clipboard'),
//         ),
//         TextButton(
//           onPressed: () => Navigator.pop(context),
//           child: const Text('Close'),
//         ),
//       ],
//     ),
//   );
// }

// /// Web-only helper to trigger a file download.
// Future<void> _downloadTextWeb(String text, String fileName) async {
//   // Avoid importing dart:html at runtime on non-web
//   // ignore: avoid_web_libraries_in_flutter


//   final bytes = utf8.encode(text);
//   final blob = html.Blob([bytes], 'application/json;charset=utf-8');
//   final url = html.Url.createObjectUrlFromBlob(blob);
//   final anchor = html.AnchorElement(href: url)
//     ..download = fileName
//     ..style.display = 'none';
//   html.document.body?.children.add(anchor);
//   anchor.click();
//   anchor.remove();
//   html.Url.revokeObjectUrl(url);
// }
// void uploadSingleProcessJson(
//   void Function(Map<String, dynamic> processJson) onLoaded,
//   BuildContext context,
// ) {
//   final uploadInput = html.FileUploadInputElement()..accept = '.json';
//   uploadInput.click();

//   uploadInput.onChange.listen((_) {
//     final files = uploadInput.files;
//     if (files == null || files.isEmpty) return;

//     final file = files.first;
//     final reader = html.FileReader();

//     reader.onLoadEnd.listen((event) {
//       try {
//         final text = reader.result as String;
//         final dynamic decoded = jsonDecode(text);

//         Map<String, dynamic>? nodeMap;
//         if (decoded is Map<String, dynamic>) {
//           nodeMap = decoded;
//         } else if (decoded is List && decoded.isNotEmpty && decoded.first is Map<String, dynamic>) {
//           nodeMap = decoded.first as Map<String, dynamic>;
//         }

//         if (nodeMap == null) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             const SnackBar(content: Text('File did not contain a process object')),
//           );
//           return;
//         }

//         onLoaded(nodeMap);

//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('Process JSON loaded from file')),
//         );
//       } catch (e) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Failed to parse JSON: $e')),
//         );
//       }
//     });

//     reader.readAsText(file);
//   });
// }

// void uploadProcesses(
//     void Function(List<ProcessNode>) onLoaded, BuildContext context) {
//   final uploadInput = html.FileUploadInputElement()..accept = '.json';
//   uploadInput.click();

//   uploadInput.onChange.listen((_) {
//     final files = uploadInput.files;
//     if (files == null || files.isEmpty) return;

//     final file = files.first;
//     final reader = html.FileReader();

//     reader.onLoadEnd.listen((event) {
//       try {
//         final text = reader.result as String;
//         final List<dynamic> jsonList = jsonDecode(text);
//         final loaded = jsonList
//             .map((item) => ProcessNode.fromJson(item as Map<String, dynamic>))
//             .toList();
//         onLoaded(loaded);

//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Processes loaded from file.')),
//         );
//       } catch (e) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Failed to parse JSON: $e')),
//         );
//       }
//     });

//     reader.readAsText(file);
//   });
// }


// // lib/lca/io_utils.dart

// import 'dart:convert';
// import 'package:earlylca/lca/newhome/lca_models.dart';
// import 'package:flutter/foundation.dart' show kIsWeb;
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'dart:html' as html;

// /// Prompts for a filename and downloads the given JSON-able [bundle] (map).
// /// Web: triggers a file download.
// /// Non-web: shows JSON with Copy button (kept for completeness).
// Future<void> promptAndDownloadProjectBundle(
//   Map<String, dynamic> bundle,
//   BuildContext context, {
//   String suggestedFileName = 'lca_project.json',
// }) async {
//   final fileNameCtrl = TextEditingController(text: suggestedFileName);

//   String? chosen;
//   await showDialog<void>(
//     context: context,
//     builder: (_) => AlertDialog(
//       title: const Text('Save project JSON'),
//       content: TextField(
//         controller: fileNameCtrl,
//         decoration: const InputDecoration(
//           labelText: 'File name',
//           hintText: 'lca_project.json',
//         ),
//       ),
//       actions: [
//         TextButton(
//           onPressed: () => Navigator.pop(context),
//           child: const Text('Cancel'),
//         ),
//         ElevatedButton(
//           onPressed: () {
//             chosen = fileNameCtrl.text.trim().isEmpty
//                 ? suggestedFileName
//                 : fileNameCtrl.text.trim();
//             Navigator.pop(context);
//           },
//           child: const Text('Save'),
//         ),
//       ],
//     ),
//   );

//   if (chosen == null) return;

//   final jsonStr = const JsonEncoder.withIndent('  ').convert(bundle);

//   if (kIsWeb) {
//     await _downloadTextWeb(jsonStr, chosen!);
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text('Saved "$chosen"')),
//     );
//     return;
//   }

//   // Fallback for non-web builds.
//   await showDialog<void>(
//     context: context,
//     builder: (_) => AlertDialog(
//       title: const Text('Project JSON'),
//       content: ConstrainedBox(
//         constraints: const BoxConstraints(maxWidth: 720, maxHeight: 420),
//         child: Scrollbar(
//           thumbVisibility: true,
//           child: SingleChildScrollView(
//             child: SelectableText(
//               jsonStr,
//               style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
//             ),
//           ),
//         ),
//       ),
//       actions: [
//         TextButton(
//           onPressed: () async {
//             await Clipboard.setData(ClipboardData(text: jsonStr));
//             if (Navigator.canPop(context)) Navigator.pop(context);
//             ScaffoldMessenger.of(context).showSnackBar(
//               const SnackBar(content: Text('JSON copied to clipboard')),
//             );
//           },
//           child: const Text('Copy to clipboard'),
//         ),
//         TextButton(
//           onPressed: () => Navigator.pop(context),
//           child: const Text('Close'),
//         ),
//       ],
//     ),
//   );
// }

// /// Optional helper to download a plain list of processes as JSON.
// Future<void> downloadProcesses(
//   List<ProcessNode> processes,
//   BuildContext context, {
//   String suggestedFileName = 'processes.json',
// }) async {
//   final fileNameCtrl = TextEditingController(text: suggestedFileName);

//   String? chosen;
//   await showDialog<void>(
//     context: context,
//     builder: (_) => AlertDialog(
//       title: const Text('Save processes JSON'),
//       content: TextField(
//         controller: fileNameCtrl,
//         decoration: const InputDecoration(
//           labelText: 'File name',
//           hintText: 'processes.json',
//         ),
//       ),
//       actions: [
//         TextButton(
//           onPressed: () => Navigator.pop(context),
//           child: const Text('Cancel'),
//         ),
//         ElevatedButton(
//           onPressed: () {
//             chosen = fileNameCtrl.text.trim().isEmpty
//                 ? suggestedFileName
//                 : fileNameCtrl.text.trim();
//             Navigator.pop(context);
//           },
//           child: const Text('Save'),
//         ),
//       ],
//     ),
//   );

//   if (chosen == null) return;

//   final jsonStr = const JsonEncoder.withIndent('  ')
//       .convert(processes.map((p) => p.toJson()).toList());

//   await _downloadTextWeb(jsonStr, chosen!);
//   ScaffoldMessenger.of(context).showSnackBar(
//     SnackBar(content: Text('Saved "$chosen"')),
//   );
// }

// /// Web-only helper to trigger a file download.
// Future<void> _downloadTextWeb(String text, String fileName) async {
//   final bytes = utf8.encode(text);
//   final blob = html.Blob([bytes], 'application/json;charset=utf-8');
//   final url = html.Url.createObjectUrlFromBlob(blob);
//   final anchor = html.AnchorElement(href: url)
//     ..download = fileName
//     ..style.display = 'none';
//   html.document.body?.children.add(anchor);
//   anchor.click();
//   anchor.remove();
//   html.Url.revokeObjectUrl(url);
// }

// /// Import a single process and return the **raw map** to the callback,
// /// matching existing call sites that mutate the map before building the node.
// /// Accepts:
// /// - a single object at root
// /// - a list with at least one object
// /// - a bundle with `process` or first of `processes`
// void uploadSingleProcessJson(
//   void Function(Map<String, dynamic> processJson) onLoaded,
//   BuildContext context,
// ) {
//   final uploadInput = html.FileUploadInputElement()
//     ..accept = '.json,application/json';
//   uploadInput.click();

//   uploadInput.onChange.listen((_) {
//     final files = uploadInput.files;
//     if (files == null || files.isEmpty) return;

//     final file = files.first;
//     final reader = html.FileReader();

//     reader.onLoadEnd.listen((event) {
//       try {
//         final text = reader.result as String;
//         final dynamic decoded = jsonDecode(text);

//         final Map<String, dynamic>? nodeMap = _extractSingleProcessMap(decoded);

//         if (nodeMap == null) {
//           throw const FormatException('File did not contain a process object');
//         }

//         // Light sanity checks. Keep it non-destructive.
//         _assertOptionalString(nodeMap, 'id');   // may be null, caller generates one
//         _assertOptionalString(nodeMap, 'name'); // warn early if present but wrong type

//         onLoaded(nodeMap);

//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('Process JSON loaded from file')),
//         );
//       } catch (e) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Failed to parse JSON: $e')),
//         );
//       }
//     });

//     reader.readAsText(file);
//   });
// }

// /// Import many processes and return **List<ProcessNode>** to match call sites.
// /// Accepts:
// /// - root list of process maps
// /// - bundle map with a `processes` list
// /// - bundle map with `data` or `items` that is a list
// void uploadProcesses(
//   void Function(List<ProcessNode>) onLoaded,
//   BuildContext context,
// ) {
//   final uploadInput = html.FileUploadInputElement()
//     ..accept = '.json,application/json';
//   uploadInput.click();

//   uploadInput.onChange.listen((_) {
//     final files = uploadInput.files;
//     if (files == null || files.isEmpty) return;

//     final file = files.first;
//     final reader = html.FileReader();

//     reader.onLoadEnd.listen((event) {
//       try {
//         final text = reader.result as String;
//         final dynamic decoded = jsonDecode(text);

//         final List<dynamic> listLike = _extractProcessList(decoded);
//         if (listLike.isEmpty) {
//           throw const FormatException('No processes found in the file');
//         }

//         final loaded = listLike.map<ProcessNode>((item) {
//           if (item is! Map<String, dynamic>) {
//             throw const FormatException('Process entry is not an object');
//           }
//           return ProcessNode.fromJson(item);
//         }).toList();

//         onLoaded(loaded);
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('Processes loaded from file')),
//         );
//       } catch (e) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Failed to parse JSON: $e')),
//         );
//       }
//     });

//     reader.readAsText(file);
//   });
// }

// /// Helpers

// /// Try to get a single process map from any of:
// /// - Map root
// /// - List root (first element)
// /// - Bundle with `process` or first of `processes`
// Map<String, dynamic>? _extractSingleProcessMap(dynamic decoded) {
//   if (decoded is Map<String, dynamic>) {
//     // Direct process object or bundle
//     if (_looksLikeProcess(decoded)) return decoded;

//     // Common bundle keys
//     final dynamic process = decoded['process'];
//     if (process is Map<String, dynamic>) return process;

//     final dynamic processes = decoded['processes'];
//     if (processes is List && processes.isNotEmpty && processes.first is Map<String, dynamic>) {
//       return processes.first as Map<String, dynamic>;
//     }
//     return null;
//   }

//   if (decoded is List && decoded.isNotEmpty) {
//     final first = decoded.first;
//     if (first is Map<String, dynamic>) return first;
//   }

//   return null;
// }

// /// Get a list of process maps from either a root list or a bundle with a list.
// /// Tries `processes`, then `data`, then `items`.
// List<dynamic> _extractProcessList(dynamic decoded) {
//   if (decoded is List) return decoded;

//   if (decoded is Map<String, dynamic>) {
//     final keysInPriority = ['processes', 'data', 'items'];
//     for (final k in keysInPriority) {
//       final v = decoded[k];
//       if (v is List) return v;
//     }
//   }
//   throw const FormatException(
//     'File did not contain a list of processes at the root or under "processes".',
//   );
// }

// /// Very light heuristic to tell a process object from a generic bundle.
// /// Adjust to your real schema if you want stronger validation.
// bool _looksLikeProcess(Map<String, dynamic> m) {
//   final idOk = m['id'] is String && (m['id'] as String).isNotEmpty;
//   final nameOk = m['name'] is String && (m['name'] as String).isNotEmpty;
//   // If it has typical process fields, treat it as a process.
//   final hasInputs = m['inputs'] is List;
//   final hasOutputs = m['outputs'] is List;
//   return idOk || nameOk || hasInputs || hasOutputs;
// }

// /// Warn early if a field is present but of the wrong type.
// /// This does not throw if the field is missing.
// void _assertOptionalString(Map<String, dynamic> m, String key) {
//   if (m.containsKey(key) && m[key] != null && m[key] is! String) {
//     throw FormatException('Invalid "$key" (expected string)');
//   }
// }


// lib/lca/io_utils.dart

import 'dart:convert';
import 'dart:html' as html;

import 'package:earlylca/lca/newhome/lca_models.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


/// Prompts for a filename and downloads the given JSON-able [bundle] (map).
/// Web: triggers a file download.
/// Non-web: shows JSON with Copy button (kept for completeness).
Future<void> promptAndDownloadProjectBundle(
  Map<String, dynamic> bundle,
  BuildContext context, {
  String suggestedFileName = 'lca_project.json',
}) async {
  final fileNameCtrl = TextEditingController(text: suggestedFileName);

  String? chosen;
  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Save project JSON'),
      content: TextField(
        controller: fileNameCtrl,
        decoration: const InputDecoration(
          labelText: 'File name',
          hintText: 'lca_project.json',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            chosen = fileNameCtrl.text.trim().isEmpty
                ? suggestedFileName
                : fileNameCtrl.text.trim();
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );

  if (chosen == null) return;

  final jsonStr = const JsonEncoder.withIndent('  ').convert(bundle);

  if (kIsWeb) {
    await _downloadTextWeb(jsonStr, chosen!);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved "$chosen"')),
    );
    return;
  }

  // Fallback for non-web builds.
  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Project JSON'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 420),
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            child: SelectableText(
              jsonStr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: jsonStr));
            if (Navigator.canPop(context)) Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('JSON copied to clipboard')),
            );
          },
          child: const Text('Copy to clipboard'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// Optional helper to download a plain list of processes as JSON.
Future<void> downloadProcesses(
  List<ProcessNode> processes,
  BuildContext context, {
  String suggestedFileName = 'processes.json',
}) async {
  final fileNameCtrl = TextEditingController(text: suggestedFileName);

  String? chosen;
  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Save processes JSON'),
      content: TextField(
        controller: fileNameCtrl,
        decoration: const InputDecoration(
          labelText: 'File name',
          hintText: 'processes.json',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            chosen = fileNameCtrl.text.trim().isEmpty
                ? suggestedFileName
                : fileNameCtrl.text.trim();
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );

  if (chosen == null) return;

  final jsonStr = const JsonEncoder.withIndent('  ')
      .convert(processes.map((p) => p.toJson()).toList());

  await _downloadTextWeb(jsonStr, chosen!);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Saved "$chosen"')),
  );
}

/// Web-only helper to trigger a file download.
Future<void> _downloadTextWeb(String text, String fileName) async {
  final bytes = utf8.encode(text);
  final blob = html.Blob([bytes], 'application/json;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

/// Import a single process and return the **raw map** to the callback,
/// matching existing call sites that mutate the map before building the node.
/// Accepts:
/// - a single object at root
/// - a list with at least one object
/// - a bundle with `process` or first of `processes`
void uploadSingleProcessJson(
  void Function(Map<String, dynamic> processJson) onLoaded,
  BuildContext context,
) {
  final uploadInput = html.FileUploadInputElement()
    ..accept = '.json,application/json';
  uploadInput.click();

  uploadInput.onChange.listen((_) {
    final files = uploadInput.files;
    if (files == null || files.isEmpty) return;

    final file = files.first;
    final reader = html.FileReader();

    reader.onLoadEnd.listen((event) {
      try {
        final text = reader.result as String;
        final dynamic decoded = jsonDecode(text);

        final Map<String, dynamic>? nodeMap = _extractSingleProcessMap(decoded);

        if (nodeMap == null) {
          throw const FormatException('File did not contain a process object');
        }

        // Light sanity checks. Keep it non-destructive.
        _assertOptionalString(nodeMap, 'id');   // may be null, caller generates one
        _assertOptionalString(nodeMap, 'name'); // warn early if present but wrong type

        onLoaded(nodeMap);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Process JSON loaded from file')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to parse JSON: $e')),
        );
      }
    });

    reader.readAsText(file);
  });
}

/// Import many processes and return **List<ProcessNode>** to match call sites.
/// Accepts:
/// - root list of process maps
/// - bundle map with a `processes` list
/// - bundle map with `data` or `items` that is a list
void uploadProcesses(
  void Function(List<ProcessNode>) onLoaded,
  BuildContext context,
) {
  final uploadInput = html.FileUploadInputElement()
    ..accept = '.json,application/json';
  uploadInput.click();

  uploadInput.onChange.listen((_) {
    final files = uploadInput.files;
    if (files == null || files.isEmpty) return;

    final file = files.first;
    final reader = html.FileReader();

    reader.onLoadEnd.listen((event) {
      try {
        final text = reader.result as String;
        final dynamic decoded = jsonDecode(text);

        final List<dynamic> listLike = _extractProcessList(decoded);
        if (listLike.isEmpty) {
          throw const FormatException('No processes found in the file');
        }

        final loaded = listLike.map<ProcessNode>((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('Process entry is not an object');
          }
          return ProcessNode.fromJson(item);
        }).toList();

        onLoaded(loaded);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Processes loaded from file')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to parse JSON: $e')),
        );
      }
    });

    reader.readAsText(file);
  });
}

/// New: Import a full project bundle and return **both** processes and parameters.
/// This mirrors the save format from `promptAndDownloadProjectBundle`.
/// Accepts:
/// - bundle map with `processes`, optional `global_parameters`, optional `process_parameters`
/// - root list of processes (falls back to empty ParameterSet)
/// - bundle map with processes under `data` or `items`
void uploadProjectBundle(
  void Function(List<ProcessNode> processes, ParameterSet parameters) onLoaded,
  BuildContext context,
) {
  final uploadInput = html.FileUploadInputElement()
    ..accept = '.json,application/json';
  uploadInput.click();

  uploadInput.onChange.listen((_) {
    final files = uploadInput.files;
    if (files == null || files.isEmpty) return;

    final file = files.first;
    final reader = html.FileReader();

    reader.onLoadEnd.listen((event) {
      try {
        final text = reader.result as String;
        final dynamic decoded = jsonDecode(text);

        // Determine process list
        final List<dynamic> processList = _extractProcessList(decoded);

        final processes = processList.map<ProcessNode>((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('Process entry is not an object');
          }
          return ProcessNode.fromJson(item);
        }).toList();

        // Determine parameters if present
        ParameterSet parameters = const ParameterSet();
        if (decoded is Map<String, dynamic>) {
          parameters = _extractParameterSet(decoded);
        }

        onLoaded(processes, parameters);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Project loaded from file')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to parse project JSON: $e')),
        );
      }
    });

    reader.readAsText(file);
  });
}

/// Helpers

/// Try to get a single process map from any of:
/// - Map root
/// - List root (first element)
/// - Bundle with `process` or first of `processes`
Map<String, dynamic>? _extractSingleProcessMap(dynamic decoded) {
  if (decoded is Map<String, dynamic>) {
    // Direct process object or bundle
    if (_looksLikeProcess(decoded)) return decoded;

    // Common bundle keys
    final dynamic process = decoded['process'];
    if (process is Map<String, dynamic>) return process;

    final dynamic processes = decoded['processes'];
    if (processes is List && processes.isNotEmpty && processes.first is Map<String, dynamic>) {
      return processes.first as Map<String, dynamic>;
    }
    return null;
  }

  if (decoded is List && decoded.isNotEmpty) {
    final first = decoded.first;
    if (first is Map<String, dynamic>) return first;
  }

  return null;
}

/// Get a list of process maps from either a root list or a bundle with a list.
/// Tries `processes`, then `data`, then `items`.
List<dynamic> _extractProcessList(dynamic decoded) {
  if (decoded is List) return decoded;

  if (decoded is Map<String, dynamic>) {
    final keysInPriority = ['processes', 'data', 'items'];
    for (final k in keysInPriority) {
      final v = decoded[k];
      if (v is List) return v;
    }
  }
  throw const FormatException(
    'File did not contain a list of processes at the root or under "processes".',
  );
}

/// Very light heuristic to tell a process object from a generic bundle.
/// Adjust to your real schema if you want stronger validation.
bool _looksLikeProcess(Map<String, dynamic> m) {
  final idOk = m['id'] is String && (m['id'] as String).isNotEmpty;
  final nameOk = m['name'] is String && (m['name'] as String).isNotEmpty;
  // If it has typical process fields, treat it as a process.
  final hasInputs = m['inputs'] is List;
  final hasOutputs = m['outputs'] is List;
  return idOk || nameOk || hasInputs || hasOutputs;
}

/// Warn early if a field is present but of the wrong type.
/// This does not throw if the field is missing.
void _assertOptionalString(Map<String, dynamic> m, String key) {
  if (m.containsKey(key) && m[key] != null && m[key] is! String) {
    throw FormatException('Invalid "$key" (expected string)');
  }
}

/// Parse ParameterSet from a bundle map. Missing sections are fine.
ParameterSet _extractParameterSet(Map<String, dynamic> bundle) {
  final globals = <Parameter>[];
  final locals = <String, List<Parameter>>{};

  // Global parameters
  final gp = bundle['global_parameters'];
  if (gp is List) {
    for (final e in gp) {
      final p = _parseParameterObject(e, scope: ParameterScope.global);
      if (p != null) globals.add(p);
    }
  }

  // Per-process parameters
  final pp = bundle['process_parameters'];
  if (pp is Map) {
    for (final entry in pp.entries) {
      final pid = entry.key.toString();
      final list = entry.value;
      if (list is List) {
        final parsed = <Parameter>[];
        for (final e in list) {
          final p = _parseParameterObject(e, scope: ParameterScope.process);
          if (p != null) parsed.add(p);
        }
        if (parsed.isNotEmpty) locals[pid] = parsed;
      }
    }
  }

  return ParameterSet(global: globals, perProcess: locals);
}

/// Convert a loosely typed map into a Parameter.
/// Accepts either a numeric `value` or a string `formula`.
Parameter? _parseParameterObject(
  dynamic raw, {
  required ParameterScope scope,
}) {
  if (raw is! Map) return null;

  final name = raw['name'];
  if (name is! String || name.trim().isEmpty) return null;

  double? numericValue;
  String? formula;

  // value can be int or double
  final v = raw['value'];
  if (v is num) {
    numericValue = v.toDouble();
  } else if (v is String) {
    // If some exporters store numbers as strings, try parsing
    final parsed = double.tryParse(v.trim());
    if (parsed != null) numericValue = parsed;
  }

  // formula takes precedence when non-empty
  final f = raw['formula'];
  if (f is String && f.trim().isNotEmpty) {
    formula = f.trim();
    numericValue = null;
  }

  final unit = raw['unit'] is String ? (raw['unit'] as String) : null;
  final note = raw['note'] is String ? (raw['note'] as String) : null;

  return Parameter(
    name: name.trim(),
    value: numericValue,
    formula: formula,
    scope: scope,
    unit: unit,
    note: note,
  );
}
