// import 'package:flutter/material.dart';

// import '../api/apicall.dart';
// import 'progress.dart';

// class LCATextField extends StatefulWidget {
//   final TextEditingController textController;
//   const LCATextField({super.key, required this.textController});

//   @override
//   State<LCATextField> createState() => _LCATextFieldState();
// }

// class _LCATextFieldState extends State<LCATextField> {
//   final ScrollController _scrollController = ScrollController();

//   void _analyzeProcess() async {
//     final userInput = widget.textController.text.trim();

//     if (userInput.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Please describe your process first!')),
//       );
//       return;
//     }

//     // Show loading dialog
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (_) => const ProgressDialog(),
//     );
//     final result = await runLCARequest(userInput);

//     Navigator.pop(context); // Hide loading

//     if (result == null) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//             content: Text(
//                 'Something went wrong. Check your network and Please try again.')),
//       );
//       return;
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(24, 24, 12, 24),
//       child: Card(
//         color: Colors.white,
//         elevation: 10,
//         shadowColor: Colors.blueGrey.withOpacity(0.1),
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
//         child: Padding(
//           padding: const EdgeInsets.all(24),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.stretch,
//             children: [
//               Row(
//                 children: [
//                   Icon(Icons.eco, color: Colors.green.shade600, size: 26),
//                   const SizedBox(width: 8),
//                   Flexible(
//                     child: FittedBox(
//                       fit: BoxFit.scaleDown,
//                       child: Text(
//                         'Describe Your LCA Scenario',
//                         style: const TextStyle(
//                           fontWeight: FontWeight.bold,
//                           fontSize: 24, // Can adjust this if needed
//                           color: Colors.green,
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),

//               const SizedBox(height: 8),
//               Text(
//                 "Describe your process in plain English. Add any details you think matter — we’ll figure it out.",
//                 style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
//               ),
//               const SizedBox(height: 16),
//               // Scrollable TextField with improved placeholder
//               Expanded(
//                 child: Scrollbar(
//                   controller: _scrollController,
//                   thumbVisibility: true,
//                   child: TextField(
//                     controller: widget.textController,
//                     scrollController: _scrollController,
//                     expands: true,
//                     maxLines: null,
//                     style: const TextStyle(fontSize: 16, height: 1.4),
//                     decoration: InputDecoration(
//                       hintText: 'Example:\n'
//                           '“I’m comparing two bottle types:\n'
//                           '- Glass bottles, 500 ml, made using natural gas, transported 200km by truck.\n'
//                           '- Plastic PET bottles, same volume, made from recycled PET, electric production, shipped 50km.”',
//                       hintStyle:
//                           TextStyle(color: Colors.grey.shade500, fontSize: 15),
//                       border: OutlineInputBorder(
//                         borderRadius: BorderRadius.circular(12),
//                         borderSide: BorderSide(color: Colors.grey.shade300),
//                       ),
//                       focusedBorder: OutlineInputBorder(
//                         borderRadius: BorderRadius.circular(12),
//                         borderSide: BorderSide(
//                             color: Colors.green.shade600, width: 1.5),
//                       ),
//                       helperText:
//                           '💡 Tip: Feel free to compare multiple scenarios!',
//                       helperStyle: TextStyle(color: Colors.green.shade700),
//                     ),
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 16),
//               // Analyze button, visually appealing and friendly
//               SizedBox(
//                 width: double.infinity,
//                 child: ElevatedButton.icon(
//                   onPressed: _analyzeProcess,
//                   icon: const Icon(Icons.play_circle_fill, size: 24),
//                   label: const Text(
//                     'Run LCA Analysis',
//                     style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
//                   ),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.green.shade600,
//                     foregroundColor: Colors.white,
//                     padding: const EdgeInsets.symmetric(vertical: 14),
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(12),
//                     ),
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



// import 'dart:convert';
// import 'package:earlylca/api/apicall.dart';
// import 'package:earlylca/homescreen/graphview.dart';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
// import 'progress.dart';
// import 'package:web_socket_channel/io.dart';

// Future<void> streamLCA(String prompt) async {
//   final channel = IOWebSocketChannel.connect('ws://192.168.43.15:8000/ws/logs');

//   // Send the initial prompt
//   channel.sink.add(jsonEncode({'prompt': prompt}));

//   // Listen for streaming JSON messages
//   channel.stream.listen((rawMessage) {
//     final msg = jsonDecode(rawMessage as String) as Map<String, dynamic>;

//     switch (msg['type']) {
//       case 'log':
//         print('LOG ▶︎ ${msg['payload']}');
//         break;
//       case 'intent':
//         print('INTENT ▶︎ ${msg['payload']}');
//         break;
//       case 'processes':
//         print('PROCESSES ▶︎ ${msg['payload']}');
//         break;
//       case 'f_matrix':
//       case 'A_matrix':
//       case 'h_vector':
//         print('${msg['type']} ▶︎ ${jsonEncode(msg['payload'])}');
//         break;
//       case 'result':
//         print('FINAL RESULT ▶︎ ${jsonEncode(msg['payload'])}');
//         break;
//       case 'status':
//         if (msg['payload'] == 'completed') {
//           print('✅ Pipeline completed');
//           channel.sink.close();
//         }
//         break;
//       case 'error':
//         print('❌ Error ▶︎ ${msg['payload']}');
//         channel.sink.close();
//         break;
//       default:
//         print('UNKNOWN ▶︎ $msg');
//     }
//   }, onDone: () {
//     print('WebSocket closed');
//   }, onError: (err) {
//     print('WebSocket error: $err');
//   });
// }



// class LCATextField extends StatefulWidget {
//   final TextEditingController textController;
//   const LCATextField({super.key, required this.textController});

//   @override
//   State<LCATextField> createState() => _LCATextFieldState();
// }

// class _LCATextFieldState extends State<LCATextField> {
//   final ScrollController _scrollController = ScrollController();
//   String? _jsonResult;  // This will hold the JSON result returned from the backend

//   // void _analyzeProcess() async {
//   //   final userInput = widget.textController.text.trim();

//   //   if (userInput.isEmpty) {
//   //     ScaffoldMessenger.of(context).showSnackBar(
//   //       const SnackBar(content: Text('Please describe your process first!')),
//   //     );
//   //     return;
//   //   }

//   //   // Show loading dialog
//   //   showDialog(
//   //     context: context,
//   //     barrierDismissible: false,
//   //     builder: (_) => const AdvancedLectureProgressDialog(),
//   //   );

//   //   // Send request to the backend
//   //   final result = await runLCARequest(userInput);

//   //   Navigator.pop(context); // Hide loading dialog

//   //   if (result == null) {
//   //     ScaffoldMessenger.of(context).showSnackBar(
//   //       const SnackBar(
//   //           content: Text('Something went wrong. Check your network and try again.')),
//   //     );
//   //     return;
//   //   }

//   //   // Optionally, update the UI with the parsed JSON (e.g. by navigating to a result page)
//   //   setState(() {
//   //     _jsonResult = const JsonEncoder.withIndent('  ').convert(result);
//   //   });

//   //   // For debugging, you can print the result
//   //   print("✅ JSON Result from backend:");
//   //   print(_jsonResult);
//   //   // You might also want to navigate to another page to display the JSON in a more user-friendly way.
//   // }
// void _analyzeProcess() async {
//   final userInput = widget.textController.text.trim();

//   // ── 1. Guard: empty input ────────────────────────────────────────────────
//   if (userInput.isEmpty) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('Please describe your process first!')),
//     );
//     return;
//   }

//   // ── 2. Show a blocking loading dialog ────────────────────────────────────
//   showDialog(
//     context: context,
//     barrierDismissible: false,
//     builder: (_) => const AdvancedLectureProgressDialog(),
//   );

//   // ── 3. Call your backend ─────────────────────────────────────────────────
//   final Map<String, dynamic>? result = await runLCARequest(userInput);

//   // Always close the loading spinner
//   Navigator.pop(context);

//   // ── 4. Handle a failure from the backend ────────────────────────────────
//   if (result == null) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('Something went wrong.')),
//     );
//     return;
//   }

//   // (Optional) pretty‑print JSON for debugging or a side‑dialog
//   final prettyJson = const JsonEncoder.withIndent('  ').convert(result);
//   debugPrint(prettyJson);

//   // ── 5. Navigate to the diagram page, passing the MAP ─────────────────────
//   Navigator.push(
//     context,
//     MaterialPageRoute(
//       builder: (_) => ProcessDiagramPage(lcaResult: result),
//     ),
//   );
// }


//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(24, 24, 12, 24),
//       child: Card(
//         color: Colors.white,
//         elevation: 10,
//         shadowColor: Colors.blueGrey.withOpacity(0.1),
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
//         child: Padding(
//           padding: const EdgeInsets.all(24),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.stretch,
//             children: [
//               Row(
//                 children: [
//                   Icon(Icons.eco, color: Colors.green.shade600, size: 26),
//                   const SizedBox(width: 8),
//                   Flexible(
//                     child: FittedBox(
//                       fit: BoxFit.scaleDown,
//                       child: Text(
//                         'Describe Your LCA Scenario',
//                         style: const TextStyle(
//                           fontWeight: FontWeight.bold,
//                           fontSize: 24,
//                           color: Colors.green,
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 8),
//               Text(
//                 "Describe your process in plain English. Add any details you think matter — we’ll figure it out.",
//                 style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
//               ),
//               const SizedBox(height: 16),
//               // Scrollable TextField with improved placeholder
//               Expanded(
//                 child: Scrollbar(
//                   controller: _scrollController,
//                   thumbVisibility: true,
//                   child: TextField(
//                     controller: widget.textController,
//                     scrollController: _scrollController,
//                     expands: true,
//                     maxLines: null,
//                     style: const TextStyle(fontSize: 16, height: 1.4),
//                     decoration: InputDecoration(
//                       hintText: 'Example:\n'
//                           '“I’m comparing two bottle types:\n'
//                           '- Glass bottles, 500 ml, made using natural gas, transported 200km by truck.\n'
//                           '- Plastic PET bottles, same volume, made from recycled PET, electric production, shipped 50km.”',
//                       hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
//                       border: OutlineInputBorder(
//                         borderRadius: BorderRadius.circular(12),
//                         borderSide: BorderSide(color: Colors.grey.shade300),
//                       ),
//                       focusedBorder: OutlineInputBorder(
//                         borderRadius: BorderRadius.circular(12),
//                         borderSide: BorderSide(color: Colors.green.shade600, width: 1.5),
//                       ),
//                       helperText: '💡 Tip: Feel free to compare multiple scenarios!',
//                       helperStyle: TextStyle(color: Colors.green.shade700),
//                     ),
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 16),
//               // Analyze button, visually appealing and friendly
//               SizedBox(
//                 width: double.infinity,
//                 child: ElevatedButton.icon(
//                   onPressed: _analyzeProcess,
//                   icon: const Icon(Icons.play_circle_fill, size: 24),
//                   label: const Text(
//                     'Run LCA Analysis',
//                     style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
//                   ),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.green.shade600,
//                     foregroundColor: Colors.white,
//                     padding: const EdgeInsets.symmetric(vertical: 14),
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(12),
//                     ),
//                   ),
//                 ),
//               ),
//               if (_jsonResult != null) ...[
//                 const SizedBox(height: 16),
//                 Text(
//                   'Result:',
//                   style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800, fontSize: 18),
//                 ),
//                 const SizedBox(height: 8),
//                 Expanded(
//                   child: SingleChildScrollView(
//                     child: Text(
//                       _jsonResult!,
//                       style: const TextStyle(fontFamily: 'Courier', fontSize: 14),
//                     ),
//                   ),
//                 ),
//               ],
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// lib/homescreen/lca_textfield.dart
// lib/homescreen/lca_textfield.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';
import '../api/apicall.dart';       // if you have runLCARequest there
import '../result/graph_pipeline.dart';
import 'dialog.dart';
import 'progress.dart';
import 'graphview.dart';

class LCATextField extends StatefulWidget {
  final TextEditingController textController;
  const LCATextField({Key? key, required this.textController})
      : super(key: key);

  @override
  State<LCATextField> createState() => _LCATextFieldState();
}

class _LCATextFieldState extends State<LCATextField> {
  final ScrollController _scrollController = ScrollController();
  String? _jsonResult;

 
Future<Map<String, dynamic>?> runLCARequest(String userPrompt) async {
final uri = Uri.parse('https://instantlca.duckdns.org/runLCA');
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': userPrompt}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {
      await Future.delayed(const Duration(seconds: 2)); // wait before retry
    }
  }
  return null;
}

  /// Streaming via WebSocket
  void streamLCA(String prompt) {
debugPrint('🔌 Connecting to WS wss://instantlca.onrender.com/ws/logs …');

final channel = WebSocketChannel.connect(
  Uri.parse('wss://instantlca.duckdns.org/ws/logs'),
);


    debugPrint('✔️ WS socket created: $channel');

    // 1) send the prompt
    final initMsg = jsonEncode({'prompt': prompt});
    debugPrint('▶️ WS send: $initMsg');
    channel.sink.add(initMsg);

    // 2) listen for messages
    channel.stream.listen(
      (rawMessage) {
        debugPrint('⟵ WS recv raw: $rawMessage');
        Map<String, dynamic> msg;
        try {
          msg = jsonDecode(rawMessage as String) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('⚠️ WS JSON parse error: $e');
          return;
        }

        final type = msg['type'] as String? ?? 'unknown';
        final payload = msg['payload'];
        switch (type) {
          case 'log':
            debugPrint('LOG ▶︎ $payload');
            break;
          case 'chat':
            debugPrint('CHAT ▶︎ $payload');
            break;
          case 'warn':
            debugPrint('⚠️ WARN ▶︎ $payload');
            break;
          case 'result':
            debugPrint('✅ RESULT ▶︎ ${const JsonEncoder.withIndent('  ').convert(payload)}');
            setState(() {
              _jsonResult = const JsonEncoder.withIndent('  ').convert(payload);
            });
            debugPrint('📴 Closing WS (result received)');
            channel.sink.close();
            break;
          case 'status':
            debugPrint('🔖 STATUS ▶︎ $payload');
            if (payload == 'completed') {
              debugPrint('📴 Closing WS (completed)');
              channel.sink.close();
            }
            break;
          case 'error':
            debugPrint('❌ ERROR ▶︎ $payload');
            channel.sink.close();
            break;
          default:
            debugPrint('❓ UNKNOWN TYPE $type ▶︎ $payload');
        }
      },
      onError: (err) {
        debugPrint('🚨 WS onError: $err');
      },
      onDone: () {
        debugPrint('🔒 WS connection closed.');
      },
      cancelOnError: true,
    );
  }

final uri = Uri.parse('https://instantlca.duckdns.org/runLCA');
final wsUri = Uri.parse('wss://instantlca.duckdns.org/ws/logs');

Future<void> _analyzeProcess() async {
  print("_analyzeProcess started");
  final prompt = widget.textController.text.trim();
  if (prompt.isEmpty) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a description.')),
      );
    }
    return;
  }

  Map<String, dynamic>? result;

  // 1) Wake up the server (optional)
  // try {
  //   await http
  //       .get(Uri.parse('https://instantlca.duckdns.org/runLCA'))
  //       .timeout(const Duration(seconds: 5));
  // } catch (_) {}

  // 2) , try WebSocket streaming first

    try {
      result = await showDialog<Map<String, dynamic>?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StreamLogsDialog(prompt: prompt),
      );
    } catch (e) {
      debugPrint('🔌 WS failed, falling back to HTTP: $e');
    }
  

  // 3) HTTP fallback with retry
  if (result == null) {
    result = await runLCARequest(prompt);
  }

  // 4) Handle null or malformed result
  if (!mounted || result == null || !result.containsKey('processes')) {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('LCA analysis failed.')),
          );
        }
      });
    }
    return;
  }

  // 5) Navigate to the diagram page
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => 
      GraphPipelinePage(initialLcaResult: result!)
      // ProcessDiagramPage(lcaResult: result!),
    ),
  );
}











  // working code below
// Future<void> _analyzeProcess() async {
//     final prompt = widget.textController.text.trim();
//     if (prompt.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Please enter a description.')),
//       );
//       return;
//     }

//     // // Show spinner while dialog is preparing
//     // showDialog(
//     //   context: context,
//     //   barrierDismissible: false,
//     //   builder: (_) => const AdvancedLectureProgressDialog(),
//     // );

//     // 1) Pop‐up streaming logs dialog
// final Map<String, dynamic>? result= await showDialog(
//   context: context,
//   barrierDismissible: false,
//   builder: (_) => StreamLogsDialog(prompt: prompt),
// );

// if (result == null) {
//   ScaffoldMessenger.of(context).showSnackBar(
//      const SnackBar(content: Text('LCA failed or was cancelled.')));
//   return;
// }
// debugPrint('▶️ Navigating with lcaResult keys: ${result.keys}');

// if (!result.containsKey('processes')) {
//   ScaffoldMessenger.of(context).showSnackBar(
//     const SnackBar(content: Text('Unexpected pipeline result — no processes found.')),
//   );
//   return;
// }

// // // 👉 navigate
// Navigator.push(
//   context,
//   MaterialPageRoute(builder: (_) => ProcessDiagramPage(lcaResult: result)),
// );




//   }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 12, 24),
      child: Card(
        color: Colors.white,
        elevation: 10,
        shadowColor: Colors.blueGrey.withOpacity(0.1),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.eco,
                      color: Colors.green.shade600, size: 26),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Describe Your LCA Scenario',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                            color: Colors.green),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "Describe your process in plain English...",
                style: TextStyle(
                    fontSize: 15, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),

              // Input field
              Expanded(
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: TextField(
                    controller: widget.textController,
                    scrollController: _scrollController,
                    expands: true,
                    maxLines: null,
                    style:
                        const TextStyle(fontSize: 16, height: 1.4),
                    decoration: InputDecoration(
                      hintText:
                          'Example: Perform an LCA for producing 1 liter of bottled water...',
                      hintStyle: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 15),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: Colors.green.shade600,
                            width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Run button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _analyzeProcess,
                  icon: const Icon(Icons.play_circle_fill,color:Colors.white,
                      size: 24),
                  label: const Text('Run LCA Analysis',
                      style: TextStyle(
                        color:Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(12)),
                  ),
                ),
              ),

              // Show JSON
              if (_jsonResult != null) ...[
                const SizedBox(height: 16),
                Text('Result:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                        fontSize: 18)),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(_jsonResult!,
                        style: const TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 14)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
