// // lib/homescreen/stream_logs_dialog.dart

// import 'dart:async';
// import 'dart:convert';

// import 'package:flutter/material.dart';
// import 'package:web_socket_channel/web_socket_channel.dart';

// /// Pops up and shows streaming LCA logs, then returns the final parsed result when done.
// class StreamLogsDialog extends StatefulWidget {
//   final String prompt;
//   const StreamLogsDialog({Key? key, required this.prompt}) : super(key: key);

//   @override
//   _StreamLogsDialogState createState() => _StreamLogsDialogState();
// }

// class _StreamLogsDialogState extends State<StreamLogsDialog> {
//   late WebSocketChannel _channel;
//   late StreamSubscription _sub;
//   final List<String> _logs = [];
//   final ScrollController _scroll = ScrollController();

//   Map<String, dynamic>? _finalResult;

//   @override
//   void initState() {
//     super.initState();

//     // 1) open websocket
//     _channel = WebSocketChannel.connect(
//       Uri.parse('ws://127.0.0.1:8000/ws/logs'),
//     );

//     // 2) send initial prompt
//     _channel.sink.add(jsonEncode({'prompt': widget.prompt}));

//     // 3) listen for messages
//     _sub = _channel.stream.listen((raw) {
//       final Map<String, dynamic> msg = jsonDecode(raw as String);

//       // Add a human-readable line for every message
//       setState(() {
//         _logs.add('[${msg['type']}] ${jsonEncode(msg['payload'])}');
//       });

//       // Auto-scroll to bottom
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         if (_scroll.hasClients) {
//           _scroll.animateTo(
//             _scroll.position.maxScrollExtent,
//             duration: const Duration(milliseconds: 200),
//             curve: Curves.easeOut,
//           );
//         }
//       });

//       // If it's the final result, capture and close
//       if (msg['type']=='final') {
//   _finalResult = msg['payload'] as Map<String,dynamic>;
//   _closeDialog();
// }

//       if (msg['type'] == 'error') {
//         _closeDialog(); // or handle errors differently
//       }
//     }, onError: (err) {
//       setState(() {
//         _logs.add('[error] $err');
//       });
//     }, onDone: () {
//       // If we get done but no explicit result, close
//       _closeDialog();
//     });
//   }

//   void _closeDialog() {
//     // Give a tiny delay so the final log shows up
//     Future.delayed(const Duration(milliseconds: 200), () {
//       if (mounted) {
//         Navigator.of(context).pop(_finalResult);
//       }
//     });
//   }

//   @override
//   void dispose() {
//     _sub.cancel();
//     _channel.sink.close();
//     _scroll.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return AlertDialog(
//       title: const Text('Running LCA…'),
//       content: SizedBox(
//         width: double.maxFinite,
//         height: 300,
//         child: Scrollbar(
//           controller: _scroll,
//           thumbVisibility: true,
//           child: ListView.builder(
//             controller: _scroll,
//             itemCount: _logs.length,
//             itemBuilder: (_, i) => Text(_logs[i]),
//           ),
//         ),
//       ),
//       actions: [
//         TextButton(
//           onPressed: () => Navigator.of(context).pop(_finalResult),
//           child: const Text('Close'),
//         ),
//       ],
//     );
//   }
// }


// lib/homescreen/stream_logs_dialog.dart
//
// A richer, more engaging WebSocket log viewer for the InstantLCA run.
//

// import 'dart:async';
// import 'dart:convert';

// import 'package:flutter/material.dart';
// import 'package:web_socket_channel/web_socket_channel.dart';

// class StreamLogsDialog extends StatefulWidget {
//   const StreamLogsDialog({super.key, required this.prompt});
//   final String prompt;

//   @override
//   State<StreamLogsDialog> createState() => _StreamLogsDialogState();
// }

// class _StreamLogsDialogState extends State<StreamLogsDialog> {
//   late final WebSocketChannel _channel;
//   late final StreamSubscription _sub;
//   final _scroll = ScrollController();

//   /// Every incoming message as a prettified line.
//   final List<_LogLine> _logLines = [];

//   /// Filled when we receive “result” or “final”.
//   Map<String, dynamic>? _finalResult;

//   /// For the animated header progress bar.
//   double _progress = 0.0;

//   /// Map WebSocket “type” → icon / color
//   static const _style = {
//     'log'    : (Icons.article_outlined, Colors.grey),
//     'chat'   : (Icons.chat_bubble_outline, Colors.blue),
//     'warn'   : (Icons.warning_amber_rounded, Colors.orange),
//     'error'  : (Icons.error_outline, Colors.red),
//     'result' : (Icons.check_circle_outline, Colors.green),
//     'final'  : (Icons.check_circle_outline, Colors.green),
//     'status' : (Icons.info_outline, Colors.teal),
//     'intent' : (Icons.lightbulb_outline, Colors.purple),
//   };

//   @override
//   void initState() {
//     super.initState();

//     // 1️⃣  Open WebSocket
//     _channel = WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:8000/ws/logs'));

//     // 2️⃣  Kick-off
//     _channel.sink.add(jsonEncode({'prompt': widget.prompt}));

//     // 3️⃣  Stream listener
//     _sub = _channel.stream.listen(_onMessage,
//         onError: (err) => _push('error', err.toString()),
//         onDone:  _closeDialog);
//   }

//   // ----------------------------------------------------------------- socket handling
//   void _onMessage(dynamic raw) {
//     final msg = jsonDecode(raw as String) as Map<String, dynamic>;
//     final type = msg['type'] as String? ?? 'log';
//     final payload = msg['payload'];

//     _push(type, payload);

//     // Update progress (dumb heuristic: +4 % per message until 90 %)
//     if (_progress < 0.9) setState(() => _progress += 0.04);

//     if (type == 'result' || type == 'final') {
//       _finalResult = payload as Map<String, dynamic>;
//       _progress    = 1.0;
//       _closeDialog();
//     }
//   }

//   void _push(String type, dynamic payload) {
//     setState(() {
//       _logLines.add(_LogLine(type, jsonEncode(payload)));
//       // auto-scroll
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         if (_scroll.hasClients) {
//           _scroll.animateTo(
//             _scroll.position.maxScrollExtent,
//             duration: const Duration(milliseconds: 250),
//             curve: Curves.easeOut,
//           );
//         }
//       });
//     });
//   }

//   void _closeDialog() {
//     // give the UI a breath so last line & progress bar paint
//     Future.delayed(const Duration(milliseconds: 200), () {
//       if (mounted) Navigator.of(context).pop(_finalResult);
//     });
//   }

//   // ----------------------------------------------------------------- lifecycle
//   @override
//   void dispose() {
//     _sub.cancel();
//     _channel.sink.close();
//     _scroll.dispose();
//     super.dispose();
//   }

//   // ----------------------------------------------------------------- UI
//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     return Dialog(
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//       insetPadding: const EdgeInsets.all(24),
//       child: ConstrainedBox(
//         constraints: const BoxConstraints(maxWidth: 600, maxHeight: 520),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             // ---------------------------------------------------------- header
//             Padding(
//               padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
//               child: Row(
//                 children: [
//                   const Icon(Icons.autorenew, size: 26, color: Colors.green),
//                   const SizedBox(width: 8),
//                   Expanded(
//                     child: Text('Running Life-Cycle Analysis…',
//                         style: theme.textTheme.titleMedium?.copyWith(
//                           fontWeight: FontWeight.bold,
//                         )),
//                   ),
//                   IconButton(
//                     tooltip: 'Close',
//                     icon: const Icon(Icons.close),
//                     onPressed: () => Navigator.of(context).pop(_finalResult),
//                   )
//                 ],
//               ),
//             ),
//             // progress bar
//             AnimatedContainer(
//               duration: const Duration(milliseconds: 300),
//               curve: Curves.easeInOut,
//               margin: const EdgeInsets.symmetric(horizontal: 20),
//               height: 6,
//               width: double.infinity,
//               decoration: BoxDecoration(
//                 color: theme.colorScheme.surfaceVariant,
//                 borderRadius: BorderRadius.circular(3),
//               ),
//               child: Align(
//                 alignment: Alignment.centerLeft,
//                 child: FractionallySizedBox(
//                   widthFactor: _progress.clamp(0.02, 1.0),
//                   child: Container(
//                     decoration: BoxDecoration(
//                       color: Colors.greenAccent.shade400,
//                       borderRadius: BorderRadius.circular(3),
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//             const SizedBox(height: 10),

//             // ---------------------------------------------------------- log console
//             Expanded(
//               child: Scrollbar(
//                 controller: _scroll,
//                 thumbVisibility: true,
//                 radius: const Radius.circular(8),
//                 child: ListView.builder(
//                   controller: _scroll,
//                   itemCount: _logLines.length,
//                   itemBuilder: (_, i) {
//                     final ll = _logLines[i];
//                     final (icon, color) = _style[ll.type] ??
//                         (Icons.article_outlined, Colors.grey);
//                     return Padding(
//                       padding:
//                           const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
//                       child: Row(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Icon(icon, size: 18, color: color),
//                           const SizedBox(width: 8),
//                           Expanded(
//                             child: SelectableText(
//                               ll.text,
//                               style: TextStyle(
//                                 fontFamily: 'FiraCode',
//                                 fontSize: 13,
//                                 height: 1.35,
//                                 color: color,
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                     );
//                   },
//                 ),
//               ),
//             ),

//             // ---------------------------------------------------------- actions
//             Padding(
//               padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
//               child: Row(
//                 children: [
//                   TextButton.icon(
//                     onPressed: () =>
//                         Navigator.of(context).pop(_finalResult),
//                     icon: const Icon(Icons.check),
//                     label: const Text('Done'),
//                   ),
//                   const Spacer(),
//                   Text('${_logLines.length} messages',
//                       style: theme.textTheme.bodySmall
//                           ?.copyWith(color: Colors.grey)),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// // =================================================================== helper
// class _LogLine {
//   const _LogLine(this.type, this.text);
//   final String type;
//   final String text;
// }

// lib/homescreen/stream_logs_dialog.dart
// lib/homescreen/stream_logs_dialog.dart
// lib/homescreen/stream_logs_dialog.dart
// lib/homescreen/stream_logs_dialog.dart

// import 'dart:async';
// import 'dart:convert';

// import 'package:flutter/material.dart';
// import 'package:web_socket_channel/web_socket_channel.dart';

// /// A sleek streaming console for your LCA pipeline, with
// /// clean key:value rendering instead of raw JSON.
// class StreamLogsDialog extends StatefulWidget {
//   const StreamLogsDialog({super.key, required this.prompt});
//   final String prompt;

//   @override
//   State<StreamLogsDialog> createState() => _StreamLogsDialogState();
// }

// class _StreamLogsDialogState extends State<StreamLogsDialog> {
//   late final WebSocketChannel _channel;
//   late final StreamSubscription _sub;
//   final ScrollController _scroll = ScrollController();

//   double _progress = 0.0;
//   final List<_LogLine> _lines = [];
//   Map<String, dynamic>? _finalResult;

//   static const Color _accent = Color(0xFF2E7D32);
//   static const Color _logGrey = Colors.black87;

//   /// Icon + color per message type
//   static const _styles = {
//     'log'    : (Icons.circle, _logGrey),
//     'intent' : (Icons.lightbulb_outline, Colors.purple),
//     'chat'   : (Icons.chat_bubble_outline, Colors.blue),
//     'warn'   : (Icons.warning_amber_rounded, Colors.orange),
//     'error'  : (Icons.error_outline, Colors.red),
//     'result' : (Icons.check_circle_outline, _accent),
//     'final'  : (Icons.check_circle, _accent),
//     'status' : (Icons.info_outline, Colors.teal),
//   };

//   @override
//   void initState() {
//     super.initState();
//     _channel = WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:8000/ws/logs'));
//     _channel.sink.add(jsonEncode({'prompt': widget.prompt}));
//     _sub = _channel.stream.listen(
//       _handleMessage,
//       onDone:   _closeDialog,
//       onError:  (e) {
//         _addLine('error', e.toString());
//         _closeDialog();
//       },
//     );
//   }

//   void _handleMessage(dynamic raw) {
//     final msg = jsonDecode(raw as String) as Map<String, dynamic>;
//     final type = msg['type'] as String? ?? 'log';
//     final payload = msg['payload'];

//     _addLine(type, payload);

//     if (_progress < 0.9) setState(() => _progress += 0.06);

//     if (type == 'result' || type == 'final') {
//       // capture final map safely
//       if (payload is Map) {
//         _finalResult = Map<String, dynamic>.from(payload);
//       }
//       setState(() => _progress = 1.0);
//       _closeDialog();
//     }
//   }

//   void _addLine(String type, dynamic payload) {
//     final time = _formatTime(DateTime.now());
//     setState(() {
//       _lines.add(_LogLine(type, payload, time));
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         _scroll.hasClients
//             ? _scroll.jumpTo(_scroll.position.maxScrollExtent)
//             : null;
//       });
//     });
//   }

//   String _formatTime(DateTime dt) {
//     String two(int v) => v.toString().padLeft(2, '0');
//     return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
//   }

//   void _closeDialog() {
//     Future.delayed(const Duration(milliseconds: 200), () {
//       if (mounted) Navigator.of(context).pop(_finalResult);
//     });
//   }

//   @override
//   void dispose() {
//     _sub.cancel();
//     _channel.sink.close();
//     _scroll.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Dialog(
//       insetPadding: const EdgeInsets.all(24),
//       backgroundColor: Colors.white,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//       child: SizedBox(
//         width: 600,
//         height: 520,
//         child: Column(
//           children: [
//             // Header
//             Container(
//               padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
//               decoration: const BoxDecoration(
//                 color: _accent,
//                 borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
//               ),
//               child: Row(
//                 children: [
//                   const Icon(Icons.autorenew, color: Colors.white),
//                   const SizedBox(width: 12),
//                   Expanded(
//                     child: Text(
//                       'Life-Cycle Analysis',
//                       style: const TextStyle(
//                           color: Colors.white,
//                           fontSize: 20,
//                           fontWeight: FontWeight.bold),
//                     ),
//                   ),
//                   IconButton(
//                     icon: const Icon(Icons.close, color: Colors.white),
//                     onPressed: () => Navigator.of(context).pop(_finalResult),
//                   ),
//                 ],
//               ),
//             ),

//             // Progress bar
//             LinearProgressIndicator(
//               value: _progress,
//               backgroundColor: Colors.grey.shade200,
//               color: Colors.greenAccent.shade400,
//               minHeight: 6,
//             ),

//             // Console
//             Expanded(
//               child: Padding(
//                 padding: const EdgeInsets.all(16),
//                 child: Container(
//                   decoration: BoxDecoration(
//                     color: Colors.grey.shade50,
//                     borderRadius: BorderRadius.circular(8),
//                   ),
//                   child: Scrollbar(
//                     controller: _scroll,
//                     thumbVisibility: true,
//                     child: ListView.builder(
//                       controller: _scroll,
//                       padding: const EdgeInsets.all(12),
//                       itemCount: _lines.length,
//                       itemBuilder: (_, i) {
//                         final line = _lines[i];
//                         final style = _styles[line.type] ??
//                             (Icons.brightness_1, _logGrey);
//                         final icon = style.$1;
//                         final color = style.$2;
//                         final typeLabel = line.type[0].toUpperCase() +
//                             line.type.substring(1);

//                         return Padding(
//                           padding: const EdgeInsets.symmetric(vertical: 6),
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               // timestamp + icon + label
//                               Row(
//                                 children: [
//                                   Text(
//                                     line.time,
//                                     style: const TextStyle(
//                                         fontSize: 12, color: Colors.grey),
//                                   ),
//                                   const SizedBox(width: 8),
//                                   Icon(icon, size: 16, color: color),
//                                   const SizedBox(width: 6),
//                                   Text(
//                                     typeLabel,
//                                     style: TextStyle(
//                                         fontWeight: FontWeight.bold,
//                                         color: color),
//                                   ),
//                                 ],
//                               ),
//                               const SizedBox(height: 4),

//                               // payload
//                               ..._renderPayload(line.payload),
//                             ],
//                           ),
//                         );
//                       },
//                     ),
//                   ),
//                 ),
//               ),
//             ),

//             // Footer
//             Container(
//               padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
//               child: Row(
//                 children: [
//                   TextButton.icon(
//                     icon: const Icon(Icons.check, color: _accent),
//                     label: const Text(
//                       'Done',
//                       style: TextStyle(color: _accent),
//                     ),
//                     onPressed: () => Navigator.of(context).pop(_finalResult),
//                   ),
//                   const Spacer(),
//                   Text(
//                     '${_lines.length} messages',
//                     style: const TextStyle(color: Colors.grey, fontSize: 12),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   /// Render any payload as a clean key: value list (no braces).
//   List<Widget> _renderPayload(dynamic data, {double indent = 24}) {
//     final List<Widget> out = [];

//     if (data is Map) {
//       data.forEach((key, val) {
//         if (val is Map || val is Iterable) {
//           // key header
//           out.add(Padding(
//             padding: EdgeInsets.only(left: indent, bottom: 2),
//             child: Text(
//               '$key:',
//               style: const TextStyle(
//                   fontFamily: 'RobotoMono',
//                   fontSize: 14,
//                   fontWeight: FontWeight.bold,
//                   color: _logGrey),
//             ),
//           ));
//           // nested payload
//           out.addAll(_renderPayload(val, indent: indent + 16));
//         } else {
//           out.add(Padding(
//             padding: EdgeInsets.only(left: indent, bottom: 2),
//             child: RichText(
//               text: TextSpan(
//                 style: const TextStyle(
//                     fontFamily: 'RobotoMono',
//                     fontSize: 14,
//                     color: _logGrey),
//                 children: [
//                   TextSpan(
//                       text: '$key: ',
//                       style: const TextStyle(fontWeight: FontWeight.bold)),
//                   TextSpan(text: val.toString()),
//                 ],
//               ),
//             ),
//           ));
//         }
//       });
//     } else if (data is Iterable) {
//       if (data.isEmpty) {
//         out.add(Padding(
//           padding: EdgeInsets.only(left: indent),
//           child: const Text('– (empty)',
//               style: TextStyle(fontFamily: 'RobotoMono', fontSize: 14)),
//         ));
//       } else if (data.every((e) => e is Map)) {
//         int idx = 1;
//         for (var entry in data.cast<Map>()) {
//           out.add(Padding(
//             padding: EdgeInsets.only(left: indent, bottom: 2),
//             child: Text(
//               '• item $idx:',
//               style: const TextStyle(
//                   fontFamily: 'RobotoMono',
//                   fontSize: 14,
//                   fontWeight: FontWeight.bold,
//                   color: _logGrey),
//             ),
//           ));
//           out.addAll(_renderPayload(entry, indent: indent + 16));
//           idx++;
//         }
//       } else {
//         // flat list
//         out.add(Padding(
//           padding: EdgeInsets.only(left: indent, bottom: 2),
//           child: Text(
//             data.map((e) => e.toString()).join(', '),
//             style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 14),
//           ),
//         ));
//       }
//     } else {
//       // scalar
//       out.add(Padding(
//         padding: EdgeInsets.only(left: indent, bottom: 2),
//         child: Text(
//           data.toString(),
//           style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 14),
//         ),
//       ));
//     }

//     return out;
//   }
// }

// /// Simple model for a console line
// class _LogLine {
//   _LogLine(this.type, this.payload, this.time);
//   final String type;
//   final dynamic payload;
//   final String time;
// }
// lib/homescreen/stream_logs_dialog.dart


// // lib/homescreen/stream_logs_dialog.dart

// import 'dart:async';
// import 'dart:convert';

// import 'package:flutter/material.dart';
// import 'package:web_socket_channel/web_socket_channel.dart';

// /// A sleek streaming console for your LCA pipeline, with
// /// clean key:value rendering instead of raw JSON.
// class StreamLogsDialog extends StatefulWidget {
//   const StreamLogsDialog({super.key, required this.prompt});
//   final String prompt;

//   @override
//   State<StreamLogsDialog> createState() => _StreamLogsDialogState();
// }

// class _StreamLogsDialogState extends State<StreamLogsDialog> {
//   late final WebSocketChannel _channel;
//   late final StreamSubscription _sub;
//   final ScrollController _scroll = ScrollController();

//   double _progress = 0.0;
//   final List<_LogLine> _lines = [];
//   dynamic _finalPayload;
//   bool _gotFinal = false; // guard to ensure we only pop on actual "final"

//   static const Color _accent = Color(0xFF2E7D32);
//   static const Color _logGrey = Colors.black87;

//   /// Icon + color per message type
//   static const _styles = {
//     'log'    : (Icons.circle, _logGrey),
//     'intent' : (Icons.lightbulb_outline, Colors.purple),
//     'chat'   : (Icons.chat_bubble_outline, Colors.blue),
//     'warn'   : (Icons.warning_amber_rounded, Colors.orange),
//     'error'  : (Icons.error_outline, Colors.red),
//     'result' : (Icons.check_circle_outline, _accent),
//     'final'  : (Icons.check_circle, _accent),
//     'status' : (Icons.info_outline, Colors.teal),
//   };

//   @override
//   void initState() {
//     super.initState();
//     _channel = WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:8000/ws/logs'));
//     _channel.sink.add(jsonEncode({'prompt': widget.prompt}));

//     _sub = _channel.stream.listen(
//       _handleMessage,
//       onError: (e) {
//         _addLine('error', e.toString());
//         if (!_gotFinal) _closeDialog();
//       },
//       onDone: () {
//         // ignore automatic pop on done—only pop when we see "final"
//       },
//     );
//   }

//   void _handleMessage(dynamic raw) {
//     final msg = jsonDecode(raw as String) as Map<String, dynamic>;
//     final type = msg['type'] as String? ?? 'log';
//     final payload = msg['payload'];

//     _addLine(type, payload);

//     // advance progress up to 90%
//     if (_progress < 0.9) setState(() => _progress += 0.06);

//     // only close on explicit "final"
//     if (type == 'final') {
//       _gotFinal = true;
//       _finalPayload = payload;
//       setState(() => _progress = 1.0);
//       _closeDialog();
//     }
//   }

//   void _addLine(String type, dynamic payload) {
//     final time = _formatTimestamp(DateTime.now());
//     setState(() {
//       _lines.add(_LogLine(type, payload, time));
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         if (_scroll.hasClients) {
//           _scroll.jumpTo(_scroll.position.maxScrollExtent);
//         }
//       });
//     });
//   }

//   String _formatTimestamp(DateTime dt) {
//     String two(int v) => v.toString().padLeft(2, '0');
//     return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
//   }

//   void _closeDialog() {
//     if (_gotFinal && mounted) {
//       Future.delayed(const Duration(milliseconds: 200), () {
//         if (mounted) Navigator.of(context).pop(_finalPayload);
//       });
//     }
//   }

//   @override
//   void dispose() {
//     _sub.cancel();
//     _channel.sink.close();
//     _scroll.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Dialog(
//       insetPadding: const EdgeInsets.all(24),
//       backgroundColor: Colors.white,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//       child: SizedBox(
//         width: 600,
//         height: 520,
//         child: Column(
//           children: [
//             _buildHeader(),
//             LinearProgressIndicator(
//               value: _progress,
//               backgroundColor: Colors.grey.shade200,
//               color: Colors.greenAccent.shade400,
//               minHeight: 6,
//             ),
//             Expanded(child: _buildConsole()),
//             _buildFooter(context),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildHeader() {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
//       decoration: const BoxDecoration(
//         color: _accent,
//         borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
//       ),
//       child: Row(
//         children: [
//           const Icon(Icons.autorenew, color: Colors.white),
//           const SizedBox(width: 12),
//           const Expanded(
//             child: Text(
//               'Life-Cycle Analysis',
//               style: TextStyle(
//                   color: Colors.white,
//                   fontSize: 20,
//                   fontWeight: FontWeight.bold),
//             ),
//           ),
//           IconButton(
//             icon: const Icon(Icons.close, color: Colors.white),
//             onPressed: () => Navigator.of(context).pop(_finalPayload),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildConsole() {
//     return Padding(
//       padding: const EdgeInsets.all(16),
//       child: Container(
//         decoration: BoxDecoration(
//           color: Colors.grey.shade50,
//           borderRadius: BorderRadius.circular(8),
//         ),
//         child: Scrollbar(
//           controller: _scroll,
//           thumbVisibility: true,
//           child: ListView.builder(
//             controller: _scroll,
//             padding: const EdgeInsets.all(12),
//             itemCount: _lines.length,
//             itemBuilder: (_, i) => _buildLine(_lines[i]),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildLine(_LogLine line) {
//     final (icon, color) = _styles[line.type] ?? (Icons.brightness_1, _logGrey);
//     final label = line.type[0].toUpperCase() + line.type.substring(1);

//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 6),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Text(line.timestamp,
//                   style: const TextStyle(fontSize: 12, color: Colors.grey)),
//               const SizedBox(width: 8),
//               Icon(icon, size: 16, color: color),
//               const SizedBox(width: 6),
//               Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
//             ],
//           ),
//           const SizedBox(height: 4),
//           ..._renderPayload(line.payload),
//         ],
//       ),
//     );
//   }

//   List<Widget> _renderPayload(dynamic data, {double indent = 24}) {
//     final widgets = <Widget>[];

//     if (data is Map) {
//       for (final entry in data.entries) {
//         final key = entry.key;
//         final val = entry.value;
//         widgets.add(Padding(
//           padding: EdgeInsets.only(left: indent, bottom: 2),
//           child: Text.rich(TextSpan(
//             style: const TextStyle(
//                 fontFamily: 'RobotoMono', fontSize: 14, color: _logGrey),
//             children: [
//               TextSpan(text: '$key: ', style: const TextStyle(fontWeight: FontWeight.bold)),
//               if (val is! Map && val is! Iterable) TextSpan(text: val.toString()),
//             ],
//           )),
//         ));
//         if (val is Map || val is Iterable) {
//           widgets.addAll(_renderPayload(val, indent: indent + 16));
//         }
//       }
//     } else if (data is Iterable) {
//       if (data.every((e) => e is Map)) {
//         var idx = 1;
//         for (final item in data.cast<Map>()) {
//           widgets.add(Padding(
//             padding: EdgeInsets.only(left: indent, bottom: 2),
//             child: Text('• item $idx:',
//                 style: const TextStyle(
//                     fontFamily: 'RobotoMono',
//                     fontSize: 14,
//                     fontWeight: FontWeight.bold,
//                     color: _logGrey)),
//           ));
//           widgets.addAll(_renderPayload(item, indent: indent + 16));
//           idx++;
//         }
//       } else {
//         widgets.add(Padding(
//           padding: EdgeInsets.only(left: indent, bottom: 2),
//           child: Text(
//             data.map((e) => e.toString()).join(', '),
//             style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 14),
//           ),
//         ));
//       }
//     } else {
//       widgets.add(Padding(
//         padding: EdgeInsets.only(left: indent, bottom: 2),
//         child: Text(data.toString(),
//             style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 14)),
//       ));
//     }

//     return widgets;
//   }

//   Widget _buildFooter(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
//       child: Row(
//         children: [
//           TextButton.icon(
//             icon: const Icon(Icons.check, color: _accent),
//             label: const Text('Done', style: TextStyle(color: _accent)),
//             onPressed: () => Navigator.of(context).pop(_finalPayload),
//           ),
//           const Spacer(),
//           Text('${_lines.length} messages',
//               style: const TextStyle(color: Colors.grey, fontSize: 12)),
//         ],
//       ),
//     );
//   }
// }

// /// Simple model for a console line
// class _LogLine {
//   _LogLine(this.type, this.payload, this.timestamp);
//   final String type;
//   final dynamic payload;
//   final String timestamp;
// }


// lib/homescreen/stream_logs_dialog.dart
// lib/homescreen/stream_logs_dialog.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A streaming console for LCA with debugging prints at every step.
class StreamLogsDialog extends StatefulWidget {
  const StreamLogsDialog({super.key, required this.prompt});
  final String prompt;

  @override
  State<StreamLogsDialog> createState() => _StreamLogsDialogState();
}

class _StreamLogsDialogState extends State<StreamLogsDialog> {
  late final WebSocketChannel _channel;
  late final StreamSubscription _sub;
  final ScrollController _scroll = ScrollController();
  List<Map<String, dynamic>>? _flowsEnriched;

  double _progress = 0.0;
  final List<_LogLine> _lines = [];
  dynamic _finalPayload;
  bool _gotFinal = false; // only pop on real "final"

  static const Color _accent = Color(0xFF2E7D32);
  static const Color _logGrey = Colors.black87;

  static const Map<String, (IconData, Color)> _styles = {
    'log'    : (Icons.circle, _logGrey),
    'intent' : (Icons.lightbulb_outline, Colors.purple),
    'chat'   : (Icons.chat_bubble_outline, Colors.blue),
    'warn'   : (Icons.warning_amber_rounded, Colors.orange),
    'error'  : (Icons.error_outline, Colors.red),
    'result' : (Icons.check_circle_outline, _accent),
    'final'  : (Icons.check_circle, _accent),
    'status' : (Icons.info_outline, Colors.teal),
  };

  @override
  void initState() {
    super.initState();
    debugPrint('🔌 [StreamLogsDialog] initState: connecting to WS wss://instantlca.onrender.com/ws/logs');
_channel = WebSocketChannel.connect(
  Uri.parse('wss://instantlca.duckdns.org/ws/logs'),
);

    _channel.stream.handleError((e) => debugPrint('🚨 [WS Stream Error] $e'));
    debugPrint('➡️ [WS] sending init prompt: "${widget.prompt}"');
    _channel.sink.add(jsonEncode({'prompt': widget.prompt}));



_sub = _channel.stream.listen(
  _handleMessage,
  onError: (e) {
    debugPrint('🚨 [WS onError] $e');
    _addLine('error', e.toString());
    // Immediately pop the dialog with `null`, so the caller can fall back to HTTP
    if (mounted) {
      Navigator.of(context).pop(null);
    }
  },
  onDone: () {
    debugPrint('🔒 [WS onDone] connection closed by server');
    // No pop here; final pop comes from _handleMessage on 'final'
  },
  cancelOnError: true,
);
 
  }

void _handleMessage(dynamic raw) {
  final msg = jsonDecode(raw as String) as Map<String, dynamic>;
  final type = msg['type'] as String;
  final payload = msg['payload'];

  // 1) Always add to the console
  _addLine(type, payload);

  // 2) Capture `flows_enriched` when it arrives:
  if (type == 'flows_enriched') {
    _flowsEnriched = (payload as List)
        .cast<Map<String, dynamic>>();
    return;
  }

  // 3) When we get "final", merge in those enriched flows:
  if (type == 'final') {
    final base = payload as Map<String, dynamic>;
    if (_flowsEnriched != null) {
      base['flows_enriched'] = _flowsEnriched;
    }
    _finalPayload = base;
    _gotFinal = true;
    setState(() => _progress = 1.0);
    _closeDialog();
    return;
  }

  // 4) Your existing error / progress / done logic continues here…
}


  void _addLine(String type, dynamic payload) {
    final ts = _formatTimestamp(DateTime.now());
    debugPrint('📋 [addLine] $ts [$type] $payload');
    setState(() {
      _lines.add(_LogLine(type, payload, ts));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    });
  }

  String _formatTimestamp(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  void _closeDialog() {
    if (_gotFinal && mounted) {
      debugPrint('🚪 [closeDialog] will pop after delay');
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          debugPrint('🏁 [Navigator.pop] payload type=${_finalPayload.runtimeType}');
          Navigator.of(context).pop(_finalPayload);
        }
      });
    } else {
      debugPrint('⚠️ [closeDialog] skipped: gotFinal=$_gotFinal, mounted=$mounted');
    }
  }

  @override
  void dispose() {
    debugPrint('🗑 [dispose] cancelling subscription & closing WS');
    _sub.cancel();
    _channel.sink.close();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 600,
        height: 520,
        child: Column(
          children: [
            _buildHeader(),
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.grey.shade200,
              color: Colors.greenAccent.shade400,
              minHeight: 6,
            ),
            Expanded(child: _buildConsole()),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: _accent,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.autorenew, color: Colors.white),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Life-Cycle Analysis',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () {
              debugPrint('❌ [Close button] popping dialog');
              Navigator.of(context).pop(_finalPayload);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConsole() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: _lines.length,
            itemBuilder: (_, i) => _buildLine(_lines[i]),
          ),
        ),
      ),
    );
  }

  Widget _buildLine(_LogLine line) {
    final style = _styles[line.type] ?? (Icons.brightness_1, _logGrey);
    final icon = style.$1;
    final color = style.$2;
    final label = line.type[0].toUpperCase() + line.type.substring(1);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(line.timestamp,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(width: 8),
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          ..._renderPayload(line.payload),
        ],
      ),
    );
  }

  List<Widget> _renderPayload(dynamic data, {double indent = 24}) {
    final widgets = <Widget>[];

    if (data is Map) {
      data.forEach((key, val) {
        widgets.add(Padding(
          padding: EdgeInsets.only(left: indent, bottom: 2),
          child: Text.rich(TextSpan(
            style: const TextStyle(
                fontFamily: 'RobotoMono', fontSize: 14, color: _logGrey),
            children: [
              TextSpan(
                  text: '$key: ',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (val is! Map && val is! Iterable) TextSpan(text: val.toString()),
            ],
          )),
        ));
        if (val is Map || val is Iterable) {
          widgets.addAll(_renderPayload(val, indent: indent + 16));
        }
      });
    } else if (data is Iterable) {
      if (data.every((e) => e is Map)) {
        var idx = 1;
        for (final item in data.cast<Map>()) {
          widgets.add(Padding(
            padding: EdgeInsets.only(left: indent, bottom: 2),
            child: Text('• item $idx:',
                style: const TextStyle(
                    fontFamily: 'RobotoMono',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _logGrey)),
          ));
          widgets.addAll(_renderPayload(item, indent: indent + 16));
          idx++;
        }
      } else {
        widgets.add(Padding(
          padding: EdgeInsets.only(left: indent, bottom: 2),
          child: Text(
            data.map((e) => e.toString()).join(', '),
            style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 14),
          ),
        ));
      }
    } else {
      widgets.add(Padding(
        padding: EdgeInsets.only(left: indent, bottom: 2),
        child: Text(data.toString(),
            style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 14)),
      ));
    }

    return widgets;
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          TextButton.icon(
            icon: const Icon(Icons.check, color: _accent),
            label: const Text('Cancel/Close', style: TextStyle(color: _accent)),
            onPressed: () {
              debugPrint('✅ [Done button] popping dialog');
              Navigator.of(context).pop(_finalPayload);
            },
          ),
          const Spacer(),
          Text('${_lines.length} messages',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Model for each log line.
class _LogLine {
  _LogLine(this.type, this.payload, this.timestamp);
  final String type;
  final dynamic payload;
  final String timestamp;
}
