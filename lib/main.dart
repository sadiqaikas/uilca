import 'package:earlylca/homescreen/home_screen.dart';
import 'package:earlylca/landing.dart';
import 'package:flutter/material.dart';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LCA Input',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const LandingPage(),
    );
  }
}


// // lib/main.dart

// import 'package:flutter/material.dart';
// import 'result/graph_pipeline.dart';

// void main() => runApp(const TestLcaApp());

// class TestLcaApp extends StatelessWidget {
//   const TestLcaApp({Key? key}) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'LCA Pipeline Test',
//       theme: ThemeData(primarySwatch: Colors.lightGreen),
//       home: GraphPipelinePage(initialLcaResult: sampleLcaResult),
//     );
//   }
// }
// final Map<String, dynamic> sampleLcaResult = {
//   // Main content expected under `brightway_result`
//   'brightway_result': {
//     'score': 17.3,
//     'method': ['IPCC 2021', 'Climate Change', 'GWP100'],
//     'emissions_per_process': {
//       'Crude Oil Extraction':       2.1,
//       'Refining':                   1.5,
//       'Monomer Production':         1.2,
//       'Polymerization':             1.6,
//       'Transportation':             3.8,
//       'Injection Molding - Bottle': 2.4,
//       'Injection Molding - Cap':    1.2,
//       'Label Printing':             1.0,
//       'Assembly':                   1.0,
//       'Packaging':                  1.5,
//     },
//   },

//   'process_loop': [
//     {'process': 'Crude Oil Extraction',       'uncertainty': 0.0},
//     {'process': 'Refining',                   'uncertainty': 0.1},
//     {'process': 'Monomer Production',         'uncertainty': 0.1},
//     {'process': 'Polymerization',             'uncertainty': 0.1},
//     {'process': 'Transportation',             'uncertainty': 0.25},
//     {'process': 'Injection Molding - Bottle', 'uncertainty': 0.25},
//     {'process': 'Injection Molding - Cap',    'uncertainty': 0.25},
//     {'process': 'Label Printing',             'uncertainty': 0.5},
//     {'process': 'Assembly',                   'uncertainty': 0.5},
//     {'process': 'Packaging',                  'uncertainty': 0.1},
//   ],

//   'flows_enriched': [
//     {'name': 'Crude Oil',        'from_process': 'Crude Oil Extraction', 'to_process': 'Refining',                   'quantity': 1.0,  'unit': 'kg',   'flow_type': 'material'},
//     {'name': 'Refined Oil',      'from_process': 'Refining',             'to_process': 'Monomer Production',         'quantity': 0.9,  'unit': 'kg',   'flow_type': 'material'},
//     {'name': 'Monomer',          'from_process': 'Monomer Production',   'to_process': 'Polymerization',             'quantity': 0.85, 'unit': 'kg',   'flow_type': 'material'},
//     {'name': 'Polymer',          'from_process': 'Polymerization',       'to_process': 'Transportation',             'quantity': 0.82, 'unit': 'kg',   'flow_type': 'material'},
//     {'name': 'Transported Polymer', 'from_process': 'Transportation',   'to_process': 'Injection Molding - Bottle', 'quantity': 0.75, 'unit': 'kg',   'flow_type': 'material'},
//     {'name': 'Transported Polymer', 'from_process': 'Transportation',   'to_process': 'Injection Molding - Cap',    'quantity': 0.1,  'unit': 'kg',   'flow_type': 'material'},
//     {'name': 'Bottle',           'from_process': 'Injection Molding - Bottle', 'to_process': 'Assembly',             'quantity': 1.0,  'unit': 'unit', 'flow_type': 'material'},
//     {'name': 'Cap',              'from_process': 'Injection Molding - Cap',    'to_process': 'Assembly',             'quantity': 1.0,  'unit': 'unit', 'flow_type': 'material'},
//     {'name': 'Label',            'from_process': 'Label Printing',       'to_process': 'Assembly',                   'quantity': 1.0,  'unit': 'unit', 'flow_type': 'material'},
//     {'name': 'Finished Bottle',  'from_process': 'Assembly',             'to_process': 'Packaging',                  'quantity': 1.0,  'unit': 'unit', 'flow_type': 'material'},
//   ],
// };
