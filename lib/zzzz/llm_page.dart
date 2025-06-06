// // File: lib/zzzz/llm_page.dart

// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;

// import '../api/api_key_delete_later.dart';
// import 'home.dart';               // ProcessNode, FlowValue, etc.
// import 'lca_functions.dart';      // All four helpers
// import 'scenario_merger.dart';    // mergeScenarios

// /// Replace with your actual OpenAI API key (or load from secure storage).
// const String openaiApiKey = openAIApiKey;

// class LLMPage extends StatefulWidget {
//   final String prompt;
//   final List<ProcessNode> processes;
//   final List<Map<String, dynamic>> flows;

//   const LLMPage({
//     super.key,
//     required this.prompt,
//     required this.processes,
//     required this.flows,
//   });

//   @override
//   State<LLMPage> createState() => _LLMPageState();
// }

// class _LLMPageState extends State<LLMPage> {
//   bool _isLoading = false;
//   String? _resultJson; // Final merged scenarios JSON

//   Future<void> _generateAndMergeScenarios() async {
//     setState(() {
//       _isLoading = true;
//       _resultJson = null;
//     });

//     try {
//       // 1) Build baseModel JSON
//       final baseModel = {
//         'processes': widget.processes.map((p) => p.toJson()).toList(),
//         'flows': widget.flows,
//       };
//       print('Built baseModel: ${jsonEncode(baseModel)}');

//       // 2) User payload (LLM gets the free‐form prompt + baseModel)
//       final userPayload = jsonEncode({
//         'scenario_prompt': widget.prompt,
//         'baseModel': baseModel,
//       });
//       print('User payload: $userPayload');

//       // 3) System prompt: instruct LLM to return only “changes” on inputs/outputs/co2,
//       //    and to call functions if large batch variation is requested.
//       const systemPrompt = '''
// You are an expert LCA scenario generator. 
// You will receive:
//   1) "scenario_prompt": a free-form description from the user,
//   2) "baseModel": an object with "processes" and "flows".

// Your job:
// - Decide which "inputs" or "outputs" to change for each scenario, and optionally override "co2".
// - Return a JSON with top-level "scenarios" key. Each scenario name maps to:
//     {
//       "changes": [
//         { "process_id": "<ID>", "field": "inputs.<FlowName>.amount", "new_value": <number> },
//         { "process_id": "<ID>", "field": "outputs.<FlowName>.amount", "new_value": <number> },
//         { "process_id": "<ID>", "field": "co2", "new_value": <number> },
//         // You can also set "inputs.<FlowName>.unit" or "outputs.<FlowName>.unit"
//       ]
//     }

// **IMPORTANT**: Do NOT list derived output or co2 changes if they follow automatically from an input change.  
// Our client code (scenario_merger) will propagate input changes to outputs and co2.  
// If you want to explicitly override an output or co2, include it.  
// If no edits are needed for a scenario, set `"changes": []`.

// If the user requests many random or systematic perturbations of flows or CO₂, you may choose to call one of these functions:
// 1) randomPerturbation(baseModel, percent_range, count)
// 2) simplexSweep(baseModel, step)
// 3) randomFlowVariation(baseModel, flowNames, percent_range, count)
// 4) simplexFlowSweep(baseModel, flowNames, step)

// Follow these function schemas exactly.
// ''';

//       // 4) Function definitions (all four)
//       final functions = [
//         {
//           "name": "randomPerturbation",
//           "description":
//               "Generate N random variations of the baseModel by applying ±percent_range% noise to each process’s CO₂ value. Return a list of change-lists (deltas) only.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               // note: baseModel may be omitted by LLM; we'll use local baseModel if missing
//               "percent_range": {"type": "number"},
//               "count": {"type": "integer"}
//             },
//             "required": ["percent_range", "count"]
//           }
//         },
//         {
//           "name": "simplexSweep",
//           "description":
//               "Perform a simplex sweep over the CO₂ values of all processes. The 'step' parameter indicates percentage increments. Return a list of change-lists (deltas) only.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "step": {"type": "number"}
//             },
//             "required": ["step"]
//           }
//         },
//         {
//           "name": "randomFlowVariation",
//           "description":
//               "Generate N random variations of specified flow amounts (inputs or outputs). 'flowNames' is the list of flow names to vary (if empty, vary all). 'percent_range' is ±% range. 'count' is how many scenarios. Return a list of change-lists (deltas) only.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               // baseModel may be omitted; use local
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "percent_range": {"type": "number"},
//               "count": {"type": "integer"}
//             },
//             "required": ["flowNames", "percent_range", "count"]
//           }
//         },
//         {
//           "name": "simplexFlowSweep",
//           "description":
//               "Perform a simplex‐lattice sweep over specified flow amounts. 'flowNames' is the list of flow names to include. 'step' is the ±% increment. Returns a list of change-lists (deltas) where each change-list modifies one or two flows by ±step%.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               // baseModel may be omitted; use local
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "step": {"type": "number"}
//             },
//             "required": ["flowNames", "step"]
//           }
//         }
//       ];
//       print('Function schemas prepared.');

//       // 5) First ChatCompletion call
//       final chatRequest = {
//         'model': 'gpt-4o-mini',
//         'messages': [
//           {'role': 'system', 'content': systemPrompt},
//           {'role': 'user', 'content': userPayload},
//         ],
//         'functions': functions,
//         'function_call': 'auto'
//       };
//       print('Sending first ChatCompletion request.');

//       final response = await http.post(
//         Uri.parse('https://api.openai.com/v1/chat/completions'),
//         headers: {
//           'Content-Type': 'application/json',
//           'Authorization': 'Bearer $openaiApiKey',
//         },
//         body: jsonEncode(chatRequest),
//       );

//       print('First response status: ${response.statusCode}');
//       print('First response body: ${response.body}');

//       if (response.statusCode != 200) {
//         throw Exception(
//             'OpenAI API error: ${response.statusCode} ${response.reasonPhrase}');
//       }

//       final decoded = jsonDecode(response.body) as Map<String, dynamic>;
//       final choices = decoded['choices'] as List<dynamic>;
//       final firstChoice = choices.first as Map<String, dynamic>;
//       final message = firstChoice['message'] as Map<String, dynamic>;
//       print('Parsed first message: $message');

//       Map<String, dynamic> finalScenarios;

//       // 6) If LLM did a function_call, execute it locally, then ask LLM to label
//       if (message.containsKey('function_call')) {
//         final fcall = message['function_call'] as Map<String, dynamic>;
//         final fname = fcall['name'] as String;
//         final argsString = fcall['arguments'] as String?;
//         print('LLM requested function call: $fname with raw args: $argsString');

//         if (argsString == null) {
//           throw Exception('Function call missing arguments');
//         }
//         final fargs = jsonDecode(argsString) as Map<String, dynamic>;
//         print('Decoded function args: $fargs');

//         late List<List<Map<String, dynamic>>> allChangeLists;
//         if (fname == 'randomPerturbation') {
//           final pm = (fargs['percent_range'] as num).toDouble();
//           final cnt = fargs['count'] as int;
//           print('Calling randomPerturbation with percentRange=$pm, count=$cnt');
//           allChangeLists = randomPerturbation(
//             baseModel: baseModel,
//             percentRange: pm,
//             count: cnt,
//           );
//         } else if (fname == 'simplexSweep') {
//           final stepVal = (fargs['step'] as num).toDouble();
//           print('Calling simplexSweep with step=$stepVal');
//           allChangeLists = simplexSweep(
//             baseModel: baseModel,
//             step: stepVal,
//           );
//         } else if (fname == 'randomFlowVariation') {
//           final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//           final pm = (fargs['percent_range'] as num).toDouble();
//           final cnt = fargs['count'] as int;
//           print('Calling randomFlowVariation with flowNames=$fm, percentRange=$pm, count=$cnt');
//           allChangeLists = randomFlowVariation(
//             baseModel: baseModel,
//             flowNames: fm,
//             percentRange: pm,
//             count: cnt,
//           );
//         } else if (fname == 'simplexFlowSweep') {
//           final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//           final stepVal = (fargs['step'] as num).toDouble();
//           print('Calling simplexFlowSweep with flowNames=$fm, step=$stepVal');
//           allChangeLists = simplexFlowSweep(
//             baseModel: baseModel,
//             flowNames: fm,
//             step: stepVal,
//           );
//         } else {
//           throw Exception('Unexpected function name: $fname');
//         }
//         print('Function returned change lists: $allChangeLists');

//         // 7) Prompt LLM to label these raw changeLists
//         final changeListsJson = jsonEncode({'changeLists': allChangeLists});
//         print('Sending back to LLM for labeling: $changeListsJson');
//         final secondMessages = [
//           {'role': 'system', 'content': systemPrompt},
//           {
//             'role': 'assistant',
//             'content': '',
//             'function_call': {
//               'name': fname,
//               'arguments': changeListsJson,
//             }
//           }
//         ];

//         final secondRequest = {
//           'model': 'gpt-4o-mini',
//           'messages': secondMessages,
//         };
//         print('Sending second ChatCompletion request.');

//         final secondResponse = await http.post(
//           Uri.parse('https://api.openai.com/v1/chat/completions'),
//           headers: {
//             'Content-Type': 'application/json',
//             'Authorization': 'Bearer $openaiApiKey',
//           },
//           body: jsonEncode(secondRequest),
//         );

//         print('Second response status: ${secondResponse.statusCode}');
//         print('Second response body: ${secondResponse.body}');

//         if (secondResponse.statusCode != 200) {
//           throw Exception(
//               'OpenAI second API error: ${secondResponse.statusCode} ${secondResponse.reasonPhrase}');
//         }

//         final decoded2 = jsonDecode(secondResponse.body) as Map<String, dynamic>;
//         final choices2 = decoded2['choices'] as List<dynamic>;
//         final firstChoice2 = choices2.first as Map<String, dynamic>;
//         final message2 = firstChoice2['message'] as Map<String, dynamic>;
//         final content2 = message2['content'] as String;
//         print('LLM labeled scenarios: $content2');

//         finalScenarios = jsonDecode(content2) as Map<String, dynamic>;
//         print('Parsed finalScenarios: $finalScenarios');
//       } else {
//         // 8) LLM returned “scenarios” directly
//         final content = message['content'] as String?;
//         print('LLM returned scenarios directly: $content');
//         if (content == null) {
//           throw Exception('No content returned for scenarios');
//         }
//         finalScenarios = jsonDecode(content) as Map<String, dynamic>;
//       }

//       // 9) Merge baseModel + deltas → full scenario models
//       print('Merging scenarios...');
//       final merged = mergeScenarios(baseModel, finalScenarios['scenarios'] as Map<String, dynamic>);
//       print('Merged result: ${jsonEncode(merged)}');
//       setState(() {
//         _resultJson = const JsonEncoder.withIndent('  ').convert(merged);
//       });
//     } catch (e, stack) {
//       print('Error during scenario generation: $e');
//       print(stack);
//       setState(() {
//         _resultJson = 'Error: $e';
//       });
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('LLM Scenario Generator'),
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           children: [
//             Text(
//               'Prompt:\n${widget.prompt}',
//               style: TextStyle(fontSize: 14),
//             ),
//             SizedBox(height: 12),
//             Expanded(
//               child: Container(
//                 padding: EdgeInsets.all(12),
//                 color: Colors.grey.shade100,
//                 child: _isLoading
//                     ? Center(child: CircularProgressIndicator())
//                     : SingleChildScrollView(
//                         child: SelectableText(
//                           _resultJson ?? 'Press “Generate Scenarios”',
//                           style: TextStyle(
//                               fontFamily: 'monospace', fontSize: 13),
//                         ),
//                       ),
//               ),
//             ),
//             SizedBox(height: 12),
//             SizedBox(
//               width: double.infinity,
//               child: ElevatedButton(
//                 onPressed: _isLoading ? null : _generateAndMergeScenarios,
//                 child: Text('Generate Scenarios'),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// // File: lib/zzzz/llm_page.dart

// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;

// import '../api/api_key_delete_later.dart';
// import 'home.dart';               // ProcessNode, FlowValue, ProcessNodeWidget, LCAGraphPainter
// import 'lca_functions.dart';      // All four helpers
// import 'scenario_merger.dart';    // mergeScenarios

// const String openaiApiKey = openAIApiKey;

// class LLMPage extends StatefulWidget {
//   final String prompt;
//   final List<ProcessNode> processes;
//   final List<Map<String, dynamic>> flows;

//   const LLMPage({
//     super.key,
//     required this.prompt,
//     required this.processes,
//     required this.flows,
//   });

//   @override
//   State<LLMPage> createState() => _LLMPageState();
// }

// class _LLMPageState extends State<LLMPage> {
//   bool _isLoading = false;
//   Map<String, dynamic>? _mergedScenarios; // parsed merged scenarios

//   Future<void> _generateAndMergeScenarios() async {
//     setState(() {
//       _isLoading = true;
//       _mergedScenarios = null;
//     });

//     try {
//       final baseModel = {
//         'processes': widget.processes.map((p) => p.toJson()).toList(),
//         'flows': widget.flows,
//       };

//       final userPayload = jsonEncode({
//         'scenario_prompt': widget.prompt,
//         'baseModel': baseModel,
//       });

//       const systemPrompt = '''
// You are an expert LCA scenario generator. 
// You will receive:
//   1) "scenario_prompt": a free-form description from the user,
//   2) "baseModel": an object with "processes" and "flows".

// Your job:
// - Decide which "inputs" or "outputs" to change for each scenario, and optionally override "co2".
// - Return a JSON with top-level "scenarios" key. Each scenario name maps to:
//     {
//       "changes": [
//         { "process_id": "<ID>", "field": "inputs.<FlowName>.amount", "new_value": <number> },
//         { "process_id": "<ID>", "field": "outputs.<FlowName>.amount", "new_value": <number> },
//         { "process_id": "<ID>", "field": "co2", "new_value": <number> },
//         // You can also set "inputs.<FlowName>.unit" or "outputs.<FlowName>.unit"
//       ]
//     }

// **IMPORTANT**: Do NOT list derived output or co2 changes if they follow automatically from an input change.  
// Our client code (scenario_merger) will propagate input changes to outputs and co2.  
// If you want to explicitly override an output or co2, include it.  
// If no edits are needed for a scenario, set "changes": [].

// If the user requests many random or systematic perturbations of flows or CO₂, you may choose to call one of these functions:
// 1) randomPerturbation(percent_range, count)
// 2) simplexSweep(step)
// 3) randomFlowVariation(flowNames, percent_range, count)
// 4) simplexFlowSweep(flowNames, step)

// Follow these function schemas exactly.
// ''';

//       final functions = [
//         {
//           "name": "randomPerturbation",
//           "description":
//               "Generate N random variations of the baseModel by applying ±percent_range% noise to each process’s CO₂ value. Return a list of change-lists (deltas) only.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "percent_range": {"type": "number"},
//               "count": {"type": "integer"}
//             },
//             "required": ["percent_range", "count"]
//           }
//         },
//         {
//           "name": "simplexSweep",
//           "description":
//               "Perform a simplex sweep over the CO₂ values of all processes. The 'step' parameter indicates percentage increments. Return a list of change-lists (deltas) only.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "step": {"type": "number"}
//             },
//             "required": ["step"]
//           }
//         },
//         {
//           "name": "randomFlowVariation",
//           "description":
//               "Generate N random variations of specified flow amounts (inputs or outputs). 'flowNames' is the list of flow names to vary (if empty, vary all). 'percent_range' is ±% range. 'count' is how many scenarios. Return a list of change-lists (deltas) only.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "percent_range": {"type": "number"},
//               "count": {"type": "integer"}
//             },
//             "required": ["flowNames", "percent_range", "count"]
//           }
//         },
//         {
//           "name": "simplexFlowSweep",
//           "description":
//               "Perform a simplex‐lattice sweep over specified flow amounts. 'flowNames' is the list of flow names to include. 'step' is the ±% increment. Returns a list of change-lists (deltas) where each change-list modifies one or two flows by ±step%.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "step": {"type": "number"}
//             },
//             "required": ["flowNames", "step"]
//           }
//         }
//       ];

//       final chatRequest = {
//         'model': 'gpt-4o-mini',
//         'messages': [
//           {'role': 'system', 'content': systemPrompt},
//           {'role': 'user', 'content': userPayload},
//         ],
//         'functions': functions,
//         'function_call': 'auto'
//       };

//       print('Sending first ChatCompletion request.');
//       final response = await http.post(
//         Uri.parse('https://api.openai.com/v1/chat/completions'),
//         headers: {
//           'Content-Type': 'application/json',
//           'Authorization': 'Bearer $openaiApiKey',
//         },
//         body: jsonEncode(chatRequest),
//       );

//       print('First response status: ${response.statusCode}');
//       print('First response body: ${response.body}');

//       if (response.statusCode != 200) {
//         throw Exception(
//             'OpenAI API error: ${response.statusCode} ${response.reasonPhrase}');
//       }

//       final decoded = jsonDecode(response.body) as Map<String, dynamic>;
//       final choices = decoded['choices'] as List<dynamic>;
//       final firstChoice = choices.first as Map<String, dynamic>;
//       final message = firstChoice['message'] as Map<String, dynamic>;
//       print('Parsed first message: $message');

//       Map<String, dynamic> finalScenarios;

//       if (message.containsKey('function_call')) {
//         final fcall = message['function_call'] as Map<String, dynamic>;
//         final fname = fcall['name'] as String;
//         final argsString = fcall['arguments'] as String?;
//         print('LLM requested function call: $fname with raw args: $argsString');

//         if (argsString == null) {
//           throw Exception('Function call missing arguments');
//         }
//         final fargs = jsonDecode(argsString) as Map<String, dynamic>;
//         print('Decoded function args: $fargs');

//         late List<List<Map<String, dynamic>>> allChangeLists;
//         if (fname == 'randomPerturbation') {
//           final pm = (fargs['percent_range'] as num).toDouble();
//           final cnt = fargs['count'] as int;
//           print('Calling randomPerturbation with percentRange=$pm, count=$cnt');
//           allChangeLists = randomPerturbation(
//             baseModel: baseModel,
//             percentRange: pm,
//             count: cnt,
//           );
//         } else if (fname == 'simplexSweep') {
//           final stepVal = (fargs['step'] as num).toDouble();
//           print('Calling simplexSweep with step=$stepVal');
//           allChangeLists = simplexSweep(
//             baseModel: baseModel,
//             step: stepVal,
//           );
//         } else if (fname == 'randomFlowVariation') {
//           final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//           final pm = (fargs['percent_range'] as num).toDouble();
//           final cnt = fargs['count'] as int;
//           print('Calling randomFlowVariation with flowNames=$fm, percentRange=$pm, count=$cnt');
//           allChangeLists = randomFlowVariation(
//             baseModel: baseModel,
//             flowNames: fm,
//             percentRange: pm,
//             count: cnt,
//           );
//         } else if (fname == 'simplexFlowSweep') {
//           final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//           final stepVal = (fargs['step'] as num).toDouble();
//           print('Calling simplexFlowSweep with flowNames=$fm, step=$stepVal');
//           allChangeLists = simplexFlowSweep(
//             baseModel: baseModel,
//             flowNames: fm,
//             step: stepVal,
//           );
//         } else {
//           throw Exception('Unexpected function name: $fname');
//         }
//         print('Function returned change lists: $allChangeLists');

//         final changeListsJson = jsonEncode({'changeLists': allChangeLists});
//         print('Sending back to LLM for labeling: $changeListsJson');
//         final secondMessages = [
//           {'role': 'system', 'content': systemPrompt},
//           {
//             'role': 'assistant',
//             'content': '',
//             'function_call': {
//               'name': fname,
//               'arguments': changeListsJson,
//             }
//           }
//         ];

//         final secondRequest = {
//           'model': 'gpt-4o-mini',
//           'messages': secondMessages,
//         };
//         print('Sending second ChatCompletion request.');

//         final secondResponse = await http.post(
//           Uri.parse('https://api.openai.com/v1/chat/completions'),
//           headers: {
//             'Content-Type': 'application/json',
//             'Authorization': 'Bearer $openaiApiKey',
//           },
//           body: jsonEncode(secondRequest),
//         );

//         print('Second response status: ${secondResponse.statusCode}');
//         print('Second response body: ${secondResponse.body}');

//         if (secondResponse.statusCode != 200) {
//           throw Exception(
//               'OpenAI second API error: ${secondResponse.statusCode} ${secondResponse.reasonPhrase}');
//         }

//         final decoded2 = jsonDecode(secondResponse.body) as Map<String, dynamic>;
//         final choices2 = decoded2['choices'] as List<dynamic>;
//         final firstChoice2 = choices2.first as Map<String, dynamic>;
//         final message2 = firstChoice2['message'] as Map<String, dynamic>;
//         final content2 = message2['content'] as String;
//         print('LLM labeled scenarios: $content2');

//         finalScenarios = jsonDecode(content2) as Map<String, dynamic>;
//         print('Parsed finalScenarios: $finalScenarios');
//       } else {
//         final content = message['content'] as String?;
//         print('LLM returned scenarios directly: $content');
//         if (content == null) {
//           throw Exception('No content returned for scenarios');
//         }
//         finalScenarios = jsonDecode(content) as Map<String, dynamic>;
//       }

//       print('Merging scenarios...');
//       final mergedFull = mergeScenarios(baseModel, finalScenarios['scenarios'] as Map<String, dynamic>);
//       final scenariosMap = mergedFull['scenarios'] as Map<String, dynamic>;
//       print('Merged result: ${jsonEncode(scenariosMap)}');

//       setState(() {
//         _mergedScenarios = scenariosMap;
//       });
//     } catch (e, stack) {
//       print('Error during scenario generation: $e');
//       print(stack);
//       setState(() {
//         _mergedScenarios = null;
//       });
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('LLM Scenario Generator'),
//         actions: [
//           // Run LCA button stub
//           IconButton(
//             icon: Icon(Icons.play_arrow),
//             tooltip: 'Run LCA',
//             onPressed: () {
//               // TODO: implement Run LCA logic
//               ScaffoldMessenger.of(context).showSnackBar(
//                 SnackBar(content: Text('Run LCA pressed (not implemented)')),
//               );
//             },
//           )
//         ],
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: _isLoading
//             ? Center(child: CircularProgressIndicator())
//             : (_mergedScenarios == null
//                 ? Center(
//                     child: ElevatedButton(
//                       onPressed: _generateAndMergeScenarios,
//                       child: Text('Generate Scenarios'),
//                     ),
//                   )
//                 : ScenarioGraphView(scenariosMap: _mergedScenarios!)),
//       ),
//     );
//   }
// }

// /// Widget that displays each scenario’s graph in a horizontal scroll.
// class ScenarioGraphView extends StatelessWidget {
//   final Map<String, dynamic> scenariosMap;

//   const ScenarioGraphView({required this.scenariosMap});

//   @override
//   Widget build(BuildContext context) {
//     return SingleChildScrollView(
//       scrollDirection: Axis.horizontal,
//       child: Row(
//         children: scenariosMap.entries.map((entry) {
//           final scenarioName = entry.key;
//           final model = entry.value['model'] as Map<String, dynamic>;
//           final processesJson = (model['processes'] as List<dynamic>).cast<Map<String, dynamic>>();
//           final flowsJson = (model['flows'] as List<dynamic>).cast<Map<String, dynamic>>();

//           // Convert JSON into ProcessNode objects
//           final processes = processesJson
//               .map((j) => ProcessNode.fromJson(j))
//               .toList();

//           return Padding(
//             padding: const EdgeInsets.all(8.0),
//             child: Column(
//               children: [
//                 Text(
//                   scenarioName,
//                   style: TextStyle(fontWeight: FontWeight.bold),
//                 ),
//                 SizedBox(
//                   width: 300,
//                   height: 300,
//                   child: Card(
//                     elevation: 4,
//                     child: Padding(
//                       padding: const EdgeInsets.all(8.0),
//                       child: Stack(
//                         children: [
//                           // Draw arrows behind
//                           CustomPaint(
//                             size: Size.infinite,
//                             painter: UndirectedConnectionPainter(processes, flowsJson),
//                           ),
//                           // Position each process node
//                           for (var node in processes)
//                             Positioned(
//                               left: node.position.dx,
//                               top: node.position.dy,
//                               child: ProcessNodeWidget(node: node),
//                             ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           );
//         }).toList(),
//       ),
//     );
//   }
// }

// // File: lib/zzzz/llm_page.dart

// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;

// import '../api/api_key_delete_later.dart';
// import 'home.dart';               // ProcessNode, FlowValue, ProcessNodeWidget, UndirectedConnectionPainter
// import 'lca_functions.dart';      // All four helpers
// import 'scenario_merger.dart';    // mergeScenarios

// const String openaiApiKey = openAIApiKey;

// class LLMPage extends StatefulWidget {
//   final String prompt;
//   final List<ProcessNode> processes;
//   final List<Map<String, dynamic>> flows;

//   const LLMPage({
//     super.key,
//     required this.prompt,
//     required this.processes,
//     required this.flows,
//   });

//   @override
//   State<LLMPage> createState() => _LLMPageState();
// }

// class _LLMPageState extends State<LLMPage> {
//   bool _isLoading = false;
//   Map<String, dynamic>? _mergedScenarios; // parsed merged scenarios

//   /// Strips leading/trailing markdown code fences (``` or ```json) if present.
//   String _stripCodeFences(String input) {
//     // Remove leading ```json or ``` if present
//     final fencePattern = RegExp(r'^```(?:json)?\s*');
//     final trailingFencePattern = RegExp(r'\s*```$');
//     var result = input.trim();
//     result = result.replaceAll(fencePattern, '');
//     result = result.replaceAll(trailingFencePattern, '');
//     return result.trim();
//   }

//   Future<void> _generateAndMergeScenarios() async {
//     setState(() {
//       _isLoading = true;
//       _mergedScenarios = null;
//     });

//     try {
//       final baseModel = {
//         'processes': widget.processes.map((p) => p.toJson()).toList(),
//         'flows': widget.flows,
//       };
//       print('Built baseModel: ${jsonEncode(baseModel)}');

//       final userPayload = jsonEncode({
//         'scenario_prompt': widget.prompt,
//         'baseModel': baseModel,
//       });
//       print('User payload: $userPayload');

//       const systemPrompt = '''
// You are an expert LCA scenario generator. 
// You will receive:
//   1) "scenario_prompt": a free-form description from the user,
//   2) "baseModel": an object with "processes" and "flows".

// Your job:
// - Decide which "inputs" or "outputs" to change for each scenario, and optionally override "co2".
// - Return a JSON with top-level "scenarios" key. Each scenario name maps to:
//     {
//       "changes": [
//         { "process_id": "<ID>", "field": "inputs.<FlowName>.amount", "new_value": <number> },
//         { "process_id": "<ID>", "field": "outputs.<FlowName>.amount", "new_value": <number> },
//         { "process_id": "<ID>", "field": "co2", "new_value": <number> },
//         // You can also set "inputs.<FlowName>.unit" or "outputs.<FlowName>.unit"
//       ]
//     }

// **IMPORTANT**: Do NOT list derived output or co2 changes if they follow automatically from an input change.  
// Our client code (scenario_merger) will propagate input changes to outputs and co2.  
// If you want to explicitly override an output or co2, include it.  
// If no edits are needed for a scenario, set "changes": [].

// If the user requests many random or systematic perturbations of flows or CO₂, you may choose to call one of these functions:
// 1) randomPerturbation(percent_range, count)
// 2) simplexSweep(step)
// 3) randomFlowVariation(flowNames, percent_range, count)
// 4) simplexFlowSweep(flowNames, step)

// Follow these function schemas exactly.
// ''';

//       final functions = [
//         {
//           "name": "randomPerturbation",
//           "description":
//               "Generate N random variations of the baseModel by applying ±percent_range% noise to each process’s CO₂ value. Return a list of change-lists (deltas) only.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "percent_range": {"type": "number"},
//               "count": {"type": "integer"}
//             },
//             "required": ["percent_range", "count"]
//           }
//         },
//         {
//           "name": "simplexSweep",
//           "description":
//               "Perform a simplex sweep over the CO₂ values of all processes. The 'step' parameter indicates percentage increments. Return a list of change-lists (deltas) only.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "step": {"type": "number"}
//             },
//             "required": ["step"]
//           }
//         },
//         {
//           "name": "randomFlowVariation",
//           "description":
//               "Generate N random variations of specified flow amounts (inputs or outputs). 'flowNames' is the list of flow names to vary (if empty, vary all). 'percent_range' is ±% range. 'count' is how many scenarios. Return a list of change-lists (deltas) only.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "percent_range": {"type": "number"},
//               "count": {"type": "integer"}
//             },
//             "required": ["flowNames", "percent_range", "count"]
//           }
//         },
//         {
//           "name": "simplexFlowSweep",
//           "description":
//               "Perform a simplex‐lattice sweep over specified flow amounts. 'flowNames' is the list of flow names to include. 'step' is the ±% increment. Returns a list of change-lists (deltas) where each change-list modifies one or two flows by ±step%.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "step": {"type": "number"}
//             },
//             "required": ["flowNames", "step"]
//           }
//         }
//       ];
//       print('Function schemas prepared.');

//       final chatRequest = {
//         'model': 'gpt-4o-mini',
//         'messages': [
//           {'role': 'system', 'content': systemPrompt},
//           {'role': 'user', 'content': userPayload},
//         ],
//         'functions': functions,
//         'function_call': 'auto'
//       };

//       print('Sending first ChatCompletion request.');
//       final response = await http.post(
//         Uri.parse('https://api.openai.com/v1/chat/completions'),
//         headers: {
//           'Content-Type': 'application/json',
//           'Authorization': 'Bearer $openaiApiKey',
//         },
//         body: jsonEncode(chatRequest),
//       );

//       print('First response status: ${response.statusCode}');
//       print('First response body: ${response.body}');

//       if (response.statusCode != 200) {
//         throw Exception(
//             'OpenAI API error: ${response.statusCode} ${response.reasonPhrase}');
//       }

//       final decoded = jsonDecode(response.body) as Map<String, dynamic>;
//       final choices = decoded['choices'] as List<dynamic>;
//       final firstChoice = choices.first as Map<String, dynamic>;
//       final message = firstChoice['message'] as Map<String, dynamic>;
//       print('Parsed first message: $message');

//       Map<String, dynamic> finalScenarios;

//       if (message.containsKey('function_call')) {
//         final fcall = message['function_call'] as Map<String, dynamic>;
//         final fname = fcall['name'] as String;
//         final argsString = fcall['arguments'] as String?;
//         print('LLM requested function call: $fname with raw args: $argsString');

//         if (argsString == null) {
//           throw Exception('Function call missing arguments');
//         }
//         final fargs =
//             jsonDecode(_stripCodeFences(argsString)) as Map<String, dynamic>;
//         print('Decoded function args: $fargs');

//         late List<List<Map<String, dynamic>>> allChangeLists;
//         if (fname == 'randomPerturbation') {
//           final pm = (fargs['percent_range'] as num).toDouble();
//           final cnt = fargs['count'] as int;
//           print('Calling randomPerturbation with percentRange=$pm, count=$cnt');
//           allChangeLists = randomPerturbation(
//             baseModel: baseModel,
//             percentRange: pm,
//             count: cnt,
//           );
//         } else if (fname == 'simplexSweep') {
//           final stepVal = (fargs['step'] as num).toDouble();
//           print('Calling simplexSweep with step=$stepVal');
//           allChangeLists = simplexSweep(
//             baseModel: baseModel,
//             step: stepVal,
//           );
//         } else if (fname == 'randomFlowVariation') {
//           final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//           final pm = (fargs['percent_range'] as num).toDouble();
//           final cnt = fargs['count'] as int;
//           print(
//               'Calling randomFlowVariation with flowNames=$fm, percentRange=$pm, count=$cnt');
//           allChangeLists = randomFlowVariation(
//             baseModel: baseModel,
//             flowNames: fm,
//             percentRange: pm,
//             count: cnt,
//           );
//         } else if (fname == 'simplexFlowSweep') {
//           final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//           final stepVal = (fargs['step'] as num).toDouble();
//           print(
//               'Calling simplexFlowSweep with flowNames=$fm, step=$stepVal');
//           allChangeLists = simplexFlowSweep(
//             baseModel: baseModel,
//             flowNames: fm,
//             step: stepVal,
//           );
//         } else {
//           throw Exception('Unexpected function name: $fname');
//         }
//         print('Function returned change lists: $allChangeLists');

//         final changeListsJson = jsonEncode({'changeLists': allChangeLists});
//         print('Sending back to LLM for labeling: $changeListsJson');
//         final secondMessages = [
//           {'role': 'system', 'content': systemPrompt},
//           {
//             'role': 'assistant',
//             'content': '',
//             'function_call': {
//               'name': fname,
//               'arguments': changeListsJson,
//             }
//           }
//         ];

//         final secondRequest = {
//           'model': 'gpt-4o-mini',
//           'messages': secondMessages,
//         };
//         print('Sending second ChatCompletion request.');

//         final secondResponse = await http.post(
//           Uri.parse('https://api.openai.com/v1/chat/completions'),
//           headers: {
//             'Content-Type': 'application/json',
//             'Authorization': 'Bearer $openaiApiKey',
//           },
//           body: jsonEncode(secondRequest),
//         );

//         print('Second response status: ${secondResponse.statusCode}');
//         print('Second response body: ${secondResponse.body}');

//         if (secondResponse.statusCode != 200) {
//           throw Exception(
//               'OpenAI second API error: ${secondResponse.statusCode} ${secondResponse.reasonPhrase}');
//         }

//         final decoded2 =
//             jsonDecode(secondResponse.body) as Map<String, dynamic>;
//         final choices2 = decoded2['choices'] as List<dynamic>;
//         final firstChoice2 = choices2.first as Map<String, dynamic>;
//         final message2 = firstChoice2['message'] as Map<String, dynamic>;
//         final content2 = message2['content'] as String;
//         print('LLM labeled scenarios: $content2');

//         finalScenarios =
//             jsonDecode(_stripCodeFences(content2)) as Map<String, dynamic>;
//         print('Parsed finalScenarios: $finalScenarios');
//       } else {
//         final content = message['content'] as String?;
//         print('LLM returned scenarios directly: $content');
//         if (content == null) {
//           throw Exception('No content returned for scenarios');
//         }
//         finalScenarios =
//             jsonDecode(_stripCodeFences(content)) as Map<String, dynamic>;
//       }

//       // print('Merging scenarios...');
//       // final mergedFull = mergeScenarios(
//       //     baseModel, finalScenarios['scenarios'] as Map<String, dynamic>);
//       print('Merging scenarios...');

// // finalScenarios['scenarios'] is a Map<String, dynamic>, where each value is
// // itself a Map containing a 'changes' key (List<Map<String, dynamic>>).
// final rawByScenario = finalScenarios['scenarios'] as Map<String, dynamic>;

// // Build a Map<String, List<Map<String, dynamic>>> where each scenarioName
// // maps to its 'changes' list.
// final Map<String, List<Map<String, dynamic>>> deltasByScenario = {};
// rawByScenario.forEach((scenarioName, scenarioValue) {
//   final scenarioMap = scenarioValue as Map<String, dynamic>;
//   final changesList = scenarioMap['changes'] as List<dynamic>;
//   // Cast each element to Map<String, dynamic>
//   deltasByScenario[scenarioName] =
//       changesList.cast<Map<String, dynamic>>();
// });

// // Now call mergeScenarios with the proper type:
// final mergedFull = mergeScenarios(baseModel, deltasByScenario);

//       final scenariosMap = mergedFull['scenarios'] as Map<String, dynamic>;
//       print('Merged result: ${jsonEncode(scenariosMap)}');

//       setState(() {
//         _mergedScenarios = scenariosMap;
//       });
//     } catch (e, stack) {
//       print('Error during scenario generation: $e');
//       print(stack);
//       setState(() {
//         _mergedScenarios = null;
//       });
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('LLM Scenario Generator'),
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: _isLoading
//             ? Center(child: CircularProgressIndicator())
//             : (_mergedScenarios == null
//                 ? Center(
//                     child: ElevatedButton(
//                       onPressed: _generateAndMergeScenarios,
//                       child: Text('Generate Scenarios'),
//                     ),
//                   )
//                 : Column(
//                     children: [
//                       Expanded(
//                         child: ScenarioGraphView(
//                             scenariosMap: _mergedScenarios!),
//                       ),
//                       SizedBox(height: 16),
//                       ElevatedButton.icon(
//                         onPressed: () {
//                           // TODO: implement Run LCA logic
//                         },
//                         icon: Icon(Icons.play_arrow),
//                         label: Text('Run LCA'),
//                       ),
//                     ],
//                   )),
//       ),
//     );
//   }
// }

// /// Widget that displays each scenario’s graph in a horizontal scroll.
// class ScenarioGraphView extends StatelessWidget {
//   final Map<String, dynamic> scenariosMap;

//   const ScenarioGraphView({required this.scenariosMap});

//   @override
//   Widget build(BuildContext context) {
//     return SingleChildScrollView(
//       scrollDirection: Axis.horizontal,
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: scenariosMap.entries.map((entry) {
//           final scenarioName = entry.key;
//           final model = entry.value['model'] as Map<String, dynamic>;
//           final processesJson =
//               (model['processes'] as List<dynamic>).cast<Map<String, dynamic>>();
//           final flowsJson =
//               (model['flows'] as List<dynamic>).cast<Map<String, dynamic>>();

//           // Convert JSON into ProcessNode objects
//           final processes =
//               processesJson.map((j) => ProcessNode.fromJson(j)).toList();

//           // Compute bounding box so the canvas fits all ProcessNodeWidgets
//           double maxX = 0, maxY = 0;
//           for (var node in processes) {
//             final sz = ProcessNodeWidget.sizeFor(node);
//             final rightEdge = node.position.dx + sz.width;
//             final bottomEdge = node.position.dy + sz.height;
//             if (rightEdge > maxX) maxX = rightEdge;
//             if (bottomEdge > maxY) maxY = bottomEdge;
//           }
//           // Add some padding
//           final canvasWidth = maxX + 20;
//           final canvasHeight = maxY + 20;

//           return Padding(
//             padding: const EdgeInsets.all(8.0),
//             child: Column(
//               children: [
//                 Text(
//                   scenarioName,
//                   style: TextStyle(fontWeight: FontWeight.bold),
//                 ),
//                 SizedBox(
//                   width: canvasWidth,
//                   height: canvasHeight,
//                   child: Card(
//                     elevation: 4,
//                     child: Padding(
//                       padding: const EdgeInsets.all(8.0),
//                       child: Stack(
//                         children: [
//                           // Draw connections behind using UndirectedConnectionPainter
//                           CustomPaint(
//                             size: Size(canvasWidth, canvasHeight),
//                             painter:
//                                 UndirectedConnectionPainter(processes, flowsJson),
//                           ),
//                           // Position each process node
//                           for (var node in processes)
//                             Positioned(
//                               left: node.position.dx,
//                               top: node.position.dy,
//                               child: ProcessNodeWidget(node: node),
//                             ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           );
//         }).toList(),
//       ),
//     );
//   }
// }


// // File: lib/zzzz/llm_page.dart

// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;

// import '../api/api_key_delete_later.dart';
// import 'home.dart';               // ProcessNode, FlowValue, ProcessNodeWidget, UndirectedConnectionPainter
// import 'lca_functions.dart';      // All four helpers
// import 'scenario_merger.dart';    // mergeScenarios

// const String openaiApiKey = openAIApiKey;

// class LLMPage extends StatefulWidget {
//   final String prompt;
//   final List<ProcessNode> processes;
//   final List<Map<String, dynamic>> flows;

//   const LLMPage({
//     super.key,
//     required this.prompt,
//     required this.processes,
//     required this.flows,
//   });

//   @override
//   State<LLMPage> createState() => _LLMPageState();
// }

// class _LLMPageState extends State<LLMPage> {
//   bool _isLoading = false;
//   Map<String, dynamic>? _mergedScenarios; // parsed merged scenarios

//   /// Strips leading/trailing markdown code fences (``` or ```json) if present.
//   String _stripCodeFences(String input) {
//     final fencePattern = RegExp(r'^```(?:json)?\s*');
//     final trailingFencePattern = RegExp(r'\s*```$');
//     var result = input.trim();
//     result = result.replaceAll(fencePattern, '');
//     result = result.replaceAll(trailingFencePattern, '');
//     return result.trim();
//   }

//   Future<void> _generateAndMergeScenarios() async {
//     setState(() {
//       _isLoading = true;
//       _mergedScenarios = null;
//     });

//     try {
//       final baseModel = {
//         'processes': widget.processes.map((p) => p.toJson()).toList(),
//         'flows': widget.flows,
//       };
//       print('Built baseModel: ${jsonEncode(baseModel)}');

//       final userPayload = jsonEncode({
//         'scenario_prompt': widget.prompt,
//         'baseModel': baseModel,
//       });
//       print('User payload: $userPayload');

// const systemPrompt = '''
// You are an expert LCA scenario generator. 
// You will receive:
//   1) "scenario_prompt": a free-form description from the user,
//   2) "baseModel": an object with "processes" and "flows".

// Your job:
// - Decide which "inputs" or "outputs" to change for each scenario, and optionally override "co2".
// - Return a JSON with a top-level "scenarios" key. Each scenario name maps to:
//     {
//       "changes": [
//         { "process_id": "<ID>", "field": "inputs.<FlowName>.amount", "new_value": <number> },
//         { "process_id": "<ID>", "field": "outputs.<FlowName>.amount", "new_value": <number> },
//         { "process_id": "<ID>", "field": "co2", "new_value": <number> },
//         // You may also override units with "inputs.<FlowName>.unit" or "outputs.<FlowName>.unit"
//       ]
//     }

// **IMPORTANT**:
// -1. If the user’s prompt gives a list of exact values (e.g. “use diesel as 10, 20, and 30”), do NOT call any random‐perturbation functions (randomFlowVariation, simplexFlowSweep, etc.). Instead, directly output scenarios that set `outputs.<flow>.amount` to exactly those numbers.

// - Do NOT list output or co2 changes if they are automatically derived from input changes.
// - Our client logic (`scenario_merger` in Dart) will automatically propagate changes to maintain balance.
// - If no edits are needed in a scenario, set "changes": [].

// ---



// If the user requests many random or systematic perturbations of flows or CO₂, you may choose to call one of these functions:
// 1) randomPerturbation(percent_range, count)
// 2) simplexSweep(step)
// 3) randomFlowVariation(flowNames, percent_range, count)
// 4) simplexFlowSweep(flowNames, step)


// **Special instructions for flows that appear in both a producer and consumer:**

// 1. If the user refers to **supply** (keywords: “produce,” “supply,” “plant,” “manufacturer,” “yield”),
//    then only change the **producer’s** `outputs.<flow>.amount`. Do not include any `inputs.<flow>.amount`.

// 2. If the user refers to **demand** (keywords: “consume,” “demand,” “usage,” “input,” “require”),
//    then only change the **consumer’s** `inputs.<flow>.amount`. Do not include any `outputs.<flow>.amount`.

// 3. If the user explicitly wants “set supply = X and demand = X,”
//    produce two identical overrides (one on `outputs.<flow>.amount` and one on `inputs.<flow>.amount`).

// 4. If the user is **ambiguous** (e.g. “perturb diesel” without “supply” vs. “demand”),
//    default to changing **only the producer** (`outputs.<flow>.amount`).

// 5. When calling **randomFlowVariation** or **simplexFlowSweep**, do not generate
//    both input and output changes for the same shared flow, unless the user explicitly asks for both.

// Follow these rules to keep the LCA balanced. Our Dart code will propagate downstream/upstream automatically.

// Follow these function schemas exactly.
// ''';


//       final functions = [
//         {
//           "name": "randomPerturbation",
//           "description":
//               "Generate N random variations of the baseModel by applying ±percent_range% noise to each process’s CO₂ value. Return a list of change-lists (deltas) only.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "percent_range": {"type": "number"},
//               "count": {"type": "integer"}
//             },
//             "required": ["percent_range", "count"]
//           }
//         },
//         {
//           "name": "simplexSweep",
//           "description":
//               "Perform a simplex sweep over the CO₂ values of all processes. The 'step' parameter indicates percentage increments. Return a list of change-lists (deltas) only.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "step": {"type": "number"}
//             },
//             "required": ["step"]
//           }
//         },
//         {
//           "name": "randomFlowVariation",
//           "description":
//               "Generate N random variations of specified flow amounts (inputs or outputs). 'flowNames' is the list of flow names to vary (if empty, vary all). 'percent_range' is ±% range. 'count' is how many scenarios. Return a list of change-lists (deltas) only.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "percent_range": {"type": "number"},
//               "count": {"type": "integer"}
//             },
//             "required": ["flowNames", "percent_range", "count"]
//           },
//               "implementation": "safeRandomFlowVariation",

//         },
//         {
//           "name": "simplexFlowSweep",
//           "description":
//               "Perform a simplex‐lattice sweep over specified flow amounts. 'flowNames' is the list of flow names to include. 'step' is the ±% increment. Returns a list of change-lists (deltas) where each change-list modifies one or two flows by ±step%.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "step": {"type": "number"}
//             },
//             "required": ["flowNames", "step"]
//           }
//         }
//       ];
//       print('Function schemas prepared.');

//       final chatRequest = {
//         'model': 'gpt-4o',
//         'messages': [
//           {'role': 'system', 'content': systemPrompt},
//           {'role': 'user', 'content': userPayload},
//         ],
//         'functions': functions,
//         'function_call': 'auto'
//       };

//       print('Sending first ChatCompletion request.');
//       final response = await http.post(
//         Uri.parse('https://api.openai.com/v1/chat/completions'),
//         headers: {
//           'Content-Type': 'application/json',
//           'Authorization': 'Bearer $openaiApiKey',
//         },
//         body: jsonEncode(chatRequest),
//       );

//       print('First response status: ${response.statusCode}');
//       print('First response body: ${response.body}');

//       if (response.statusCode != 200) {
//         throw Exception(
//             'OpenAI API error: ${response.statusCode} ${response.reasonPhrase}');
//       }

//       final decoded = jsonDecode(response.body) as Map<String, dynamic>;
//       final choices = decoded['choices'] as List<dynamic>;
//       final firstChoice = choices.first as Map<String, dynamic>;
//       final message = firstChoice['message'] as Map<String, dynamic>;
//       print('Parsed first message: $message');

//       Map<String, dynamic> finalScenarios;

//       if (message.containsKey('function_call')) {
//         final fcall = message['function_call'] as Map<String, dynamic>;
//         final fname = fcall['name'] as String;
//         final argsString = fcall['arguments'] as String?;
//         print('LLM requested function call: $fname with raw args: $argsString');

//         if (argsString == null) {
//           throw Exception('Function call missing arguments');
//         }
//         final fargs =
//             jsonDecode(_stripCodeFences(argsString)) as Map<String, dynamic>;
//         print('Decoded function args: $fargs');

//         late List<List<Map<String, dynamic>>> allChangeLists;
//         if (fname == 'randomPerturbation') {
//           final pm = (fargs['percent_range'] as num).toDouble();
//           final cnt = fargs['count'] as int;
//           print('Calling randomPerturbation with percentRange=$pm, count=$cnt');
//           allChangeLists = randomPerturbation(
//             baseModel: baseModel,
//             percentRange: pm,
//             count: cnt,
//           );
//         } else if (fname == 'simplexSweep') {
//           final stepVal = (fargs['step'] as num).toDouble();
//           print('Calling simplexSweep with step=$stepVal');
//           allChangeLists = simplexSweep(
//             baseModel: baseModel,
//             step: stepVal,
//           );
//         } else if (fname == 'randomFlowVariation') {
//           // final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//           // final pm = (fargs['percent_range'] as num).toDouble();
//           // final cnt = fargs['count'] as int;
//           // print(
//           //     'Calling randomFlowVariation with flowNames=$fm, percentRange=$pm, count=$cnt');
//           // allChangeLists = randomFlowVariation(
//           //   baseModel: baseModel,
//           //   flowNames: fm,
//           //   percentRange: pm,
//           //   count: cnt,
//           // );

//   final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//   final pm = (fargs['percent_range'] as num).toDouble();
//   final cnt = fargs['count'] as int;
//   print(
//     'Calling safeRandomFlowVariation with flowNames=$fm, percentRange=$pm, count=$cnt'
//   );
//   allChangeLists = safeRandomFlowVariation(
//     baseModel: baseModel,
//     flowNames: fm,
//     percentRange: pm,
//     count: cnt,
//   );
// }

//          else if (fname == 'simplexFlowSweep') {
//           final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//           final stepVal = (fargs['step'] as num).toDouble();
//           print(
//               'Calling simplexFlowSweep with flowNames=$fm, step=$stepVal');
//           allChangeLists = simplexFlowSweep(
//             baseModel: baseModel,
//             flowNames: fm,
//             step: stepVal,
//           );
//         } else {
//           throw Exception('Unexpected function name: $fname');
//         }
//         print('Function returned change lists: $allChangeLists');

//         final changeListsJson = jsonEncode({'changeLists': allChangeLists});
//         print('Sending back to LLM for labeling: $changeListsJson');
//         final secondMessages = [
//           {'role': 'system', 'content': systemPrompt},
//           {
//             'role': 'assistant',
//             'content': '',
//             'function_call': {
//               'name': fname,
//               'arguments': changeListsJson,
//             }
//           }
//         ];

//         final secondRequest = {
//           'model': 'gpt-4o',
//           'messages': secondMessages,
//         };
//         print('Sending second ChatCompletion request.');

//         final secondResponse = await http.post(
//           Uri.parse('https://api.openai.com/v1/chat/completions'),
//           headers: {
//             'Content-Type': 'application/json',
//             'Authorization': 'Bearer $openaiApiKey',
//           },
//           body: jsonEncode(secondRequest),
//         );

//         print('Second response status: ${secondResponse.statusCode}');
//         print('Second response body: ${secondResponse.body}');

//         if (secondResponse.statusCode != 200) {
//           throw Exception(
//               'OpenAI second API error: ${secondResponse.statusCode} ${secondResponse.reasonPhrase}');
//         }

//         final decoded2 =
//             jsonDecode(secondResponse.body) as Map<String, dynamic>;
//         final choices2 = decoded2['choices'] as List<dynamic>;
//         final firstChoice2 = choices2.first as Map<String, dynamic>;
//         final message2 = firstChoice2['message'] as Map<String, dynamic>;
//         final content2 = message2['content'] as String;
//         print('LLM labeled scenarios: $content2');

//         finalScenarios =
//             jsonDecode(_stripCodeFences(content2)) as Map<String, dynamic>;
//         print('Parsed finalScenarios: $finalScenarios');
//       } else {
//         final content = message['content'] as String?;
//         print('LLM returned scenarios directly: $content');
//         if (content == null) {
//           throw Exception('No content returned for scenarios');
//         }
//         finalScenarios =
//             jsonDecode(_stripCodeFences(content)) as Map<String, dynamic>;
//       }

//       print('Merging scenarios...');

//       // finalScenarios['scenarios'] is a Map<String, dynamic>, where each value is
//       // itself a Map containing a 'changes' key (List<Map<String, dynamic>>).
//       final rawByScenario = finalScenarios['scenarios'] as Map<String, dynamic>;

//       // Build a Map<String, List<Map<String, dynamic>>> where each scenarioName
//       // maps to its 'changes' list.
//       final Map<String, List<Map<String, dynamic>>> deltasByScenario = {};
//       rawByScenario.forEach((scenarioName, scenarioValue) {
//         final scenarioMap = scenarioValue as Map<String, dynamic>;
//         final changesList = scenarioMap['changes'] as List<dynamic>;
//         deltasByScenario[scenarioName] =
//             changesList.cast<Map<String, dynamic>>();
//       });

//       // Now call mergeScenarios with the proper type:
//       final mergedFull = mergeScenarios(baseModel, deltasByScenario);

//       final scenariosMap = mergedFull['scenarios'] as Map<String, dynamic>;
//       print('Merged result: ${jsonEncode(scenariosMap)}');

//       setState(() {
//         _mergedScenarios = scenariosMap;
//       });
//     } catch (e, stack) {
//       print('Error during scenario generation: $e');
//       print(stack);
//       setState(() {
//         _mergedScenarios = null;
//       });
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('LLM Scenario Generator'),
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: _isLoading
//             ? Center(child: CircularProgressIndicator())
//             : (_mergedScenarios == null
//                 ? Center(
//                     child: ElevatedButton(
//                       onPressed: _generateAndMergeScenarios,
//                       child: Text('Generate Scenarios'),
//                     ),
//                   )
//                 : Column(
//                     children: [
//                       Expanded(
//                         child: ScenarioGraphView(
//                             scenariosMap: _mergedScenarios!),
//                       ),
//                       SizedBox(height: 16),
//                       ElevatedButton.icon(
//                         onPressed: () {
//                           // TODO: implement Run LCA logic
//                         },
//                         icon: Icon(Icons.play_arrow),
//                         label: Text('Run LCA'),
//                       ),
//                     ],
//                   )),
//       ),
//     );
//   }
// }

// /// Widget that displays each scenario’s graph in a horizontal scroll.
// class ScenarioGraphView extends StatelessWidget {
//   final Map<String, dynamic> scenariosMap;

//   const ScenarioGraphView({required this.scenariosMap});

//   @override
//   Widget build(BuildContext context) {
//     return SingleChildScrollView(
//       scrollDirection: Axis.horizontal,
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: scenariosMap.entries.map((entry) {
//           final scenarioName = entry.key;
//           final model = entry.value['model'] as Map<String, dynamic>;
//           final processesJson =
//               (model['processes'] as List<dynamic>).cast<Map<String, dynamic>>();
//           final flowsJson =
//               (model['flows'] as List<dynamic>).cast<Map<String, dynamic>>();

//           // Convert JSON into ProcessNode objects
//           final processes =
//               processesJson.map((j) => ProcessNode.fromJson(j)).toList();

//           // Compute bounding box so the canvas fits all ProcessNodeWidgets
//           double maxX = 0, maxY = 0;
//           for (var node in processes) {
//             final sz = ProcessNodeWidget.sizeFor(node);
//             final rightEdge = node.position.dx + sz.width;
//             final bottomEdge = node.position.dy + sz.height;
//             if (rightEdge > maxX) maxX = rightEdge;
//             if (bottomEdge > maxY) maxY = bottomEdge;
//           }
//           // Add some padding
//           final canvasWidth = maxX + 20;
//           final canvasHeight = maxY + 20;

//           return Padding(
//             padding: const EdgeInsets.all(8.0),
//             child: Column(
//               children: [
//                 Text(
//                   scenarioName,
//                   style: TextStyle(fontWeight: FontWeight.bold),
//                 ),
//                 SizedBox(
//                   width: canvasWidth,
//                   height: canvasHeight,
//                   child: Card(
//                     elevation: 4,
//                     child: Padding(
//                       padding: const EdgeInsets.all(8.0),
//                       child: Stack(
//                         children: [
//                           // Draw connections behind using UndirectedConnectionPainter
//                           CustomPaint(
//                             size: Size(canvasWidth, canvasHeight),
//                             painter:
//                                 UndirectedConnectionPainter(processes, flowsJson),
//                           ),
//                           // Position each process node
//                           for (var node in processes)
//                             Positioned(
//                               left: node.position.dx,
//                               top: node.position.dy,
//                               child: ProcessNodeWidget(node: node),
//                             ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           );
//         }).toList(),
//       ),
//     );
//   }
// }
// File: lib/zzzz/llm_page.dart

// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;

// import '../api/api_key_delete_later.dart';
// import 'home.dart';               // ProcessNode, FlowValue, etc.
// import 'lca_functions.dart';      // Now includes both wrappers
// import 'scenario_merger.dart';    // mergeScenarios

// const String openaiApiKey = openAIApiKey;

// class LLMPage extends StatefulWidget {
//   final String prompt;
//   final List<ProcessNode> processes;
//   final List<Map<String, dynamic>> flows;

//   const LLMPage({
//     super.key,
//     required this.prompt,
//     required this.processes,
//     required this.flows,
//   });

//   @override
//   State<LLMPage> createState() => _LLMPageState();
// }

// class _LLMPageState extends State<LLMPage> {
//   bool _isLoading = false;
//   Map<String, dynamic>? _mergedScenarios; // parsed merged scenarios

//   String _stripCodeFences(String input) {
//     final fencePattern = RegExp(r'^```(?:json)?\s*');
//     final trailingFencePattern = RegExp(r'\s*```$');
//     var result = input.trim();
//     result = result.replaceAll(fencePattern, '');
//     result = result.replaceAll(trailingFencePattern, '');
//     return result.trim();
//   }

//   Future<void> _generateAndMergeScenarios() async {
//     setState(() {
//       _isLoading = true;
//       _mergedScenarios = null;
//     });

//     try {
//       // 1) Build baseModel and userPayload
//       final baseModel = {
//         'processes': widget.processes.map((p) => p.toJson()).toList(),
//         'flows': widget.flows,
//       };
//       print('🔍 Built baseModel:\n${const JsonEncoder.withIndent('  ').convert(baseModel)}');

//       final userPayload = jsonEncode({
//         'scenario_prompt': widget.prompt,
//         'baseModel': baseModel,
//       });
//       print('🧑‍💻 User payload:\n$userPayload');

//       const systemPrompt = '''
// You are an expert LCA scenario generator.
// You will receive:
//   1) "scenario_prompt": a free-form description from the user,
//   2) "baseModel": an object with "processes" and "flows".

// Your job:
// - Decide which "inputs" or "outputs" to change for each scenario, and optionally override "co2".
// - Return a JSON with a top-level "scenarios" key. Each scenario name maps to:
//     {
//       "changes": [
//         { "process_id": "<ID>", "field": "inputs.<FlowName>.amount", "new_value": <number> },
//         { "process_id": "<ID>", "field": "outputs.<FlowName>.amount", "new_value": <number> },
//         { "process_id": "<ID>", "field": "co2", "new_value": <number> },
//         // You may also override units with "inputs.<FlowName>.unit" or "outputs.<FlowName>.unit"
//       ]
//     }

// **IMPORTANT**:
// - Do NOT list output or co2 changes if they are automatically derived from input changes.
// - Our client logic (`scenario_merger` in Dart) will automatically propagate changes to maintain balance.
// - If no edits are needed in a scenario, set "changes": [].

// ---

// If the user requests many random or systematic perturbations of flows or CO₂:
//   1) randomPerturbation(percent_range, count)
//   2) simplexSweep(step)
//   3) randomFlowVariationProducer(flowNames, percent_range, count)
//   4) randomFlowVariationConsumer(flowNames, percent_range, count)
//   5) simplexFlowSweep(flowNames, step)

// **Special instructions for flows that appear in both a producer and consumer:**

// 1. If the user refers to **supply** (keywords: “produce,” “supply,” “plant,” “manufacturer,” “yield”),
//    then call **randomFlowVariationProducer** (or otherwise generate deltas only on `outputs.<flow>.amount`).

// 2. If the user refers to **demand** (keywords: “consume,” “demand,” “usage,” “input,” “require”),
//    then call **randomFlowVariationConsumer** (or otherwise generate deltas only on `inputs.<flow>.amount`).

// 3. If the user explicitly wants “set supply = X and demand = X,”
//    produce two identical overrides (one on `outputs.<flow>.amount` and one on `inputs.<flow>.amount`).

// // 4. If the user is **ambiguous** (e.g. “perturb diesel” without “supply” vs. “demand”),
// //    default to **randomFlowVariationProducer**.

// Follow these instructions to keep the LCA balanced. Our Dart code will propagate downstream/upstream automatically.
// ''';

//       final functions = [
//         {
//           "name": "randomPerturbation",
//           "description":
//               "Generate N random variations of the baseModel by applying ±percent_range% noise to each process’s CO₂ value. Return a list of change-lists (deltas) only.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "percent_range": {"type": "number"},
//               "count": {"type": "integer"}
//             },
//             "required": ["percent_range", "count"]
//           }
//         },
//         {
//           "name": "simplexSweep",
//           "description":
//               "Perform a simplex sweep over the CO₂ values of all processes. The 'step' parameter indicates percentage increments. Return a list of change-lists (deltas) only.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "step": {"type": "number"}
//             },
//             "required": ["step"]
//           }
//         },
//         {
//           "name": "randomFlowVariationProducer",
//           "description":
//               "Generate N random variations of specified flow amounts (producer side only). 'flowNames' is the list of flow names to vary. 'percent_range' is ±% range. 'count' is how many scenarios. Drops any consumer-side (inputs) changes for shared flows.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "percent_range": {"type": "number"},
//               "count": {"type": "integer"}
//             },
//             "required": ["flowNames", "percent_range", "count"]
//           }
//         },
//         {
//           "name": "randomFlowVariationConsumer",
//           "description":
//               "Generate N random variations of specified flow amounts (consumer side only). 'flowNames' is the list of flow names to vary. 'percent_range' is ±% range. 'count' is how many scenarios. Drops any producer-side (outputs) changes for shared flows.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "percent_range": {"type": "number"},
//               "count": {"type": "integer"}
//             },
//             "required": ["flowNames", "percent_range", "count"]
//           }
//         },
//         {
//           "name": "simplexFlowSweep",
//           "description":
//               "Perform a simplex‐lattice sweep over specified flow amounts. 'flowNames' is the list of flow names to include. 'step' is the ±% increment. Returns a list of change-lists (deltas) where each change-list modifies one or two flows by ±step%. Drops both sides only if explicitly requested.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "step": {"type": "number"}
//             },
//             "required": ["flowNames", "step"]
//           }
//         }
//       ];

//       // 2) Send first ChatCompletion request
//       final chatRequest = {
//         'model': 'gpt-4o',
//         'messages': [
//           {'role': 'system', 'content': systemPrompt},
//           {'role': 'user', 'content': userPayload},
//         ],
//         'functions': functions,
//         'function_call': 'auto'
//       };

//       print('🚀 Sending first ChatCompletion request to OpenAI...');
//       final response = await http.post(
//         Uri.parse('https://api.openai.com/v1/chat/completions'),
//         headers: {
//           'Content-Type': 'application/json',
//           'Authorization': 'Bearer $openaiApiKey',
//         },
//         body: jsonEncode(chatRequest),
//       );
//       print('📥 First response status: ${response.statusCode}');
//       print('📥 First response body: ${response.body}');

//       if (response.statusCode != 200) {
//         throw Exception(
//           'OpenAI API error: ${response.statusCode} ${response.reasonPhrase}'
//         );
//       }

//       final decoded = jsonDecode(response.body) as Map<String, dynamic>;
//       final choices = decoded['choices'] as List<dynamic>;
//       final firstChoice = choices.first as Map<String, dynamic>;
//       final message = firstChoice['message'] as Map<String, dynamic>;
//       print('🔎 Parsed first message:\n$message');

//       Map<String, dynamic> finalScenarios;

//       // 3) If LLM returned a function_call, decode fargs and call the right wrapper
//       if (message.containsKey('function_call')) {
//         final fcall = message['function_call'] as Map<String, dynamic>;
//         final fname = fcall['name'] as String;
//         final argsString = fcall['arguments'] as String?;
//         print('🛠️ LLM requested function: $fname, raw args: $argsString');

//         if (argsString == null) {
//           throw Exception('Function call missing arguments');
//         }

//         final fargs = jsonDecode(_stripCodeFences(argsString)) as Map<String, dynamic>;
//         print('✅ Decoded function args: ${const JsonEncoder.withIndent('  ').convert(fargs)}');

//         late List<List<Map<String, dynamic>>> allChangeLists;

//         if (fname == 'randomPerturbation') {
//           final pm = (fargs['percent_range'] as num).toDouble();
//           final cnt = fargs['count'] as int;
//           print('〽️ Calling randomPerturbation(percentRange=$pm, count=$cnt)');
//           allChangeLists = randomPerturbation(
//             baseModel: baseModel,
//             percentRange: pm,
//             count: cnt,
//           );
//         } else if (fname == 'simplexSweep') {
//           final stepVal = (fargs['step'] as num).toDouble();
//           print('〽️ Calling simplexSweep(step=$stepVal)');
//           allChangeLists = simplexSweep(
//             baseModel: baseModel,
//             step: stepVal,
//           );
//         } else if (fname == 'randomFlowVariationProducer') {
//           final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//           final pm = (fargs['percent_range'] as num).toDouble();
//           final cnt = fargs['count'] as int;
//           print('〽️ Calling safeRandomFlowVariationProducer(flowNames=$fm, percentRange=$pm, count=$cnt)');
//           allChangeLists = safeRandomFlowVariationProducer(
//             baseModel: baseModel,
//             flowNames: fm,
//             percentRange: pm,
//             count: cnt,
//           );
//         } else if (fname == 'randomFlowVariationConsumer') {
//           final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//           final pm = (fargs['percent_range'] as num).toDouble();
//           final cnt = fargs['count'] as int;
//           print('〽️ Calling safeRandomFlowVariationConsumer(flowNames=$fm, percentRange=$pm, count=$cnt)');
//           allChangeLists = safeRandomFlowVariationConsumer(
//             baseModel: baseModel,
//             flowNames: fm,
//             percentRange: pm,
//             count: cnt,
//           );
//         } else if (fname == 'simplexFlowSweep') {
//           final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//           final stepVal = (fargs['step'] as num).toDouble();
//           print('〽️ Calling simplexFlowSweep(flowNames=$fm, step=$stepVal)');
//           allChangeLists = simplexFlowSweep(
//             baseModel: baseModel,
//             flowNames: fm,
//             step: stepVal,
//           );
//         } else {
//           throw Exception('Unexpected function name: $fname');
//         }

//         print('✅ Function returned change lists:\n${const JsonEncoder.withIndent('  ').convert(allChangeLists)}');

//         // 4) Send the changeLists back to LLM for labeling
//         final changeListsJson = jsonEncode({'changeLists': allChangeLists});
//         print('📝 Sending changeLists back for labeling:\n$changeListsJson');

//         final secondMessages = [
//           {'role': 'system', 'content': systemPrompt},
//           {
//             'role': 'assistant',
//             'content': '',
//             'function_call': {
//               'name': fname,
//               'arguments': changeListsJson,
//             }
//           }
//         ];
//         final secondRequest = {
//           'model': 'gpt-4o',
//           'messages': secondMessages,
//         };

//         print('🚀 Sending second ChatCompletion request to OpenAI...');
//         final secondResponse = await http.post(
//           Uri.parse('https://api.openai.com/v1/chat/completions'),
//           headers: {
//             'Content-Type': 'application/json',
//             'Authorization': 'Bearer $openaiApiKey',
//           },
//           body: jsonEncode(secondRequest),
//         );
//         print('📥 Second response status: ${secondResponse.statusCode}');
//         print('📥 Second response body: ${secondResponse.body}');

//         if (secondResponse.statusCode != 200) {
//           throw Exception(
//             'OpenAI second API error: ${secondResponse.statusCode} ${secondResponse.reasonPhrase}'
//           );
//         }

//         final decoded2 = jsonDecode(secondResponse.body) as Map<String, dynamic>;
//         final choices2 = decoded2['choices'] as List<dynamic>;
//         final firstChoice2 = choices2.first as Map<String, dynamic>;
//         final message2 = firstChoice2['message'] as Map<String, dynamic>;
//         final content2 = message2['content'] as String;
//         print('🔎 LLM labeled scenarios:\n$content2');

//         finalScenarios = jsonDecode(_stripCodeFences(content2)) as Map<String, dynamic>;
//         print('✅ Parsed finalScenarios:\n${const JsonEncoder.withIndent('  ').convert(finalScenarios)}');
//       }
//       // 5) Otherwise, LLM returned scenarios directly in "content"
//       else {
//         final content = message['content'] as String?;
//         print('ℹ️ LLM returned scenarios directly in content:\n$content');
//         if (content == null) {
//           throw Exception('No content returned for scenarios');
//         }
//         finalScenarios = jsonDecode(_stripCodeFences(content)) as Map<String, dynamic>;
//         print('✅ Parsed finalScenarios:\n${const JsonEncoder.withIndent('  ').convert(finalScenarios)}');
//       }

//       // 6) Merge the scenarios
//       print('🔄 Merging scenarios with mergeScenarios()...');
//       final rawByScenario = finalScenarios['scenarios'] as Map<String, dynamic>;
//       final Map<String, List<Map<String, dynamic>>> deltasByScenario = {};
//       rawByScenario.forEach((scenarioName, scenarioValue) {
//         final scenarioMap = scenarioValue as Map<String, dynamic>;
//         final changesList = scenarioMap['changes'] as List<dynamic>;
//         deltasByScenario[scenarioName] = changesList.cast<Map<String, dynamic>>();
//       });
//       print('📊 deltasByScenario:\n${const JsonEncoder.withIndent('  ').convert(deltasByScenario)}');

//       final mergedFull = mergeScenarios(baseModel, deltasByScenario);
//       final scenariosMap = mergedFull['scenarios'] as Map<String, dynamic>;
//       print('✅ Merged result (scenariosMap):\n${const JsonEncoder.withIndent('  ').convert(scenariosMap)}');

//       setState(() {
//         _mergedScenarios = scenariosMap;
//       });
//     } catch (e, stack) {
//       print('❌ Error during scenario generation:\n$e\n$stack');
//       setState(() {
//         _mergedScenarios = null;
//       });
//     } finally {
//       setState(() {
//         _isLoading = false;
//         print('🎯 _isLoading set to false');
//       });
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('LLM Scenario Generator'),
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: _isLoading
//             ? Center(child: CircularProgressIndicator())
//             : (_mergedScenarios == null
//                 ? Center(
//                     child: ElevatedButton(
//                       onPressed: _generateAndMergeScenarios,
//                       child: Text('Generate Scenarios'),
//                     ),
//                   )
//                 : Column(
//                     children: [
//                       Expanded(
//                         child:
//                             ScenarioGraphView(scenariosMap: _mergedScenarios!),
//                       ),
//                       SizedBox(height: 16),
//                       ElevatedButton.icon(
//                         onPressed: () {
//                           // TODO: implement Run LCA logic
//                         },
//                         icon: Icon(Icons.play_arrow),
//                         label: Text('Run LCA'),
//                       ),
//                     ],
//                   )),
//       ),
//     );
//   }
// }

// /// Widget that displays each scenario’s graph in a horizontal scroll.
// class ScenarioGraphView extends StatelessWidget {
//   final Map<String, dynamic> scenariosMap;

//   const ScenarioGraphView({required this.scenariosMap});

//   @override
//   Widget build(BuildContext context) {
//     return SingleChildScrollView(
//       scrollDirection: Axis.horizontal,
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: scenariosMap.entries.map((entry) {
//           final scenarioName = entry.key;
//           final model = entry.value['model'] as Map<String, dynamic>;
//           final processesJson =
//               (model['processes'] as List<dynamic>).cast<Map<String, dynamic>>();
//           final flowsJson =
//               (model['flows'] as List<dynamic>).cast<Map<String, dynamic>>();

//           // Convert JSON into ProcessNode objects
//           final processes =
//               processesJson.map((j) => ProcessNode.fromJson(j)).toList();

//           // Compute bounding box so the canvas fits all ProcessNodeWidgets
//           double maxX = 0, maxY = 0;
//           for (var node in processes) {
//             final sz = ProcessNodeWidget.sizeFor(node);
//             final rightEdge = node.position.dx + sz.width;
//             final bottomEdge = node.position.dy + sz.height;
//             if (rightEdge > maxX) maxX = rightEdge;
//             if (bottomEdge > maxY) maxY = bottomEdge;
//           }
//           // Add some padding
//           final canvasWidth = maxX + 20;
//           final canvasHeight = maxY + 20;

//           return Padding(
//             padding: const EdgeInsets.all(8.0),
//             child: Column(
//               children: [
//                 Text(
//                   scenarioName,
//                   style: TextStyle(fontWeight: FontWeight.bold),
//                 ),
//                 SizedBox(
//                   width: canvasWidth,
//                   height: canvasHeight,
//                   child: Card(
//                     elevation: 4,
//                     child: Padding(
//                       padding: const EdgeInsets.all(8.0),
//                       child: Stack(
//                         children: [
//                           // Draw connections behind using UndirectedConnectionPainter
//                           CustomPaint(
//                             size: Size(canvasWidth, canvasHeight),
//                             painter:
//                                 UndirectedConnectionPainter(processes, flowsJson),
//                           ),
//                           // Position each process node
//                           for (var node in processes)
//                             Positioned(
//                               left: node.position.dx,
//                               top: node.position.dy,
//                               child: ProcessNodeWidget(node: node),
//                             ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           );
//         }).toList(),
//       ),
//     );
//   }
// }
// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;

// import '../api/api_key_delete_later.dart';
// import 'home.dart';               // ProcessNode, FlowValue, etc.
// import 'lca_functions.dart';      // randomPerturbation, simplexSweep, safeRandomFlowVariationProducer, safeRandomFlowVariationConsumer, simplexFlowSweep
// import 'scenario_merger.dart';    // mergeScenarios

// const String openaiApiKey = openAIApiKey;

// /// A page that (1) asks GPT‐4o for scenario deltas, (2) displays:
// ///   • A small summary table (“User Prompt” and “Function Called”), and
// ///   • A data table listing each scenario’s proposed changes (one row per change),
// /// and then (3) renders each scenario graph with UndirectedConnectionPainter.
// class LLMPage extends StatefulWidget {
//   final String prompt;
//   final List<ProcessNode> processes;
//   final List<Map<String, dynamic>> flows;

//   const LLMPage({
//     super.key,
//     required this.prompt,
//     required this.processes,
//     required this.flows,
//   });

//   @override
//   State<LLMPage> createState() => _LLMPageState();
// }

// class _LLMPageState extends State<LLMPage> {
//   bool _isLoading = false;

//   /// The final merged scenarios (processed by mergeScenarios)
//   Map<String, dynamic>? _mergedScenarios;

//   /// Raw deltas that GPT returned, before merging: scenarioName → list of changes
//   Map<String, List<Map<String, dynamic>>>? _rawDeltasByScenario;

//   /// Which function (if any) GPT asked us to call
//   String? _capturedFunctionName;

//   /// Utility: strip triple‐backtick code fences from any LLM output
//   String _stripCodeFences(String input) {
//     final fencePattern = RegExp(r'^```(?:json)?\s*');
//     final trailingFencePattern = RegExp(r'\s*```$');
//     var result = input.trim();
//     result = result.replaceAll(fencePattern, '');
//     result = result.replaceAll(trailingFencePattern, '');
//     return result.trim();
//   }

//   Future<void> _generateAndMergeScenarios() async {
//     setState(() {
//       _isLoading = true;
//       _mergedScenarios = null;
//       _rawDeltasByScenario = null;
//       _capturedFunctionName = null;
//     });

//     try {
//       // 1) Build baseModel
//       final baseModel = {
//         'processes': widget.processes.map((p) => p.toJson()).toList(),
//         'flows': widget.flows,
//       };

//       // 2) Prepare userPayload
//       final userPayload = jsonEncode({
//         'scenario_prompt': widget.prompt,
//         'baseModel': baseModel,
//       });

//       // 3) Construct system prompt, including function descriptions
//       final systemPrompt = '''
// You are an expert LCA scenario generator.
// You will receive:
//   1) "scenario_prompt": a free-form description from the user,
//   2) "baseModel": an object with "processes" and "flows".

// Your job:
// - Decide which "inputs" or "outputs" to change for each scenario, and optionally override "co2".
// - Return a JSON with a top-level "scenarios" key. Each scenario name maps to:
//     {
//       "changes": [
//         { "process_id": "<ID>", "field": "inputs.<FlowName>.amount", "new_value": <number> },
//         { "process_id": "<ID>", "field": "outputs.<FlowName>.amount", "new_value": <number> },
//         { "process_id": "<ID>", "field": "co2", "new_value": <number> },
//         // You may also override units with "inputs.<FlowName>.unit" or "outputs.<FlowName>.unit"
//       ]
//     }

// **IMPORTANT**:
// - Do NOT list output or co2 changes if they are automatically derived from input changes.
// - Our client logic (`scenario_merger`) will automatically propagate changes to maintain balance.
// - If no edits are needed in a scenario, set "changes": [].

// ---

// **Available functions**:
// 1) randomPerturbation(percent_range, count):  
//    Generate N random variations of the baseModel by applying ±percent_range% noise to each process’s CO₂.  
//    Returns a list of change-lists (deltas) only.

// 2) simplexSweep(step):  
//    Perform a simplex sweep over all processes’ CO₂. 'step' indicates percentage increments.  
//    Returns a list of change-lists (deltas) only.

// 3) randomFlowVariationProducer(flowNames, percent_range, count):  
//    Generate N random variations of specified flow amounts (producer side only).  
//    Drops any consumer-side changes for shared flows.

// 4) randomFlowVariationConsumer(flowNames, percent_range, count):  
//    Generate N random variations of specified flow amounts (consumer side only).  
//    Drops any producer-side changes for shared flows.

// 5) simplexFlowSweep(flowNames, step):  
//    Perform a simplex-lattice sweep over specified flows. 'step' is the ±% increment.  
//    Returns a list of deltas where each change-list modifies one or two flows by ±step%.  
//    Drops both sides only if explicitly requested.

// Follow these instructions to keep the LCA balanced. Our Dart `scenario_merger` will handle propagation.
// ''';

//       // 4) Functions metadata to send to GPT
//       final functions = [
//         {
//           "name": "randomPerturbation",
//           "description":
//               "Generate N random variations of the baseModel by applying ±percent_range% noise to each process’s CO₂ value. Return a list of change-lists (deltas) only.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "percent_range": {"type": "number"},
//               "count": {"type": "integer"}
//             },
//             "required": ["percent_range", "count"]
//           }
//         },
//         {
//           "name": "simplexSweep",
//           "description":
//               "Perform a simplex sweep over all processes’ CO₂. 'step' indicates percentage increments. Return a list of change-lists (deltas) only.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "step": {"type": "number"}
//             },
//             "required": ["step"]
//           }
//         },
//         {
//           "name": "randomFlowVariationProducer",
//           "description":
//               "Generate N random variations of specified flow amounts (producer side only). Drops any consumer-side changes for shared flows.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "percent_range": {"type": "number"},
//               "count": {"type": "integer"}
//             },
//             "required": ["flowNames", "percent_range", "count"]
//           }
//         },
//         {
//           "name": "randomFlowVariationConsumer",
//           "description":
//               "Generate N random variations of specified flow amounts (consumer side only). Drops any producer-side changes for shared flows.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "percent_range": {"type": "number"},
//               "count": {"type": "integer"}
//             },
//             "required": ["flowNames", "percent_range", "count"]
//           }
//         },
//         {
//           "name": "simplexFlowSweep",
//           "description":
//               "Perform a simplex-lattice sweep over specified flows. 'step' is the ±% increment. Returns a list of deltas where each change-list modifies one or two flows by ±step%. Drops both sides only if explicitly requested.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "step": {"type": "number"}
//             },
//             "required": ["flowNames", "step"]
//           }
//         }
//       ];

//       // 5) First ChatCompletion request
//       final chatRequest = {
//         'model': 'gpt-4o',
//         'messages': [
//           {'role': 'system', 'content': systemPrompt},
//           {'role': 'user', 'content': userPayload},
//         ],
//         'functions': functions,
//         'function_call': 'auto',
//       };
//       final response = await http.post(
//         Uri.parse('https://api.openai.com/v1/chat/completions'),
//         headers: {
//           'Content-Type': 'application/json',
//           'Authorization': 'Bearer $openaiApiKey',
//         },
//         body: jsonEncode(chatRequest),
//       );
//       if (response.statusCode != 200) {
//         throw Exception(
//           'OpenAI API error: ${response.statusCode} ${response.reasonPhrase}'
//         );
//       }

//       final decoded = jsonDecode(response.body) as Map<String, dynamic>;
//       final choices = decoded['choices'] as List<dynamic>;
//       final firstChoice = choices.first as Map<String, dynamic>;
//       final message = firstChoice['message'] as Map<String, dynamic>;

//       Map<String, dynamic> finalScenarios;
//       String functionNameUsed = 'none';

//       // 6) Detect function_call vs. direct content
//       if (message.containsKey('function_call')) {
//         final fcall = message['function_call'] as Map<String, dynamic>;
//         functionNameUsed = fcall['name'] as String;
//         final argsString = fcall['arguments'] as String? ?? '';
//         final fargs =
//             jsonDecode(_stripCodeFences(argsString)) as Map<String, dynamic>;

//         late List<List<Map<String, dynamic>>> allChangeLists;
//         switch (functionNameUsed) {
//           case 'randomPerturbation':
//             final pm = (fargs['percent_range'] as num).toDouble();
//             final cnt = fargs['count'] as int;
//             allChangeLists = randomPerturbation(
//               baseModel: baseModel,
//               percentRange: pm,
//               count: cnt,
//             );
//             break;
//           case 'simplexSweep':
//             final stepVal = (fargs['step'] as num).toDouble();
//             allChangeLists = simplexSweep(
//               baseModel: baseModel,
//               step: stepVal,
//             );
//             break;
//           case 'randomFlowVariationProducer':
//             final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//             final pm = (fargs['percent_range'] as num).toDouble();
//             final cnt = fargs['count'] as int;
//             allChangeLists = safeRandomFlowVariationProducer(
//               baseModel: baseModel,
//               flowNames: fm,
//               percentRange: pm,
//               count: cnt,
//             );
//             break;
//           case 'randomFlowVariationConsumer':
//             final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//             final pm = (fargs['percent_range'] as num).toDouble();
//             final cnt = fargs['count'] as int;
//             allChangeLists = safeRandomFlowVariationConsumer(
//               baseModel: baseModel,
//               flowNames: fm,
//               percentRange: pm,
//               count: cnt,
//             );
//             break;
//           case 'simplexFlowSweep':
//             final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//             final stepVal = (fargs['step'] as num).toDouble();
//             allChangeLists = simplexFlowSweep(
//               baseModel: baseModel,
//               flowNames: fm,
//               step: stepVal,
//             );
//             break;
//           default:
//             throw Exception('Unexpected function name: $functionNameUsed');
//         }

//         // Send change lists back to GPT for labeling
//         final changeListsJson = jsonEncode({'changeLists': allChangeLists});
//         final secondMessages = [
//           {'role': 'system', 'content': systemPrompt},
//           {
//             'role': 'assistant',
//             'content': '',
//             'function_call': {
//               'name': functionNameUsed,
//               'arguments': changeListsJson,
//             }
//           }
//         ];
//         final secondRequest = {
//           'model': 'gpt-4o',
//           'messages': secondMessages,
//         };
//         final secondResponse = await http.post(
//           Uri.parse('https://api.openai.com/v1/chat/completions'),
//           headers: {
//             'Content-Type': 'application/json',
//             'Authorization': 'Bearer $openaiApiKey',
//           },
//           body: jsonEncode(secondRequest),
//         );
//         if (secondResponse.statusCode != 200) {
//           throw Exception(
//             'OpenAI second API error: ${secondResponse.statusCode} ${secondResponse.reasonPhrase}'
//           );
//         }
//         final decoded2 = jsonDecode(secondResponse.body) as Map<String, dynamic>;
//         final choices2 = decoded2['choices'] as List<dynamic>;
//         final firstChoice2 = choices2.first as Map<String, dynamic>;
//         final message2 = firstChoice2['message'] as Map<String, dynamic>;
//         final content2 = message2['content'] as String;
//         finalScenarios = jsonDecode(_stripCodeFences(content2)) as Map<String, dynamic>;
//       } else {
//         final content = message['content'] as String? ?? '';
//         finalScenarios = jsonDecode(_stripCodeFences(content)) as Map<String, dynamic>;
//       }

//       // 7) Extract raw deltas by scenario
//       final rawByScenario = finalScenarios['scenarios'] as Map<String, dynamic>;
//       final Map<String, List<Map<String, dynamic>>> deltasByScenario = {};
//       rawByScenario.forEach((scenarioName, scenarioValue) {
//         final scenarioMap = scenarioValue as Map<String, dynamic>;
//         final changesList = scenarioMap['changes'] as List<dynamic>;
//         deltasByScenario[scenarioName] = changesList.cast<Map<String, dynamic>>();
//       });

//       // 8) Merge the scenarios
//       final mergedFull = mergeScenarios(baseModel, deltasByScenario);
//       final scenariosMap = mergedFull['scenarios'] as Map<String, dynamic>;

//       setState(() {
//         _capturedFunctionName = functionNameUsed;
//         _rawDeltasByScenario = deltasByScenario;
//         _mergedScenarios = scenariosMap;
//       });
//     } catch (e, stack) {
//       // If anything fails, clear outputs (graphs) but leave _capturedFunctionName and _rawDeltasByScenario null
//       setState(() {
//         _mergedScenarios = null;
//         _rawDeltasByScenario = null;
//         _capturedFunctionName = null;
//       });
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('LLM Scenario Generator'),
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: _isLoading
//             ? Center(child: CircularProgressIndicator())
//             : (_mergedScenarios == null
//                 ? Center(
//                     child: ElevatedButton(
//                       onPressed: _generateAndMergeScenarios,
//                       child: Text('Generate Scenarios'),
//                     ),
//                   )
//                 : SingleChildScrollView(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         // ——— Horizontal summary table: User Prompt + Function Called ———
//                         SingleChildScrollView(
//                           scrollDirection: Axis.horizontal,
//                           child: DataTable(
//                             columns: const [
//                               DataColumn(label: Text('User Prompt')),
//                               DataColumn(label: Text('Function Called by GPT')),
//                             ],
//                             rows: [
//                               DataRow(
//                                 cells: [
//                                   DataCell(
//                                     ConstrainedBox(
//                                       constraints: BoxConstraints(maxWidth: 300),
//                                       child: Text(
//                                         widget.prompt,
//                                         style: TextStyle(fontSize: 14),
//                                       ),
//                                     ),
//                                   ),
//                                   DataCell(
//                                     Text(
//                                       _capturedFunctionName ?? 'none',
//                                       style: TextStyle(fontSize: 14),
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ],
//                           ),
//                         ),
//                         SizedBox(height: 16),

//                         // ——— Horizontal table summarizing all scenario changes ———
//                         SingleChildScrollView(
//                           scrollDirection: Axis.horizontal,
//                           child: DataTable(
//                             columns: const [
//                               DataColumn(label: Text('Scenario')),
//                               DataColumn(label: Text('Process ID')),
//                               DataColumn(label: Text('Field')),
//                               DataColumn(label: Text('New Value')),
//                             ],
//                             rows: _buildChangeRows(),
//                           ),
//                         ),
//                         SizedBox(height: 16),

//                         // ——— Scenario Graphs ———
//                         SizedBox(
//                           height: 400, // fix height so graphs show below the tables
//                           child: ScenarioGraphView(
//                             scenariosMap: _mergedScenarios!,
//                           ),
//                         ),
//                         SizedBox(height: 16),
//                         ElevatedButton.icon(
//                           onPressed: () {
//                             // TODO: implement Run LCA logic
//                           },
//                           icon: Icon(Icons.play_arrow),
//                           label: Text('Run LCA'),
//                         ),
//                       ],
//                     ),
//                   )),
//       ),
//     );
//   }

//   /// Build one DataRow per change in each scenario.
//   List<DataRow> _buildChangeRows() {
//     final rows = <DataRow>[];
//     if (_rawDeltasByScenario == null) return rows;

//     _rawDeltasByScenario!.forEach((scenarioName, changes) {
//       for (var change in changes) {
//         final pid = change['process_id'] as String;
//         final field = change['field'] as String;
//         final newVal = change['new_value'].toString();
//         rows.add(
//           DataRow(
//             cells: [
//               DataCell(Text(scenarioName)),
//               DataCell(Text(pid)),
//               DataCell(Text(field)),
//               DataCell(Text(newVal)),
//             ],
//           ),
//         );
//       }
//       // If a scenario has no changes, still show a single row with “(no changes)”
//       if (changes.isEmpty) {
//         rows.add(
//           DataRow(
//             cells: [
//               DataCell(Text(scenarioName)),
//               DataCell(Text('(no changes)', style: TextStyle(fontStyle: FontStyle.italic))),
//               DataCell(Text('-', style: TextStyle(fontStyle: FontStyle.italic))),
//               DataCell(Text('-', style: TextStyle(fontStyle: FontStyle.italic))),
//             ],
//           ),
//         );
//       }
//     });

//     return rows;
//   }
// }

// /// Widget that displays each scenario’s graph in a horizontal scroll.
// class ScenarioGraphView extends StatelessWidget {
//   final Map<String, dynamic> scenariosMap;

//   const ScenarioGraphView({required this.scenariosMap});

//   @override
//   Widget build(BuildContext context) {
//     return SingleChildScrollView(
//       scrollDirection: Axis.horizontal,
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: scenariosMap.entries.map((entry) {
//           final scenarioName = entry.key;
//           final model = entry.value['model'] as Map<String, dynamic>;
//           final processesJson =
//               (model['processes'] as List<dynamic>).cast<Map<String, dynamic>>();
//           final flowsJson =
//               (model['flows'] as List<dynamic>).cast<Map<String, dynamic>>();

//           // Convert JSON into ProcessNode objects
//           final processes =
//               processesJson.map((j) => ProcessNode.fromJson(j)).toList();

//           // Compute bounding box so the canvas fits all ProcessNodeWidgets
//           double maxX = 0, maxY = 0;
//           for (var node in processes) {
//             final sz = ProcessNodeWidget.sizeFor(node);
//             final rightEdge = node.position.dx + sz.width;
//             final bottomEdge = node.position.dy + sz.height;
//             if (rightEdge > maxX) maxX = rightEdge;
//             if (bottomEdge > maxY) maxY = bottomEdge;
//           }
//           // Add some padding
//           final canvasWidth = maxX + 20;
//           final canvasHeight = maxY + 20;

//           return Padding(
//             padding: const EdgeInsets.all(8.0),
//             child: Column(
//               children: [
//                 Text(
//                   scenarioName,
//                   style: TextStyle(fontWeight: FontWeight.bold),
//                 ),
//                 SizedBox(
//                   width: canvasWidth,
//                   height: canvasHeight,
//                   child: Card(
//                     elevation: 4,
//                     child: Padding(
//                       padding: const EdgeInsets.all(8.0),
//                       child: Stack(
//                         children: [
//                           // Draw connections behind using UndirectedConnectionPainter
//                           CustomPaint(
//                             size: Size(canvasWidth, canvasHeight),
//                             painter: UndirectedConnectionPainter(processes, flowsJson),
//                           ),
//                           // Position each process node
//                           for (var node in processes)
//                             Positioned(
//                               left: node.position.dx,
//                               top: node.position.dy,
//                               child: ProcessNodeWidget(node: node),
//                             ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           );
//         }).toList(),
//       ),
//     );
//   }
// }

// // File: lib/zzzz/llm_page.dart

// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;

// import '../api/api_key_delete_later.dart';
// import 'home.dart';               // ProcessNode, FlowValue, etc.
// import 'lca_functions.dart';      // oneAtATimeSensitivity, fullSystemUncertainty, simplexLatticeDesign
// import 'scenario_merger.dart';    // mergeScenarios

// const String openaiApiKey = openAIApiKey;

// /// A page that:
// ///  1) Sends the user’s prompt + baseModel to GPT‐4o along with exactly three functions:
// ///     • oneAtATimeSensitivity
// ///     • fullSystemUncertainty
// ///     • simplexLatticeDesign
// ///  2) Displays a small summary table (“User Prompt” + “Function Called”)
// ///  3) Displays a data table listing every scenario & its individual changes
// ///  4) Renders each scenario graph with UndirectedConnectionPainter
// class LLMPage extends StatefulWidget {
//   final String prompt;
//   final List<ProcessNode> processes;
//   final List<Map<String, dynamic>> flows;

//   const LLMPage({
//     super.key,
//     required this.prompt,
//     required this.processes,
//     required this.flows,
//   });

//   @override
//   State<LLMPage> createState() => _LLMPageState();
// }

// class _LLMPageState extends State<LLMPage> {
//   bool _isLoading = false;

//   /// Merged scenarios returned by mergeScenarios(...)
//   Map<String, dynamic>? _mergedScenarios;

//   /// Raw deltas from GPT: scenarioName -> list of change maps
//   Map<String, List<Map<String, dynamic>>>? _rawDeltasByScenario;

//   /// The name of the function GPT chose to call (or "none" if it returned scenarios directly)
//   String? _capturedFunctionName;

//   /// Helper to strip any ```json code fences in GPT outputs
//   String _stripCodeFences(String input) {
//     final fencePattern = RegExp(r'^```(?:json)?\s*');
//     final trailingFencePattern = RegExp(r'\s*```$');
//     var result = input.trim();
//     result = result.replaceAll(fencePattern, '');
//     result = result.replaceAll(trailingFencePattern, '');
//     return result.trim();
//   }

//   Future<void> _generateAndMergeScenarios() async {
//     setState(() {
//       _isLoading = true;
//       _mergedScenarios = null;
//       _rawDeltasByScenario = null;
//       _capturedFunctionName = null;
//     });

//     try {
//       // 1) Build baseModel JSON
//       final baseModel = {
//         'processes': widget.processes.map((p) => p.toJson()).toList(),
//         'flows': widget.flows,
//       };

//       // 2) Prepare user payload
//       final userPayload = jsonEncode({
//         'scenario_prompt': widget.prompt,
//         'baseModel': baseModel,
//       });

//       // 3) Construct system prompt listing exactly the three functions
//       final systemPrompt = '''
// You are an expert LCA scenario generator.
// You will receive:
//   1) "scenario_prompt": a free‐form description from the user,
//   2) "baseModel": an object with "processes" and "flows".

// Your job:
// - Decide which of the three available functions best fits the user’s request:
//     1) oneAtATimeSensitivity(flowNames, percent, [levels])
//     2) fullSystemUncertainty(percent, [levels])
//     3) simplexLatticeDesign(flowNames, m)

// - oneAtATimeSensitivity:
//     • For each flow in "flowNames", vary that flow by ±percent% (and by each level in "levels" if provided),
//       holding all other flows at baseline.

// - fullSystemUncertainty:
//     • Scale every single input and output flow in the model by ±percent% (and by each level in "levels" if provided).
//       Produces “all‐up” and “all‐down” scenarios.

// - simplexLatticeDesign:
//     • Let q = number of items in "flowNames", and m = integer. Build all boundary points on the q‐simplex
//       with coordinates xi ∈ {0, 1/m, 2/m, …, 1} subject to sum(xi)=1. Includes centroid when appropriate.

// Return only a JSON with a top‐level "scenarios" key. Each key under "scenarios" is the scenario name,
// and its value is:
//   {
//     "changes": [
//       { "process_id": "<ID>", "field": "inputs.<FlowName>.amount", "new_value": <number> },
//       { "process_id": "<ID>", "field": "outputs.<FlowName>.amount", "new_value": <number> },
//       // Do not include any other fields.
//     ]
//   }

// If you choose to call one of the functions, emit a function_call with:
//   {
//     "name": "<functionName>",
//     "arguments": { ... }
//   }

// If the user’s request does not require any edits, return `"changes": []` for a single “baseline” scenario.
// ''';

//       // 4) Define the functions metadata for GPT
//       final functions = [
//         {
//           "name": "oneAtATimeSensitivity",
//           "description":
//               "For each flow in flowNames, generate scenarios that vary that flow by ±percent (default 10%) or by each level in levels[], holding all other flows at baseline. Returns a list of change-lists.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "percent": {"type": "number"},
//               "levels": {
//                 "type": "array",
//                 "items": {"type": "number"}
//               }
//             },
//             "required": ["flowNames", "percent"]
//           }
//         },
//         {
//           "name": "fullSystemUncertainty",
//           "description":
//               "Scale every input and output flow in the entire model by ±percent (default 10%) or by each level in levels[]. Returns two or more change-lists.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "percent": {"type": "number"},
//               "levels": {
//                 "type": "array",
//                 "items": {"type": "number"}
//               }
//             },
//             "required": ["percent"]
//           }
//         },
//         {
//           "name": "simplexLatticeDesign",
//           "description":
//               "Build a {q,m} simplex-lattice design for q components listed in flowNames. Each xi ∈ {0,1/m,2/m,…,1} with sum(xi)=1. Returns a list of change-lists that override input flows proportionally.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "m": {"type": "integer"}
//             },
//             "required": ["flowNames", "m"]
//           }
//         }
//       ];

//       // 5) Send first ChatCompletion request
//       final chatRequest = {
//         'model': 'gpt-4o',
//         'messages': [
//           {'role': 'system', 'content': systemPrompt},
//           {'role': 'user', 'content': userPayload},
//         ],
//         'functions': functions,
//         'function_call': 'auto',
//       };
//       final response = await http.post(
//         Uri.parse('https://api.openai.com/v1/chat/completions'),
//         headers: {
//           'Content-Type': 'application/json',
//           'Authorization': 'Bearer $openaiApiKey',
//         },
//         body: jsonEncode(chatRequest),
//       );
//       if (response.statusCode != 200) {
//         throw Exception('OpenAI API error: ${response.statusCode} ${response.reasonPhrase}');
//       }

//       final decoded = jsonDecode(response.body) as Map<String, dynamic>;
//       final choices = decoded['choices'] as List<dynamic>;
//       final firstChoice = choices.first as Map<String, dynamic>;
//       final message = firstChoice['message'] as Map<String, dynamic>;

//       Map<String, dynamic> finalScenarios;
//       String functionNameUsed = 'none';

//       // 6) Handle function_call or direct content
//       if (message.containsKey('function_call')) {
//         final fcall = message['function_call'] as Map<String, dynamic>;
//         functionNameUsed = fcall['name'] as String;
//         final argsString = fcall['arguments'] as String? ?? '';
//         final fargs = jsonDecode(_stripCodeFences(argsString)) as Map<String, dynamic>;

//         late List<List<Map<String, dynamic>>> allChangeLists;

//         switch (functionNameUsed) {
//           case 'oneAtATimeSensitivity':
//             final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//             final pm = (fargs['percent'] as num).toDouble();
//             final levelsList = (fargs['levels'] as List<dynamic>?)
//                 ?.cast<num>()
//                 .map((n) => n.toDouble())
//                 .toList();
//             allChangeLists = oneAtATimeSensitivity(
//               baseModel: baseModel,
//               flowNames: fm,
//               percent: pm,
//               levels: levelsList,
//             );
//             break;

//           case 'fullSystemUncertainty':
//             final pm = (fargs['percent'] as num).toDouble();
//             final levelsList = (fargs['levels'] as List<dynamic>?)
//                 ?.cast<num>()
//                 .map((n) => n.toDouble())
//                 .toList();
//             allChangeLists = fullSystemUncertainty(
//               baseModel: baseModel,
//               percent: pm,
//               levels: levelsList,
//             );
//             break;

//           case 'simplexLatticeDesign':
//             final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//             final mm = (fargs['m'] as num).toInt();
//             allChangeLists = simplexLatticeDesign(
//               baseModel: baseModel,
//               flowNames: fm,
//               m: mm,
//             );
//             break;

//           default:
//             throw Exception('Unexpected function name: $functionNameUsed');
//         }

//         // 7) Send changeLists back to GPT for scenario naming
//         final changeListsJson = jsonEncode({'changeLists': allChangeLists});
//         final secondMessages = [
//           {'role': 'system', 'content': systemPrompt},
//           {
//             'role': 'assistant',
//             'content': '',
//             'function_call': {
//               'name': functionNameUsed,
//               'arguments': changeListsJson,
//             }
//           }
//         ];
//         final secondRequest = {
//           'model': 'gpt-4o',
//           'messages': secondMessages,
//         };

//         final secondResponse = await http.post(
//           Uri.parse('https://api.openai.com/v1/chat/completions'),
//           headers: {
//             'Content-Type': 'application/json',
//             'Authorization': 'Bearer $openaiApiKey',
//           },
//           body: jsonEncode(secondRequest),
//         );
//         if (secondResponse.statusCode != 200) {
//           throw Exception(
//             'OpenAI second API error: ${secondResponse.statusCode} ${secondResponse.reasonPhrase}'
//           );
//         }
//         final decoded2 = jsonDecode(secondResponse.body) as Map<String, dynamic>;
//         final choices2 = decoded2['choices'] as List<dynamic>;
//         final firstChoice2 = choices2.first as Map<String, dynamic>;
//         final message2 = firstChoice2['message'] as Map<String, dynamic>;
//         final content2 = message2['content'] as String;
//         finalScenarios = jsonDecode(_stripCodeFences(content2)) as Map<String, dynamic>;
//       } else {
//         final content = message['content'] as String? ?? '';
//         finalScenarios = jsonDecode(_stripCodeFences(content)) as Map<String, dynamic>;
//       }

//       // 8) Extract raw deltas by scenario
//       final rawByScenario = finalScenarios['scenarios'] as Map<String, dynamic>;
//       final Map<String, List<Map<String, dynamic>>> deltasByScenario = {};
//       rawByScenario.forEach((scenarioName, scenarioValue) {
//         final scenarioMap = scenarioValue as Map<String, dynamic>;
//         final changesList = scenarioMap['changes'] as List<dynamic>;
//         deltasByScenario[scenarioName] = changesList.cast<Map<String, dynamic>>();
//       });

//       // 9) Merge with mergeScenarios()
//       final mergedFull = mergeScenarios(baseModel, deltasByScenario);
//       final scenariosMap = mergedFull['scenarios'] as Map<String, dynamic>;

//       setState(() {
//         _capturedFunctionName = functionNameUsed;
//         _rawDeltasByScenario = deltasByScenario;
//         _mergedScenarios = scenariosMap;
//       });
//     } catch (e, stack) {
//       // On error, clear results
//       setState(() {
//         _mergedScenarios = null;
//         _rawDeltasByScenario = null;
//         _capturedFunctionName = null;
//       });
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('LLM Scenario Generator'),
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: _isLoading
//             ? Center(child: CircularProgressIndicator())
//             : (_mergedScenarios == null
//                 ? Center(
//                     child: ElevatedButton(
//                       onPressed: _generateAndMergeScenarios,
//                       child: Text('Generate Scenarios'),
//                     ),
//                   )
//                 : SingleChildScrollView(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         // ——— Summary Table: User Prompt + Function Called ———
//                         SingleChildScrollView(
//                           scrollDirection: Axis.horizontal,
//                           child: DataTable(
//                             columns: const [
//                               DataColumn(label: Text('User Prompt')),
//                               DataColumn(label: Text('Function Called')),
//                             ],
//                             rows: [
//                               DataRow(
//                                 cells: [
//                                   DataCell(
//                                     ConstrainedBox(
//                                       constraints: BoxConstraints(maxWidth: 300),
//                                       child: Text(
//                                         widget.prompt,
//                                         style: TextStyle(fontSize: 14),
//                                       ),
//                                     ),
//                                   ),
//                                   DataCell(
//                                     Text(
//                                       _capturedFunctionName ?? 'none',
//                                       style: TextStyle(fontSize: 14),
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ],
//                           ),
//                         ),
//                         SizedBox(height: 16),

//                         // ——— Detailed Table: Scenario / Process / Field / New Value ———
//                         SingleChildScrollView(
//                           scrollDirection: Axis.horizontal,
//                           child: DataTable(
//                             columns: const [
//                               DataColumn(label: Text('Scenario')),
//                               DataColumn(label: Text('Process ID')),
//                               DataColumn(label: Text('Field')),
//                               DataColumn(label: Text('New Value')),
//                             ],
//                             rows: _buildChangeRows(),
//                           ),
//                         ),
//                         SizedBox(height: 16),

//                         // ——— Scenario Graphs ———
//                         SizedBox(
//                           height: 400, // fixed height so tables scroll first
//                           child: ScenarioGraphView(
//                             scenariosMap: _mergedScenarios!,
//                           ),
//                         ),
//                         SizedBox(height: 16),
//                         ElevatedButton.icon(
//                           onPressed: () {
//                             // TODO: implement Run LCA logic
//                           },
//                           icon: Icon(Icons.play_arrow),
//                           label: Text('Run LCA'),
//                         ),
//                       ],
//                     ),
//                   )),
//       ),
//     );
//   }

//   /// Build one DataRow per change in each scenario
//   List<DataRow> _buildChangeRows() {
//     final rows = <DataRow>[];
//     if (_rawDeltasByScenario == null) return rows;

//     _rawDeltasByScenario!.forEach((scenarioName, changes) {
//       if (changes.isEmpty) {
//         rows.add(
//           DataRow(
//             cells: [
//               DataCell(Text(scenarioName)),
//               DataCell(Text('(no changes)', style: TextStyle(fontStyle: FontStyle.italic))),
//               DataCell(Text('-', style: TextStyle(fontStyle: FontStyle.italic))),
//               DataCell(Text('-', style: TextStyle(fontStyle: FontStyle.italic))),
//             ],
//           ),
//         );
//       } else {
//         for (var change in changes) {
//           final pid = change['process_id'] as String;
//           final field = change['field'] as String;
//           final newVal = change['new_value'].toString();
//           rows.add(
//             DataRow(
//               cells: [
//                 DataCell(Text(scenarioName)),
//                 DataCell(Text(pid)),
//                 DataCell(Text(field)),
//                 DataCell(Text(newVal)),
//               ],
//             ),
//           );
//         }
//       }
//     });

//     return rows;
//   }
// }
// /// Widget that displays each scenario’s graph in a horizontal scroll.
// /// If a single graph is taller than the viewport, it will scroll vertically.
// class ScenarioGraphView extends StatelessWidget {
//   final Map<String, dynamic> scenariosMap;

//   const ScenarioGraphView({required this.scenariosMap});

//   @override
//   Widget build(BuildContext context) {
//     return SingleChildScrollView(
//       scrollDirection: Axis.horizontal,
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: scenariosMap.entries.map((entry) {
//           final String scenarioName = entry.key;
//           final Map<String, dynamic> model = entry.value['model'] as Map<String, dynamic>;
//           final List<Map<String, dynamic>> processesJson =
//               (model['processes'] as List<dynamic>).cast<Map<String, dynamic>>();
//           final List<Map<String, dynamic>> flowsJson =
//               (model['flows'] as List<dynamic>).cast<Map<String, dynamic>>();

//           // Convert JSON into ProcessNode objects
//           final List<ProcessNode> processes =
//               processesJson.map((j) => ProcessNode.fromJson(j)).toList();

//           // Compute bounding box so the canvas fits all ProcessNodeWidgets
//           double maxX = 0, maxY = 0;
//           for (var node in processes) {
//             final sz = ProcessNodeWidget.sizeFor(node);
//             final double rightEdge = node.position.dx + sz.width;
//             final double bottomEdge = node.position.dy + sz.height;
//             if (rightEdge > maxX) maxX = rightEdge;
//             if (bottomEdge > maxY) maxY = bottomEdge;
//           }
//           // Add some padding around the canvas
//           final double canvasWidth = maxX + 20;
//           final double canvasHeight = maxY + 20;

//           return Padding(
//             padding: const EdgeInsets.all(8.0),
//             child: SizedBox(
//               width: canvasWidth + 16, // extra padding for vertical scroll view
//               child: SingleChildScrollView(
//                 scrollDirection: Axis.vertical,
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.center,
//                   children: [
//                     Text(
//                       scenarioName,
//                       style: TextStyle(fontWeight: FontWeight.bold),
//                     ),
//                     SizedBox(
//                       width: canvasWidth,
//                       height: canvasHeight,
//                       child: Card(
//                         elevation: 4,
//                         child: Padding(
//                           padding: const EdgeInsets.all(8.0),
//                           child: Stack(
//                             children: [
//                               // Draw connections behind using UndirectedConnectionPainter
//                               CustomPaint(
//                                 size: Size(canvasWidth, canvasHeight),
//                                 painter: UndirectedConnectionPainter(processes, flowsJson),
//                               ),
//                               // Position each process node
//                               for (var node in processes)
//                                 Positioned(
//                                   left: node.position.dx,
//                                   top: node.position.dy,
//                                   child: ProcessNodeWidget(node: node),
//                                 ),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           );
//         }).toList(),
//       ),
//     );
//   }
// }
// // File: lib/zzzz/llm_page.dart
// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;

// import '../api/api_key_delete_later.dart';
// import 'home.dart';               // ProcessNode, FlowValue, ProcessNodeWidget, UndirectedConnectionPainter, etc.
// import 'lca_functions.dart';      // oneAtATimeSensitivity, fullSystemUncertainty, simplexLatticeDesign
// import 'scenario_merger.dart';    // mergeScenarios

// const String openaiApiKey = openAIApiKey;

// /// A page that:
// ///   1) Sends the user’s prompt + baseModel to GPT-4o along with exactly three functions:
// ///      • oneAtATimeSensitivity
// ///      • fullSystemUncertainty
// ///      • simplexLatticeDesign
// ///   2) Displays a small summary table (“User Prompt” + “Function Called”)
// ///   3) Displays a data table listing every scenario & its individual changes
// ///   4) Renders each scenario graph with UndirectedConnectionPainter
// ///
// /// The system prompt is written to be robust: it embeds a strict JSON schema for all allowed
// /// “change” entries (numeric adjustments, renames, additions), includes an explicit “no extra keys”
// /// reminder, and shows short examples. This ensures GPT-4o will produce valid JSON that your
// /// Dart code can parse and merge correctly, even when the user asks for process/flow renaming or creation.
// class LLMPage extends StatefulWidget {
//   final String prompt;
//   final List<ProcessNode> processes;
//   final List<Map<String, dynamic>> flows;

//   const LLMPage({
//     super.key,
//     required this.prompt,
//     required this.processes,
//     required this.flows,
//   });

//   @override
//   State<LLMPage> createState() => _LLMPageState();
// }

// class _LLMPageState extends State<LLMPage> {
//   bool _isLoading = false;

//   /// Merged scenarios returned by mergeScenarios(...)
//   Map<String, dynamic>? _mergedScenarios;

//   /// Raw deltas from GPT: scenarioName -> list of change maps
//   Map<String, List<Map<String, dynamic>>>? _rawDeltasByScenario;

//   /// The name of the function GPT chose to call (or "none" if it returned scenarios directly)
//   String? _capturedFunctionName;

//   /// Strips any ```json code fences from GPT outputs
//   String _stripCodeFences(String input) {
//     final fencePattern = RegExp(r'^```(?:json)?\s*', multiLine: true);
//     final trailingFencePattern = RegExp(r'\s*```$', multiLine: true);
//     var result = input.trim();
//     result = result.replaceAll(fencePattern, '');
//     result = result.replaceAll(trailingFencePattern, '');
//     return result.trim();
//   }

//   Future<void> _generateAndMergeScenarios() async {
//     setState(() {
//       _isLoading = true;
//       _mergedScenarios = null;
//       _rawDeltasByScenario = null;
//       _capturedFunctionName = null;
//     });

//     try {
//       // 1) Build baseModel JSON
//       final baseModel = {
//         'processes': widget.processes.map((p) => p.toJson()).toList(),
//         'flows': widget.flows,
//       };
//       print("=== Debug: baseModel JSON ===");
//       print(jsonEncode(baseModel));

//       // 2) Prepare user payload
//       final userPayload = jsonEncode({
//         'scenario_prompt': widget.prompt,
//         'baseModel': baseModel,
//       });
//       print("=== Debug: userPayload ===");
//       print(userPayload);

//       // 3) Construct system prompt describing the three functions
//       //    and a strict schema for renaming/adding processes/flows
//       final systemPrompt = r'''
// You are an expert LCA scenario generator. 
// You will receive two things:
//   1) "scenario_prompt": a free‐form description from the user
//   2) "baseModel": { "processes": [ … ], "flows": [ … ] }

// Your job:
//   1. Decide if the user wants to:
//      • Run a sensitivity / uncertainty / simplex‐lattice design calculation 
//        via oneAtATimeSensitivity, fullSystemUncertainty, or simplexLatticeDesign,
//      OR
//      • Rename or add new processes or flows (structural edits),
//      OR
//      • A combination of both (e.g., “do a one‐at‐a‐time sensitivity, then rename the glass process to X”).

//   2. Return exactly one JSON object with a single top‐level key: 
//      {
//        "scenarios": {
//          "<scenarioName>": {
//            "changes": [
//              { … change‐descriptor A … },
//              { … change‐descriptor B … },
//              …
//            ]
//          },
//          "<anotherScenario>": { … },
//          …
//        }
//      }

//   3. Do **not** output any text outside of this JSON object (no prose, no markdown).

// Important: Your response must be valid JSON—no extra keys, no comments, no text outside the JSON. 
// Keys not listed below will be removed by the client. If you include any unrecognized key, 
// the client will reject your output.

// **JSON Schema for each “change” entry** (choose exactly one of these forms):

//   A) **Numeric adjustment (inputs/outputs):**

//      {
//        "process_id":   "<existing‐process‐ID‐string>",
//        "field":        "inputs.<flowName>.amount"
//                       OR "outputs.<flowName>.amount",
//        "new_value":    <a numeric value>
//      }

//   B) **Rename an existing process:**

//      {
//        "process_id": "<existing‐process‐ID‐string>",
//        "field":      "name",
//        "new_value":  "<new process name string>"
//      }

//   C) **Rename an existing flow:**

//      {
//        "flow_id":  "<existing‐flow‐ID‐string>",
//        "field":    "name",
//        "new_value":"<new flow name string>"
//      }

//   D) **Add a new process (full ProcessNode JSON must match your app’s `ProcessNode.toJson()` exactly):**

//      {
//        "action":  "add_process",
//        "process": {
//          "id":       "<new‐process‐ID>",
//          "name":     "<new process name>",
//          "position": { "dx": <number>, "dy": <number> },
//          "inputs":   { "<flowName>": { "amount": <number>, "unit": "<unit‐string>" }, … },
//          "outputs":  { "<flowName>": { "amount": <number>, "unit": "<unit‐string>" }, … }
//          // include any other fields exactly as defined in your ProcessNode JSON schema
//        }
//      }

//   E) **Add a new flow:**

//      {
//        "action": "add_flow",
//        "flow": {
//          "id":        "<new‐flow‐ID>",
//          "name":      "<new flow name>",
//          "unit":      "<unit‐string>",
//          "location":  "<location‐string>",
//          "value":     <number>
//          // include any other fields exactly as defined in your Flow JSON schema
//        }
//      }

// **Rules for function calls**:
//   - If you detect that the user’s request requires one of the three built‐in functions (oneAtATimeSensitivity, fullSystemUncertainty, simplexLatticeDesign), reply with exactly:
//     {
//       "function_call": {
//         "name": "<chosenFunctionName>",
//         "arguments": { … }
//       }
//     }
//     where `<chosenFunctionName>` is one of those three. The `arguments` object must match the function’s parameter schema exactly:
//       • oneAtATimeSensitivity:
//         {
//           "flowNames": [ "<flowName1>", … ],
//           "percent":   <number>,
//           "levels":    [ <number>, … ]   // optional
//         }
//       • fullSystemUncertainty:
//         {
//           "percent": <number>,
//           "levels":  [ <number>, … ]   // optional
//         }
//       • simplexLatticeDesign:
//         {
//           "flowNames": [ "<flowName1>", … ],
//           "m":         <integer>
//         }

//   - **Do not include any “scenarios” key in the same message as a function_call.** Once your client sees the function_call, it will compute the numeric change lists and send them back to you for naming.

//   - If the user’s request involves only renames/adds (no numeric scenarios), return the “scenarios” object directly (skip function_call):
//     {
//       "scenarios": {
//         "baseline": {
//           "changes": [
//             { … structural edit 1 … },
//             { … structural edit 2 … },
//             …
//           ]
//         }
//       }
//     }

//   - If the user wants a mix (e.g. “run oneAtATimeSensitivity, then rename glass process”), do **both**:
//     1) Return a function_call for the numeric part.
//     2) In the follow‐up (after receiving numeric results), append your structural “rename” / “add” entries at the end of each scenario’s “changes” list.

// If no edits are required (true baseline), return:
// {
//   "scenarios": {
//     "baseline": {
//       "changes": []
//     }
//   }
// }

// **Short Examples**:

// Example 1 (renaming a process without any numeric changes):

// User: “Please rename the process with ID 'proc_water_glass_01' to 'pultrusion_composite' and add a new flow 'fiber_A' with ID 'flow_fiber_A' (unit: kg, value: 1.0).”

// Output:
// {
//   "scenarios": {
//     "baseline": {
//       "changes": [
//         {
//           "process_id": "proc_water_glass_01",
//           "field":      "name",
//           "new_value":  "pultrusion_composite"
//         },
//         {
//           "action": "add_flow",
//           "flow": {
//             "id":       "flow_fiber_A",
//             "name":     "fiber_A",
//             "unit":     "kg",
//             "location": "CH",
//             "value":    1.0
//           }
//         }
//       ]
//     }
//   }
// }

// Example 2 (oneAtATimeSensitivity on flows ["glass", "energy"], ±10%):

// User: “Run a one-at-a-time sensitivity on flows 'glass' and 'energy' by ±10%.”

// Assistant → function_call:
// {
//   "function_call": {
//     "name": "oneAtATimeSensitivity",
//     "arguments": {
//       "flowNames": ["glass", "energy"],
//       "percent":   10.0
//     }
//   }
// }

// (… your client will compute the ±10% change lists and send them back for scenario naming …)
// ''';

//       // 4) Define the functions metadata for GPT
//       final functions = [
//         {
//           "name": "oneAtATimeSensitivity",
//           "description":
//               "For each flow in flowNames, generate scenarios that vary that flow by ±percent% (or by each level in levels[]) while holding other flows at baseline. Returns a list of change‐lists.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "percent": {"type": "number"},
//               "levels": {
//                 "type": "array",
//                 "items": {"type": "number"}
//               }
//             },
//             "required": ["flowNames", "percent"]
//           }
//         },
//         {
//           "name": "fullSystemUncertainty",
//           "description":
//               "Scale every input and output flow in the entire model by ±percent% (or by each level in levels[]). Returns a list of change‐lists.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "percent": {"type": "number"},
//               "levels": {
//                 "type": "array",
//                 "items": {"type": "number"}
//               }
//             },
//             "required": ["percent"]
//           }
//         },
//         {
//           "name": "simplexLatticeDesign",
//           "description":
//               "Build a {q,m} simplex‐lattice design for the flows listed in flowNames. Each xi ∈ {0, 1/m, 2/m, …, 1} subject to ∑xi=1. Returns a list of change‐lists overriding input flows.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "m": {"type": "integer"}
//             },
//             "required": ["flowNames", "m"]
//           }
//         }
//       ];

//       // 5) Send the first ChatCompletion request
//       final chatRequest = {
//         'model': 'gpt-4o',
//         'messages': [
//           {'role': 'system', 'content': systemPrompt},
//           {'role': 'user', 'content': userPayload},
//         ],
//         'functions': functions,
//         'function_call': 'auto',
//       };
//       print("=== Debug: Sending first chat.completions request ===");
//       print(jsonEncode(chatRequest));

//       final response = await http.post(
//         Uri.parse('https://api.openai.com/v1/chat/completions'),
//         headers: {
//           'Content-Type': 'application/json',
//           'Authorization': 'Bearer $openaiApiKey',
//         },
//         body: jsonEncode(chatRequest),
//       );

//       print("=== Debug: First response status = ${response.statusCode} ===");
//       print("=== Debug: First response body ===");
//       print(response.body);

//       if (response.statusCode != 200) {
//         throw Exception('OpenAI API error: ${response.statusCode} ${response.reasonPhrase}');
//       }

//       final decoded = jsonDecode(response.body) as Map<String, dynamic>;
//       final choices = decoded['choices'] as List<dynamic>;
//       final firstChoice = choices.first as Map<String, dynamic>;
//       final message = firstChoice['message'] as Map<String, dynamic>;
//       print("=== Debug: Parsed firstChoice message ===");
//       print(jsonEncode(message));

//       Map<String, dynamic> finalScenarios;
//       String functionNameUsed = 'none';

//       // 6) Handle function_call or direct content
//       if (message.containsKey('function_call')) {
//         final fcall = message['function_call'] as Map<String, dynamic>;
//         functionNameUsed = fcall['name'] as String;
//         final argsString = fcall['arguments'] as String? ?? '';
//         final fargs = jsonDecode(_stripCodeFences(argsString)) as Map<String, dynamic>;
//         print("=== Debug: Detected function_call: $functionNameUsed ===");
//         print("=== Debug: function_call arguments ===");
//         print(jsonEncode(fargs));

//         late List<List<Map<String, dynamic>>> allChangeLists;

//         switch (functionNameUsed) {
//           case 'oneAtATimeSensitivity':
//             final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//             final pm = (fargs['percent'] as num).toDouble();
//             final levelsList = (fargs['levels'] as List<dynamic>?)
//                 ?.cast<num>()
//                 .map((n) => n.toDouble())
//                 .toList();
//             allChangeLists = oneAtATimeSensitivity(
//               baseModel: baseModel,
//               flowNames: fm,
//               percent: pm,
//               levels: levelsList,
//             );
//             break;

//           case 'fullSystemUncertainty':
//             final pm = (fargs['percent'] as num).toDouble();
//             final levelsList = (fargs['levels'] as List<dynamic>?)
//                 ?.cast<num>()
//                 .map((n) => n.toDouble())
//                 .toList();
//             allChangeLists = fullSystemUncertainty(
//               baseModel: baseModel,
//               percent: pm,
//               levels: levelsList,
//             );
//             break;

//           case 'simplexLatticeDesign':
//             final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//             final mm = (fargs['m'] as num).toInt();
//             allChangeLists = simplexLatticeDesign(
//               baseModel: baseModel,
//               flowNames: fm,
//               m: mm,
//             );
//             break;

//           default:
//             throw Exception('Unexpected function name: $functionNameUsed');
//         }

//         print("=== Debug: Computed allChangeLists ===");
//         print(jsonEncode(allChangeLists));

//         // 7) Send the changeLists back to GPT so it can assign scenario names
//         final changeListsJson = jsonEncode({'changeLists': allChangeLists});
//         print("=== Debug: Sending second chat.completions request with changeLists ===");
//         print(changeListsJson);

//         final secondMessages = [
//           {'role': 'system', 'content': systemPrompt},
//           {
//             'role': 'assistant',
//             'content': '',
//             'function_call': {
//               'name': functionNameUsed,
//               'arguments': changeListsJson,
//             }
//           }
//         ];
//         final secondRequest = {
//           'model': 'gpt-4o',
//           'messages': secondMessages,
//         };

//         final secondResponse = await http.post(
//           Uri.parse('https://api.openai.com/v1/chat/completions'),
//           headers: {
//             'Content-Type': 'application/json',
//             'Authorization': 'Bearer $openaiApiKey',
//           },
//           body: jsonEncode(secondRequest),
//         );

//         print("=== Debug: Second response status = ${secondResponse.statusCode} ===");
//         print("=== Debug: Second response body ===");
//         print(secondResponse.body);

//         if (secondResponse.statusCode != 200) {
//           throw Exception(
//             'OpenAI second API error: ${secondResponse.statusCode} ${secondResponse.reasonPhrase}'
//           );
//         }

//         final decoded2 = jsonDecode(secondResponse.body) as Map<String, dynamic>;
//         final choices2 = decoded2['choices'] as List<dynamic>;
//         final firstChoice2 = choices2.first as Map<String, dynamic>;
//         final message2 = firstChoice2['message'] as Map<String, dynamic>;
//         final content2 = message2['content'] as String;
//         print("=== Debug: Parsed secondChoice message content ===");
//         print(content2);
//         finalScenarios = jsonDecode(_stripCodeFences(content2)) as Map<String, dynamic>;
//       } else {
//         // If GPT returned scenarios (with possible renames/additions) directly
//         final content = message['content'] as String? ?? '';
//         print("=== Debug: GPT returned direct scenarios JSON ===");
//         print(content);
//         finalScenarios = jsonDecode(_stripCodeFences(content)) as Map<String, dynamic>;
//       }

//       print("=== Debug: finalScenarios ===");
//       print(jsonEncode(finalScenarios));

//       // 8) Extract raw deltas by scenario
//       final rawByScenario = finalScenarios['scenarios'] as Map<String, dynamic>;
//       final Map<String, List<Map<String, dynamic>>> deltasByScenario = {};
//       rawByScenario.forEach((scenarioName, scenarioValue) {
//         final scenarioMap = scenarioValue as Map<String, dynamic>;
//         final changesList = scenarioMap['changes'] as List<dynamic>;
//         deltasByScenario[scenarioName] = changesList.cast<Map<String, dynamic>>();
//       });
//       print("=== Debug: deltasByScenario ===");
//       print(jsonEncode(deltasByScenario));

//       // 9) Merge with mergeScenarios()
//       //    mergeScenarios handles numeric adjustments + renames + additions
//       print("=== Debug: Calling mergeScenarios(...) ===");
//       final mergedFull = mergeScenarios(baseModel, deltasByScenario);
//       print("=== Debug: mergedFull (before extracting 'scenarios') ===");
//       print(jsonEncode(mergedFull));

//       final scenariosMap = mergedFull['scenarios'] as Map<String, dynamic>;
//       print("=== Debug: scenariosMap ===");
//       print(jsonEncode(scenariosMap));

//       setState(() {
//         _capturedFunctionName = functionNameUsed;
//         _rawDeltasByScenario = deltasByScenario;
//         _mergedScenarios = scenariosMap;
//       });
//     } catch (e, stack) {
//       print("=== Error in _generateAndMergeScenarios ===");
//       print(e);
//       print(stack);
//       // On error, clear results (you might also show a Snackbar or AlertDialog)
//       setState(() {
//         _mergedScenarios = null;
//         _rawDeltasByScenario = null;
//         _capturedFunctionName = null;
//       });
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('LLM Scenario Generator'),
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: _isLoading
//             ? Center(child: CircularProgressIndicator())
//             : (_mergedScenarios == null
//                 ? Center(
//                     child: ElevatedButton(
//                       onPressed: _generateAndMergeScenarios,
//                       child: Text('Generate Scenarios'),
//                     ),
//                   )
//                 : SingleChildScrollView(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         // ——— Summary Table: User Prompt + Function Called ———
//                         SingleChildScrollView(
//                           scrollDirection: Axis.horizontal,
//                           child: DataTable(
//                             columns: const [
//                               DataColumn(label: Text('User Prompt')),
//                               DataColumn(label: Text('Function Called')),
//                             ],
//                             rows: [
//                               DataRow(
//                                 cells: [
//                                   DataCell(
//                                     ConstrainedBox(
//                                       constraints: BoxConstraints(maxWidth: 300),
//                                       child: Text(
//                                         widget.prompt,
//                                         style: TextStyle(fontSize: 14),
//                                       ),
//                                     ),
//                                   ),
//                                   DataCell(
//                                     Text(
//                                       _capturedFunctionName ?? 'none',
//                                       style: TextStyle(fontSize: 14),
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ],
//                           ),
//                         ),
//                         SizedBox(height: 16),

//                         // ——— Detailed Table: Scenario / Process/Flow ID / Field / New Value ———
//                         SingleChildScrollView(
//                           scrollDirection: Axis.horizontal,
//                           child: DataTable(
//                             columns: const [
//                               DataColumn(label: Text('Scenario')),
//                               DataColumn(label: Text('Process/Flow ID')),
//                               DataColumn(label: Text('Field')),
//                               DataColumn(label: Text('New Value')),
//                             ],
//                             rows: _buildChangeRows(),
//                           ),
//                         ),
//                         SizedBox(height: 16),

//                         // ——— Scenario Graphs ———
//                         // We wrap in a fixed-height container so the above tables can scroll first,
//                         // and each graph has its own vertical scroll if it overflows.
//                         SizedBox(
//                           height: 400,
//                           child: ScenarioGraphView(
//                             scenariosMap: _mergedScenarios!,
//                           ),
//                         ),
//                         SizedBox(height: 16),

//                         // Run LCA button (placeholder)
//                         ElevatedButton.icon(
//                           onPressed: () {
//                             // TODO: implement Run LCA logic (e.g. export to Brightway2, run, and show results)
//                           },
//                           icon: Icon(Icons.play_arrow),
//                           label: Text('Run LCA'),
//                         ),
//                       ],
//                     ),
//                   )),
//       ),
//     );
//   }

//   /// Build one DataRow per change in each scenario
//   List<DataRow> _buildChangeRows() {
//     final rows = <DataRow>[];
//     if (_rawDeltasByScenario == null) return rows;

//     _rawDeltasByScenario!.forEach((scenarioName, changes) {
//       if (changes.isEmpty) {
//         rows.add(
//           DataRow(
//             cells: [
//               DataCell(Text(scenarioName)),
//               DataCell(Text('(no changes)', style: TextStyle(fontStyle: FontStyle.italic))),
//               DataCell(Text('-', style: TextStyle(fontStyle: FontStyle.italic))),
//               DataCell(Text('-', style: TextStyle(fontStyle: FontStyle.italic))),
//             ],
//           ),
//         );
//       } else {
//         for (var change in changes) {
//           String idText;
//           if (change.containsKey('process_id')) {
//             idText = change['process_id'] as String;
//           } else if (change.containsKey('flow_id')) {
//             idText = change['flow_id'] as String;
//           } else if (change.containsKey('action')) {
//             // For add_process/add_flow entries, show the action as the “ID” column
//             idText = change['action'] as String;
//           } else {
//             idText = '(unknown)';
//           }

//           final field = change['field']?.toString() ?? '(action)';
//           final newVal = change.containsKey('new_value')
//               ? change['new_value'].toString()
//               : (change.containsKey('process')
//                   ? jsonEncode(change['process'])
//                   : (change.containsKey('flow')
//                       ? jsonEncode(change['flow'])
//                       : '-'));

//           rows.add(
//             DataRow(
//               cells: [
//                 DataCell(Text(scenarioName)),
//                 DataCell(Text(idText)),
//                 DataCell(Text(field)),
//                 DataCell(Text(newVal)),
//               ],
//             ),
//           );
//         }
//       }
//     });

//     return rows;
//   }
// }

// /// Widget that displays each scenario’s graph in a horizontal scroll.
// /// If a single graph is taller than the viewport, it will scroll vertically.
// /// Relies on the merged JSON having full "processes" and "flows" for each scenario.
// class ScenarioGraphView extends StatelessWidget {
//   final Map<String, dynamic> scenariosMap;

//   const ScenarioGraphView({required this.scenariosMap});

//   @override
//   Widget build(BuildContext context) {
//     return SingleChildScrollView(
//       scrollDirection: Axis.horizontal,
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: scenariosMap.entries.map((entry) {
//           final String scenarioName = entry.key;
//           final Map<String, dynamic> model = entry.value['model'] as Map<String, dynamic>;
//           final List<Map<String, dynamic>> processesJson =
//               (model['processes'] as List<dynamic>).cast<Map<String, dynamic>>();
//           final List<Map<String, dynamic>> flowsJson =
//               (model['flows'] as List<dynamic>).cast<Map<String, dynamic>>();

//           // Convert JSON into ProcessNode objects
//           final List<ProcessNode> processes =
//               processesJson.map((j) => ProcessNode.fromJson(j)).toList();

//           // Compute bounding box so the canvas fits all ProcessNodeWidgets
//           double maxX = 0, maxY = 0;
//           for (var node in processes) {
//             final sz = ProcessNodeWidget.sizeFor(node);
//             final double rightEdge = node.position.dx + sz.width;
//             final double bottomEdge = node.position.dy + sz.height;
//             if (rightEdge > maxX) maxX = rightEdge;
//             if (bottomEdge > maxY) maxY = bottomEdge;
//           }
//           // Add padding around the canvas
//           final double canvasWidth = maxX + 20;
//           final double canvasHeight = maxY + 20;

//           return Padding(
//             padding: const EdgeInsets.all(8.0),
//             child: SizedBox(
//               width: canvasWidth + 16, // extra for vertical scrollbars
//               child: SingleChildScrollView(
//                 scrollDirection: Axis.vertical,
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.center,
//                   children: [
//                     Text(
//                       scenarioName,
//                       style: TextStyle(fontWeight: FontWeight.bold),
//                     ),
//                     SizedBox(
//                       width: canvasWidth,
//                       height: canvasHeight,
//                       child: Card(
//                         elevation: 4,
//                         child: Padding(
//                           padding: const EdgeInsets.all(8.0),
//                           child: Stack(
//                             children: [
//                               // Draw connections behind using UndirectedConnectionPainter
//                               CustomPaint(
//                                 size: Size(canvasWidth, canvasHeight),
//                                 painter: UndirectedConnectionPainter(processes, flowsJson),
//                               ),
//                               // Position each process node
//                               for (var node in processes)
//                                 Positioned(
//                                   left: node.position.dx,
//                                   top: node.position.dy,
//                                   child: ProcessNodeWidget(node: node),
//                                 ),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           );
//         }).toList(),
//       ),
//     );
//   }
// }


// // File: lib/zzzz/llm_page.dart
// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;

// import '../api/api_key_delete_later.dart';
// import 'home.dart';               // ProcessNode, FlowValue, ProcessNodeWidget, UndirectedConnectionPainter, etc.
// import 'lca_functions.dart';      // oneAtATimeSensitivity, fullSystemUncertainty, simplexLatticeDesign
// import 'scenario_merger.dart';    // mergeScenarios

// const String openaiApiKey = openAIApiKey;

// /// A page that:
// ///   1) Sends the user’s prompt + baseModel to GPT-4o along with exactly three functions:
// ///      • oneAtATimeSensitivity
// ///      • fullSystemUncertainty
// ///      • simplexLatticeDesign
// ///   2) Displays a small summary table (“User Prompt” + “Function Called”)
// ///   3) Displays a data table listing every scenario & its individual changes
// ///   4) Renders each scenario graph with UndirectedConnectionPainter
// ///
// /// The system prompt is written to be robust: it embeds a strict JSON schema for all allowed
// /// “change” entries (numeric adjustments, renames, additions), includes an explicit “no extra keys”
// /// reminder, and shows short examples. This ensures GPT-4o will produce valid JSON that your
// /// Dart code can parse and merge correctly, even when the user asks for process/flow renaming or creation.
// class LLMPage extends StatefulWidget {
//   final String prompt;
//   final List<ProcessNode> processes;
//   final List<Map<String, dynamic>> flows;

//   const LLMPage({
//     super.key,
//     required this.prompt,
//     required this.processes,
//     required this.flows,
//   });

//   @override
//   State<LLMPage> createState() => _LLMPageState();
// }

// class _LLMPageState extends State<LLMPage> {
//   bool _isLoading = false;

//   /// Merged scenarios returned by mergeScenarios(...)
//   Map<String, dynamic>? _mergedScenarios;

//   /// Raw deltas from GPT: scenarioName -> list of change maps
//   Map<String, List<Map<String, dynamic>>>? _rawDeltasByScenario;

//   /// The name of the function GPT chose to call (or "none" if it returned scenarios directly)
//   String? _capturedFunctionName;

//   /// Strips any ```json code fences from GPT outputs
//   String _stripCodeFences(String input) {
//     final fencePattern = RegExp(r'^```(?:json)?\s*', multiLine: true);
//     final trailingFencePattern = RegExp(r'\s*```$', multiLine: true);
//     var result = input.trim();
//     result = result.replaceAll(fencePattern, '');
//     result = result.replaceAll(trailingFencePattern, '');
//     return result.trim();
//   }

//   Future<void> _generateAndMergeScenarios() async {
//     setState(() {
//       _isLoading = true;
//       _mergedScenarios = null;
//       _rawDeltasByScenario = null;
//       _capturedFunctionName = null;
//     });

//     try {
//       // 1) Build baseModel JSON
//       final baseModel = {
//         'processes': widget.processes.map((p) => p.toJson()).toList(),
//         'flows': widget.flows,
//       };
//       print("=== Debug: baseModel JSON ===");
//       print(jsonEncode(baseModel));

//       // 2) Prepare user payload
//       final userPayload = jsonEncode({
//         'scenario_prompt': widget.prompt,
//         'baseModel': baseModel,
//       });
//       print("=== Debug: userPayload ===");
//       print(userPayload);

//       // 3) Construct system prompt describing the three functions
//       //    and a strict schema for renaming/adding processes/flows
//       final systemPrompt = r'''
// You are an expert LCA scenario generator. 
// You will receive two things:
//   1) "scenario_prompt": a free‐form description from the user
//   2) "baseModel": { "processes": [ … ], "flows": [ … ] }

// Your job:
//   1. Decide if the user wants to:
//      • Run a sensitivity / uncertainty / simplex‐lattice design calculation 
//        via oneAtATimeSensitivity, fullSystemUncertainty, or simplexLatticeDesign,
//      OR
//      • Rename or add new processes or flows (structural edits),
//      OR
//      • A combination of both (e.g., “do a one‐at‐a‐time sensitivity, then rename the glass process to X”).

//   2. Return exactly one JSON object with a single top‐level key: 
//      {
//        "scenarios": {
//          "<scenarioName>": {
//            "changes": [
//              { … change‐descriptor A … },
//              { … change‐descriptor B … },
//              …
//            ]
//          },
//          "<anotherScenario>": { … },
//          …
//        }
//      }

//   3. Do **not** output any text outside of this JSON object (no prose, no markdown).

// Important: Your response must be valid JSON—no extra keys, no comments, no text outside the JSON. 
// Keys not listed below will be removed by the client. If you include any unrecognized key, 
// the client will reject your output.

// **JSON Schema for each “change” entry** (choose exactly one of these forms):

//   A) **Numeric adjustment (inputs/outputs):**

//      {
//        "process_id":   "<existing‐process‐ID‐string>",
//        "field":        "inputs.<flowName>.amount"
//                       OR "outputs.<flowName>.amount",
//        "new_value":    <a numeric value>
//      }

//   B) **Rename an existing process:**

//      {
//        "process_id": "<existing‐process‐ID‐string>",
//        "field":      "name",
//        "new_value":  "<new process name string>"
//      }

//   C) **Rename an existing flow:**

//      {
//        "flow_id":  "<existing‐flow‐ID‐string>",
//        "field":    "name",
//        "new_value":"<new flow name string>"
//      }

//   D) **Add a new process (full ProcessNode JSON must match your app’s `ProcessNode.toJson()` exactly):**

//      {
//        "action":  "add_process",
//        "process": {
//          "id":       "<new‐process‐ID>",
//          "name":     "<new process name>",
//          "position": { "dx": <number>, "dy": <number> },
//          "inputs":   { "<flowName>": { "amount": <number>, "unit": "<unit‐string>" }, … },
//          "outputs":  { "<flowName>": { "amount": <number>, "unit": "<unit‐string>" }, … }
//          // include any other fields exactly as defined in your ProcessNode JSON schema
//        }
//      }

//   E) **Add a new flow:**

//      {
//        "action": "add_flow",
//        "flow": {
//          "id":        "<new‐flow‐ID>",
//          "name":      "<new flow name>",
//          "unit":      "<unit‐string>",
//          "location":  "<location‐string>",
//          "value":     <number>
//          // include any other fields exactly as defined in your Flow JSON schema
//        }
//      }

// **Rules for function calls**:
//   - If you detect that the user’s request requires one of the three built‐in functions (oneAtATimeSensitivity, fullSystemUncertainty, simplexLatticeDesign), reply with exactly:
//     {
//       "function_call": {
//         "name": "<chosenFunctionName>",
//         "arguments": { … }
//       }
//     }
//     where `<chosenFunctionName>` is one of those three. The `arguments` object must match the function’s parameter schema exactly:
//       • oneAtATimeSensitivity:
//         {
//           "flowNames": [ "<flowName1>", … ],
//           "percent":   <number>,
//           "levels":    [ <number>, … ]   // optional
//         }
//       • fullSystemUncertainty:
//         {
//           "percent": <number>,
//           "levels":  [ <number>, … ]   // optional
//         }
//       • simplexLatticeDesign:
//         {
//           "flowNames": [ "<flowName1>", … ],
//           "m":         <integer>
//         }

//   - **Do not include any “scenarios” key in the same message as a function_call.** Once your client sees the function_call, it will compute the numeric change lists and send them back to you for naming.

//   - If the user’s request involves only renames/adds (no numeric scenarios), return the “scenarios” object directly (skip function_call):
//     {
//       "scenarios": {
//         "baseline": {
//           "changes": [
//             { … structural edit 1 … },
//             { … structural edit 2 … },
//             …
//           ]
//         }
//       }
//     }

//   - If the user wants a mix (e.g. “run oneAtATimeSensitivity, then rename glass process”), do **both**:
//     1) Return a function_call for the numeric part.
//     2) In the follow‐up (after receiving numeric results), append your structural “rename” / “add” entries at the end of each scenario’s “changes” list.

// If no edits are required (true baseline), return:
// {
//   "scenarios": {
//     "baseline": {
//       "changes": []
//     }
//   }
// }

// **Short Examples**:

// Example 1 (renaming a process without any numeric changes):

// User: “Please rename the process with ID 'proc_water_glass_01' to 'pultrusion_composite' and add a new flow 'fiber_A' with ID 'flow_fiber_A' (unit: kg, value: 1.0).”

// Output:
// {
//   "scenarios": {
//     "baseline": {
//       "changes": [
//         {
//           "process_id": "proc_water_glass_01",
//           "field":      "name",
//           "new_value":  "pultrusion_composite"
//         },
//         {
//           "action": "add_flow",
//           "flow": {
//             "id":       "flow_fiber_A",
//             "name":     "fiber_A",
//             "unit":     "kg",
//             "location": "CH",
//             "value":    1.0
//           }
//         }
//       ]
//     }
//   }
// }

// Example 2 (oneAtATimeSensitivity on flows ["glass", "energy"], ±10%):

// User: “Run a one-at-a-time sensitivity on flows 'glass' and 'energy' by ±10%.”

// Assistant → function_call:
// {
//   "function_call": {
//     "name": "oneAtATimeSensitivity",
//     "arguments": {
//       "flowNames": ["glass", "energy"],
//       "percent":   10.0
//     }
//   }
// }

// (… your client will compute the ±10% change lists and send them back for scenario naming …)
// ''';

//       // 4) Define the functions metadata for GPT
//       final functions = [
//         {
//           "name": "oneAtATimeSensitivity",
//           "description":
//               "For each flow in flowNames, generate scenarios that vary that flow by ±percent% (or by each level in levels[]) while holding other flows at baseline. Returns a list of change‐lists.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "percent": {"type": "number"},
//               "levels": {
//                 "type": "array",
//                 "items": {"type": "number"}
//               }
//             },
//             "required": ["flowNames", "percent"]
//           }
//         },
//         {
//           "name": "fullSystemUncertainty",
//           "description":
//               "Scale every input and output flow in the entire model by ±percent% (or by each level in levels[]). Returns a list of change‐lists.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "percent": {"type": "number"},
//               "levels": {
//                 "type": "array",
//                 "items": {"type": "number"}
//               }
//             },
//             "required": ["percent"]
//           }
//         },
//         {
//           "name": "simplexLatticeDesign",
//           "description":
//               "Build a {q,m} simplex‐lattice design for the flows listed in flowNames. Each xi ∈ {0, 1/m, 2/m, …, 1} subject to ∑xi=1. Returns a list of change‐lists overriding input flows.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "m": {"type": "integer"}
//             },
//             "required": ["flowNames", "m"]
//           }
//         }
//       ];

//       // 5) Send the first ChatCompletion request
//       final chatRequest = {
//         'model': 'gpt-4o',
//         'messages': [
//           {'role': 'system', 'content': systemPrompt},
//           {'role': 'user', 'content': userPayload},
//         ],
//         'functions': functions,
//         'function_call': 'auto',
//       };
//       print("=== Debug: Sending first chat.completions request ===");
//       print(jsonEncode(chatRequest));

//       final response = await http.post(
//         Uri.parse('https://api.openai.com/v1/chat/completions'),
//         headers: {
//           'Content-Type': 'application/json',
//           'Authorization': 'Bearer $openaiApiKey',
//         },
//         body: jsonEncode(chatRequest),
//       );

//       print("=== Debug: First response status = ${response.statusCode} ===");
//       print("=== Debug: First response body ===");
//       print(response.body);

//       if (response.statusCode != 200) {
//         throw Exception('OpenAI API error: ${response.statusCode} ${response.reasonPhrase}');
//       }

//       final decoded = jsonDecode(response.body) as Map<String, dynamic>;
//       final choices = decoded['choices'] as List<dynamic>;
//       final firstChoice = choices.first as Map<String, dynamic>;
//       final message = firstChoice['message'] as Map<String, dynamic>;
//       print("=== Debug: Parsed firstChoice message ===");
//       print(jsonEncode(message));

//       Map<String, dynamic> finalScenarios;
//       String functionNameUsed = 'none';

//       // 6) Handle function_call or direct content
//       if (message.containsKey('function_call')) {
//         final fcall = message['function_call'] as Map<String, dynamic>;
//         functionNameUsed = fcall['name'] as String;
//         final argsString = fcall['arguments'] as String? ?? '';
//         final fargs = jsonDecode(_stripCodeFences(argsString)) as Map<String, dynamic>;
//         print("=== Debug: Detected function_call: $functionNameUsed ===");
//         print("=== Debug: function_call arguments ===");
//         print(jsonEncode(fargs));

//         late List<List<Map<String, dynamic>>> allChangeLists;

//         switch (functionNameUsed) {
//           case 'oneAtATimeSensitivity':
//             final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//             final pm = (fargs['percent'] as num).toDouble();
//             final levelsList = (fargs['levels'] as List<dynamic>?)
//                 ?.cast<num>()
//                 .map((n) => n.toDouble())
//                 .toList();
//             allChangeLists = oneAtATimeSensitivity(
//               baseModel: baseModel,
//               flowNames: fm,
//               percent: pm,
//               levels: levelsList,
//             );
//             break;

//           case 'fullSystemUncertainty':
//             final pm = (fargs['percent'] as num).toDouble();
//             final levelsList = (fargs['levels'] as List<dynamic>?)
//                 ?.cast<num>()
//                 .map((n) => n.toDouble())
//                 .toList();
//             allChangeLists = fullSystemUncertainty(
//               baseModel: baseModel,
//               percent: pm,
//               levels: levelsList,
//             );
//             break;

//           case 'simplexLatticeDesign':
//             final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//             final mm = (fargs['m'] as num).toInt();
//             allChangeLists = simplexLatticeDesign(
//               baseModel: baseModel,
//               flowNames: fm,
//               m: mm,
//             );
//             break;

//           default:
//             throw Exception('Unexpected function name: $functionNameUsed');
//         }

//         print("=== Debug: Computed allChangeLists ===");
//         print(jsonEncode(allChangeLists));

//         // 7) Send the changeLists back to GPT so it can assign scenario names
//         final changeListsJson = jsonEncode({'changeLists': allChangeLists});
//         print("=== Debug: Sending second chat.completions request with changeLists ===");
//         print(changeListsJson);

//         final secondMessages = [
//           {'role': 'system', 'content': systemPrompt},
//           {
//             'role': 'assistant',
//             'content': '',
//             'function_call': {
//               'name': functionNameUsed,
//               'arguments': changeListsJson,
//             }
//           }
//         ];
//         final secondRequest = {
//           'model': 'gpt-4o',
//           'messages': secondMessages,
//         };

//         final secondResponse = await http.post(
//           Uri.parse('https://api.openai.com/v1/chat/completions'),
//           headers: {
//             'Content-Type': 'application/json',
//             'Authorization': 'Bearer $openaiApiKey',
//           },
//           body: jsonEncode(secondRequest),
//         );

//         print("=== Debug: Second response status = ${secondResponse.statusCode} ===");
//         print("=== Debug: Second response body ===");
//         print(secondResponse.body);

//         if (secondResponse.statusCode != 200) {
//           throw Exception(
//             'OpenAI second API error: ${secondResponse.statusCode} ${secondResponse.reasonPhrase}'
//           );
//         }

//         final decoded2 = jsonDecode(secondResponse.body) as Map<String, dynamic>;
//         final choices2 = decoded2['choices'] as List<dynamic>;
//         final firstChoice2 = choices2.first as Map<String, dynamic>;
//         final message2 = firstChoice2['message'] as Map<String, dynamic>;
//         final content2 = message2['content'] as String;
//         print("=== Debug: Parsed secondChoice message content ===");
//         print(content2);
//         finalScenarios = jsonDecode(_stripCodeFences(content2)) as Map<String, dynamic>;
//       } else {
//         // If GPT returned scenarios (with possible renames/additions) directly
//         final content = message['content'] as String? ?? '';
//         print("=== Debug: GPT returned direct scenarios JSON ===");
//         print(content);
//         finalScenarios = jsonDecode(_stripCodeFences(content)) as Map<String, dynamic>;
//       }

//       print("=== Debug: finalScenarios ===");
//       print(jsonEncode(finalScenarios));

//       // 8) Extract raw deltas by scenario
//       final rawByScenario = finalScenarios['scenarios'] as Map<String, dynamic>;
//       final Map<String, List<Map<String, dynamic>>> deltasByScenario = {};
//       rawByScenario.forEach((scenarioName, scenarioValue) {
//         final scenarioMap = scenarioValue as Map<String, dynamic>;
//         final changesList = scenarioMap['changes'] as List<dynamic>;
//         deltasByScenario[scenarioName] = changesList.cast<Map<String, dynamic>>();
//       });
//       print("=== Debug: deltasByScenario ===");
//       print(jsonEncode(deltasByScenario));

//       // 9) Merge with mergeScenarios()
//       //    mergeScenarios handles numeric adjustments + renames + additions
//       print("=== Debug: Calling mergeScenarios(...) ===");
//       final mergedFull = mergeScenarios(baseModel, deltasByScenario);
//       print("=== Debug: mergedFull (before extracting 'scenarios') ===");
//       print(jsonEncode(mergedFull));

//       final scenariosMap = mergedFull['scenarios'] as Map<String, dynamic>;
//       print("=== Debug: scenariosMap ===");
//       print(jsonEncode(scenariosMap));

//       setState(() {
//         _capturedFunctionName = functionNameUsed;
//         _rawDeltasByScenario = deltasByScenario;
//         _mergedScenarios = scenariosMap;
//       });
//     } catch (e, stack) {
//       print("=== Error in _generateAndMergeScenarios ===");
//       print(e);
//       print(stack);
//       // On error, clear results (you might also show a Snackbar or AlertDialog)
//       setState(() {
//         _mergedScenarios = null;
//         _rawDeltasByScenario = null;
//         _capturedFunctionName = null;
//       });
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('LLM Scenario Generator'),
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: _isLoading
//             ? Center(child: CircularProgressIndicator())
//             : (_mergedScenarios == null
//                 ? Center(
//                     child: ElevatedButton(
//                       onPressed: _generateAndMergeScenarios,
//                       child: Text('Generate Scenarios'),
//                     ),
//                   )
//                 : SingleChildScrollView(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         // ——— Summary Table: User Prompt + Function Called ———
//                         SingleChildScrollView(
//                           scrollDirection: Axis.horizontal,
//                           child: DataTable(
//                             columns: const [
//                               DataColumn(label: Text('User Prompt')),
//                               DataColumn(label: Text('Function Called')),
//                             ],
//                             rows: [
//                               DataRow(
//                                 cells: [
//                                   DataCell(
//                                     ConstrainedBox(
//                                       constraints: BoxConstraints(maxWidth: 300),
//                                       child: Text(
//                                         widget.prompt,
//                                         style: TextStyle(fontSize: 14),
//                                       ),
//                                     ),
//                                   ),
//                                   DataCell(
//                                     Text(
//                                       _capturedFunctionName ?? 'none',
//                                       style: TextStyle(fontSize: 14),
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ],
//                           ),
//                         ),
//                         SizedBox(height: 16),

//                         // ——— Detailed Table: Scenario / Process/Flow ID / Field / New Value ———
//                         SingleChildScrollView(
//                           scrollDirection: Axis.horizontal,
//                           child: DataTable(
//                             columns: const [
//                               DataColumn(label: Text('Scenario')),
//                               DataColumn(label: Text('Process/Flow ID')),
//                               DataColumn(label: Text('Field')),
//                               DataColumn(label: Text('New Value')),
//                             ],
//                             rows: _buildChangeRows(),
//                           ),
//                         ),
//                         SizedBox(height: 16),

//                         // ——— Scenario Graphs ———
//                         // We wrap in a fixed-height container so the above tables can scroll first,
//                         // and each graph has its own vertical scroll if it overflows.
//                         SizedBox(
//                           height: 400,
//                           child: ScenarioGraphView(
//                             scenariosMap: _mergedScenarios!,
//                           ),
//                         ),
//                         SizedBox(height: 16),

//                         // Run LCA button (placeholder)
//                         ElevatedButton.icon(
//                           onPressed: () {
//                             // TODO: implement Run LCA logic (e.g. export to Brightway2, run, and show results)
//                           },
//                           icon: Icon(Icons.play_arrow),
//                           label: Text('Run LCA'),
//                         ),
//                       ],
//                     ),
//                   )),
//       ),
//     );
//   }

//   /// Build one DataRow per change in each scenario
//   List<DataRow> _buildChangeRows() {
//     final rows = <DataRow>[];
//     if (_rawDeltasByScenario == null) return rows;

//     _rawDeltasByScenario!.forEach((scenarioName, changes) {
//       if (changes.isEmpty) {
//         rows.add(
//           DataRow(
//             cells: [
//               DataCell(Text(scenarioName)),
//               DataCell(Text('(no changes)', style: TextStyle(fontStyle: FontStyle.italic))),
//               DataCell(Text('-', style: TextStyle(fontStyle: FontStyle.italic))),
//               DataCell(Text('-', style: TextStyle(fontStyle: FontStyle.italic))),
//             ],
//           ),
//         );
//       } else {
//         for (var change in changes) {
//           String idText;
//           if (change.containsKey('process_id')) {
//             idText = change['process_id'] as String;
//           } else if (change.containsKey('flow_id')) {
//             idText = change['flow_id'] as String;
//           } else if (change.containsKey('action')) {
//             // For add_process/add_flow entries, show the action as the “ID” column
//             idText = change['action'] as String;
//           } else {
//             idText = '(unknown)';
//           }

//           final field = change['field']?.toString() ?? '(action)';
//           final newVal = change.containsKey('new_value')
//               ? change['new_value'].toString()
//               : (change.containsKey('process')
//                   ? jsonEncode(change['process'])
//                   : (change.containsKey('flow')
//                       ? jsonEncode(change['flow'])
//                       : '-'));

//           rows.add(
//             DataRow(
//               cells: [
//                 DataCell(Text(scenarioName)),
//                 DataCell(Text(idText)),
//                 DataCell(Text(field)),
//                 DataCell(Text(newVal)),
//               ],
//             ),
//           );
//         }
//       }
//     });

//     return rows;
//   }
// }

// /// Widget that displays each scenario’s graph in a horizontal scroll.
// /// If a single graph is taller than the viewport, it will scroll vertically.
// /// Relies on the merged JSON having full "processes" and "flows" for each scenario.
// class ScenarioGraphView extends StatelessWidget {
//   final Map<String, dynamic> scenariosMap;

//   const ScenarioGraphView({required this.scenariosMap});

//   @override
//   Widget build(BuildContext context) {
//     return SingleChildScrollView(
//       scrollDirection: Axis.horizontal,
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: scenariosMap.entries.map((entry) {
//           final String scenarioName = entry.key;
//           final Map<String, dynamic> model = entry.value['model'] as Map<String, dynamic>;
//           final List<Map<String, dynamic>> processesJson =
//               (model['processes'] as List<dynamic>).cast<Map<String, dynamic>>();
//           final List<Map<String, dynamic>> flowsJson =
//               (model['flows'] as List<dynamic>).cast<Map<String, dynamic>>();

//           // Convert JSON into ProcessNode objects
//           final List<ProcessNode> processes =
//               processesJson.map((j) => ProcessNode.fromJson(j)).toList();

//           // Compute bounding box so the canvas fits all ProcessNodeWidgets
//           double maxX = 0, maxY = 0;
//           for (var node in processes) {
//             final sz = ProcessNodeWidget.sizeFor(node);
//             final double rightEdge = node.position.dx + sz.width;
//             final double bottomEdge = node.position.dy + sz.height;
//             if (rightEdge > maxX) maxX = rightEdge;
//             if (bottomEdge > maxY) maxY = bottomEdge;
//           }
//           // Add padding around the canvas
//           final double canvasWidth = maxX + 20;
//           final double canvasHeight = maxY + 20;

//           return Padding(
//             padding: const EdgeInsets.all(8.0),
//             child: SizedBox(
//               width: canvasWidth + 16, // extra for vertical scrollbars
//               child: SingleChildScrollView(
//                 scrollDirection: Axis.vertical,
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.center,
//                   children: [
//                     Text(
//                       scenarioName,
//                       style: TextStyle(fontWeight: FontWeight.bold),
//                     ),
//                     SizedBox(
//                       width: canvasWidth,
//                       height: canvasHeight,
//                       child: Card(
//                         elevation: 4,
//                         child: Padding(
//                           padding: const EdgeInsets.all(8.0),
//                           child: Stack(
//                             children: [
//                               // Draw connections behind using UndirectedConnectionPainter
//                               CustomPaint(
//                                 size: Size(canvasWidth, canvasHeight),
//                                 painter: UndirectedConnectionPainter(processes, flowsJson),
//                               ),
//                               // Position each process node
//                               for (var node in processes)
//                                 Positioned(
//                                   left: node.position.dx,
//                                   top: node.position.dy,
//                                   child: ProcessNodeWidget(node: node),
//                                 ),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           );
//         }).toList(),
//       ),
//     );
//   }
// }


// // File: lib/zzzz/llm_page.dart
// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;

// import '../api/api_key_delete_later.dart';
// import 'home.dart';               // ProcessNode, FlowValue, ProcessNodeWidget, UndirectedConnectionPainter, etc.
// import 'lca_functions.dart';      // oneAtATimeSensitivity, fullSystemUncertainty, simplexLatticeDesign
// import 'scenario_merger.dart';    // mergeScenarios

// const String openaiApiKey = openAIApiKey;

// /// A page that:
// ///   1) Sends the user’s prompt + baseModel to GPT-4o along with exactly three functions:
// ///      • oneAtATimeSensitivity
// ///      • fullSystemUncertainty
// ///      • simplexLatticeDesign
// ///   2) Displays a small summary table (“User Prompt” + “Function Called”)
// ///   3) Displays a data table listing every scenario & its individual changes
// ///   4) Renders each scenario graph with UndirectedConnectionPainter
// ///
// /// The system prompt is written to be robust: it embeds a strict JSON schema for all allowed
// /// “change” entries (numeric adjustments, renames, additions), includes an explicit “no extra keys”
// /// reminder, and now also explicitly instructs GPT: “If you introduce a new flow name, first emit an
// /// 'add_flow' entry before any numeric override or rename.”
// ///
// /// Even if GPT forgets, the Dart code below will *also* auto-insert any missing add_flow entries
// /// based on numeric overrides that refer to unknown flows.
// class LLMPage extends StatefulWidget {
//   final String prompt;
//   final List<ProcessNode> processes;
//   final List<Map<String, dynamic>> flows;

//   const LLMPage({
//     super.key,
//     required this.prompt,
//     required this.processes,
//     required this.flows,
//   });

//   @override
//   State<LLMPage> createState() => _LLMPageState();
// }

// class _LLMPageState extends State<LLMPage> {
//   bool _isLoading = false;

//   /// Merged scenarios returned by mergeScenarios(...)
//   Map<String, dynamic>? _mergedScenarios;

//   /// Raw deltas from GPT: scenarioName -> list of change maps
//   Map<String, List<Map<String, dynamic>>>? _rawDeltasByScenario;

//   /// The name of the function GPT chose to call (or "none" if it returned scenarios directly)
//   String? _capturedFunctionName;

//   /// Strips any ```json code fences from GPT outputs
//   String _stripCodeFences(String input) {
//     final fencePattern = RegExp(r'^```(?:json)?\s*', multiLine: true);
//     final trailingFencePattern = RegExp(r'\s*```$', multiLine: true);
//     var result = input.trim();
//     result = result.replaceAll(fencePattern, '');
//     result = result.replaceAll(trailingFencePattern, '');
//     return result.trim();
//   }

//   Future<void> _generateAndMergeScenarios() async {
//     setState(() {
//       _isLoading = true;
//       _mergedScenarios = null;
//       _rawDeltasByScenario = null;
//       _capturedFunctionName = null;
//     });

//     try {
//       // 1) Build baseModel JSON
//       final baseModel = {
//         'processes': widget.processes.map((p) => p.toJson()).toList(),
//         'flows': widget.flows,
//       };
//       print("=== Debug: baseModel JSON ===");
//       print(jsonEncode(baseModel));

//       // 2) Prepare user payload
//       final userPayload = jsonEncode({
//         'scenario_prompt': widget.prompt,
//         'baseModel': baseModel,
//       });
//       print("=== Debug: userPayload ===");
//       print(userPayload);

//       // 3) Construct a stronger system prompt:
//       //    - Emphasize that if GPT “introduces” a new flow by name, it must output an add_flow JSON entry first.
//       //    - Keep the strict JSON schema for renames/adds.
//       final systemPrompt = r'''
// You are an expert LCA scenario generator.
// You will receive two things:
//   1) "scenario_prompt": a free‐form description from the user
//   2) "baseModel": { "processes": [ … ], "flows": [ … ] }

// Your job:
//   1. Decide if the user wants to:
//      • Run a sensitivity / uncertainty / simplex‐lattice design calculation 
//        via oneAtATimeSensitivity, fullSystemUncertainty, or simplexLatticeDesign,
//      OR
//      • Rename or add new processes or flows (structural edits),
//      OR
//      • A combination of both (e.g., “do a one‐at‐a‐time sensitivity, then rename the glass process to X”).

//   2. Whenever you introduce a brand-new flow name (e.g. “cap”, or “aramid”), you MUST
//      first emit an “add_flow” entry in your JSON, before any numeric or rename statements
//      referring to that flow. If you do not, the client will crash. In other words:
//        – If scenario_prompt mentions “add flow cap”, your first change object must be:
//          {
//            "action": "add_flow",
//            "flow": {
//              "id":        "<new-flow-id>",
//              "name":      "cap",
//              "unit":      "<unit-string>",
//              "location":  "<location-string>",
//              "value":     <number>
//            }
//          }
//        – Only then can you specify numeric overrides or renames for “cap”.

//   3. Return exactly one JSON object with a single top-level key:
//      {
//        "scenarios": {
//          "<scenarioName>": {
//            "changes": [
//              { … change-descriptor A … },
//              { … change-descriptor B … },
//              …
//            ]
//          },
//          "<anotherScenario>": { … },
//          …
//        }
//      }

//   4. Do **not** output any text outside of this JSON object (no prose, no markdown).

// Important: Your response must be valid JSON—no extra keys, no comments, no text outside JSON.
// Keys not listed below will be removed by the client. If you include unrecognized keys, the client
// will reject your output.

// **JSON Schema for each “change” entry** (choose exactly one):

//   A) **Numeric adjustment (inputs/outputs):**

//      {
//        "process_id":   "<existing-process-ID-string>",
//        "field":        "inputs.<flowName>.amount"
//                       OR "outputs.<flowName>.amount",
//        "new_value":    <a numeric value>
//      }

//   B) **Rename an existing process:**

//      {
//        "process_id": "<existing-process-ID-string>",
//        "field":      "name",
//        "new_value":  "<new process name string>"
//      }

//   C) **Rename an existing flow:**

//      {
//        "flow_id":  "<existing-flow-ID-string>",
//        "field":    "name",
//        "new_value":"<new flow name string>"
//      }

//   D) **Add a new process** (full ProcessNode JSON must match your app’s ProcessNode.toJson()):

//      {
//        "action":  "add_process",
//        "process": {
//          "id":       "<new-process-ID>",
//          "name":     "<new process name>",
//          "position": { "dx": <number>, "dy": <number> },
//          "inputs":   { "<flowName>": { "amount": <number>, "unit": "<unit-string>" }, … },
//          "outputs":  { "<flowName>": { "amount": <number>, "unit": "<unit-string>" }, … }
//          // include any other fields as defined in your ProcessNode JSON schema
//        }
//      }

//   E) **Add a new flow**:

//      {
//        "action": "add_flow",
//        "flow": {
//          "id":        "<new-flow-ID>",
//          "name":      "<new flow name>",
//          "unit":      "<unit-string>",
//          "location":  "<location-string>",
//          "value":     <number>
//          // include any other fields as defined in your Flow JSON schema
//        }
//      }

// **Rules for function calls**:
//   - If you detect that the user’s request requires one of the three built-in functions
//     (oneAtATimeSensitivity, fullSystemUncertainty, simplexLatticeDesign), reply with exactly:
//     {
//       "function_call": {
//         "name": "<chosenFunctionName>",
//         "arguments": { … }
//       }
//     }
//     – Arguments must match the function’s parameter schema:
//       • oneAtATimeSensitivity:
//         {
//           "flowNames": [ "<flowName1>", … ],
//           "percent":   <number>,
//           "levels":    [ <number>, … ]   // optional
//         }
//       • fullSystemUncertainty:
//         {
//           "percent": <number>,
//           "levels":  [ <number>, … ]   // optional
//         }
//       • simplexLatticeDesign:
//         {
//           "flowNames": [ "<flowName1>", … ],
//           "m":         <integer>
//         }

//   - **Do not include any “scenarios” key in the same message as a function_call.** Once your
//     client sees a function_call, it computes the numeric change lists and sends them back to you
//     for naming.

//   - If the user’s request involves only renames/adds (no numeric scenarios), return the “scenarios”
//     object directly (skip function_call):
//     {
//       "scenarios": {
//         "baseline": {
//           "changes": [
//             { … structural edit 1 … },
//             { … structural edit 2 … },
//             …
//           ]
//         }
//       }
//     }

//   - If the user wants a mix (e.g. “run oneAtATimeSensitivity, then rename glass process”), do **both**:
//     1) Return a function_call for the numeric part.
//     2) In the follow-up (after receiving numeric results), append your structural “rename”/“add” entries
//        at the end of each scenario’s “changes” list.

// If no edits are required (true baseline), return:
// {
//   "scenarios": {
//     "baseline": {
//       "changes": []
//     }
//   }
// }
// ''';

//       // 4) Define the functions metadata for GPT
//       final functions = [
//         {
//           "name": "oneAtATimeSensitivity",
//           "description":
//               "For each flow in flowNames, generate scenarios that vary that flow by ±percent% (or by each level in levels[]) while holding other flows at baseline. Returns a list of change-lists.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "percent": {"type": "number"},
//               "levels": {
//                 "type": "array",
//                 "items": {"type": "number"}
//               }
//             },
//             "required": ["flowNames", "percent"]
//           }
//         },
//         {
//           "name": "fullSystemUncertainty",
//           "description":
//               "Scale every input and output flow in the entire model by ±percent% (or by each level in levels[]). Returns a list of change-lists.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "percent": {"type": "number"},
//               "levels": {
//                 "type": "array",
//                 "items": {"type": "number"}
//               }
//             },
//             "required": ["percent"]
//           }
//         },
//         {
//           "name": "simplexLatticeDesign",
//           "description":
//               "Build a {q,m} simplex-lattice design for the flows listed in flowNames. Each xi ∈ {0, 1/m, 2/m, …, 1} subject to ∑xi=1. Returns a list of change-lists overriding input flows.",
//           "parameters": {
//             "type": "object",
//             "properties": {
//               "flowNames": {
//                 "type": "array",
//                 "items": {"type": "string"}
//               },
//               "m": {"type": "integer"}
//             },
//             "required": ["flowNames", "m"]
//           }
//         }
//       ];

//       // 5) Send the first ChatCompletion request
//       final chatRequest = {
//         'model': 'gpt-4o',
//         'messages': [
//           {'role': 'system', 'content': systemPrompt},
//           {'role': 'user', 'content': userPayload},
//         ],
//         'functions': functions,
//         'function_call': 'auto',
//       };
//       print("=== Debug: Sending first chat.completions request ===");
//       print(jsonEncode(chatRequest));

//       final response = await http.post(
//         Uri.parse('https://api.openai.com/v1/chat/completions'),
//         headers: {
//           'Content-Type': 'application/json',
//           'Authorization': 'Bearer $openaiApiKey',
//         },
//         body: jsonEncode(chatRequest),
//       );

//       print("=== Debug: First response status = ${response.statusCode} ===");
//       print("=== Debug: First response body ===");
//       print(response.body);

//       if (response.statusCode != 200) {
//         throw Exception('OpenAI API error: ${response.statusCode} ${response.reasonPhrase}');
//       }

//       final decoded = jsonDecode(response.body) as Map<String, dynamic>;
//       final choices = decoded['choices'] as List<dynamic>;
//       final firstChoice = choices.first as Map<String, dynamic>;
//       final message = firstChoice['message'] as Map<String, dynamic>;
//       print("=== Debug: Parsed firstChoice message ===");
//       print(jsonEncode(message));

//       Map<String, dynamic> finalScenarios;
//       String functionNameUsed = 'none';

//       // 6) Handle either function_call or direct JSON
//       if (message.containsKey('function_call')) {
//         final fcall = message['function_call'] as Map<String, dynamic>;
//         functionNameUsed = fcall['name'] as String;
//         final argsString = fcall['arguments'] as String? ?? '';
//         final fargs = jsonDecode(_stripCodeFences(argsString)) as Map<String, dynamic>;
//         print("=== Debug: Detected function_call: $functionNameUsed ===");
//         print("=== Debug: function_call arguments ===");
//         print(jsonEncode(fargs));

//         late List<List<Map<String, dynamic>>> allChangeLists;

//         switch (functionNameUsed) {
//           case 'oneAtATimeSensitivity':
//             final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//             final pm = (fargs['percent'] as num).toDouble();
//             final levelsList = (fargs['levels'] as List<dynamic>?)
//                 ?.cast<num>()
//                 .map((n) => n.toDouble())
//                 .toList();
//             allChangeLists = oneAtATimeSensitivity(
//               baseModel: baseModel,
//               flowNames: fm,
//               percent: pm,
//               levels: levelsList,
//             );
//             break;

//           case 'fullSystemUncertainty':
//             final pm = (fargs['percent'] as num).toDouble();
//             final levelsList = (fargs['levels'] as List<dynamic>?)
//                 ?.cast<num>()
//                 .map((n) => n.toDouble())
//                 .toList();
//             allChangeLists = fullSystemUncertainty(
//               baseModel: baseModel,
//               percent: pm,
//               levels: levelsList,
//             );
//             break;

//           case 'simplexLatticeDesign':
//             final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
//             final mm = (fargs['m'] as num).toInt();
//             allChangeLists = simplexLatticeDesign(
//               baseModel: baseModel,
//               flowNames: fm,
//               m: mm,
//             );
//             break;

//           default:
//             throw Exception('Unexpected function name: $functionNameUsed');
//         }

//         print("=== Debug: Computed allChangeLists ===");
//         print(jsonEncode(allChangeLists));

//         // 7) Send the changeLists back to GPT so it can assign scenario names
//         final changeListsJson = jsonEncode({'changeLists': allChangeLists});
//         print("=== Debug: Sending second chat.completions request with changeLists ===");
//         print(changeListsJson);

//         final secondMessages = [
//           {'role': 'system', 'content': systemPrompt},
//           {
//             'role': 'assistant',
//             'content': '',
//             'function_call': {
//               'name': functionNameUsed,
//               'arguments': changeListsJson,
//             }
//           }
//         ];
//         final secondRequest = {
//           'model': 'gpt-4o',
//           'messages': secondMessages,
//         };

//         final secondResponse = await http.post(
//           Uri.parse('https://api.openai.com/v1/chat/completions'),
//           headers: {
//             'Content-Type': 'application/json',
//             'Authorization': 'Bearer $openaiApiKey',
//           },
//           body: jsonEncode(secondRequest),
//         );

//         print("=== Debug: Second response status = ${secondResponse.statusCode} ===");
//         print("=== Debug: Second response body ===");
//         print(secondResponse.body);

//         if (secondResponse.statusCode != 200) {
//           throw Exception(
//             'OpenAI second API error: ${secondResponse.statusCode} ${secondResponse.reasonPhrase}'
//           );
//         }

//         final decoded2 = jsonDecode(secondResponse.body) as Map<String, dynamic>;
//         final choices2 = decoded2['choices'] as List<dynamic>;
//         final firstChoice2 = choices2.first as Map<String, dynamic>;
//         final message2 = firstChoice2['message'] as Map<String, dynamic>;
//         final content2 = message2['content'] as String;
//         print("=== Debug: Parsed secondChoice message content ===");
//         print(content2);
//         finalScenarios = jsonDecode(_stripCodeFences(content2)) as Map<String, dynamic>;
//       } else {
//         // GPT returned “scenarios” JSON directly (no function_call)
//         final content = message['content'] as String? ?? '';
//         print("=== Debug: GPT returned direct scenarios JSON ===");
//         print(content);
//         finalScenarios = jsonDecode(_stripCodeFences(content)) as Map<String, dynamic>;
//       }

//       print("=== Debug: finalScenarios (before auto-add) ===");
//       print(jsonEncode(finalScenarios));

//       // 8) Extract raw deltas by scenario
//       final rawByScenario = finalScenarios['scenarios'] as Map<String, dynamic>;
//       final Map<String, List<Map<String, dynamic>>> deltasByScenario = {};
//       rawByScenario.forEach((scenarioName, scenarioValue) {
//         final scenarioMap = scenarioValue as Map<String, dynamic>;
//         final changesList = scenarioMap['changes'] as List<dynamic>;
//         deltasByScenario[scenarioName] = changesList.cast<Map<String, dynamic>>();
//       });
//       print("=== Debug: raw deltasByScenario ===");
//       print(jsonEncode(deltasByScenario));

//       // ────────────────────────────────────────────────────────────────────────────
//       // 9) AUTO-INJECT MISSING “add_flow” for any override that mentions a flow not already in baseModel.
//       //
//       //    We collect all known flow names (lowercase) from:
//       //      • baseModel['flows']  (each flow has a 'name' field)
//       //      • baseModel['processes'][].outputs[].name
//       //      • any "add_flow" entries that GPT already provided
//       //    Then, if any change has field="inputs.X.amount" or "outputs.X.amount"
//       //    where X is not in knownFlows, we push a default add_flow entry to that scenario.
//       //
//       final Set<String> knownFlowNames = <String>{};
//       //  a) Start with baseModel flows list:
//       for (var f in widget.flows) {
//         final name = (f['name'] as String).toLowerCase();
//         knownFlowNames.add(name);
//       }
//       //  b) Also include every output flow name in each process:
//       for (var p in widget.processes) {
//         for (var fv in p.outputs) {
//           knownFlowNames.add(fv.name.toLowerCase());
//         }
//       }

//       // Helper to insert a default add_flow:
//       Map<String, dynamic> _makeAutoAddFlow(String flowName) {
//         final sanitized = flowName.replaceAll(' ', '_');
//         final newId = 'flow_auto_$sanitized';
//         return {
//           'action': 'add_flow',
//           'flow': {
//             'id': newId,
//             'name': flowName,
//             'unit': 'kg',         // Default unit—adjust as needed
//             'location': 'UNSPECIFIED',
//             'value': 1.0,         // Default “value”
//           }
//         };
//       }

//       deltasByScenario.forEach((scenarioName, changes) {
//         final List<Map<String, dynamic>> toInsert = [];
//         for (var change in changes) {
//           if (change.containsKey('field')) {
//             final field = change['field'] as String;
//             if (field.startsWith('inputs.') || field.startsWith('outputs.')) {
//               final parts = field.split('.');
//               if (parts.length >= 2) {
//                 final flowName = parts[1]; // e.g. "cap" or "pet bottle"
//                 final lc = flowName.toLowerCase();
//                 if (!knownFlowNames.contains(lc)) {
//                   // Insert a default add_flow before any numeric override
//                   toInsert.add(_makeAutoAddFlow(flowName));
//                   knownFlowNames.add(lc);
//                   print(
//                     "    → Auto-injecting add_flow for \"$flowName\" in scenario \"$scenarioName\""
//                   );
//                 }
//               }
//             }
//           }
//         }
//         if (toInsert.isNotEmpty) {
//           // Prepend these adds so they appear before numeric overrides
//           changes.insertAll(0, toInsert);
//         }
//       });
//       print("=== Debug: deltasByScenario (after auto-add) ===");
//       print(jsonEncode(deltasByScenario));

//       // 10) Now call mergeScenarios()—it will see every necessary add_flow first.
//       print("=== Debug: Calling mergeScenarios(...) ===");
//       final mergedFull = mergeScenarios(baseModel, deltasByScenario);
//       print("=== Debug: mergedFull (before extracting 'scenarios') ===");
//       print(jsonEncode(mergedFull));

//       final scenariosMap = mergedFull['scenarios'] as Map<String, dynamic>;
//       print("=== Debug: scenariosMap ===");
//       print(jsonEncode(scenariosMap));

//       setState(() {
//         _capturedFunctionName = functionNameUsed;
//         _rawDeltasByScenario = deltasByScenario;
//         _mergedScenarios = scenariosMap;
//       });
//     } catch (e, stack) {
//       print("=== Error in _generateAndMergeScenarios ===");
//       print(e);
//       print(stack);
//       // On error, clear results (you might also show a Snackbar or AlertDialog)
//       setState(() {
//         _mergedScenarios = null;
//         _rawDeltasByScenario = null;
//         _capturedFunctionName = null;
//       });
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('LLM Scenario Generator'),
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: _isLoading
//             ? Center(child: CircularProgressIndicator())
//             : (_mergedScenarios == null
//                 ? Center(
//                     child: ElevatedButton(
//                       onPressed: _generateAndMergeScenarios,
//                       child: Text('Generate Scenarios'),
//                     ),
//                   )
//                 : SingleChildScrollView(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         // ——— Summary Table: User Prompt + Function Called ———
//                         SingleChildScrollView(
//                           scrollDirection: Axis.horizontal,
//                           child: DataTable(
//                             columns: const [
//                               DataColumn(label: Text('User Prompt')),
//                               DataColumn(label: Text('Function Called')),
//                             ],
//                             rows: [
//                               DataRow(
//                                 cells: [
//                                   DataCell(
//                                     ConstrainedBox(
//                                       constraints: BoxConstraints(maxWidth: 300),
//                                       child: Text(
//                                         widget.prompt,
//                                         style: TextStyle(fontSize: 14),
//                                       ),
//                                     ),
//                                   ),
//                                   DataCell(
//                                     Text(
//                                       _capturedFunctionName ?? 'none',
//                                       style: TextStyle(fontSize: 14),
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ],
//                           ),
//                         ),
//                         SizedBox(height: 16),

//                         // ——— Detailed Table: Scenario / Process/Flow ID / Field / New Value ———
//                         SingleChildScrollView(
//                           scrollDirection: Axis.horizontal,
//                           child: DataTable(
//                             columns: const [
//                               DataColumn(label: Text('Scenario')),
//                               DataColumn(label: Text('Process/Flow ID')),
//                               DataColumn(label: Text('Field')),
//                               DataColumn(label: Text('New Value')),
//                             ],
//                             rows: _buildChangeRows(),
//                           ),
//                         ),
//                         SizedBox(height: 16),

//                         // ——— Scenario Graphs ———
//                         // We wrap in a fixed-height container so the above tables can scroll first,
//                         // and each graph has its own vertical scroll if it overflows.
//                         SizedBox(
//                           height: 400,
//                           child: ScenarioGraphView(
//                             scenariosMap: _mergedScenarios!,
//                           ),
//                         ),
//                         SizedBox(height: 16),

//                         // Run LCA button (placeholder)
//                         ElevatedButton.icon(
//                           onPressed: () {
//                             // TODO: implement Run LCA logic (e.g. export to Brightway2, run, and show results)
//                           },
//                           icon: Icon(Icons.play_arrow),
//                           label: Text('Run LCA'),
//                         ),
//                       ],
//                     ),
//                   )),
//       ),
//     );
//   }

//   /// Build one DataRow per change in each scenario
//   List<DataRow> _buildChangeRows() {
//     final rows = <DataRow>[];
//     if (_rawDeltasByScenario == null) return rows;

//     _rawDeltasByScenario!.forEach((scenarioName, changes) {
//       if (changes.isEmpty) {
//         rows.add(
//           DataRow(
//             cells: [
//               DataCell(Text(scenarioName)),
//               DataCell(Text('(no changes)', style: TextStyle(fontStyle: FontStyle.italic))),
//               DataCell(Text('-', style: TextStyle(fontStyle: FontStyle.italic))),
//               DataCell(Text('-', style: TextStyle(fontStyle: FontStyle.italic))),
//             ],
//           ),
//         );
//       } else {
//         for (var change in changes) {
//           String idText;
//           if (change.containsKey('process_id')) {
//             idText = change['process_id'] as String;
//           } else if (change.containsKey('flow_id')) {
//             idText = change['flow_id'] as String;
//           } else if (change.containsKey('action')) {
//             // For add_process/add_flow entries, show the action as the “ID” column
//             idText = change['action'] as String;
//           } else {
//             idText = '(unknown)';
//           }

//           final field = change['field']?.toString() ?? '(action)';
//           final newVal = change.containsKey('new_value')
//               ? change['new_value'].toString()
//               : (change.containsKey('process')
//                   ? jsonEncode(change['process'])
//                   : (change.containsKey('flow')
//                       ? jsonEncode(change['flow'])
//                       : '-'));

//           rows.add(
//             DataRow(
//               cells: [
//                 DataCell(Text(scenarioName)),
//                 DataCell(Text(idText)),
//                 DataCell(Text(field)),
//                 DataCell(Text(newVal)),
//               ],
//             ),
//           );
//         }
//       }
//     });

//     return rows;
//   }
// }

// /// Widget that displays each scenario’s graph in a horizontal scroll.
// /// If a single graph is taller than the viewport, it will scroll vertically.
// /// Relies on the merged JSON having full "processes" and "flows" for each scenario.
// class ScenarioGraphView extends StatelessWidget {
//   final Map<String, dynamic> scenariosMap;

//   const ScenarioGraphView({required this.scenariosMap});

//   @override
//   Widget build(BuildContext context) {
//     return SingleChildScrollView(
//       scrollDirection: Axis.horizontal,
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: scenariosMap.entries.map((entry) {
//           final String scenarioName = entry.key;
//           final Map<String, dynamic> model = entry.value['model'] as Map<String, dynamic>;
//           final List<Map<String, dynamic>> processesJson =
//               (model['processes'] as List<dynamic>).cast<Map<String, dynamic>>();
//           final List<Map<String, dynamic>> flowsJson =
//               (model['flows'] as List<dynamic>).cast<Map<String, dynamic>>();

//           // Convert JSON into ProcessNode objects
//           final List<ProcessNode> processes =
//               processesJson.map((j) => ProcessNode.fromJson(j)).toList();

//           // Compute bounding box so the canvas fits all ProcessNodeWidgets
//           double maxX = 0, maxY = 0;
//           for (var node in processes) {
//             final sz = ProcessNodeWidget.sizeFor(node);
//             final double rightEdge = node.position.dx + sz.width;
//             final double bottomEdge = node.position.dy + sz.height;
//             if (rightEdge > maxX) maxX = rightEdge;
//             if (bottomEdge > maxY) maxY = bottomEdge;
//           }
//           // Add padding around the canvas
//           final double canvasWidth = maxX + 20;
//           final double canvasHeight = maxY + 20;

//           return Padding(
//             padding: const EdgeInsets.all(8.0),
//             child: SizedBox(
//               width: canvasWidth + 16, // extra for vertical scrollbars
//               child: SingleChildScrollView(
//                 scrollDirection: Axis.vertical,
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.center,
//                   children: [
//                     Text(
//                       scenarioName,
//                       style: TextStyle(fontWeight: FontWeight.bold),
//                     ),
//                     SizedBox(
//                       width: canvasWidth,
//                       height: canvasHeight,
//                       child: Card(
//                         elevation: 4,
//                         child: Padding(
//                           padding: const EdgeInsets.all(8.0),
//                           child: Stack(
//                             children: [
//                               // Draw connections behind using UndirectedConnectionPainter
//                               CustomPaint(
//                                 size: Size(canvasWidth, canvasHeight),
//                                 painter: UndirectedConnectionPainter(processes, flowsJson),
//                               ),
//                               // Position each process node
//                               for (var node in processes)
//                                 Positioned(
//                                   left: node.position.dx,
//                                   top: node.position.dy,
//                                   child: ProcessNodeWidget(node: node),
//                                 ),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           );
//         }).toList(),
//       ),
//     );
//   }
// }


// File: lib/zzzz/llm_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api/api_key_delete_later.dart';
import 'home.dart';               // ProcessNode, FlowValue, ProcessNodeWidget, UndirectedConnectionPainter, etc.
import 'lca_functions.dart';      // oneAtATimeSensitivity, fullSystemUncertainty, simplexLatticeDesign
import 'scenario_merger.dart';    // mergeScenarios

const String openaiApiKey = openAIApiKey;

/// A page that:
///   1) Sends the user’s prompt + baseModel to GPT-4o along with exactly three functions:
///      • oneAtATimeSensitivity
///      • fullSystemUncertainty
///      • simplexLatticeDesign
///   2) Displays a small summary table (“User Prompt” + “Function Called”)
///   3) Displays a data table listing every scenario & its individual changes
///   4) Renders each scenario graph with UndirectedConnectionPainter
///
/// The system prompt now explicitly tells GPT to emit an `add_flow` entry whenever it “introduces”
/// a brand-new flow name.  And after GPT returns its raw deltas, we also “auto-inject” any missing
/// add_flow entries so that `mergeScenarios(...)` never crashes on a numeric override of an unknown flow.
class LLMPage extends StatefulWidget {
  final String prompt;
  final List<ProcessNode> processes;
  final List<Map<String, dynamic>> flows;

  const LLMPage({
    super.key,
    required this.prompt,
    required this.processes,
    required this.flows,
  });

  @override
  State<LLMPage> createState() => _LLMPageState();
}

class _LLMPageState extends State<LLMPage> {
  bool _isLoading = false;

  /// Merged scenarios returned by mergeScenarios(...)
  Map<String, dynamic>? _mergedScenarios;

  /// Raw deltas from GPT: scenarioName -> list of change maps
  Map<String, List<Map<String, dynamic>>>? _rawDeltasByScenario;

  /// The name of the function GPT chose to call (or "none" if it returned scenarios directly)
  String? _capturedFunctionName;

  /// Strips any ```json code fences from GPT outputs
  String _stripCodeFences(String input) {
    final fencePattern = RegExp(r'^```(?:json)?\s*', multiLine: true);
    final trailingFencePattern = RegExp(r'\s*```$', multiLine: true);
    var result = input.trim();
    result = result.replaceAll(fencePattern, '');
    result = result.replaceAll(trailingFencePattern, '');
    return result.trim();
  }

  Future<void> _generateAndMergeScenarios() async {
    setState(() {
      _isLoading = true;
      _mergedScenarios = null;
      _rawDeltasByScenario = null;
      _capturedFunctionName = null;
    });

    try {
      // 1) Build baseModel JSON
      final Map<String, dynamic> baseModel = {
        'processes': widget.processes.map((p) => p.toJson()).toList(),
        'flows': widget.flows,
      };
      print("=== Debug: baseModel JSON ===");
      print(jsonEncode(baseModel));

      // 2) Prepare user payload
      final userPayload = jsonEncode({
        'scenario_prompt': widget.prompt,
        'baseModel': baseModel,
      });
      print("=== Debug: userPayload ===");
      print(userPayload);

      // 3) Construct a stronger system prompt:
      //    - Emphasize that if GPT “introduces” a new flow, it must first emit an add_flow JSON entry.
      //    - Keep the strict JSON schema for renames/adds.
      final systemPrompt = r'''
You are an expert LCA scenario generator.
You will receive two things:
  1) "scenario_prompt": a free‐form description from the user
  2) "baseModel": { "processes": [ … ], "flows": [ … ] }

Your job:
  1. Decide if the user wants to:
     • Run a sensitivity / uncertainty / simplex‐lattice design calculation 
       via oneAtATimeSensitivity, fullSystemUncertainty, or simplexLatticeDesign,
     OR
     • Rename or add new processes or flows (structural edits),
     OR
     • A combination of both (e.g., “do a one‐at‐a‐time sensitivity, then rename the glass process to X”).

  2. Whenever you introduce a brand-new flow name (e.g. “cap” or “aramid”), you MUST
     first emit an “add_flow” entry in your JSON, before any numeric or rename statements
     referring to that flow. In other words:
       – If scenario_prompt mentions “add flow cap”, your first change object must be:
         {
           "action": "add_flow",
           "flow": {
             "id":        "<new-flow-id>",
             "name":      "cap",
             "unit":      "<unit-string>",
             "location":  "<location-string>",
             "value":     <number>
           }
         }
       – Only then can you specify numeric overrides or renames for “cap”.
     If you fail to do so, the client will crash.

  3. Return exactly one JSON object with a single top‐level key:
     {
       "scenarios": {
         "<scenarioName>": {
           "changes": [
             { … change-descriptor A … },
             { … change-descriptor B … },
             …
           ]
         },
         "<anotherScenario>": { … },
         …
       }
     }

  4. Do **not** output any text outside of this JSON object (no prose, no markdown).

Important: Your response must be valid JSON—no extra keys, no comments, no text outside JSON.
Keys not listed below will be removed by the client. If you include unrecognized keys, the client
will reject your output.

**JSON Schema for each “change” entry** (choose exactly one):

  A) **Numeric adjustment (inputs/outputs):**

     {
       "process_id":   "<existing-process-ID-string>",
       "field":        "inputs.<flowName>.amount"
                      OR "outputs.<flowName>.amount",
       "new_value":    <a numeric value>
     }

  B) **Rename an existing process:**

     {
       "process_id": "<existing-process-ID-string>",
       "field":      "name",
       "new_value":  "<new process name string>"
     }

  C) **Rename an existing flow:**

     {
       "flow_id":  "<existing-flow-ID-string>",
       "field":    "name",
       "new_value":"<new flow name string>"
     }

  D) **Add a new process** (full ProcessNode JSON must match your app’s ProcessNode.toJson()):

     {
       "action":  "add_process",
       "process": {
         "id":       "<new-process-ID>",
         "name":     "<new process name>",
         "position": { "dx": <number>, "dy": <number> },
         "inputs":   { "<flowName>": { "amount": <number>, "unit": "<unit-string>" }, … },
         "outputs":  { "<flowName>": { "amount": <number>, "unit": "<unit-string>" }, … }
         // include any other fields as defined in your ProcessNode JSON schema
       }
     }

  E) **Add a new flow**:

     {
       "action": "add_flow",
       "flow": {
         "id":        "<new-flow-ID>",
         "name":      "<new flow name>",
         "unit":      "<unit-string>",
         "location":  "<location-string>",
         "value":     <number>
         // include any other fields as defined in your Flow JSON schema
       }
     }

**Rules for function calls**:
  - If you detect that the user’s request requires one of the three built‐in functions
    (oneAtATimeSensitivity, fullSystemUncertainty, simplexLatticeDesign), reply with exactly:
    {
      "function_call": {
        "name": "<chosenFunctionName>",
        "arguments": { … }
      }
    }
    – Arguments must match the function’s parameter schema exactly:
      • oneAtATimeSensitivity:
        {
          "flowNames": [ "<flowName1>", … ],
          "percent":   <number>,
          "levels":    [ <number>, … ]   // optional
        }
      • fullSystemUncertainty:
        {
          "percent": <number>,
          "levels":  [ <number>, … ]   // optional
        }
      • simplexLatticeDesign:
        {
          "flowNames": [ "<flowName1>", … ],
          "m":         <integer>
        }

  - **Do not include any “scenarios” key in the same message as a function_call.** Once your
    client sees a function_call, it computes the numeric change lists and sends them back to you
    for naming.

  - If the user’s request involves only renames/adds (no numeric scenarios), return the “scenarios”
    object directly (skip function_call):
    {
      "scenarios": {
        "baseline": {
          "changes": [
            { … structural edit 1 … },
            { … structural edit 2 … },
            …
          ]
        }
      }
    }

  - If the user wants a mix (e.g. “run oneAtATimeSensitivity, then rename glass process”), do **both**:
    1) Return a function_call for the numeric part.
    2) In the follow-up (after receiving numeric results), append your structural “rename”/“add” entries
       at the end of each scenario’s “changes” list.

If no edits are required (true baseline), return:
{
  "scenarios": {
    "baseline": {
      "changes": []
    }
  }
}
''';

      // 4) Define the functions metadata for GPT
      final functions = [
        {
          "name": "oneAtATimeSensitivity",
          "description":
              "For each flow in flowNames, generate scenarios that vary that flow by ±percent% (or by each level in levels[]) while holding other flows at baseline. Returns a list of change-lists.",
          "parameters": {
            "type": "object",
            "properties": {
              "flowNames": {
                "type": "array",
                "items": {"type": "string"}
              },
              "percent": {"type": "number"},
              "levels": {
                "type": "array",
                "items": {"type": "number"}
              }
            },
            "required": ["flowNames", "percent"]
          }
        },
        {
          "name": "fullSystemUncertainty",
          "description":
              "Scale every input and output flow in the entire model by ±percent% (or by each level in levels[]). Returns a list of change-lists.",
          "parameters": {
            "type": "object",
            "properties": {
              "percent": {"type": "number"},
              "levels": {
                "type": "array",
                "items": {"type": "number"}
              }
            },
            "required": ["percent"]
          }
        },
        {
          "name": "simplexLatticeDesign",
          "description":
              "Build a {q,m} simplex-lattice design for the flows listed in flowNames. Each xi ∈ {0, 1/m, 2/m, …, 1} subject to ∑xi=1. Returns a list of change-lists overriding input flows.",
          "parameters": {
            "type": "object",
            "properties": {
              "flowNames": {
                "type": "array",
                "items": {"type": "string"}
              },
              "m": {"type": "integer"}
            },
            "required": ["flowNames", "m"]
          }
        }
      ];

      // 5) Send the first ChatCompletion request
      final chatRequest = {
        'model': 'gpt-4o',
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPayload},
        ],
        'functions': functions,
        'function_call': 'auto',
      };
      print("=== Debug: Sending first chat.completions request ===");
      print(jsonEncode(chatRequest));

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $openaiApiKey',
        },
        body: jsonEncode(chatRequest),
      );

      print("=== Debug: First response status = ${response.statusCode} ===");
      print("=== Debug: First response body ===");
      print(response.body);

      if (response.statusCode != 200) {
        throw Exception('OpenAI API error: ${response.statusCode} ${response.reasonPhrase}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List<dynamic>;
      final firstChoice = choices.first as Map<String, dynamic>;
      final message = firstChoice['message'] as Map<String, dynamic>;
      print("=== Debug: Parsed firstChoice message ===");
      print(jsonEncode(message));

      late Map<String, dynamic> finalScenarios;
      String functionNameUsed = 'none';

      // ────────────────────────────────────────────────────────────────────────────────────────────
      // 6) Handle either top-level function_call or parse message['content']
      // ────────────────────────────────────────────────────────────────────────────────────────────

      if (message.containsKey('function_call')) {
        // GPT returned a top-level function_call
        final fcall = message['function_call'] as Map<String, dynamic>;
        functionNameUsed = fcall['name'] as String;
        final argsRaw = fcall['arguments'] as String? ?? '';
        print("=== Debug: Raw arguments string for first function_call ===");
        print(argsRaw);

        final fargs = jsonDecode(argsRaw) as Map<String, dynamic>;
        print("=== Debug: Parsed arguments map ===");
        print(jsonEncode(fargs));

        print("=== Debug: Detected top-level function_call: $functionNameUsed ===");

        // Compute change lists in Dart
        late List<List<Map<String, dynamic>>> allChangeLists;
        switch (functionNameUsed) {
          case 'oneAtATimeSensitivity':
            final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
            final pm = (fargs['percent'] as num).toDouble();
            final levelsList = (fargs['levels'] as List<dynamic>?)
                ?.cast<num>()
                .map((n) => n.toDouble())
                .toList();
            allChangeLists = oneAtATimeSensitivity(
              baseModel: baseModel,
              flowNames: fm,
              percent: pm,
              levels: levelsList,
            );
            break;

          case 'fullSystemUncertainty':
            final pm = (fargs['percent'] as num).toDouble();
            final levelsList = (fargs['levels'] as List<dynamic>?)
                ?.cast<num>()
                .map((n) => n.toDouble())
                .toList();
            allChangeLists = fullSystemUncertainty(
              baseModel: baseModel,
              percent: pm,
              levels: levelsList,
            );
            break;

          case 'simplexLatticeDesign':
            final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
            final mm = (fargs['m'] as num).toInt();
            allChangeLists = simplexLatticeDesign(
              baseModel: baseModel,
              flowNames: fm,
              m: mm,
            );
            break;

          default:
            throw Exception('Unexpected function name: $functionNameUsed');
        }

        print("=== Debug: Computed allChangeLists ===");
        print(jsonEncode(allChangeLists));

        // 7) Send the changeLists back to GPT so it can assign scenario names
        final changeListsJson = jsonEncode({'changeLists': allChangeLists});
        print("=== Debug: Sending second chat.completions request with changeLists ===");
        print(changeListsJson);

        final secondMessages = [
          {'role': 'system', 'content': systemPrompt},
          {
            'role': 'assistant',
            'content': '',
            'function_call': {
              'name': functionNameUsed,
              'arguments': changeListsJson,
            }
          }
        ];
        final secondRequest = {
          'model': 'gpt-4o',
          'messages': secondMessages,
        };

        final secondResponse = await http.post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $openaiApiKey',
          },
          body: jsonEncode(secondRequest),
        );

        print("=== Debug: Second response status = ${secondResponse.statusCode} ===");
        print("=== Debug: Second response body ===");
        print(secondResponse.body);

        if (secondResponse.statusCode != 200) {
          throw Exception(
            'OpenAI second API error: ${secondResponse.statusCode} ${secondResponse.reasonPhrase}'
          );
        }

        final decoded2 = jsonDecode(secondResponse.body) as Map<String, dynamic>;
        final choices2 = decoded2['choices'] as List<dynamic>;
        final firstChoice2 = choices2.first as Map<String, dynamic>;
        final message2 = firstChoice2['message'] as Map<String, dynamic>;

        // If GPT again returns a top-level function_call object here, we print and stop.
        if (message2.containsKey('function_call')) {
          print("=== Debug: SECOND reply also contains function_call ===");
          print(jsonEncode(message2['function_call']));
          throw Exception("GPT returned another function_call instead of scenarios.");
        }

        // Otherwise, we expect message2['content'] to contain the scenarios JSON
        final content2 = message2['content'] as String? ?? '';
        print("=== Debug: Parsed secondChoice message content ===");
        print(content2);
        finalScenarios = jsonDecode(_stripCodeFences(content2)) as Map<String, dynamic>;
      } else {
        // No top-level function_call, so decode message['content']
        final rawContent = message['content'] as String? ?? '';
        print("=== Debug: No top-level function_call. message['content'] ===");
        print(rawContent);
        final strippedContent = _stripCodeFences(rawContent);

        // Now `strippedContent` might contain either:
        //  • a JSON containing {"function_call": …}, or
        //  • the final {"scenarios": …} object.
        final decodedContent = jsonDecode(strippedContent) as Map<String, dynamic>;
        print("=== Debug: Decoded content JSON ===");
        print(jsonEncode(decodedContent));

        if (decodedContent.containsKey('function_call')) {
          // GPT embedded a function_call inside content
          final fcall = decodedContent['function_call'] as Map<String, dynamic>;
          functionNameUsed = fcall['name'] as String;

          final argsRaw = fcall['arguments'] as String? ?? '';
          print("=== Debug: Raw arguments string for embedded function_call ===");
          print(argsRaw);
          final fargs = jsonDecode(argsRaw) as Map<String, dynamic>;
          print("=== Debug: Parsed arguments map ===");
          print(jsonEncode(fargs));
          print("=== Debug: Detected embedded function_call: $functionNameUsed ===");

          // Compute change lists just as above
          late List<List<Map<String, dynamic>>> allChangeLists;
          switch (functionNameUsed) {
            case 'oneAtATimeSensitivity':
              final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
              final pm = (fargs['percent'] as num).toDouble();
              final levelsList = (fargs['levels'] as List<dynamic>?)
                  ?.cast<num>()
                  .map((n) => n.toDouble())
                  .toList();
              allChangeLists = oneAtATimeSensitivity(
                baseModel: baseModel,
                flowNames: fm,
                percent: pm,
                levels: levelsList,
              );
              break;

            case 'fullSystemUncertainty':
              final pm = (fargs['percent'] as num).toDouble();
              final levelsList = (fargs['levels'] as List<dynamic>?)
                  ?.cast<num>()
                  .map((n) => n.toDouble())
                  .toList();
              allChangeLists = fullSystemUncertainty(
                baseModel: baseModel,
                percent: pm,
                levels: levelsList,
              );
              break;

            case 'simplexLatticeDesign':
              final fm = (fargs['flowNames'] as List<dynamic>).cast<String>();
              final mm = (fargs['m'] as num).toInt();
              allChangeLists = simplexLatticeDesign(
                baseModel: baseModel,
                flowNames: fm,
                m: mm,
              );
              break;

            default:
              throw Exception('Unexpected function name: $functionNameUsed');
          }

          print("=== Debug: Computed allChangeLists ===");
          print(jsonEncode(allChangeLists));

          // Send change lists back for naming
          final changeListsJson = jsonEncode({'changeLists': allChangeLists});
          print("=== Debug: Sending second chat.completions request with changeLists ===");
          print(changeListsJson);

          final secondMessages = [
            {'role': 'system', 'content': systemPrompt},
            {
              'role': 'assistant',
              'content': '',
              'function_call': {
                'name': functionNameUsed,
                'arguments': changeListsJson,
              }
            }
          ];
          final secondRequest = {
            'model': 'gpt-4o',
            'messages': secondMessages,
          };

          final secondResponse = await http.post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $openaiApiKey',
            },
            body: jsonEncode(secondRequest),
          );

          print("=== Debug: Second response status = ${secondResponse.statusCode} ===");
          print("=== Debug: Second response body ===");
          print(secondResponse.body);

          if (secondResponse.statusCode != 200) {
            throw Exception(
              'OpenAI second API error: ${secondResponse.statusCode} ${secondResponse.reasonPhrase}'
            );
          }

          final decoded2 = jsonDecode(secondResponse.body) as Map<String, dynamic>;
          final choices2 = decoded2['choices'] as List<dynamic>;
          final firstChoice2 = choices2.first as Map<String, dynamic>;
          final message2 = firstChoice2['message'] as Map<String, dynamic>;

          // If GPT again returns a top-level function_call object here, we print and stop.
          if (message2.containsKey('function_call')) {
            print("=== Debug: SECOND reply also contains function_call ===");
            print(jsonEncode(message2['function_call']));
            throw Exception("GPT returned another function_call instead of scenarios.");
          }

          // Otherwise, we expect message2['content'] to contain the scenarios JSON
          final content2 = message2['content'] as String? ?? '';
          print("=== Debug: Parsed secondChoice message content ===");
          print(content2);
          finalScenarios = jsonDecode(_stripCodeFences(content2)) as Map<String, dynamic>;
        }
        else {
          // GPT returned the final “scenarios” object directly
          print("=== Debug: GPT returned direct scenarios JSON ===");
          print(jsonEncode(decodedContent));
          finalScenarios = decodedContent;
        }
      }

      print("=== Debug: finalScenarios (before auto-add) ===");
      print(jsonEncode(finalScenarios));

      // 8) Extract raw deltas by scenario
      final rawByScenario = finalScenarios['scenarios'] as Map<String, dynamic>;
      final Map<String, List<Map<String, dynamic>>> deltasByScenario = {};
      rawByScenario.forEach((scenarioName, scenarioValue) {
        final scenarioMap = scenarioValue as Map<String, dynamic>;
        final changesList = scenarioMap['changes'] as List<dynamic>;
        deltasByScenario[scenarioName] = changesList.cast<Map<String, dynamic>>();
      });
      print("=== Debug: raw deltasByScenario ===");
      print(jsonEncode(deltasByScenario));

      // ────────────────────────────────────────────────────────────────────────────
      // 9) AUTO-INJECT MISSING “add_flow” for any override that mentions a flow not already in baseModel.
      //
      //    We collect all known flow names (lowercase) from:
      //      • every process’s outputs[].name
      //      • every connection in widget.flows's "names" list
      //      • any "add_flow" entries that GPT already provided
      //    Then, if any change has field="inputs.X.amount" or "outputs.X.amount"
      //    where X is not in knownFlows, we push a default add_flow entry to that scenario.
      //
      final Set<String> knownFlowNames = <String>{};

      //  a) Add all flow names that appear as outputs in any ProcessNode
      for (var p in widget.processes) {
        for (var outp in p.outputs) {
          knownFlowNames.add(outp.name.toLowerCase());
        }
      }

      //  b) Also include any "names" in widget.flows connectivity
      for (var conn in widget.flows) {
        final rawNames = conn['names'] as List<dynamic>;
        for (var nm in rawNames) {
          knownFlowNames.add((nm as String).toLowerCase());
        }
      }

      // Helper to insert a default add_flow:
      Map<String, dynamic> _makeAutoAddFlow(String flowName) {
        final sanitized = flowName.replaceAll(' ', '_');
        final newId = 'flow_auto_$sanitized';
        return {
          'action': 'add_flow',
          'flow': {
            'id': newId,
            'name': flowName,
            'unit': 'kg',         // Default unit—adjust as needed
            'location': 'UNSPECIFIED',
            'value': 1.0,         // Default “value”
          }
        };
      }

      deltasByScenario.forEach((scenarioName, changes) {
        final List<Map<String, dynamic>> toInsert = [];
        for (var change in changes) {
          if (change.containsKey('field')) {
            final field = change['field'] as String;
            if (field.startsWith('inputs.') || field.startsWith('outputs.')) {
              final parts = field.split('.');
              if (parts.length >= 2) {
                final flowName = parts[1]; // e.g. "cap" or "pet bottle"
                final lc = flowName.toLowerCase();
                if (!knownFlowNames.contains(lc)) {
                  // Insert a default add_flow before any numeric override
                  toInsert.add(_makeAutoAddFlow(flowName));
                  knownFlowNames.add(lc);
                  print(
                    "    → Auto-injecting add_flow for \"$flowName\" in scenario \"$scenarioName\""
                  );
                }
              }
            }
          }
        }
        if (toInsert.isNotEmpty) {
          // Prepend these adds so they appear before numeric overrides
          changes.insertAll(0, toInsert);
        }
      });
      print("=== Debug: deltasByScenario (after auto-add) ===");
      print(jsonEncode(deltasByScenario));

      // 10) Now call mergeScenarios()—it will see every necessary add_flow first.
      print("=== Debug: Calling mergeScenarios(...) ===");
      final mergedFull = mergeScenarios(baseModel, deltasByScenario);
      print("=== Debug: mergedFull (before extracting 'scenarios') ===");
      print(jsonEncode(mergedFull));

      final scenariosMap = mergedFull['scenarios'] as Map<String, dynamic>;
      print("=== Debug: scenariosMap ===");
      print(jsonEncode(scenariosMap));

      setState(() {
        _capturedFunctionName = functionNameUsed;
        _rawDeltasByScenario = deltasByScenario;
        _mergedScenarios = scenariosMap;
      });
    } catch (e, stack) {
      print("=== Error in _generateAndMergeScenarios ===");
      print(e);
      print(stack);
      // On error, clear results (you might also show a Snackbar or AlertDialog)
      setState(() {
        _mergedScenarios = null;
        _rawDeltasByScenario = null;
        _capturedFunctionName = null;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('LLM Scenario Generator'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : (_mergedScenarios == null
                ? Center(
                    child: ElevatedButton(
                      onPressed: _generateAndMergeScenarios,
                      child: Text('Generate Scenarios'),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ——— Summary Table: User Prompt + Function Called ———
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('User Prompt')),
                              DataColumn(label: Text('Function Called')),
                            ],
                            rows: [
                              DataRow(
                                cells: [
                                  DataCell(
                                    ConstrainedBox(
                                      constraints: BoxConstraints(maxWidth: 300),
                                      child: Text(
                                        widget.prompt,
                                        style: TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      _capturedFunctionName ?? 'none',
                                      style: TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),

                        // ——— Detailed Table: Scenario / Process/Flow ID / Field / New Value ———
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Scenario')),
                              DataColumn(label: Text('Process/Flow ID')),
                              DataColumn(label: Text('Field')),
                              DataColumn(label: Text('New Value')),
                            ],
                            rows: _buildChangeRows(),
                          ),
                        ),
                        SizedBox(height: 16),

                        // ——— Scenario Graphs ———
                        // We wrap in a fixed-height container so the above tables can scroll first,
                        // and each graph has its own vertical scroll if it overflows.
                        SizedBox(
                          height: 400,
                          child: ScenarioGraphView(
                            scenariosMap: _mergedScenarios!,
                          ),
                        ),
                        SizedBox(height: 16),

                        // Run LCA button (placeholder)
                        ElevatedButton.icon(
                          onPressed: () {
                            // TODO: implement Run LCA logic (e.g. export to Brightway2, run, and show results)
                          },
                          icon: Icon(Icons.play_arrow),
                          label: Text('Run LCA'),
                        ),
                      ],
                    ),
                  )),
      ),
    );
  }

  /// Build one DataRow per change in each scenario
  List<DataRow> _buildChangeRows() {
    final rows = <DataRow>[];
    if (_rawDeltasByScenario == null) return rows;

    _rawDeltasByScenario!.forEach((scenarioName, changes) {
      if (changes.isEmpty) {
        rows.add(
          DataRow(
            cells: [
              DataCell(Text(scenarioName)),
              DataCell(Text('(no changes)', style: TextStyle(fontStyle: FontStyle.italic))),
              DataCell(Text('-', style: TextStyle(fontStyle: FontStyle.italic))),
              DataCell(Text('-', style: TextStyle(fontStyle: FontStyle.italic))),
            ],
          ),
        );
      } else {
        for (var change in changes) {
          String idText;
          if (change.containsKey('process_id')) {
            idText = change['process_id'] as String;
          } else if (change.containsKey('flow_id')) {
            idText = change['flow_id'] as String;
          } else if (change.containsKey('action')) {
            // For add_process/add_flow entries, show the action as the “ID” column
            idText = change['action'] as String;
          } else {
            idText = '(unknown)';
          }

          final field = change['field']?.toString() ?? '(action)';
          final newVal = change.containsKey('new_value')
              ? change['new_value'].toString()
              : (change.containsKey('process')
                  ? jsonEncode(change['process'])
                  : (change.containsKey('flow')
                      ? jsonEncode(change['flow'])
                      : '-'));

          rows.add(
            DataRow(
              cells: [
                DataCell(Text(scenarioName)),
                DataCell(Text(idText)),
                DataCell(Text(field)),
                DataCell(Text(newVal)),
              ],
            ),
          );
        }
      }
    });

    return rows;
  }
}

/// Widget that displays each scenario’s graph in a horizontal scroll.
/// If a single graph is taller than the viewport, it will scroll vertically.
/// Relies on the merged JSON having full "processes" and "flows" for each scenario.
class ScenarioGraphView extends StatelessWidget {
  final Map<String, dynamic> scenariosMap;

  const ScenarioGraphView({required this.scenariosMap});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: scenariosMap.entries.map((entry) {
          final String scenarioName = entry.key;
          final Map<String, dynamic> model = entry.value['model'] as Map<String, dynamic>;
          final List<Map<String, dynamic>> processesJson =
              (model['processes'] as List<dynamic>).cast<Map<String, dynamic>>();
          final List<Map<String, dynamic>> flowsJson =
              (model['flows'] as List<dynamic>).cast<Map<String, dynamic>>();

          // Convert JSON into ProcessNode objects
          final List<ProcessNode> processes =
              processesJson.map((j) => ProcessNode.fromJson(j)).toList();

          // Compute bounding box so the canvas fits all ProcessNodeWidgets
          double maxX = 0, maxY = 0;
          for (var node in processes) {
            final sz = ProcessNodeWidget.sizeFor(node);
            final double rightEdge = node.position.dx + sz.width;
            final double bottomEdge = node.position.dy + sz.height;
            if (rightEdge > maxX) maxX = rightEdge;
            if (bottomEdge > maxY) maxY = bottomEdge;
          }
          // Add padding around the canvas
          final double canvasWidth = maxX + 20;
          final double canvasHeight = maxY + 20;

          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              width: canvasWidth + 16, // extra for vertical scrollbars
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      scenarioName,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(
                      width: canvasWidth,
                      height: canvasHeight,
                      child: Card(
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Stack(
                            children: [
                              // Draw connections behind using UndirectedConnectionPainter
                              CustomPaint(
                                size: Size(canvasWidth, canvasHeight),
                                painter: UndirectedConnectionPainter(processes, flowsJson),
                              ),
                              // Position each process node
                              for (var node in processes)
                                Positioned(
                                  left: node.position.dx,
                                  top: node.position.dy,
                                  child: ProcessNodeWidget(node: node),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
