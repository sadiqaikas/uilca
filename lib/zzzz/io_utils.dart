// lib/io_utils.dart
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'home.dart'; // for ProcessNode and FlowValue

/// Prompts the user for a filename, then triggers a download of the given
/// list of ProcessNode as JSON. Shows a SnackBar on completion.
Future<void> promptAndDownloadProcesses(
    List<ProcessNode> processes, BuildContext context) async {
  final controller = TextEditingController(text: 'processes.json');

  final filename = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text('Save As', style: TextStyle(fontSize: 20)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Filename',
            hintText: 'e.g. my_model.json',
          ),
          autofocus: true,
          style: TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: TextStyle(fontSize: 16)),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            child: Text('Save', style: TextStyle(fontSize: 16)),
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.pop(context, name);
            },
          ),
        ],
      );
    },
  );

  if (filename == null) return;

  final jsonList = processes.map((p) => p.toJson()).toList();
  final bytes = utf8.encode(jsonEncode(jsonList));
  final blob = html.Blob([bytes], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.document.createElement('a') as html.AnchorElement
    ..href = url
    ..download = filename;
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Downloaded as "$filename"')),
  );
}

/// Opens a file‐picker, reads the selected JSON file, parses it into a
/// List<ProcessNode>, and invokes [onLoaded] with that list. Shows a SnackBar
/// upon success or failure.
void uploadProcesses(
    void Function(List<ProcessNode>) onLoaded, BuildContext context) {
  final uploadInput = html.FileUploadInputElement()..accept = '.json';
  uploadInput.click();

  uploadInput.onChange.listen((_) {
    final files = uploadInput.files;
    if (files == null || files.isEmpty) return;

    final file = files.first;
    final reader = html.FileReader();

    reader.onLoadEnd.listen((event) {
      try {
        final text = reader.result as String;
        final List<dynamic> jsonList = jsonDecode(text);
        final loaded = jsonList
            .map((item) => ProcessNode.fromJson(item as Map<String, dynamic>))
            .toList();
        onLoaded(loaded);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Processes loaded from file.')),
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
